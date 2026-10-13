unit UMain;

{ Window: live hex background on the left, inspector panel on the right.

  Inspector tabs
    Layers     - every render stage with thumbnail, on/off box, blend mode,
                 item count and render time. Click a row to view it alone.
    Parameters - every value of THexSettings, generated from Hex.Params:
                 slider + number box (or colour button + alpha). Changing a
                 value re-renders only the stages it affects.
    Info       - full text report: sizes, derived values, stages, techniques
                 and all parameter values.

  Keys (when no edit box has focus): R new seed, S save PNG, Space pause,
  F2 show/hide panel, F11 fullscreen, Esc leave fullscreen / unfocus. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, StdCtrls, ComCtrls,
  Spin, Dialogs, Clipbrd, LCLType, BGRABitmap, BGRABitmapTypes, UHexBackground;

type
  TStageRow = record
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
    FViewCombo: TComboBox;
    FSeedEdit: TSpinEdit;
    FPauseBtn: TButton;
    FStatus: TLabel;
    FInfoMemo: TMemo;
    FStageRows: array[0..StageCount - 1] of TStageRow;
    FParamRows: array of TParamRow;
    FUpdating, FNeedUpdate, FPaused, FFullScreen: boolean;
    FDirtyAt, FLastTick: QWord;
    FSavedBounds: TRect;
    procedure BuildSidePanel;
    procedure BuildLayersTab(Tab: TTabSheet);
    procedure BuildParamsTab(Tab: TTabSheet);
    procedure BuildInfoTab(Tab: TTabSheet);
    function AddButton(AParent: TWinControl; const ACaption: string;
      X, Y, W: integer; AOnClick: TNotifyEvent): TButton;
    function AddLabel(AParent: TWinControl; const ACaption: string; X, Y: integer): TLabel;
    procedure ScheduleUpdate;
    procedure DoUpdate;
    procedure RefreshStageRows;
    procedure RefreshParamControls;
    procedure RenderFrame;
    procedure ToggleFullScreen;
    procedure TimerTick(Sender: TObject);
    procedure ViewPaint(Sender: TObject);
    procedure ViewResize(Sender: TObject);
    procedure ViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure StageCheckClick(Sender: TObject);
    procedure StageRowClick(Sender: TObject);
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
  Caption := 'Hex Background - BGRABitmap   (R new seed, S save PNG, Space pause, F2 panel, F11 fullscreen)';
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
  FView.OnResize := @ViewResize;
  FView.OnMouseDown := @ViewMouseDown;

  BuildSidePanel;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 33;
  FTimer.OnTimer := @TimerTick;
  FLastTick := GetTickCount64;
  ScheduleUpdate;
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
  Pages: TPageControl;
  i: integer;
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
  for i := 0 to StageCount - 1 do
    FViewCombo.Items.Add(Format('%d  %s (alone)', [i, FHex.Stages[i]^.Name]));
  FViewCombo.ItemIndex := 0;
  FViewCombo.OnChange := @ViewComboChange;
  FViewCombo.Hint := 'Show the final image, or one stage alone (transparent parts over a checkerboard).';
  FPauseBtn := AddButton(TopBar, 'Pause', 260, 7, 80, @PauseClick);

  AddLabel(TopBar, 'Seed:', 8, 42);
  FSeedEdit := TSpinEdit.Create(Self);
  FSeedEdit.Parent := TopBar;
  FSeedEdit.SetBounds(52, 38, 110, 23);
  FSeedEdit.MaxValue := MaxInt;
  FSeedEdit.Value := FHex.Seed;
  FSeedEdit.OnChange := @SeedChange;
  FSeedEdit.Hint := 'Random seed of the whole layout.';
  AddButton(TopBar, 'New seed', 170, 37, 82, @NewSeedClick);
  AddButton(TopBar, 'Reset all', 260, 37, 80, @ResetClick).Hint := 'Restore every parameter to its default.';

  AddButton(TopBar, 'Save PNG', 8, 70, 90, @SavePngClick);
  AddButton(TopBar, 'Save settings...', 104, 70, 112, @SaveIniClick);
  AddButton(TopBar, 'Load settings...', 222, 70, 118, @LoadIniClick);

  FStatus := TLabel.Create(Self);
  FStatus.Parent := FSide;
  FStatus.Align := alBottom;
  FStatus.BorderSpacing.Around := 6;
  FStatus.WordWrap := True;
  FStatus.Caption := '';

  Pages := TPageControl.Create(Self);
  Pages.Parent := FSide;
  Pages.Align := alClient;
  BuildLayersTab(Pages.AddTabSheet);
  BuildParamsTab(Pages.AddTabSheet);
  BuildInfoTab(Pages.AddTabSheet);
  Pages.ActivePageIndex := 0;
end;

procedure TMainForm.BuildLayersTab(Tab: TTabSheet);
var
  Box: TScrollBox;
  i: integer;
  P: TPanel;
begin
  Tab.Caption := 'Layers';
  Box := TScrollBox.Create(Self);
  Box.Parent := Tab;
  Box.Align := alClient;
  Box.HorzScrollBar.Visible := False;
  Box.VertScrollBar.Tracking := True;

  // top of the list = top of the picture, so list stages in reverse order
  for i := StageCount - 1 downto 0 do
  begin
    P := TPanel.Create(Self);
    P.Parent := Box;
    P.Top := (StageCount - i) * 1000;
    P.Align := alTop;
    P.Height := ThumbH + 10;
    P.BevelOuter := bvNone;
    P.BorderSpacing.Bottom := 1;
    P.Tag := i;
    P.OnClick := @StageRowClick;
    P.Cursor := crHandPoint;
    FStageRows[i].Panel := P;

    with FStageRows[i] do
    begin
      Check := TCheckBox.Create(Self);
      Check.Parent := P;
      Check.SetBounds(6, (ThumbH + 10 - 20) div 2, 20, 20);
      Check.Checked := FHex.Stages[i]^.Enabled;
      Check.Tag := i;
      Check.OnClick := @StageCheckClick;
      Check.Hint := 'Include this stage in the final image.';

      Thumb := TImage.Create(Self);
      Thumb.Parent := P;
      Thumb.SetBounds(28, 5, ThumbW, ThumbH);
      Thumb.Tag := i;
      Thumb.OnClick := @StageRowClick;
      Thumb.Hint := 'Click to view this stage alone.';

      Title := TLabel.Create(Self);
      Title.Parent := P;
      Title.Left := ThumbW + 36;
      Title.Top := 4;
      Title.Font.Style := [fsBold];
      Title.Tag := i;
      Title.OnClick := @StageRowClick;

      Stats := TLabel.Create(Self);
      Stats.Parent := P;
      Stats.AutoSize := False;
      Stats.WordWrap := True;
      Stats.SetBounds(ThumbW + 36, 22, SideWidth - ThumbW - 70, ThumbH - 16);
      Stats.Tag := i;
      Stats.OnClick := @StageRowClick;
      Stats.ShowHint := True;
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
    // count rows of this group
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

      L := AddLabel(GB, P.Name, 8, Y + 4);
      L.Hint := P.Hint;

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
          Hint := P.Hint;
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
          Hint := Format('%s'#13'Range %g .. %g', [P.Hint, P.Min, P.Max]);
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
          Hint := P.Hint;
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
    for i := 0 to StageCount - 1 do
      FStageRows[i].Check.Checked := FHex.Stages[i]^.Enabled;
  finally
    FUpdating := False;
  end;
end;

procedure TMainForm.RefreshStageRows;
var
  i: integer;
  T: TBGRABitmap;
  B: TBitmap;
  S: PStage;
begin
  T := TBGRABitmap.Create(ThumbW, ThumbH);
  try
    for i := 0 to StageCount - 1 do
    begin
      S := FHex.Stages[i];
      FHex.DrawThumbnail(T, i);
      // a new TBitmap per row: Assign shares the image data with the source
      B := TBitmap.Create;
      try
        B.SetSize(ThumbW, ThumbH);
        T.Draw(B.Canvas, 0, 0, True);
        FStageRows[i].Thumb.Picture.Assign(B);
      finally
        B.Free;
      end;
      FStageRows[i].Title.Caption := Format('%d. %s', [i, S^.Name]);
      if S^.Additive then
        FStageRows[i].Stats.Caption := Format('%s'#13'%s'#13'rendered with the hex stage above',
          [FHex.StageSummary(i), S^.Blend])
      else
        FStageRows[i].Stats.Caption := Format('%s'#13'%s'#13'render %d ms',
          [FHex.StageSummary(i), S^.Blend, S^.TimeMs]);
      FStageRows[i].Stats.Hint := S^.Technique;
      FStageRows[i].Thumb.Hint := 'Click to view alone.'#13 + S^.Technique;
      if FViewCombo.ItemIndex = i + 1 then
        FStageRows[i].Panel.Color := clHighlight
      else
        FStageRows[i].Panel.Color := clDefault;
      if FViewCombo.ItemIndex = i + 1 then
        FStageRows[i].Title.Font.Color := clHighlightText
      else
        FStageRows[i].Title.Font.Color := clDefault;
      FStageRows[i].Stats.Font.Color := FStageRows[i].Title.Font.Color;
    end;
  finally
    T.Free;
  end;
end;

procedure TMainForm.ScheduleUpdate;
begin
  FNeedUpdate := True;
  FDirtyAt := GetTickCount64;
end;

procedure TMainForm.DoUpdate;
var
  t0, Ms: QWord;
  i, Hexes: integer;
begin
  FNeedUpdate := False;
  Screen.Cursor := crHourGlass;
  try
    t0 := GetTickCount64;
    FHex.SetSize(FView.Width, FView.Height);
    FHex.Update;
    Ms := GetTickCount64 - t0;
  finally
    Screen.Cursor := crDefault;
  end;
  RefreshStageRows;
  FInfoMemo.Lines.Text := FHex.Report;
  Hexes := 0;
  for i := stFar to stNear do
    if not Odd(i - stFar) then Inc(Hexes, FHex.Stages[i]^.Items);
  FStatus.Caption := Format('%d x %d px  |  update %d ms (compose %d ms)  |  %d hexagons  |  hex radius %.1f px',
    [FHex.Width, FHex.Height, Ms, FHex.ComposeMs, Hexes, FHex.Scale]);
  RenderFrame;
end;

procedure TMainForm.RenderFrame;
begin
  if FViewCombo.ItemIndex <= 0 then
    FHex.DrawFrame(FFrame)
  else
    FHex.DrawStageView(FFrame, FViewCombo.ItemIndex - 1);
  FView.Invalidate;
end;

{ ---------------------------------------------------------------- events }

procedure TMainForm.TimerTick(Sender: TObject);
var
  Now: QWord;
begin
  Now := GetTickCount64;
  // re-render after the user stopped dragging / resizing for a moment
  if FNeedUpdate and (Now - FDirtyAt > 120) then
  begin
    DoUpdate;
    FLastTick := GetTickCount64;
    Exit;
  end;
  if FPaused then
  begin
    FLastTick := Now;
    Exit;
  end;
  FHex.Animate(Min(0.1, (Now - FLastTick) / 1000));
  FLastTick := Now;
  RenderFrame;
end;

procedure TMainForm.ViewPaint(Sender: TObject);
begin
  if (FFrame.Width = FView.Width) and (FFrame.Height = FView.Height) then
    FFrame.Draw(FView.Canvas, 0, 0, True)
  else
    // stretch the last frame while the window is being resized
    FFrame.Draw(FView.Canvas, Rect(0, 0, FView.Width, FView.Height), True);
end;

procedure TMainForm.ViewResize(Sender: TObject);
begin
  ScheduleUpdate;
end;

procedure TMainForm.ViewMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
begin
  ActiveControl := nil;     // hand the hotkeys back to the form
end;

procedure TMainForm.StageCheckClick(Sender: TObject);
begin
  if FUpdating then Exit;
  FHex.Stages[TCheckBox(Sender).Tag]^.Enabled := TCheckBox(Sender).Checked;
  FHex.Compose;
  FInfoMemo.Lines.Text := FHex.Report;
  RenderFrame;
end;

procedure TMainForm.StageRowClick(Sender: TObject);
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
  RefreshStageRows;
  RenderFrame;
end;

procedure TMainForm.ParamChanged(Index: integer);
begin
  FHex.MarkDirty(FHex.Params[Index].Stages);
  ScheduleUpdate;
end;

procedure TMainForm.TrackChange(Sender: TObject);
var
  i: integer;
  P: TParamInfo;
begin
  if FUpdating then Exit;
  i := TTrackBar(Sender).Tag;
  P := FHex.Params[i];
  P.PValue^ := P.Min + TTrackBar(Sender).Position / 1000 * (P.Max - P.Min);
  P.PValue^ := RoundTo(P.PValue^, -P.Decimals);
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
  ScheduleUpdate;
end;

procedure TMainForm.NewSeedClick(Sender: TObject);
begin
  Randomize;
  FSeedEdit.Value := Random(MaxInt);     // triggers SeedChange
end;

procedure TMainForm.ResetClick(Sender: TObject);
begin
  FHex.ResetDefaults;
  RefreshParamControls;
  ScheduleUpdate;
end;

procedure TMainForm.PauseClick(Sender: TObject);
begin
  FPaused := not FPaused;
  if FPaused then FPauseBtn.Caption := 'Play' else FPauseBtn.Caption := 'Pause';
end;

procedure TMainForm.SavePngClick(Sender: TObject);
var
  FileName: string;
begin
  FileName := ExtractFilePath(Application.ExeName) +
    Format('hexbg_%dx%d_%d.png', [FFrame.Width, FFrame.Height, FHex.Seed]);
  FFrame.SaveToFile(FileName);
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
    begin
      FHex.SaveToIni(FileName);
      FStatus.Caption := 'Saved ' + FileName;
    end;
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
      RefreshParamControls;
      ScheduleUpdate;
    end;
  finally
    Free;
  end;
end;

procedure TMainForm.CopyInfoClick(Sender: TObject);
begin
  Clipboard.AsText := FInfoMemo.Lines.Text;
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
