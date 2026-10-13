unit UHUDIconSet;

{ HUD Icon Set - reusable small HUD glyphs: 8 corner brackets (light and
  heavy), hexagon / square / circle frames and 3 warning triangles.
  Static by default; the warnings can blink (Alert blink rate > 0). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { THUDIconSetWidget }

  THUDIconSetWidget = class(THUDWidget)
  private
    FBlinkRate: single;   // blinks per second of the warning icons, 0 = static
    function Blink: single;
    procedure DrawWarnings(alpha: byte);
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
  ViewW = 330;
  ViewH = 130;
  AX = 25;    // top-left of the bracket grid
  AY = 32;
  SX = AX + 180;  // x of the first shape / warning column
  WY = AY + 52;   // y of the warning row

constructor THUDIconSetWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FBlinkRate := 0;
  AddParam('Alert blink rate', 'Animation', 'Blinks per second of the three warning icons. 0 = static (as in the design).',
    FBlinkRate, 0, 10, 1, True);
end;

class function THUDIconSetWidget.UIName: string;
begin
  Result := 'HUD Icon Set';
end;

class function THUDIconSetWidget.UIDescription: string;
begin
  Result := 'Reusable HUD glyphs: eight corner brackets (light and heavy styles), hexagon / square / ' +
    'circle frames and three warning triangles. Building blocks for frames, buttons and alerts.';
end;

class function THUDIconSetWidget.UnitFile: string;
begin
  Result := 'HUDIconSet\uhudiconset.pas';
end;

function THUDIconSetWidget.Blink: single;
begin
  Result := 0.55 + 0.45 * Cos(Phase(0, FBlinkRate * 2 * Pi));
end;

procedure THUDIconSetWidget.DrawWarnings(alpha: byte);
var
  bx: single;
begin
  // 1) outlined triangle with "!"
  bx := SX;
  Polygon([bx, WY - 15, bx + 17, WY + 13, bx - 17, WY + 13], 3, White(alpha));
  Line(bx, WY - 4, bx, WY + 4, 3, White(alpha));
  Disc(bx, WY + 8, 1.6, White(alpha));
  // 2) broken triangle with "!"
  bx := bx + 40;
  PolyLine([bx - 5, WY - 7, bx, WY - 15, bx + 5, WY - 7], 2, White(alpha));
  PolyLine([bx + 9, WY, bx + 17, WY + 13, bx + 6, WY + 13], 2, White(alpha));
  PolyLine([bx - 9, WY, bx - 17, WY + 13, bx - 6, WY + 13], 2, White(alpha));
  Line(bx, WY - 4, bx, WY + 4, 2.5, White(alpha));
  Disc(bx, WY + 8, 1.4, White(alpha));
  // 3) solid triangle, the "!" is cut out in Navy on the glow layer
  bx := bx + 42;
  FillPoly([bx, WY - 16, bx + 18, WY + 14, bx - 18, WY + 14], White(alpha));
  FLayer.FillPolyAntialias(Pts([bx - 2, WY - 5, bx + 2, WY - 5, bx + 1.2, WY + 5, bx - 1.2, WY + 5]), Navy);
  FLayer.FillEllipseAntialias(X(bx), Y(WY + 9), 1.8 * K, 1.8 * K, Navy);
end;

procedure THUDIconSetWidget.DrawStatic;
var
  i: integer;
  bx, by: single;
  hex: array[0..11] of single;
begin
  // row 1: light corner brackets, row 2: heavy corner brackets
  for i := 0 to 3 do
  begin
    bx := AX + i * 40;
    by := AY;
    case i of
      0: begin
           PolyLine([bx, by + 30, bx, by + 6, bx + 6, by, bx + 30, by], 2, White);
           Line(bx + 3, by + 14, bx + 3, by + 24, 1.5, White(180));
         end;
      1: PolyLine([bx, by + 30, bx, by, bx + 30, by], 2.5, White);
      2: begin
           PolyLine([bx, by + 30, bx, by + 4, bx + 4, by, bx + 30, by], 1.5, White);
           Line(bx + 4, by + 4, bx + 14, by + 4, 2, White);
         end;
      3: begin
           PolyLine([bx, by + 30, bx, by + 10, bx + 10, by, bx + 30, by], 2, White);
           FillPoly([bx - 1, by + 10, bx + 10, by - 1, bx + 10, by + 4, bx + 4, by + 10], White);
         end;
    end;
    by := AY + 38;
    case i of
      0: begin
           FillPoly([bx, by + 32, bx, by + 6, bx + 6, by, bx + 30, by, bx + 30, by + 3,
                     bx + 7, by + 3, bx + 3, by + 7, bx + 3, by + 32], White);
           FillPoly([bx + 3, by + 9, bx + 9, by + 3, bx + 9, by + 9], White);
         end;
      1: FillPoly([bx, by + 32, bx, by, bx + 30, by, bx + 30, by + 4, bx + 4, by + 4, bx + 4, by + 32], White);
      2: begin
           FillPoly([bx, by + 32, bx, by, bx + 30, by, bx + 30, by + 2.5, bx + 2.5, by + 2.5, bx + 2.5, by + 32], White);
           FillPoly([bx + 4, by + 4, bx + 14, by + 4, bx + 4, by + 14], White(200));
         end;
      3: FillPoly([bx, by + 32, bx, by + 10, bx + 10, by, bx + 30, by, bx + 30, by + 4,
                   bx + 12, by + 4, bx + 4, by + 12, bx + 4, by + 32], White);
    end;
  end;
  // frame shapes: hexagon, square, circle
  by := AY + 14;
  for i := 0 to 5 do
  begin
    hex[2 * i] := SX + 16 * Cos(DegToRad(i * 60));
    hex[2 * i + 1] := by + 16 * Sin(DegToRad(i * 60));
  end;
  Polygon(hex, 2.5, White);
  Polygon([SX + 25, by - 14, SX + 53, by - 14, SX + 53, by + 14, SX + 25, by + 14], 2.5, White);
  Ring(SX + 82, by, 15, 2.5, White);
  if FBlinkRate = 0 then
    DrawWarnings(255);
end;

procedure THUDIconSetWidget.DrawDynamic;
begin
  if FBlinkRate > 0 then
    DrawWarnings(Round(255 * Blink));
end;

procedure THUDIconSetWidget.DefineDirty;
begin
  // only animated when blinking
  if FBlinkRate > 0 then
    AddDirty(SX - 18, WY - 16, SX + 100, WY + 14);
end;

procedure THUDIconSetWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 330 x 130. Grid origin (AX, AY) = (25, 32), shapes column SX = 205.');
  L.Add('');
  L.Add('CORNER BRACKETS (DrawStatic), 30 x 30, columns every 40 units');
  L.Add('  Row 1 (y = AY, light strokes)');
  L.Add('    #1 chamfered 6, w2  + inner tick w1.5 White a180');
  L.Add('    #2 square corner w2.5');
  L.Add('    #3 chamfered 4, w1.5 + top accent w2');
  L.Add('    #4 chamfered 10, w2 + filled chamfer wedge');
  L.Add('  Row 2 (y = AY + 38, filled 3-4 unit thick)');
  L.Add('    #1 chamfered + triangular notch   #2 square 4 thick');
  L.Add('    #3 thin 2.5 + inner triangle a200  #4 chamfered 10, 4 thick');
  L.Add('');
  L.Add('FRAME SHAPES (y = AY + 14), stroke w2.5 White');
  L.Add('  Hexagon r16 at SX, square 28 x 28 at SX+25, circle r15 at SX+82');
  L.Add('');
  L.Add('WARNINGS (y = WY = AY + 52)');
  L.Add('  #1 outlined triangle w3 + "!" (bar w3, dot r1.6) at SX');
  L.Add('  #2 broken triangle (3 strokes w2) + "!" at SX+40');
  L.Add('  #3 solid triangle with Navy cut-out "!" at SX+82');
  L.Add('  Static when Alert blink rate = 0, otherwise drawn in DrawDynamic with');
  L.Add('  alpha = 255 * (0.55 + 0.45 cos(2 pi t rate)).');
  L.Add('');
  L.Add('DIRTY RECT        none (static) / warning row when blinking');
end;

procedure THUDIconSetWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  if FBlinkRate > 0 then
    L.Add(Format('Warning intensity   %.0f %%', [Blink * 100]))
  else
    L.Add('Warnings            static');
end;

end.
