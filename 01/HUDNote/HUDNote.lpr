program HUDNote;

{ HUD Note - Sci-Fi HUD program.
  The UI itself is in HUDNote\uhudnote.pas; the window, the info panel and the
  render engine are shared (../shared/hudhost.pas, ../shared/hudcore.pas). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, HUDCore, HUDHost, UHUDNote;

{$R *.res}

begin
  Application.Scaled := True;
  RunHUDWidget(THUDNoteWidget);
end.
