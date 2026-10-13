unit HUDHost;

{ Host window shared by all Sci-Fi HUD programs:
  - left: THUDView, the live HUD rendering (partial blits of dirty rects)
  - right: developer info panel (Overview, Parameters, Anatomy, Palette, Live)

  A program only has to call RunHUDWidget(TMyWidget). }

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}MMSystem,{$ENDIF} Classes, SysUtils, Math, Forms, Controls, Graphics,
  ExtCtrls, StdCtrls, ComCtrls, ValEdit, Grids, Clipbrd, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { THUDView }

  THUDView = class(TCustomControl)
  private
    FWidget: THUDWidget;
    FPartial: boolean;       // next paint only needs the dirty rects
    FLastW, FLastH: integer; // size of the last paint
  public
    AnimTime: single;
    ShowDirty: boolean;
    Frames: integer;         // painted frames (FPS counter)
    constructor Create(AOwner: TComponent; AWidget: THUDWidget); reintroduce;
    procedure EraseBackground(DC: HDC); override;
    procedure Paint; override;
    procedure RequestFrame(ForceFull: boolean);
  end;

  { THUDHostForm }

  THUDHostForm = class(TForm)
  private
    FWidget: THUDWidget;
    FView: THUDView;
    FInfo: TPanel;
    FTitle, FDesc, FStatus, FParamHint: TLabel;
    FPages: TPageControl;
    FOverview, FAnatomy, FLive: TMemo;
    FParamGrid: TValueListEditor;
    FPalette: TPaintBox;
    FBtnPause: TButton;
    FChkDirty, FChkCap: TCheckBox;
    FInfoTimer: TTimer;
    FAnimTime, FLastTick, FNextFrame, FFpsStart, FFps: double;
    FPaused, FForceFull: boolean;
    FProfSnap: array[0..3] of double;
    FProfSnapFrames: integer;
    procedure BuildUI;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    function AddMemo(APage: TTabSheet): TMemo;
    procedure FillOverview;
    procedure FillParams;
    procedure FillAnatomy;
    procedure UpdateLive;
    function ParamText(i: integer): string;
    function ParamOfRow(aRow: integer): integer;
    function InfoText: string;
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure InfoTimerTick(Sender: TObject);
    procedure PauseClick(Sender: TObject);
    procedure ShotClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure DirtyClick(Sender: TObject);
    procedure ViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ParamValidate(Sender: TObject; aCol, aRow: Integer;
      const OldValue: string; var NewValue: String);
    procedure ParamSelect(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
    procedure PalettePaint(Sender: TObject);
    procedure HostKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

procedure RunHUDWidget(AClass: THUDWidgetClass);

implementation

var
  HostWidgetClass: THUDWidgetClass;

procedure RunHUDWidget(AClass: THUDWidgetClass);
var
  F: THUDHostForm;
begin
  HostWidgetClass := AClass;
  Application.Title := AClass.UIName;
  Application.Initialize;
  Application.CreateForm(THUDHostForm, F);
  Application.Run;
end;

function FloatStr(v: single; dec: integer): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(v, ffFixed, 15, dec, fs);
end;

{ ---------- THUDView ---------- }

constructor THUDView.Create(AOwner: TComponent; AWidget: THUDWidget);
begin
  inherited Create(AOwner);
  FWidget := AWidget;
  TabStop := True;
  DoubleBuffered := False;
end;

procedure THUDView.EraseBackground(DC: HDC);
begin
  // we paint every pixel ourselves: no erase, no flicker
end;

procedure THUDView.RequestFrame(ForceFull: boolean);
var
  i: integer;
  R: TRect;
begin
  if not HandleAllocated then Exit;
  if ForceFull or ShowDirty or (FWidget.Output = nil) or
     (ClientWidth <> FLastW) or (ClientHeight <> FLastH) then
  begin
    FPartial := False;
    Invalidate;
  end
  else if FWidget.DirtyCount > 0 then
  begin
    // only the animated regions changed: invalidate just those
    FPartial := True;
    for i := 0 to FWidget.DirtyCount - 1 do
    begin
      R := FWidget.DirtyRect(i);
      InvalidateRect(Handle, @R, False);
    end;
  end
  else
    Exit; // static widget, nothing changed
  Update;  // paint synchronously, right now
end;

procedure THUDView.Paint;
var
  i: integer;
  R, BB, CR: TRect;
begin
  FWidget.Render(ClientWidth, ClientHeight, AnimTime);
  if FWidget.Output = nil then Exit;
  if FPartial and (FWidget.DirtyCount > 0) then
  begin
    // if Windows also asks for an area outside our rects, blit everything
    BB := FWidget.DirtyRect(0);
    for i := 1 to FWidget.DirtyCount - 1 do
      UnionRect(BB, BB, FWidget.DirtyRect(i));
    CR := Canvas.ClipRect;
    FPartial := (CR.Left >= BB.Left) and (CR.Top >= BB.Top) and
                (CR.Right <= BB.Right) and (CR.Bottom <= BB.Bottom);
  end
  else
    FPartial := False;
  if FPartial then
    for i := 0 to FWidget.DirtyCount - 1 do
    begin
      R := FWidget.DirtyRect(i);
      FWidget.Output.DrawPart(R, Canvas, R.Left, R.Top, True);
    end
  else
    FWidget.Output.Draw(Canvas, 0, 0, True);
  FPartial := False;
  if ShowDirty then
  begin
    // developer overlay: the regions recomposed every frame
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := clYellow;
    Canvas.Pen.Style := psDash;
    for i := 0 to FWidget.DirtyCount - 1 do
    begin
      R := FWidget.DirtyRect(i);
      Canvas.Rectangle(R);
    end;
    Canvas.Pen.Style := psSolid;
    Canvas.Font.Color := clYellow;
    Canvas.Font.Size := 8;
    Canvas.TextOut(6, 4, Format('%d dirty rect(s), %d px', [FWidget.DirtyCount, FWidget.DirtyArea]));
  end;
  FLastW := ClientWidth;
  FLastH := ClientHeight;
  Inc(Frames);
end;

{ ---------- THUDHostForm: construction ---------- }

constructor THUDHostForm.Create(TheOwner: TComponent);
var
  W, H: integer;
begin
  inherited Create(TheOwner);   // no .lfm: the whole UI is built in code
  FWidget := HostWidgetClass.Create;
  Caption := FWidget.UIName + '  -  Sci-Fi HUD (BGRABitmap)';
  Width := 1260;
  Height := 760;
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @HostKeyDown;
  BuildUI;
  {$IFDEF WINDOWS}
  timeBeginPeriod(1); // Sleep(1) really sleeps ~1 ms
  {$ENDIF}
  // <program>.exe --shot out.png [W H] : render one frame (t = 2.5 s) and quit
  if (ParamCount >= 2) and (ParamStr(1) = '--shot') then
  begin
    W := StrToIntDef(ParamStr(3), 760);
    H := StrToIntDef(ParamStr(4), 700);
    try
      FWidget.Render(W, H, 2.5);
      FWidget.Output.SaveToFile(ParamStr(2));
    except
      on E: Exception do
        with TStringList.Create do
        try
          Text := E.ClassName + ': ' + E.Message;
          SaveToFile(ParamStr(2) + '.error.txt');
        finally
          Free;
        end;
    end;
    Application.Terminate;
    Exit;
  end;
  // <program>.exe --info out.txt : export the info panel text and quit
  if (ParamCount >= 2) and (ParamStr(1) = '--info') then
  begin
    FWidget.Render(760, 700, 2.5);
    with TStringList.Create do
    try
      Text := InfoText;
      SaveToFile(ParamStr(2));
    finally
      Free;
    end;
    Application.Terminate;
    Exit;
  end;
  FLastTick := NowMs;
  FFpsStart := FLastTick;
  Application.OnIdle := @AppIdle;
end;

destructor THUDHostForm.Destroy;
begin
  Application.OnIdle := nil;
  {$IFDEF WINDOWS}
  timeEndPeriod(1);
  {$ENDIF}
  inherited Destroy;
  FWidget.Free;  // after the view (a child control) is gone
end;

function THUDHostForm.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.OnClick := AClick;
  Result.BorderSpacing.Around := 2;
end;

function THUDHostForm.AddMemo(APage: TTabSheet): TMemo;
begin
  Result := TMemo.Create(Self);
  Result.Parent := APage;
  Result.Align := alClient;
  Result.ReadOnly := True;
  Result.ScrollBars := ssAutoBoth;
  Result.WordWrap := False;
  Result.Font.Name := 'Consolas';
  Result.Font.Size := 9;
end;

procedure THUDHostForm.BuildUI;
var
  Head: TPanel;
  Bar: TFlowPanel;
  Split: TSplitter;
  Page: TTabSheet;
begin
  // ---- info panel (right) ----
  FInfo := TPanel.Create(Self);
  FInfo.Parent := Self;
  FInfo.Align := alRight;
  FInfo.Width := 500;
  FInfo.BevelOuter := bvNone;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alRight;
  Split.Left := FInfo.Left - 5;
  Split.Width := 5;

  Head := TPanel.Create(Self);
  Head.Parent := FInfo;
  Head.Align := alTop;
  Head.BevelOuter := bvNone;
  Head.AutoSize := True;
  Head.BorderSpacing.Around := 6;

  FTitle := TLabel.Create(Self);
  FTitle.Parent := Head;
  FTitle.Align := alTop;
  FTitle.Caption := FWidget.UIName;
  FTitle.Font.Size := 15;
  FTitle.Font.Style := [fsBold];

  FDesc := TLabel.Create(Self);
  FDesc.Parent := Head;
  FDesc.Align := alTop;
  FDesc.Top := 40;
  FDesc.WordWrap := True;
  FDesc.AutoSize := True;
  FDesc.Caption := FWidget.UIDescription;
  FDesc.BorderSpacing.Top := 4;

  Bar := TFlowPanel.Create(Self);
  Bar.Parent := FInfo;
  Bar.Align := alTop;
  Bar.Top := 200;
  Bar.AutoSize := True;
  Bar.BevelOuter := bvNone;
  Bar.BorderSpacing.Left := 4;
  FBtnPause := AddButton(Bar, 'Pause', @PauseClick);
  AddButton(Bar, 'Screenshot', @ShotClick);
  AddButton(Bar, 'Export info', @ExportClick);
  AddButton(Bar, 'Reset params', @ResetClick);
  FChkDirty := TCheckBox.Create(Self);
  FChkDirty.Parent := Bar;
  FChkDirty.Caption := 'Show dirty rects';
  FChkDirty.OnClick := @DirtyClick;
  FChkDirty.BorderSpacing.Around := 4;
  FChkCap := TCheckBox.Create(Self);
  FChkCap.Parent := Bar;
  FChkCap.Caption := '60 fps cap';
  FChkCap.Checked := True;
  FChkCap.BorderSpacing.Around := 4;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := FInfo;
  FStatus.Align := alBottom;
  FStatus.BorderSpacing.Around := 4;
  FStatus.Caption := 'Space: pause   S: screenshot   D: dirty rects   V: fps cap   Esc: exit';

  FPages := TPageControl.Create(Self);
  FPages.Parent := FInfo;
  FPages.Align := alClient;

  Page := FPages.AddTabSheet;
  Page.Caption := 'Overview';
  FOverview := AddMemo(Page);

  Page := FPages.AddTabSheet;
  Page.Caption := 'Parameters';
  FParamHint := TLabel.Create(Self);
  FParamHint.Parent := Page;
  FParamHint.Align := alBottom;
  FParamHint.WordWrap := True;
  FParamHint.AutoSize := True;
  FParamHint.BorderSpacing.Around := 6;
  FParamHint.Caption := 'Select a parameter to see its description. Edit the value and press Enter.';
  FParamGrid := TValueListEditor.Create(Self);
  FParamGrid.Parent := Page;
  FParamGrid.Align := alClient;
  FParamGrid.TitleCaptions.Clear;
  FParamGrid.TitleCaptions.Add('Parameter');
  FParamGrid.TitleCaptions.Add('Value');
  FParamGrid.ColWidths[0] := 200;
  FParamGrid.OnValidateEntry := @ParamValidate;
  FParamGrid.OnSelectCell := @ParamSelect;

  Page := FPages.AddTabSheet;
  Page.Caption := 'Anatomy';
  FAnatomy := AddMemo(Page);

  Page := FPages.AddTabSheet;
  Page.Caption := 'Palette';
  FPalette := TPaintBox.Create(Self);
  FPalette.Parent := Page;
  FPalette.Align := alClient;
  FPalette.OnPaint := @PalettePaint;

  Page := FPages.AddTabSheet;
  Page.Caption := 'Live';
  FLive := AddMemo(Page);

  // ---- HUD view (fills the rest) ----
  FView := THUDView.Create(Self, FWidget);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.OnMouseDown := @ViewMouseDown;

  FInfoTimer := TTimer.Create(Self);
  FInfoTimer.Interval := 250;
  FInfoTimer.OnTimer := @InfoTimerTick;

  FillOverview;
  FillParams;
  FillAnatomy;
end;

{ ---------- info panel content ---------- }

procedure THUDHostForm.FillOverview;
var
  L: TStringList;
  exe: string;
begin
  exe := ExtractFileName(Application.ExeName);
  L := TStringList.Create;
  try
    L.Add('UI NAME        ' + FWidget.UIName);
    L.Add('Program        ' + exe);
    L.Add('Widget class   ' + FWidget.ClassName);
    L.Add('Widget unit    ' + FWidget.UnitFile);
    L.Add('Shared units   shared\hudcore.pas (engine), shared\hudhost.pas (this window)');
    L.Add(Format('Design view    %s x %s design units (scaled to fit, max zoom %s)',
      [FloatStr(FWidget.DesignWidth, 0), FloatStr(FWidget.DesignHeight, 0), FloatStr(FWidget.Params[2].Value^, 1)]));
    L.Add('');
    L.Add('DESCRIPTION');
    L.Add('  ' + FWidget.UIDescription);
    L.Add('');
    L.Add('COORDINATES');
    L.Add('  Units are design units inside the view (origin top-left).');
    L.Add('  Angles are degrees, 0 = 3 o''clock, positive = clockwise.');
    L.Add('  Pixel = Offset + unit * Scale; see Live tab for the current scale.');
    L.Add('');
    L.Add('RENDER PIPELINE (hudcore.pas)');
    L.Add('  1. DrawStatic   once per size / static param change -> cached');
    L.Add('  2. DrawDynamic  every frame, only inside the dirty rects');
    L.Add('  3. Glow         box-downsample FLayer -> 2x box blur (H+V)');
    L.Add('  4. Compose      cache + fills + bilinear glow (add) + strokes,');
    L.Add('                  multithreaded when the dirty area >= 600k px');
    L.Add('  5. Blit         only the dirty rects are copied to the window');
    L.Add('  Strokes go to FLayer (glow). Colors with alpha < 200 or dark');
    L.Add('  colors are routed to FFill (no glow) by THUDWidget.Dest().');
    L.Add('');
    L.Add('HOW TO EXTEND THIS UI (' + FWidget.UnitFile + ')');
    L.Add('  constructor Create   SetView(w, h); AddParam(...); RegisterRing(...)');
    L.Add('  DrawStatic           add non-moving elements here (cheap: cached)');
    L.Add('  DrawDynamic          add moving elements here (cost: every frame)');
    L.Add('  DefineDirty          AddDirty(x1,y1,x2,y2) must cover EVERYTHING');
    L.Add('                       drawn in DrawDynamic (check "Show dirty rects")');
    L.Add('  DrawRingShape        shape of a pre-rendered rotating ring (RingFrame)');
    L.Add('  DescribeAnatomy      text of the Anatomy tab');
    L.Add('  DescribeLive         extra lines of the Live tab');
    L.Add('  Primitives           Arc Band Pie Ring Disc SoftDisc Ticks Dots Line');
    L.Add('                       PolyLine Polygon FillPoly Txt TxtCached');
    L.Add('  Palette              White Ice Steel Navy (alpha optional)');
    L.Add('');
    L.Add('KEYS & COMMAND LINE');
    L.Add('  Space pause   S screenshot   D dirty rects   V 60 fps cap   Esc exit');
    L.Add('  ' + exe + ' --shot out.png [W H]   render one frame and quit');
    L.Add('  ' + exe + ' --info out.txt         export this info and quit');
    FOverview.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

function THUDHostForm.ParamText(i: integer): string;
begin
  with FWidget.Params[i] do
    Result := FloatStr(Value^, Decimals);
end;

function THUDHostForm.ParamOfRow(aRow: integer): integer;
var
  key: string;
begin
  // rows are matched by name, never by position
  Result := -1;
  if (aRow < 1) or (aRow >= FParamGrid.RowCount) then Exit;
  key := FParamGrid.Keys[aRow];
  for Result := 0 to FWidget.ParamCount - 1 do
    if FWidget.Params[Result].Name = key then Exit;
  Result := -1;
end;

procedure THUDHostForm.FillParams;
var
  i: integer;
begin
  FParamGrid.Strings.BeginUpdate;
  try
    FParamGrid.Strings.Clear;
    for i := 0 to FWidget.ParamCount - 1 do
      FParamGrid.Strings.Add(FWidget.Params[i].Name + '=' + ParamText(i));
  finally
    FParamGrid.Strings.EndUpdate;
  end;
end;

procedure THUDHostForm.FillAnatomy;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    FWidget.DescribeAnatomy(L);
    FAnatomy.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

procedure THUDHostForm.UpdateLive;
var
  L: TStringList;
  i, n: integer;
  ms: array[0..3] of double;
  total: double;
begin
  n := FWidget.ProfFrames - FProfSnapFrames;
  for i := 0 to 3 do
  begin
    if n > 0 then ms[i] := (FWidget.Prof[i] - FProfSnap[i]) / n else ms[i] := 0;
    FProfSnap[i] := FWidget.Prof[i];
  end;
  FProfSnapFrames := FWidget.ProfFrames;
  total := ms[0] + ms[1] + ms[2] + ms[3];
  L := TStringList.Create;
  try
    L.Add('PERFORMANCE');
    L.Add(Format('  Painted fps         %.0f %s', [FFps, BoolToStr(FPaused, '(paused)', '')]));
    if FWidget.DirtyCount = 0 then
      L.Add('  Static widget       nothing is redrawn per frame')
    else
    begin
      L.Add(Format('  Render / frame      %.2f ms  (max %.0f fps)', [total, 1000 / Max(total, 0.01)]));
      L.Add(Format('    draw dynamic      %.2f ms', [ms[0]]));
      L.Add(Format('    glow downsample   %.2f ms', [ms[1]]));
      L.Add(Format('    glow blur         %.2f ms', [ms[2]]));
      L.Add(Format('    compose           %.2f ms  (%s)', [ms[3],
        BoolToStr(FWidget.UsesThreads, 'thread pool', 'main thread')]));
    end;
    L.Add(Format('  Static cache build  %.1f ms', [FWidget.StaticBuildMs]));
    L.Add('');
    L.Add('GEOMETRY');
    L.Add(Format('  View size           %d x %d px', [FWidget.RenderWidth, FWidget.RenderHeight]));
    L.Add(Format('  Scale               %.3f px per design unit', [FWidget.Scale]));
    L.Add(Format('  Glow grid           1/%d resolution, blur radius %d', [FWidget.GlowScale, FWidget.BlurRadius]));
    L.Add(Format('  Dirty rects         %d, %d px (%.0f%% of view)', [FWidget.DirtyCount, FWidget.DirtyArea,
      100 * FWidget.DirtyArea / Max(1, FWidget.RenderWidth * FWidget.RenderHeight)]));
    for i := 0 to FWidget.DirtyCount - 1 do
      with FWidget.DirtyRect(i) do
        L.Add(Format('    #%d  (%d,%d)-(%d,%d)', [i, Left, Top, Right, Bottom]));
    L.Add(Format('  Ring frames cached  %d', [FWidget.RingFramesCached]));
    L.Add('');
    L.Add('STATE');
    FWidget.DescribeLive(L);
    FLive.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

function THUDHostForm.InfoText: string;
var
  L, A: TStringList;
  i: integer;
  e: TPaletteEntry;
begin
  L := TStringList.Create;
  A := TStringList.Create;
  try
    L.AddStrings(FOverview.Lines);
    L.Add('');
    L.Add('PARAMETERS');
    for i := 0 to FWidget.ParamCount - 1 do
      with FWidget.Params[i] do
        L.Add(Format('  %-26s %10s  [%s .. %s] default %s  (%s%s) %s',
          [Name, ParamText(i), FloatStr(MinV, Decimals), FloatStr(MaxV, Decimals),
           FloatStr(DefV, Decimals), Group, BoolToStr(AffectsStatic, ', rebuilds cache', ''), Hint]));
    L.Add('');
    L.Add('ANATOMY');
    FWidget.DescribeAnatomy(A);
    L.AddStrings(A);
    L.Add('');
    L.Add('PALETTE');
    for i := 0 to PaletteCount - 1 do
    begin
      e := PaletteEntry(i);
      L.Add(Format('  %-18s #%.2x%.2x%.2x a%-3d  %s',
        [e.Name, e.Color.red, e.Color.green, e.Color.blue, e.Color.alpha, e.Usage]));
    end;
    L.Add('');
    L.Add('LIVE');
    UpdateLive;
    L.AddStrings(FLive.Lines);
    Result := L.Text;
  finally
    A.Free;
    L.Free;
  end;
end;

procedure THUDHostForm.PalettePaint(Sender: TObject);
var
  i, y: integer;
  e: TPaletteEntry;
  C: TCanvas;
  R: TRect;
begin
  C := FPalette.Canvas;
  C.Brush.Color := clWindow;
  C.FillRect(FPalette.ClientRect);
  y := 8;
  for i := 0 to PaletteCount - 1 do
  begin
    e := PaletteEntry(i);
    R := Rect(8, y, 56, y + 40);
    // swatch shown over the background navy so alpha is visible
    C.Brush.Color := RGBToColor(18, 36, 60);
    C.FillRect(R);
    C.Brush.Color := RGBToColor(
      (e.Color.red * e.Color.alpha + 18 * (255 - e.Color.alpha)) div 255,
      (e.Color.green * e.Color.alpha + 36 * (255 - e.Color.alpha)) div 255,
      (e.Color.blue * e.Color.alpha + 60 * (255 - e.Color.alpha)) div 255);
    C.FillRect(Rect(R.Left + 4, R.Top + 4, R.Right - 4, R.Bottom - 4));
    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := clWindowText;
    C.TextOut(66, y, Format('%s   #%.2x%.2x%.2x  alpha %d',
      [e.Name, e.Color.red, e.Color.green, e.Color.blue, e.Color.alpha]));
    C.Font.Style := [];
    C.TextOut(66, y + 18, e.Usage);
    C.Brush.Style := bsSolid;
    Inc(y, 52);
  end;
end;

{ ---------- events ---------- }

procedure THUDHostForm.ParamValidate(Sender: TObject; aCol, aRow: Integer;
  const OldValue: string; var NewValue: String);
var
  i: integer;
  v: double;
  fs: TFormatSettings;
begin
  i := ParamOfRow(aRow);
  if i < 0 then Exit;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if not TryStrToFloat(StringReplace(Trim(NewValue), ',', '.', []), v, fs) then
  begin
    NewValue := OldValue;
    Exit;
  end;
  FWidget.SetParamValue(i, v);
  NewValue := ParamText(i);   // clamped / rounded value
  FForceFull := True;
end;

procedure THUDHostForm.ParamSelect(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
var
  i: integer;
begin
  i := ParamOfRow(aRow);
  if i < 0 then Exit;
  with FWidget.Params[i] do
    FParamHint.Caption := Format('%s  (%s)'#10'%s'#10'Range %s .. %s, default %s%s',
      [Name, Group, Hint, FloatStr(MinV, Decimals), FloatStr(MaxV, Decimals),
       FloatStr(DefV, Decimals), BoolToStr(AffectsStatic, ' - changing it rebuilds the static cache', '')]);
end;

procedure THUDHostForm.PauseClick(Sender: TObject);
begin
  FPaused := not FPaused;
  FBtnPause.Caption := BoolToStr(FPaused, 'Play', 'Pause');
end;

procedure THUDHostForm.ShotClick(Sender: TObject);
var
  fn: string;
begin
  fn := ExtractFilePath(Application.ExeName) + StringReplace(FWidget.UIName, ' ', '', [rfReplaceAll]) + '_screenshot.png';
  FWidget.Render(FView.ClientWidth, FView.ClientHeight, FAnimTime);
  FWidget.Output.SaveToFile(fn);
  FStatus.Caption := 'Saved ' + fn;
end;

procedure THUDHostForm.ExportClick(Sender: TObject);
var
  fn: string;
begin
  fn := ExtractFilePath(Application.ExeName) + StringReplace(FWidget.UIName, ' ', '', [rfReplaceAll]) + '_info.txt';
  with TStringList.Create do
  try
    Text := InfoText;
    SaveToFile(fn);
    Clipboard.AsText := Text;
  finally
    Free;
  end;
  FStatus.Caption := 'Saved ' + fn + ' (also copied to clipboard)';
end;

procedure THUDHostForm.ResetClick(Sender: TObject);
begin
  FWidget.ResetParams;
  FillParams;
  FForceFull := True;
end;

procedure THUDHostForm.DirtyClick(Sender: TObject);
begin
  FView.ShowDirty := FChkDirty.Checked;
  FForceFull := True;
end;

procedure THUDHostForm.ViewMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FView.SetFocus;
end;

procedure THUDHostForm.HostKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // shortcuts only when the user is not typing in the info panel
  if (ActiveControl <> nil) and (ActiveControl <> FView) and
     not (ActiveControl is TButton) and not (ActiveControl is TCheckBox) then Exit;
  case Key of
    VK_SPACE: PauseClick(nil);
    VK_S: ShotClick(nil);
    VK_D: FChkDirty.Checked := not FChkDirty.Checked;  // fires DirtyClick
    VK_V: FChkCap.Checked := not FChkCap.Checked;
    VK_ESCAPE: Close;
  else
    Exit;
  end;
  Key := 0;
end;

procedure THUDHostForm.InfoTimerTick(Sender: TObject);
var
  now: double;
begin
  now := NowMs;
  if now - FFpsStart >= 1000 then
  begin
    FFps := FView.Frames * 1000 / (now - FFpsStart);
    FView.Frames := 0;
    FFpsStart := now;
  end;
  if FPages.ActivePage.Caption = 'Live' then
    UpdateLive;
end;

procedure THUDHostForm.AppIdle(Sender: TObject; var Done: Boolean);
const
  FrameMs = 1000 / 60;
var
  now: double;
begin
  Done := False;  // keep the idle loop running
  now := NowMs;
  if FPaused then
  begin
    FLastTick := now;
    if FForceFull then
    begin
      FForceFull := False;
      FView.RequestFrame(True);
    end;
    Sleep(5);
    Exit;
  end;
  if (not FChkCap.Checked) or (now >= FNextFrame) then
  begin
    // fixed cadence; if we fell behind, restart from now instead of bursting
    if now - FNextFrame > FrameMs then
      FNextFrame := now + FrameMs
    else
      FNextFrame := FNextFrame + FrameMs;
    FAnimTime += (now - FLastTick) / 1000 * FWidget.TimeScale;
    FLastTick := now;
    FView.AnimTime := FAnimTime;
    FView.RequestFrame(FForceFull);
    FForceFull := False;
  end
  else if FNextFrame - now > 1.5 then
    Sleep(1);   // give the CPU back while waiting for the next frame
end;

end.
