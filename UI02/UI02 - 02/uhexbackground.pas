unit UHexBackground;

{ Hex Background - dark navy sci-fi background with floating hexagons.

  The picture is built from 12 stages. Every stage is rendered into its own
  full-size bitmap and kept, so it can be inspected, switched off or
  re-rendered alone; Compose stacks the enabled stages into Background.

    #  stage         blend                       content
    0  Base          copy (opaque)               navy fill + 3 radial hazes
    1  Bokeh         alpha                       blurred light blobs
    2  Far glow      additive (on black)         blurred rims of layer Far
    3  Far           alpha                       hex prisms, blurred (depth of field)
    4..9             same pairs for Mid, Focus, Near
    10 Vignette      alpha                       dark corners + top-left shadow
    11 Sparks        alpha, drawn every frame    rising, twinkling orange sparks

  All numbers live in Settings (THexSettings). Params lists every one of them
  with group, range, hint and the stages it affects, so a UI can be generated
  from it (see umain.pas). Each stage has its own random seed (Seed + stage),
  so re-rendering one stage never changes the others.

  Usage:
    Hex := THexBackground.Create;
    Hex.SetSize(W, H);  Hex.Update;      // renders dirty stages + composes
    Hex.Animate(dt);    Hex.DrawFrame(FrameBmp);  // per frame }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, IniFiles, BGRABitmap, BGRABitmapTypes;

const
  LayerCount = 4;
  StageCount = 12;
  stBase = 0;
  stBokeh = 1;
  stFarGlow = 2;     // glow stage of hex layer L = stFarGlow + 2 * L
  stFar = 3;         // hex stage of hex layer L   = stFar + 2 * L
  stMidGlow = 4;
  stMid = 5;
  stFocusGlow = 6;
  stFocus = 7;
  stNearGlow = 8;
  stNear = 9;
  stVignette = 10;
  stSparks = 11;

  LayerNames: array[0..LayerCount - 1] of string = ('Far', 'Mid', 'Focus', 'Near');

type
  TStageSet = set of 0..StageCount - 1;

  THexLayer = record
    Scale: single;    // hex size relative to the base hex size
    Blur: single;     // depth-of-field blur radius, relative to the base hex size
    EdgeA: single;    // rim alpha 0..255
    FillA: single;    // face fill alpha 0..255
    Density: single;  // 0..1 chance a covered cell holds a hexagon
    Reach: single;    // shifts the cluster edge (+ = reaches further up-left)
    Glow: single;     // 0 = no glow, 1 = full glow
  end;

  THexSettings = record
    // geometry (shared by all hex layers)
    HexSize, Gap, EdgeTop, EdgeSlope, FadeStart, FadeEnd: single;
    NoiseFreqMin, NoiseFreqRange, ClusterLo, ClusterHi, ClusterMin: single;
    RotJitter, EdgeWobble, SizeJitter: single;
    LooseChance, LooseZoneTop, LooseZoneBottom, LooseDrift, LooseRot, LooseShrink: single;
    VanishX, VanishY, Extrude, ExtrudeMax: single;
    // base
    BaseColor: TBGRAPixel;
    HazeColor: array[0..2] of TBGRAPixel;
    HazeX, HazeY, HazeR: array[0..2] of single;
    // bokeh
    BokehPerMP, BokehMax, BokehBand, BokehBaseChance, BokehBigChance: single;
    BokehBigMin, BokehBigMax, BokehBigAlphaMin, BokehBigAlphaMax: single;
    BokehDotMin, BokehDotMax, BokehDotAlphaMin, BokehDotAlphaMax, BokehBlur: single;
    BokehBigColor, BokehDotColor: TBGRAPixel;
    // hexagon style
    EdgeColor, FillColor, BackColor, InnerColor, SpecColor, GlowColor: TBGRAPixel;
    LineWidth, BackSize, BackAlpha, SideAlpha, InnerSize, InnerAlpha, SpecAlpha: single;
    GlowWidth, GlowStrength, GlowBlur: single;
    Layers: array[0..LayerCount - 1] of THexLayer;
    // vignette
    VigAlpha, VigX, VigY, VigRadius, ShadowAlpha, ShadowX, ShadowY: single;
    // sparks
    SparkPerMP, SparkMin, SparkMax, SparkFieldBias: single;
    SparkSizeMin, SparkSizeMax, SparkSoftChance, SparkSoftSize: single;
    SparkAlphaMin, SparkAlphaMax, SparkRiseMin, SparkRiseMax, SparkSwayMin, SparkSwayMax: single;
    SparkLifeMin, SparkLifeMax, SparkTwinkleMin, SparkTwinkleMax, SparkTwinkleDepth: single;
    SparkHaloSize, SparkHaloAlpha, SparkSoftAlpha: single;
    SparkCoreColor, SparkHaloColor, SparkSoftColor: TBGRAPixel;
  end;
  PHexSettings = ^THexSettings;

  TParamKind = (pkFloat, pkColor);

  TParamInfo = record
    Group, Name, Hint: string;
    Kind: TParamKind;
    PValue: PSingle;
    PColor: PBGRAPixel;
    Min, Max: single;
    Decimals: integer;
    Stages: TStageSet;    // stages to re-render when the value changes
  end;
  TParamList = array of TParamInfo;

  TStage = record
    Name, Technique, Blend: string;
    Enabled, Dirty, Additive: boolean;
    Bitmap: TBGRABitmap;
    Items, Extra: integer;
    TimeMs: QWord;
  end;
  PStage = ^TStage;

  TSpark = record
    X, Y, Size, Alpha: single;
    Life, LifeSpeed: single;
    Phase, Twinkle, VY, Sway: single;
    Soft: boolean;
  end;

  { THexBackground }

  THexBackground = class
  private
    FSettings: THexSettings;
    FParams: TParamList;
    FStages: array[0..StageCount - 1] of TStage;
    FWidth, FHeight, FSeed: integer;
    FScale: single;                     // base hex circumradius in pixels
    FBackground: TBGRABitmap;
    FSparks: array of TSpark;
    FTime: single;
    FNoiseF, FNoiseP: array[0..2] of single;
    FComposeMs: QWord;
    function Coverage(x, y: single): single;
    function Noise(x, y: single): single;
    procedure RenderBase;
    procedure RenderBokeh;
    procedure RenderHexLayer(L: integer);
    procedure RenderVignette;
    procedure RenderSparksSnapshot;
    procedure InitSparks;
    procedure NewSpark(var S: TSpark; RandomLife: boolean);
    procedure DrawHexPrism(Bmp: TBGRABitmap; cx, cy, r, rot: single; Ext: TPointF;
      EdgeA, FillA, LineW: single);
    procedure BuildParams;
    function GetStage(Index: integer): PStage;
    function GetSettings: PHexSettings;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ResetDefaults;
    procedure SetSize(AWidth, AHeight: integer);
    procedure SetSeed(ASeed: integer);
    procedure MarkDirty(const AStages: TStageSet);
    procedure Update;
    procedure Compose;
    procedure Animate(dt: single);
    procedure DrawSparks(Dest: TBGRABitmap);
    procedure DrawFrame(Dest: TBGRABitmap);
    procedure DrawStageView(Dest: TBGRABitmap; Index: integer);
    procedure DrawThumbnail(Dest: TBGRABitmap; Index: integer);
    function StageSummary(Index: integer): string;
    function Report: string;
    procedure SaveToIni(const FileName: string);
    procedure LoadFromIni(const FileName: string);
    property Settings: PHexSettings read GetSettings;
    property Params: TParamList read FParams;
    property Stages[Index: integer]: PStage read GetStage;
    property Background: TBGRABitmap read FBackground;
    property Width: integer read FWidth;
    property Height: integer read FHeight;
    property Seed: integer read FSeed;
    property Scale: single read FScale;
    property ComposeMs: QWord read FComposeMs;
  end;

function DefaultHexSettings: THexSettings;
procedure DrawCheckers(Dest: TBGRABitmap; Cell: integer);

implementation

const
  AllStages: TStageSet = [0..StageCount - 1];
  HexStages: TStageSet = [stFarGlow..stNear];

function DefaultHexSettings: THexSettings;
begin
  FillChar(Result, SizeOf(Result), 0);
  with Result do
  begin
    HexSize := 0.04;  Gap := 1.10;
    EdgeTop := 0.80;  EdgeSlope := 0.62;  FadeStart := -0.05;  FadeEnd := 0.30;
    NoiseFreqMin := 0.12;  NoiseFreqRange := 0.25;
    ClusterLo := 0.30;  ClusterHi := 0.70;  ClusterMin := 0.25;
    RotJitter := 6;  EdgeWobble := 0.30;  SizeJitter := 0.10;
    LooseChance := 0.05;  LooseZoneTop := -0.32;  LooseZoneBottom := 0.10;
    LooseDrift := 1.5;  LooseRot := 30;  LooseShrink := 0.40;
    VanishX := 0.30;  VanishY := 0.30;  Extrude := 0.05;  ExtrudeMax := 0.35;

    BaseColor := BGRA(5, 8, 18);
    HazeColor[0] := BGRA(36, 54, 90, 255);  HazeX[0] := 0.28;  HazeY[0] := 0.70;  HazeR[0] := 0.70;
    HazeColor[1] := BGRA(45, 66, 110, 210); HazeX[1] := 0.65;  HazeY[1] := 0.95;  HazeR[1] := 0.55;
    HazeColor[2] := BGRA(32, 48, 82, 200);  HazeX[2] := 0.95;  HazeY[2] := 0.10;  HazeR[2] := 0.40;

    BokehPerMP := 143;  BokehMax := 260;  BokehBand := 0.22;  BokehBaseChance := 0.15;
    BokehBigChance := 0.70;  BokehBigMin := 0.25;  BokehBigMax := 1.0;
    BokehBigAlphaMin := 12;  BokehBigAlphaMax := 50;
    BokehDotMin := 0.06;  BokehDotMax := 0.18;  BokehDotAlphaMin := 60;  BokehDotAlphaMax := 150;
    BokehBlur := 0.14;
    BokehBigColor := BGRA(100, 130, 180);  BokehDotColor := BGRA(170, 200, 240);

    EdgeColor := BGRA(195, 215, 250);  FillColor := BGRA(8, 14, 30);
    BackColor := BGRA(110, 140, 195);  InnerColor := BGRA(140, 170, 225);
    SpecColor := BGRA(235, 245, 255);  GlowColor := BGRA(70, 110, 190);
    LineWidth := 0.055;  BackSize := 0.95;  BackAlpha := 0.35;  SideAlpha := 0.25;
    InnerSize := 0.86;  InnerAlpha := 0.22;  SpecAlpha := 0.60;
    GlowWidth := 2.5;  GlowStrength := 0.55;  GlowBlur := 0.30;

    with Layers[0] do begin Scale := 0.55; Blur := 0.16; EdgeA := 105; FillA := 90;  Density := 0.95; Reach := 0.06;  Glow := 0;   end;
    with Layers[1] do begin Scale := 0.78; Blur := 0.06; EdgeA := 160; FillA := 140; Density := 0.80; Reach := 0.02;  Glow := 0.4; end;
    with Layers[2] do begin Scale := 1.00; Blur := 0;    EdgeA := 235; FillA := 185; Density := 0.72; Reach := -0.02; Glow := 1;   end;
    with Layers[3] do begin Scale := 1.75; Blur := 0.22; EdgeA := 150; FillA := 165; Density := 0.40; Reach := -0.28; Glow := 0.5; end;

    VigAlpha := 160;  VigX := 0.50;  VigY := 0.55;  VigRadius := 0.62;
    ShadowAlpha := 130;  ShadowX := 0.45;  ShadowY := 0.40;

    SparkPerMP := 333;  SparkMin := 60;  SparkMax := 700;  SparkFieldBias := 0.94;
    SparkSizeMin := 0.02;  SparkSizeMax := 0.065;  SparkSoftChance := 0.30;  SparkSoftSize := 2.1;
    SparkAlphaMin := 120;  SparkAlphaMax := 255;
    SparkRiseMin := 3;  SparkRiseMax := 17;  SparkSwayMin := 2;  SparkSwayMax := 10;
    SparkLifeMin := 3;  SparkLifeMax := 9;
    SparkTwinkleMin := 2;  SparkTwinkleMax := 8;  SparkTwinkleDepth := 0.40;
    SparkHaloSize := 3;  SparkHaloAlpha := 0.18;  SparkSoftAlpha := 0.22;
    SparkCoreColor := BGRA(255, 196, 110);  SparkHaloColor := BGRA(255, 130, 30);
    SparkSoftColor := BGRA(255, 150, 50);
  end;
end;

function SmoothStep(e0, e1, x: single): single;
begin
  if e1 = e0 then
    Exit(Ord(x >= e0));
  Result := EnsureRange((x - e0) / (e1 - e0), 0, 1);
  Result := Result * Result * (3 - 2 * Result);
end;

function RandRange(AMin, AMax: single): single;
begin
  Result := AMin + Random * (AMax - AMin);
end;

function WithAlpha(c: TBGRAPixel; a: single): TBGRAPixel;
begin
  Result := c;
  Result.alpha := EnsureRange(Round(a), 0, 255);
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

procedure DrawCheckers(Dest: TBGRABitmap; Cell: integer);
var
  x, y: integer;
begin
  Dest.Fill(BGRA(34, 34, 40));
  for y := 0 to Dest.Height div Cell do
    for x := 0 to Dest.Width div Cell do
      if Odd(x + y) then
        Dest.FillRect(x * Cell, y * Cell, (x + 1) * Cell, (y + 1) * Cell, BGRA(24, 24, 29), dmSet);
end;

{ THexBackground }

constructor THexBackground.Create;
const
  BlendAlpha = 'PutImage (dmDrawWithTransparency)';
  BlendAdd = 'BlendImage (boAdditive)';
var
  i, L: integer;
begin
  FBackground := TBGRABitmap.Create(16, 16, BGRABlack);
  FWidth := 16;
  FHeight := 16;
  FSeed := 2026;
  for i := 0 to StageCount - 1 do
  begin
    FStages[i].Bitmap := TBGRABitmap.Create(16, 16, BGRAPixelTransparent);
    FStages[i].Enabled := True;
    FStages[i].Dirty := True;
    FStages[i].Blend := BlendAlpha;
  end;

  with FStages[stBase] do
  begin
    Name := 'Base';
    Blend := 'PutImage (dmSet) - opaque';
    Technique := 'Fill(BaseColor), then 3 x GradientFill(gtRadial, dmDrawWithTransparency) ' +
      'from HazeColor to the same colour with alpha 0.';
  end;
  with FStages[stBokeh] do
  begin
    Name := 'Bokeh';
    Technique := 'FillEllipseAntialias: big soft blobs and small bright dots, placed mostly ' +
      'along the cluster edge, then FilterBlurRadial(rbFast).';
  end;
  for L := 0 to LayerCount - 1 do
  begin
    with FStages[stFarGlow + 2 * L] do
    begin
      Name := LayerNames[L] + ' glow';
      Blend := BlendAdd;
      Additive := True;
      Technique := 'Opaque black bitmap; DrawPolygonAntialias of every rim with GlowColor, ' +
        'width LineWidth x GlowWidth, then FilterBlurRadial. Added on top: black adds nothing.';
    end;
    with FStages[stFar + 2 * L] do
    begin
      Name := LayerNames[L] + ' hexagons';
      Technique := 'Flat-top honeycomb lattice. Per cell: back face + 6 side lines ' +
        '(DrawPolygonAntialias / DrawLineAntialias, extruded toward the vanishing point), ' +
        'front face with dark fill and bright rim, inner rim, specular edge. ' +
        'Then FilterBlurRadial = depth of field.';
    end;
  end;
  with FStages[stVignette] do
  begin
    Name := 'Vignette';
    Technique := 'GradientFill(gtRadial) transparent -> black, plus a GradientFill(gtLinear) ' +
      'shadow from the top-left corner.';
  end;
  with FStages[stSparks] do
  begin
    Name := 'Sparks';
    Blend := 'Drawn every frame';
    Technique := 'Per frame: FillEllipseAntialias halo + core (or one soft blob). ' +
      'Alpha = sin(pi*life) x twinkle; sparks rise and sway, respawn when life ends.';
  end;

  ResetDefaults;
end;

destructor THexBackground.Destroy;
var
  i: integer;
begin
  for i := 0 to StageCount - 1 do
    FStages[i].Bitmap.Free;
  FBackground.Free;
  inherited Destroy;
end;

function THexBackground.GetStage(Index: integer): PStage;
begin
  Result := @FStages[Index];
end;

function THexBackground.GetSettings: PHexSettings;
begin
  Result := @FSettings;
end;

procedure THexBackground.ResetDefaults;
begin
  FSettings := DefaultHexSettings;
  BuildParams;
  MarkDirty(AllStages);
end;

procedure THexBackground.SetSize(AWidth, AHeight: integer);
begin
  AWidth := Max(AWidth, 16);
  AHeight := Max(AHeight, 16);
  if (AWidth = FWidth) and (AHeight = FHeight) then Exit;
  FWidth := AWidth;
  FHeight := AHeight;
  MarkDirty(AllStages);
end;

procedure THexBackground.SetSeed(ASeed: integer);
begin
  if ASeed = FSeed then Exit;
  FSeed := ASeed;
  MarkDirty(AllStages);
end;

procedure THexBackground.MarkDirty(const AStages: TStageSet);
var
  i: integer;
begin
  for i := 0 to StageCount - 1 do
    if i in AStages then FStages[i].Dirty := True;
end;

{ ---------------------------------------------------------------- params }

procedure THexBackground.BuildParams;
var
  CurGroup: string;
  CurStages: TStageSet;

  procedure F(const AName, AHint: string; var V: single; AMin, AMax: single; ADec: integer);
  var
    n: integer;
  begin
    n := Length(FParams);
    SetLength(FParams, n + 1);
    with FParams[n] do
    begin
      Group := CurGroup;
      Name := AName;
      Hint := AHint;
      Kind := pkFloat;
      PValue := @V;
      PColor := nil;
      Min := AMin;
      Max := AMax;
      Decimals := ADec;
      Stages := CurStages;
    end;
  end;

  procedure C(const AName, AHint: string; var V: TBGRAPixel);
  var
    n: integer;
  begin
    n := Length(FParams);
    SetLength(FParams, n + 1);
    with FParams[n] do
    begin
      Group := CurGroup;
      Name := AName;
      Hint := AHint;
      Kind := pkColor;
      PValue := nil;
      PColor := @V;
      Min := 0;
      Max := 255;
      Decimals := 0;
      Stages := CurStages;
    end;
  end;

var
  i, L: integer;
begin
  FParams := nil;
  with FSettings do
  begin
    CurGroup := 'Geometry';
    CurStages := AllStages;
    F('Hex size', 'Base hex radius = sqrt(W x H) x this. Also scales bokeh and sparks.', HexSize, 0.01, 0.12, 3);
    CurStages := HexStages + [stBokeh, stSparks];
    F('Edge top', 'Height (0..1) of the cluster edge at the left side.', EdgeTop, 0, 1.2, 2);
    F('Edge slope', 'How much the edge rises toward the right side.', EdgeSlope, -0.5, 1.5, 2);
    F('Fade start', 'Coverage where hexagons start to appear (negative = above the edge).', FadeStart, -0.5, 0.5, 2);
    F('Fade end', 'Coverage where the cluster reaches full density.', FadeEnd, -0.2, 1, 2);
    CurStages := HexStages;
    F('Cell gap', 'Lattice spacing / hex size. 1 = touching.', Gap, 0.9, 2, 2);
    F('Size jitter', 'Random size variation of each hexagon.', SizeJitter, 0, 0.5, 2);
    F('Rotation jitter', 'Random rotation of each hexagon, in degrees.', RotJitter, 0, 60, 1);
    F('Edge wobble', 'Random offset of the sparse cells at the cluster edge (x hex size).', EdgeWobble, 0, 1.5, 2);
    F('Noise freq min', 'Cluster noise: lowest frequency (per hex).', NoiseFreqMin, 0.01, 1, 2);
    F('Noise freq range', 'Cluster noise: random extra frequency.', NoiseFreqRange, 0, 1, 2);
    F('Cluster low', 'Noise value where patches start.', ClusterLo, 0, 1, 2);
    F('Cluster high', 'Noise value where patches are full.', ClusterHi, 0, 1, 2);
    F('Cluster min', 'Density kept outside patches (0 = holes, 1 = no patches).', ClusterMin, 0, 1, 2);

    CurGroup := 'Loose hexagons';
    F('Chance', 'Chance an empty cell near the edge spawns a stray hexagon.', LooseChance, 0, 0.5, 3);
    F('Zone top', 'Coverage above which strays may appear.', LooseZoneTop, -1, 0.5, 2);
    F('Zone bottom', 'Coverage below which strays may appear.', LooseZoneBottom, -0.5, 1, 2);
    F('Drift', 'How far strays drift up-left (x hex size).', LooseDrift, 0, 5, 2);
    F('Rotation', 'Rotation range of strays, in degrees.', LooseRot, 0, 90, 1);
    F('Shrink', 'Max size reduction of strays.', LooseShrink, 0, 0.9, 2);

    CurGroup := '3D extrusion';
    F('Vanish X', 'Vanishing point X (0..1). Back faces move toward it.', VanishX, -1, 2, 2);
    F('Vanish Y', 'Vanishing point Y (0..1).', VanishY, -1, 2, 2);
    F('Depth', 'Extrusion length per pixel of distance to the vanishing point.', Extrude, 0, 0.3, 3);
    F('Depth max', 'Max extrusion length (x hex size).', ExtrudeMax, 0, 1.5, 2);

    CurGroup := 'Hexagon style';
    C('Rim colour', 'Front face outline.', EdgeColor);
    C('Face colour', 'Front face fill (alpha comes from each layer).', FillColor);
    C('Back colour', 'Back face and side edges.', BackColor);
    C('Inner rim colour', 'Thin inner outline.', InnerColor);
    C('Specular colour', 'Highlight on the upper-left edge.', SpecColor);
    F('Line width', 'Rim width = hex size x this (min 1 px).', LineWidth, 0.01, 0.3, 3);
    F('Back size', 'Back face size relative to the front face.', BackSize, 0.5, 1.2, 2);
    F('Back alpha', 'Back face alpha x rim alpha.', BackAlpha, 0, 1, 2);
    F('Side alpha', 'Side edges alpha x rim alpha.', SideAlpha, 0, 1, 2);
    F('Inner size', 'Inner rim size relative to the front face.', InnerSize, 0.3, 1, 2);
    F('Inner alpha', 'Inner rim alpha x rim alpha.', InnerAlpha, 0, 1, 2);
    F('Specular alpha', 'Highlight alpha x rim alpha.', SpecAlpha, 0, 1, 2);

    CurGroup := 'Glow';
    C('Glow colour', 'Colour of the blurred halo around rims.', GlowColor);
    F('Glow width', 'Halo stroke width x rim width.', GlowWidth, 0.5, 10, 1);
    F('Glow strength', 'Halo alpha x rim alpha x layer glow.', GlowStrength, 0, 2, 2);
    F('Glow blur', 'Halo blur radius x layer hex size.', GlowBlur, 0, 1.5, 2);

    for L := 0 to LayerCount - 1 do
    begin
      CurGroup := Format('Layer %d - %s', [L + 1, LayerNames[L]]);
      CurStages := [stFarGlow + 2 * L, stFar + 2 * L];
      F('Scale', 'Hex size relative to the base hex size.', Layers[L].Scale, 0.1, 4, 2);
      F('Blur', 'Depth-of-field blur radius x base hex size.', Layers[L].Blur, 0, 1, 2);
      F('Rim alpha', 'Opacity of the rims (0..255).', Layers[L].EdgeA, 0, 255, 0);
      F('Face alpha', 'Opacity of the dark faces (0..255).', Layers[L].FillA, 0, 255, 0);
      F('Density', 'Chance a covered cell holds a hexagon.', Layers[L].Density, 0, 1, 2);
      F('Reach', 'Moves this layer''s edge (+ = further up-left).', Layers[L].Reach, -1, 1, 2);
      F('Glow', 'Glow amount for this layer (0 = off).', Layers[L].Glow, 0, 2, 2);
    end;

    CurGroup := 'Base';
    CurStages := [stBase];
    C('Base colour', 'Background fill.', BaseColor);
    for i := 0 to 2 do
    begin
      C(Format('Haze %d colour', [i + 1]), 'Radial haze colour; alpha = strength.', HazeColor[i]);
      F(Format('Haze %d X', [i + 1]), 'Haze centre X (0..1).', HazeX[i], -0.5, 1.5, 2);
      F(Format('Haze %d Y', [i + 1]), 'Haze centre Y (0..1).', HazeY[i], -0.5, 1.5, 2);
      F(Format('Haze %d radius', [i + 1]), 'Haze radius x the longer image side.', HazeR[i], 0.05, 2, 2);
    end;

    CurGroup := 'Bokeh';
    CurStages := [stBokeh];
    F('Count / megapixel', 'Blob attempts per million pixels.', BokehPerMP, 0, 1000, 0);
    F('Max count', 'Upper limit of blob attempts.', BokehMax, 0, 2000, 0);
    F('Edge band', 'Width of the band along the cluster edge where blobs gather.', BokehBand, 0.02, 1, 2);
    F('Base chance', 'Chance to keep a blob far from the edge.', BokehBaseChance, 0, 1, 2);
    F('Big chance', 'Share of big soft blobs (the rest are small dots).', BokehBigChance, 0, 1, 2);
    C('Big colour', 'Colour of the big blobs.', BokehBigColor);
    F('Big size min', 'x base hex size.', BokehBigMin, 0, 3, 2);
    F('Big size max', 'x base hex size.', BokehBigMax, 0, 3, 2);
    F('Big alpha min', '0..255', BokehBigAlphaMin, 0, 255, 0);
    F('Big alpha max', '0..255', BokehBigAlphaMax, 0, 255, 0);
    C('Dot colour', 'Colour of the small dots.', BokehDotColor);
    F('Dot size min', 'x base hex size.', BokehDotMin, 0, 1, 2);
    F('Dot size max', 'x base hex size.', BokehDotMax, 0, 1, 2);
    F('Dot alpha min', '0..255', BokehDotAlphaMin, 0, 255, 0);
    F('Dot alpha max', '0..255', BokehDotAlphaMax, 0, 255, 0);
    F('Blur', 'Blur radius x base hex size.', BokehBlur, 0, 1, 2);

    CurGroup := 'Vignette';
    CurStages := [stVignette];
    F('Strength', 'Corner darkness alpha (0..255).', VigAlpha, 0, 255, 0);
    F('Centre X', '0..1', VigX, 0, 1, 2);
    F('Centre Y', '0..1', VigY, 0, 1, 2);
    F('Radius', 'x image diagonal.', VigRadius, 0.1, 2, 2);
    F('Shadow alpha', 'Top-left shadow alpha (0..255).', ShadowAlpha, 0, 255, 0);
    F('Shadow end X', 'Where the shadow fades out (0..1).', ShadowX, 0.01, 1.5, 2);
    F('Shadow end Y', 'Where the shadow fades out (0..1).', ShadowY, 0.01, 1.5, 2);

    CurGroup := 'Sparks';
    CurStages := [stSparks];
    F('Count / megapixel', 'Sparks per million pixels.', SparkPerMP, 0, 3000, 0);
    F('Min count', 'Lower limit of the spark count.', SparkMin, 0, 2000, 0);
    F('Max count', 'Upper limit of the spark count.', SparkMax, 0, 5000, 0);
    F('Field bias', '0 = anywhere, 1 = only inside the hex field.', SparkFieldBias, 0, 1, 2);
    F('Size min', 'Core radius x base hex size.', SparkSizeMin, 0.005, 0.3, 3);
    F('Size max', 'Core radius x base hex size.', SparkSizeMax, 0.005, 0.3, 3);
    F('Alpha min', '0..255', SparkAlphaMin, 0, 255, 0);
    F('Alpha max', '0..255', SparkAlphaMax, 0, 255, 0);
    C('Core colour', 'Bright centre.', SparkCoreColor);
    C('Halo colour', 'Glow around the centre.', SparkHaloColor);
    F('Halo size', 'Halo radius x core radius.', SparkHaloSize, 1, 10, 1);
    F('Halo alpha', 'Halo alpha x spark alpha.', SparkHaloAlpha, 0, 1, 2);
    F('Soft chance', 'Share of out-of-focus sparks (one soft blob).', SparkSoftChance, 0, 1, 2);
    C('Soft colour', 'Colour of soft sparks.', SparkSoftColor);
    F('Soft size', 'Soft spark radius x core radius.', SparkSoftSize, 0.5, 8, 1);
    F('Soft alpha', 'Soft spark alpha x spark alpha.', SparkSoftAlpha, 0, 1, 2);
    F('Rise min', 'Upward speed, px/s.', SparkRiseMin, -50, 100, 1);
    F('Rise max', 'Upward speed, px/s.', SparkRiseMax, -50, 100, 1);
    F('Sway min', 'Sideways sway speed, px/s.', SparkSwayMin, 0, 60, 1);
    F('Sway max', 'Sideways sway speed, px/s.', SparkSwayMax, 0, 60, 1);
    F('Life min', 'Seconds from fade-in to fade-out.', SparkLifeMin, 0.2, 30, 1);
    F('Life max', 'Seconds from fade-in to fade-out.', SparkLifeMax, 0.2, 30, 1);
    F('Twinkle min', 'Twinkle speed, rad/s.', SparkTwinkleMin, 0, 30, 1);
    F('Twinkle max', 'Twinkle speed, rad/s.', SparkTwinkleMax, 0, 30, 1);
    F('Twinkle depth', '0 = steady, 1 = blinks fully off.', SparkTwinkleDepth, 0, 1, 2);
  end;
end;

{ --------------------------------------------------------------- helpers }

// Signed distance (normalized units) below the diagonal edge of the cluster:
// > 0 inside the hex field (bottom / right), < 0 in the empty upper-left.
function THexBackground.Coverage(x, y: single): single;
begin
  Result := y / FHeight - (FSettings.EdgeTop - FSettings.EdgeSlope * x / FWidth);
end;

// Cheap smooth noise 0..1 used to break the cluster into patches.
function THexBackground.Noise(x, y: single): single;
begin
  x := x / FScale;
  y := y / FScale;
  Result := 0.5 + (Sin(x * FNoiseF[0] + FNoiseP[0]) * Sin(y * FNoiseF[1] + FNoiseP[1])
    + 0.5 * Sin((x + y) * FNoiseF[2] + FNoiseP[2])) / 3;
end;

procedure THexBackground.DrawHexPrism(Bmp: TBGRABitmap; cx, cy, r, rot: single;
  Ext: TPointF; EdgeA, FillA, LineW: single);
var
  Fr, B, Inner: ArrayOfTPointF;
  i: integer;
begin
  with FSettings do
  begin
    Fr := HexPoints(cx, cy, r, rot);
    B := HexPoints(cx + Ext.x, cy + Ext.y, r * BackSize, rot);
    Inner := HexPoints(cx, cy, r * InnerSize, rot);

    // back face and side edges (the far side of the prism)
    Bmp.DrawPolygonAntialias(B, WithAlpha(BackColor, EdgeA * BackAlpha), LineW * 0.8);
    for i := 0 to 5 do
      Bmp.DrawLineAntialias(Fr[i].x, Fr[i].y, B[i].x, B[i].y,
        WithAlpha(BackColor, EdgeA * SideAlpha), LineW * 0.7);

    // front face: dark glassy fill + bright rim + faint inner rim
    Bmp.DrawPolygonAntialias(Fr, WithAlpha(EdgeColor, EdgeA), LineW, WithAlpha(FillColor, FillA));
    Bmp.DrawPolygonAntialias(Inner, WithAlpha(InnerColor, EdgeA * InnerAlpha), LineW * 0.5);
    // specular on the upper-left edge
    Bmp.DrawLineAntialias(Fr[3].x, Fr[3].y, Fr[4].x, Fr[4].y,
      WithAlpha(SpecColor, EdgeA * SpecAlpha), LineW * 0.6);
  end;
end;

{ ---------------------------------------------------------------- stages }

procedure THexBackground.RenderBase;
var
  Bmp: TBGRABitmap;
  M: single;
  i: integer;
begin
  Bmp := FStages[stBase].Bitmap;
  M := Max(FWidth, FHeight);
  with FSettings do
  begin
    Bmp.Fill(WithAlpha(BaseColor, 255));
    for i := 0 to 2 do
      Bmp.GradientFill(0, 0, FWidth, FHeight, HazeColor[i], WithAlpha(HazeColor[i], 0),
        gtRadial, PointF(FWidth * HazeX[i], FHeight * HazeY[i]),
        PointF(FWidth * HazeX[i] + M * HazeR[i], FHeight * HazeY[i]), dmDrawWithTransparency);
  end;
  FStages[stBase].Items := 3;
end;

procedure THexBackground.RenderBokeh;
var
  S: PStage;
  i, n, Big, Dots: integer;
  x, y, t, r: single;
begin
  S := @FStages[stBokeh];
  S^.Bitmap.FillTransparent;
  Big := 0;
  Dots := 0;
  with FSettings do
  begin
    n := EnsureRange(Round(FWidth * FHeight / 1e6 * BokehPerMP), 0, Round(BokehMax));
    for i := 1 to n do
    begin
      x := Random * FWidth;
      y := Random * FHeight;
      t := Coverage(x, y);
      // most blobs float along the edge of the cluster
      if Random > BokehBaseChance + (1 - BokehBaseChance) * Exp(-Sqr(t / BokehBand)) then
        Continue;
      if Random < BokehBigChance then
      begin
        r := FScale * RandRange(BokehBigMin, BokehBigMax);
        S^.Bitmap.FillEllipseAntialias(x, y, r, r,
          WithAlpha(BokehBigColor, RandRange(BokehBigAlphaMin, BokehBigAlphaMax)));
        Inc(Big);
      end
      else
      begin
        r := FScale * RandRange(BokehDotMin, BokehDotMax);
        S^.Bitmap.FillEllipseAntialias(x, y, r, r,
          WithAlpha(BokehDotColor, RandRange(BokehDotAlphaMin, BokehDotAlphaMax)));
        Inc(Dots);
      end;
    end;
    if BokehBlur > 0 then
      BGRAReplace(S^.Bitmap, S^.Bitmap.FilterBlurRadial(FScale * BokehBlur, rbFast));
  end;
  S^.Items := Big;
  S^.Extra := Dots;
end;

procedure THexBackground.RenderHexLayer(L: integer);
var
  G, H: PStage;
  Ly: THexLayer;
  r, rr, dx, dy, ox, oy, cx, cy, t, p, rot, jit, lw, vx, vy, len: single;
  col, row, cols, rows, Count, LooseCount: integer;
  Ext: TPointF;
  Loose: boolean;
begin
  G := @FStages[stFarGlow + 2 * L];
  H := @FStages[stFar + 2 * L];
  Ly := FSettings.Layers[L];
  H^.Bitmap.FillTransparent;
  G^.Bitmap.Fill(BGRABlack);
  Count := 0;
  LooseCount := 0;

  with FSettings do
  begin
    r := FScale * Ly.Scale;
    dx := 1.5 * r * Gap;
    dy := Sqrt(3) * r * Gap;
    lw := Max(1.0, r * LineWidth);
    ox := -Random * dx;
    oy := -Random * dy;
    cols := Ceil((FWidth + 2 * r) / dx) + 2;
    rows := Ceil((FHeight + 2 * r) / dy) + 2;
    vx := FWidth * VanishX;
    vy := FHeight * VanishY;

    for col := 0 to cols - 1 do
      for row := 0 to rows - 1 do
      begin
        cx := ox + col * dx;
        cy := oy + row * dy;
        if Odd(col) then cy := cy + dy / 2;

        t := Coverage(cx, cy) + Ly.Reach;
        p := SmoothStep(FadeStart, FadeEnd, t) * Ly.Density *
          (ClusterMin + (1 - ClusterMin) * SmoothStep(ClusterLo, ClusterHi, Noise(cx, cy)));
        Loose := False;
        if Random >= p then
        begin
          // a few stray hexagons floating off the edge of the cluster
          if (t > LooseZoneTop) and (t < LooseZoneBottom) and (Random < LooseChance * Ly.Density) then
            Loose := True
          else
            Continue;
        end;

        rot := (Random - 0.5) * DegToRad(RotJitter);
        rr := r * (1 - SizeJitter * 0.7 + Random * SizeJitter);
        if Loose then
        begin
          jit := r * (0.5 + Random * LooseDrift);
          cx := cx - jit * 0.6;
          cy := cy - jit * 0.8;
          rot := (Random - 0.5) * DegToRad(LooseRot);
          rr := rr * (1 - LooseShrink * Random);
          Inc(LooseCount);
        end
        else if p < 0.4 * Ly.Density then
        begin
          // wobbly cells at the edge of the cluster
          cx := cx + (Random - 0.5) * r * EdgeWobble;
          cy := cy + (Random - 0.5) * r * EdgeWobble;
        end;

        Ext := PointF((vx - cx) * Extrude * Ly.Scale, (vy - cy) * Extrude * Ly.Scale);
        len := Sqrt(Sqr(Ext.x) + Sqr(Ext.y));
        if len > rr * ExtrudeMax then
          Ext := Ext * (rr * ExtrudeMax / len);

        DrawHexPrism(H^.Bitmap, cx, cy, rr, rot, Ext, Ly.EdgeA, Ly.FillA, lw);
        if Ly.Glow > 0 then
          G^.Bitmap.DrawPolygonAntialias(HexPoints(cx, cy, rr, rot),
            WithAlpha(GlowColor, Ly.EdgeA * Ly.Glow * GlowStrength), lw * GlowWidth);
        Inc(Count);
      end;

    if (Ly.Glow > 0) and (r * GlowBlur + FScale * Ly.Blur > 0) then
      BGRAReplace(G^.Bitmap, G^.Bitmap.FilterBlurRadial(r * GlowBlur + FScale * Ly.Blur, rbFast));
    if Ly.Blur > 0 then
      BGRAReplace(H^.Bitmap, H^.Bitmap.FilterBlurRadial(FScale * Ly.Blur, rbFast));
  end;
  H^.Items := Count;
  H^.Extra := LooseCount;
  if Ly.Glow > 0 then G^.Items := Count else G^.Items := 0;
end;

procedure THexBackground.RenderVignette;
var
  Bmp: TBGRABitmap;
  D: single;
begin
  Bmp := FStages[stVignette].Bitmap;
  Bmp.FillTransparent;
  D := Sqrt(Sqr(FWidth) + Sqr(FHeight));
  with FSettings do
  begin
    Bmp.GradientFill(0, 0, FWidth, FHeight, BGRA(0, 0, 0, 0), WithAlpha(BGRABlack, VigAlpha),
      gtRadial, PointF(FWidth * VigX, FHeight * VigY),
      PointF(FWidth * VigX + D * VigRadius, FHeight * VigY), dmDrawWithTransparency);
    // deep shadow in the empty top-left corner
    Bmp.GradientFill(0, 0, FWidth, FHeight, WithAlpha(BGRABlack, ShadowAlpha), BGRA(0, 0, 0, 0),
      gtLinear, PointF(0, 0), PointF(FWidth * ShadowX, FHeight * ShadowY), dmDrawWithTransparency);
  end;
  FStages[stVignette].Items := 2;
end;

procedure THexBackground.NewSpark(var S: TSpark; RandomLife: boolean);
var
  t: single;
  Tries: integer;
begin
  with FSettings do
  begin
    // sparks live mostly inside the hex field
    Tries := 0;
    repeat
      S.X := Random * FWidth;
      S.Y := Random * FHeight;
      t := Coverage(S.X, S.Y);
      Inc(Tries);
    until (Random < (1 - SparkFieldBias) + SparkFieldBias * SmoothStep(FadeStart - 0.03, FadeEnd + 0.05, t))
      or (Tries > 50);
    S.Soft := Random < SparkSoftChance;
    S.Size := FScale * RandRange(SparkSizeMin, SparkSizeMax);
    S.Alpha := RandRange(SparkAlphaMin, SparkAlphaMax);
    S.Phase := Random * 2 * Pi;
    S.Twinkle := RandRange(SparkTwinkleMin, SparkTwinkleMax);
    S.VY := -RandRange(SparkRiseMin, SparkRiseMax);
    S.Sway := RandRange(SparkSwayMin, SparkSwayMax);
    S.LifeSpeed := 1 / Max(0.1, RandRange(SparkLifeMin, SparkLifeMax));
  end;
  if RandomLife then S.Life := Random else S.Life := 0;
end;

procedure THexBackground.InitSparks;
var
  i: integer;
begin
  with FSettings do
    SetLength(FSparks, Max(0, Min(Round(SparkMax),
      Max(Round(SparkMin), Round(FWidth * FHeight / 1e6 * SparkPerMP)))));
  for i := 0 to High(FSparks) do
    NewSpark(FSparks[i], True);
  FStages[stSparks].Items := Length(FSparks);
end;

procedure THexBackground.RenderSparksSnapshot;
begin
  FStages[stSparks].Bitmap.FillTransparent;
  DrawSparks(FStages[stSparks].Bitmap);
end;

{ -------------------------------------------------------------- pipeline }

procedure THexBackground.Update;
var
  i, L: integer;
  t0: QWord;
begin
  FScale := Sqrt(FWidth * FHeight) * FSettings.HexSize;
  RandSeed := FSeed;
  for i := 0 to 2 do
  begin
    FNoiseF[i] := FSettings.NoiseFreqMin + Random * FSettings.NoiseFreqRange;
    FNoiseP[i] := Random * 2 * Pi;
  end;

  for i := 0 to StageCount - 1 do
    with FStages[i] do
      if Dirty and ((Bitmap.Width <> FWidth) or (Bitmap.Height <> FHeight)) then
        Bitmap.SetSize(FWidth, FHeight);

  // a hex layer renders its glow stage and its hex stage in one pass
  for L := 0 to LayerCount - 1 do
    if FStages[stFarGlow + 2 * L].Dirty then
      FStages[stFar + 2 * L].Dirty := True;

  for i := 0 to StageCount - 1 do
  begin
    if not FStages[i].Dirty then Continue;
    t0 := GetTickCount64;
    RandSeed := FSeed + (i + 1) * 7919;
    case i of
      stBase: RenderBase;
      stBokeh: RenderBokeh;
      stFarGlow, stMidGlow, stFocusGlow, stNearGlow: Continue;   // done with its hex stage
      stFar, stMid, stFocus, stNear:
        begin
          RenderHexLayer((i - stFar) div 2);
          FStages[i - 1].Dirty := False;
          FStages[i - 1].TimeMs := 0;
        end;
      stVignette: RenderVignette;
      stSparks:
        begin
          InitSparks;
          RenderSparksSnapshot;
        end;
    end;
    FStages[i].TimeMs := GetTickCount64 - t0;
    FStages[i].Dirty := False;
  end;
  Compose;
end;

procedure THexBackground.Compose;
var
  i: integer;
  t0: QWord;
begin
  t0 := GetTickCount64;
  FBackground.SetSize(FWidth, FHeight);
  if FStages[stBase].Enabled then
    FBackground.PutImage(0, 0, FStages[stBase].Bitmap, dmSet)
  else
    FBackground.Fill(BGRABlack);
  for i := stBokeh to stVignette do
    with FStages[i] do
    begin
      if not Enabled or (Additive and (Items = 0)) then Continue;
      if Additive then
        FBackground.BlendImage(0, 0, Bitmap, boAdditive)
      else
        FBackground.PutImage(0, 0, Bitmap, dmDrawWithTransparency);
    end;
  FComposeMs := GetTickCount64 - t0;
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

procedure THexBackground.DrawSparks(Dest: TBGRABitmap);
var
  i: integer;
  a: single;
begin
  with FSettings do
    for i := 0 to High(FSparks) do
      with FSparks[i] do
      begin
        a := Alpha * Sin(Pi * Life) *
          ((1 - SparkTwinkleDepth) + SparkTwinkleDepth * Sin(FTime * Twinkle + Phase));
        if a < 3 then Continue;
        if Soft then
          Dest.FillEllipseAntialias(X, Y, Size * SparkSoftSize, Size * SparkSoftSize,
            WithAlpha(SparkSoftColor, a * SparkSoftAlpha))
        else
        begin
          Dest.FillEllipseAntialias(X, Y, Size * SparkHaloSize, Size * SparkHaloSize,
            WithAlpha(SparkHaloColor, a * SparkHaloAlpha));
          Dest.FillEllipseAntialias(X, Y, Size, Size, WithAlpha(SparkCoreColor, a));
        end;
      end;
end;

procedure THexBackground.DrawFrame(Dest: TBGRABitmap);
begin
  Dest.SetSize(FWidth, FHeight);
  Dest.PutImage(0, 0, FBackground, dmSet);
  if FStages[stSparks].Enabled then
    DrawSparks(Dest);
end;

// One stage alone: transparent stages are shown over a checkerboard.
procedure THexBackground.DrawStageView(Dest: TBGRABitmap; Index: integer);
begin
  Dest.SetSize(FWidth, FHeight);
  with FStages[Index] do
  begin
    if Additive or (Index = stBase) then
      Dest.PutImage(0, 0, Bitmap, dmSet)
    else
    begin
      DrawCheckers(Dest, 16);
      if Index = stSparks then
        DrawSparks(Dest)
      else
        Dest.PutImage(0, 0, Bitmap, dmDrawWithTransparency);
    end;
  end;
end;

procedure THexBackground.DrawThumbnail(Dest: TBGRABitmap; Index: integer);
var
  w, h: integer;
  R: TRect;
  Small: TBGRABitmap;
begin
  DrawCheckers(Dest, 6);
  if FWidth / FHeight > Dest.Width / Dest.Height then
  begin
    w := Dest.Width;
    h := Max(1, Round(Dest.Width * FHeight / FWidth));
  end
  else
  begin
    h := Dest.Height;
    w := Max(1, Round(Dest.Height * FWidth / FHeight));
  end;
  R.Left := (Dest.Width - w) div 2;
  R.Top := (Dest.Height - h) div 2;
  R.Right := R.Left + w;
  R.Bottom := R.Top + h;
  Small := FStages[Index].Bitmap.Resample(w, h, rmFineResample);
  try
    Dest.PutImage(R.Left, R.Top, Small, dmDrawWithTransparency);
  finally
    Small.Free;
  end;
end;

function THexBackground.StageSummary(Index: integer): string;
begin
  with FStages[Index] do
    case Index of
      stBase: Result := '1 fill + 3 radial hazes';
      stBokeh: Result := Format('%d soft blobs + %d dots', [Items, Extra]);
      stFarGlow, stMidGlow, stFocusGlow, stNearGlow:
        if Items = 0 then Result := 'off (layer Glow = 0)'
        else Result := Format('halo of %d rims', [Items]);
      stFar, stMid, stFocus, stNear:
        Result := Format('%d hexagons (%d loose)', [Items, Extra]);
      stVignette: Result := 'radial + linear gradient';
      stSparks: Result := Format('%d sparks, animated', [Items]);
    else
      Result := '';
    end;
end;

{ ---------------------------------------------------------------- report }

function THexBackground.Report: string;
var
  SL: TStringList;
  i, L, Total: integer;
  LastGroup, V: string;
  Ms: QWord;
begin
  SL := TStringList.Create;
  try
    SL.Add('HEX BACKGROUND - RENDER REPORT');
    SL.Add(StringOfChar('=', 60));
    SL.Add(Format('Output size     : %d x %d px', [FWidth, FHeight]));
    SL.Add(Format('Seed            : %d  (stage i uses Seed + (i+1) x 7919)', [FSeed]));
    SL.Add(Format('Base hex radius : %.1f px  (sqrt(W x H) x Hex size)', [FScale]));
    for L := 0 to LayerCount - 1 do
      with FSettings do
        SL.Add(Format('  %-6s radius %.1f px, lattice step %.1f x %.1f px, blur %.1f px',
          [LayerNames[L], FScale * Layers[L].Scale, 1.5 * FScale * Layers[L].Scale * Gap,
           Sqrt(3) * FScale * Layers[L].Scale * Gap, FScale * Layers[L].Blur]));
    SL.Add(Format('Cluster edge    : y/H = %.2f - %.2f x x/W', [FSettings.EdgeTop, FSettings.EdgeSlope]));
    SL.Add(Format('Vanishing point : (%.0f, %.0f) px', [FWidth * FSettings.VanishX, FHeight * FSettings.VanishY]));
    SL.Add(Format('Noise           : freq %.3f / %.3f / %.3f, phase %.2f / %.2f / %.2f',
      [FNoiseF[0], FNoiseF[1], FNoiseF[2], FNoiseP[0], FNoiseP[1], FNoiseP[2]]));
    SL.Add('');
    SL.Add('STAGES (bottom to top)');
    SL.Add(StringOfChar('-', 60));
    Ms := 0;
    Total := 0;
    for i := 0 to StageCount - 1 do
      with FStages[i] do
      begin
        SL.Add(Format('%2d  %-16s %-3s %4d ms   %s',
          [i, Name, BoolToStr(Enabled, 'on', 'off'), TimeMs, StageSummary(i)]));
        SL.Add('      blend : ' + Blend);
        SL.Add('      how   : ' + Technique);
        Inc(Ms, TimeMs);
        if i in [stFar, stMid, stFocus, stNear] then Inc(Total, Items);
      end;
    SL.Add(Format('Total hexagons: %d   Stage render time: %d ms   Compose: %d ms',
      [Total, Ms, FComposeMs]));
    SL.Add('');
    SL.Add('PARAMETERS');
    SL.Add(StringOfChar('-', 60));
    LastGroup := '';
    for i := 0 to High(FParams) do
      with FParams[i] do
      begin
        if Group <> LastGroup then
        begin
          SL.Add('[' + Group + ']');
          LastGroup := Group;
        end;
        if Kind = pkColor then
          V := Format('RGBA(%d, %d, %d, %d)', [PColor^.red, PColor^.green, PColor^.blue, PColor^.alpha])
        else
          V := FloatToStrF(PValue^, ffFixed, 15, Decimals);
        SL.Add(Format('  %-20s = %-22s %s', [Name, V, Hint]));
      end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

{ ------------------------------------------------------------- ini files }

procedure THexBackground.SaveToIni(const FileName: string);
var
  Ini: TIniFile;
  FS: TFormatSettings;
  i: integer;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Ini := TIniFile.Create(FileName);
  try
    Ini.WriteInteger('General', 'Seed', FSeed);
    for i := 0 to StageCount - 1 do
      Ini.WriteBool('Stages', FStages[i].Name, FStages[i].Enabled);
    for i := 0 to High(FParams) do
      with FParams[i] do
        if Kind = pkColor then
          Ini.WriteString(Group, Name, Format('%.2x%.2x%.2x%.2x',
            [PColor^.red, PColor^.green, PColor^.blue, PColor^.alpha]))
        else
          Ini.WriteString(Group, Name, FloatToStr(PValue^, FS));
  finally
    Ini.Free;
  end;
end;

procedure THexBackground.LoadFromIni(const FileName: string);
var
  Ini: TIniFile;
  FS: TFormatSettings;
  i: integer;
  s: string;
  c: longint;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Ini := TIniFile.Create(FileName);
  try
    FSeed := Ini.ReadInteger('General', 'Seed', FSeed);
    for i := 0 to StageCount - 1 do
      FStages[i].Enabled := Ini.ReadBool('Stages', FStages[i].Name, FStages[i].Enabled);
    for i := 0 to High(FParams) do
      with FParams[i] do
      begin
        s := Ini.ReadString(Group, Name, '');
        if s = '' then Continue;
        if Kind = pkColor then
        begin
          if (Length(s) = 8) and TryStrToInt('$' + s, c) then
            PColor^ := BGRA((c shr 24) and $FF, (c shr 16) and $FF, (c shr 8) and $FF, c and $FF);
        end
        else
          PValue^ := StrToFloatDef(s, PValue^, FS);
      end;
  finally
    Ini.Free;
  end;
  MarkDirty(AllStages);
end;

end.
