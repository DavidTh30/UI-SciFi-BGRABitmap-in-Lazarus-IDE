unit UDataFrames;

{ Data Frames - four chamfered information panels: a SIGNAL header frame
  with a scan line, a frame with glowing bars and a dot grid, a targeting
  frame with a pulsing ring and a status frame with progress dots. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TDataFramesWidget }

  TDataFramesWidget = class(THUDWidget)
  private
    FScanSpeed: single;    // scan passes per second (panel 1)
    FPulseRate: single;    // rad/s of the target ring (panel 3)
    FStatusRate: single;   // status dot steps per second (panel 4)
    FFillAlpha: single;    // panel fill opacity
    function Scan: single;
    function StatusLit: integer;
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
  ViewW = 152;
  ViewH = 484;
  AX = 20;              // left edge of all panels (panels are 112 wide)
  P1 = 20;              // top of each panel
  P2 = 148;
  P3 = 272;
  P4 = 398;

constructor TDataFramesWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FScanSpeed := 0.35;
  FPulseRate := 4;
  FStatusRate := 3;
  FFillAlpha := 55;
  AddParam('Scan speed', 'Animation', 'Panel 1: scan line passes per second.',
    FScanSpeed, 0, 5, 2, False);
  AddParam('Pulse rate', 'Animation', 'Panel 3: target ring pulse in radians per second.',
    FPulseRate, 0, 30, 1, False);
  AddParam('Status rate', 'Animation', 'Panel 4: status dot steps per second.',
    FStatusRate, 0, 20, 1, False);
  AddParam('Panel fill opacity', 'Style', 'Alpha (0-255) of the panel backgrounds.',
    FFillAlpha, 0, 255, 0, True);
end;

class function TDataFramesWidget.UIName: string;
begin
  Result := 'Data Frames';
end;

class function TDataFramesWidget.UIDescription: string;
begin
  Result := 'Four chamfered information panels: SIGNAL header with scan line, glowing-bar panel with ' +
    'dot grid, targeting frame with pulsing ring and status frame with progress dots. ' +
    'Containers for text, readouts and thumbnails.';
end;

class function TDataFramesWidget.UnitFile: string;
begin
  Result := 'DataFrames\udataframes.pas';
end;

function TDataFramesWidget.Scan: single;
begin
  Result := Frac(T * FScanSpeed);
end;

function TDataFramesWidget.StatusLit: integer;
begin
  Result := Trunc(T * FStatusRate) mod 5;
end;

procedure TDataFramesWidget.DrawStatic;
var
  i, j: integer;
  fa: byte;
begin
  fa := Round(FFillAlpha);
  // panel 1: SIGNAL header with hatched corner
  FillPoly([AX, P1 + 8, AX + 8, P1, AX + 92, P1, AX + 100, P1 + 8, AX + 112, P1 + 8,
            AX + 112, P1 + 66, AX + 104, P1 + 72, AX, P1 + 72], Steel(fa));
  Polygon([AX, P1 + 8, AX + 8, P1, AX + 92, P1, AX + 100, P1 + 8, AX + 112, P1 + 8,
           AX + 112, P1 + 66, AX + 104, P1 + 72, AX, P1 + 72], 1.5, Ice(200));
  for i := 0 to 4 do
    Line(AX + 78 + i * 6, P1 + 7, AX + 84 + i * 6, P1 + 1, 2, White(200));
  Line(AX + 112, P1 + 30, AX + 112, P1 + 62, 3, White);
  Line(AX + 30, P1 + 72, AX + 80, P1 + 72, 2.5, White(220));
  Txt(AX + 6, P1 + 6, '\\SIGNAL', 6, White(220));

  // panel 2: glowing top/bottom bars + dot grid
  FillPoly([AX, P2 + 6, AX + 6, P2, AX + 106, P2, AX + 112, P2 + 6, AX + 112, P2 + 56,
            AX + 106, P2 + 62, AX + 6, P2 + 62, AX, P2 + 56], Steel(Min(255, fa + 5)));
  Polygon([AX, P2 + 6, AX + 6, P2, AX + 106, P2, AX + 112, P2 + 6, AX + 112, P2 + 56,
           AX + 106, P2 + 62, AX + 6, P2 + 62, AX, P2 + 56], 1.5, Ice(190));
  Line(AX + 38, P2, AX + 74, P2, 4, White);
  Line(AX + 38, P2 + 62, AX + 74, P2 + 62, 4, White);
  Line(AX, P2 + 22, AX, P2 + 40, 3, White(220));
  Line(AX + 112, P2 + 22, AX + 112, P2 + 40, 3, White(220));
  for i := 0 to 12 do
    for j := 0 to 5 do
      Disc(AX + 10 + i * 7.6, P2 + 12 + j * 7.6, 0.6, Ice(90));

  // panel 3: targeting frame
  FillPoly([AX + 8, P3, AX + 104, P3, AX + 112, P3 + 8, AX + 112, P3 + 58, AX + 104, P3 + 64,
            AX + 8, P3 + 64, AX, P3 + 56, AX, P3 + 8], Steel(Min(255, fa + 5)));
  Polygon([AX + 8, P3, AX + 104, P3, AX + 112, P3 + 8, AX + 112, P3 + 58, AX + 104, P3 + 64,
           AX + 8, P3 + 64, AX, P3 + 56, AX, P3 + 8], 2, White(230));
  Line(AX + 80, P3 - 4, AX + 112, P3 - 4, 2.5, White);
  FillPoly([AX - 4, P3 + 22, AX + 2, P3 + 22, AX + 2, P3 + 44, AX - 4, P3 + 44], White(220));
  PolyLine([AX + 26, P3 + 22, AX + 26, P3 + 14, AX + 38, P3 + 14], 1.2, Ice(220));
  PolyLine([AX + 74, P3 + 14, AX + 86, P3 + 14, AX + 86, P3 + 22], 1.2, Ice(220));
  PolyLine([AX + 26, P3 + 42, AX + 26, P3 + 50, AX + 38, P3 + 50], 1.2, Ice(220));
  PolyLine([AX + 74, P3 + 50, AX + 86, P3 + 50, AX + 86, P3 + 42], 1.2, Ice(220));
  Line(AX + 52, P3 + 28, AX + 60, P3 + 36, 1.2, White);
  Line(AX + 60, P3 + 28, AX + 52, P3 + 36, 1.2, White);

  // panel 4: status frame
  FillPoly([AX, P4, AX + 94, P4, AX + 112, P4 + 18, AX + 112, P4 + 66, AX, P4 + 66], Steel(Max(0, fa - 10)));
  Polygon([AX, P4, AX + 94, P4, AX + 112, P4 + 18, AX + 112, P4 + 66, AX, P4 + 66], 1.2, Ice(180));
  Line(AX, P4 + 2, AX, P4 + 36, 4, White);
  for i := 0 to 4 do
    Disc(AX + 8 + i * 6, P4 + 58, 1.5, White(80));
  Txt(AX + 106, P4 + 58, '06_501', 5.5, Ice(220), taRightJustify);
end;

procedure TDataFramesWidget.DrawDynamic;
var
  i: integer;
  s: single;
begin
  s := Scan;
  Line(AX + 6, P1 + 20 + s * 46, AX + 106, P1 + 20 + s * 46, 1, Ice(Round(160 * (1 - s))));
  Ring(AX + 56, P3 + 32, 10 + 3 * Sin(T * FPulseRate), 0.8, Ice(120));
  for i := 0 to StatusLit do
    Disc(AX + 8 + i * 6, P4 + 58, 1.5, White);
end;

procedure TDataFramesWidget.DefineDirty;
begin
  AddDirty(AX + 6, P1 + 18, AX + 106, P1 + 68);   // scan line
  AddDirty(AX + 42, P3 + 18, AX + 70, P3 + 46);   // pulse ring
  AddDirty(AX + 6, P4 + 54, AX + 42, P4 + 62);    // status dots
end;

procedure TDataFramesWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 152 x 484. All panels are 112 wide at x = AX = 20.');
  L.Add('Panel tops: P1 = 20, P2 = 148, P3 = 272, P4 = 398.');
  L.Add('');
  L.Add('PANEL 1 - SIGNAL header (112 x 72)');
  L.Add('  Shape           chamfered top-left 8, notch step at x+92..100, bottom-right 8');
  L.Add('  Fill / border   Steel(Panel fill opacity), border w1.5 Ice a200');
  L.Add('  Hatching        5 diagonal strokes w2 White a200 at top-right');
  L.Add('  Accents         right bar w3 (y+30..62), bottom bar w2.5 (x+30..80)');
  L.Add('  Label           "\\SIGNAL" size 6 at (x+6, y+6)');
  L.Add('  DYNAMIC         scan line w1 Ice, y = P1+20 + 46*phase, fades as it descends');
  L.Add('');
  L.Add('PANEL 2 - glowing bars (112 x 62)');
  L.Add('  Shape           chamfered 6 on all corners');
  L.Add('  Bars            top/bottom w4 White (x+38..74), side bars w3 White a220');
  L.Add('  Dot grid        13 x 6 dots r0.6 Ice a90, pitch 7.6');
  L.Add('');
  L.Add('PANEL 3 - targeting frame (112 x 64)');
  L.Add('  Shape           chamfered 8, border w2 White a230, top-right tab w2.5');
  L.Add('  Left tab        6 x 22 White a220 at x-4');
  L.Add('  Reticle         4 corner hooks w1.2 Ice a220 + "x" cross w1.2 at centre');
  L.Add('  DYNAMIC         ring r = 10 + 3 sin(t * Pulse rate), w0.8 Ice a120');
  L.Add('');
  L.Add('PANEL 4 - status frame (112 x 66)');
  L.Add('  Shape           cut top-right corner 18, border w1.2 Ice a180');
  L.Add('  Left bar        w4 White (y+2..36)');
  L.Add('  Status dots     5 dots r1.5 (White a80 off), label "06_501" size 5.5');
  L.Add('  DYNAMIC         dots 0..n lit White, n = trunc(t * Status rate) mod 5');
  L.Add('');
  L.Add('DIRTY RECTS       scan area, pulse ring, status dots (+ 24 glow margin)');
end;

procedure TDataFramesWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Scan position       %.0f %%', [Scan * 100]));
  L.Add(Format('Target ring radius  %.1f', [10 + 3 * Sin(T * FPulseRate)]));
  L.Add(Format('Status dots lit     %d / 5', [StatusLit + 1]));
end;

end.
