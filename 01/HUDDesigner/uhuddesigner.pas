unit UHUDDesigner;

{ HUD Designer - lay out your own HUD screens with the Sci-Fi HUD kit.

  - Toolbar: add any kit widget, delete, duplicate, new, open, save, load the
    kit sample, export Pascal.
  - Mouse: click a widget to select it (its parameters appear in the info
    panel), drag it to move it (snaps to the grid).
  - Keys (view focused): Del delete, Ctrl+D duplicate, arrows nudge
    (Shift = 1 unit, else one grid step).
  - Layouts are saved as .hud files (INI text). "Export Pascal" writes a
    THUDComposite unit that builds the same screen in code (like
    SciFiHUDKit/uscifihudkit.pas), ready to become its own program. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, IniFiles, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  LCLType, BGRABitmap, BGRABitmapTypes, HUDCore, HUDHost,
  UOpticScanner, UTargetLock, UShieldCore, UHUDIconSet, UDataFrames, URadarSweep,
  UHexCore, UTargetCrosshair, UChevronLoader, UPillLoader, UBlockLoader, USlantLoader;

type
  TWidgetEntry = record
    Cls: THUDWidgetClass;
    UnitName: string;
  end;

  { THUDDesignWidget - the editable canvas }

  THUDDesignWidget = class(THUDComposite)
  private
    FSnap: single;
    FCounter: array of integer;    // per registry entry, for unique captions
    function NextCaption(cls: THUDWidgetClass): string;
  protected
    procedure DrawStatic; override;
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;

    function SnapValue(v: single): single;
    function AddItem(cls: THUDWidgetClass; AX, AY: single; const ACaption: string = ''): integer;
    function DuplicateItem(i: integer): integer;
    procedure DeleteItem(i: integer);
    procedure Clear;
    procedure LoadKitSample;
    procedure SaveToFile(const AFileName: string);
    procedure LoadFromFile(const AFileName: string);
    procedure ExportPascal(const AFileName, ASourceName: string);
    function IndexOfWidget(W: THUDWidget): integer;
    property Snap: single read FSnap;
  end;

function WidgetRegistryCount: integer;
function WidgetRegistry(i: integer): TWidgetEntry;
function FindWidgetEntry(const AClassName: string): integer;

implementation

const
  Registry: array[0..11] of TWidgetEntry = (
    (Cls: TOpticScannerWidget;    UnitName: 'UOpticScanner'),
    (Cls: TTargetLockWidget;      UnitName: 'UTargetLock'),
    (Cls: TShieldCoreWidget;      UnitName: 'UShieldCore'),
    (Cls: THUDIconSetWidget;      UnitName: 'UHUDIconSet'),
    (Cls: TDataFramesWidget;      UnitName: 'UDataFrames'),
    (Cls: TRadarSweepWidget;      UnitName: 'URadarSweep'),
    (Cls: THexCoreWidget;         UnitName: 'UHexCore'),
    (Cls: TTargetCrosshairWidget; UnitName: 'UTargetCrosshair'),
    (Cls: TChevronLoaderWidget;   UnitName: 'UChevronLoader'),
    (Cls: TPillLoaderWidget;      UnitName: 'UPillLoader'),
    (Cls: TBlockLoaderWidget;     UnitName: 'UBlockLoader'),
    (Cls: TSlantLoaderWidget;     UnitName: 'USlantLoader'));

function WidgetRegistryCount: integer;
begin
  Result := Length(Registry);
end;

function WidgetRegistry(i: integer): TWidgetEntry;
begin
  Result := Registry[i];
end;

function FindWidgetEntry(const AClassName: string): integer;
begin
  for Result := 0 to High(Registry) do
    if SameText(Registry[Result].Cls.ClassName, AClassName) then Exit;
  Result := -1;
end;

function DotFloat(v: double; dec: integer = 2): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(v, ffFixed, 15, dec, fs);
end;

function ParseDot(const s: string; def: double): double;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if not TryStrToFloat(StringReplace(Trim(s), ',', '.', []), Result, fs) then Result := def;
end;

{ ---------- THUDDesignWidget ---------- }

constructor THUDDesignWidget.Create;
begin
  inherited Create;
  SetView(740, 960);
  FSnap := 8;
  SetLength(FCounter, Length(Registry));
  AddParam('Canvas width', 'Canvas', 'Width of the design canvas in design units.',
    FViewW, 100, 4000, 0, True);
  AddParam('Canvas height', 'Canvas', 'Height of the design canvas in design units.',
    FViewH, 100, 4000, 0, True);
  AddParam('Snap grid', 'Canvas', 'Drag / nudge step in design units (0 = no snapping).',
    FSnap, 0, 64, 0, False);
  LoadKitSample;
end;

class function THUDDesignWidget.UIName: string;
begin
  Result := 'HUD Designer';
end;

class function THUDDesignWidget.UIDescription: string;
begin
  Result := 'Lay out your own HUD: add widgets from the toolbar, drag them, tune them in Parameters, ' +
    'save .hud layouts and export them as a Pascal unit.';
end;

class function THUDDesignWidget.UnitFile: string;
begin
  Result := 'HUDDesigner\uhuddesigner.pas';
end;

function THUDDesignWidget.SnapValue(v: single): single;
begin
  if FSnap >= 1 then Result := Round(v / FSnap) * FSnap else Result := Round(v);
end;

function THUDDesignWidget.NextCaption(cls: THUDWidgetClass): string;
var
  i: integer;
begin
  i := FindWidgetEntry(cls.ClassName);
  if i < 0 then Exit(cls.UIName);
  Inc(FCounter[i]);
  Result := Format('%s #%d', [cls.UIName, FCounter[i]]);
end;

function THUDDesignWidget.AddItem(cls: THUDWidgetClass; AX, AY: single; const ACaption: string): integer;
var
  cap: string;
begin
  if ACaption = '' then cap := NextCaption(cls) else cap := ACaption;
  Result := AddChild(cls.Create, AX, AY, cap);
end;

function THUDDesignWidget.DuplicateItem(i: integer): integer;
var
  src, dst: THUDWidget;
  p: integer;
  o: TPointF;
begin
  src := Children[i];
  o := ChildOrigin(i);
  Result := AddItem(THUDWidgetClass(src.ClassType), o.x + 16, o.y + 16);
  dst := Children[Result];
  for p := 0 to src.ParamCount - 1 do
    if src.ParamIsText(p) then
      dst.SetParamText(p, src.ParamAsText(p))
    else
      dst.SetParamValue(p, src.Params[p].Value^);
end;

procedure THUDDesignWidget.DeleteItem(i: integer);
begin
  RemoveChild(i);
end;

procedure THUDDesignWidget.Clear;
var
  i: integer;
begin
  while ChildCount > 0 do
    RemoveChild(ChildCount - 1);
  for i := 0 to High(FCounter) do FCounter[i] := 0;
end;

function THUDDesignWidget.IndexOfWidget(W: THUDWidget): integer;
begin
  for Result := 0 to ChildCount - 1 do
    if Children[Result] = W then Exit;
  Result := -1;
end;

procedure THUDDesignWidget.LoadKitSample;
var
  i: integer;
begin
  // the original Sci-Fi HUD kit sheet (same layout as SciFiHUDKit)
  Clear;
  FViewW := 740;
  FViewH := 960;
  AddItem(TOpticScannerWidget, 12, -10);
  AddItem(TTargetLockWidget, 62, 235);
  AddItem(TShieldCoreWidget, 72, 495);
  AddItem(THUDIconSetWidget, 63, 780);
  AddItem(TDataFramesWidget, 413, 20);
  AddItem(TRadarSweepWidget, 588, 15);
  i := AddItem(TRadarSweepWidget, 588, 138);
  Children[i].SetParamValue(Children[i].ParamIndex('Frame style'), 1);
  Children[i].SetParamValue(Children[i].ParamIndex('Sweep speed'), -70);
  AddItem(THexCoreWidget, 593, 267);
  AddItem(TTargetCrosshairWidget, 593, 390);
  AddItem(TChevronLoaderWidget, 420, 525);
  AddItem(TPillLoaderWidget, 420, 625);
  AddItem(TBlockLoaderWidget, 420, 730);
  AddItem(TSlantLoaderWidget, 420, 830);
  InvalidateStatic;
end;

procedure THUDDesignWidget.DrawStatic;
begin
  // canvas border so the design area is visible
  Polygon([0, 0, FViewW, 0, FViewW, FViewH, 0, FViewH], 1, Ice(70));
  inherited DrawStatic;
  if ChildCount = 0 then
    Txt(FViewW / 2, FViewH / 2, 'EMPTY CANVAS - ADD WIDGETS FROM THE TOOLBAR', 12, Ice(200), taCenter);
end;

procedure THUDDesignWidget.SaveToFile(const AFileName: string);
var
  ini: TMemIniFile;
  i, p: integer;
  sec: string;
  W: THUDWidget;
begin
  if FileExists(AFileName) then DeleteFile(AFileName);
  ini := TMemIniFile.Create(AFileName);
  try
    ini.WriteString('Layout', 'Format', 'HUDDesigner 1');
    for p := 0 to ParamCount - 1 do
      ini.WriteString('Canvas', Params[p].Name, ParamAsText(p));
    for i := 0 to ChildCount - 1 do
    begin
      W := Children[i];
      sec := Format('Item.%d', [i]);
      ini.WriteString(sec, 'Class', W.ClassName);
      ini.WriteString(sec, 'Caption', ChildCaption(i));
      ini.WriteString(sec, 'X', DotFloat(ChildOrigin(i).x, 1));
      ini.WriteString(sec, 'Y', DotFloat(ChildOrigin(i).y, 1));
      for p := 0 to W.ParamCount - 1 do
        if W.Params[p].Group <> 'Engine' then
          ini.WriteString(sec, 'P.' + W.Params[p].Name, W.ParamAsText(p));
    end;
    ini.UpdateFile;
  finally
    ini.Free;
  end;
end;

procedure THUDDesignWidget.LoadFromFile(const AFileName: string);
var
  ini: TMemIniFile;
  secs, keys: TStringList;
  i, ki, e, idx, p: integer;
  W: THUDWidget;
  pname: string;
begin
  ini := TMemIniFile.Create(AFileName);
  secs := TStringList.Create;
  keys := TStringList.Create;
  try
    Clear;
    for p := 0 to ParamCount - 1 do
      if not ParamIsText(p) then
        SetParamValue(p, ParseDot(ini.ReadString('Canvas', Params[p].Name, ParamAsText(p)), Params[p].Value^));
    ini.ReadSections(secs);
    for i := 0 to secs.Count - 1 do
    begin
      if Pos('Item.', secs[i]) <> 1 then Continue;
      e := FindWidgetEntry(ini.ReadString(secs[i], 'Class', ''));
      if e < 0 then Continue;  // unknown class: skipped
      idx := AddItem(Registry[e].Cls,
        ParseDot(ini.ReadString(secs[i], 'X', '0'), 0),
        ParseDot(ini.ReadString(secs[i], 'Y', '0'), 0),
        ini.ReadString(secs[i], 'Caption', ''));
      W := Children[idx];
      ini.ReadSection(secs[i], keys);
      for ki := 0 to keys.Count - 1 do
        if Pos('P.', keys[ki]) = 1 then
        begin
          pname := Copy(keys[ki], 3, MaxInt);
          p := W.ParamIndex(pname);
          if p < 0 then Continue;
          if W.ParamIsText(p) then
            W.SetParamText(p, ini.ReadString(secs[i], keys[ki], ''))
          else
            W.SetParamValue(p, ParseDot(ini.ReadString(secs[i], keys[ki], ''), W.Params[p].Value^));
        end;
    end;
    InvalidateStatic;
  finally
    keys.Free;
    secs.Free;
    ini.Free;
  end;
end;

procedure THUDDesignWidget.ExportPascal(const AFileName, ASourceName: string);
var
  L, units: TStringList;
  uName, base, cls, usesLine: string;
  i, p, e: integer;
  W, ref: THUDWidget;
  ch: char;
begin
  // unit / class names from the file name
  uName := '';
  for ch in ChangeFileExt(ExtractFileName(AFileName), '') do
    if ch in ['A'..'Z', 'a'..'z', '0'..'9', '_'] then uName += ch;
  if (uName = '') or (uName[1] in ['0'..'9']) then uName := 'U' + uName;
  // umyhud.pas -> unit umyhud, class TMyhudWidget
  base := uName;
  if (Length(base) > 1) and (UpCase(base[1]) = 'U') then Delete(base, 1, 1);
  base[1] := UpCase(base[1]);
  cls := 'T' + base + 'Widget';

  units := TStringList.Create;
  units.Sorted := True;
  units.Duplicates := dupIgnore;
  L := TStringList.Create;
  try
    for i := 0 to ChildCount - 1 do
    begin
      e := FindWidgetEntry(Children[i].ClassName);
      if e >= 0 then units.Add(Registry[e].UnitName);
    end;
    L.Add('unit ' + uName + ';');
    L.Add('');
    L.Add('{ ' + base + ' - HUD screen generated by HUD Designer');
    L.Add('  from ' + ExtractFileName(ASourceName) + ' on ' + FormatDateTime('yyyy-mm-dd hh:nn', Now) + '.');
    L.Add('  Run it like SciFiHUDKit: add it to KITS in tools/make_projects.py,');
    L.Add('  or call RunHUDWidget(' + cls + ') from any program. }');
    L.Add('');
    L.Add('{$mode objfpc}{$H+}');
    L.Add('');
    L.Add('interface');
    L.Add('');
    L.Add('uses');
    usesLine := '  Classes, SysUtils, HUDCore';
    for i := 0 to units.Count - 1 do usesLine += ', ' + units[i];
    L.Add(usesLine + ';');
    L.Add('');
    L.Add('type');
    L.Add('');
    L.Add('  { ' + cls + ' }');
    L.Add('');
    L.Add('  ' + cls + ' = class(THUDComposite)');
    L.Add('  public');
    L.Add('    constructor Create; override;');
    L.Add('    class function UIName: string; override;');
    L.Add('    class function UIDescription: string; override;');
    L.Add('    class function UnitFile: string; override;');
    L.Add('    procedure DescribeAnatomy(L: TStrings); override;');
    L.Add('  end;');
    L.Add('');
    L.Add('implementation');
    L.Add('');
    L.Add('constructor ' + cls + '.Create;');
    L.Add('var');
    L.Add('  W: THUDWidget;');
    L.Add('begin');
    L.Add('  inherited Create;');
    L.Add(Format('  SetView(%s, %s);', [DotFloat(FViewW, 0), DotFloat(FViewH, 0)]));
    // engine settings that differ from the defaults
    for p := 0 to ParamCount - 1 do
      if (Params[p].Group = 'Engine') and (Abs(Params[p].Value^ - Params[p].DefV) > 1e-4) then
        L.Add(Format('  SetParamByName(%s, %s);', [QuotedStr(Params[p].Name), ParamAsText(p)]));
    for i := 0 to ChildCount - 1 do
    begin
      W := Children[i];
      ref := THUDWidgetClass(W.ClassType).Create;  // fresh instance = defaults
      try
        L.Add('');
        L.Add('  W := ' + W.ClassName + '.Create;');
        for p := 0 to W.ParamCount - 1 do
        begin
          if W.Params[p].Group = 'Engine' then Continue;
          if W.ParamAsText(p) = ref.ParamAsText(p) then Continue;
          if W.ParamIsText(p) then
            L.Add(Format('  W.SetTextParamByName(%s, %s);', [QuotedStr(W.Params[p].Name), QuotedStr(W.ParamAsText(p))]))
          else
            L.Add(Format('  W.SetParamByName(%s, %s);', [QuotedStr(W.Params[p].Name), W.ParamAsText(p)]));
        end;
        L.Add(Format('  AddChild(W, %s, %s, %s);',
          [DotFloat(ChildOrigin(i).x, 1), DotFloat(ChildOrigin(i).y, 1), QuotedStr(ChildCaption(i))]));
      finally
        ref.Free;
      end;
    end;
    L.Add('end;');
    L.Add('');
    L.Add('class function ' + cls + '.UIName: string;');
    L.Add('begin');
    L.Add('  Result := ' + QuotedStr(base) + ';');
    L.Add('end;');
    L.Add('');
    L.Add('class function ' + cls + '.UIDescription: string;');
    L.Add('begin');
    L.Add(Format('  Result := %s;', [QuotedStr(Format('HUD screen with %d widgets, designed in HUD Designer.', [ChildCount]))]));
    L.Add('end;');
    L.Add('');
    L.Add('class function ' + cls + '.UnitFile: string;');
    L.Add('begin');
    L.Add('  Result := ' + QuotedStr(ExtractFileName(AFileName)) + ';');
    L.Add('end;');
    L.Add('');
    L.Add('procedure ' + cls + '.DescribeAnatomy(L: TStrings);');
    L.Add('var');
    L.Add('  i: integer;');
    L.Add('begin');
    L.Add(Format('  L.Add(%s);', [QuotedStr(Format('Canvas %s x %s design units, %d widgets:', [DotFloat(FViewW, 0), DotFloat(FViewH, 0), ChildCount]))]));
    L.Add('  for i := 0 to ChildCount - 1 do');
    L.Add('    L.Add(Format(''  %-28s %-24s (%4.0f,%4.0f)'', [ChildCaption(i), Children[i].ClassName,');
    L.Add('      ChildOrigin(i).x, ChildOrigin(i).y]));');
    L.Add('end;');
    L.Add('');
    L.Add('end.');
    L.SaveToFile(AFileName);
  finally
    L.Free;
    units.Free;
  end;
end;

procedure THUDDesignWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
  o: TPointF;
begin
  L.Add(Format('Canvas %s x %s design units, %d widgets, snap %s.',
    [DotFloat(FViewW, 0), DotFloat(FViewH, 0), ChildCount, DotFloat(FSnap, 0)]));
  L.Add('Draw order = list order (later widgets are drawn on top).');
  L.Add('');
  L.Add(Format('%-4s %-28s %-24s %-14s %s', ['#', 'Caption', 'Class', 'Origin', 'Size']));
  for i := 0 to ChildCount - 1 do
  begin
    o := ChildOrigin(i);
    L.Add(Format('%-4d %-28s %-24s (%4.0f,%4.0f)    %3.0f x %3.0f', [i, ChildCaption(i),
      Children[i].ClassName, o.x, o.y, Children[i].DesignWidth, Children[i].DesignHeight]));
  end;
  L.Add('');
  L.Add('EDITING');
  L.Add('  Click = select, drag = move (snaps to "Snap grid"), Del = delete,');
  L.Add('  Ctrl+D = duplicate, arrows = nudge (Shift: 1 unit).');
  L.Add('  Parameters of the selected widget are in the Parameters tab;');
  L.Add('  "Whole canvas" holds canvas size, snap and the engine settings.');
  L.Add('');
  L.Add('FILES');
  L.Add('  .hud    INI text: [Canvas] params, [Item.n] Class/Caption/X/Y/P.<param>');
  L.Add('  Export  Pascal unit with a THUDComposite that rebuilds this screen;');
  L.Add('          only parameters that differ from the widget defaults are written.');
end;

procedure THUDDesignWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Widgets             %d', [ChildCount]));
end;

{ ---------- designer controller (toolbar, mouse, keys) ---------- }

type

  { TDesignerController }

  TDesignerController = class(TComponent)
  private
    FForm: THUDHostForm;
    FCanvas: THUDDesignWidget;
    FKind: TComboBox;
    FFileName: string;
    FOldKeyDown: TKeyEvent;
    FDragIdx: integer;
    FDragStart: TPoint;
    FDragOrigin, FDragNew: TPointF;
    FDragging: boolean;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    function Selected: integer;
    function LayoutDir: string;
    procedure AfterStructureChange(ASelect: integer);
    procedure UpdateCaption;
    procedure AddClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure DuplicateClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure SampleClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ViewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreateFor(AForm: THUDHostForm);
  end;

constructor TDesignerController.CreateFor(AForm: THUDHostForm);
var
  Bar: TFlowPanel;
  Lbl: TLabel;
  i: integer;
begin
  inherited Create(AForm);
  FForm := AForm;
  FCanvas := AForm.Widget as THUDDesignWidget;
  FDragIdx := -1;

  Bar := TFlowPanel.Create(AForm);
  Bar.Parent := AForm;
  Bar.Align := alTop;
  Bar.AutoSize := True;
  Bar.BevelOuter := bvNone;
  Bar.BorderSpacing.Around := 2;
  AddButton(Bar, 'New', @NewClick);
  AddButton(Bar, 'Open...', @OpenClick);
  AddButton(Bar, 'Save...', @SaveClick);
  AddButton(Bar, 'Export Pascal...', @ExportClick);
  AddButton(Bar, 'Kit sample', @SampleClick);
  Lbl := TLabel.Create(AForm);
  Lbl.Parent := Bar;
  Lbl.Caption := '   Widget:';
  Lbl.BorderSpacing.Around := 6;
  FKind := TComboBox.Create(AForm);
  FKind.Parent := Bar;
  FKind.Style := csDropDownList;
  FKind.Width := 170;
  FKind.BorderSpacing.Around := 2;
  for i := 0 to WidgetRegistryCount - 1 do
    FKind.Items.Add(WidgetRegistry(i).Cls.UIName);
  FKind.ItemIndex := 0;
  AddButton(Bar, 'Add', @AddClick);
  AddButton(Bar, 'Duplicate', @DuplicateClick);
  AddButton(Bar, 'Delete', @DeleteClick);

  FForm.View.OnMouseDown := @ViewDown;
  FForm.View.OnMouseMove := @ViewMove;
  FForm.View.OnMouseUp := @ViewUp;
  FOldKeyDown := FForm.OnKeyDown;
  FForm.OnKeyDown := @KeyDown;
  FForm.SetStatus('Click: select   Drag: move   Del: delete   Ctrl+D: duplicate   Arrows: nudge' +
    LineEnding + 'Space: pause   S: screenshot   D: dirty rects   Esc: exit');
  UpdateCaption;
end;

function TDesignerController.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(FForm);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.OnClick := AClick;
  Result.BorderSpacing.Around := 2;
end;

function TDesignerController.Selected: integer;
begin
  Result := FCanvas.IndexOfWidget(FForm.InfoWidget);
end;

function TDesignerController.LayoutDir: string;
begin
  Result := ExtractFilePath(Application.ExeName) + 'layouts';
  ForceDirectories(Result);
end;

procedure TDesignerController.UpdateCaption;
var
  n: string;
begin
  if FFileName = '' then n := 'untitled' else n := ExtractFileName(FFileName);
  FForm.Caption := 'HUD Designer  -  ' + n;
end;

procedure TDesignerController.AfterStructureChange(ASelect: integer);
begin
  FForm.RefreshSelector;
  FForm.SelectInfo(ASelect);
  FForm.RequestFullRepaint;
end;

procedure TDesignerController.AddClick(Sender: TObject);
var
  i: integer;
  W: THUDWidget;
begin
  // add, then centre it on the canvas (its size is known once it exists)
  i := FCanvas.AddItem(WidgetRegistry(FKind.ItemIndex).Cls, 0, 0);
  W := FCanvas.Children[i];
  FCanvas.SetChildOrigin(i, FCanvas.SnapValue((FCanvas.DesignWidth - W.DesignWidth) / 2),
    FCanvas.SnapValue((FCanvas.DesignHeight - W.DesignHeight) / 2));
  AfterStructureChange(i);
end;

procedure TDesignerController.DeleteClick(Sender: TObject);
var
  i: integer;
begin
  i := Selected;
  if i < 0 then Exit;
  FForm.SelectInfo(-1);       // the info panel must not point at a freed widget
  FCanvas.DeleteItem(i);
  AfterStructureChange(-1);
end;

procedure TDesignerController.DuplicateClick(Sender: TObject);
var
  i: integer;
begin
  i := Selected;
  if i < 0 then Exit;
  AfterStructureChange(FCanvas.DuplicateItem(i));
end;

procedure TDesignerController.NewClick(Sender: TObject);
begin
  FForm.SelectInfo(-1);
  FCanvas.Clear;
  FCanvas.InvalidateStatic;
  FFileName := '';
  UpdateCaption;
  AfterStructureChange(-1);
end;

procedure TDesignerController.SampleClick(Sender: TObject);
begin
  FForm.SelectInfo(-1);
  FCanvas.LoadKitSample;
  AfterStructureChange(-1);
end;

procedure TDesignerController.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(nil);
  try
    D.Filter := 'HUD layout (*.hud)|*.hud|All files (*.*)|*.*';
    D.InitialDir := LayoutDir;
    if not D.Execute then Exit;
    FForm.SelectInfo(-1);
    FCanvas.LoadFromFile(D.FileName);
    FFileName := D.FileName;
    UpdateCaption;
    AfterStructureChange(-1);
    FForm.SetStatus('Opened ' + D.FileName);
  finally
    D.Free;
  end;
end;

procedure TDesignerController.SaveClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(nil);
  try
    D.Filter := 'HUD layout (*.hud)|*.hud';
    D.DefaultExt := 'hud';
    D.InitialDir := LayoutDir;
    D.FileName := ExtractFileName(FFileName);
    D.Options := D.Options + [ofOverwritePrompt];
    if not D.Execute then Exit;
    FCanvas.SaveToFile(D.FileName);
    FFileName := D.FileName;
    UpdateCaption;
    FForm.SetStatus('Saved ' + D.FileName);
  finally
    D.Free;
  end;
end;

procedure TDesignerController.ExportClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(nil);
  try
    D.Filter := 'Pascal unit (*.pas)|*.pas';
    D.DefaultExt := 'pas';
    D.InitialDir := LayoutDir;
    if FFileName <> '' then
      D.FileName := 'u' + LowerCase(ChangeFileExt(ExtractFileName(FFileName), '')) + '.pas'
    else
      D.FileName := 'umyhud.pas';
    D.Options := D.Options + [ofOverwritePrompt];
    if not D.Execute then Exit;
    FCanvas.ExportPascal(D.FileName, FFileName);
    FForm.SetStatus('Exported ' + D.FileName + LineEnding +
      'Add it to KITS in tools\make_projects.py to build it as a program.');
  finally
    D.Free;
  end;
end;

procedure TDesignerController.ViewDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  i: integer;
begin
  FForm.View.SetFocus;
  if Button <> mbLeft then Exit;
  i := FCanvas.ChildAt(X, Y);
  FForm.SelectInfo(i);
  FDragIdx := i;
  FDragging := False;
  if i >= 0 then
  begin
    FDragStart := Point(X, Y);
    FDragOrigin := FCanvas.ChildOrigin(i);
    FDragNew := FDragOrigin;
  end;
end;

procedure TDesignerController.ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  R: TRect;
  k: single;
  dx, dy: integer;
begin
  if (FDragIdx < 0) or not (ssLeft in Shift) then Exit;
  if not FDragging and (Abs(X - FDragStart.X) + Abs(Y - FDragStart.Y) < 4) then Exit;
  FDragging := True;
  k := FCanvas.Scale;
  if k <= 0 then Exit;
  FDragNew := PointF(FCanvas.SnapValue(FDragOrigin.x + (X - FDragStart.X) / k),
                     FCanvas.SnapValue(FDragOrigin.y + (Y - FDragStart.Y) / k));
  // outline only while dragging: moving the widget rebuilds the static cache
  R := FCanvas.ChildPixelRect(FDragIdx);
  dx := Round((FDragNew.x - FDragOrigin.x) * k);
  dy := Round((FDragNew.y - FDragOrigin.y) * k);
  R := Rect(R.Left + dx, R.Top + dy, R.Right + dx, R.Bottom + dy);
  FForm.View.DragRect := R;
  FForm.View.ShowDrag := True;
  FForm.SetStatus(Format('Moving %s to (%.0f, %.0f)', [FCanvas.ChildCaption(FDragIdx), FDragNew.x, FDragNew.y]));
end;

procedure TDesignerController.ViewUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if FDragging and (FDragIdx >= 0) then
  begin
    FCanvas.SetChildOrigin(FDragIdx, FDragNew.x, FDragNew.y);
    FForm.RefreshInfo;
    FForm.SetStatus(Format('Moved %s to (%.0f, %.0f)', [FCanvas.ChildCaption(FDragIdx), FDragNew.x, FDragNew.y]));
  end;
  FForm.View.ShowDrag := False;
  FForm.RequestFullRepaint;
  FDragIdx := -1;
  FDragging := False;
end;

procedure TDesignerController.KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  i: integer;
  step: single;
  o: TPointF;
begin
  // editing keys only while the view has the focus (not while typing in the panel)
  if FForm.ActiveControl = FForm.View then
  begin
    i := Selected;
    if ssShift in Shift then step := 1 else step := Max(1, FCanvas.Snap);
    case Key of
      VK_DELETE:
        begin DeleteClick(nil); Key := 0; end;
      VK_D:
        if ssCtrl in Shift then begin DuplicateClick(nil); Key := 0; end;
      VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN:
        if i >= 0 then
        begin
          o := FCanvas.ChildOrigin(i);
          case Key of
            VK_LEFT: o.x -= step;
            VK_RIGHT: o.x += step;
            VK_UP: o.y -= step;
            VK_DOWN: o.y += step;
          end;
          FCanvas.SetChildOrigin(i, o.x, o.y);
          FForm.RefreshInfo;
          FForm.RequestFullRepaint;
          Key := 0;
        end;
    end;
  end;
  if (Key <> 0) and Assigned(FOldKeyDown) then
    FOldKeyDown(Sender, Key, Shift);
end;

procedure SelfTest(C: THUDDesignWidget; const ADir: string);
{ HUDDesigner.exe --selftest <dir> : save -> clear -> load -> compare -> export }
var
  R: TStringList;
  before, after: TStringList;
  i: integer;
begin
  R := TStringList.Create;
  before := TStringList.Create;
  after := TStringList.Create;
  try
    ForceDirectories(ADir);
    C.LoadKitSample;
    C.SetChildOrigin(1, 100, 260);                                  // move
    C.Children[9].SetParamText(C.Children[9].ParamIndex('Label text'), 'CPU LOAD');
    C.Children[0].SetParamValue(C.Children[0].ParamIndex('Rotation speed'), 33);
    C.DuplicateItem(7);                                              // duplicate
    C.DeleteItem(3);                                                 // delete
    C.SaveToFile(ADir + 'test.hud');
    C.DescribeAnatomy(before);
    for i := 0 to C.ChildCount - 1 do
      before.Add(C.ChildCaption(i) + ' ' + C.Children[i].ParamAsText(C.Children[i].ParamCount - 1));
    C.Clear;
    C.LoadFromFile(ADir + 'test.hud');
    C.DescribeAnatomy(after);
    for i := 0 to C.ChildCount - 1 do
      after.Add(C.ChildCaption(i) + ' ' + C.Children[i].ParamAsText(C.Children[i].ParamCount - 1));
    R.Add('items after reload: ' + IntToStr(C.ChildCount));
    R.Add('round trip identical: ' + BoolToStr(before.Text = after.Text, True));
    C.ExportPascal(ADir + 'udesignexport.pas', ADir + 'test.hud');
    R.Add('exported: ' + ADir + 'udesignexport.pas');
    R.AddStrings(after);
    R.SaveToFile(ADir + 'selftest.txt');
  finally
    after.Free;
    before.Free;
    R.Free;
  end;
end;

procedure SetupDesigner(AForm: THUDHostForm);
begin
  if not (AForm.Widget is THUDDesignWidget) then Exit;
  if (ParamCount >= 2) and (ParamStr(1) = '--selftest') then
  begin
    SelfTest(THUDDesignWidget(AForm.Widget), IncludeTrailingPathDelimiter(ParamStr(2)));
    Application.Terminate;
    Exit;
  end;
  TDesignerController.CreateFor(AForm);
end;

initialization
  HostSetupProc := @SetupDesigner;

end.
