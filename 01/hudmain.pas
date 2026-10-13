unit HUDMain;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}MMSystem,{$ENDIF} Classes, SysUtils, Math, Forms, Controls, Graphics,
  LCLType, LCLIntf, HUDRender;

type

  { TSciFiHUDForm }

  TSciFiHUDForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormPaint(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    FRenderer: THUDRenderer;
    FStart: double;          // ms, high resolution clock
    FPausedAt: single;
    FNextFrame: double;      // ms, when the next frame is due
    FUncapped: boolean;      // V key: render as fast as possible
    FFrames: integer;        // FPS counter
    FFpsStart: double;
    FPartial: boolean;       // next paint only needs the dirty rects
    FLastW, FLastH: integer; // size of the last full paint
    function Elapsed: single;
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure RunBench(const AFile: string; W, H: integer);
  public
    procedure EraseBackground(DC: HDC); override;
  end;

var
  SciFiHUDForm: TSciFiHUDForm;

implementation

{$R *.lfm}

const
  TargetFPS = 60;
  BaseCaption = 'Sci-Fi HUD Interface Kit  -  BGRABitmap   [Space: pause | V: 60fps cap on/off | S: screenshot | Esc]';

{ TSciFiHUDForm }

procedure TSciFiHUDForm.FormCreate(Sender: TObject);
begin
  // we paint every pixel ourselves: no erase, no extra LCL back buffer
  DoubleBuffered := False;
  FRenderer := THUDRenderer.Create;
  FStart := NowMs;
  FPausedAt := -1;
  FFpsStart := FStart;
  {$IFDEF WINDOWS}
  timeBeginPeriod(1); // Sleep(1) really sleeps ~1 ms instead of 15.6 ms
  {$ENDIF}
  // SciFiHUDKit.exe --bench report.txt [W H] : time 200 frames per stage and quit
  if (ParamCount >= 2) and (ParamStr(1) = '--bench') then
  begin
    // optional 5th arg: multithreaded compose -1 auto (default), 0 off, 1 on
    MTMode := StrToIntDef(ParamStr(5), -1);
    RunBench(ParamStr(2), StrToIntDef(ParamStr(3), DesignW), StrToIntDef(ParamStr(4), DesignH));
    Application.Terminate;
    Exit;
  end;
  // SciFiHUDKit.exe --shot out.png [seconds] : render one frame and quit
  if (ParamCount >= 2) and (ParamStr(1) = '--shot') then
  begin
    FRenderer.Render(DesignW, DesignH, StrToFloatDef(ParamStr(3), 0));
    FRenderer.Output.SaveToFile(ParamStr(2));
    Application.Terminate;
    Exit;
  end;
  // --uncapped : start without the 60 fps cap (same as pressing V)
  FUncapped := (ParamCount >= 1) and (ParamStr(1) = '--uncapped');
  Caption := BaseCaption;
  Application.OnIdle := @AppIdle;
end;

procedure TSciFiHUDForm.RunBench(const AFile: string; W, H: integer);
const
  N = 300;
  Names: array[0..6] of string = ('(clear: in compose)', 'draw left column', 'draw right column',
    'draw loading bars', 'glow downsample', 'glow blur', 'compose');
var
  i: integer;
  t0, total: double;
  L: TStringList;
begin
  t0 := NowMs;
  FRenderer.Render(W, H, 0); // first frame also builds the static cache
  total := NowMs - t0;
  L := TStringList.Create;
  try
    L.Add(Format('Size %dx%d, %d frames', [W, H, N]));
    L.Add(Format('%-22s %7.2f ms  (once per resize)', ['static cache build', total]));
    FillChar(FRenderer.Prof, SizeOf(FRenderer.Prof), 0);
    t0 := NowMs;
    for i := 1 to N do
      FRenderer.Render(W, H, i / 60);
    total := NowMs - t0;
    for i := 0 to High(Names) do
      L.Add(Format('%-22s %7.2f ms', [Names[i], FRenderer.Prof[i] / N]));
    L.Add(Format('%-22s %7.2f ms  (%.0f fps)', ['TOTAL / frame', total / N, 1000 * N / total]));
    L.Add(Format('compose threads: %s', [BoolToStr(FRenderer.UsesThreads, 'pool', 'main only')]));
    L.SaveToFile(AFile);
  finally
    L.Free;
  end;
end;

procedure TSciFiHUDForm.FormDestroy(Sender: TObject);
begin
  Application.OnIdle := nil;
  {$IFDEF WINDOWS}
  timeEndPeriod(1);
  {$ENDIF}
  FRenderer.Free;
end;

procedure TSciFiHUDForm.EraseBackground(DC: HDC);
begin
  // intentionally empty: avoids flicker and a useless full-window fill
end;

function TSciFiHUDForm.Elapsed: single;
begin
  if FPausedAt >= 0 then
    Result := FPausedAt
  else
    Result := (NowMs - FStart) / 1000;
end;

procedure TSciFiHUDForm.AppIdle(Sender: TObject; var Done: Boolean);
var
  now: double;
  i: integer;
  R: TRect;
begin
  if FPausedAt >= 0 then
  begin
    Done := True; // paused: sleep until the next message
    Exit;
  end;
  Done := False;  // keep the idle loop running
  now := NowMs;
  if FUncapped or (now >= FNextFrame) then
  begin
    // fixed cadence; if we fell behind, restart from now instead of bursting
    if now - FNextFrame > 1000 / TargetFPS then
      FNextFrame := now + 1000 / TargetFPS
    else
      FNextFrame := FNextFrame + 1000 / TargetFPS;
    if (FRenderer.DirtyCount > 0) and (ClientWidth = FLastW) and (ClientHeight = FLastH) then
    begin
      // only the animated regions changed: invalidate just those
      FPartial := True;
      for i := 0 to FRenderer.DirtyCount - 1 do
      begin
        R := FRenderer.DirtyRect(i);
        InvalidateRect(Handle, @R, False);
      end;
    end
    else
      Invalidate;
    Update;     // paint synchronously, right now
  end
  else if FNextFrame - now > 1.5 then
    Sleep(1);   // give the CPU back while waiting for the next frame
end;

procedure TSciFiHUDForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_SPACE:  // pause / resume animation
      if FPausedAt >= 0 then
      begin
        FStart := NowMs - FPausedAt * 1000;
        FPausedAt := -1;
      end
      else
        FPausedAt := Elapsed;
    VK_V: FUncapped := not FUncapped;
    VK_S:      // save a screenshot next to the executable
    begin
      FRenderer.Render(ClientWidth, ClientHeight, Elapsed);
      FRenderer.Output.SaveToFile(ExtractFilePath(Application.ExeName) + 'hud_screenshot.png');
    end;
    VK_ESCAPE: Close;
  end;
end;

procedure TSciFiHUDForm.FormPaint(Sender: TObject);
var
  now: double;
  i: integer;
  R, BB, CR: TRect;
begin
  FRenderer.Render(ClientWidth, ClientHeight, Elapsed);
  if FRenderer.Output = nil then Exit;
  if FPartial then
  begin
    // if Windows also asks for an area outside our rects (window uncovered),
    // fall back to a full blit below
    BB := FRenderer.DirtyRect(0);
    for i := 1 to FRenderer.DirtyCount - 1 do
      UnionRect(BB, BB, FRenderer.DirtyRect(i));
    CR := Canvas.ClipRect;
    FPartial := (CR.Left >= BB.Left) and (CR.Top >= BB.Top) and
                (CR.Right <= BB.Right) and (CR.Bottom <= BB.Bottom);
  end;
  if FPartial then
  begin
    // blit only the regions that changed (screen keeps the rest)
    for i := 0 to FRenderer.DirtyCount - 1 do
    begin
      R := FRenderer.DirtyRect(i);
      FRenderer.Output.DrawPart(R, Canvas, R.Left, R.Top, True);
    end;
    FPartial := False;
  end
  else
    FRenderer.Output.Draw(Canvas, 0, 0, True);  // first frame, resize or uncovered
  FLastW := ClientWidth;
  FLastH := ClientHeight;
  // FPS counter in the title bar
  Inc(FFrames);
  now := NowMs;
  if now - FFpsStart >= 1000 then
  begin
    Caption := Format('%s   %.0f fps', [BaseCaption, FFrames * 1000 / (now - FFpsStart)]);
    FFrames := 0;
    FFpsStart := now;
  end;
end;

procedure TSciFiHUDForm.FormResize(Sender: TObject);
begin
  Invalidate;
end;

end.
