unit UBlockLoader;

{ Block Loader - tick-ring gauge with a percentage readout next to a row of
  rectangular blocks that light up with progress, with header and rules. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, HUDCore;

type

  { TBlockLoaderWidget }

  TBlockLoaderWidget = class(THUDWidget)
  private
    FAuto: single;
    FSpeed: single;
    FManual: single;
    FBlocks: single;     // number of blocks
    function Progress: single;
    function BlockPitch: single;
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
  GX = 43;
  BlocksL = 89;        // first block x
  BlocksW = 182;       // total width of the block row
  TickCount = 60;
  StartAt = 0.50;      // progress at t = 0 (as in the design: 50%)

constructor TBlockLoaderWidget.Create;
begin
  inherited Create;
  SetView(ViewW, ViewH);
  FAuto := 1;
  FSpeed := 0.07;
  FManual := 50;
  FBlocks := 16;
  AddParam('Auto progress', 'Data', '1 = progress cycles 0..100% automatically, 0 = use "Progress %".',
    FAuto, 0, 1, 0, False);
  AddParam('Progress %', 'Data', 'Progress shown when Auto progress = 0.',
    FManual, 0, 100, 1, False);
  AddParam('Cycle speed', 'Animation', 'Auto mode: full cycles per second.',
    FSpeed, 0, 2, 3, False);
  AddParam('Block count', 'Style', 'Number of blocks in the row (they share 182 units).',
    FBlocks, 4, 40, 0, True);
end;

class function TBlockLoaderWidget.UIName: string;
begin
  Result := 'Block Loader';
end;

class function TBlockLoaderWidget.UIDescription: string;
begin
  Result := 'Tick-ring gauge with percentage readout next to a row of blocks that light up with ' +
    'progress, with a LOADING header and underline rules. Used for staged / step progress.';
end;

class function TBlockLoaderWidget.UnitFile: string;
begin
  Result := 'BlockLoader\ublockloader.pas';
end;

function TBlockLoaderWidget.Progress: single;
begin
  if FAuto >= 1 then
    Result := Frac(StartAt + T * FSpeed)
  else
    Result := FManual / 100;
end;

function TBlockLoaderWidget.BlockPitch: single;
begin
  Result := BlocksW / FBlocks;
end;

procedure TBlockLoaderWidget.DrawStatic;
var
  i: integer;
  bx, bw: single;
begin
  Disc(GX, AY, 30, Navy(200));
  Ticks(GX, AY, 24, 30, TickCount, -90, 270, 0.8, Steel(200));
  Ring(GX, AY, 22, 1, Ice(150));
  Ring(GX, AY, 33, 1.5, Ice(180));
  Txt(BlocksL, AY - 18, 'LOADING...', 7, White(220));
  Line(140, AY - 18, 270, AY - 18, 1, Ice(150));
  bw := BlockPitch * 0.7;
  for i := 0 to Round(FBlocks) - 1 do
  begin
    bx := BlocksL + i * BlockPitch;
    FillPoly([bx, AY - 10, bx + bw, AY - 10, bx + bw, AY + 10, bx, AY + 10], Steel(130));
  end;
  Line(80, AY + 16, 270, AY + 16, 1.2, Ice(180));
  Line(100, AY + 21, 220, AY + 21, 2, White(200));
end;

procedure TBlockLoaderWidget.DrawDynamic;
var
  i, n: integer;
  p, bx, bw: single;
begin
  p := Progress;
  n := Round(FBlocks);
  Ticks(GX, AY, 24, 30, Round(TickCount * p), -90, -90 + 360 * p, 1, White);
  TxtCached(GX, AY, Format('%d%%', [Round(p * 100)]), 9, taCenter);
  bw := BlockPitch * 0.7;
  for i := 0 to Round(p * n) - 1 do
  begin
    bx := BlocksL + i * BlockPitch;
    FillPoly([bx, AY - 10, bx + bw, AY - 10, bx + bw, AY + 10, bx, AY + 10],
      White(Round(130 + 125 * i / n)));
  end;
end;

procedure TBlockLoaderWidget.DefineDirty;
begin
  AddDirty(GX - 31, AY - 31, GX + 31, AY + 31);
  AddDirty(BlocksL - 1, AY - 11, BlocksL + BlocksW + 1, AY + 11);
end;

procedure TBlockLoaderWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 300 x 80, centre line AY = 40. Gauge centre GX = 43, blocks 89..271.');
  L.Add('');
  L.Add('STATIC (DrawStatic)');
  L.Add('  Gauge body      disc r30 Navy a200');
  L.Add('  Gauge ticks     60 ticks r24..30 w0.8 Steel a200 (unlit)');
  L.Add('  Gauge rings     r22 w1 Ice a150, r33 w1.5 Ice a180');
  L.Add('  Header          "LOADING..." size 7 at (89, AY-18) + rule w1 Ice a150 x 140..270');
  L.Add('  Blocks          Block count blocks, 20 high, width 70% of pitch (182 / count),');
  L.Add('                  Steel a130 (unlit)');
  L.Add('  Rules           w1.2 Ice a180 x 80..270 at AY+16, w2 White a200 x 100..220 at AY+21');
  L.Add('');
  L.Add('DYNAMIC (DrawDynamic), p = progress 0..1');
  L.Add('  Lit ticks       round(60 p) ticks w1 White from 12 o''clock');
  L.Add('  Readout         "NN%" size 9 centred (cached text bitmaps)');
  L.Add('  Lit blocks      first round(p * count) blocks White, alpha 130..255 ramp');
  L.Add('');
  L.Add('DATA');
  L.Add('  Auto progress = 1: p = frac(0.50 + t * Cycle speed)');
  L.Add('  Auto progress = 0: p = Progress % / 100');
  L.Add('');
  L.Add('DIRTY RECTS       gauge, block row (+ 24 glow margin)');
end;

procedure TBlockLoaderWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Progress            %.1f %%  (%s)', [Progress * 100, BoolToStr(FAuto >= 1, 'auto', 'manual')]));
  L.Add(Format('Blocks lit          %d / %d', [Round(Progress * Round(FBlocks)), Round(FBlocks)]));
end;

end.
