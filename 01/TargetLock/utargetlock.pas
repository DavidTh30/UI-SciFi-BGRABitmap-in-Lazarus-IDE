unit UTargetLock;

{ Target Lock - circular lock-on reticle with side wings, partial outer
  rings, a fine rotating tick ring, rotating bright segments and a dotted
  ring around a glowing core. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TTargetLockWidget }

  TTargetLockWidget = class(THUDWidget)
  private
    FRotSpeed: single;    // deg/s of the bright segments (counter-clockwise)
    FTickRatio: single;   // fine tick ring speed relative to FRotSpeed
    FDotRatio: single;    // dotted ring speed relative to FRotSpeed (opposite way)
    FWingAlpha: single;
    function CX: single; inline;
    function CY: single; inline;
    function Rot: single;
  protected
    procedure DrawBackground(B: TBGRABitmap); override;
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
  ViewW = 320;
  ViewH = 300;
  RingTicks = 0;  // RegisterRing ids
  RingDots = 1;

constructor TTargetLockWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FRotSpeed := 14;
  FTickRatio := 0.5;
  FDotRatio := 0.7;
  FWingAlpha := 120;
  AddParam('Rotation speed', 'Animation', 'Speed of the bright segments in degrees per second (they turn counter-clockwise).',
    FRotSpeed, -180, 180, 1, False);
  AddParam('Tick ring ratio', 'Animation', 'Speed of the 120-tick ring as a multiple of the rotation speed.',
    FTickRatio, 0, 5, 2, False);
  AddParam('Dot ring ratio', 'Animation', 'Speed of the 72-dot ring as a multiple of the rotation speed (opposite way).',
    FDotRatio, 0, 5, 2, False);
  AddParam('Wing opacity', 'Style', 'Alpha (0-255) of the two side wings.',
    FWingAlpha, 0, 255, 0, True);
  // rotating rings with many identical elements -> pre-rendered frames
  RegisterRing(RingTicks, 110, 3, False);  // 120 ticks: repeats every 3 deg
  RegisterRing(RingDots, 88, 5, True);     // 72 dots: repeats every 5 deg
end;

class function TTargetLockWidget.UIName: string;
begin
  Result := 'Target Lock';
end;

class function TTargetLockWidget.UIDescription: string;
begin
  Result := 'Lock-on reticle with side wings, partial outer rings, a fine rotating tick ring, rotating ' +
    'bright segments and a dotted ring around a glowing core. Used to show an acquired target.';
end;

class function TTargetLockWidget.UnitFile: string;
begin
  Result := 'TargetLock\utargetlock.pas';
end;

function TTargetLockWidget.CX: single;
begin
  Result := ViewW / 2;
end;

function TTargetLockWidget.CY: single;
begin
  Result := ViewH / 2;
end;

function TTargetLockWidget.Rot: single;
begin
  Result := -T * FRotSpeed;
end;

procedure TTargetLockWidget.DrawBackground(B: TBGRABitmap);
begin
  inherited DrawBackground(B);
  SoftDisc(B, CX, CY, 140, Ice(30));
end;

procedure TTargetLockWidget.DrawStatic;
var
  wing: byte;
begin
  wing := Round(FWingAlpha);
  // side wings
  Band(CX, CY, 116, 134, 148, 212, Steel(wing));
  Band(CX, CY, 116, 134, -32, 32, Steel(wing));
  Arc(CX, CY, 134, 150, 210, 2.5, White(230));
  Arc(CX, CY, 134, -30, 30, 2.5, White(230));
  Arc(CX, CY, 116, 150, 210, 1, Ice(160));
  Arc(CX, CY, 116, -30, 30, 1, Ice(160));
  // outer partial rings
  Arc(CX, CY, 128, 215, 325, 1.5, White(220));
  Arc(CX, CY, 128, 35, 145, 1.5, White(220));
  Arc(CX, CY, 138, 240, 300, 1, Ice(140));
  Arc(CX, CY, 138, 60, 120, 1, Ice(140));
  // body and core
  Disc(CX, CY, 112, Navy(110));
  Ring(CX, CY, 112, 1, Ice(140));
  SoftDisc(FFill, CX, CY, 70, Ice(70));
  Ring(CX, CY, 56, 2, White(230));
  Ring(CX, CY, 48, 1, Ice(120));
  // corner markers
  FillPoly([CX - 104, CY - 32, CX - 98, CY - 32, CX - 98, CY - 26, CX - 104, CY - 26], White);
  FillPoly([CX + 98, CY - 32, CX + 104, CY - 32, CX + 104, CY - 26, CX + 98, CY - 26], White);
  PolyLine([CX + 96, CY + 22, CX + 104, CY + 22, CX + 104, CY + 30], 1.5, White(200));
  PolyLine([CX - 96, CY + 22, CX - 104, CY + 22, CX - 104, CY + 30], 1.5, White(200));
end;

procedure TTargetLockWidget.DrawRingShape(id: integer; ax, ay, a: single);
begin
  case id of
    RingTicks: Ticks(ax, ay, 103, 108, 120, a, 360 + a, 0.8, Ice(150));
    RingDots: Dots(ax, ay, 86, 72, 0.9, a, Ice(170));
  end;
end;

procedure TTargetLockWidget.DrawDynamic;
var
  r: single;
begin
  r := Rot;
  RingFrame(RingTicks, CX, CY, r * FTickRatio);
  Arc(CX, CY, 98, 235 + r, 305 + r, 3, White);
  Arc(CX, CY, 98, 55 + r, 125 + r, 3, White);
  Arc(CX, CY, 98, 150 - r, 170 - r, 2, Ice(200));
  Arc(CX, CY, 98, -10 - r, 10 - r, 2, Ice(200));
  RingFrame(RingDots, CX, CY, -r * FDotRatio);
end;

procedure TTargetLockWidget.DefineDirty;
begin
  AddDirty(CX - 110, CY - 110, CX + 110, CY + 110);
end;

procedure TTargetLockWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('Center (CX, CY) = (160, 150) in a 320 x 300 view. r = radius.');
  L.Add('');
  L.Add('BACKGROUND');
  L.Add('  Soft halo       Ice a30 r140 at center');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Side wings      bands r116..134 at 148..212 and -32..32 deg, Steel(Wing opacity)');
  L.Add('  Wing rims       outer r134 w2.5 White a230, inner r116 w1 Ice a160');
  L.Add('  Partial rings   r128 w1.5 White a220 at 215..325 / 35..145 deg');
  L.Add('                  r138 w1 Ice a140 at 240..300 / 60..120 deg');
  L.Add('  Body            disc r112 Navy a110 + ring r112 w1 Ice a140');
  L.Add('  Core            soft glow r70 Ice a70, ring r56 w2 White a230, ring r48 w1 Ice a120');
  L.Add('  Markers         2 squares 6x6 at (CX-/+101, CY-29), 2 corner hooks at CY+22..30');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic), rot = -time * Rotation speed');
  L.Add('  Tick ring       120 ticks r103..108 w0.8 Ice a150, angle rot * Tick ratio');
  L.Add('                  (pre-rendered ring #0: 3 deg period, blitted per frame)');
  L.Add('  Bright segments r98 w3 White at 235..305 / 55..125 deg + rot');
  L.Add('  Counter accents r98 w2 Ice a200 at 150..170 / -10..10 deg - rot');
  L.Add('  Dot ring        72 dots r86 size 0.9 Ice a170, angle -rot * Dot ratio');
  L.Add('                  (pre-rendered ring #1: 5 deg period, on the fill layer)');
  L.Add('');
  L.Add('DIRTY RECT        (CX-110, CY-110)-(CX+110, CY+110) + 24 glow margin');
end;

procedure TTargetLockWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Segment angle       %.1f deg', [NormDeg(Rot)]));
  L.Add(Format('Tick ring angle     %.1f deg', [NormDeg(Rot * FTickRatio)]));
  L.Add(Format('Dot ring angle      %.1f deg', [NormDeg(-Rot * FDotRatio)]));
end;

end.
