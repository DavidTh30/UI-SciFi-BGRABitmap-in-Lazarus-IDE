unit UHexCore;

{ Hex Core - isometric hexagonal cube (outer + inner hexagon with spokes)
  with chevron brackets at every corner and a pulsing light at the core. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { THexCoreWidget }

  THexCoreWidget = class(THUDWidget)
  private
    FPulseRate: single;   // rad/s of the core light
    FCoreSize: single;    // radius of the core glow
    FFaceAlpha: single;   // opacity of the hexagon face
    function Pulse: single;
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
  ROuter = 32;
  RInner = 20;
  RChevron = 40;

constructor THexCoreWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FPulseRate := 2.5;
  FCoreSize := 12;
  FFaceAlpha := 60;
  AddParam('Pulse rate', 'Animation', 'Core light pulse in radians per second.',
    FPulseRate, 0, 30, 1, False);
  AddParam('Core glow radius', 'Style', 'Radius of the pulsing core light (design units).',
    FCoreSize, 2, 20, 1, True);
  AddParam('Face opacity', 'Style', 'Alpha (0-255) of the hexagon face.',
    FFaceAlpha, 0, 255, 0, True);
end;

class function THexCoreWidget.UIName: string;
begin
  Result := 'Hex Core';
end;

class function THexCoreWidget.UIDescription: string;
begin
  Result := 'Isometric hexagonal cube with spokes, chevron brackets on every corner and a pulsing ' +
    'core light. Used as a reactor / core / node status icon.';
end;

class function THexCoreWidget.UnitFile: string;
begin
  Result := 'HexCore\uhexcore.pas';
end;

function THexCoreWidget.Pulse: single;
begin
  Result := 0.5 + 0.5 * Sin(T * FPulseRate);
end;

procedure THexCoreWidget.DrawStatic;
var
  i: integer;
  a: single;
  outer, inner: array[0..11] of single;
begin
  for i := 0 to 5 do
  begin
    a := DegToRad(i * 60 - 90);
    outer[2 * i] := CX + ROuter * Cos(a);
    outer[2 * i + 1] := CY + ROuter * Sin(a);
    inner[2 * i] := CX + RInner * Cos(a);
    inner[2 * i + 1] := CY + RInner * Sin(a);
  end;
  FillPoly(outer, Steel(Round(FFaceAlpha)));
  Polygon(outer, 2, White);
  Polygon(inner, 1, Ice(160));
  for i := 0 to 5 do
    Line(CX, CY, outer[2 * i], outer[2 * i + 1], 1, Ice(120 + 100 * Ord(i mod 2 = 0)));
  Disc(CX, CY, 3, White);
  // corner chevrons
  for i := 0 to 5 do
  begin
    a := i * 60 - 90;
    PolyLine([CX + RChevron * Cos(DegToRad(a - 9)), CY + RChevron * Sin(DegToRad(a - 9)),
              CX + (RChevron + 3) * Cos(DegToRad(a)), CY + (RChevron + 3) * Sin(DegToRad(a)),
              CX + RChevron * Cos(DegToRad(a + 9)), CY + RChevron * Sin(DegToRad(a + 9))], 2, White);
  end;
end;

procedure THexCoreWidget.DrawDynamic;
begin
  SoftDisc(FFill, CX, CY, FCoreSize, White(Round(150 + 100 * Pulse)));
end;

procedure THexCoreWidget.DefineDirty;
begin
  AddDirty(CX - FCoreSize - 2, CY - FCoreSize - 2, CX + FCoreSize + 2, CY + FCoreSize + 2);
end;

procedure THexCoreWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('Center (55, 55) in a 110 x 110 view. Hexagons have a vertex at the top (-90 deg).');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Face            outer hexagon r32 filled Steel(Face opacity)');
  L.Add('  Outer hexagon   r32 w2 White');
  L.Add('  Inner hexagon   r20 w1 Ice a160');
  L.Add('  Spokes          6 lines centre -> outer vertices w1, Ice a220 / a120 alternating');
  L.Add('                  (the bright ones form the isometric cube edges)');
  L.Add('  Core dot        disc r3 White');
  L.Add('  Chevrons        6 chevrons w2 White at r40 (tip r43), +-9 deg, at each vertex');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic)');
  L.Add('  Core light      soft glow r = Core glow radius, White alpha 150..250');
  L.Add('                  = 150 + 100 * (0.5 + 0.5 sin(t * Pulse rate)), on the fill layer');
  L.Add('');
  L.Add('DIRTY RECT        core glow bounds + 24 glow margin');
end;

procedure THexCoreWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Core light          %.0f %%', [Pulse * 100]));
end;

end.
