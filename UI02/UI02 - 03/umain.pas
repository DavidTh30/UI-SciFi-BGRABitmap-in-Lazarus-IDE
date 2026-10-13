unit UMain;

{ Window: the camera fly-through on the left, inspector panel on the right.
  Move the mouse over the picture to steer the camera.

  Inspector tabs
    Passes     - the 8 render passes with live thumbnail, on/off box, items
                 drawn and time per frame. Click a row to view it alone.
    Parameters - every value of THexSettings, generated from Hex.Params.
                 Camera / lens / fog values apply on the next frame; values
                 that feed a cache (sprites, field, particles) rebuild it
                 when the slider stops.
    Info       - live report: camera, lens, world, sprite cache, passes and
                 all parameter values.

  Keys (when no edit box has focus): R new seed, S save PNG, Space pause,
  F2 show/hide panel, F11 fullscreen, Esc leave fullscreen / unfocus. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, StdCtrls, ComCtrls,
  Spin, Dialogs, Clipbrd, LCLType, BGRABitmap, BGRABitmapTypes, UHexBackground;

type
  TPassRow = record
    Panel: TPanel;
    Check: TCheckBox;
    Thumb: TImage;
    Title, Stats: TLabel;
  end;

  TParamRow = record
    Track: TTrackBar;
    Spin: TFloatSpinEdit;
    ColorBtn: TColorButton;
    Alpha: TSpinEdit;
  end;

  { TMainForm }

  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FHex: THexBackground;
    FFrame: TBGRABitmap;
    FTimer: TTimer;
    FView: TPaintBox;
    FSide: TPanel;
    FSplitter: TSplitter;
    FPages: TPageControl;
    FPassTab, FInfoTab: TTabSheet;
    FViewCombo: TComboBox;
    FSeedEdit: TSpinEdit;
    FPauseBtn: TButton;
    FStatus: TLabel;
    FInfoMemo: TMemo;
    FPassRows: array[0..PassCount - 1] of TPassRow;
    FParamRows: array of TParamRow;
    FUpdating, FPaused, FFullScreen: boolean;
    FPending: TInvalidateSet;
    FPendingAt, FLastTick, FLastThumbs, FLastInfo, FLastStatus: QWord;
    FFrames: integer;
    FFps: double;
    FSavedBounds: TRect;
    procedure BuildSidePanel;
    procedure BuildPassesTab(Tab: TTabSheet);
    procedure BuildParamsTab(Tab: TTabSheet);
    procedure BuildInfoTab(Tab: TTabSheet);
    function AddButton(AParent: TWinControl; const ACaption: string;
      X, Y, W: integer; AOnClick: TNotifyEvent): TButton;
    function AddLabel(AParent: TWinControl; const ACaption: string; X, Y: integer): TLabel;
    function CompositePasses: TPassSet;
    procedure RefreshPassRows(WithThumbs: boolean);
    procedure RefreshParamControls;
    procedure RenderFrame;
    procedure ToggleFullScreen;
    procedure TimerTick(Sender: TObject);
    procedure ViewPaint(Sender: TObject);
    procedure ViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure ViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure ViewMouseLeave(Sender: TObject);
    procedure PassCheckClick(Sender: TObject);
    procedure PassRowClick(Sender: TObject);
    procedure ViewComboChange(Sender: TObject);
    procedure TrackChange(Sender: TObject);
    procedure SpinChange(Sender: TObject);
    procedure ColorChanged(Sender: TObject);
    procedure SeedChange(Sender: TObject);
    procedure NewSeedClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure PauseClick(Sender: TObject);
    procedure SavePngClick(Sender: TObject);
    procedure SaveIniClick(Sender: TObject);
    procedure LoadIniClick(Sender: TObject);
    procedure CopyInfoClick(Sender: TObject);
    procedure ParamChanged(Index: integer);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  SideWidth = 450;
  RowH = 26;
  ThumbW = 120;
  ThumbH = 68;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := 'Hex Background - camera fly-through   (mouse steers, R new seed, S save PNG, Space pause, F2 panel, F11 fullscreen)';
  ShowHint := True;
  FHex := THexBackground.Create;
  FFrame := TBGRABitmap.Create(16, 16, BGRABlack);

  FSide := TPanel.Create(Self);
  FSide.Parent := Self;
  FSide.Align := alRight;
  FSide.Width := SideWidth;
  FSide.BevelOuter := bvNone;
  FSide.ParentColor := False;
  FSide.Color := clBtnFace;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alRight;
  FSplitter.Width := 5;

  FView := TPaintBox.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.OnPaint := @ViewPaint;
  FView.OnMouseDown := @ViewMouseDown;
  FView.OnMouseMove := @ViewMouseMove;
  FView.OnMouseLeave := @ViewMouseLeave;

  BuildSidePanel;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 15;
  FTimer.OnTimer := @TimerTick;
  FLastTick := GetTickCount64;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FTimer.Enabled := False;
  FFrame.Free;
  FHex.Free;
end;

{ ------------------------------------------------------------ side panel }

function TMainForm.AddButton(AParent: TWinControl; const ACaption: string;
  X, Y, W: integer; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 25);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
end;

function TMainForm.AddLabel(AParent: TWinControl; const ACaption: string; X, Y: integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := ACaption;
end;

procedure TMainForm.BuildSidePanel;
var
  TopBar: TPanel;
  i: integer;
  Tab: TTabSheet;
begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := FSide;
  TopBar.Align := alTop;
  TopBar.Height := 104;
  TopBar.BevelOuter := bvNone;

  AddLabel(TopBar, 'View:', 8, 12);
  FViewCombo := TComboBox.Create(Self);
  FViewCombo.Parent := TopBar;
  FViewCombo.SetBounds(52, 8, 200, 23);
  FViewCombo.Style := csDropDownList;
  FViewCombo.Items.Add('Composite (final image)');
  for i := 0 to PassCount - 1 do
    FViewCombo.Items.Add(Format('%d  %s (alone)', [i, FHex.Passes[i]^.Name]));
  FViewCombo.ItemIndex := 0;
  FViewCombo.OnChange := @ViewComboChange;
  FViewCombo.Hint := 'Show the final image, or one pass alone over a checkerboard.';
  FPauseBtn := AddButton(TopBar, 'Pause', 260, 7, 80, @PauseClick);
  FPauseBtn.Hint := 'Freeze the camera and particles (Space).';

  AddLabel(TopBar, 'Seed:', 8, 42);
  FSeedEdit := TSpinEdit.Create(Self);
  FSeedEdit.Parent := TopBar;
  FSeedEdit.SetBounds(52, 38, 110, 23);
  FSeedEdit.MaxValue := MaxInt;
  FSeedEdit.Value := FHex.Seed;
  FSeedEdit.OnChange := @SeedChange;
  FSeedEdit.Hint := 'Random seed of the hexagon field and particles.';
  AddButton(TopBar, 'New seed', 170, 37, 82, @NewSeedClick);
  AddButton(TopBar, 'Reset all', 260, 37, 80, @ResetClick).Hint := 'Restore every parameter to its default.';

  AddButton(TopBar, 'Save PNG', 8, 70, 90, @SavePngClick).Hint :=
    'Save the current frame at full window resolution.';
  AddButton(TopBar, 'Save settings...', 104, 70, 112, @SaveIniClick);
  AddButton(TopBar, 'Load settings...', 222, 70, 118, @LoadIniClick);

  FStatus := TLabel.Create(Self);
  FStatus.Parent := FSide;
  FStatus.Align := alBottom;
  FStatus.BorderSpacing.Around := 6;
  FStatus.WordWrap := True;
  FStatus.Caption := '';

  FPages := TPageControl.Create(Self);
  FPages.Parent := FSide;
  FPages.Align := alClient;
  FPassTab := FPages.AddTabSheet;
  BuildPassesTab(FPassTab);
  Tab := FPages.AddTabSheet;
  BuildParamsTab(Tab);
  FInfoTab := FPages.AddTabSheet;
  BuildInfoTab(FInfoTab);
  FPages.ActivePageIndex := 0;
end;

procedure TMainForm.BuildPassesTab(Tab: TTabSheet);
var
  Box: TScrollBox;
  i: integer;
  P: TPanel;
begin
  Tab.Caption := 'Passes';
  Box := TScrollBox.Create(Self);
  Box.Parent := Tab;
  Box.Align := alClient;
  Box.HorzScrollBar.Visible := False;
  Box.VertScrollBar.Tracking := True;

  // top of the list = drawn last (on top)
  for i := PassCount - 1 downto 0 do
  begin
    P := TPanel.Create(Self);
    P.Parent := Box;
    P.Top := (PassCount - i) * 1000;
    P.Align := alTop;
    P.Height := ThumbH + 10;
    P.BevelOuter := bvNone;
    P.BorderSpacing.Bottom := 1;
    P.Tag := i;
    P.OnClick := @PassRowClick;
    P.Cursor := crHandPoint;
    FPassRows[i].Panel := P;

    with FPassRows[i] do
    begin
      Check := TCheckBox.Create(Self);
      Check.Parent := P;
      Check.SetBounds(6, (ThumbH + 10 - 20) div 2, 20, 20);
      Check.Checked := FHex.Passes[i]^.Enabled;
      Check.Tag := i;
      Check.OnClick := @PassCheckClick;
      Check.Hint := 'Include this pass in the final image.';

      Thumb := TImage.Create(Self);
      Thumb.Parent := P;
      Thumb.SetBounds(28, 5, ThumbW, ThumbH);
      Thumb.Tag := i;
      Thumb.OnClick := @PassRowClick;

      Title := TLabel.Create(Self);
      Title.Parent := P;
      Title.Left := ThumbW + 36;
      Title.Top := 4;
      Title.Font.Style := [fsBold];
      Title.Caption := Format('%d. %s', [i, FHex.Passes[i]^.Name]);
      Title.Tag := i;
      Title.OnClick := @PassRowClick;

      Stats := TLabel.Create(Self);
      Stats.Parent := P;
      Stats.AutoSize := False;
      Stats.WordWrap := True;
      Stats.SetBounds(ThumbW + 36, 22, SideWidth - ThumbW - 70, ThumbH - 16);
      Stats.Tag := i;
      Stats.OnClick := @PassRowClick;
      Stats.Hint := FHex.Passes[i]^.Technique;
      Thumb.Hint := 'Click to view alone.'#13 + FHex.Passes[i]^.Technique;
    end;
  end;
end;

procedure TMainForm.BuildParamsTab(Tab: TTabSheet);
var
  Box: TScrollBox;
  GB: TGroupBox;
  i, k, n, GroupNo, Y: integer;
  P: TParamInfo;
  L: TLabel;
  Live: string;
begin
  Tab.Caption := 'Parameters';
  Box := TScrollBox.Create(Self);
  Box.Parent := Tab;
  Box.Align := alClient;
  Box.HorzScrollBar.Visible := False;
  Box.VertScrollBar.Tracking := True;
  Box.VertScrollBar.Increment := RowH;

  SetLength(FParamRows, Length(FHex.Params));
  i := 0;
  GroupNo := 0;
  while i <= High(FHex.Params) do
  begin
    n := 0;
    while (i + n <= High(FHex.Params)) and (FHex.Params[i + n].Group = FHex.Params[i].Group) do
      Inc(n);

    GB := TGroupBox.Create(Self);
    GB.Parent := Box;
    GB.Top := (GroupNo + 1) * 10000;
    GB.Align := alTop;
    GB.BorderSpacing.Around := 4;
    GB.Caption := ' ' + FHex.Params[i].Group + ' ';
    GB.Height := n * RowH + 26;
    Inc(GroupNo);

    for k := 0 to n - 1 do
    begin
      P := FHex.Params[i + k];
      Y := 2 + k * RowH;
      if P.Effects = [] then Live := #13'Applies on the next frame.'
      else Live := #13'Rebuilds a cache when you stop changing it.';

      L := AddLabel(GB, P.Name, 8, Y + 4);
      L.Hint := P.Hint + Live;

      if P.Kind = pkFloat then
      begin
        FParamRows[i + k].Track := TTrackBar.Create(Self);
        with FParamRows[i + k].Track do
        begin
          Parent := GB;
          SetBounds(140, Y, 180, 24);
          Min := 0;
          Max := 1000;
          TickStyle := tsNone;
          PageSize := 50;
          Tag := i + k;
          Hint := P.Hint + Live;
          OnChange := @TrackChange;
        end;
        FParamRows[i + k].Spin := TFloatSpinEdit.Create(Self);
        with FParamRows[i + k].Spin do
        begin
          Parent := GB;
          SetBounds(326, Y, 84, 23);
          DecimalPlaces := P.Decimals;
          MinValue := P.Min;
          MaxValue := P.Max;
          Increment := Power(10, -P.Decimals);
          Tag := i + k;
          Hint := Format('%s'#13'Range %g .. %g', [P.Hint, P.Min, P.Max]) + Live;
          OnChange := @SpinChange;
        end;
      end
      else
      begin
        FParamRows[i + k].ColorBtn := TColorButton.Create(Self);
        with FParamRows[i + k].ColorBtn do
        begin
          Parent := GB;
          SetBounds(140, Y, 120, 24);
          Tag := i + k;
          Hint := P.Hint + Live;
          OnColorChanged := @ColorChanged;
        end;
        AddLabel(GB, 'alpha', 286, Y + 4);
        FParamRows[i + k].Alpha := TSpinEdit.Create(Self);
        with FParamRows[i + k].Alpha do
        begin
          Parent := GB;
          SetBounds(326, Y, 84, 23);
          MinValue := 0;
          MaxValue := 255;
          Tag := i + k;
          Hint := 'Alpha 0..255 of this colour.';
          OnChange := @ColorChanged;
        end;
      end;
    end;
    Inc(i, n);
  end;
  RefreshParamControls;
end;

procedure TMainForm.BuildInfoTab(Tab: TTabSheet);
var
  Bar: TPanel;
begin
  Tab.Caption := 'Info';
  Bar := TPanel.Create(Self);
  Bar.Parent := Tab;
  Bar.Align := alBottom;
  Bar.Height := 34;
  Bar.BevelOuter := bvNone;
  AddButton(Bar, 'Copy report', 6, 4, 110, @CopyInfoClick);

  FInfoMemo := TMemo.Create(Self);
  FInfoMemo.Parent := Tab;
  FInfoMemo.Align := alClient;
  FInfoMemo.ReadOnly := True;
  FInfoMemo.ScrollBars := ssBoth;
  FInfoMemo.WordWrap := False;
  FInfoMemo.Font.Name := 'Consolas';
  FInfoMemo.Font.Size := 9;
end;

{ --------------------------------------------------------------- refresh }

function TMainForm.CompositePasses: TPassSet;
var
  i: integer;
begin
  Result := [];
  for i := 0 to PassCount - 1 do
    if FHex.Passes[i]^.Enabled then Include(Result, i);
end;

procedure TMainForm.RefreshParamControls;
var
  i: integer;
  P: TParamInfo;
begin
  FUpdating := True;
  try
    for i := 0 to High(FParamRows) do
    begin
      P := FHex.Params[i];
      if P.Kind = pkFloat then
      begin
        FParamRows[i].Spin.Value := P.PValue^;
        FParamRows[i].Track.Position := Round((P.PValue^ - P.Min) / (P.Max - P.Min) * 1000);
      end
      else
      begin
        FParamRows[i].ColorBtn.ButtonColor := BGRAToColor(P.PColor^);
        FParamRows[i].Alpha.Value := P.PColor^.alpha;
      end;
    end;
    FSeedEdit.Value := FHex.Seed;
    for i := 0 to PassCount - 1 do
      FPassRows[i].Check.Checked := FHex.Passes[i]^.Enabled;
  finally
    FUpdating := False;
  end;
end;

procedure TMainForm.RefreshPassRows(WithThumbs: boolean);
var
  i: integer;
  T: TBGRABitmap;
  B: TBitmap;
  Sel: boolean;
begin
  T := TBGRABitmap.Create(ThumbW, ThumbH);
  try
    for i := 0 to PassCount - 1 do
    begin
      if WithThumbs then
      begin
        // each pass rendered alone, at thumbnail size, with the live camera
        FHex.Render(T, ThumbW, ThumbH, [i], True, False);
        B := TBitmap.Create;     // a new TBitmap per row: Assign shares image data
        try
          B.SetSize(ThumbW, ThumbH);
          T.Draw(B.Canvas, 0, 0, True);
          FPassRows[i].Thumb.Picture.Assign(B);
        finally
          B.Free;
        end;
      end;
      with FHex.Passes[i]^ do
        if (i = psGlow) and Enabled and FHex.Passes[psFront]^.Enabled and (FViewCombo.ItemIndex <= 0) then
          FPassRows[i].Stats.Caption := Format('%d halos'#13'baked into the front-face sprites'#13 +
            '(time counted in pass 5)', [Items])
        else
          FPassRows[i].Stats.Caption := Format('%d items drawn'#13'%.2f ms per frame'#13'%s',
            [Items, TimeMs, BoolToStr(Enabled, 'in the final image', 'switched off')]);
      Sel := FViewCombo.ItemIndex = i + 1;
      if Sel then FPassRows[i].Panel.Color := clHighlight else FPassRows[i].Panel.Color := clDefault;
      if Sel then FPassRows[i].Title.Font.Color := clHighlightText else FPassRows[i].Title.Font.Color := clDefault;
      FPassRows[i].Stats.Font.Color := FPassRows[i].Title.Font.Color;
    end;
  finally
    T.Free;
  end;
end;

procedure TMainForm.RenderFrame;
var
  W, H, i: integer;
begin
  W := Max(16, Round(FView.Width * FHex.Settings^.RenderScale));
  H := Max(16, Round(FView.Height * FHex.Settings^.RenderScale));
  i := FViewCombo.ItemIndex - 1;
  if i < 0 then
    FHex.Render(FFrame, W, H, CompositePasses, False, True)
  else
    FHex.Render(FFrame, W, H, [i], True, True);
  FView.Invalidate;
end;

{ ---------------------------------------------------------------- events }

procedure TMainForm.TimerTick(Sender: TObject);
var
  Now: QWord;
begin
  Now := GetTickCount64;
  // caches are rebuilt once the user stops dragging a slider
  if (FPending <> []) and (Now - FPendingAt > 150) then
  begin
    FHex.Invalidate(FPending);
    FPending := [];
  end;
  if FPaused then
    FHex.Animate(0)
  else
    FHex.Animate(Min(0.1, (Now - FLastTick) / 1000));
  FLastTick := Now;
  RenderFrame;
  Inc(FFrames);

  if Now - FLastStatus >= 500 then
  begin
    FFps := FFrames * 1000 / (Now - FLastStatus);
    FFrames := 0;
    FLastStatus := Now;
    with FHex.Stats do
      FStatus.Caption := Format('%.0f fps  |  frame %.1f ms at %d x %d  |  %d hexagons  |  %d sprites (%.0f MB)  |  camera z %.1f',
        [FFps, FrameMs, FFrame.Width, FFrame.Height, Visible, FHex.SpriteCount,
         FHex.SpriteBytes / 1048576, FHex.CameraPos.Z]);
    if FPages.ActivePage = FPassTab then
      RefreshPassRows(Now - FLastThumbs >= 1500);
    if Now - FLastThumbs >= 1500 then FLastThumbs := Now;
  end;
  if (FPages.ActivePage = FInfoTab) and (Now - FLastInfo >= 1000) then
  begin
    FLastInfo := Now;
    FInfoMemo.Lines.BeginUpdate;
    try
      FInfoMemo.Lines.Text := FHex.Report(FFps);
    finally
      FInfoMemo.Lines.EndUpdate;
    end;
  end;
end;

procedure TMainForm.ViewPaint(Sender: TObject);
begin
  if (FFrame.Width = FView.Width) and (FFrame.Height = FView.Height) then
    FFrame.Draw(FView.Canvas, 0, 0, True)
  else
    FFrame.Draw(FView.Canvas, Rect(0, 0, FView.Width, FView.Height), True);
end;

procedure TMainForm.ViewMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
begin
  ActiveControl := nil;     // hand the hotkeys back to the form
end;

procedure TMainForm.ViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
begin
  if (FView.Width > 0) and (FView.Height > 0) then
    FHex.SetMouse(X / FView.Width * 2 - 1, Y / FView.Height * 2 - 1);
end;

procedure TMainForm.ViewMouseLeave(Sender: TObject);
begin
  FHex.SetMouse(0, 0);
end;

procedure TMainForm.PassCheckClick(Sender: TObject);
begin
  if FUpdating then Exit;
  FHex.Passes[TCheckBox(Sender).Tag]^.Enabled := TCheckBox(Sender).Checked;
  RefreshPassRows(False);
end;

procedure TMainForm.PassRowClick(Sender: TObject);
var
  i: integer;
begin
  i := TControl(Sender).Tag + 1;
  if FViewCombo.ItemIndex = i then i := 0;    // click again = back to composite
  FViewCombo.ItemIndex := i;
  ViewComboChange(nil);
end;

procedure TMainForm.ViewComboChange(Sender: TObject);
begin
  RefreshPassRows(False);
end;

procedure TMainForm.ParamChanged(Index: integer);
begin
  if FHex.Params[Index].Effects = [] then Exit;     // read live every frame
  FPending := FPending + FHex.Params[Index].Effects;
  FPendingAt := GetTickCount64;
end;

procedure TMainForm.TrackChange(Sender: TObject);
var
  i: integer;
  P: TParamInfo;
begin
  if FUpdating then Exit;
  i := TTrackBar(Sender).Tag;
  P := FHex.Params[i];
  P.PValue^ := RoundTo(P.Min + TTrackBar(Sender).Position / 1000 * (P.Max - P.Min), -P.Decimals);
  FUpdating := True;
  FParamRows[i].Spin.Value := P.PValue^;
  FUpdating := False;
  ParamChanged(i);
end;

procedure TMainForm.SpinChange(Sender: TObject);
var
  i: integer;
  P: TParamInfo;
begin
  if FUpdating then Exit;
  i := TFloatSpinEdit(Sender).Tag;
  P := FHex.Params[i];
  P.PValue^ := TFloatSpinEdit(Sender).Value;
  FUpdating := True;
  FParamRows[i].Track.Position := Round((P.PValue^ - P.Min) / (P.Max - P.Min) * 1000);
  FUpdating := False;
  ParamChanged(i);
end;

procedure TMainForm.ColorChanged(Sender: TObject);
var
  i: integer;
begin
  if FUpdating then Exit;
  i := TControl(Sender).Tag;
  FHex.Params[i].PColor^ := ColorToBGRA(ColorToRGB(FParamRows[i].ColorBtn.ButtonColor),
    FParamRows[i].Alpha.Value);
  ParamChanged(i);
end;

procedure TMainForm.SeedChange(Sender: TObject);
begin
  if FUpdating then Exit;
  FHex.SetSeed(FSeedEdit.Value);
end;

procedure TMainForm.NewSeedClick(Sender: TObject);
begin
  Randomize;
  FSeedEdit.Value := Random(MaxInt);     // triggers SeedChange
end;

procedure TMainForm.ResetClick(Sender: TObject);
begin
  FHex.ResetDefaults;
  FPending := [];
  RefreshParamControls;
end;

procedure TMainForm.PauseClick(Sender: TObject);
begin
  FPaused := not FPaused;
  if FPaused then FPauseBtn.Caption := 'Play' else FPauseBtn.Caption := 'Pause';
end;

procedure TMainForm.SavePngClick(Sender: TObject);
var
  FileName: string;
  Bmp: TBGRABitmap;
begin
  Bmp := TBGRABitmap.Create(1, 1);
  try
    FHex.Render(Bmp, FView.Width, FView.Height, CompositePasses, False, False);
    FileName := ExtractFilePath(Application.ExeName) +
      Format('hexbg_%dx%d_%d_t%.0f.png', [Bmp.Width, Bmp.Height, FHex.Seed, FHex.Time]);
    Bmp.SaveToFile(FileName);
  finally
    Bmp.Free;
  end;
  FStatus.Caption := 'Saved ' + FileName;
end;

procedure TMainForm.SaveIniClick(Sender: TObject);
begin
  with TSaveDialog.Create(Self) do
  try
    Filter := 'Hex background settings (*.ini)|*.ini';
    DefaultExt := 'ini';
    FileName := 'hexbg.ini';
    InitialDir := ExtractFilePath(Application.ExeName);
    if Execute then
      FHex.SaveToIni(FileName);
  finally
    Free;
  end;
end;

procedure TMainForm.LoadIniClick(Sender: TObject);
begin
  with TOpenDialog.Create(Self) do
  try
    Filter := 'Hex background settings (*.ini)|*.ini';
    InitialDir := ExtractFilePath(Application.ExeName);
    if Execute then
    begin
      FHex.LoadFromIni(FileName);
      FPending := [];
      RefreshParamControls;
    end;
  finally
    Free;
  end;
end;

procedure TMainForm.CopyInfoClick(Sender: TObject);
begin
  Clipboard.AsText := FHex.Report(FFps);
end;

procedure TMainForm.ToggleFullScreen;
begin
  FFullScreen := not FFullScreen;
  if FFullScreen then
  begin
    FSavedBounds := BoundsRect;
    BorderStyle := bsNone;
    BoundsRect := Monitor.BoundsRect;
  end
  else
  begin
    BorderStyle := bsSizeable;
    BoundsRect := FSavedBounds;
  end;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F2:
      begin
        FSide.Visible := not FSide.Visible;
        FSplitter.Visible := FSide.Visible;
        if FSide.Visible then FSplitter.Left := FSide.Left - 1;
      end;
    VK_F11:
      ToggleFullScreen;
    VK_ESCAPE:
      if FFullScreen then ToggleFullScreen else ActiveControl := nil;
  else
    // letter hotkeys only when no edit / slider has the focus
    if ActiveControl <> nil then Exit;
    case Key of
      VK_R: NewSeedClick(nil);
      VK_S: SavePngClick(nil);
      VK_SPACE: PauseClick(nil);
    else
      Exit;
    end;
  end;
  Key := 0;
end;

end.
