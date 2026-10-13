unit HUDRender;

{ Sci-Fi HUD Interface Kit renderer.
  Everything is drawn with BGRABitmap in a 740 x 960 design space that is
  scaled to fit the target size.

  Performance design:
  - Every widget has a static part and an animated part. The static part is
    drawn once per window size (FStatic = True) and composed together with
    the background and its glow into FStaticOut.
  - Each frame only the animated parts are drawn into FLayer / FFill.
  - Glow = 4x box-downsample of FLayer -> fast blur -> one custom pass that
    upsamples bilinearly, adds the glow and alpha-blends the layers. }

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF} Classes, SysUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes;

const
  DesignW = 740;
  DesignH = 960;
  GlowScale = 4;    // glow is computed at 1/4 resolution
  GlowGain = 330;   // glow intensity, 256 = 1.0

type

  { THUDRenderer }

  THUDRenderer = class
  private
    FBack: TBGRABitmap;       // background (gradient + grid + soft glows)
    FStaticOut: TBGRABitmap;  // background + static widgets + their glow
    FLayer: TBGRABitmap;      // bright strokes, transparent, gets the glow
    FFill: TBGRABitmap;       // translucent fills, drawn without glow
    FSmall: TBGRABitmap;      // downsampled layer used to compute the glow
    FOut: TBGRABitmap;        // final composed image
    FTextCache: TStringList;  // pre-rendered dynamic texts (percentages)
    FStatic: boolean;         // True while building the static cache
    K, OX, OY: single;        // design -> pixel transform
    T: single;                // animation time in seconds
    // glow upsampling tables
    FXI0, FXI1, FWX: array of integer;
    FRowR, FRowG, FRowB: array of integer;
    FDirty: array of TRect;   // pixel rects that contain animated content

    function X(v: single): single; inline;
    function Y(v: single): single; inline;
    function Pt(ax, ay: single): TPointF; inline;
    function ArcPts(cx, cy, r, a0, a1: single): ArrayOfTPointF;
    function Pts(const A: array of single): ArrayOfTPointF;
    function Dest(c: TBGRAPixel): TBGRABitmap;

    { drawing primitives (design units, angles in degrees, clockwise from 3 o'clock) }
    procedure Arc(cx, cy, r, a0, a1, w: single; c: TBGRAPixel);
    procedure Band(cx, cy, r1, r2, a0, a1: single; c: TBGRAPixel);
    procedure Pie(cx, cy, r, a0, a1: single; c: TBGRAPixel);
    procedure Ring(cx, cy, r, w: single; c: TBGRAPixel);
    procedure Disc(cx, cy, r: single; c: TBGRAPixel);
    procedure SoftDisc(B: TBGRABitmap; cx, cy, r: single; inner: TBGRAPixel);
    procedure Ticks(cx, cy, r1, r2: single; n: integer; a0, a1, w: single; c: TBGRAPixel);
    procedure Dots(cx, cy, r: single; n: integer; dotR, a0: single; c: TBGRAPixel);
    procedure Line(x1, y1, x2, y2, w: single; c: TBGRAPixel);
    procedure PolyLine(const A: array of single; w: single; c: TBGRAPixel);
    procedure Polygon(const A: array of single; w: single; c: TBGRAPixel);
    procedure FillPoly(const A: array of single; c: TBGRAPixel);
    procedure Txt(ax, ay: single; const S: string; size: single; c: TBGRAPixel;
      align: TAlignment = taLeftJustify);
    procedure TxtCached(ax, ay: single; const S: string; size: single; align: TAlignment);

    { background, static cache and composition }
    procedure BuildBackground(W, H: integer);
    procedure DrawWidgets;
    procedure BuildDirtyRects(W, H: integer);
    procedure DownsampleLayer(const SR: TRect);
    procedure ComposeRect(Base, Dst: TBGRABitmap; const DR: TRect; Glow: TBGRACustomBitmap; gx0, gy0: integer);
    procedure Compose(Base, Dst: TBGRABitmap; const Rects: array of TRect);

    { widgets }
    procedure DrawOpticScanner(cx, cy: single);
    procedure DrawTargetLock(cx, cy: single);
    procedure DrawShieldCore(cx, cy: single);
    procedure DrawCornerIcons(ax, ay: single);
    procedure DrawDataPanels(ax: single);
    procedure DrawRadarSweep(cx, cy: single; heavy: boolean; speed: single);
    procedure DrawHexCube(cx, cy: single);
    procedure DrawCrosshair(cx, cy: single);
    procedure DrawLoadingChevron(ay, p: single);
    procedure DrawLoadingPill(ay, p: single);
    procedure DrawLoadingBlocks(ay, p: single);
    procedure DrawLoadingSlant(ay, p: single);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Render(W, H: integer; ATime: single);
    property Output: TBGRABitmap read FOut;
  public
    Prof: array[0..6] of double;  // accumulated ms per stage (benchmark)
  end;

function NowMs: double;

implementation

function NowMs: double;
{$IFDEF WINDOWS}
var c, f: Int64;
begin
  QueryPerformanceCounter(c);
  QueryPerformanceFrequency(f);
  Result := c * 1000 / f;
end;
{$ELSE}
begin
  Result := GetTickCount64;
end;
{$ENDIF}

{ ---------- palette ---------- }

function White(a: byte = 255): TBGRAPixel; begin Result := BGRA(236, 247, 255, a); end;
function Ice(a: byte = 255): TBGRAPixel;   begin Result := BGRA(150, 212, 242, a); end;
function Steel(a: byte = 255): TBGRAPixel; begin Result := BGRA(96, 140, 186, a); end;
function Navy(a: byte = 255): TBGRAPixel;  begin Result := BGRA(22, 46, 78, a); end;

{ ---------- transform & geometry ---------- }

function THUDRenderer.X(v: single): single;
begin
  Result := OX + v * K;
end;

function THUDRenderer.Y(v: single): single;
begin
  Result := OY + v * K;
end;

function THUDRenderer.Pt(ax, ay: single): TPointF;
begin
  Result := PointF(X(ax), Y(ay));
end;

function THUDRenderer.ArcPts(cx, cy, r, a0, a1: single): ArrayOfTPointF;
var
  n, i: integer;
  a: single;
begin
  n := Max(3, Round(Abs(a1 - a0) * Pi / 180 * r * K / 3) + 2);
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    a := DegToRad(a0 + (a1 - a0) * i / (n - 1));
    Result[i] := Pt(cx + r * Cos(a), cy + r * Sin(a));
  end;
end;

function THUDRenderer.Pts(const A: array of single): ArrayOfTPointF;
var
  i: integer;
begin
  SetLength(Result, Length(A) div 2);
  for i := 0 to High(Result) do
    Result[i] := Pt(A[2 * i], A[2 * i + 1]);
end;

function THUDRenderer.Dest(c: TBGRAPixel): TBGRABitmap;
begin
  // translucent or dark surfaces go to the fill layer so they do not bloom
  if (c.alpha < 200) or (c.red + c.green + c.blue < 200) then Result := FFill else Result := FLayer;
end;

function JoinPts(const A, B: ArrayOfTPointF): ArrayOfTPointF;
var
  i: integer;
begin
  SetLength(Result, Length(A) + Length(B));
  for i := 0 to High(A) do Result[i] := A[i];
  for i := 0 to High(B) do Result[Length(A) + i] := B[i];
end;

{ ---------- primitives ---------- }

procedure THUDRenderer.Arc(cx, cy, r, a0, a1, w: single; c: TBGRAPixel);
begin
  FLayer.DrawPolyLineAntialias(ArcPts(cx, cy, r, a0, a1), c, w * K);
end;

procedure THUDRenderer.Band(cx, cy, r1, r2, a0, a1: single; c: TBGRAPixel);
begin
  Dest(c).FillPolyAntialias(JoinPts(ArcPts(cx, cy, r2, a0, a1), ArcPts(cx, cy, r1, a1, a0)), c);
end;

procedure THUDRenderer.Pie(cx, cy, r, a0, a1: single; c: TBGRAPixel);
var
  P: ArrayOfTPointF;
begin
  SetLength(P, 1);
  P[0] := Pt(cx, cy);
  Dest(c).FillPolyAntialias(JoinPts(P, ArcPts(cx, cy, r, a0, a1)), c);
end;

procedure THUDRenderer.Ring(cx, cy, r, w: single; c: TBGRAPixel);
begin
  FLayer.EllipseAntialias(X(cx), Y(cy), r * K, r * K, c, w * K);
end;

procedure THUDRenderer.Disc(cx, cy, r: single; c: TBGRAPixel);
begin
  Dest(c).FillEllipseAntialias(X(cx), Y(cy), r * K, r * K, c);
end;

procedure THUDRenderer.SoftDisc(B: TBGRABitmap; cx, cy, r: single; inner: TBGRAPixel);
var
  outer: TBGRAPixel;
begin
  outer := inner;
  outer.alpha := 0;
  B.FillEllipseLinearColorAntialias(X(cx), Y(cy), r * K, r * K, outer, inner);
end;

procedure THUDRenderer.Ticks(cx, cy, r1, r2: single; n: integer; a0, a1, w: single; c: TBGRAPixel);
var
  i: integer;
  a, ca, sa, hw: single;
  P: ArrayOfTPointF;
begin
  // all ticks as one multi-polygon (EmptyPointF separated) = a single fill call
  if n <= 0 then Exit;
  SetLength(P, n * 5 - 1);
  hw := w / 2;
  for i := 0 to n - 1 do
  begin
    a := DegToRad(a0 + (a1 - a0) * i / n);
    ca := Cos(a);
    sa := Sin(a);
    P[i * 5]     := Pt(cx + r1 * ca - hw * sa, cy + r1 * sa + hw * ca);
    P[i * 5 + 1] := Pt(cx + r2 * ca - hw * sa, cy + r2 * sa + hw * ca);
    P[i * 5 + 2] := Pt(cx + r2 * ca + hw * sa, cy + r2 * sa - hw * ca);
    P[i * 5 + 3] := Pt(cx + r1 * ca + hw * sa, cy + r1 * sa - hw * ca);
    if i < n - 1 then P[i * 5 + 4] := EmptyPointF;
  end;
  FLayer.FillPolyAntialias(P, c);
end;

procedure THUDRenderer.Dots(cx, cy, r: single; n: integer; dotR, a0: single; c: TBGRAPixel);
const
  M = 8; // a dot of 1-3 px needs only an octagon
var
  i, j: integer;
  a, dx, dy: single;
  P: ArrayOfTPointF;
begin
  SetLength(P, n * (M + 1) - 1);
  for i := 0 to n - 1 do
  begin
    a := DegToRad(a0 + 360 * i / n);
    dx := cx + r * Cos(a);
    dy := cy + r * Sin(a);
    for j := 0 to M - 1 do
      P[i * (M + 1) + j] := Pt(dx + dotR * Cos(j * 2 * Pi / M), dy + dotR * Sin(j * 2 * Pi / M));
    if i < n - 1 then P[i * (M + 1) + M] := EmptyPointF;
  end;
  Dest(c).FillPolyAntialias(P, c);
end;

procedure THUDRenderer.Line(x1, y1, x2, y2, w: single; c: TBGRAPixel);
begin
  FLayer.DrawLineAntialias(X(x1), Y(y1), X(x2), Y(y2), c, w * K);
end;

procedure THUDRenderer.PolyLine(const A: array of single; w: single; c: TBGRAPixel);
begin
  FLayer.DrawPolyLineAntialias(Pts(A), c, w * K);
end;

procedure THUDRenderer.Polygon(const A: array of single; w: single; c: TBGRAPixel);
begin
  FLayer.DrawPolygonAntialias(Pts(A), c, w * K);
end;

procedure THUDRenderer.FillPoly(const A: array of single; c: TBGRAPixel);
begin
  Dest(c).FillPolyAntialias(Pts(A), c);
end;

procedure THUDRenderer.Txt(ax, ay: single; const S: string; size: single;
  c: TBGRAPixel; align: TAlignment);
begin
  FLayer.FontName := 'Consolas';
  FLayer.FontStyle := [fsBold];
  FLayer.FontQuality := fqFineAntialiasing;
  FLayer.FontHeight := Max(6, Round(size * K));
  FLayer.TextOut(X(ax), Y(ay - size * 0.55), S, c, align);
end;

procedure THUDRenderer.TxtCached(ax, ay: single; const S: string; size: single; align: TAlignment);
var
  idx: integer;
  B: TBGRABitmap;
  sz: TSize;
  px: integer;
begin
  // text rasterization is slow; render each distinct string once per window size
  idx := FTextCache.IndexOf(S);
  if idx < 0 then
  begin
    B := TBGRABitmap.Create(1, 1);
    B.FontName := 'Consolas';
    B.FontStyle := [fsBold];
    B.FontQuality := fqFineAntialiasing;
    B.FontHeight := Max(6, Round(size * K));
    sz := B.TextSize(S);
    B.SetSize(sz.cx + 2, sz.cy + 2);
    B.FillTransparent;
    B.TextOut(1, 1, S, White);
    idx := FTextCache.AddObject(S, B);
  end;
  B := TBGRABitmap(FTextCache.Objects[idx]);
  case align of
    taCenter: px := Round(X(ax) - B.Width / 2);
    taRightJustify: px := Round(X(ax)) - B.Width + 1;
  else
    px := Round(X(ax)) - 1;
  end;
  FLayer.PutImage(px, Round(Y(ay - size * 0.55)) - 1, B, dmDrawWithTransparency);
end;

{ ---------- background ---------- }

procedure THUDRenderer.BuildBackground(W, H: integer);
var
  i: integer;
  gx, gy: single;
begin
  FreeAndNil(FBack);
  FBack := TBGRABitmap.Create(W, H, BGRA(14, 28, 48));
  // deep navy vertical gradient across the design area
  FBack.GradientFill(0, Round(Y(0)), W, Round(Y(DesignH)),
    BGRA(30, 58, 92), BGRA(18, 36, 60), gtLinear,
    PointF(0, Y(0)), PointF(0, Y(DesignH)), dmSet);
  // light bloom in the middle like the original backdrop
  FBack.GradientFill(0, 0, W, H, BGRA(70, 110, 160, 90), BGRA(70, 110, 160, 0),
    gtRadial, PointF(X(430), Y(420)), PointF(X(430 + 420), Y(420)), dmDrawWithTransparency);
  // faint grid
  gx := 0;
  for i := 0 to DesignW div 16 do
  begin
    FBack.DrawLineAntialias(X(gx), Y(0), X(gx), Y(DesignH), BGRA(120, 170, 220, 10), 1);
    gx := gx + 16;
  end;
  gy := 0;
  for i := 0 to DesignH div 16 do
  begin
    FBack.DrawLineAntialias(X(0), Y(gy), X(DesignW), Y(gy), BGRA(120, 170, 220, 10), 1);
    gy := gy + 16;
  end;
  // big soft halo behind the optic scanner wings
  SoftDisc(FBack, 92, 135, 70, White(150));
  SoftDisc(FBack, 352, 135, 70, White(130));
  SoftDisc(FBack, 222, 135, 140, Ice(40));
  SoftDisc(FBack, 222, 385, 140, Ice(30));
  SoftDisc(FBack, 222, 640, 140, Ice(35));
end;

{ ---------- widgets: left column ----------
  In every widget: "if FStatic then" = drawn once into the cache,
  "else" = animated part drawn every frame on top of the cache. }

procedure THUDRenderer.DrawOpticScanner(cx, cy: single);
var
  rot: single;
  i: integer;
begin
  if FStatic then
  begin
    // translucent lens shells left/right
    Disc(cx - 72, cy, 74, Steel(70));
    Disc(cx + 72, cy, 74, Steel(70));
    Arc(cx - 72, cy, 74, 115, 245, 7, White);
    Arc(cx + 72, cy, 74, -65, 65, 7, White);
    Arc(cx - 72, cy, 66, 140, 220, 2, White(160));
    Arc(cx + 72, cy, 66, -40, 40, 2, White(160));
    Disc(cx, cy, 98, Navy(170));
    Ticks(cx, cy, 112, 116, 90, 0, 360, 1, Ice(140));
    Ring(cx, cy, 104, 1.5, Ice(130));
    Arc(cx, cy, 86, 0, 360, 1, Ice(120));
    // lens core
    Ring(cx, cy, 56, 2, Ice(200));
    SoftDisc(FFill, cx, cy, 52, Ice(60));
    Arc(cx, cy, 42, 140, 220, 5, White);
    Arc(cx, cy, 42, -40, 40, 5, White);
    Arc(cx, cy, 34, 0, 360, 1, Ice(90));
    Txt(cx - 120, cy - 42, '052', 11, White);
  end
  else
  begin
    rot := T * 18;
    Ticks(cx, cy, 108, 118, 12, -rot * 0.3, 360 - rot * 0.3, 2, White(220));
    Arc(cx, cy, 94, 205 + rot, 335 + rot, 7, White);
    Arc(cx, cy, 94, 25 + rot, 155 + rot, 7, White);
    for i := 0 to 5 do
      Band(cx, cy, 70, 78, i * 60 - rot * 1.4, i * 60 + 32 - rot * 1.4, White(i mod 2 * 120 + 120));
  end;
end;

procedure THUDRenderer.DrawTargetLock(cx, cy: single);
var
  rot: single;
begin
  if FStatic then
  begin
    Band(cx, cy, 116, 134, 148, 212, Steel(120));
    Band(cx, cy, 116, 134, -32, 32, Steel(120));
    Arc(cx, cy, 134, 150, 210, 2.5, White(230));
    Arc(cx, cy, 134, -30, 30, 2.5, White(230));
    Arc(cx, cy, 116, 150, 210, 1, Ice(160));
    Arc(cx, cy, 116, -30, 30, 1, Ice(160));
    Arc(cx, cy, 128, 215, 325, 1.5, White(220));
    Arc(cx, cy, 128, 35, 145, 1.5, White(220));
    Arc(cx, cy, 138, 240, 300, 1, Ice(140));
    Arc(cx, cy, 138, 60, 120, 1, Ice(140));
    Disc(cx, cy, 112, Navy(110));
    Ring(cx, cy, 112, 1, Ice(140));
    SoftDisc(FFill, cx, cy, 70, Ice(70));
    Ring(cx, cy, 56, 2, White(230));
    Ring(cx, cy, 48, 1, Ice(120));
    FillPoly([cx - 104, cy - 32, cx - 98, cy - 32, cx - 98, cy - 26, cx - 104, cy - 26], White);
    FillPoly([cx + 98, cy - 32, cx + 104, cy - 32, cx + 104, cy - 26, cx + 98, cy - 26], White);
    PolyLine([cx + 96, cy + 22, cx + 104, cy + 22, cx + 104, cy + 30], 1.5, White(200));
    PolyLine([cx - 96, cy + 22, cx - 104, cy + 22, cx - 104, cy + 30], 1.5, White(200));
  end
  else
  begin
    rot := -T * 14;
    Ticks(cx, cy, 103, 108, 120, rot * 0.5, 360 + rot * 0.5, 0.8, Ice(150));
    Arc(cx, cy, 98, 235 + rot, 305 + rot, 3, White);
    Arc(cx, cy, 98, 55 + rot, 125 + rot, 3, White);
    Arc(cx, cy, 98, 150 - rot, 170 - rot, 2, Ice(200));
    Arc(cx, cy, 98, -10 - rot, 10 - rot, 2, Ice(200));
    Dots(cx, cy, 86, 72, 0.9, rot * -0.7, Ice(170));
  end;
end;

procedure THUDRenderer.DrawShieldCore(cx, cy: single);
var
  rot, pulse: single;
begin
  if FStatic then
  begin
    Band(cx, cy, 108, 126, 140, 220, Steel(125));
    Band(cx, cy, 108, 126, -40, 40, Steel(125));
    Arc(cx, cy, 132, 148, 212, 5, White);
    Arc(cx, cy, 132, -32, 32, 5, White);
    Disc(cx, cy, 108, Navy(140));
    Arc(cx, cy, 114, 60, 120, 3, White(220));
    Arc(cx, cy, 114, 240, 300, 1.5, Ice(180));
    Ring(cx, cy, 88, 1.5, Ice(160));
    Ring(cx, cy, 82, 0.8, Ice(90));
    Ring(cx, cy, 52, 1, Ice(120));
    PolyLine([cx - 30, cy - 12, cx - 30, cy - 22, cx - 18, cy - 22], 1.5, White);
    PolyLine([cx + 18, cy - 22, cx + 30, cy - 22, cx + 30, cy - 12], 1.5, White);
    PolyLine([cx - 30, cy + 12, cx - 30, cy + 22, cx - 18, cy + 22], 1.5, White);
    PolyLine([cx + 18, cy + 22, cx + 30, cy + 22, cx + 30, cy + 12], 1.5, White);
    Line(cx - 18, cy, cx + 18, cy, 0.8, Ice(150));
    FillPoly([cx - 104, cy - 5, cx - 104, cy + 5, cx - 110, cy], White);
    FillPoly([cx + 104, cy - 5, cx + 104, cy + 5, cx + 110, cy], White);
    FillPoly([cx - 108, cy + 70, cx - 102, cy + 70, cx - 102, cy + 75, cx - 108, cy + 75], White);
    FillPoly([cx - 100, cy + 70, cx - 94, cy + 70, cx - 94, cy + 75, cx - 100, cy + 75], White(150));
    Txt(cx + 84, cy + 72, 'SIGNAL_8', 7, White(220));
  end
  else
  begin
    rot := T * 10;
    pulse := 0.5 + 0.5 * Sin(T * 3);
    Arc(cx, cy, 102, 200 + rot, 250 + rot, 7, White);
    Arc(cx, cy, 102, 290 + rot, 340 + rot, 7, White);
    Arc(cx, cy, 102, 30 + rot, 80 + rot, 7, White);
    Arc(cx, cy, 102, 100 + rot, 150 + rot, 7, White);
    SoftDisc(FFill, cx, cy, 72, Ice(Round(40 + 50 * pulse)));
    Dots(cx, cy, 62, 48, 1.1, -rot * 2, White(200));
  end;
end;

procedure THUDRenderer.DrawCornerIcons(ax, ay: single);
var
  i: integer;
  bx, by: single;
  hex: array[0..11] of single;
begin
  if not FStatic then Exit; // fully static
  // row 1: light corner brackets, row 2: heavy corner brackets
  for i := 0 to 3 do
  begin
    bx := ax + i * 40;
    by := ay;
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
    by := ay + 38;
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
  // shapes
  bx := ax + 180;
  by := ay + 14;
  for i := 0 to 5 do
  begin
    hex[2 * i] := bx + 16 * Cos(DegToRad(i * 60));
    hex[2 * i + 1] := by + 16 * Sin(DegToRad(i * 60));
  end;
  Polygon(hex, 2.5, White);
  Polygon([bx + 25, by - 14, bx + 53, by - 14, bx + 53, by + 14, bx + 25, by + 14], 2.5, White);
  Ring(bx + 82, by, 15, 2.5, White);
  // warning triangles
  by := ay + 52;
  Polygon([bx, by - 15, bx + 17, by + 13, bx - 17, by + 13], 3, White);
  Line(bx, by - 4, bx, by + 4, 3, White);
  Disc(bx, by + 8, 1.6, White);
  bx := bx + 40;
  PolyLine([bx - 5, by - 7, bx, by - 15, bx + 5, by - 7], 2, White);
  PolyLine([bx + 9, by, bx + 17, by + 13, bx + 6, by + 13], 2, White);
  PolyLine([bx - 9, by, bx - 17, by + 13, bx - 6, by + 13], 2, White);
  Line(bx, by - 4, bx, by + 4, 2.5, White);
  Disc(bx, by + 8, 1.4, White);
  bx := bx + 42;
  FillPoly([bx, by - 16, bx + 18, by + 14, bx - 18, by + 14], White);
  // the cut-out '!' must sit on the glow layer, above the white triangle
  FLayer.FillPolyAntialias(Pts([bx - 2, by - 5, bx + 2, by - 5, bx + 1.2, by + 5, bx - 1.2, by + 5]), Navy);
  FLayer.FillEllipseAntialias(X(bx), Y(by + 9), 1.8 * K, 1.8 * K, Navy);
end;

{ ---------- widgets: right column ---------- }

procedure THUDRenderer.DrawDataPanels(ax: single);
var
  i, j: integer;
  y0, scan: single;
begin
  if FStatic then
  begin
    // panel 1: SIGNAL header with hatched corner
    y0 := 40;
    FillPoly([ax, y0 + 8, ax + 8, y0, ax + 92, y0, ax + 100, y0 + 8, ax + 112, y0 + 8,
              ax + 112, y0 + 66, ax + 104, y0 + 72, ax, y0 + 72], Steel(55));
    Polygon([ax, y0 + 8, ax + 8, y0, ax + 92, y0, ax + 100, y0 + 8, ax + 112, y0 + 8,
             ax + 112, y0 + 66, ax + 104, y0 + 72, ax, y0 + 72], 1.5, Ice(200));
    for i := 0 to 4 do
      Line(ax + 78 + i * 6, y0 + 7, ax + 84 + i * 6, y0 + 1, 2, White(200));
    Line(ax + 112, y0 + 30, ax + 112, y0 + 62, 3, White);
    Line(ax + 30, y0 + 72, ax + 80, y0 + 72, 2.5, White(220));
    Txt(ax + 6, y0 + 6, '\\SIGNAL', 6, White(220));

    // panel 2: glowing top/bottom bars + dot grid
    y0 := 168;
    FillPoly([ax, y0 + 6, ax + 6, y0, ax + 106, y0, ax + 112, y0 + 6, ax + 112, y0 + 56,
              ax + 106, y0 + 62, ax + 6, y0 + 62, ax, y0 + 56], Steel(60));
    Polygon([ax, y0 + 6, ax + 6, y0, ax + 106, y0, ax + 112, y0 + 6, ax + 112, y0 + 56,
             ax + 106, y0 + 62, ax + 6, y0 + 62, ax, y0 + 56], 1.5, Ice(190));
    Line(ax + 38, y0, ax + 74, y0, 4, White);
    Line(ax + 38, y0 + 62, ax + 74, y0 + 62, 4, White);
    Line(ax, y0 + 22, ax, y0 + 40, 3, White(220));
    Line(ax + 112, y0 + 22, ax + 112, y0 + 40, 3, White(220));
    for i := 0 to 12 do
      for j := 0 to 5 do
        Disc(ax + 10 + i * 7.6, y0 + 12 + j * 7.6, 0.6, Ice(90));

    // panel 3: targeting frame
    y0 := 292;
    FillPoly([ax + 8, y0, ax + 104, y0, ax + 112, y0 + 8, ax + 112, y0 + 58, ax + 104, y0 + 64,
              ax + 8, y0 + 64, ax, y0 + 56, ax, y0 + 8], Steel(60));
    Polygon([ax + 8, y0, ax + 104, y0, ax + 112, y0 + 8, ax + 112, y0 + 58, ax + 104, y0 + 64,
             ax + 8, y0 + 64, ax, y0 + 56, ax, y0 + 8], 2, White(230));
    Line(ax + 80, y0 - 4, ax + 112, y0 - 4, 2.5, White);
    FillPoly([ax - 4, y0 + 22, ax + 2, y0 + 22, ax + 2, y0 + 44, ax - 4, y0 + 44], White(220));
    PolyLine([ax + 26, y0 + 22, ax + 26, y0 + 14, ax + 38, y0 + 14], 1.2, Ice(220));
    PolyLine([ax + 74, y0 + 14, ax + 86, y0 + 14, ax + 86, y0 + 22], 1.2, Ice(220));
    PolyLine([ax + 26, y0 + 42, ax + 26, y0 + 50, ax + 38, y0 + 50], 1.2, Ice(220));
    PolyLine([ax + 74, y0 + 50, ax + 86, y0 + 50, ax + 86, y0 + 42], 1.2, Ice(220));
    Line(ax + 52, y0 + 28, ax + 60, y0 + 36, 1.2, White);
    Line(ax + 60, y0 + 28, ax + 52, y0 + 36, 1.2, White);

    // panel 4: status frame
    y0 := 418;
    FillPoly([ax, y0, ax + 94, y0, ax + 112, y0 + 18, ax + 112, y0 + 66, ax, y0 + 66], Steel(45));
    Polygon([ax, y0, ax + 94, y0, ax + 112, y0 + 18, ax + 112, y0 + 66, ax, y0 + 66], 1.2, Ice(180));
    Line(ax, y0 + 2, ax, y0 + 36, 4, White);
    for i := 0 to 4 do
      Disc(ax + 8 + i * 6, y0 + 58, 1.5, White(80));
    Txt(ax + 106, y0 + 58, '06_501', 5.5, Ice(220), taRightJustify);
  end
  else
  begin
    scan := Frac(T * 0.35);
    Line(ax + 6, 60 + scan * 46, ax + 106, 60 + scan * 46, 1, Ice(Round(160 * (1 - scan))));
    Ring(ax + 56, 292 + 32, 10 + 3 * Sin(T * 4), 0.8, Ice(120));
    for i := 0 to Trunc(T * 3) mod 5 do
      Disc(ax + 8 + i * 6, 418 + 58, 1.5, White);
  end;
end;

procedure THUDRenderer.DrawRadarSweep(cx, cy: single; heavy: boolean; speed: single);
var
  a: single;
  i: integer;
begin
  if FStatic then
  begin
    Disc(cx, cy, 38, Navy(150));
    if heavy then
    begin
      Ring(cx, cy, 38, 3.5, White);
      Ring(cx, cy, 43, 1, Ice(160));
    end
    else
    begin
      Ring(cx, cy, 38, 1.5, White);
      Ticks(cx, cy, 40, 45, 72, 0, 360, 0.8, Ice(160));
      Arc(cx, cy, 46, 200, 250, 2, White);
      Arc(cx, cy, 46, 20, 70, 2, White);
    end;
    Ring(cx, cy, 26, 0.8, Ice(150));
    Ring(cx, cy, 14, 0.8, Ice(150));
    Line(cx - 38, cy, cx + 38, cy, 0.7, Ice(110));
    Line(cx, cy - 38, cx, cy + 38, 0.7, Ice(110));
  end
  else
  begin
    a := T * speed;
    // sweep trail: 12 slices of fading alpha
    for i := 0 to 11 do
      Pie(cx, cy, 36, a - (i + 1) * 6, a - i * 6, Ice(Round(110 * (1 - i / 12))));
    Line(cx, cy, cx + 36 * Cos(DegToRad(a)), cy + 36 * Sin(DegToRad(a)), 1.5, White);
    Disc(cx + 18, cy - 12, 1.8, White(Round(255 * Max(0, Cos(DegToRad(a + 34))))));
    Disc(cx - 10, cy + 20, 1.6, White(Round(255 * Max(0, Cos(DegToRad(a - 117))))));
  end;
end;

procedure THUDRenderer.DrawHexCube(cx, cy: single);
var
  i: integer;
  a, r: single;
  outer, inner: array[0..11] of single;
begin
  if not FStatic then
  begin
    SoftDisc(FFill, cx, cy, 12, White(Round(150 + 100 * (0.5 + 0.5 * Sin(T * 2.5)))));
    Exit;
  end;
  for i := 0 to 5 do
  begin
    a := DegToRad(i * 60 - 90);
    outer[2 * i] := cx + 32 * Cos(a);
    outer[2 * i + 1] := cy + 32 * Sin(a);
    inner[2 * i] := cx + 20 * Cos(a);
    inner[2 * i + 1] := cy + 20 * Sin(a);
  end;
  FillPoly(outer, Steel(60));
  Polygon(outer, 2, White);
  Polygon(inner, 1, Ice(160));
  for i := 0 to 5 do
    Line(cx, cy, outer[2 * i], outer[2 * i + 1], 1, Ice(120 + 100 * Ord(i mod 2 = 0)));
  Disc(cx, cy, 3, White);
  r := 40;
  for i := 0 to 5 do
  begin
    a := i * 60 - 90;
    PolyLine([cx + r * Cos(DegToRad(a - 9)), cy + r * Sin(DegToRad(a - 9)),
              cx + (r + 3) * Cos(DegToRad(a)), cy + (r + 3) * Sin(DegToRad(a)),
              cx + r * Cos(DegToRad(a + 9)), cy + r * Sin(DegToRad(a + 9))], 2, White);
  end;
end;

procedure THUDRenderer.DrawCrosshair(cx, cy: single);
var
  a: single;
begin
  if FStatic then
  begin
    Ring(cx, cy, 30, 1.5, White);
    Ring(cx, cy, 20, 0.8, Ice(150));
    Line(cx - 44, cy, cx + 44, cy, 1.2, White);
    Line(cx, cy - 44, cx, cy + 44, 1.2, White);
    Arc(cx, cy, 38, 200, 250, 1.2, Ice(180));
    Arc(cx, cy, 38, 20, 70, 1.2, Ice(180));
    Disc(cx, cy, 3, White);
  end
  else
  begin
    a := T * 40;
    Pie(cx, cy, 30, a - 90, a, Ice(150));
  end;
end;

{ ---------- loading rows ---------- }

procedure THUDRenderer.DrawLoadingChevron(ay, p: single);
var
  gx, bx: single;
  i, n: integer;
begin
  gx := 463;
  n := 14;
  if FStatic then
  begin
    Disc(gx, ay, 30, Navy(200));
    Ring(gx, ay, 30, 1, Ice(120));
    for i := 0 to 3 do
      Arc(gx, ay, 25, i * 90 + 8, i * 90 + 82, 6, Steel(150));
    Ring(gx, ay, 18, 1, Ice(150));
    Polygon([505, ay - 20, 680, ay - 20, 695, ay, 680, ay + 20, 505, ay + 20], 1.2, Ice(180));
    for i := 0 to n - 1 do
    begin
      bx := 512 + i * 12;
      FillPoly([bx, ay - 11, bx + 6, ay - 11, bx + 13, ay, bx + 6, ay + 11, bx, ay + 11, bx + 7, ay],
        Steel(110));
    end;
    Txt(507, ay + 28, 'LOADING...', 7, White(220));
  end
  else
  begin
    Arc(gx, ay, 25, -90, -90 + 360 * p, 6, Ice);
    TxtCached(gx, ay, Format('%d%%', [Round(p * 100)]), 9, taCenter);
    for i := 0 to Round(p * n) - 1 do
    begin
      bx := 512 + i * 12;
      FillPoly([bx, ay - 11, bx + 6, ay - 11, bx + 13, ay, bx + 6, ay + 11, bx, ay + 11, bx + 7, ay],
        White(Round(150 + 105 * i / n)));
    end;
  end;
end;

procedure THUDRenderer.DrawLoadingPill(ay, p: single);
var
  gx: single;
  i, n: integer;
begin
  gx := 461;
  n := 24;
  if FStatic then
  begin
    for i := 0 to n - 1 do
      Disc(gx + 28 * Cos(DegToRad(-90 + i * 15)), ay + 28 * Sin(DegToRad(-90 + i * 15)), 2.2, Steel(150));
    Disc(gx, ay, 20, Navy(200));
    PolyLine([520, ay - 10, 590, ay - 10, 598, ay - 18, 690, ay - 18], 0.8, Ice(160));
    Disc(690, ay - 18, 2, Ice);
    PolyLine([600, ay + 10, 660, ay + 10, 668, ay + 22, 690, ay + 22], 0.8, Ice(160));
    Disc(690, ay + 22, 2, Ice);
    Disc(520, ay - 10, 2, Ice);
    FFill.FillRoundRectAntialias(X(507), Y(ay - 9), X(693), Y(ay + 9), 9 * K, 9 * K, Navy(230));
    FLayer.RoundRectAntialias(X(507), Y(ay - 9), X(693), Y(ay + 9), 9 * K, 9 * K, Steel(150), 1 * K);
    Txt(507, ay + 18, 'LOADING...', 7, White(220));
  end
  else
  begin
    for i := 0 to Round(p * n) - 1 do
      Disc(gx + 28 * Cos(DegToRad(-90 + i * 15)), ay + 28 * Sin(DegToRad(-90 + i * 15)), 2.6, White);
    TxtCached(gx, ay, Format('%d%%', [Round(p * 100)]), 9, taCenter);
    if p > 0.02 then
    begin
      FLayer.GradientFill(Round(X(511)), Round(Y(ay - 5)), Round(X(511 + 178 * p)), Round(Y(ay + 5)),
        Steel(255), Ice(255), gtLinear, PointF(X(511), 0), PointF(X(511 + 178 * p), 0), dmSet);
      Line(511 + 178 * p - 1, ay - 5, 511 + 178 * p - 1, ay + 5, 2, White);
    end;
  end;
end;

procedure THUDRenderer.DrawLoadingBlocks(ay, p: single);
var
  gx, bx: single;
  i, n: integer;
begin
  gx := 463;
  n := 16;
  if FStatic then
  begin
    Disc(gx, ay, 30, Navy(200));
    Ticks(gx, ay, 24, 30, 60, -90, 270, 0.8, Steel(200));
    Ring(gx, ay, 22, 1, Ice(150));
    Ring(gx, ay, 33, 1.5, Ice(180));
    Txt(509, ay - 18, 'LOADING...', 7, White(220));
    Line(560, ay - 18, 690, ay - 18, 1, Ice(150));
    for i := 0 to n - 1 do
    begin
      bx := 509 + i * 11.4;
      FillPoly([bx, ay - 10, bx + 8, ay - 10, bx + 8, ay + 10, bx, ay + 10], Steel(130));
    end;
    Line(500, ay + 16, 690, ay + 16, 1.2, Ice(180));
    Line(520, ay + 21, 640, ay + 21, 2, White(200));
  end
  else
  begin
    Ticks(gx, ay, 24, 30, Round(60 * p), -90, -90 + 360 * p, 1, White);
    TxtCached(gx, ay, Format('%d%%', [Round(p * 100)]), 9, taCenter);
    for i := 0 to Round(p * n) - 1 do
    begin
      bx := 509 + i * 11.4;
      FillPoly([bx, ay - 10, bx + 8, ay - 10, bx + 8, ay + 10, bx, ay + 10],
        White(Round(130 + 125 * i / n)));
    end;
  end;
end;

procedure THUDRenderer.DrawLoadingSlant(ay, p: single);
var
  gx, x1, x2: single;
begin
  gx := 461;
  if FStatic then
  begin
    Disc(gx, ay, 30, Navy(200));
    Arc(gx, ay, 26, 0, 360, 7, Steel(120));
    PolyLine([488, ay + 22, 520, ay - 16, 600, ay - 16, 610, ay - 24, 690, ay - 24], 1, Ice(180));
    PolyLine([488, ay + 22, 690, ay + 22], 1, Ice(180));
    Txt(690, ay + 16, 'LOADING...', 7, White(220), taRightJustify);
  end
  else
  begin
    Arc(gx, ay, 26, -90, -90 + 360 * p, 7, Ice);
    Arc(gx, ay, 26, -90 + 360 * p - 6, -90 + 360 * p, 7, White);
    TxtCached(gx, ay, Format('%d%%', [Round(p * 100)]), 9, taCenter);
    x1 := 500;
    x2 := x1 + 180 * p;
    FillPoly([x1, ay + 16, x1 + 24, ay - 10, x2 + 24, ay - 10, x2, ay + 16], Steel(170));
    FillPoly([x1, ay + 16, x1 + 24, ay - 10, x1 + 70 * p, ay - 10, x1 + 46 * p, ay + 16], Steel(220));
    Line(x2, ay + 16, x2 + 24, ay - 10, 2, White);
  end;
end;

{ ---------- composition ---------- }

constructor THUDRenderer.Create;
begin
  inherited Create;
  FTextCache := TStringList.Create;
  FTextCache.OwnsObjects := True;
  FTextCache.Sorted := True;
end;

destructor THUDRenderer.Destroy;
begin
  FTextCache.Free;
  FBack.Free;
  FStaticOut.Free;
  FLayer.Free;
  FFill.Free;
  FSmall.Free;
  FOut.Free;
  inherited Destroy;
end;

procedure THUDRenderer.DrawWidgets;
var
  t0, t1: double;
begin
  t0 := NowMs;
  DrawOpticScanner(222, 135);
  DrawTargetLock(222, 385);
  DrawShieldCore(222, 640);
  DrawCornerIcons(88, 812);
  t1 := NowMs; Prof[1] += t1 - t0; t0 := t1;

  DrawDataPanels(433);
  DrawRadarSweep(648, 75, False, 90);
  DrawRadarSweep(648, 198, True, -70);
  DrawHexCube(648, 322);
  DrawCrosshair(648, 445);
  t1 := NowMs; Prof[2] += t1 - t0; t0 := t1;

  DrawLoadingChevron(565, Frac(0.65 + T * 0.06));
  DrawLoadingPill(665, Frac(0.85 + T * 0.05));
  DrawLoadingBlocks(770, Frac(0.50 + T * 0.07));
  DrawLoadingSlant(870, Frac(0.75 + T * 0.045));
  t1 := NowMs; Prof[3] += t1 - t0;
end;

procedure THUDRenderer.BuildDirtyRects(W, H: integer);
const
  M = 24; // glow margin in design units (blur radius 4 px at 1/4 scale = 16 + safety)
  Base: array[0..12, 0..3] of single = (
    (100, 13, 344, 257),   // optic scanner rotating parts
    (112, 275, 332, 495),  // target lock
    (116, 534, 328, 746),  // shield core
    (439, 58, 539, 108),   // panel 1 scan line
    (475, 310, 503, 338),  // panel 3 pulse ring
    (439, 472, 475, 480),  // panel 4 status dots
    (610, 37, 686, 113),   // radar 1
    (610, 160, 686, 236),  // radar 2
    (634, 308, 662, 336),  // hex core pulse
    (618, 415, 678, 475),  // crosshair
    (431, 533, 706, 597),  // loading rows 1..4
    (431, 633, 706, 697),
    (431, 738, 706, 902));
var
  i, j, n: integer;
  R: TRect;
  merged: boolean;
begin
  SetLength(FDirty, Length(Base));
  for i := 0 to High(Base) do
  begin
    R.Left := Floor(X(Base[i, 0] - M)) div GlowScale * GlowScale;
    R.Top := Floor(Y(Base[i, 1] - M)) div GlowScale * GlowScale;
    R.Right := (Ceil(X(Base[i, 2] + M)) + GlowScale - 1) div GlowScale * GlowScale;
    R.Bottom := (Ceil(Y(Base[i, 3] + M)) + GlowScale - 1) div GlowScale * GlowScale;
    R.Left := Max(R.Left, 0); R.Top := Max(R.Top, 0);
    R.Right := Min(R.Right, W); R.Bottom := Min(R.Bottom, H);
    FDirty[i] := R;
  end;
  // merge overlapping rects so every pixel is composed exactly once
  n := Length(FDirty);
  repeat
    merged := False;
    for i := 0 to n - 2 do
    begin
      for j := i + 1 to n - 1 do
        if (FDirty[i].Left < FDirty[j].Right) and (FDirty[j].Left < FDirty[i].Right) and
           (FDirty[i].Top < FDirty[j].Bottom) and (FDirty[j].Top < FDirty[i].Bottom) then
        begin
          FDirty[i].Left := Min(FDirty[i].Left, FDirty[j].Left);
          FDirty[i].Top := Min(FDirty[i].Top, FDirty[j].Top);
          FDirty[i].Right := Max(FDirty[i].Right, FDirty[j].Right);
          FDirty[i].Bottom := Max(FDirty[i].Bottom, FDirty[j].Bottom);
          FDirty[j] := FDirty[n - 1];
          Dec(n);
          merged := True;
          Break;
        end;
      if merged then Break;
    end;
  until not merged;
  SetLength(FDirty, n);
end;

procedure THUDRenderer.DownsampleLayer(const SR: TRect);
var
  sx, sy, ix, iy, xs, ys, a: integer;
  r, g, b: cardinal;
  p, d: PBGRAPixel;
begin
  // 4x4 box average of premultiplied colors into the opaque small bitmap
  for sy := SR.Top to SR.Bottom - 1 do
  begin
    d := FSmall.ScanLine[sy] + SR.Left;
    for sx := SR.Left to SR.Right - 1 do
    begin
      r := 0; g := 0; b := 0;
      xs := sx * GlowScale;
      for iy := 0 to GlowScale - 1 do
      begin
        ys := Min(sy * GlowScale + iy, FLayer.Height - 1);
        p := FLayer.ScanLine[ys] + xs;
        for ix := 0 to Min(GlowScale, FLayer.Width - xs) - 1 do
        begin
          a := p^.alpha;
          if a <> 0 then
          begin
            r += p^.red * a;
            g += p^.green * a;
            b += p^.blue * a;
          end;
          Inc(p);
        end;
      end;
      d^.red := r div (255 * GlowScale * GlowScale);
      d^.green := g div (255 * GlowScale * GlowScale);
      d^.blue := b div (255 * GlowScale * GlowScale);
      d^.alpha := 255;
      Inc(d);
    end;
  end;
end;

procedure THUDRenderer.ComposeRect(Base, Dst: TBGRABitmap; const DR: TRect;
  Glow: TBGRACustomBitmap; gx0, gy0: integer);
var
  ix, iy, gw, gh, y0, y1, wy, i0, i1, wx, n: integer;
  r, g, b, a, gr, gg, gb: integer;
  fy: single;
  pb, pf, pl, pd, s0, s1: PBGRAPixel;
  LXI0, LXI1, LWX: array of integer;
begin
  gw := Glow.Width;
  gh := Glow.Height;
  n := DR.Right - DR.Left;
  // glow column indices local to the cropped glow bitmap
  SetLength(LXI0, n); SetLength(LXI1, n); SetLength(LWX, n);
  for ix := 0 to n - 1 do
  begin
    LXI0[ix] := EnsureRange(FXI0[DR.Left + ix] - gx0, 0, gw - 1);
    LXI1[ix] := EnsureRange(FXI1[DR.Left + ix] - gx0, 0, gw - 1);
    LWX[ix] := FWX[DR.Left + ix];
  end;
  for iy := DR.Top to DR.Bottom - 1 do
  begin
    // vertical bilinear interpolation of the glow into a row buffer
    fy := (iy + 0.5) / GlowScale - 0.5;
    y0 := Floor(fy);
    wy := Round((fy - y0) * 256);
    if y0 < 0 then begin y0 := 0; wy := 0; end;
    y1 := EnsureRange(y0 + 1 - gy0, 0, gh - 1);
    y0 := EnsureRange(y0 - gy0, 0, gh - 1);
    s0 := Glow.ScanLine[y0];
    s1 := Glow.ScanLine[y1];
    for ix := 0 to gw - 1 do
    begin
      FRowR[ix] := s0[ix].red * (256 - wy) + s1[ix].red * wy;
      FRowG[ix] := s0[ix].green * (256 - wy) + s1[ix].green * wy;
      FRowB[ix] := s0[ix].blue * (256 - wy) + s1[ix].blue * wy;
    end;

    pb := Base.ScanLine[iy] + DR.Left;
    pf := FFill.ScanLine[iy] + DR.Left;
    pl := FLayer.ScanLine[iy] + DR.Left;
    pd := Dst.ScanLine[iy] + DR.Left;
    for ix := 0 to n - 1 do
    begin
      r := pb^.red; g := pb^.green; b := pb^.blue;
      // 1) translucent fills (alpha blend)
      a := pf^.alpha;
      if a <> 0 then
      begin
        a := a + a shr 7;
        r += SarLongint((pf^.red - r) * a, 8);
        g += SarLongint((pf^.green - g) * a, 8);
        b += SarLongint((pf^.blue - b) * a, 8);
      end;
      // 2) glow (horizontal bilinear + additive)
      i0 := LXI0[ix]; i1 := LXI1[ix]; wx := LWX[ix];
      gr := (FRowR[i0] * (256 - wx) + FRowR[i1] * wx) shr 8;
      gg := (FRowG[i0] * (256 - wx) + FRowG[i1] * wx) shr 8;
      gb := (FRowB[i0] * (256 - wx) + FRowB[i1] * wx) shr 8;
      r += (gr * GlowGain) shr 16;
      g += (gg * GlowGain) shr 16;
      b += (gb * GlowGain) shr 16;
      if r > 255 then r := 255;
      if g > 255 then g := 255;
      if b > 255 then b := 255;
      // 3) crisp strokes on top (alpha blend)
      a := pl^.alpha;
      if a <> 0 then
      begin
        a := a + a shr 7;
        r += SarLongint((pl^.red - r) * a, 8);
        g += SarLongint((pl^.green - g) * a, 8);
        b += SarLongint((pl^.blue - b) * a, 8);
      end;
      pd^.red := r; pd^.green := g; pd^.blue := b; pd^.alpha := 255;
      Inc(pb); Inc(pf); Inc(pl); Inc(pd);
    end;
  end;
end;

procedure THUDRenderer.Compose(Base, Dst: TBGRABitmap; const Rects: array of TRect);
var
  i: integer;
  SR: array of TRect;
  part, blurred: TBGRACustomBitmap;
  t0, t1: double;
begin
  // 1) downsample every dirty rect first (rects never overlap after merging)
  t0 := NowMs;
  SetLength(SR, Length(Rects));
  for i := 0 to High(Rects) do
  begin
    SR[i] := Rect(Rects[i].Left div GlowScale, Rects[i].Top div GlowScale,
      Min((Rects[i].Right + GlowScale - 1) div GlowScale, FSmall.Width),
      Min((Rects[i].Bottom + GlowScale - 1) div GlowScale, FSmall.Height));
    DownsampleLayer(SR[i]);
  end;
  FSmall.InvalidateBitmap;
  t1 := NowMs; Prof[4] += t1 - t0; t0 := t1;
  // 2) blur each cropped region and compose it
  for i := 0 to High(Rects) do
  begin
    part := FSmall.GetPart(SR[i]);
    try
      blurred := part.FilterBlurRadial(Max(1.5, 4 * K), rbFast);
      try
        t1 := NowMs; Prof[5] += t1 - t0; t0 := t1;
        ComposeRect(Base, Dst, Rects[i], blurred, SR[i].Left, SR[i].Top);
        t1 := NowMs; Prof[6] += t1 - t0; t0 := t1;
      finally
        blurred.Free;
      end;
    finally
      part.Free;
    end;
  end;
  Dst.InvalidateBitmap;
end;

procedure THUDRenderer.Render(W, H: integer; ATime: single);
var
  ix, gw, i: integer;
  fx: single;
  t0: double;
begin
  if (W < 8) or (H < 8) then Exit;
  T := ATime;
  K := Min(W / DesignW, H / DesignH);
  OX := (W - DesignW * K) / 2;
  OY := (H - DesignH * K) / 2;

  if (FBack = nil) or (FBack.Width <> W) or (FBack.Height <> H) then
  begin
    // (re)build everything that only depends on the window size
    BuildBackground(W, H);
    FreeAndNil(FLayer);
    FreeAndNil(FFill);
    FreeAndNil(FOut);
    FreeAndNil(FSmall);
    FreeAndNil(FStaticOut);
    FTextCache.Clear;
    FLayer := TBGRABitmap.Create(W, H);
    FLayer.LineCap := pecFlat;
    FFill := TBGRABitmap.Create(W, H);
    FStaticOut := TBGRABitmap.Create(W, H);
    gw := (W + GlowScale - 1) div GlowScale;
    FSmall := TBGRABitmap.Create(gw, (H + GlowScale - 1) div GlowScale, BGRABlack);
    SetLength(FRowR, gw);
    SetLength(FRowG, gw);
    SetLength(FRowB, gw);
    SetLength(FXI0, W);
    SetLength(FXI1, W);
    SetLength(FWX, W);
    for ix := 0 to W - 1 do
    begin
      fx := (ix + 0.5) / GlowScale - 0.5;
      FXI0[ix] := EnsureRange(Floor(fx), 0, gw - 1);
      FXI1[ix] := Min(FXI0[ix] + 1, gw - 1);
      if fx < 0 then FWX[ix] := 0 else FWX[ix] := Round((fx - Floor(fx)) * 256);
    end;
    BuildDirtyRects(W, H);
    // static pass over the whole window
    FStatic := True;
    FLayer.FillTransparent;
    FFill.FillTransparent;
    DrawWidgets;
    Compose(FBack, FStaticOut, [Rect(0, 0, W, H)]);
    FStatic := False;
    // outside the dirty rects the output never changes
    FOut := FStaticOut.Duplicate as TBGRABitmap;
    FLayer.FillTransparent;
    FFill.FillTransparent;
  end;

  // dynamic pass: only the dirty rects are cleared, drawn and composed
  t0 := NowMs;
  for i := 0 to High(FDirty) do
  begin
    FLayer.FillRect(FDirty[i], BGRAPixelTransparent, dmSet);
    FFill.FillRect(FDirty[i], BGRAPixelTransparent, dmSet);
  end;
  Prof[0] += NowMs - t0;
  DrawWidgets;
  Compose(FStaticOut, FOut, FDirty);
end;

end.
