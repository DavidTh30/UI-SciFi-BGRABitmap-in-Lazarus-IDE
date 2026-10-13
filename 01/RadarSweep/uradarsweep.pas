unit URadarSweep;

{ Radar Sweep - round radar scope with range rings, cross hairs, a rotating
  sweep beam with a fading trail and contacts (blips) that light up when
  the beam passes. Two frame styles: tick bezel or heavy ring. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TRadarSweepWidget }

  TRadarSweepWidget = class(THUDWidget)
  private
    FSweepSpeed: single;   // deg/s, negative = counter-clockwise
    FStyle: single;        // 0 = tick bezel, 1 = heavy ring
    FTrailSlices: single;  // number of 6-degree slices in the trail
    function Beam: single;
    function BlipLevel(bx, by: single): single;
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
  ViewW = 120;
  ViewH = 120;
  CX = 60;
  CY = 60;
  R = 38;        // scope radius
  // contacts (offsets from the centre)
  Blips: array[0..1, 0..2] of single = ((18, -12, 1.8), (-10, 20, 1.6));

constructor TRadarSweepWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FSweepSpeed := 90;
  FStyle := 0;
  FTrailSlices := 12;
  AddParam('Sweep speed', 'Animation', 'Beam rotation in degrees per second (negative = counter-clockwise).',
    FSweepSpeed, -720, 720, 0, False);
  AddParam('Trail length', 'Style', 'Number of 6-degree slices in the fading trail behind the beam.',
    FTrailSlices, 0, 40, 0, False);
  AddParam('Frame style', 'Style', '0 = thin ring with tick bezel and arcs, 1 = heavy double ring.',
    FStyle, 0, 1, 0, True);
end;

class function TRadarSweepWidget.UIName: string;
begin
  Result := 'Radar Sweep';
end;

class function TRadarSweepWidget.UIDescription: string;
begin
  Result := 'Radar scope with range rings, cross hairs, a rotating sweep beam with a fading trail and ' +
    'contacts that light up when the beam passes. Two frame styles (tick bezel / heavy ring).';
end;

class function TRadarSweepWidget.UnitFile: string;
begin
  Result := 'RadarSweep\uradarsweep.pas';
end;

function TRadarSweepWidget.Beam: single;
begin
  Result := Phase(0, FSweepSpeed);
end;

function TRadarSweepWidget.BlipLevel(bx, by: single): single;
var
  ang: single;
begin
  // brightest right when the beam is on the contact, fades over ~90 deg after it
  ang := RadToDeg(ArcTan2(by, bx));
  if FSweepSpeed >= 0 then
    Result := Max(0, Cos(DegToRad(EnsureRange(NormDeg(Beam - ang), 0, 90))))
  else
    Result := Max(0, Cos(DegToRad(EnsureRange(NormDeg(ang - Beam), 0, 90))));
end;

procedure TRadarSweepWidget.DrawStatic;
begin
  Disc(CX, CY, R, Navy(150));
  if FStyle >= 1 then
  begin
    Ring(CX, CY, R, 3.5, White);
    Ring(CX, CY, R + 5, 1, Ice(160));
  end
  else
  begin
    Ring(CX, CY, R, 1.5, White);
    Ticks(CX, CY, R + 2, R + 7, 72, 0, 360, 0.8, Ice(160));
    Arc(CX, CY, R + 8, 200, 250, 2, White);
    Arc(CX, CY, R + 8, 20, 70, 2, White);
  end;
  Ring(CX, CY, 26, 0.8, Ice(150));
  Ring(CX, CY, 14, 0.8, Ice(150));
  Line(CX - R, CY, CX + R, CY, 0.7, Ice(110));
  Line(CX, CY - R, CX, CY + R, 0.7, Ice(110));
end;

procedure TRadarSweepWidget.DrawDynamic;
var
  a, dir: single;
  i, n: integer;
begin
  a := Beam;
  if FSweepSpeed >= 0 then dir := 1 else dir := -1;
  n := Round(FTrailSlices);
  // trail: slices of fading alpha behind the beam
  for i := 0 to n - 1 do
    Pie(CX, CY, R - 2, a - dir * (i + 1) * 6, a - dir * i * 6, Ice(Round(110 * (1 - i / n))));
  Line(CX, CY, CX + (R - 2) * Cos(DegToRad(a)), CY + (R - 2) * Sin(DegToRad(a)), 1.5, White);
  for i := 0 to High(Blips) do
    Disc(CX + Blips[i, 0], CY + Blips[i, 1], Blips[i, 2],
      White(Round(255 * BlipLevel(Blips[i, 0], Blips[i, 1]))));
end;

procedure TRadarSweepWidget.DefineDirty;
begin
  AddDirty(CX - R, CY - R, CX + R, CY + R);
end;

procedure TRadarSweepWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('Center (60, 60) in a 120 x 120 view. Scope radius R = 38.');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Scope           disc R Navy a150');
  L.Add('  Frame style 0   ring R w1.5 White, 72 ticks R+2..R+7 w0.8 Ice a160,');
  L.Add('                  arcs R+8 w2 White at 200..250 and 20..70 deg');
  L.Add('  Frame style 1   ring R w3.5 White + ring R+5 w1 Ice a160');
  L.Add('  Range rings     r26 and r14, w0.8 Ice a150');
  L.Add('  Cross hairs     horizontal + vertical w0.7 Ice a110');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic), beam = time * Sweep speed');
  L.Add('  Trail           n = Trail length pie slices of 6 deg, r R-2,');
  L.Add('                  Ice alpha 110 * (1 - i/n) behind the beam');
  L.Add('  Beam            line centre -> r R-2, w1.5 White');
  L.Add('  Contacts        (18,-12) r1.8 and (-10,20) r1.6 White, brightness =');
  L.Add('                  cos(angle since the beam passed), 0 after 90 deg');
  L.Add('');
  L.Add('DIRTY RECT        (CX-R, CY-R)-(CX+R, CY+R) + 24 glow margin');
end;

procedure TRadarSweepWidget.DescribeLive(L: TStrings);
var
  i: integer;
begin
  inherited DescribeLive(L);
  L.Add(Format('Beam angle          %.1f deg', [NormDeg(Beam)]));
  for i := 0 to High(Blips) do
    L.Add(Format('Contact %d level     %.0f %%', [i + 1, 100 * BlipLevel(Blips[i, 0], Blips[i, 1])]));
end;

end.
