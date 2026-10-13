unit UHexBackground;

{ Hex Background - dark navy sci-fi background with floating hexagons.

  Static part (rendered once per size / seed, kept in Background):
    1. base       : dark navy fill + soft radial haze
    2. bokeh      : blurred out-of-focus light blobs
    3. hex layers : far / mid / focus / near honeycomb layers; each layer is
                    drawn on its own bitmap and blurred by its distance from
                    the focus plane (fake depth of field). Hexagons are drawn
                    as thin prisms extruded toward a vanishing point (3D look).
                    The cluster dissolves toward the upper-left: cells near
                    the edge drift away as loose single hexagons.
    4. vignette   : darkened corners, deep shadow top-left
  Dynamic part (DrawFrame): orange sparks that rise, sway and twinkle.

  Usage:
    Hex := THexBackground.Create;
    Hex.Render(W, H, Seed);     // heavy, call on resize
    Hex.Animate(dt);            // per frame
    Hex.DrawFrame(FrameBmp);    // background + sparks into FrameBmp }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes;

type
  THexLayer = record
    Scale: single;    // hex size relative to the focus layer
    Blur: single;     // blur radius relative to the base hex size
    EdgeA: single;    // edge alpha 0..255
    FillA: single;    // face fill alpha 0..255
    Density: single;  // 0..1 chance a covered cell holds a hexagon
    Reach: single;    // shifts the cluster edge (+ = reaches further up-left)
    Glow: single;     // 0 = no glow, 1 = full glow around edges
  end;

  TSpark = record
    X, Y, Size, Alpha: single;
    Life, LifeSpeed: single;
    Phase, Twinkle, VY, Sway: single;
    Soft: boolean;
  end;

  { THexBackground }

  THexBackground = class
  private
    FWidth, FHeight: integer;
    FScale: single;                     // hex circumradius of the focus layer
    FBackground: TBGRABitmap;
    FSparks: array of TSpark;
    FTime: single;
    FNoiseF, FNoiseP: array[0..2] of single;
    function Coverage(x, y: single): single;
    function Noise(x, y: single): single;
    procedure RenderBase;
    procedure RenderBokeh;
    procedure RenderHexLayer(const L: THexLayer);
    procedure RenderVignette;
    procedure NewSpark(var S: TSpark; RandomLife: boolean);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Render(AWidth, AHeight, ASeed: integer);
    procedure Animate(dt: single);
    procedure DrawFrame(Dest: TBGRABitmap);
    property Background: TBGRABitmap read FBackground;
    property Width: integer read FWidth;
    property Height: integer read FHeight;
  end;

implementation

const
  LayerFar:   THexLayer = (Scale: 0.55; Blur: 0.16; EdgeA: 105; FillA: 90;  Density: 0.95; Reach: 0.06;  Glow: 0);
  LayerMid:   THexLayer = (Scale: 0.78; Blur: 0.06; EdgeA: 160; FillA: 140; Density: 0.80; Reach: 0.02;  Glow: 0.4);
  LayerFocus: THexLayer = (Scale: 1.00; Blur: 0;    EdgeA: 235; FillA: 185; Density: 0.72; Reach: -0.02; Glow: 1);
  LayerNear:  THexLayer = (Scale: 1.75; Blur: 0.22; EdgeA: 150; FillA: 165; Density: 0.40; Reach: -0.28; Glow: 0.5);


function SmoothStep(e0, e1, x: single): single;
begin
  Result := EnsureRange((x - e0) / (e1 - e0), 0, 1);
  Result := Result * Result * (3 - 2 * Result);
end;

function HexPoints(cx, cy, r, rot: single): ArrayOfTPointF;
var
  i: integer;
  a: single;
begin
  SetLength(Result, 6);
  for i := 0 to 5 do
  begin
    a := rot + i * Pi / 3;              // flat-top hexagon
    Result[i] := PointF(cx + r * Cos(a), cy + r * Sin(a));
  end;
end;

procedure DrawHexPrism(Bmp: TBGRABitmap; cx, cy, r, rot: single; Ext: TPointF;
  EdgeA, FillA, LineW: single);
var
  F, B, Inner: ArrayOfTPointF;
  i: integer;
begin
  F := HexPoints(cx, cy, r, rot);
  B := HexPoints(cx + Ext.x, cy + Ext.y, r * 0.95, rot);
  Inner := HexPoints(cx, cy, r * 0.86, rot);

  // back face and side edges (the far side of the prism)
  Bmp.DrawPolygonAntialias(B, BGRA(110, 140, 195, Round(EdgeA * 0.35)), LineW * 0.8);
  for i := 0 to 5 do
    Bmp.DrawLineAntialias(F[i].x, F[i].y, B[i].x, B[i].y,
      BGRA(110, 140, 195, Round(EdgeA * 0.25)), LineW * 0.7);

  // front face: dark glassy fill + bright rim + faint inner rim
  Bmp.DrawPolygonAntialias(F, BGRA(195, 215, 250, Round(EdgeA)), LineW,
    BGRA(8, 14, 30, Round(FillA)));
  Bmp.DrawPolygonAntialias(Inner, BGRA(140, 170, 225, Round(EdgeA * 0.22)), LineW * 0.5);
  // small specular on the upper-left edges
  Bmp.DrawLineAntialias(F[3].x, F[3].y, F[4].x, F[4].y,
    BGRA(235, 245, 255, Round(EdgeA * 0.6)), LineW * 0.6);
end;

{ THexBackground }

constructor THexBackground.Create;
begin
  FBackground := TBGRABitmap.Create(1, 1, BGRA(5, 8, 18));
end;

destructor THexBackground.Destroy;
begin
  FBackground.Free;
  inherited Destroy;
end;

// Signed distance (in normalized units) below the diagonal edge of the
// cluster: > 0 inside the hex field (bottom / right), < 0 in the empty
// upper-left area.
function THexBackground.Coverage(x, y: single): single;
var
  u, v: single;
begin
  u := x / FWidth;
  v := y / FHeight;
  Result := v - (0.80 - 0.62 * u);
end;

// Cheap smooth noise 0..1 used to break the cluster into patches.
function THexBackground.Noise(x, y: single): single;
begin
  x := x / FScale;
  y := y / FScale;
  Result := 0.5 + (Sin(x * FNoiseF[0] + FNoiseP[0]) * Sin(y * FNoiseF[1] + FNoiseP[1])
    + 0.5 * Sin((x + y) * FNoiseF[2] + FNoiseP[2])) / 3;
end;

procedure THexBackground.RenderBase;
var
  M: single;
begin
  M := Max(FWidth, FHeight);
  FBackground.Fill(BGRA(5, 8, 18));
  // main haze, lower-left / centre
  FBackground.GradientFill(0, 0, FWidth, FHeight, BGRA(36, 54, 90), BGRA(36, 54, 90, 0),
    gtRadial, PointF(FWidth * 0.28, FHeight * 0.70),
    PointF(FWidth * 0.28 + M * 0.70, FHeight * 0.70), dmDrawWithTransparency);
  // glow behind the dense part of the cluster
  FBackground.GradientFill(0, 0, FWidth, FHeight, BGRA(45, 66, 110, 210), BGRA(45, 66, 110, 0),
    gtRadial, PointF(FWidth * 0.65, FHeight * 0.95),
    PointF(FWidth * 0.65 + M * 0.55, FHeight * 0.95), dmDrawWithTransparency);
  // faint light at the top-right
  FBackground.GradientFill(0, 0, FWidth, FHeight, BGRA(32, 48, 82, 200), BGRA(32, 48, 82, 0),
    gtRadial, PointF(FWidth * 0.95, FHeight * 0.10),
    PointF(FWidth * 0.95 + M * 0.40, FHeight * 0.10), dmDrawWithTransparency);
end;

procedure THexBackground.RenderBokeh;
var
  Layer: TBGRABitmap;
  i, n: integer;
  x, y, t, r: single;
begin
  Layer := TBGRABitmap.Create(FWidth, FHeight, BGRAPixelTransparent);
  try
    n := EnsureRange(FWidth * FHeight div 7000, 40, 260);
    for i := 1 to n do
    begin
      x := Random * FWidth;
      y := Random * FHeight;
      t := Coverage(x, y);
      // most blobs float along the edge of the cluster
      if Random > 0.15 + 0.85 * Exp(-Sqr(t / 0.22)) then Continue;
      if Random < 0.7 then
      begin
        r := FScale * (0.25 + Random * 0.75);         // big soft blob
        Layer.FillEllipseAntialias(x, y, r, r, BGRA(100, 130, 180, 12 + Random(38)));
      end
      else
      begin
        r := FScale * (0.06 + Random * 0.12);         // small bright dot
        Layer.FillEllipseAntialias(x, y, r, r, BGRA(170, 200, 240, 60 + Random(90)));
      end;
    end;
    BGRAReplace(Layer, Layer.FilterBlurRadial(FScale * 0.14, rbFast));
    FBackground.PutImage(0, 0, Layer, dmDrawWithTransparency);
  finally
    Layer.Free;
  end;
end;

procedure THexBackground.RenderHexLayer(const L: THexLayer);
var
  Layer, Glow: TBGRABitmap;
  r, rr, dx, dy, ox, oy, cx, cy, t, p, rot, jit, lw, vx, vy, len: single;
  col, row, cols, rows: integer;
  Ext: TPointF;
  Loose: boolean;
begin
  r := FScale * L.Scale;
  dx := 1.5 * r * 1.10;                 // 10% gap between neighbours
  dy := Sqrt(3) * r * 1.10;
  lw := Max(1.0, r * 0.055);
  ox := -Random * dx;
  oy := -Random * dy;
  cols := Ceil((FWidth + 2 * r) / dx) + 2;
  rows := Ceil((FHeight + 2 * r) / dy) + 2;
  vx := FWidth * 0.30;                  // vanishing point of the prisms
  vy := FHeight * 0.30;

  Layer := TBGRABitmap.Create(FWidth, FHeight, BGRAPixelTransparent);
  Glow := nil;
  if L.Glow > 0 then
    // opaque black: adding black changes nothing, so only the glow shows
    Glow := TBGRABitmap.Create(FWidth, FHeight, BGRABlack);
  try
    for col := 0 to cols - 1 do
      for row := 0 to rows - 1 do
      begin
        cx := ox + col * dx;
        cy := oy + row * dy;
        if Odd(col) then cy := cy + dy / 2;

        t := Coverage(cx, cy) + L.Reach;
        p := SmoothStep(-0.05, 0.30, t) * L.Density *
          (0.25 + 0.75 * SmoothStep(0.30, 0.70, Noise(cx, cy)));
        Loose := False;
        if Random >= p then
        begin
          // a few stray hexagons floating off the edge of the cluster
          if (t > -0.32) and (t < 0.10) and (Random < 0.05 * L.Density) then
            Loose := True
          else
            Continue;
        end;

        rot := (Random - 0.5) * Pi / 30;
        rr := r * (0.93 + Random * 0.10);
        if Loose then
        begin
          jit := r * (0.5 + Random * 1.5);
          cx := cx - jit * 0.6;
          cy := cy - jit * 0.8;
          rot := (Random - 0.5) * Pi / 6;
          rr := rr * (0.6 + Random * 0.35);
        end
        else if p < 0.4 * L.Density then
        begin
          // wobbly cells at the edge of the cluster
          cx := cx + (Random - 0.5) * r * 0.3;
          cy := cy + (Random - 0.5) * r * 0.3;
        end;

        Ext := PointF((vx - cx) * 0.05 * L.Scale, (vy - cy) * 0.05 * L.Scale);
        len := Sqrt(Sqr(Ext.x) + Sqr(Ext.y));
        if len > rr * 0.35 then
          Ext := Ext * (rr * 0.35 / len);

        DrawHexPrism(Layer, cx, cy, rr, rot, Ext, L.EdgeA, L.FillA, lw);
        if Glow <> nil then
          Glow.DrawPolygonAntialias(HexPoints(cx, cy, rr, rot),
            BGRA(70, 110, 190, Round(L.EdgeA * L.Glow * 0.55)), lw * 2.5);
      end;

    if Glow <> nil then
    begin
      BGRAReplace(Glow, Glow.FilterBlurRadial(r * 0.30 + FScale * L.Blur, rbFast));
      FBackground.BlendImage(0, 0, Glow, boAdditive);
    end;
    if L.Blur > 0 then
      BGRAReplace(Layer, Layer.FilterBlurRadial(FScale * L.Blur, rbFast));
    FBackground.PutImage(0, 0, Layer, dmDrawWithTransparency);
  finally
    Glow.Free;
    Layer.Free;
  end;
end;

procedure THexBackground.RenderVignette;
var
  D: single;
begin
  D := Sqrt(Sqr(FWidth) + Sqr(FHeight));
  FBackground.GradientFill(0, 0, FWidth, FHeight, BGRA(0, 0, 0, 0), BGRA(0, 0, 0, 160),
    gtRadial, PointF(FWidth * 0.5, FHeight * 0.55),
    PointF(FWidth * 0.5 + D * 0.62, FHeight * 0.55), dmDrawWithTransparency);
  // deep shadow in the empty top-left corner
  FBackground.GradientFill(0, 0, FWidth, FHeight, BGRA(0, 0, 0, 130), BGRA(0, 0, 0, 0),
    gtLinear, PointF(0, 0), PointF(FWidth * 0.45, FHeight * 0.40), dmDrawWithTransparency);
end;

procedure THexBackground.NewSpark(var S: TSpark; RandomLife: boolean);
var
  t: single;
begin
  // sparks live mostly inside the hex field
  repeat
    S.X := Random * FWidth;
    S.Y := Random * FHeight;
    t := Coverage(S.X, S.Y);
  until Random < 0.06 + 0.94 * SmoothStep(-0.08, 0.35, t);
  S.Soft := Random < 0.3;
  S.Size := FScale * (0.02 + Random * 0.045);
  if S.Soft then S.Size := S.Size * 1.3;
  S.Alpha := 120 + Random * 135;
  S.Phase := Random * 2 * Pi;
  S.Twinkle := 2 + Random * 6;
  S.VY := -(3 + Random * 14);
  S.Sway := 2 + Random * 8;
  S.LifeSpeed := 1 / (3 + Random * 6);
  if RandomLife then S.Life := Random else S.Life := 0;
end;

procedure THexBackground.Render(AWidth, AHeight, ASeed: integer);
var
  i: integer;
begin
  FWidth := Max(AWidth, 16);
  FHeight := Max(AHeight, 16);
  FScale := Sqrt(FWidth * FHeight) * 0.04;
  RandSeed := ASeed;
  for i := 0 to 2 do
  begin
    FNoiseF[i] := 0.12 + Random * 0.25;
    FNoiseP[i] := Random * 2 * Pi;
  end;

  FBackground.SetSize(FWidth, FHeight);
  RenderBase;
  RenderBokeh;
  RenderHexLayer(LayerFar);
  RenderHexLayer(LayerMid);
  RenderHexLayer(LayerFocus);
  RenderHexLayer(LayerNear);
  RenderVignette;

  SetLength(FSparks, EnsureRange(FWidth * FHeight div 3000, 60, 700));
  for i := 0 to High(FSparks) do
    NewSpark(FSparks[i], True);
end;

procedure THexBackground.Animate(dt: single);
var
  i: integer;
begin
  FTime := FTime + dt;
  for i := 0 to High(FSparks) do
    with FSparks[i] do
    begin
      Life := Life + dt * LifeSpeed;
      Y := Y + VY * dt;
      X := X + Cos(FTime * 0.7 + Phase) * Sway * dt;
      if Life >= 1 then NewSpark(FSparks[i], False);
    end;
end;

procedure THexBackground.DrawFrame(Dest: TBGRABitmap);
var
  i: integer;
  a: single;
begin
  Dest.SetSize(FWidth, FHeight);
  Dest.PutImage(0, 0, FBackground, dmSet);
  for i := 0 to High(FSparks) do
    with FSparks[i] do
    begin
      a := Alpha * Sin(Pi * Life) * (0.6 + 0.4 * Sin(FTime * Twinkle + Phase));
      if a < 3 then Continue;
      if Soft then
        Dest.FillEllipseAntialias(X, Y, Size * 1.6, Size * 1.6, BGRA(255, 150, 50, Round(a * 0.22)))
      else
      begin
        Dest.FillEllipseAntialias(X, Y, Size * 3, Size * 3, BGRA(255, 130, 30, Round(a * 0.18)));
        Dest.FillEllipseAntialias(X, Y, Size, Size, BGRA(255, 196, 110, Round(a)));
      end;
    end;
end;

end.
