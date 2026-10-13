unit UTargetCrosshair;

{ Target Crosshair - aiming reticle: two rings, long cross hairs, bracket
  arcs and a rotating filled sector that sweeps around the centre. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TTargetCrosshairWidget }

  TTargetCrosshairWidget = class(THUDWidget)
  private
    FSpinSpeed: single;   // deg/s of the sector
    FSectorSize: single;  // angular size of the sector in degrees
    FSectorAlpha: single;
    function SectorAngle: single;
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
  end;

implementation

const
  ViewW = 110;
  ViewH = 110;
  CX = 55;
  CY = 55;
  R = 30;

constructor TTargetCrosshairWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FSpinSpeed := 40;
  FSectorSize := 90;
  FSectorAlpha := 150;
  AddParam('Spin speed', 'Animation', 'Sector rotation in degrees per second (negative = counter-clockwise).',
    FSpinSpeed, -720, 720, 0, False);
  AddParam('Sector size', 'Style', 'Angular size of the filled sector in degrees.',
    FSectorSize, 0, 360, 0, False);
  AddParam('Sector opacity', 'Style', 'Alpha (0-255) of the filled sector.',
    FSectorAlpha, 0, 255, 0, False);
end;

class function TTargetCrosshairWidget.UIName: string;
begin
  Result := 'Target Crosshair';
end;

class function TTargetCrosshairWidget.UIDescription: string;
begin
  Result := 'Aiming reticle with two rings, long cross hairs, bracket arcs and a rotating filled sector. ' +
    'Used as a cursor / aim point or a "searching" indicator.';
end;

class function TTargetCrosshairWidget.UnitFile: string;
begin
  Result := 'TargetCrosshair\utargetcrosshair.pas';
end;

function TTargetCrosshairWidget.SectorAngle: single;
begin
  Result := T * FSpinSpeed;
end;

procedure TTargetCrosshairWidget.DrawStatic;
begin
  Ring(CX, CY, R, 1.5, White);
  Ring(CX, CY, 20, 0.8, Ice(150));
  Line(CX - 44, CY, CX + 44, CY, 1.2, White);
  Line(CX, CY - 44, CX, CY + 44, 1.2, White);
  Arc(CX, CY, 38, 200, 250, 1.2, Ice(180));
  Arc(CX, CY, 38, 20, 70, 1.2, Ice(180));
  Disc(CX, CY, 3, White);
end;

procedure TTargetCrosshairWidget.DrawDynamic;
var
  a: single;
begin
  a := SectorAngle;
  if FSectorSize > 0 then
    Pie(CX, CY, R, a - FSectorSize, a, Ice(Round(FSectorAlpha)));
end;

procedure TTargetCrosshairWidget.DefineDirty;
begin
  AddDirty(CX - R, CY - R, CX + R, CY + R);
end;

procedure TTargetCrosshairWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('Center (55, 55) in a 110 x 110 view.');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Outer ring      r30 w1.5 White');
  L.Add('  Inner ring      r20 w0.8 Ice a150');
  L.Add('  Cross hairs     88 long (r44 each side), w1.2 White');
  L.Add('  Bracket arcs    r38 w1.2 Ice a180 at 200..250 and 20..70 deg');
  L.Add('  Centre dot      r3 White');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic), angle = time * Spin speed');
  L.Add('  Sector          pie r30 from angle - Sector size to angle,');
  L.Add('                  Ice(Sector opacity); alpha < 200 -> fill layer (no glow)');
  L.Add('');
  L.Add('DIRTY RECT        (CX-30, CY-30)-(CX+30, CY+30) + 24 glow margin');
end;

procedure TTargetCrosshairWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Sector leading edge %.1f deg', [NormDeg(SectorAngle)]));
end;

end.
