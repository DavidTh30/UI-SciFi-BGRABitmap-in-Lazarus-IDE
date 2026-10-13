program HexGate;

{ HexGate - fly down a hexagon tunnel and thread the gaps in the honeycomb
  walls. Built on the HexFlight renderer (BGRABitmap, all CPU cores,
  OpenGL output with vsync).
    uhexbackground.pas  renderer (+ gates, corridor, game camera)
    ugateaudio.pas      synthesized music and sound effects
    ugategame.pas       rules, menus, options, scoring, HUD
    ugatemain.pas       window and input }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, UHexBackground, UGateAudio, UGateGame, UGateMain;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title := 'HexGate';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TGateForm, GateForm);
  Application.Run;
end.
