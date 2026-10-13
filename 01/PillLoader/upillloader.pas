unit UPillLoader;

{ Pill Loader - dotted ring gauge with a percentage readout next to a
  rounded "pill" bar with a gradient fill and circuit-trace decorations. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TPillLoaderWidget }

  TPillLoaderWidget = class(THUDWidget)
  private
    FAuto: single;
    FSpeed: single;
    FManual: single;
    FDots: single;       // dots around the gauge
    function Progress: single;
    function DotPos(i, n: integer; out dx, dy: single): boolean;
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
  ViewW = 300;
  ViewH = 80;
  AY = 40;
  GX = 41;
  PillL = 87;
  PillR = 273;
  FillL = 91;          // inner fill start
  FillW = 178;         // inner fill width at 100%
  StartAt = 0.85;      // progress at t = 0 (as in the design: 85%)

constructor TPillLoaderWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FAuto := 1;
  FSpeed := 0.05;
  FManual := 85;
  FDots := 24;
  AddParam('Auto progress', 'Data', '1 = progress cycles 0..100% automatically, 0 = use "Progress %".',
    FAuto, 0, 1, 0, False);
  AddParam('Progress %', 'Data', 'Progress shown when Auto progress = 0.',
    FManual, 0, 100, 1, False);
  AddParam('Cycle speed', 'Animation', 'Auto mode: full cycles per second.',
    FSpeed, 0, 2, 3, False);
  AddParam('Gauge dots', 'Style', 'Number of dots around the gauge.',
    FDots, 6, 60, 0, True);
end;

class function TPillLoaderWidget.UIName: string;
begin
  Result := 'Pill Loader';
end;

class function TPillLoaderWidget.UIDescription: string;
begin
  Result := 'Dotted ring gauge with percentage readout next to a rounded pill bar with a gradient fill ' +
    'and circuit-trace decorations. Used for downloads, sync and buffering progress.';
end;

class function TPillLoaderWidget.UnitFile: string;
begin
  Result := 'PillLoader\upillloader.pas';
end;

function TPillLoaderWidget.Progress: single;
begin
  if FAuto >= 1 then
    Result := Frac(StartAt + T * FSpeed)
  else
    Result := FManual / 100;
end;

function TPillLoaderWidget.DotPos(i, n: integer; out dx, dy: single): boolean;
var
  a: single;
begin
  a := DegToRad(-90 + i * 360 / n);
  dx := GX + 28 * Cos(a);
  dy := AY + 28 * Sin(a);
  Result := True;
end;

procedure TPillLoaderWidget.DrawStatic;
var
  i, n: integer;
  dx, dy: single;
begin
  n := Round(FDots);
  for i := 0 to n - 1 do
    if DotPos(i, n, dx, dy) then
      Disc(dx, dy, 2.2, Steel(150));
  Disc(GX, AY, 20, Navy(200));
  // circuit traces
  PolyLine([100, AY - 10, 170, AY - 10, 178, AY - 18, 270, AY - 18], 0.8, Ice(160));
  Disc(270, AY - 18, 2, Ice);
  PolyLine([180, AY + 10, 240, AY + 10, 248, AY + 22, 270, AY + 22], 0.8, Ice(160));
  Disc(270, AY + 22, 2, Ice);
  Disc(100, AY - 10, 2, Ice);
  // pill track
  FFill.FillRoundRectAntialias(X(PillL), Y(AY - 9), X(PillR), Y(AY + 9), 9 * K, 9 * K, Navy(230));
  FLayer.RoundRectAntialias(X(PillL), Y(AY - 9), X(PillR), Y(AY + 9), 9 * K, 9 * K, Steel(150), 1 * K);
  Txt(PillL, AY + 18, 'LOADING...', 7, White(220));
end;

procedure TPillLoaderWidget.DrawDynamic;
var
  i, n: integer;
  p, dx, dy: single;
begin
  p := Progress;
  n := Round(FDots);
  for i := 0 to Round(p * n) - 1 do
    if DotPos(i, n, dx, dy) then
      Disc(dx, dy, 2.6, White);
  TxtCached(GX, AY, Format('%d%%', [Round(p * 100)]), 9, taCenter);
  if p > 0.02 then
  begin
    FLayer.GradientFill(Round(X(FillL)), Round(Y(AY - 5)), Round(X(FillL + FillW * p)), Round(Y(AY + 5)),
      Steel(255), Ice(255), gtLinear, PointF(X(FillL), 0), PointF(X(FillL + FillW * p), 0), dmSet);
    Line(FillL + FillW * p - 1, AY - 5, FillL + FillW * p - 1, AY + 5, 2, White);
  end;
end;

procedure TPillLoaderWidget.DefineDirty;
begin
  AddDirty(GX - 31, AY - 31, GX + 31, AY + 31);            // dots + readout
  AddDirty(FillL - 2, AY - 6, FillL + FillW + 2, AY + 6);  // fill
end;

procedure TPillLoaderWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 300 x 80, centre line AY = 40. Gauge centre GX = 41, pill 87..273.');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Gauge dots      Gauge dots x r2.2 Steel a150 on r28, first one at 12 o''clock');
  L.Add('  Gauge body      disc r20 Navy a200');
  L.Add('  Circuit traces  2 polylines w0.8 Ice a160 with r2 Ice end pads');
  L.Add('  Pill track      round rect 186 x 18, radius 9, Navy a230 + outline w1 Steel a150');
  L.Add('  Label           "LOADING..." size 7 at (87, AY+18)');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic), p = progress 0..1');
  L.Add('  Lit dots        first round(p * dots) dots r2.6 White (drawn over the unlit ones)');
  L.Add('  Readout         "NN%" size 9 centred (cached text bitmaps)');
  L.Add('  Fill            gradient Steel -> Ice, x 91..91+178p, 10 high, + end cap w2 White');
  L.Add('');
  L.Add('DATA');
  L.Add('  Auto progress = 1: p = frac(0.85 + t * Cycle speed)');
  L.Add('  Auto progress = 0: p = Progress % / 100');
  L.Add('');
  L.Add('DIRTY RECTS       gauge, pill fill (+ 24 glow margin)');
end;

procedure TPillLoaderWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Progress            %.1f %%  (%s)', [Progress * 100, BoolToStr(FAuto >= 1, 'auto', 'manual')]));
  L.Add(Format('Dots lit            %d / %d', [Round(Progress * Round(FDots)), Round(FDots)]));
end;

end.
