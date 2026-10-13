program HexBackground;

{ Hex Background - sci-fi hexagon UI background made with BGRABitmap.
  The renderer is in uhexbackground.pas, the window in umain.pas.

  Command line (no window):
    HexBackground --png <file.png> [width] [height] [seed] }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  SysUtils, Forms, BGRABitmap, UHexBackground, UMain;

{$R *.res}

procedure RenderToFile;
var
  Hex: THexBackground;
  Frame: TBGRABitmap;
begin
  Hex := THexBackground.Create;
  Frame := TBGRABitmap.Create(1, 1);
  try
    Hex.Render(StrToIntDef(ParamStr(3), 1920), StrToIntDef(ParamStr(4), 1080),
      StrToIntDef(ParamStr(5), 2026));
    Hex.DrawFrame(Frame);
    Frame.SaveToFile(ParamStr(2));
  finally
    Frame.Free;
    Hex.Free;
  end;
end;

begin
  if (ParamCount >= 2) and (ParamStr(1) = '--png') then
  begin
    RenderToFile;
    Exit;
  end;
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
