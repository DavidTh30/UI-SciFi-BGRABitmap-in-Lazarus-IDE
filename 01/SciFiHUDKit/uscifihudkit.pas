unit USciFiHUDKit;

{ Sci-Fi HUD Kit - the complete HUD sheet: every UI of the kit on one canvas,
  laid out like the original design (740 x 960).

  Nothing is drawn here: each UI is the same widget class used by its own
  program (OpticScanner, TargetLock, ...), hosted by THUDComposite at an
  origin. Change a widget unit and both its program and this kit change. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmapTypes, HUDCore,
  UOpticScanner, UTargetLock, UShieldCore, UHUDIconSet, UDataFrames,
  URadarSweep, UHexCore, UTargetCrosshair,
  UChevronLoader, UPillLoader, UBlockLoader, USlantLoader;

type

  { TSciFiHUDKitWidget }

  TSciFiHUDKitWidget = class(THUDComposite)
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
  end;

implementation

constructor TSciFiHUDKitWidget.Create;
var
  radar: THUDWidget;
begin
  inherited Create;
  SetView(740, 960);
  SetParamByName('Max zoom', 2.5);
  // left column: the three big instruments, then the icon set
  AddChild(TOpticScannerWidget.Create, 12, -10);
  AddChild(TTargetLockWidget.Create, 62, 235);
  AddChild(TShieldCoreWidget.Create, 72, 495);
  AddChild(THUDIconSetWidget.Create, 63, 780);
  // right column: data frames + small instruments
  AddChild(TDataFramesWidget.Create, 413, 20);
  AddChild(TRadarSweepWidget.Create, 588, 15, 'Radar Sweep (bezel)');
  radar := TRadarSweepWidget.Create;
  radar.SetParamByName('Frame style', 1);
  radar.SetParamByName('Sweep speed', -70);
  AddChild(radar, 588, 138, 'Radar Sweep (heavy ring)');
  AddChild(THexCoreWidget.Create, 593, 267);
  AddChild(TTargetCrosshairWidget.Create, 593, 390);
  // loaders
  AddChild(TChevronLoaderWidget.Create, 420, 525);
  AddChild(TPillLoaderWidget.Create, 420, 625);
  AddChild(TBlockLoaderWidget.Create, 420, 730);
  AddChild(TSlantLoaderWidget.Create, 420, 830);
end;

class function TSciFiHUDKitWidget.UIName: string;
begin
  Result := 'Sci-Fi HUD Kit';
end;

class function TSciFiHUDKitWidget.UIDescription: string;
begin
  Result := 'The complete HUD sheet: all UIs of the kit on one canvas, laid out like the original design. ' +
    'Click a UI (or pick it in the list) to inspect and tune it.';
end;

class function TSciFiHUDKitWidget.UnitFile: string;
begin
  Result := 'SciFiHUDKit\uscifihudkit.pas';
end;

procedure TSciFiHUDKitWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
  o: TPointF;
begin
  L.Add('Canvas 740 x 960 design units. Each UI is a hosted widget; its own');
  L.Add('design units start at the origin below (same scale as the canvas).');
  L.Add('');
  L.Add(Format('%-26s %-22s %-14s %s', ['UI', 'Class', 'Origin', 'View size']));
  for i := 0 to ChildCount - 1 do
  begin
    o := ChildOrigin(i);
    L.Add(Format('%-26s %-22s (%4.0f,%4.0f)    %3.0f x %3.0f',
      [ChildCaption(i), Children[i].ClassName, o.x, o.y,
       Children[i].DesignWidth, Children[i].DesignHeight]));
  end;
  L.Add('');
  L.Add('HOW IT IS DRAWN');
  L.Add('  One background, one glow pipeline and one set of dirty rects for the');
  L.Add('  whole canvas. Every frame each child draws its animated parts into the');
  L.Add('  shared layers (THUDComposite.SyncChild gives it the canvas transform');
  L.Add('  shifted by its origin). Overlapping dirty rects are merged.');
  L.Add('');
  L.Add('TO CHANGE THE LAYOUT');
  L.Add('  Edit the AddChild(..., originX, originY) calls in the constructor.');
  L.Add('  Preset a child with SetParamByName (see the heavy-ring radar).');
  L.Add('  Select a UI to see its own anatomy, parameters and live state.');
end;

procedure TSciFiHUDKitWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Hosted UIs          %d', [ChildCount]));
end;

end.
