unit UOpticScanner;

{ Optic Scanner - large circular scanner with glowing lens shells on both
  sides, a rotating tick ring, two thick rotating arcs and a
  counter-rotating segmented band around a lens core. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TOpticScannerWidget }

  TOpticScannerWidget = class(THUDWidget)
  private
    FRotSpeed: single;      // deg/s of the thick arcs
    FBandRatio: single;     // band speed relative to the arcs (counter-rotating)
    FTickRatio: single;     // outer tick speed relative to the arcs
    FShellAlpha: single;    // opacity of the lens shells
    FLabelNum: single;      // number printed at the top-left
    function CX: single; inline;
    function CY: single; inline;
    function Rot: single;
  protected
    procedure DrawBackground(B: TBGRABitmap); override;
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
  ViewW = 420;
  ViewH = 290;

constructor TOpticScannerWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FRotSpeed := 18;
  FBandRatio := 1.4;
  FTickRatio := 0.3;
  FShellAlpha := 70;
  FLabelNum := 52;
  AddParam('Rotation speed', 'Animation', 'Speed of the two thick arcs in degrees per second (negative = counter-clockwise).',
    FRotSpeed, -180, 180, 1, False);
  AddParam('Band speed ratio', 'Animation', 'Segmented band speed as a multiple of the rotation speed; it turns the opposite way.',
    FBandRatio, 0, 5, 2, False);
  AddParam('Tick speed ratio', 'Animation', 'Speed of the 12 major ticks as a multiple of the rotation speed (opposite way).',
    FTickRatio, 0, 5, 2, False);
  AddParam('Shell opacity', 'Style', 'Alpha (0-255) of the two translucent lens shells.',
    FShellAlpha, 0, 255, 0, True);
  AddParam('Label number', 'Content', 'Value shown in the top-left label (3 digits).',
    FLabelNum, 0, 999, 0, True);
end;

class function TOpticScannerWidget.UIName: string;
begin
  Result := 'Optic Scanner';
end;

class function TOpticScannerWidget.UIDescription: string;
begin
  Result := 'Large circular scanner with glowing lens shells, rotating thick arcs, a counter-rotating ' +
    'segmented band and a lens core. Used as a primary focus / scanning indicator.';
end;

class function TOpticScannerWidget.UnitFile: string;
begin
  Result := 'OpticScanner\uopticscanner.pas';
end;

function TOpticScannerWidget.CX: single;
begin
  Result := ViewW / 2;
end;

function TOpticScannerWidget.CY: single;
begin
  Result := ViewH / 2;
end;

function TOpticScannerWidget.Rot: single;
begin
  Result := T * FRotSpeed;
end;

procedure TOpticScannerWidget.DrawBackground(B: TBGRABitmap);
begin
  inherited DrawBackground(B);
  // soft white halos behind the lens shells
  SoftDisc(B, CX - 130, CY, 70, White(150));
  SoftDisc(B, CX + 130, CY, 70, White(130));
  SoftDisc(B, CX, CY, 140, Ice(40));
end;

procedure TOpticScannerWidget.DrawStatic;
var
  shell: byte;
begin
  shell := Round(FShellAlpha);
  // translucent lens shells left/right
  Disc(CX - 72, CY, 74, Steel(shell));
  Disc(CX + 72, CY, 74, Steel(shell));
  Arc(CX - 72, CY, 74, 115, 245, 7, White);
  Arc(CX + 72, CY, 74, -65, 65, 7, White);
  Arc(CX - 72, CY, 66, 140, 220, 2, White(160));
  Arc(CX + 72, CY, 66, -40, 40, 2, White(160));
  // dark core and fixed rings
  Disc(CX, CY, 98, Navy(170));
  Ticks(CX, CY, 112, 116, 90, 0, 360, 1, Ice(140));
  Ring(CX, CY, 104, 1.5, Ice(130));
  Arc(CX, CY, 86, 0, 360, 1, Ice(120));
  // lens core
  Ring(CX, CY, 56, 2, Ice(200));
  SoftDisc(FFill, CX, CY, 52, Ice(60));
  Arc(CX, CY, 42, 140, 220, 5, White);
  Arc(CX, CY, 42, -40, 40, 5, White);
  Arc(CX, CY, 34, 0, 360, 1, Ice(90));
  Txt(CX - 120, CY - 42, Format('%.3d', [Round(FLabelNum)]), 11, White);
end;

procedure TOpticScannerWidget.DrawDynamic;
var
  i: integer;
  r: single;
begin
  r := Rot;
  Ticks(CX, CY, 108, 118, 12, -r * FTickRatio, 360 - r * FTickRatio, 2, White(220));
  Arc(CX, CY, 94, 205 + r, 335 + r, 7, White);
  Arc(CX, CY, 94, 25 + r, 155 + r, 7, White);
  for i := 0 to 5 do
    Band(CX, CY, 70, 78, i * 60 - r * FBandRatio, i * 60 + 32 - r * FBandRatio,
      White(i mod 2 * 120 + 120));
end;

procedure TOpticScannerWidget.DefineDirty;
begin
  AddDirty(CX - 122, CY - 122, CX + 122, CY + 122);
end;

procedure TOpticScannerWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('Center (CX, CY) = (210, 145) in a 420 x 290 view. r = radius.');
  L.Add('');
  L.Add('BACKGROUND (DrawBackground)');
  L.Add('  Soft halos      White a150 r70 at CX-130, White a130 r70 at CX+130, Ice a40 r140 at center');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Lens shells     2 discs r74 at CX-72 / CX+72, Steel(Shell opacity)');
  L.Add('  Shell rims      outer arcs r74 w7 White: left 115..245 deg, right -65..65 deg');
  L.Add('                  inner arcs r66 w2 White a160: left 140..220, right -40..40');
  L.Add('  Dark core       disc r98 Navy a170');
  L.Add('  Minor ticks     90 ticks r112..116 w1 Ice a140');
  L.Add('  Rings           r104 w1.5 Ice a130, r86 w1 Ice a120, r34 w1 Ice a90');
  L.Add('  Lens core       ring r56 w2 Ice a200 + soft glow r52 Ice a60');
  L.Add('  Lens brackets   arcs r42 w5 White at 140..220 and -40..40');
  L.Add('  Label           "052" Consolas bold 11 at (CX-120, CY-42)');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic), rot = time * Rotation speed');
  L.Add('  Major ticks     12 ticks r108..118 w2 White a220, angle -rot * Tick ratio');
  L.Add('  Thick arcs      2 arcs r94 w7 White, 205..335 and 25..155 deg, + rot');
  L.Add('  Segmented band  6 sectors r70..78, 32 deg each every 60 deg,');
  L.Add('                  alternating White a120 / a240, angle -rot * Band ratio');
  L.Add('');
  L.Add('DIRTY RECT        (CX-122, CY-122)-(CX+122, CY+122) + 24 glow margin');
end;

procedure TOpticScannerWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Thick arc angle     %.1f deg', [NormDeg(Rot)]));
  L.Add(Format('Band angle          %.1f deg', [NormDeg(-Rot * FBandRatio)]));
  L.Add(Format('Major tick angle    %.1f deg', [NormDeg(-Rot * FTickRatio)]));
end;

end.
