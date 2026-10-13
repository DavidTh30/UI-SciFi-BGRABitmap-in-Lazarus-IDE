unit UChevronLoader;

{ Chevron Loader - segmented round gauge with a percentage readout next to
  an arrow-shaped bar filled with chevrons that light up with progress. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TChevronLoaderWidget }

  TChevronLoaderWidget = class(THUDWidget)
  private
    FAuto: single;       // 1 = cycle automatically, 0 = use FManual
    FSpeed: single;      // cycles per second in auto mode
    FManual: single;     // progress in percent in manual mode
    FCount: single;      // number of chevrons
    FCaption: string;    // label text, default LOADING...
    function Progress: single;
    procedure SetCaption(const AValue: string);
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
    property Caption: string read FCaption write SetCaption;
  end;

implementation

const
  ViewW = 300;
  ViewH = 80;
  AY = 40;        // centre line
  GX = 43;        // gauge centre x
  BarL = 85;      // arrow bar left
  BarR = 275;     // arrow tip
  StartAt = 0.65; // progress at t = 0 (as in the design: 65%)

constructor TChevronLoaderWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FCaption := 'LOADING...';
  FAuto := 1;
  FSpeed := 0.06;
  FManual := 65;
  FCount := 14;
  AddParam('Auto progress', 'Data', '1 = progress cycles 0..100% automatically, 0 = use "Progress %".',
    FAuto, 0, 1, 0, False);
  AddParam('Progress %', 'Data', 'Progress shown when Auto progress = 0.',
    FManual, 0, 100, 1, False);
  AddParam('Cycle speed', 'Animation', 'Auto mode: full cycles per second.',
    FSpeed, 0, 2, 3, False);
  AddParam('Chevron count', 'Style', 'Number of chevrons in the bar (spacing 12 units).',
    FCount, 1, 15, 0, True);
  AddTextParam('Label text', 'Content', 'Text of the label (e.g. the name of the value shown).',
    FCaption, True);
end;

class function TChevronLoaderWidget.UIName: string;
begin
  Result := 'Chevron Loader';
end;

class function TChevronLoaderWidget.UIDescription: string;
begin
  Result := 'Segmented round gauge with percentage readout next to an arrow-shaped bar of chevrons ' +
    'that light up with progress. Used for loading / transfer / charge progress.';
end;

class function TChevronLoaderWidget.UnitFile: string;
begin
  Result := 'ChevronLoader\uchevronloader.pas';
end;

procedure TChevronLoaderWidget.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  InvalidateStatic;  // the label is part of the static cache
end;

function TChevronLoaderWidget.Progress: single;
begin
  if FAuto >= 1 then
    Result := Frac(StartAt + Phase(0, FSpeed))
  else
    Result := FManual / 100;
end;

procedure TChevronLoaderWidget.DrawStatic;
var
  i: integer;
  bx: single;
begin
  // gauge
  Disc(GX, AY, 30, Navy(200));
  Ring(GX, AY, 30, 1, Ice(120));
  for i := 0 to 3 do
    Arc(GX, AY, 25, i * 90 + 8, i * 90 + 82, 6, Steel(150));
  Ring(GX, AY, 18, 1, Ice(150));
  // arrow bar and unlit chevrons
  Polygon([BarL, AY - 20, BarR - 15, AY - 20, BarR, AY, BarR - 15, AY + 20, BarL, AY + 20], 1.2, Ice(180));
  for i := 0 to Round(FCount) - 1 do
  begin
    bx := BarL + 7 + i * 12;
    FillPoly([bx, AY - 11, bx + 6, AY - 11, bx + 13, AY, bx + 6, AY + 11, bx, AY + 11, bx + 7, AY],
      Steel(110));
  end;
  Txt(BarL + 2, AY + 28, FCaption, 7, White(220));
end;

procedure TChevronLoaderWidget.DrawDynamic;
var
  i, n: integer;
  p, bx: single;
begin
  p := Progress;
  n := Round(FCount);
  Arc(GX, AY, 25, -90, -90 + 360 * p, 6, Ice);
  TxtCached(GX, AY, Format('%d%%', [Round(p * 100)]), 9, taCenter);
  for i := 0 to Round(p * n) - 1 do
  begin
    bx := BarL + 7 + i * 12;
    FillPoly([bx, AY - 11, bx + 6, AY - 11, bx + 13, AY, bx + 6, AY + 11, bx, AY + 11, bx + 7, AY],
      White(Round(150 + 105 * i / n)));
  end;
end;

procedure TChevronLoaderWidget.DefineDirty;
begin
  AddDirty(GX - 28, AY - 28, GX + 28, AY + 28);           // gauge
  AddDirty(BarL + 5, AY - 12, BarL + 9 + 15 * 12, AY + 12); // chevrons
end;

procedure TChevronLoaderWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 300 x 80, centre line AY = 40. Gauge centre GX = 43, bar 85..275.');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Gauge body      disc r30 Navy a200 + ring r30 w1 Ice a120');
  L.Add('  Gauge track     4 arcs r25 w6 Steel a150, 74 deg each, 16 deg gaps');
  L.Add('  Inner ring      r18 w1 Ice a150');
  L.Add('  Arrow bar       outline w1.2 Ice a180, 40 high, tip at x = 275');
  L.Add('  Chevrons        Chevron count x (13 x 22) at x = 92 + 12 i, Steel a110 (unlit)');
  L.Add('  Label           "LOADING..." size 7 at (87, AY+28)');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic), p = progress 0..1');
  L.Add('  Gauge progress  arc r25 w6 Ice from -90 deg over 360 * p');
  L.Add('  Readout         "NN%" size 9 centred in the gauge (cached text bitmaps)');
  L.Add('  Lit chevrons    first round(p * count) chevrons White, alpha 150..255 ramp');
  L.Add('');
  L.Add('DATA');
  L.Add('  Auto progress = 1: p = frac(0.65 + t * Cycle speed)');
  L.Add('  Auto progress = 0: p = Progress % / 100   (set it from your code / params)');
  L.Add('');
  L.Add('DIRTY RECTS       gauge, chevron strip (+ 24 glow margin)');
end;

procedure TChevronLoaderWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Progress            %.1f %%  (%s)', [Progress * 100, BoolToStr(FAuto >= 1, 'auto', 'manual')]));
  L.Add(Format('Chevrons lit        %d / %d', [Round(Progress * Round(FCount)), Round(FCount)]));
end;

end.
