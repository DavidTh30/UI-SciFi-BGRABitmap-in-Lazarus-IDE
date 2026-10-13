program RadarSweep;

{ Radar Sweep - Sci-Fi HUD program.
  The UI itself is in RadarSweep\uradarsweep.pas; the window, the info panel and the
  render engine are shared (../shared/hudhost.pas, ../shared/hudcore.pas). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, HUDCore, HUDHost, URadarSweep;

{$R *.res}

begin
  Application.Scaled := True;
  RunHUDWidget(TRadarSweepWidget);
end.
