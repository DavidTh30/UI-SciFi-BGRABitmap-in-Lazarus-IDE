unit UShieldCore;

{ Shield Core - heavy armoured ring with bright side wings, four thick
  rotating arc plates, a pulsing core glow with a rotating dot ring and a
  central bracket frame. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TShieldCoreWidget }

  TShieldCoreWidget = class(THUDWidget)
  private
    FRotSpeed: single;   // deg/s of the arc plates
    FPulseRate: single;  // rad/s of the core pulse
    FDotRatio: single;   // dot ring speed relative to FRotSpeed (opposite way)
    FSignalNum: single;  // number in the SIGNAL_n label
    function CX: single; inline;
    function CY: single; inline;
    function Rot: single;
    function Pulse: single;
  protected
    procedure DrawBackgroundExtras(B: TBGRABitmap); override;
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
    procedure DrawRingShape(id: integer; ax, ay, a: single); override;
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
  ViewW = 300;
  ViewH = 290;
  RingDots = 0;

constructor TShieldCoreWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FRotSpeed := 10;
  FPulseRate := 3;
  FDotRatio := 2;
  FSignalNum := 8;
  AddParam('Rotation speed', 'Animation', 'Speed of the four thick arc plates in degrees per second.',
    FRotSpeed, -180, 180, 1, False);
  AddParam('Pulse rate', 'Animation', 'Core glow pulse speed in radians per second (2*pi = 1 pulse per second).',
    FPulseRate, 0, 20, 2, False);
  AddParam('Dot ring ratio', 'Animation', 'Speed of the 48-dot ring as a multiple of the rotation speed (opposite way).',
    FDotRatio, 0, 10, 2, False);
  AddParam('Signal number', 'Content', 'n in the "SIGNAL_n" label.',
    FSignalNum, 0, 99, 0, True);
  RegisterRing(RingDots, 64, 7.5, False);  // 48 dots: repeats every 7.5 deg
end;

class function TShieldCoreWidget.UIName: string;
begin
  Result := 'Shield Core';
end;

class function TShieldCoreWidget.UIDescription: string;
begin
  Result := 'Armoured ring with bright side wings, four thick rotating arc plates, a pulsing core ' +
    'glow with a rotating dot ring and a central bracket frame. Used for shield / power status.';
end;

class function TShieldCoreWidget.UnitFile: string;
begin
  Result := 'ShieldCore\ushieldcore.pas';
end;

function TShieldCoreWidget.CX: single;
begin
  Result := ViewW / 2;
end;

function TShieldCoreWidget.CY: single;
begin
  Result := 145;
end;

function TShieldCoreWidget.Rot: single;
begin
  Result := Phase(0, FRotSpeed);
end;

function TShieldCoreWidget.Pulse: single;
begin
  Result := 0.5 + 0.5 * Sin(Phase(1, FPulseRate));
end;

procedure TShieldCoreWidget.DrawBackgroundExtras(B: TBGRABitmap);
begin
  SoftDisc(B, CX, CY, 140, Ice(35));
end;

procedure TShieldCoreWidget.DrawStatic;
begin
  // wings
  Band(CX, CY, 108, 126, 140, 220, Steel(125));
  Band(CX, CY, 108, 126, -40, 40, Steel(125));
  Arc(CX, CY, 132, 148, 212, 5, White);
  Arc(CX, CY, 132, -32, 32, 5, White);
  // body
  Disc(CX, CY, 108, Navy(140));
  Arc(CX, CY, 114, 60, 120, 3, White(220));
  Arc(CX, CY, 114, 240, 300, 1.5, Ice(180));
  Ring(CX, CY, 88, 1.5, Ice(160));
  Ring(CX, CY, 82, 0.8, Ice(90));
  Ring(CX, CY, 52, 1, Ice(120));
  // central bracket frame
  PolyLine([CX - 30, CY - 12, CX - 30, CY - 22, CX - 18, CY - 22], 1.5, White);
  PolyLine([CX + 18, CY - 22, CX + 30, CY - 22, CX + 30, CY - 12], 1.5, White);
  PolyLine([CX - 30, CY + 12, CX - 30, CY + 22, CX - 18, CY + 22], 1.5, White);
  PolyLine([CX + 18, CY + 22, CX + 30, CY + 22, CX + 30, CY + 12], 1.5, White);
  Line(CX - 18, CY, CX + 18, CY, 0.8, Ice(150));
  // side triangles
  FillPoly([CX - 104, CY - 5, CX - 104, CY + 5, CX - 110, CY], White);
  FillPoly([CX + 104, CY - 5, CX + 104, CY + 5, CX + 110, CY], White);
  // labels
  FillPoly([CX - 108, CY + 70, CX - 102, CY + 70, CX - 102, CY + 75, CX - 108, CY + 75], White);
  FillPoly([CX - 100, CY + 70, CX - 94, CY + 70, CX - 94, CY + 75, CX - 100, CY + 75], White(150));
  Txt(CX + 84, CY + 72, Format('SIGNAL_%d', [Round(FSignalNum)]), 7, White(220));
end;

procedure TShieldCoreWidget.DrawRingShape(id: integer; ax, ay, a: single);
begin
  if id = RingDots then
    Dots(ax, ay, 62, 48, 1.1, a, White(200));
end;

procedure TShieldCoreWidget.DrawDynamic;
var
  r: single;
begin
  r := Rot;
  Arc(CX, CY, 102, 200 + r, 250 + r, 7, White);
  Arc(CX, CY, 102, 290 + r, 340 + r, 7, White);
  Arc(CX, CY, 102, 30 + r, 80 + r, 7, White);
  Arc(CX, CY, 102, 100 + r, 150 + r, 7, White);
  SoftDisc(FFill, CX, CY, 72, Ice(Round(40 + 50 * Pulse)));
  RingFrame(RingDots, CX, CY, -r * FDotRatio);
end;

procedure TShieldCoreWidget.DefineDirty;
begin
  AddDirty(CX - 106, CY - 106, CX + 106, CY + 106);
end;

procedure TShieldCoreWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('Center (CX, CY) = (150, 145) in a 300 x 290 view. r = radius.');
  L.Add('');
  L.Add('BACKGROUND');
  L.Add('  Soft halo       Ice a35 r140 at center');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Wings           bands r108..126 at 140..220 and -40..40 deg, Steel a125');
  L.Add('  Wing rims       arcs r132 w5 White at 148..212 / -32..32 deg');
  L.Add('  Body            disc r108 Navy a140');
  L.Add('  Accent arcs     r114 w3 White a220 at 60..120, r114 w1.5 Ice a180 at 240..300');
  L.Add('  Rings           r88 w1.5 Ice a160, r82 w0.8 Ice a90, r52 w1 Ice a120');
  L.Add('  Bracket frame   4 corner hooks of a 60 x 44 box + centre line w0.8');
  L.Add('  Side triangles  pointing out at CX-/+104..110');
  L.Add('  Labels          2 small squares at (CX-108, CY+70), "SIGNAL_n" at (CX+84, CY+72)');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic), rot = time * Rotation speed');
  L.Add('  Arc plates      4 arcs r102 w7 White, 50 deg long, at 30/100/200/290 deg + rot');
  L.Add('  Core pulse      soft glow r72 Ice, alpha 40..90 = 40 + 50 * (0.5 + 0.5 sin(t * Pulse rate))');
  L.Add('  Dot ring        48 dots r62 size 1.1 White a200, angle -rot * Dot ratio');
  L.Add('                  (pre-rendered ring #0: 7.5 deg period)');
  L.Add('');
  L.Add('DIRTY RECT        (CX-106, CY-106)-(CX+106, CY+106) + 24 glow margin');
end;

procedure TShieldCoreWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Arc plate angle     %.1f deg', [NormDeg(Rot)]));
  L.Add(Format('Dot ring angle      %.1f deg', [NormDeg(-Rot * FDotRatio)]));
  L.Add(Format('Core pulse          %.0f %%', [Pulse * 100]));
end;

end.
