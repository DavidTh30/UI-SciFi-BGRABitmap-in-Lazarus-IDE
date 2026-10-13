unit HUDCore;

{ HUD rendering engine shared by all Sci-Fi HUD programs.

  A widget (one UI) derives from THUDWidget and implements:
    constructor Create         - SetView(), AddParam(), RegisterRing()
    DrawStatic                 - parts that never move (drawn once per size)
    DrawDynamic                - animated parts (drawn every frame)
    DefineDirty                - AddDirty() rects that contain ALL dynamic parts
    DescribeAnatomy / DescribeLive / UIName / UIDescription - info panel

  Coordinates are design units inside the widget viewport (SetView), scaled
  to fit the window. Angles are degrees, clockwise from 3 o'clock.

  Render pipeline per frame (only inside the dirty rects):
    DrawDynamic -> FLayer (glowing strokes) + FFill (translucent fills)
    -> box-downsample FLayer -> 2x separable box blur
    -> one pass: static cache + fills + bilinear glow (additive) + strokes
       (multithreaded when the dirty area is large; clears the layers too) }

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF} Classes, SysUtils, Math, Graphics, MTProcs, MTPCPU,
  BGRABitmap, BGRABitmapTypes;

const
  // compose runs multithreaded when the dirty area is at least this many
  // pixels; below that, waking the pool costs more than it saves
  MTMinPixels = 600000;
  DirtyMargin = 24;  // design units added around dirty rects for the glow

type
  TPixRows = record
    P0: PByte;       // address of row 0
    Stride: PtrInt;  // bytes between rows (negative for bottom-up DIBs)
  end;

  TRingFrames = record
    Radius, Period: single;      // outer radius, symmetry period in degrees
    OnFill: boolean;             // blit to the fill layer (no glow)
    N: integer;                  // frames per period (0 = not built yet)
    Frames: array of TBGRABitmap;
  end;

  THUDParam = record
    Name, Group, Hint: string;
    Value: PSingle;
    MinV, MaxV, DefV: single;
    Decimals: integer;           // 0 = integer / on-off value
    AffectsStatic: boolean;      // True = static cache is rebuilt on change
  end;

  TPaletteEntry = record
    Name: string;
    Color: TBGRAPixel;
    Usage: string;
  end;

  { THUDWidget }

  THUDWidget = class
  private
    FBack: TBGRABitmap;       // background
    FStaticOut: TBGRABitmap;  // background + static parts + their glow
    FSmall: TBGRABitmap;      // downsampled FLayer (glow source)
    FBlur, FBlurTmp: TBGRABitmap;
    FOut: TBGRABitmap;        // final image
    FTextCache: TStringList;
    FStaticDirty: boolean;
    FStaticBuildMs: double;
    FW, FH: integer;
    FGS: integer;             // glow downsample factor (4, 6 or 8)
    FBoxR: integer;           // box blur radius in glow pixels
    FGainI: integer;          // glow gain, 256 = 1.0
    FUseMT: boolean;
    FDirtyDesign: array of TRectF;
    FDirty: array of TRect;
    FDirtyArea: Int64;
    FParams: array of THUDParam;
    FRings: array of TRingFrames;
    FXI0, FXI1, FWX: array of integer;
    FJobs: array of TRect;
    FJobOwner: array of integer;
    FSmallRects: array of TRect;
    FRBase, FRDst, FRLayer, FRFill, FRSmall, FRBlur, FRTmp, FBlurSrc, FBlurDst: TPixRows;
    FProfiling: boolean;

    procedure Rebuild(W, H: integer);
    procedure BuildDirtyRects;
    procedure FreeRings;
    procedure MakeJobs(const Rects: array of TRect; BandSize: integer; ByColumns: boolean);
    procedure RunJobs(AMethod: TMTMethod; Parallel: boolean);
    procedure JobDownsample(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
    procedure JobBlurH(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
    procedure JobBlurV(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
    procedure JobCompose(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
    procedure Compose(Base, Dst: TBGRABitmap; const Rects: array of TRect);
    function GetParam(i: integer): THUDParam;
    function GetRingFramesCached: integer;
  protected
    FLayer: TBGRABitmap;      // glowing strokes (transparent)
    FFill: TBGRABitmap;       // translucent fills (no glow)
    FDrawingStatic: boolean;  // True during DrawStatic
    K, OX, OY: single;        // design -> pixel transform
    T: single;                // animation time in seconds
    FViewW, FViewH: single;   // design viewport size
    FGlowGain: single;
    FMaxZoom: single;
    FTimeScale: single;

    { transform & geometry }
    function X(v: single): single; inline;
    function Y(v: single): single; inline;
    function Pt(ax, ay: single): TPointF; inline;
    function ArcPts(cx, cy, r, a0, a1: single): ArrayOfTPointF;
    function Pts(const A: array of single): ArrayOfTPointF;
    function Dest(c: TBGRAPixel): TBGRABitmap;

    { drawing primitives (design units) }
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

    { widget definition helpers }
    procedure SetView(AW, AH: single);
    procedure AddParam(const AName, AGroup, AHint: string; var AValue: single;
      AMin, AMax: single; ADecimals: integer; AStatic: boolean);
    procedure AddDirty(x1, y1, x2, y2: single);
    procedure RegisterRing(id: integer; ARadius, APeriod: single; AOnFill: boolean);
    procedure RingFrame(id: integer; cx, cy, angle: single);

    { to implement / override }
    procedure DrawBackground(B: TBGRABitmap); virtual;
    procedure DrawStatic; virtual; abstract;
    procedure DrawDynamic; virtual; abstract;
    procedure DefineDirty; virtual;
    procedure DrawRingShape(id: integer; cx, cy, a: single); virtual;
  public
    Prof: array[0..3] of double;  // ms: draw dynamic, downsample, blur, compose
    ProfFrames: integer;

    constructor Create; virtual;
    destructor Destroy; override;

    class function UIName: string; virtual; abstract;
    class function UIDescription: string; virtual; abstract;
    class function UnitFile: string; virtual; abstract;
    procedure DescribeAnatomy(L: TStrings); virtual; abstract;
    procedure DescribeLive(L: TStrings); virtual;

    procedure Render(W, H: integer; ATime: single);
    procedure InvalidateStatic;
    procedure ResetParams;
    procedure SetParamValue(i: integer; v: single);
    function ParamCount: integer;
    function DirtyCount: integer;
    function DirtyRect(i: integer): TRect;

    property Params[i: integer]: THUDParam read GetParam;
    property Output: TBGRABitmap read FOut;
    property UsesThreads: boolean read FUseMT;
    property StaticBuildMs: double read FStaticBuildMs;
    property GlowScale: integer read FGS;
    property BlurRadius: integer read FBoxR;
    property Scale: single read K;
    property DirtyArea: Int64 read FDirtyArea;
    property RenderWidth: integer read FW;    // size of the last Render
    property RenderHeight: integer read FH;
    property DesignWidth: single read FViewW;    // design viewport (SetView)
    property DesignHeight: single read FViewH;
    property TimeScale: single read FTimeScale;
    property RingFramesCached: integer read GetRingFramesCached;
  end;

  THUDWidgetClass = class of THUDWidget;

{ shared palette }
function White(a: byte = 255): TBGRAPixel;
function Ice(a: byte = 255): TBGRAPixel;
function Steel(a: byte = 255): TBGRAPixel;
function Navy(a: byte = 255): TBGRAPixel;
function PaletteCount: integer;
function PaletteEntry(i: integer): TPaletteEntry;

function NowMs: double;
function NormDeg(a: single): single;  // angle wrapped into 0..360

implementation

function NormDeg(a: single): single;
begin
  Result := a - Floor(a / 360) * 360;
end;

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

function White(a: byte): TBGRAPixel; begin Result := BGRA(236, 247, 255, a); end;
function Ice(a: byte): TBGRAPixel;   begin Result := BGRA(150, 212, 242, a); end;
function Steel(a: byte): TBGRAPixel; begin Result := BGRA(96, 140, 186, a); end;
function Navy(a: byte): TBGRAPixel;  begin Result := BGRA(22, 46, 78, a); end;

function PaletteCount: integer;
begin
  Result := 7;
end;

function PaletteEntry(i: integer): TPaletteEntry;
begin
  case i of
    0: begin Result.Name := 'White'; Result.Color := White;
         Result.Usage := 'Main strokes, labels, lit segments. Alpha >= 200 glows.'; end;
    1: begin Result.Name := 'Ice'; Result.Color := Ice;
         Result.Usage := 'Secondary rings, ticks, progress, sweeps.'; end;
    2: begin Result.Name := 'Steel'; Result.Color := Steel;
         Result.Usage := 'Panel/wing fills, inactive segments (usually alpha 45-170).'; end;
    3: begin Result.Name := 'Navy'; Result.Color := Navy;
         Result.Usage := 'Dark cores behind rings, cut-outs. Never glows.'; end;
    4: begin Result.Name := 'Background top'; Result.Color := BGRA(30, 58, 92);
         Result.Usage := 'Vertical gradient start (DrawBackground).'; end;
    5: begin Result.Name := 'Background bottom'; Result.Color := BGRA(18, 36, 60);
         Result.Usage := 'Vertical gradient end (DrawBackground).'; end;
  else
    begin Result.Name := 'Grid'; Result.Color := BGRA(120, 170, 220, 10);
      Result.Usage := '16-unit grid lines, alpha 10 (DrawBackground).'; end;
  end;
end;

{ ---------- transform & geometry ---------- }

function THUDWidget.X(v: single): single;
begin
  Result := OX + v * K;
end;

function THUDWidget.Y(v: single): single;
begin
  Result := OY + v * K;
end;

function THUDWidget.Pt(ax, ay: single): TPointF;
begin
  Result := PointF(X(ax), Y(ay));
end;

function THUDWidget.ArcPts(cx, cy, r, a0, a1: single): ArrayOfTPointF;
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

function THUDWidget.Pts(const A: array of single): ArrayOfTPointF;
var
  i: integer;
begin
  SetLength(Result, Length(A) div 2);
  for i := 0 to High(Result) do
    Result[i] := Pt(A[2 * i], A[2 * i + 1]);
end;

function THUDWidget.Dest(c: TBGRAPixel): TBGRABitmap;
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

procedure THUDWidget.Arc(cx, cy, r, a0, a1, w: single; c: TBGRAPixel);
begin
  FLayer.DrawPolyLineAntialias(ArcPts(cx, cy, r, a0, a1), c, w * K);
end;

procedure THUDWidget.Band(cx, cy, r1, r2, a0, a1: single; c: TBGRAPixel);
begin
  Dest(c).FillPolyAntialias(JoinPts(ArcPts(cx, cy, r2, a0, a1), ArcPts(cx, cy, r1, a1, a0)), c);
end;

procedure THUDWidget.Pie(cx, cy, r, a0, a1: single; c: TBGRAPixel);
var
  P: ArrayOfTPointF;
begin
  SetLength(P, 1);
  P[0] := Pt(cx, cy);
  Dest(c).FillPolyAntialias(JoinPts(P, ArcPts(cx, cy, r, a0, a1)), c);
end;

procedure THUDWidget.Ring(cx, cy, r, w: single; c: TBGRAPixel);
begin
  FLayer.EllipseAntialias(X(cx), Y(cy), r * K, r * K, c, w * K);
end;

procedure THUDWidget.Disc(cx, cy, r: single; c: TBGRAPixel);
begin
  Dest(c).FillEllipseAntialias(X(cx), Y(cy), r * K, r * K, c);
end;

procedure THUDWidget.SoftDisc(B: TBGRABitmap; cx, cy, r: single; inner: TBGRAPixel);
var
  outer: TBGRAPixel;
begin
  outer := inner;
  outer.alpha := 0;
  B.FillEllipseLinearColorAntialias(X(cx), Y(cy), r * K, r * K, outer, inner);
end;

procedure THUDWidget.Ticks(cx, cy, r1, r2: single; n: integer; a0, a1, w: single; c: TBGRAPixel);
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

procedure THUDWidget.Dots(cx, cy, r: single; n: integer; dotR, a0: single; c: TBGRAPixel);
const
  M = 8; // a dot of 1-3 px needs only an octagon
var
  i, j: integer;
  a, dx, dy: single;
  P: ArrayOfTPointF;
begin
  if n <= 0 then Exit;
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

procedure THUDWidget.Line(x1, y1, x2, y2, w: single; c: TBGRAPixel);
begin
  FLayer.DrawLineAntialias(X(x1), Y(y1), X(x2), Y(y2), c, w * K);
end;

procedure THUDWidget.PolyLine(const A: array of single; w: single; c: TBGRAPixel);
begin
  FLayer.DrawPolyLineAntialias(Pts(A), c, w * K);
end;

procedure THUDWidget.Polygon(const A: array of single; w: single; c: TBGRAPixel);
begin
  FLayer.DrawPolygonAntialias(Pts(A), c, w * K);
end;

procedure THUDWidget.FillPoly(const A: array of single; c: TBGRAPixel);
begin
  Dest(c).FillPolyAntialias(Pts(A), c);
end;

procedure THUDWidget.Txt(ax, ay: single; const S: string; size: single;
  c: TBGRAPixel; align: TAlignment);
begin
  FLayer.FontName := 'Consolas';
  FLayer.FontStyle := [fsBold];
  FLayer.FontQuality := fqFineAntialiasing;
  FLayer.FontHeight := Max(6, Round(size * K));
  FLayer.TextOut(X(ax), Y(ay - size * 0.55), S, c, align);
end;

procedure THUDWidget.TxtCached(ax, ay: single; const S: string; size: single; align: TAlignment);
var
  idx, px: integer;
  B: TBGRABitmap;
  sz: TSize;
  key: string;
begin
  // text rasterization is slow; render each distinct string once per size
  key := S + '|' + FloatToStr(size);
  idx := FTextCache.IndexOf(key);
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
    idx := FTextCache.AddObject(key, B);
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

{ ---------- widget definition helpers ---------- }

procedure THUDWidget.SetView(AW, AH: single);
begin
  FViewW := AW;
  FViewH := AH;
  FStaticDirty := True;
end;

procedure THUDWidget.AddParam(const AName, AGroup, AHint: string; var AValue: single;
  AMin, AMax: single; ADecimals: integer; AStatic: boolean);
var
  n: integer;
begin
  n := Length(FParams);
  SetLength(FParams, n + 1);
  with FParams[n] do
  begin
    Name := AName;
    Group := AGroup;
    Hint := AHint;
    Value := @AValue;
    MinV := AMin;
    MaxV := AMax;
    DefV := AValue;
    Decimals := ADecimals;
    AffectsStatic := AStatic;
  end;
end;

procedure THUDWidget.AddDirty(x1, y1, x2, y2: single);
var
  n: integer;
begin
  n := Length(FDirtyDesign);
  SetLength(FDirtyDesign, n + 1);
  FDirtyDesign[n] := RectF(x1, y1, x2, y2);
end;

procedure THUDWidget.RegisterRing(id: integer; ARadius, APeriod: single; AOnFill: boolean);
begin
  if id >= Length(FRings) then SetLength(FRings, id + 1);
  FRings[id].Radius := ARadius;
  FRings[id].Period := APeriod;
  FRings[id].OnFill := AOnFill;
  FRings[id].N := 0;
end;

procedure THUDWidget.RingFrame(id: integer; cx, cy, angle: single);
var
  P, a: single;
  f, px0, py0, sz: integer;
  B, oldLayer, oldFill: TBGRABitmap;
  oldOX, oldOY: single;
begin
  // A ring of n identical elements looks the same after 360/n degrees, so
  // only one period is pre-rendered (lazily) and then just blitted.
  with FRings[id] do
  begin
    if N = 0 then
    begin
      N := EnsureRange(Ceil(Period * Pi / 180 * Radius * K * 4), 8, 48);
      SetLength(Frames, N);
    end;
    P := Period;
    a := angle - Floor(angle / P) * P;
    f := Round(a / P * N) mod N;
    px0 := Floor(X(cx - Radius));
    py0 := Floor(Y(cy - Radius));
    if Frames[f] = nil then
    begin
      sz := Ceil(2 * Radius * K) + 3;
      B := TBGRABitmap.Create(sz, sz);
      oldLayer := FLayer; oldFill := FFill; oldOX := OX; oldOY := OY;
      FLayer := B; FFill := B;
      OX := OX - px0; OY := OY - py0;  // same sub-pixel position as direct drawing
      try
        DrawRingShape(id, cx, cy, f * P / N);
      finally
        FLayer := oldLayer; FFill := oldFill; OX := oldOX; OY := oldOY;
      end;
      Frames[f] := B;
    end;
    if OnFill then
      FFill.PutImage(px0, py0, Frames[f], dmDrawWithTransparency)
    else
      FLayer.PutImage(px0, py0, Frames[f], dmDrawWithTransparency);
  end;
end;

procedure THUDWidget.DrawRingShape(id: integer; cx, cy, a: single);
begin
  // override when RegisterRing is used
end;

procedure THUDWidget.FreeRings;
var
  i, j: integer;
begin
  for i := 0 to High(FRings) do
  begin
    for j := 0 to High(FRings[i].Frames) do
      FRings[i].Frames[j].Free;
    FRings[i].Frames := nil;
    FRings[i].N := 0;
  end;
end;

function THUDWidget.GetRingFramesCached: integer;
var
  i, j: integer;
begin
  Result := 0;
  for i := 0 to High(FRings) do
    for j := 0 to High(FRings[i].Frames) do
      if FRings[i].Frames[j] <> nil then Inc(Result);
end;

procedure THUDWidget.DrawBackground(B: TBGRABitmap);
var
  i: integer;
begin
  // deep navy vertical gradient over the whole window
  B.GradientFill(0, 0, B.Width, B.Height,
    BGRA(30, 58, 92), BGRA(18, 36, 60), gtLinear,
    PointF(0, 0), PointF(0, B.Height), dmSet);
  // light bloom in the middle
  B.GradientFill(0, 0, B.Width, B.Height, BGRA(70, 110, 160, 70), BGRA(70, 110, 160, 0),
    gtRadial, PointF(X(FViewW / 2), Y(FViewH / 2)),
    PointF(X(FViewW / 2) + Max(FViewW, FViewH) * K * 0.7, Y(FViewH / 2)), dmDrawWithTransparency);
  // faint 16-unit grid over the whole window
  for i := Floor(-OX / (16 * K)) to Ceil((B.Width - OX) / (16 * K)) do
    B.DrawLineAntialias(X(i * 16), 0, X(i * 16), B.Height, BGRA(120, 170, 220, 10), 1);
  for i := Floor(-OY / (16 * K)) to Ceil((B.Height - OY) / (16 * K)) do
    B.DrawLineAntialias(0, Y(i * 16), B.Width, Y(i * 16), BGRA(120, 170, 220, 10), 1);
end;

procedure THUDWidget.DefineDirty;
begin
  // no animated parts by default
end;

procedure THUDWidget.DescribeLive(L: TStrings);
begin
  L.Add(Format('Animation time      %.2f s', [T]));
end;

{ ---------- life cycle & parameters ---------- }

constructor THUDWidget.Create;
begin
  inherited Create;
  FTextCache := TStringList.Create;
  FTextCache.OwnsObjects := True;
  FTextCache.Sorted := True;
  FViewW := 300;
  FViewH := 300;
  FGlowGain := 1.3;
  FMaxZoom := 3;
  FTimeScale := 1;
  FStaticDirty := True;
  AddParam('Glow intensity', 'Engine', 'Strength of the neon bloom added around bright strokes (0 = off).',
    FGlowGain, 0, 3, 2, True);
  AddParam('Animation speed', 'Engine', 'Multiplier applied to the animation clock (0 = frozen).',
    FTimeScale, 0, 5, 2, False);
  AddParam('Max zoom', 'Engine', 'Upper limit of the design-unit -> pixel scale. Lower = faster on big windows.',
    FMaxZoom, 0.5, 8, 1, True);
end;

destructor THUDWidget.Destroy;
begin
  FreeRings;
  FTextCache.Free;
  FBack.Free;
  FStaticOut.Free;
  FLayer.Free;
  FFill.Free;
  FSmall.Free;
  FBlur.Free;
  FBlurTmp.Free;
  FOut.Free;
  inherited Destroy;
end;

procedure THUDWidget.InvalidateStatic;
begin
  FStaticDirty := True;
end;

procedure THUDWidget.ResetParams;
var
  i: integer;
begin
  for i := 0 to High(FParams) do
    FParams[i].Value^ := FParams[i].DefV;
  FStaticDirty := True;
end;

procedure THUDWidget.SetParamValue(i: integer; v: single);
begin
  with FParams[i] do
  begin
    v := EnsureRange(v, MinV, MaxV);
    if Decimals = 0 then v := Round(v);
    if Value^ = v then Exit;
    Value^ := v;
    if AffectsStatic then FStaticDirty := True;
  end;
end;

function THUDWidget.ParamCount: integer;
begin
  Result := Length(FParams);
end;

function THUDWidget.GetParam(i: integer): THUDParam;
begin
  Result := FParams[i];
end;

function THUDWidget.DirtyCount: integer;
begin
  Result := Length(FDirty);
end;

function THUDWidget.DirtyRect(i: integer): TRect;
begin
  Result := FDirty[i];
end;

{ ---------- dirty rects ---------- }

procedure THUDWidget.BuildDirtyRects;
var
  i, j, n: integer;
  R: TRect;
  merged: boolean;
begin
  FDirtyDesign := nil;
  DefineDirty;
  SetLength(FDirty, Length(FDirtyDesign));
  for i := 0 to High(FDirtyDesign) do
  begin
    R.Left := Max(0, Floor(X(FDirtyDesign[i].Left - DirtyMargin)) div FGS * FGS);
    R.Top := Max(0, Floor(Y(FDirtyDesign[i].Top - DirtyMargin)) div FGS * FGS);
    R.Right := Min(FW, (Ceil(X(FDirtyDesign[i].Right + DirtyMargin)) + FGS - 1) div FGS * FGS);
    R.Bottom := Min(FH, (Ceil(Y(FDirtyDesign[i].Bottom + DirtyMargin)) + FGS - 1) div FGS * FGS);
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
  FDirtyArea := 0;
  for i := 0 to n - 1 do
    FDirtyArea += Int64(FDirty[i].Right - FDirty[i].Left) * (FDirty[i].Bottom - FDirty[i].Top);
end;

{ ---------- multithreaded glow pipeline ---------- }

function PixRows(B: TBGRABitmap): TPixRows;
begin
  Result.P0 := PByte(B.ScanLine[0]);
  if B.Height > 1 then
    Result.Stride := PByte(B.ScanLine[1]) - Result.P0
  else
    Result.Stride := 0;
end;

function RowAt(const R: TPixRows; y: integer): PBGRAPixel; inline;
begin
  Result := PBGRAPixel(R.P0 + PtrInt(y) * R.Stride);
end;

procedure THUDWidget.MakeJobs(const Rects: array of TRect; BandSize: integer; ByColumns: boolean);
var
  i, p, n: integer;
  R: TRect;
begin
  n := 0;
  SetLength(FJobs, 0);
  SetLength(FJobOwner, 0);
  for i := 0 to High(Rects) do
  begin
    if ByColumns then p := Rects[i].Left else p := Rects[i].Top;
    while (ByColumns and (p < Rects[i].Right)) or (not ByColumns and (p < Rects[i].Bottom)) do
    begin
      R := Rects[i];
      if ByColumns then
      begin
        R.Left := p; R.Right := Min(p + BandSize, Rects[i].Right);
      end
      else
      begin
        R.Top := p; R.Bottom := Min(p + BandSize, Rects[i].Bottom);
      end;
      SetLength(FJobs, n + 1);
      SetLength(FJobOwner, n + 1);
      FJobs[n] := R;
      FJobOwner[n] := i;
      Inc(n);
      Inc(p, BandSize);
    end;
  end;
end;

procedure THUDWidget.RunJobs(AMethod: TMTMethod; Parallel: boolean);
var
  i: integer;
begin
  if Length(FJobs) = 0 then Exit;
  if Parallel and (Length(FJobs) > 1) then
    ProcThreadPool.DoParallel(AMethod, 0, High(FJobs))
  else
    for i := 0 to High(FJobs) do
      AMethod(i, nil, nil);
end;

procedure THUDWidget.JobDownsample(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
var
  SR: TRect;
  sx, sy, ix, iy, xs, ys, a, area, nx: integer;
  r, g, b: cardinal;
  p, d: PBGRAPixel;
begin
  // FGS x FGS box average of premultiplied colors into the opaque small bitmap
  SR := FJobs[Index];
  area := 255 * FGS * FGS;
  for sy := SR.Top to SR.Bottom - 1 do
  begin
    d := RowAt(FRSmall, sy) + SR.Left;
    for sx := SR.Left to SR.Right - 1 do
    begin
      r := 0; g := 0; b := 0;
      xs := sx * FGS;
      nx := Min(FGS, FW - xs);
      for iy := 0 to FGS - 1 do
      begin
        ys := Min(sy * FGS + iy, FH - 1);
        p := RowAt(FRLayer, ys) + xs;
        for ix := 0 to nx - 1 do
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
      d^.red := r div area;
      d^.green := g div area;
      d^.blue := b div area;
      d^.alpha := 255;
      Inc(d);
    end;
  end;
end;

procedure THUDWidget.JobBlurH(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
var
  R: TRect;
  bx, by, rb, inv: integer;
  sr, sg, sb: integer;
  s, d: PBGRAPixel;
begin
  // running-sum box blur along rows, zero outside the rect
  R := FJobs[Index];
  rb := FBoxR;
  inv := 65536 div (2 * rb + 1);
  for by := R.Top to R.Bottom - 1 do
  begin
    s := RowAt(FBlurSrc, by);
    d := RowAt(FBlurDst, by);
    sr := 0; sg := 0; sb := 0;
    for bx := R.Left to Min(R.Left + rb, R.Right - 1) do
    begin
      sr += s[bx].red; sg += s[bx].green; sb += s[bx].blue;
    end;
    for bx := R.Left to R.Right - 1 do
    begin
      d[bx].red := (sr * inv) shr 16;
      d[bx].green := (sg * inv) shr 16;
      d[bx].blue := (sb * inv) shr 16;
      d[bx].alpha := 255;
      if bx - rb >= R.Left then
      begin
        sr -= s[bx - rb].red; sg -= s[bx - rb].green; sb -= s[bx - rb].blue;
      end;
      if bx + rb + 1 < R.Right then
      begin
        sr += s[bx + rb + 1].red; sg += s[bx + rb + 1].green; sb += s[bx + rb + 1].blue;
      end;
    end;
  end;
end;

procedure THUDWidget.JobBlurV(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
var
  R: TRect;
  bx, by, rb, inv: integer;
  sr, sg, sb: integer;
  p: PBGRAPixel;
begin
  // running-sum box blur along columns, zero outside the rect
  R := FJobs[Index];
  rb := FBoxR;
  inv := 65536 div (2 * rb + 1);
  for bx := R.Left to R.Right - 1 do
  begin
    sr := 0; sg := 0; sb := 0;
    for by := R.Top to Min(R.Top + rb, R.Bottom - 1) do
    begin
      p := RowAt(FBlurSrc, by) + bx;
      sr += p^.red; sg += p^.green; sb += p^.blue;
    end;
    for by := R.Top to R.Bottom - 1 do
    begin
      p := RowAt(FBlurDst, by) + bx;
      p^.red := (sr * inv) shr 16;
      p^.green := (sg * inv) shr 16;
      p^.blue := (sb * inv) shr 16;
      p^.alpha := 255;
      if by - rb >= R.Top then
      begin
        p := RowAt(FBlurSrc, by - rb) + bx;
        sr -= p^.red; sg -= p^.green; sb -= p^.blue;
      end;
      if by + rb + 1 < R.Bottom then
      begin
        p := RowAt(FBlurSrc, by + rb + 1) + bx;
        sr += p^.red; sg += p^.green; sb += p^.blue;
      end;
    end;
  end;
end;

procedure THUDWidget.JobCompose(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
var
  DR, SR: TRect;
  ix, iy, sw, y0, y1, wy, i0, i1, wx, n, gain: integer;
  r, g, b, a, gr, gg, gb: integer;
  fy: single;
  pb, pf, pl, pd, s0, s1: PBGRAPixel;
  LXI0, LXI1, LWX, RowR, RowG, RowB: array of integer;
begin
  DR := FJobs[Index];
  SR := FSmallRects[FJobOwner[Index]];
  gain := FGainI;
  sw := SR.Right - SR.Left;
  n := DR.Right - DR.Left;
  SetLength(RowR, sw); SetLength(RowG, sw); SetLength(RowB, sw);
  SetLength(LXI0, n); SetLength(LXI1, n); SetLength(LWX, n);
  for ix := 0 to n - 1 do
  begin
    LXI0[ix] := EnsureRange(FXI0[DR.Left + ix] - SR.Left, 0, sw - 1);
    LXI1[ix] := EnsureRange(FXI1[DR.Left + ix] - SR.Left, 0, sw - 1);
    LWX[ix] := FWX[DR.Left + ix];
  end;
  for iy := DR.Top to DR.Bottom - 1 do
  begin
    // vertical bilinear interpolation of the glow into a row buffer
    fy := (iy + 0.5) / FGS - 0.5;
    y0 := Floor(fy);
    wy := Round((fy - y0) * 256);
    if y0 < SR.Top then begin y0 := SR.Top; wy := 0; end;
    y1 := Min(y0 + 1, SR.Bottom - 1);
    y0 := Min(y0, SR.Bottom - 1);
    s0 := RowAt(FRBlur, y0) + SR.Left;
    s1 := RowAt(FRBlur, y1) + SR.Left;
    for ix := 0 to sw - 1 do
    begin
      RowR[ix] := s0[ix].red * (256 - wy) + s1[ix].red * wy;
      RowG[ix] := s0[ix].green * (256 - wy) + s1[ix].green * wy;
      RowB[ix] := s0[ix].blue * (256 - wy) + s1[ix].blue * wy;
    end;

    pb := RowAt(FRBase, iy) + DR.Left;
    pf := RowAt(FRFill, iy) + DR.Left;
    pl := RowAt(FRLayer, iy) + DR.Left;
    pd := RowAt(FRDst, iy) + DR.Left;
    for ix := 0 to n - 1 do
    begin
      r := pb^.red; g := pb^.green; b := pb^.blue;
      // 1) translucent fills (alpha blend), then clear for the next frame
      a := pf^.alpha;
      if a <> 0 then
      begin
        a := a + a shr 7;
        r += SarLongint((pf^.red - r) * a, 8);
        g += SarLongint((pf^.green - g) * a, 8);
        b += SarLongint((pf^.blue - b) * a, 8);
        PDWord(pf)^ := 0;
      end;
      // 2) glow (horizontal bilinear + additive)
      i0 := LXI0[ix]; i1 := LXI1[ix]; wx := LWX[ix];
      gr := (RowR[i0] * (256 - wx) + RowR[i1] * wx) shr 8;
      gg := (RowG[i0] * (256 - wx) + RowG[i1] * wx) shr 8;
      gb := (RowB[i0] * (256 - wx) + RowB[i1] * wx) shr 8;
      r += (gr * gain) shr 16;
      g += (gg * gain) shr 16;
      b += (gb * gain) shr 16;
      if r > 255 then r := 255;
      if g > 255 then g := 255;
      if b > 255 then b := 255;
      // 3) crisp strokes on top (alpha blend), then clear
      a := pl^.alpha;
      if a <> 0 then
      begin
        a := a + a shr 7;
        r += SarLongint((pl^.red - r) * a, 8);
        g += SarLongint((pl^.green - g) * a, 8);
        b += SarLongint((pl^.blue - b) * a, 8);
        PDWord(pl)^ := 0;
      end;
      pd^.red := r; pd^.green := g; pd^.blue := b; pd^.alpha := 255;
      Inc(pb); Inc(pf); Inc(pl); Inc(pd);
    end;
  end;
end;

procedure THUDWidget.Compose(Base, Dst: TBGRABitmap; const Rects: array of TRect);
var
  i, pass: integer;
  t0, t1: double;
begin
  t0 := NowMs;
  FRBase := PixRows(Base);
  FRDst := PixRows(Dst);
  FRLayer := PixRows(FLayer);
  FRFill := PixRows(FFill);
  FRSmall := PixRows(FSmall);
  FRBlur := PixRows(FBlur);
  FRTmp := PixRows(FBlurTmp);
  FGainI := Round(FGlowGain * 256);

  SetLength(FSmallRects, Length(Rects));
  for i := 0 to High(Rects) do
    FSmallRects[i] := Rect(Rects[i].Left div FGS, Rects[i].Top div FGS,
      Min((Rects[i].Right + FGS - 1) div FGS, FSmall.Width),
      Min((Rects[i].Bottom + FGS - 1) div FGS, FSmall.Height));

  // 1) downsample (single thread: too little work to pay for the pool)
  MakeJobs(FSmallRects, 8, False);
  RunJobs(@JobDownsample, False);
  t1 := NowMs; if FProfiling then Prof[1] += t1 - t0; t0 := t1;

  // 2) blur: two separable box passes (H then V) ~ gaussian
  for pass := 0 to 1 do
  begin
    if pass = 0 then FBlurSrc := FRSmall else FBlurSrc := FRBlur;
    FBlurDst := FRTmp;
    MakeJobs(FSmallRects, 16, False);
    RunJobs(@JobBlurH, False);
    FBlurSrc := FRTmp;
    FBlurDst := FRBlur;
    MakeJobs(FSmallRects, 16, True);
    RunJobs(@JobBlurV, False);
  end;
  t1 := NowMs; if FProfiling then Prof[2] += t1 - t0; t0 := t1;

  // 3) upsample + blend into the destination (+ clears the layers)
  MakeJobs(Rects, 32, False);
  RunJobs(@JobCompose, FUseMT);
  Dst.InvalidateBitmap;
  t1 := NowMs; if FProfiling then Prof[3] += t1 - t0;
end;

{ ---------- frame ---------- }

procedure THUDWidget.Rebuild(W, H: integer);
var
  ix, gw: integer;
  fx: single;
  t0: double;
begin
  t0 := NowMs;
  FW := W;
  FH := H;
  // coarser glow grid on big scales: the blur hides it, the cost drops by GS^2
  if K < 1.3 then FGS := 4 else if K < 2.2 then FGS := 6 else FGS := 8;
  FBoxR := Max(1, Round(8 * K / FGS));
  FreeAndNil(FBack);
  FreeAndNil(FLayer);
  FreeAndNil(FFill);
  FreeAndNil(FOut);
  FreeAndNil(FSmall);
  FreeAndNil(FBlur);
  FreeAndNil(FBlurTmp);
  FreeAndNil(FStaticOut);
  FTextCache.Clear;
  FreeRings;
  FBack := TBGRABitmap.Create(W, H);
  DrawBackground(FBack);
  FLayer := TBGRABitmap.Create(W, H);
  FLayer.LineCap := pecFlat;
  FFill := TBGRABitmap.Create(W, H);
  FStaticOut := TBGRABitmap.Create(W, H);
  gw := (W + FGS - 1) div FGS;
  FSmall := TBGRABitmap.Create(gw, (H + FGS - 1) div FGS, BGRABlack);
  FBlur := TBGRABitmap.Create(FSmall.Width, FSmall.Height, BGRABlack);
  FBlurTmp := TBGRABitmap.Create(FSmall.Width, FSmall.Height, BGRABlack);
  SetLength(FXI0, W);
  SetLength(FXI1, W);
  SetLength(FWX, W);
  for ix := 0 to W - 1 do
  begin
    fx := (ix + 0.5) / FGS - 0.5;
    FXI0[ix] := EnsureRange(Floor(fx), 0, gw - 1);
    FXI1[ix] := Min(FXI0[ix] + 1, gw - 1);
    if fx < 0 then FWX[ix] := 0 else FWX[ix] := Round((fx - Floor(fx)) * 256);
  end;
  BuildDirtyRects;
  FUseMT := (FDirtyArea >= MTMinPixels) and (GetSystemThreadCount > 1);
  // static pass over the whole window
  FDrawingStatic := True;
  FProfiling := False;
  DrawStatic;
  FUseMT := (W * H >= MTMinPixels) and (GetSystemThreadCount > 1);
  Compose(FBack, FStaticOut, [Rect(0, 0, W, H)]);
  FUseMT := (FDirtyArea >= MTMinPixels) and (GetSystemThreadCount > 1);
  FDrawingStatic := False;
  FProfiling := True;
  // outside the dirty rects the output never changes
  FOut := FStaticOut.Duplicate as TBGRABitmap;
  FStaticDirty := False;
  FStaticBuildMs := NowMs - t0;
end;

procedure THUDWidget.Render(W, H: integer; ATime: single);
var
  t0: double;
begin
  if (W < 8) or (H < 8) then Exit;
  T := ATime;
  K := Min(Min(W / FViewW, H / FViewH), FMaxZoom);
  OX := (W - FViewW * K) / 2;
  OY := (H - FViewH * K) / 2;
  if FStaticDirty or (FOut = nil) or (FW <> W) or (FH <> H) then
    Rebuild(W, H);
  if Length(FDirty) = 0 then Exit;  // fully static widget
  // compose of the previous frame left the dirty rects of FLayer / FFill
  // transparent, so we can draw straight away
  t0 := NowMs;
  DrawDynamic;
  Prof[0] += NowMs - t0;
  Compose(FStaticOut, FOut, FDirty);
  Inc(ProfFrames);
end;

end.
