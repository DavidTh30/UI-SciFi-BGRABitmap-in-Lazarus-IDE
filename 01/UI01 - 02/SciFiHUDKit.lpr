program SciFiHUDKit;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, HUDMain, HUDRender;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Title := 'Sci-Fi HUD Interface Kit';
  Application.Initialize;
  Application.CreateForm(TSciFiHUDForm, SciFiHUDForm);
  Application.Run;
end.
