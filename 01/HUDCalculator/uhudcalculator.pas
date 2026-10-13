unit UHUDCalculator;

{ HUD Calculator - scientific calculator in the Sci-Fi HUD style.

  Display (expression, result, memory / angle / ANS indicators),
  keypad of HUD buttons (scientific block + standard block), history list and
  a status panel. Parsing and maths are in ucalcengine.pas.

  Keyboard (view focused): digits . + - * / ^ ( ) % !  Enter or = evaluate,
  Backspace delete, Delete or Esc clear (Esc on an empty display closes),
  Ctrl+C copy result, Ctrl+V paste an expression, D toggles DEG/RAD,
  P inserts pi. Mouse: click keys; click a history line to reload it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, LazUTF8, Forms, Controls, StdCtrls, ExtCtrls, Clipbrd, LCLType,
  BGRABitmap, BGRABitmapTypes, HUDCore, HUDHost, HUDPanels, UHexCore, UCalcEngine;

type
  TKeyKind = (kkNum, kkOp, kkFunc, kkMem, kkClear, kkEquals);

  TCalcKey = record
    Caption: string;
    Action: string;      // text inserted, or a command starting with '#'
    Kind: TKeyKind;
    Col, Row, ColSpan, RowSpan: integer;
  end;

  { TCalcDisplayWidget }

  TCalcDisplayWidget = class(THUDWidget)
  public
    ExprText, ResultText, ErrorText, AngleText, AnsText: string;
    MemoryOn, Fresh: boolean;   // Fresh = result just computed
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

  { TKeypadWidget }

  TKeypadWidget = class(THUDWidget)
  public
    HoverKey, FlashKey: integer;
    FlashT0: single;
    AngleCaption: string;
    function KeyRect(i: integer; out x1, y1, x2, y2: single): boolean;
    function KeyAt(lx, ly: single): integer;
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

  { TCalcStatusWidget }

  TCalcStatusWidget = class(THUDWidget)
  public
    Lines_: TStringList;
    constructor Create; override;
    destructor Destroy; override;
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

  { THUDCalculatorWidget }

  THUDCalculatorWidget = class(THUDComposite)
  private
    FDegrees: single;
    FHistExpr: TStringList;      // history: expression of each list row
  public
    Engine: TCalcEngine;
    Expression: string;          // internal form (ASCII operators, "π")
    LastResult, Memory: double;
    JustEvaluated: boolean;
    LastError: string;
    Display: TCalcDisplayWidget;
    Keypad: TKeypadWidget;
    History: THUDListWidget;
    Status: TCalcStatusWidget;
    Core: THexCoreWidget;
    constructor Create; override;
    destructor Destroy; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
    procedure Press(const Action: string);
    procedure Evaluate;
    procedure LoadHistory(row: integer);
    procedure PasteText(const S: string);
  protected
    procedure DrawDynamic; override;
  end;

function DisplayForm(const S: string): string;
function KeyCount: integer;
function KeyDef(i: integer): TCalcKey;

implementation

const
  Keys: array[0..47] of TCalcKey = (
    // scientific block: columns 0..2
    (Caption: 'sin';  Action: 'sin(';   Kind: kkFunc; Col: 0; Row: 0; ColSpan: 1; RowSpan: 1),
    (Caption: 'cos';  Action: 'cos(';   Kind: kkFunc; Col: 1; Row: 0; ColSpan: 1; RowSpan: 1),
    (Caption: 'tan';  Action: 'tan(';   Kind: kkFunc; Col: 2; Row: 0; ColSpan: 1; RowSpan: 1),
    (Caption: 'asin'; Action: 'asin(';  Kind: kkFunc; Col: 0; Row: 1; ColSpan: 1; RowSpan: 1),
    (Caption: 'acos'; Action: 'acos(';  Kind: kkFunc; Col: 1; Row: 1; ColSpan: 1; RowSpan: 1),
    (Caption: 'atan'; Action: 'atan(';  Kind: kkFunc; Col: 2; Row: 1; ColSpan: 1; RowSpan: 1),
    (Caption: 'ln';   Action: 'ln(';    Kind: kkFunc; Col: 0; Row: 2; ColSpan: 1; RowSpan: 1),
    (Caption: 'log';  Action: 'log(';   Kind: kkFunc; Col: 1; Row: 2; ColSpan: 1; RowSpan: 1),
    (Caption: 'eˣ';   Action: 'exp(';   Kind: kkFunc; Col: 2; Row: 2; ColSpan: 1; RowSpan: 1),
    (Caption: 'x²';   Action: '^2';     Kind: kkFunc; Col: 0; Row: 3; ColSpan: 1; RowSpan: 1),
    (Caption: '√';    Action: 'sqrt(';  Kind: kkFunc; Col: 1; Row: 3; ColSpan: 1; RowSpan: 1),
    (Caption: 'xʸ';   Action: '^';      Kind: kkFunc; Col: 2; Row: 3; ColSpan: 1; RowSpan: 1),
    (Caption: 'n!';   Action: '!';      Kind: kkFunc; Col: 0; Row: 4; ColSpan: 1; RowSpan: 1),
    (Caption: '1/x';  Action: '^(-1)';  Kind: kkFunc; Col: 1; Row: 4; ColSpan: 1; RowSpan: 1),
    (Caption: '|x|';  Action: 'abs(';   Kind: kkFunc; Col: 2; Row: 4; ColSpan: 1; RowSpan: 1),
    (Caption: 'π';    Action: 'π';      Kind: kkFunc; Col: 0; Row: 5; ColSpan: 1; RowSpan: 1),
    (Caption: 'e';    Action: 'e';      Kind: kkFunc; Col: 1; Row: 5; ColSpan: 1; RowSpan: 1),
    (Caption: 'ANS';  Action: 'ans';    Kind: kkFunc; Col: 2; Row: 5; ColSpan: 1; RowSpan: 1),
    // standard block: columns 3..7
    (Caption: 'MC';   Action: '#mc';    Kind: kkMem;  Col: 3; Row: 0; ColSpan: 1; RowSpan: 1),
    (Caption: 'MR';   Action: '#mr';    Kind: kkMem;  Col: 4; Row: 0; ColSpan: 1; RowSpan: 1),
    (Caption: 'M+';   Action: '#m+';    Kind: kkMem;  Col: 5; Row: 0; ColSpan: 1; RowSpan: 1),
    (Caption: 'M-';   Action: '#m-';    Kind: kkMem;  Col: 6; Row: 0; ColSpan: 1; RowSpan: 1),
    (Caption: '';     Action: '#angle'; Kind: kkMem;  Col: 7; Row: 0; ColSpan: 1; RowSpan: 1),
    (Caption: 'AC';   Action: '#ac';    Kind: kkClear; Col: 3; Row: 1; ColSpan: 1; RowSpan: 1),
    (Caption: '⌫';    Action: '#back';  Kind: kkClear; Col: 4; Row: 1; ColSpan: 1; RowSpan: 1),
    (Caption: '(';    Action: '(';      Kind: kkOp;   Col: 5; Row: 1; ColSpan: 1; RowSpan: 1),
    (Caption: ')';    Action: ')';      Kind: kkOp;   Col: 6; Row: 1; ColSpan: 1; RowSpan: 1),
    (Caption: '%';    Action: '%';      Kind: kkOp;   Col: 7; Row: 1; ColSpan: 1; RowSpan: 1),
    (Caption: '7';    Action: '7';      Kind: kkNum;  Col: 3; Row: 2; ColSpan: 1; RowSpan: 1),
    (Caption: '8';    Action: '8';      Kind: kkNum;  Col: 4; Row: 2; ColSpan: 1; RowSpan: 1),
    (Caption: '9';    Action: '9';      Kind: kkNum;  Col: 5; Row: 2; ColSpan: 1; RowSpan: 1),
    (Caption: '÷';    Action: '/';      Kind: kkOp;   Col: 6; Row: 2; ColSpan: 1; RowSpan: 1),
    (Caption: 'EXP';  Action: 'e';      Kind: kkOp;   Col: 7; Row: 2; ColSpan: 1; RowSpan: 1),
    (Caption: '4';    Action: '4';      Kind: kkNum;  Col: 3; Row: 3; ColSpan: 1; RowSpan: 1),
    (Caption: '5';    Action: '5';      Kind: kkNum;  Col: 4; Row: 3; ColSpan: 1; RowSpan: 1),
    (Caption: '6';    Action: '6';      Kind: kkNum;  Col: 5; Row: 3; ColSpan: 1; RowSpan: 1),
    (Caption: '×';    Action: '*';      Kind: kkOp;   Col: 6; Row: 3; ColSpan: 1; RowSpan: 1),
    (Caption: '1';    Action: '1';      Kind: kkNum;  Col: 3; Row: 4; ColSpan: 1; RowSpan: 1),
    (Caption: '2';    Action: '2';      Kind: kkNum;  Col: 4; Row: 4; ColSpan: 1; RowSpan: 1),
    (Caption: '3';    Action: '3';      Kind: kkNum;  Col: 5; Row: 4; ColSpan: 1; RowSpan: 1),
    (Caption: '-';    Action: '-';      Kind: kkOp;   Col: 6; Row: 4; ColSpan: 1; RowSpan: 1),
    (Caption: '0';    Action: '0';      Kind: kkNum;  Col: 3; Row: 5; ColSpan: 1; RowSpan: 1),
    (Caption: '.';    Action: '.';      Kind: kkNum;  Col: 4; Row: 5; ColSpan: 1; RowSpan: 1),
    (Caption: '±';    Action: '#neg';   Kind: kkNum;  Col: 5; Row: 5; ColSpan: 1; RowSpan: 1),
    (Caption: '+';    Action: '+';      Kind: kkOp;   Col: 6; Row: 5; ColSpan: 1; RowSpan: 1),
    (Caption: '=';    Action: '#eval';  Kind: kkEquals; Col: 7; Row: 3; ColSpan: 1; RowSpan: 3),
    // spare slots kept for future keys (not drawn)
    (Caption: '';     Action: '';       Kind: kkNum;  Col: -1; Row: -1; ColSpan: 0; RowSpan: 0),
    (Caption: '';     Action: '';       Kind: kkNum;  Col: -1; Row: -1; ColSpan: 0; RowSpan: 0));

  KPadX = 20;      // keypad grid inside the keypad widget
  KPadY = 34;
  KCellW = 88;
  KCellH = 64;
  KGap = 8;

function KeyCount: integer;
begin
  Result := Length(Keys);
end;

function KeyDef(i: integer): TCalcKey;
begin
  Result := Keys[i];
end;

function DisplayForm(const S: string): string;
begin
  // internal ASCII -> display glyphs
  Result := StringReplace(S, '*', '×', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '÷', [rfReplaceAll]);
  Result := StringReplace(Result, 'sqrt(', '√(', [rfReplaceAll]);
  Result := StringReplace(Result, 'ans', 'ANS', [rfReplaceAll]);
end;

{ ---------- TCalcDisplayWidget ---------- }

const
  DW = 740;
  DH = 190;

constructor TCalcDisplayWidget.Create;
begin
  inherited Create;
  SetView(DW, DH);
end;

class function TCalcDisplayWidget.UIName: string;
begin
  Result := 'Calculator Display';
end;

class function TCalcDisplayWidget.UIDescription: string;
begin
  Result := 'Expression, result (or error), memory / angle / ANS indicators.';
end;

class function TCalcDisplayWidget.UnitFile: string;
begin
  Result := 'HUDCalculator\uhudcalculator.pas';
end;

procedure TCalcDisplayWidget.DrawStatic;
var
  i: integer;
begin
  FillPoly([0, 12, 12, 0, 460, 0, 472, 12, DW, 12, DW, DH - 12, DW - 12, DH, 0, DH], Navy(220));
  Polygon([0, 12, 12, 0, 460, 0, 472, 12, DW, 12, DW, DH - 12, DW - 12, DH, 0, DH], 1.4, Ice(190));
  for i := 0 to 5 do
    Line(414 + i * 7, 9, 421 + i * 7, 2, 2, White(200));
  Line(DW, 30, DW, 110, 3, White);
  Line(0, 120, 0, 170, 3, White(220));
  Txt(16, 16, '\\CALC', 8, White(230));
  Line(30, 100, DW - 30, 100, 1, Ice(90));
end;

procedure TCalcDisplayWidget.DrawDynamic;
var
  e: string;
  maxChars: integer;
begin
  // indicators
  TxtCached(DW - 24, 24, AngleText, 8, taRightJustify, Ice(220));
  if MemoryOn then TxtCached(DW - 80, 24, 'M', 8, taRightJustify, White);
  TxtCached(120, 24, AnsText, 7, taLeftJustify, Ice(150));
  // expression: the end stays visible
  e := DisplayForm(ExprText);
  maxChars := 52;
  if UTF8Length(e) > maxChars then e := '…' + UTF8Copy(e, UTF8Length(e) - maxChars + 2, maxChars);
  TxtCached(DW - 30, 66, e, 15, taRightJustify, Ice(230));
  // result or error
  if ErrorText <> '' then
    TxtCached(DW - 30, 140, ErrorText, 15, taRightJustify, White)
  else if ResultText <> '' then
  begin
    if Fresh then
      TxtCached(DW - 30, 140, ResultText, 40, taRightJustify)
    else
      TxtCached(DW - 30, 140, '= ' + ResultText, 22, taRightJustify, Ice(200));
  end;
end;

procedure TCalcDisplayWidget.DefineDirty;
begin
  AddDirty(20, 14, DW - 8, DH - 8);
end;

procedure TCalcDisplayWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 740 x 190.');
  L.Add('  Top      ANS value, M (memory set), DEG / RAD');
  L.Add('  Middle   expression (size 15, right-aligned, × ÷ √ glyphs, no cursor,');
  L.Add('           long input scrolls so the end stays visible)');
  L.Add('  Bottom   result size 40 after "=", live preview "= x" size 22 while typing,');
  L.Add('           or the error message');
end;

{ ---------- TKeypadWidget ---------- }

const
  KW = 740;
  KH = 440;

constructor TKeypadWidget.Create;
begin
  inherited Create;
  SetView(KW, KH);
  HoverKey := -1;
  FlashKey := -1;
  AngleCaption := 'DEG';
end;

class function TKeypadWidget.UIName: string;
begin
  Result := 'Keypad';
end;

class function TKeypadWidget.UIDescription: string;
begin
  Result := 'HUD buttons: scientific block (3 columns) and standard block (5 columns), hover and press flash.';
end;

class function TKeypadWidget.UnitFile: string;
begin
  Result := 'HUDCalculator\uhudcalculator.pas';
end;

function TKeypadWidget.KeyRect(i: integer; out x1, y1, x2, y2: single): boolean;
var
  gapX: single;
begin
  Result := Keys[i].Col >= 0;
  if not Result then Exit;
  // a wider gap separates the scientific block from the standard block
  if Keys[i].Col >= 3 then gapX := 18 else gapX := 0;
  x1 := KPadX + Keys[i].Col * KCellW + gapX;
  y1 := KPadY + Keys[i].Row * KCellH;
  x2 := x1 + Keys[i].ColSpan * KCellW - KGap;
  y2 := y1 + Keys[i].RowSpan * KCellH - KGap;
end;

function TKeypadWidget.KeyAt(lx, ly: single): integer;
var
  i: integer;
  x1, y1, x2, y2: single;
begin
  for i := 0 to High(Keys) do
    if KeyRect(i, x1, y1, x2, y2) and (lx >= x1) and (lx < x2) and (ly >= y1) and (ly < y2) then
      Exit(i);
  Result := -1;
end;

procedure TKeypadWidget.Flash(i: integer);
begin
  FlashKey := i;
  FlashT0 := T;
end;

procedure TKeypadWidget.DrawStatic;
var
  i: integer;
  x1, y1, x2, y2, c: single;
  fill, edge, ink: TBGRAPixel;
begin
  FillPoly([0, 12, 12, 0, 300, 0, 312, 12, KW, 12, KW, KH - 12, KW - 12, KH, 0, KH], Steel(35));
  Polygon([0, 12, 12, 0, 300, 0, 312, 12, KW, 12, KW, KH - 12, KW - 12, KH, 0, KH], 1.3, Ice(170));
  Txt(16, 16, '\\KEYPAD', 7, White(220));
  for i := 0 to High(Keys) do
  begin
    if not KeyRect(i, x1, y1, x2, y2) then Continue;
    c := 6;  // chamfer
    case Keys[i].Kind of
      kkNum:    begin fill := Steel(90);  edge := Ice(170); ink := White; end;
      kkOp:     begin fill := Steel(60);  edge := Ice(230); ink := Ice;   end;
      kkFunc:   begin fill := Navy(200);  edge := Ice(130); ink := Ice(230); end;
      kkMem:    begin fill := Navy(200);  edge := Ice(110); ink := Ice(200); end;
      kkClear:  begin fill := Steel(130); edge := White(220); ink := White; end;
    else
      begin fill := Ice(170); edge := White; ink := Navy; end;
    end;
    FillPoly([x1 + c, y1, x2, y1, x2, y2 - c, x2 - c, y2, x1, y2, x1, y1 + c], fill);
    Polygon([x1 + c, y1, x2, y1, x2, y2 - c, x2 - c, y2, x1, y2, x1, y1 + c], 1.2, edge);
    if Keys[i].Kind = kkEquals then
      FLayer.FillRectAntialias(X(x1 + 8), Y(y1 + 8), X(x2 - 8), Y(y1 + 11), White);
    if Keys[i].Caption <> '' then
      Txt((x1 + x2) / 2, (y1 + y2) / 2, Keys[i].Caption, IfThen(Length(Keys[i].Caption) > 2, 10, 14),
        ink, taCenter);
  end;
end;

procedure TKeypadWidget.DrawDynamic;
var
  i: integer;
  x1, y1, x2, y2, age: single;
begin
  // the DEG / RAD key caption changes with the mode
  for i := 0 to High(Keys) do
    if (Keys[i].Action = '#angle') and KeyRect(i, x1, y1, x2, y2) then
      TxtCached((x1 + x2) / 2, (y1 + y2) / 2, AngleCaption, 10, taCenter, Ice);
  if (HoverKey >= 0) and KeyRect(HoverKey, x1, y1, x2, y2) then
  begin
    FillPoly([x1 + 6, y1, x2, y1, x2, y2 - 6, x2 - 6, y2, x1, y2, x1, y1 + 6], White(40));
    Polygon([x1 + 6, y1, x2, y1, x2, y2 - 6, x2 - 6, y2, x1, y2, x1, y1 + 6], 2, White);
  end;
  // press flash: a bright ring that fades in 0.25 s
  if (FlashKey >= 0) and KeyRect(FlashKey, x1, y1, x2, y2) then
  begin
    age := T - FlashT0;
    if (age >= 0) and (age < 0.25) then
      Polygon([x1 - 3, y1 - 3, x2 + 3, y1 - 3, x2 + 3, y2 + 3, x1 - 3, y2 + 3], 3,
        White(Round(255 * (1 - age / 0.25))));
  end;
end;

procedure TKeypadWidget.DefineDirty;
begin
  AddDirty(10, 26, KW - 6, KH - 6);
end;

procedure TKeypadWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %d x %d. Grid cell %d x %d, gap %d, from (%d,%d);', [KW, KH, KCellW, KCellH, KGap, KPadX, KPadY]));
  L.Add('the standard block (columns 3..7) is shifted 18 units right of the scientific one.');
  L.Add('  Kinds    number = Steel, operator = Ice outline, function / memory = Navy,');
  L.Add('           clear = brighter Steel, "=" = Ice fill spanning 3 rows');
  L.Add('  Hover    white outline + wash; press = fading white frame (0.25 s)');
  L.Add('  Keys     sin cos tan asin acos atan ln log eˣ x² √ xʸ n! 1/x |x| π e ANS,');
  L.Add('           MC MR M+ M- DEG/RAD, AC ⌫ ( ) %, digits . ± + - × ÷ EXP =');
end;

{ ---------- TCalcStatusWidget ---------- }

constructor TCalcStatusWidget.Create;
begin
  inherited Create;
  SetView(470, 150);
  Lines_ := TStringList.Create;
end;

destructor TCalcStatusWidget.Destroy;
begin
  Lines_.Free;
  inherited Destroy;
end;

class function TCalcStatusWidget.UIName: string;
begin
  Result := 'Calculator Status';
end;

class function TCalcStatusWidget.UIDescription: string;
begin
  Result := 'Memory, angle mode, ANS and the last error.';
end;

class function TCalcStatusWidget.UnitFile: string;
begin
  Result := 'HUDCalculator\uhudcalculator.pas';
end;

procedure TCalcStatusWidget.DrawStatic;
begin
  FillPoly([0, 12, 12, 0, 470, 0, 470, 138, 458, 150, 0, 150], Steel(40));
  Polygon([0, 12, 12, 0, 470, 0, 470, 138, 458, 150, 0, 150], 1.3, Ice(170));
  Txt(16, 16, '\\STATUS', 7, White(220));
end;

procedure TCalcStatusWidget.DrawDynamic;
var
  i: integer;
begin
  for i := 0 to Lines_.Count - 1 do
    TxtCached(18, 40 + i * 22, FitText(Lines_[i], 90), 8, taLeftJustify, Ice(220));
end;

procedure TCalcStatusWidget.DefineDirty;
begin
  AddDirty(10, 28, 300, 146);
end;

procedure TCalcStatusWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 470 x 150: memory, angle mode, ANS and the last error, one line each.');
end;

{ ---------- THUDCalculatorWidget ---------- }

constructor THUDCalculatorWidget.Create;
begin
  inherited Create;
  SetView(1240, 650);
  SetParamByName('Max zoom', 2);
  SetParamByName('Glow intensity', 0.9);
  FDegrees := 1;
  AddParam('Degrees', 'Calculator', '1 = trigonometry in degrees, 0 = radians.', FDegrees, 0, 1, 0, False);
  Engine := TCalcEngine.Create;
  FHistExpr := TStringList.Create;
  Display := TCalcDisplayWidget.Create;
  AddChild(Display, 10, 10, 'Display');
  Keypad := TKeypadWidget.Create;
  AddChild(Keypad, 10, 205, 'Keypad');
  History := THUDListWidget.CreateList(470, 470, '\\HISTORY');
  History.EmptyText := 'NO CALCULATIONS YET';
  AddChild(History, 760, 10, 'History');
  Status := TCalcStatusWidget.Create;
  AddChild(Status, 760, 495, 'Status');
  Core := THexCoreWidget.Create;
  AddChild(Core, 1110, 515, 'Activity core (Hex Core)');
  Display.ResultText := '0';
  Display.Fresh := True;
end;

destructor THUDCalculatorWidget.Destroy;
begin
  inherited Destroy;
  Engine.Free;
  FHistExpr.Free;
end;

class function THUDCalculatorWidget.UIName: string;
begin
  Result := 'HUD Calculator';
end;

class function THUDCalculatorWidget.UIDescription: string;
begin
  Result := 'Scientific calculator in the HUD style: precedence, parentheses, functions, memory, DEG/RAD ' +
    'and a history you can click to reuse.';
end;

class function THUDCalculatorWidget.UnitFile: string;
begin
  Result := 'HUDCalculator\uhudcalculator.pas';
end;

procedure THUDCalculatorWidget.Evaluate;
var
  v: double;
  r: string;
begin
  if Trim(Expression) = '' then Exit;
  Engine.Degrees := FDegrees >= 1;
  try
    v := Engine.Evaluate(Expression);
    r := FormatResult(v);
    LastResult := v;
    Engine.Ans := v;
    LastError := '';
    History.Add(DisplayForm(Expression) + ' = ' + r, FormatDateTime('hh:nn:ss', Now), ikNone);
    FHistExpr.Add(Expression);
    History.EnsureVisible(History.Count - 1);
    Display.ResultText := r;
    Display.ErrorText := '';
    JustEvaluated := True;
    // the hex core flares on every result
    Core.SetParamValue(Core.ParamIndex('Pulse rate'), 18);
  except
    on E: ECalcError do
    begin
      LastError := E.Message;
      Display.ErrorText := 'ERROR: ' + E.Message;
    end;
  end;
end;

procedure THUDCalculatorWidget.Press(const Action: string);
var
  last: string;
  v: double;
begin
  if Action = '' then Exit;
  if Action[1] = '#' then
  begin
    if Action = '#eval' then Evaluate
    else if Action = '#ac' then
    begin
      Expression := '';
      Display.ErrorText := '';
      Display.ResultText := '0';
      JustEvaluated := True;
    end
    else if Action = '#back' then
    begin
      if JustEvaluated then Expression := ''
      else if Expression <> '' then
      begin
        // remove a whole function name ("sin(") or one UTF-8 character
        last := Expression;
        if (Length(last) >= 5) and ((Copy(last, Length(last) - 4, 5) = 'asin(') or (Copy(last, Length(last) - 4, 5) = 'acos(') or
           (Copy(last, Length(last) - 4, 5) = 'atan(') or (Copy(last, Length(last) - 4, 5) = 'sqrt(')) then
          SetLength(Expression, Length(Expression) - 5)
        else if (Length(last) >= 4) and ((Copy(last, Length(last) - 3, 4) = 'sin(') or (Copy(last, Length(last) - 3, 4) = 'cos(') or
           (Copy(last, Length(last) - 3, 4) = 'tan(') or (Copy(last, Length(last) - 3, 4) = 'log(') or
           (Copy(last, Length(last) - 3, 4) = 'exp(') or (Copy(last, Length(last) - 3, 4) = 'abs(')) then
          SetLength(Expression, Length(Expression) - 4)
        else if (Length(last) >= 3) and ((Copy(last, Length(last) - 2, 3) = 'ln(') or (Copy(last, Length(last) - 2, 3) = 'ans')) then
          SetLength(Expression, Length(Expression) - 3)
        else
          Expression := UTF8Copy(Expression, 1, UTF8Length(Expression) - 1);
      end;
      JustEvaluated := False;
      Display.ErrorText := '';
    end
    else if Action = '#neg' then
    begin
      if JustEvaluated then Expression := 'ans';
      Expression := '-(' + Expression + ')';
      JustEvaluated := False;
    end
    else if Action = '#angle' then
      SetParamValue(ParamIndex('Degrees'), 1 - FDegrees)
    else if Action = '#mc' then Memory := 0
    else if Action = '#mr' then
    begin
      if JustEvaluated then Expression := '';
      Expression := Expression + '(' + FormatResult(Memory) + ')';
      JustEvaluated := False;
    end
    else if (Action = '#m+') or (Action = '#m-') then
    begin
      // memory uses the current expression's value (or the last result)
      v := LastResult;
      if (not JustEvaluated) and (Trim(Expression) <> '') then
      begin
        Evaluate;
        v := LastResult;
      end;
      if Action = '#m+' then Memory += v else Memory -= v;
    end;
    Exit;
  end;
  // text input
  if JustEvaluated then
  begin
    // an operator continues from the result, anything else starts fresh
    if (Action[1] in ['+', '-', '*', '/', '^', '%', '!']) and (Display.ErrorText = '') then
      Expression := 'ans'
    else
      Expression := '';
    JustEvaluated := False;
  end;
  Display.ErrorText := '';
  Expression := Expression + Action;
end;

procedure THUDCalculatorWidget.LoadHistory(row: integer);
begin
  if (row < 0) or (row >= FHistExpr.Count) then Exit;
  Expression := FHistExpr[row];
  JustEvaluated := False;
  Display.ErrorText := '';
end;

procedure THUDCalculatorWidget.PasteText(const S: string);
var
  i: integer;
  c: char;
  clean: string;
begin
  // accept only characters the calculator understands
  clean := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c in ['0'..'9', '.', '+', '-', '*', '/', '^', '(', ')', '%', '!', 'a'..'z', 'A'..'Z', ' '] then
      clean += c
    else if c = ',' then clean += '.';
  end;
  if clean = '' then Exit;
  if JustEvaluated then Expression := '';
  JustEvaluated := False;
  Expression := Expression + LowerCase(Trim(clean));
end;

procedure THUDCalculatorWidget.DrawDynamic;
var
  preview: string;
  pr: single;
begin
  Engine.Degrees := FDegrees >= 1;
  if FDegrees >= 1 then Keypad.AngleCaption := 'DEG' else Keypad.AngleCaption := 'RAD';
  Display.AngleText := Keypad.AngleCaption;
  Display.MemoryOn := Memory <> 0;
  Display.AnsText := 'ANS ' + FormatResult(Engine.Ans);
  Display.ExprText := Expression;
  Display.Fresh := JustEvaluated;
  // live preview while typing (errors stay silent until "=")
  if (not JustEvaluated) and (Display.ErrorText = '') then
  begin
    preview := '';
    try
      if Trim(Expression) <> '' then preview := FormatResult(Engine.Evaluate(Expression));
    except
      on E: ECalcError do preview := '';
    end;
    Display.ResultText := preview;
  end;
  Status.Lines_.Clear;
  Status.Lines_.Add('MEMORY  ' + FormatResult(Memory));
  Status.Lines_.Add('ANGLE   ' + Keypad.AngleCaption);
  Status.Lines_.Add('ANS     ' + FormatResult(Engine.Ans));
  if LastError <> '' then Status.Lines_.Add('ERROR   ' + LastError)
  else Status.Lines_.Add('ERROR   none');
  // the core flare decays back to calm
  pr := Core.Params[Core.ParamIndex('Pulse rate')].Value^;
  if pr > 2.5 then Core.SetParamValue(Core.ParamIndex('Pulse rate'), Max(2.5, pr - 0.4));
  inherited DrawDynamic;
end;

procedure THUDCalculatorWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('Canvas 1240 x 650 design units.');
  L.Add('');
  L.Add('LAYOUT');
  for i := 0 to ChildCount - 1 do
    L.Add(Format('  %-26s %-22s (%4.0f,%4.0f)', [ChildCaption(i), Children[i].ClassName,
      ChildOrigin(i).x, ChildOrigin(i).y]));
  L.Add('');
  L.Add('ENGINE (ucalcengine.pas)');
  L.Add('  precedence  ( )  >  ! %  >  ^ (right-assoc)  >  unary -  >  * / implicit  >  + -');
  L.Add('  -2^2 = -4, 2^3^2 = 512, 2pi and 3(4+1) multiply, missing ")" are added');
  L.Add('  functions   sin cos tan asin acos atan ln log sqrt abs exp; constants pi e ans');
  L.Add('  degrees     exact 0 for sin(180k) and cos(90+180k); tan(90+180k) is an error');
  L.Add('  results     12 significant digits (0.1 + 0.2 = 0.3)');
  L.Add('  errors      division by zero, domain errors, overflow, n! only for 0..170');
  L.Add('');
  L.Add('INPUT');
  L.Add('  After "=": an operator continues from ANS, a digit or function starts fresh.');
  L.Add('  ⌫ removes a whole function name ("sin(") or one character.');
  L.Add('  M+ / M- use the current expression (evaluated) or the last result.');
  L.Add('  Keys: digits . + - * / ^ ( ) % !, Enter/=, Backspace, Delete/Esc clear,');
  L.Add('        Ctrl+C copy result, Ctrl+V paste, D DEG/RAD, P pi.');
end;

procedure THUDCalculatorWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add('Expression          ' + Expression);
  L.Add('Last result         ' + FormatResult(LastResult));
  L.Add('Memory              ' + FormatResult(Memory));
  L.Add('History entries     ' + IntToStr(FHistExpr.Count));
  if LastError <> '' then L.Add('Last error          ' + LastError);
end;

{ ---------- input ---------- }

type
  TCalcInput = class(TComponent)
  private
    FForm: THUDHostForm;
    FOldKeyDown: TKeyEvent;
    FOldKeyPress: TKeyPressEvent;
    function C: THUDCalculatorWidget;
    function Local(px, py: integer; W: THUDWidget; out lx, ly: single): boolean;
    procedure DoKey(const Action: string);
    procedure Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure KeyPress(Sender: TObject; var Key: char);
    procedure CopyClick(Sender: TObject);
    procedure ClearHistoryClick(Sender: TObject);
  end;

function TCalcInput.C: THUDCalculatorWidget;
begin
  Result := FForm.Widget as THUDCalculatorWidget;
end;

function TCalcInput.Local(px, py: integer; W: THUDWidget; out lx, ly: single): boolean;
var
  i: integer;
  d, o: TPointF;
begin
  Result := False;
  d := C.PixelToDesign(px, py);
  for i := 0 to C.ChildCount - 1 do
    if C.Children[i] = W then
    begin
      o := C.ChildOrigin(i);
      lx := d.x - o.x;
      ly := d.y - o.y;
      Exit((lx >= 0) and (ly >= 0) and (lx < W.DesignWidth) and (ly < W.DesignHeight));
    end;
end;

procedure TCalcInput.DoKey(const Action: string);
var
  i: integer;
begin
  // flash the matching keypad key (also for keyboard input)
  for i := 0 to KeyCount - 1 do
    if Keys[i].Action = Action then
    begin
      C.Keypad.Flash(i);
      Break;
    end;
  C.Press(Action);
end;

procedure TCalcInput.Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  lx, ly: single;
begin
  C.Keypad.HoverKey := -1;
  C.History.Hover := -1;
  if Local(X, Y, C.Keypad, lx, ly) then C.Keypad.HoverKey := C.Keypad.KeyAt(lx, ly);
  if Local(X, Y, C.History, lx, ly) then C.History.Hover := C.History.RowAt(lx, ly);
end;

procedure TCalcInput.Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  lx, ly: single;
  k: integer;
begin
  FForm.View.SetFocus;
  if Button <> mbLeft then Exit;
  if Local(X, Y, C.Keypad, lx, ly) then
  begin
    k := C.Keypad.KeyAt(lx, ly);
    if k >= 0 then DoKey(Keys[k].Action);
  end;
  if Local(X, Y, C.History, lx, ly) then
  begin
    k := C.History.RowAt(lx, ly);
    if k >= 0 then
    begin
      C.History.Selected := k;
      C.LoadHistory(k);
    end;
  end;
end;

procedure TCalcInput.Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  lx, ly: single;
begin
  if Local(MousePos.X, MousePos.Y, C.History, lx, ly) then
  begin
    C.History.ScrollBy(-Sign(WheelDelta) * 3);
    Handled := True;
  end;
end;

procedure TCalcInput.KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (FForm.ActiveControl = FForm.View) or (FForm.ActiveControl = nil) then
  begin
    if ssCtrl in Shift then
      case Key of
        VK_C: begin CopyClick(nil); Key := 0; Exit; end;
        VK_V: begin C.PasteText(Clipboard.AsText); Key := 0; Exit; end;
      end;
    case Key of
      VK_RETURN: begin DoKey('#eval'); Key := 0; Exit; end;
      VK_BACK: begin DoKey('#back'); Key := 0; Exit; end;
      VK_DELETE: begin DoKey('#ac'); Key := 0; Exit; end;
      VK_ESCAPE:
        if C.Expression <> '' then
        begin
          DoKey('#ac');   // Esc on a non-empty display clears; on an empty one the host closes
          Key := 0;
          Exit;
        end;
      VK_SPACE: begin Key := 0; Exit; end;   // no animation pause in a calculator
      VK_D: begin DoKey('#angle'); Key := 0; Exit; end;
      VK_P: begin DoKey('π'); Key := 0; Exit; end;
      VK_E: begin DoKey('e'); Key := 0; Exit; end;
      VK_A..VK_C, VK_F..VK_O, VK_Q..VK_Z:
        begin Key := 0; Exit; end;   // keep the host's letter shortcuts (S, V...) out of typing
    end;
  end;
  if Assigned(FOldKeyDown) then FOldKeyDown(Sender, Key, Shift);
end;

procedure TCalcInput.KeyPress(Sender: TObject; var Key: char);
begin
  // symbols come here (they depend on Shift / keyboard layout); letters are handled in KeyDown
  if not ((FForm.ActiveControl = FForm.View) or (FForm.ActiveControl = nil)) then Exit;
  case Key of
    '0'..'9', '.', '+', '-', '*', '/', '^', '(', ')', '%', '!': DoKey(Key);
    ',': DoKey('.');
    '=': DoKey('#eval');
  else
    Exit;
  end;
  Key := #0;
end;

procedure TCalcInput.CopyClick(Sender: TObject);
begin
  Clipboard.AsText := FormatResult(C.LastResult);
  FForm.SetStatus('Copied ' + FormatResult(C.LastResult));
end;

procedure TCalcInput.ClearHistoryClick(Sender: TObject);
begin
  C.History.Clear;
  C.FHistExpr.Clear;
end;

procedure SetupCalculator(AForm: THUDHostForm);
var
  i: integer;
  inp: TCalcInput;
  Bar: TFlowPanel;

  procedure Btn(const ACaption: string; AClick: TNotifyEvent);
  var
    B: TButton;
  begin
    B := TButton.Create(AForm);
    B.Parent := Bar;
    B.Caption := ACaption;
    B.AutoSize := True;
    B.OnClick := AClick;
    B.BorderSpacing.Around := 2;
  end;

begin
  if not (AForm.Widget is THUDCalculatorWidget) then Exit;
  inp := TCalcInput.Create(AForm);
  inp.FForm := AForm;
  Bar := TFlowPanel.Create(AForm);
  Bar.Parent := AForm;
  Bar.Align := alTop;
  Bar.AutoSize := True;
  Bar.BevelOuter := bvNone;
  Bar.BorderSpacing.Around := 2;
  Btn('Copy result', @inp.CopyClick);
  Btn('Clear history', @inp.ClearHistoryClick);
  AForm.View.OnMouseMove := @inp.Move;
  AForm.View.OnMouseDown := @inp.Down;
  AForm.View.OnMouseWheel := @inp.Wheel;
  inp.FOldKeyDown := AForm.OnKeyDown;
  AForm.OnKeyDown := @inp.KeyDown;
  AForm.OnKeyPress := @inp.KeyPress;
  AForm.SetStatus('Type or click: digits + - * / ^ ( ) % !   Enter: =   Backspace   Del/Esc: clear   ' +
    'Ctrl+C/V   D: DEG/RAD   P: pi');
  // HUDCalculator.exe [--eval "expression"]... : evaluate at start (each goes into the
  // history); works together with --shot / --info
  for i := 1 to ParamCount - 1 do
    if ParamStr(i) = '--eval' then
      with AForm.Widget as THUDCalculatorWidget do
      begin
        Press('#ac');
        PasteText(ParamStr(i + 1));
        Evaluate;
      end;
end;

initialization
  HostSetupProc := @SetupCalculator;

end.
