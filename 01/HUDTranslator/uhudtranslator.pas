unit UHUDTranslator;

{ HUD Translator - text translation in the Sci-Fi HUD style (MyMemory API).

  Language bar: SOURCE chip, swap, TARGET chip, TRANSLATE button, status.
  Two text panels with real editors (TMemo, Tahoma for Thai and other
  scripts): source (CLEAR, PASTE) and translation (COPY, quality).
  Language list: click a chip, then a language. History: click a row to
  bring a translation back. Ctrl+Enter translates, Ctrl+Shift+S swaps.
  History is kept in translator_history.txt next to the program. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, LazUTF8, Forms, Controls, StdCtrls, ExtCtrls, Clipbrd, LCLType,
  BGRABitmap, BGRABitmapTypes, HUDCore, HUDHost, HUDPanels, UTranslate;

type

  { TLangBarWidget }

  TLangBarWidget = class(THUDWidget)
  public
    SrcName, DstName, StatusText: string;
    ActiveChip: integer;     // 0 = source, 1 = target (which one the list sets)
    HoverItem, FlashItem: integer;   // 0 src chip, 1 swap, 2 dst chip, 3 translate
    FlashT0: single;
    Busy: boolean;
    function ItemAt(lx, ly: single): integer;
    procedure Flash(i: integer);
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  end;

  { TTextPanelWidget - frame for a memo with HUD buttons along the bottom }

  TTextPanelWidget = class(THUDWidget)
  private
    FTitle: string;
  public
    Buttons: array of string;
    InfoText: string;
    HoverBtn, FlashBtn: integer;
    FlashT0: single;
    Focused_: boolean;
    constructor CreatePanel(const ATitle: string; const AButtons: array of string);
    function ButtonAt(lx, ly: single): integer;
    procedure Flash(i: integer);
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  public
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  end;

  THistoryItem = record
    Src, Dst, SrcText, DstText: string;
    When: TDateTime;
  end;

  { THUDTranslatorWidget }

  THUDTranslatorWidget = class(THUDComposite)
  private
    FSrc, FDst: single;          // language indexes (parameters)
  public
    Bar: TLangBarWidget;
    SrcPanel, DstPanel: TTextPanelWidget;
    History: THUDListWidget;
    Langs: THUDListWidget;
    Items: array of THistoryItem;
    Busy: boolean;
    LastResult: TTranslation;
    PendingText: string;
    OnResult: TNotifyEvent;      // controller fills the target memo
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
    function SrcIndex: integer;
    function DstIndex: integer;
    procedure SetLang(chip, idx: integer);
    procedure Swap;
    procedure Start(const AText: string);
    procedure Received(const R: TTranslation);
    procedure RebuildLangList;
    procedure AddHistory(const ASrcText, ADstText: string);
    procedure SaveHistory;
    procedure LoadHistory;
    function HistoryFile: string;
  protected
    procedure DrawDynamic; override;
  end;

implementation

{ ---------- TLangBarWidget ---------- }

const
  LBW = 1220;
  LBH = 58;
  ChipY0 = 12;
  ChipY1 = 46;
  // item x ranges: source chip, swap, target chip, translate
  ItemX0: array[0..3] of single = (130, 452, 516, 852);
  ItemX1: array[0..3] of single = (440, 504, 826, 1012);

constructor TLangBarWidget.Create;
begin
  inherited Create;
  SetView(LBW, LBH);
  HoverItem := -1;
  FlashItem := -1;
  ActiveChip := 1;
end;

class function TLangBarWidget.UIName: string;
begin
  Result := 'Language Bar';
end;

class function TLangBarWidget.UIDescription: string;
begin
  Result := 'Source and target language chips, swap button, TRANSLATE button and status.';
end;

class function TLangBarWidget.UnitFile: string;
begin
  Result := 'HUDTranslator\uhudtranslator.pas';
end;

function TLangBarWidget.ItemAt(lx, ly: single): integer;
var
  i: integer;
begin
  Result := -1;
  if (ly < ChipY0) or (ly > ChipY1) then Exit;
  for i := 0 to 3 do
    if (lx >= ItemX0[i]) and (lx <= ItemX1[i]) then Exit(i);
end;

procedure TLangBarWidget.Flash(i: integer);
begin
  FlashItem := i;
  FlashT0 := T;
end;

procedure TLangBarWidget.DrawStatic;
var
  i: integer;
  x0, x1: single;
begin
  FillPoly([0, 10, 10, 0, LBW, 0, LBW, LBH - 10, LBW - 10, LBH, 0, LBH], Steel(45));
  Polygon([0, 10, 10, 0, LBW, 0, LBW, LBH - 10, LBW - 10, LBH, 0, LBH], 1.3, Ice(180));
  Line(0, 14, 0, 44, 3, White);
  for i := 0 to 4 do
    Line(LBW - 52 + i * 7, 8, LBW - 45 + i * 7, 1, 2, White(200));
  Txt(16, 29, '\\LANGUAGE', 8, White(230));
  for i := 0 to 3 do
  begin
    x0 := ItemX0[i];
    x1 := ItemX1[i];
    if i = 3 then
      FillPoly([x0 + 6, ChipY0, x1, ChipY0, x1, ChipY1 - 6, x1 - 6, ChipY1, x0, ChipY1, x0, ChipY0 + 6], Ice(170))
    else
      FillPoly([x0 + 6, ChipY0, x1, ChipY0, x1, ChipY1 - 6, x1 - 6, ChipY1, x0, ChipY1, x0, ChipY0 + 6],
        BGRA(14, 30, 50));
    Polygon([x0 + 6, ChipY0, x1, ChipY0, x1, ChipY1 - 6, x1 - 6, ChipY1, x0, ChipY1, x0, ChipY0 + 6], 1.2, Ice(210));
  end;
  Txt(ItemX0[0] + 12, 21, 'FROM', 6, Ice(150));
  Txt(ItemX0[2] + 12, 21, 'TO', 6, Ice(150));
  // swap glyph: two opposite arrows
  Line(462, 24, 494, 24, 1.6, White);
  FillPoly([494, 20, 500, 24, 494, 28], White);
  Line(462, 34, 494, 34, 1.6, White);
  FillPoly([462, 30, 456, 34, 462, 38], White);
  Txt((ItemX0[3] + ItemX1[3]) / 2, 29, 'TRANSLATE', 9, Navy, taCenter);
end;

procedure TLangBarWidget.DrawDynamic;
var
  x0, x1, age: single;
  i: integer;
begin
  TxtCached(ItemX0[0] + 12, 36, SrcName, 9, taLeftJustify);
  TxtCached(ItemX0[2] + 12, 36, DstName, 9, taLeftJustify);
  // the chip the language list currently sets
  x0 := ItemX0[ActiveChip * 2];
  x1 := ItemX1[ActiveChip * 2];
  Polygon([x0 + 6, ChipY0, x1, ChipY0, x1, ChipY1 - 6, x1 - 6, ChipY1, x0, ChipY1, x0, ChipY0 + 6], 2.2, White);
  FillPoly([x1 - 22, 25, x1 - 10, 25, x1 - 16, 32], White);
  for i := 0 to 3 do
    if i = HoverItem then
    begin
      x0 := ItemX0[i];
      x1 := ItemX1[i];
      FillPoly([x0 + 6, ChipY0, x1, ChipY0, x1, ChipY1 - 6, x1 - 6, ChipY1, x0, ChipY1, x0, ChipY0 + 6], White(35));
    end;
  if FlashItem >= 0 then
  begin
    age := T - FlashT0;
    if (age >= 0) and (age < 0.3) then
      Polygon([ItemX0[FlashItem] - 3, ChipY0 - 3, ItemX1[FlashItem] + 3, ChipY0 - 3, ItemX1[FlashItem] + 3,
        ChipY1 + 3, ItemX0[FlashItem] - 3, ChipY1 + 3], 2.5, White(Round(255 * (1 - age / 0.3))));
  end;
  if Busy then
  begin
    Arc(1040, 29, 10, T * 360, T * 360 + 100, 2.5, Ice);
    Arc(1040, 29, 10, T * 360 + 180, T * 360 + 280, 2.5, Ice);
    TxtCached(1058, 29, 'TRANSLATING...', 7.5, taLeftJustify);
  end
  else
    TxtCached(1030, 29, FitText(StatusText, 30), 7, taLeftJustify, Ice(200));
end;

procedure TLangBarWidget.DefineDirty;
begin
  AddDirty(124, 6, LBW - 60, LBH - 6);
end;

procedure TLangBarWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 1220 x 58.');
  L.Add('  FROM chip x 130..440, swap 452..504, TO chip 516..826, TRANSLATE 852..1012 (Ice fill),');
  L.Add('  status at the right (spinning arcs while translating).');
  L.Add('  The white-framed chip is the one the language list sets; click a chip to choose.');
end;

{ ---------- TTextPanelWidget ---------- }

const
  TPW = 600;
  TPH = 430;
  TBtnY0 = 388;
  TBtnY1 = 418;
  TBtnW = 110;

constructor TTextPanelWidget.CreatePanel(const ATitle: string; const AButtons: array of string);
var
  i: integer;
begin
  Create;
  FTitle := ATitle;
  SetLength(Buttons, Length(AButtons));
  for i := 0 to High(AButtons) do Buttons[i] := AButtons[i];
  HoverBtn := -1;
  FlashBtn := -1;
  SetView(TPW, TPH);
end;

class function TTextPanelWidget.UIName: string;
begin
  Result := 'Text Panel';
end;

class function TTextPanelWidget.UIDescription: string;
begin
  Result := 'HUD frame holding a text editor, with buttons and an info line at the bottom.';
end;

class function TTextPanelWidget.UnitFile: string;
begin
  Result := 'HUDTranslator\uhudtranslator.pas';
end;

function TTextPanelWidget.ButtonAt(lx, ly: single): integer;
var
  i: integer;
begin
  Result := -1;
  if (ly < TBtnY0) or (ly > TBtnY1) then Exit;
  for i := 0 to High(Buttons) do
    if (lx >= 16 + i * (TBtnW + 10)) and (lx <= 16 + i * (TBtnW + 10) + TBtnW) then Exit(i);
end;

procedure TTextPanelWidget.Flash(i: integer);
begin
  FlashBtn := i;
  FlashT0 := T;
end;

procedure TTextPanelWidget.DrawStatic;
var
  i: integer;
  x0: single;
begin
  FillPoly([0, 12, 12, 0, 370, 0, 382, 12, TPW, 12, TPW, TPH - 12, TPW - 12, TPH, 0, TPH], Steel(45));
  Polygon([0, 12, 12, 0, 370, 0, 382, 12, TPW, 12, TPW, TPH - 12, TPW - 12, TPH, 0, TPH], 1.3, Ice(180));
  for i := 0 to 4 do
    Line(324 + i * 7, 9, 331 + i * 7, 2, 2, White(200));
  Line(TPW, 30, TPW, 110, 3, White);
  Txt(16, 16, FTitle, 8, White(230));
  // editor well
  FillPoly([14, 30, TPW - 14, 30, TPW - 14, 376, 14, 376], BGRA(14, 30, 50));
  for i := 0 to High(Buttons) do
  begin
    x0 := 16 + i * (TBtnW + 10);
    FillPoly([x0 + 6, TBtnY0, x0 + TBtnW, TBtnY0, x0 + TBtnW, TBtnY1 - 6, x0 + TBtnW - 6, TBtnY1, x0, TBtnY1, x0,
      TBtnY0 + 6], Steel(100));
    Polygon([x0 + 6, TBtnY0, x0 + TBtnW, TBtnY0, x0 + TBtnW, TBtnY1 - 6, x0 + TBtnW - 6, TBtnY1, x0, TBtnY1, x0,
      TBtnY0 + 6], 1.2, Ice(210));
    Txt(x0 + TBtnW / 2, (TBtnY0 + TBtnY1) / 2, Buttons[i], 8, White, taCenter);
  end;
end;

procedure TTextPanelWidget.DrawDynamic;
var
  x0, age: single;
  edge: TBGRAPixel;
begin
  if Focused_ then edge := White else edge := Ice(150);
  Polygon([14, 30, TPW - 14, 30, TPW - 14, 376, 14, 376], 1 + Ord(Focused_), edge);
  if HoverBtn >= 0 then
  begin
    x0 := 16 + HoverBtn * (TBtnW + 10);
    FillPoly([x0 + 6, TBtnY0, x0 + TBtnW, TBtnY0, x0 + TBtnW, TBtnY1 - 6, x0 + TBtnW - 6, TBtnY1, x0, TBtnY1, x0,
      TBtnY0 + 6], White(40));
    Polygon([x0 + 6, TBtnY0, x0 + TBtnW, TBtnY0, x0 + TBtnW, TBtnY1 - 6, x0 + TBtnW - 6, TBtnY1, x0, TBtnY1, x0,
      TBtnY0 + 6], 2, White);
  end;
  if FlashBtn >= 0 then
  begin
    age := T - FlashT0;
    x0 := 16 + FlashBtn * (TBtnW + 10);
    if (age >= 0) and (age < 0.3) then
      Polygon([x0 - 3, TBtnY0 - 3, x0 + TBtnW + 3, TBtnY0 - 3, x0 + TBtnW + 3, TBtnY1 + 3, x0 - 3, TBtnY1 + 3], 2.5,
        White(Round(255 * (1 - age / 0.3))));
  end;
  TxtCached(TPW - 18, (TBtnY0 + TBtnY1) / 2, FitText(InfoText, 44), 7, taRightJustify, Ice(190));
end;

procedure TTextPanelWidget.DefineDirty;
begin
  AddDirty(10, 26, TPW - 8, TPH - 8);
end;

procedure TTextPanelWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
  b: string;
begin
  b := '';
  for i := 0 to High(Buttons) do b += Buttons[i] + ' ';
  L.Add(Format('View %d x %d, title "%s".', [TPW, TPH, FTitle]));
  L.Add('  Editor well (14,30)-(586,376): a TMemo (Tahoma) is placed inside it; the');
  L.Add('  border brightens while it has the focus.');
  L.Add('  Buttons ' + b + '(110 wide from x 16, y 388..418), info line at the right.');
end;

{ ---------- THUDTranslatorWidget ---------- }

constructor THUDTranslatorWidget.Create;
begin
  inherited Create;
  SetView(1240, 800);
  SetParamByName('Max zoom', 2);
  SetParamByName('Glow intensity', 0.8);
  FSrc := LanguageIndex('en');
  FDst := LanguageIndex('th');
  AddParam('Source language', 'Translator', 'Index in the language list (0 = auto detect).', FSrc, 0,
    LanguageCount - 1, 0, False);
  AddParam('Target language', 'Translator', 'Index in the language list (1 and up).', FDst, 1,
    LanguageCount - 1, 0, False);
  Bar := TLangBarWidget.Create;
  AddChild(Bar, 10, 10, 'Language bar');
  SrcPanel := TTextPanelWidget.CreatePanel('\\SOURCE', ['CLEAR', 'PASTE']);
  AddChild(SrcPanel, 10, 78, 'Source text');
  DstPanel := TTextPanelWidget.CreatePanel('\\TRANSLATION', ['COPY', 'USE AS SOURCE']);
  AddChild(DstPanel, 630, 78, 'Translation');
  History := THUDListWidget.CreateList(900, 272, '\\HISTORY');
  History.TextFont := 'Tahoma';   // history rows can be in any script
  History.EmptyText := 'NO TRANSLATIONS YET';
  AddChild(History, 10, 518, 'History');
  Langs := THUDListWidget.CreateList(310, 272, '\\TARGET LANGUAGE');
  AddChild(Langs, 920, 518, 'Language list');
  RebuildLangList;
  LoadHistory;
end;

class function THUDTranslatorWidget.UIName: string;
begin
  Result := 'HUD Translator';
end;

class function THUDTranslatorWidget.UIDescription: string;
begin
  Result := 'Translate text in the HUD style (MyMemory, free, about 5000 characters a day). Choose the ' +
    'languages, type or paste, press TRANSLATE or Ctrl+Enter.';
end;

class function THUDTranslatorWidget.UnitFile: string;
begin
  Result := 'HUDTranslator\uhudtranslator.pas';
end;

function THUDTranslatorWidget.SrcIndex: integer;
begin
  Result := Round(FSrc);
end;

function THUDTranslatorWidget.DstIndex: integer;
begin
  Result := Round(FDst);
end;

procedure THUDTranslatorWidget.RebuildLangList;
var
  i, chip, sel: integer;
begin
  chip := Bar.ActiveChip;
  Langs.Clear;
  for i := 0 to LanguageCount - 1 do
    if (chip = 0) or (i > 0) then    // the target cannot be "auto detect"
      Langs.Add(Language(i).Name, Language(i).Code, 0);
  if chip = 0 then
  begin
    Langs.SetTitle('\\SOURCE LANGUAGE');
    sel := SrcIndex;
  end
  else
  begin
    Langs.SetTitle('\\TARGET LANGUAGE');
    sel := DstIndex - 1;
  end;
  Langs.Selected := sel;
  Langs.EnsureVisible(sel);
end;

procedure THUDTranslatorWidget.SetLang(chip, idx: integer);
begin
  if chip = 0 then SetParamValue(ParamIndex('Source language'), idx)
  else SetParamValue(ParamIndex('Target language'), Max(1, idx));
end;

procedure THUDTranslatorWidget.Swap;
var
  s: single;
begin
  if SrcIndex = 0 then Exit;   // auto detect cannot become a target
  s := FSrc;
  FSrc := FDst;
  FDst := s;
  RebuildLangList;
end;

procedure THUDTranslatorWidget.Start(const AText: string);
begin
  if Busy or (Trim(AText) = '') then Exit;
  if (SrcIndex = DstIndex) then
  begin
    LastResult := Default(TTranslation);
    LastResult.Error := 'Source and target are the same language';
    Exit;
  end;
  Busy := True;
  PendingText := AText;
  TTranslateJob.Start(AText, Language(SrcIndex).Code, Language(DstIndex).Code, @Received);
end;

procedure THUDTranslatorWidget.Received(const R: TTranslation);
begin
  Busy := False;
  LastResult := R;
  if R.OK then AddHistory(PendingText, R.Text);
  if Assigned(OnResult) then OnResult(Self);
end;

procedure THUDTranslatorWidget.AddHistory(const ASrcText, ADstText: string);
var
  n: integer;
begin
  n := Length(Items);
  SetLength(Items, n + 1);
  Items[n].Src := Language(SrcIndex).Code;
  Items[n].Dst := Language(DstIndex).Code;
  Items[n].SrcText := ASrcText;
  Items[n].DstText := ADstText;
  Items[n].When := Now;
  History.Add(StringReplace(ASrcText, LineEnding, ' ', [rfReplaceAll]) + '  →  ' +
    StringReplace(ADstText, LineEnding, ' ', [rfReplaceAll]),
    UpperCase(Items[n].Src + ' > ' + Items[n].Dst) + '  ' + FormatDateTime('hh:nn', Items[n].When), 0);
  History.Selected := History.Count - 1;
  History.EnsureVisible(History.Count - 1);
  SaveHistory;
end;

function THUDTranslatorWidget.HistoryFile: string;
begin
  Result := ExtractFilePath(Application.ExeName) + 'translator_history.txt';
end;

function Esc(const S: string): string;
begin
  // one record per line: tabs and line breaks are escaped
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function Unesc(const S: string): string;
var
  i: integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '\') and (i < Length(S)) then
    begin
      case S[i + 1] of
        't': Result += #9;
        'n': Result += LineEnding;
      else
        Result += S[i + 1];
      end;
      Inc(i, 2);
    end
    else
    begin
      Result += S[i];
      Inc(i);
    end;
  end;
end;

procedure THUDTranslatorWidget.SaveHistory;
var
  L: TStringList;
  i: integer;
begin
  L := TStringList.Create;
  try
    for i := Max(0, Length(Items) - 200) to High(Items) do
      L.Add(FormatDateTime('yyyy-mm-dd hh:nn', Items[i].When) + #9 + Items[i].Src + #9 + Items[i].Dst + #9 +
        Esc(Items[i].SrcText) + #9 + Esc(Items[i].DstText));
    try
      L.SaveToFile(HistoryFile);
    except
      // read-only folder: history is just not kept
    end;
  finally
    L.Free;
  end;
end;

procedure THUDTranslatorWidget.LoadHistory;
var
  L, F: TStringList;
  i, n: integer;
begin
  Items := nil;
  History.Clear;
  if not FileExists(HistoryFile) then Exit;
  L := TStringList.Create;
  F := TStringList.Create;
  try
    L.LoadFromFile(HistoryFile);
    F.StrictDelimiter := True;
    F.Delimiter := #9;
    for i := 0 to L.Count - 1 do
    begin
      F.DelimitedText := L[i];
      if F.Count < 5 then Continue;
      n := Length(Items);
      SetLength(Items, n + 1);
      Items[n].When := StrToDateTimeDef(F[0], Now);
      Items[n].Src := F[1];
      Items[n].Dst := F[2];
      Items[n].SrcText := Unesc(F[3]);
      Items[n].DstText := Unesc(F[4]);
      History.Add(StringReplace(Items[n].SrcText, LineEnding, ' ', [rfReplaceAll]) + '  →  ' +
        StringReplace(Items[n].DstText, LineEnding, ' ', [rfReplaceAll]),
        UpperCase(Items[n].Src + ' > ' + Items[n].Dst), 0);
    end;
    History.EnsureVisible(History.Count - 1);
  finally
    F.Free;
    L.Free;
  end;
end;

procedure THUDTranslatorWidget.DrawDynamic;
begin
  Bar.SrcName := Language(SrcIndex).Name;
  Bar.DstName := Language(DstIndex).Name;
  Bar.Busy := Busy;
  if LastResult.Error <> '' then
    Bar.StatusText := 'ERROR: ' + LastResult.Error
  else if LastResult.OK then
    Bar.StatusText := Format('DONE  ·  MATCH %.0f%%', [LastResult.Match * 100])
  else
    Bar.StatusText := 'MYMEMORY  ·  READY';
  inherited DrawDynamic;
end;

procedure THUDTranslatorWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('Canvas 1240 x 800 design units.');
  L.Add('');
  L.Add('LAYOUT');
  for i := 0 to ChildCount - 1 do
    L.Add(Format('  %-18s %-18s (%4.0f,%4.0f)', [ChildCaption(i), Children[i].ClassName,
      ChildOrigin(i).x, ChildOrigin(i).y]));
  L.Add('');
  L.Add('SERVICE (utranslate.pas)');
  L.Add('  MyMemory: GET api.mymemory.translated.net/get?q=...&langpair=src|dst');
  L.Add('  free, no key; anonymous limit about 5000 characters per day; 500 bytes per');
  L.Add('  request -> text is split at sentence / line / space boundaries (UTF-8 safe)');
  L.Add('  and the translated pieces are joined. MATCH = lowest quality of the pieces.');
  L.Add('  The text is sent to MyMemory; nothing else is.');
  L.Add('  HTTPS via WinINet (shared\hudnet.pas) in a background thread.');
  L.Add('');
  L.Add('HISTORY      translator_history.txt (last 200, tab-separated, escaped)');
  L.Add('KEYS         Ctrl+Enter translate, Ctrl+Shift+S swap, Esc closes when the');
  L.Add('             editors are not focused');
end;

procedure THUDTranslatorWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add('Languages           ' + Language(SrcIndex).Code + ' -> ' + Language(DstIndex).Code);
  L.Add('Busy                ' + BoolToStr(Busy, 'yes', 'no'));
  L.Add(Format('Last result         ok=%s match=%.2f chunks=%d', [BoolToStr(LastResult.OK, 'yes', 'no'),
    LastResult.Match, LastResult.Chunks]));
  if LastResult.Error <> '' then L.Add('Last error          ' + LastResult.Error);
  L.Add(Format('History entries     %d', [Length(Items)]));
end;

{ ---------- controller ---------- }

type
  TTranslatorInput = class(TComponent)
  private
    FForm: THUDHostForm;
    FSrc, FDst: TMemo;
    FOldKeyDown: TKeyEvent;
    function W: THUDTranslatorWidget;
    function Local(px, py: integer; C: THUDWidget; out lx, ly: single): boolean;
    procedure DoTranslate;
    procedure ResultIn(Sender: TObject);
    procedure SrcChange(Sender: TObject);
    procedure Place(Sender: TObject);
    procedure Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

function TTranslatorInput.W: THUDTranslatorWidget;
begin
  Result := FForm.Widget as THUDTranslatorWidget;
end;

function TTranslatorInput.Local(px, py: integer; C: THUDWidget; out lx, ly: single): boolean;
var
  p, o: TPointF;
  i: integer;
begin
  Result := False;
  lx := 0;
  ly := 0;
  p := W.PixelToDesign(px, py);
  for i := 0 to W.ChildCount - 1 do
    if W.Children[i] = C then
    begin
      o := W.ChildOrigin(i);
      lx := p.x - o.x;
      ly := p.y - o.y;
      Exit((lx >= 0) and (ly >= 0) and (lx < C.DesignWidth) and (ly < C.DesignHeight));
    end;
end;

procedure TTranslatorInput.DoTranslate;
begin
  W.Bar.Flash(3);
  W.LastResult := Default(TTranslation);
  W.Start(FSrc.Text);
end;

procedure TTranslatorInput.ResultIn(Sender: TObject);
begin
  if W.LastResult.OK then
  begin
    FDst.Text := W.LastResult.Text;
    W.DstPanel.InfoText := Format('%d CHARS  ·  MATCH %.0f%%', [UTF8Length(FDst.Text), W.LastResult.Match * 100]);
  end;
end;

procedure TTranslatorInput.SrcChange(Sender: TObject);
var
  n: integer;
begin
  n := UTF8Length(FSrc.Text);
  W.SrcPanel.InfoText := Format('%d CHARS  ·  %d BYTES', [n, Length(FSrc.Text)]);
end;

procedure TTranslatorInput.Place(Sender: TObject);
var
  i: integer;
  fh: integer;
begin
  for i := 0 to W.ChildCount - 1 do
    if W.Children[i] = W.SrcPanel then
      PlaceControl(FSrc, W, W.ChildOrigin(i), 22, 36, TPW - 20, 370)
    else if W.Children[i] = W.DstPanel then
      PlaceControl(FDst, W, W.ChildOrigin(i), 22, 36, TPW - 20, 370);
  fh := -Max(11, Round(17 * W.Scale));
  FSrc.Font.Height := fh;
  FDst.Font.Height := fh;
  W.SrcPanel.Focused_ := FSrc.Focused;
  W.DstPanel.Focused_ := FDst.Focused;
end;

procedure TTranslatorInput.Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  lx, ly: single;
begin
  if Local(X, Y, W.Bar, lx, ly) then W.Bar.HoverItem := W.Bar.ItemAt(lx, ly) else W.Bar.HoverItem := -1;
  if Local(X, Y, W.SrcPanel, lx, ly) then W.SrcPanel.HoverBtn := W.SrcPanel.ButtonAt(lx, ly)
  else W.SrcPanel.HoverBtn := -1;
  if Local(X, Y, W.DstPanel, lx, ly) then W.DstPanel.HoverBtn := W.DstPanel.ButtonAt(lx, ly)
  else W.DstPanel.HoverBtn := -1;
  if Local(X, Y, W.History, lx, ly) then W.History.Hover := W.History.RowAt(lx, ly) else W.History.Hover := -1;
  if Local(X, Y, W.Langs, lx, ly) then W.Langs.Hover := W.Langs.RowAt(lx, ly) else W.Langs.Hover := -1;
end;

procedure TTranslatorInput.Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  lx, ly: single;
  i, row: integer;
begin
  FForm.View.SetFocus;
  if Button <> mbLeft then Exit;
  if Local(X, Y, W.Bar, lx, ly) then
  begin
    i := W.Bar.ItemAt(lx, ly);
    if i >= 0 then W.Bar.Flash(i);
    case i of
      0: begin W.Bar.ActiveChip := 0; W.RebuildLangList; end;
      1: W.Swap;
      2: begin W.Bar.ActiveChip := 1; W.RebuildLangList; end;
      3: DoTranslate;
    end;
  end;
  if Local(X, Y, W.SrcPanel, lx, ly) then
  begin
    i := W.SrcPanel.ButtonAt(lx, ly);
    if i >= 0 then W.SrcPanel.Flash(i);
    case i of
      0: begin FSrc.Clear; FDst.Clear; W.DstPanel.InfoText := ''; SrcChange(nil); FSrc.SetFocus; end;
      1: begin FSrc.Text := Clipboard.AsText; SrcChange(nil); FSrc.SetFocus; end;
    end;
  end;
  if Local(X, Y, W.DstPanel, lx, ly) then
  begin
    i := W.DstPanel.ButtonAt(lx, ly);
    if i >= 0 then W.DstPanel.Flash(i);
    case i of
      0: if FDst.Text <> '' then begin Clipboard.AsText := FDst.Text; FForm.SetStatus('Translation copied'); end;
      1: if FDst.Text <> '' then
         begin
           // continue from the translation: it becomes the source, languages swap
           FSrc.Text := FDst.Text;
           FDst.Clear;
           W.DstPanel.InfoText := '';
           SrcChange(nil);
           W.Swap;
         end;
    end;
  end;
  if Local(X, Y, W.Langs, lx, ly) then
  begin
    row := W.Langs.RowAt(lx, ly);
    if row >= 0 then
    begin
      if W.Bar.ActiveChip = 0 then W.SetLang(0, row) else W.SetLang(1, row + 1);
      W.RebuildLangList;
    end;
  end;
  if Local(X, Y, W.History, lx, ly) then
  begin
    row := W.History.RowAt(lx, ly);
    if (row >= 0) and (row <= High(W.Items)) then
    begin
      W.History.Selected := row;
      FSrc.Text := W.Items[row].SrcText;
      FDst.Text := W.Items[row].DstText;
      SrcChange(nil);
      W.DstPanel.InfoText := Format('%d CHARS', [UTF8Length(FDst.Text)]);
      if LanguageIndex(W.Items[row].Src) >= 0 then W.SetLang(0, LanguageIndex(W.Items[row].Src));
      if LanguageIndex(W.Items[row].Dst) >= 1 then W.SetLang(1, LanguageIndex(W.Items[row].Dst));
      W.RebuildLangList;
    end;
  end;
end;

procedure TTranslatorInput.Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  lx, ly: single;
begin
  if Local(MousePos.X, MousePos.Y, W.History, lx, ly) then
  begin
    W.History.ScrollBy(-Sign(WheelDelta) * 3);
    Handled := True;
  end
  else if Local(MousePos.X, MousePos.Y, W.Langs, lx, ly) then
  begin
    W.Langs.ScrollBy(-Sign(WheelDelta) * 3);
    Handled := True;
  end;
end;

procedure TTranslatorInput.KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (ssCtrl in Shift) and (Key = VK_RETURN) then
  begin
    DoTranslate;
    Key := 0;
    Exit;
  end;
  if (ssCtrl in Shift) and (ssShift in Shift) and (Key = VK_S) then
  begin
    W.Swap;
    Key := 0;
    Exit;
  end;
  if Assigned(FOldKeyDown) then FOldKeyDown(Sender, Key, Shift);
end;

procedure SetupTranslator(AForm: THUDHostForm);
var
  inp: TTranslatorInput;
  i: integer;

  function MakeMemo(ro: boolean): TMemo;
  begin
    Result := TMemo.Create(AForm);
    Result.Parent := AForm.View;
    StyleControl(Result);
    Result.Font.Name := 'Tahoma';     // Thai, Cyrillic, Greek, Arabic, Hebrew...
    Result.ScrollBars := ssAutoVertical;
    Result.WordWrap := True;
    Result.ReadOnly := ro;
  end;

begin
  if not (AForm.Widget is THUDTranslatorWidget) then Exit;
  inp := TTranslatorInput.Create(AForm);
  inp.FForm := AForm;
  inp.FSrc := MakeMemo(False);
  inp.FDst := MakeMemo(True);
  inp.FSrc.OnChange := @inp.SrcChange;
  (AForm.Widget as THUDTranslatorWidget).OnResult := @inp.ResultIn;
  AForm.View.OnAfterPaint := @inp.Place;
  AForm.View.OnMouseMove := @inp.Move;
  AForm.View.OnMouseDown := @inp.Down;
  AForm.View.OnMouseWheel := @inp.Wheel;
  inp.FOldKeyDown := AForm.OnKeyDown;
  AForm.OnKeyDown := @inp.KeyDown;
  AForm.SetStatus('Ctrl+Enter: translate   Ctrl+Shift+S: swap   Click a chip, then a language   ' +
    'Translation by MyMemory (text is sent to mymemory.translated.net)');
  inp.SrcChange(nil);
  // HUDTranslator.exe --text "Hello" [--from en] [--to th] : translate at start
  // (synchronous with --shot / --info, so one-frame renders include the result)
  for i := 1 to ParamCount - 1 do
    if ParamStr(i) = '--from' then (AForm.Widget as THUDTranslatorWidget).SetLang(0, Max(0, LanguageIndex(ParamStr(i + 1))))
    else if ParamStr(i) = '--to' then (AForm.Widget as THUDTranslatorWidget).SetLang(1, Max(1, LanguageIndex(ParamStr(i + 1))));
  (AForm.Widget as THUDTranslatorWidget).RebuildLangList;
  for i := 1 to ParamCount - 1 do
    if ParamStr(i) = '--text' then
    begin
      inp.FSrc.Text := ParamStr(i + 1);
      inp.SrcChange(nil);
      with AForm.Widget as THUDTranslatorWidget do
        if (ParamStr(1) = '--shot') or (ParamStr(1) = '--info') then
        begin
          PendingText := ParamStr(i + 1);
          try
            Received(TranslateText(PendingText, Language(SrcIndex).Code, Language(DstIndex).Code));
          except
            on E: Exception do
            begin
              LastResult := Default(TTranslation);
              LastResult.Error := E.Message;
            end;
          end;
        end
        else
          inp.DoTranslate;
    end;
end;

initialization
  HostSetupProc := @SetupTranslator;

end.
