program HUDMediaPlayer;

{ HUD Media Player - Sci-Fi HUD program.
  The UI itself is in HUDMediaPlayer\uhudmediaplayer.pas; the window, the info panel and the
  render engine are shared (../shared/hudhost.pas, ../shared/hudcore.pas). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, HUDCore, HUDHost, UHUDMediaPlayer;

{$R *.res}

begin
  Application.Scaled := True;
  RunHUDWidget(THUDMediaPlayerWidget);
end.
