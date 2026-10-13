unit UMain;

{ Window that shows THexBackground full-size and animates its sparks.
  Keys: R = new random layout, S = save PNG, Space = pause, F11 = fullscreen,
        Esc = leave fullscreen / quit. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes, UHexBackground;

type

  { TMainForm }

  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormPaint(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    FHex: THexBackground;
    FFrame: TBGRABitmap;
    FTimer: TTimer;
    FSeed: integer;
    FDirty, FPaused, FFullScreen: boolean;
    FResizeAt, FLastTick: QWord;
    FSavedBounds: TRect;
    procedure TimerTick(Sender: TObject);
    procedure Rebuild;
    procedure ToggleFullScreen;
  protected
    procedure EraseBackground(DC: HDC); override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  HelpText = 'Hex Background  -  R: new layout   S: save PNG   Space: pause   F11: fullscreen';

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := HelpText;
  FHex := THexBackground.Create;
  FFrame := TBGRABitmap.Create(1, 1, BGRABlack);
  FSeed := 2026;
  FDirty := True;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 33;
  FTimer.OnTimer := @TimerTick;
  FLastTick := GetTickCount64;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FFrame.Free;
  FHex.Free;
end;

procedure TMainForm.EraseBackground(DC: HDC);
begin
  // everything is painted in FormPaint; skipping the erase avoids flicker
end;

procedure TMainForm.Rebuild;
begin
  if (ClientWidth < 16) or (ClientHeight < 16) then Exit;
  Screen.Cursor := crHourGlass;
  try
    FHex.Render(ClientWidth, ClientHeight, FSeed);
    FHex.DrawFrame(FFrame);
  finally
    Screen.Cursor := crDefault;
  end;
  FDirty := False;
  Invalidate;
end;

procedure TMainForm.TimerTick(Sender: TObject);
var
  Now: QWord;
begin
  Now := GetTickCount64;
  // re-render the heavy static layer only when resizing has settled
  if FDirty and (Now - FResizeAt > 150) then
  begin
    Rebuild;
    FLastTick := GetTickCount64;
    Exit;
  end;
  if FPaused or FDirty then
  begin
    FLastTick := Now;
    Exit;
  end;
  FHex.Animate((Now - FLastTick) / 1000);
  FLastTick := Now;
  FHex.DrawFrame(FFrame);
  Invalidate;
end;

procedure TMainForm.FormPaint(Sender: TObject);
begin
  if (FFrame.Width = ClientWidth) and (FFrame.Height = ClientHeight) then
    FFrame.Draw(Canvas, 0, 0, True)
  else
    // stretch the last frame while the window is being resized
    FFrame.Draw(Canvas, Rect(0, 0, ClientWidth, ClientHeight), True);
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  FDirty := True;
  FResizeAt := GetTickCount64;
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
var
  FileName: string;
begin
  case Key of
    VK_R:
      begin
        Randomize;
        FSeed := Random(MaxInt);
        Rebuild;
      end;
    VK_S:
      begin
        FileName := ExtractFilePath(Application.ExeName) +
          Format('hexbg_%dx%d_%d.png', [FFrame.Width, FFrame.Height, FSeed]);
        FFrame.SaveToFile(FileName);
        Caption := 'Saved ' + FileName;
      end;
    VK_SPACE:
      FPaused := not FPaused;
    VK_F11:
      ToggleFullScreen;
    VK_ESCAPE:
      if FFullScreen then ToggleFullScreen else Close;
  end;
end;

end.
