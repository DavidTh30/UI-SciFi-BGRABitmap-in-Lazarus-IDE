unit USlantLoader;

{ Slant Loader - thick progress-ring gauge with a percentage readout next
  to a slanted frame filled by a growing parallelogram wedge. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TSlantLoaderWidget }

  TSlantLoaderWidget = class(THUDWidget)
  private
    FAuto: single;
    FSpeed: single;
    FManual: single;
    FSlant: single;      // horizontal offset of the wedge top edge
    function Progress: single;
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
  WedgeL = 80;         // wedge bottom-left x
  WedgeW = 180;        // wedge length at 100%
  StartAt = 0.75;      // progress at t = 0 (as in the design: 75%)

constructor TSlantLoaderWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FAuto := 1;
  FSpeed := 0.045;
  FManual := 75;
  FSlant := 24;
  AddParam('Auto progress', 'Data', '1 = progress cycles 0..100% automatically, 0 = use "Progress %".',
    FAuto, 0, 1, 0, False);
  AddParam('Progress %', 'Data', 'Progress shown when Auto progress = 0.',
    FManual, 0, 100, 1, False);
  AddParam('Cycle speed', 'Animation', 'Auto mode: full cycles per second.',
    FSpeed, 0, 2, 3, False);
  AddParam('Slant', 'Style', 'Horizontal offset of the wedge top edge (0 = rectangle).',
    FSlant, 0, 30, 0, False);
end;

class function TSlantLoaderWidget.UIName: string;
begin
  Result := 'Slant Loader';
end;

class function TSlantLoaderWidget.UIDescription: string;
begin
  Result := 'Thick progress-ring gauge with percentage readout next to a slanted frame filled by a ' +
    'growing parallelogram wedge. Used for boost / thrust / power-up progress.';
end;

class function TSlantLoaderWidget.UnitFile: string;
begin
  Result := 'SlantLoader\uslantloader.pas';
end;

function TSlantLoaderWidget.Progress: single;
begin
  if FAuto >= 1 then
    Result := Frac(StartAt + T * FSpeed)
  else
    Result := FManual / 100;
end;

procedure TSlantLoaderWidget.DrawStatic;
begin
  Disc(GX, AY, 30, Navy(200));
  Arc(GX, AY, 26, 0, 360, 7, Steel(120));
  // slanted frame
  PolyLine([68, AY + 22, 100, AY - 16, 180, AY - 16, 190, AY - 24, 270, AY - 24], 1, Ice(180));
  PolyLine([68, AY + 22, 270, AY + 22], 1, Ice(180));
  Txt(270, AY + 31, 'LOADING...', 7, White(220), taRightJustify);
end;

procedure TSlantLoaderWidget.DrawDynamic;
var
  p, x2, s: single;
begin
  p := Progress;
  s := FSlant;
  Arc(GX, AY, 26, -90, -90 + 360 * p, 7, Ice);
  Arc(GX, AY, 26, -90 + 360 * p - 6, -90 + 360 * p, 7, White);
  TxtCached(GX, AY, Format('%d%%', [Round(p * 100)]), 9, taCenter);
  x2 := WedgeL + WedgeW * p;
  FillPoly([WedgeL, AY + 16, WedgeL + s, AY - 10, x2 + s, AY - 10, x2, AY + 16], Steel(170));
  FillPoly([WedgeL, AY + 16, WedgeL + s, AY - 10, WedgeL + 70 * p, AY - 10, WedgeL + 46 * p, AY + 16], Steel(220));
  Line(x2, AY + 16, x2 + s, AY - 10, 2, White);
end;

procedure TSlantLoaderWidget.DefineDirty;
begin
  AddDirty(GX - 30, AY - 30, GX + 30, AY + 30);
  AddDirty(WedgeL - 1, AY - 11, WedgeL + WedgeW + 31, AY + 17);
end;

procedure TSlantLoaderWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 300 x 80, centre line AY = 40. Gauge centre GX = 41, wedge from x = 80.');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Gauge body      disc r30 Navy a200');
  L.Add('  Gauge track     full ring arc r26 w7 Steel a120');
  L.Add('  Slanted frame   polyline w1 Ice a180: (68,AY+22) (100,AY-16) (180,AY-16)');
  L.Add('                  (190,AY-24) (270,AY-24) + base line to x = 270');
  L.Add('  Label           "LOADING..." size 7 right-aligned at (270, AY+31), under the frame');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic), p = progress 0..1');
  L.Add('  Gauge progress  arc r26 w7 Ice over 360 p + 6 deg White head');
  L.Add('  Readout         "NN%" size 9 centred (cached text bitmaps)');
  L.Add('  Wedge           parallelogram x 80..80+180p, 26 high, top shifted by Slant,');
  L.Add('                  Steel a170, darker inner part Steel a220, leading edge w2 White');
  L.Add('');
  L.Add('DATA');
  L.Add('  Auto progress = 1: p = frac(0.75 + t * Cycle speed)');
  L.Add('  Auto progress = 0: p = Progress % / 100');
  L.Add('');
  L.Add('DIRTY RECTS       gauge, wedge area (+ 24 glow margin)');
end;

procedure TSlantLoaderWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Progress            %.1f %%  (%s)', [Progress * 100, BoolToStr(FAuto >= 1, 'auto', 'manual')]));
  L.Add(Format('Wedge leading edge  x = %.1f', [WedgeL + WedgeW * Progress]));
end;

end.
