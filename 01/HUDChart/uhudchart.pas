unit UHUDChart;

{ HUD Chart - data charts in the Sci-Fi HUD style.

  Screen: 4 KPI tiles (total + first three series: value, change vs the
  previous row, sparkline), a multi-series line chart, a donut of each
  series' share and a column chart of the total per row.

  Chart rules followed (dataviz method):
  - categorical colors in fixed slot order, validated on the HUD plot surface
    #162d4a (validate_palette.js --mode dark): series i always = slot i,
    max 6 series (CSV tail folds into "Other");
  - one y axis, clean ticks (1/2/2.5/5 x 10^n), hairline recessive grid;
  - 2 px lines, end dots r 4 px with a 2 px surface ring, columns <= 24 px
    with a 4 px rounded data end, 2 px surface gap between donut segments;
  - legend for >= 2 series + sparing direct labels (line ends, max / last
    column); text never in series colors; status colors (with a ▲/▼ shape)
    only for "up / down vs previous";
  - hover crosshair + tooltip on every chart; the data table is in the
    Live tab of the info panel.

  Data: built-in sample, Open CSV (toolbar or --csv file), or Live data
  (random walk appended every "Live interval s"). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  BGRABitmap, BGRABitmapTypes, HUDCore, HUDHost, UChartData;

type

  { TChartBase - shared look, reveal animation, hover and tooltip }

  TChartBase = class(THUDWidget)
  protected
    FData: TChartData;
    FRevealDur: single;
    FSeenSet: integer;
    FRevealT0: single;
    FHoverOn: boolean;
    FHX, FHY: single;
    function Reveal: single;
    function PX(n: single): single;   // screen pixels -> design units
    procedure Panel(AW, AH: single; const ATitle, ASub: string);
    procedure Dot(cx, cy, rpx: single; c: TBGRAPixel);
    procedure Hairline(x1, y1, x2, y2: single; c: TBGRAPixel; Behind: boolean = False);
    procedure RoundTopBar(x0, yBase, bw, h: single; c: TBGRAPixel);
    procedure Swatch(ax, ay, size: single; c: TBGRAPixel);
    procedure Tooltip(ax, ay: single; const ATitle: string; const ANames, AValues: array of string;
      const AColors: array of TBGRAPixel);
  public
    procedure SetHover(AOn: boolean; AX, AY: single);
    class function UnitFile: string; override;
  end;

  { TKpiTileWidget }

  TKpiTileWidget = class(TChartBase)
  private
    FSeries: integer;   // -1 = total
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  public
    constructor CreateFor(ASeries: integer);
    class function UIName: string; override;
    class function UIDescription: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  end;

  { TLineChartWidget }

  TLineChartWidget = class(TChartBase)
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  end;

  { TDonutWidget }

  TDonutWidget = class(TChartBase)
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  end;

  { TBarChartWidget }

  TBarChartWidget = class(TChartBase)
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  end;

  { THUDChartWidget - the chart screen }

  THUDChartWidget = class(THUDComposite)
  private
    FData: TChartData;
    FLive, FLiveInterval, FRevealDur: single;
    FLastLive: single;
    FSeenSet: integer;
  protected
    procedure DrawDynamic; override;
  public
    constructor Create; override;
    destructor Destroy; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
    procedure HoverAt(px, py: integer);
    procedure HoverOff;
    property Data: TChartData read FData;
  end;

function SeriesColor(i: integer): TBGRAPixel;

implementation

const
  // categorical slots (dark steps), validated on PlotSurface #162d4a:
  // lightness band, chroma floor, CVD adjacent dE >= 8.4, normal-vision >= 19.3
  SeriesHex: array[0..MaxSeries - 1] of string =
    ('#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#008300');

function SeriesColor(i: integer): TBGRAPixel;
begin
  Result := StrToBGRA(SeriesHex[EnsureRange(i, 0, High(SeriesHex))]);
end;

function PlotSurface: TBGRAPixel; begin Result := BGRA(22, 45, 74); end;      // #162d4a
function GridInk: TBGRAPixel;     begin Result := BGRA(42, 68, 100); end;     // hairline
function BaseInk: TBGRAPixel;     begin Result := BGRA(86, 114, 150); end;    // baseline
function TextPrimary: TBGRAPixel; begin Result := BGRA(236, 247, 255); end;
function TextSecondary: TBGRAPixel; begin Result := BGRA(190, 205, 222); end;
function TextMuted: TBGRAPixel;   begin Result := BGRA(138, 158, 184); end;
function StatusGood: TBGRAPixel;  begin Result := StrToBGRA('#0ca30c'); end;
function StatusCritical: TBGRAPixel; begin Result := StrToBGRA('#d03b3b'); end;
function TotalInk: TBGRAPixel;    begin Result := Ice; end;   // "Total" is not a series slot

function EaseOut(v: single): single;
begin
  v := EnsureRange(v, 0, 1);
  Result := 1 - (1 - v) * (1 - v) * (1 - v);
end;

{ ---------- TChartBase ---------- }

class function TChartBase.UnitFile: string;
begin
  Result := 'HUDChart\uhudchart.pas';
end;

function TChartBase.Reveal: single;
begin
  // replay the draw-in animation whenever a new dataset arrives
  if FData.DataSetVersion <> FSeenSet then
  begin
    // the very first dataset starts at t = 0 (program start)
    if FSeenSet = 0 then FRevealT0 := 0 else FRevealT0 := T;
    FSeenSet := FData.DataSetVersion;
  end;
  if FRevealDur <= 0 then Exit(1);
  Result := EaseOut((T - FRevealT0) / FRevealDur);
end;

function TChartBase.PX(n: single): single;
begin
  if K > 0 then Result := n / K else Result := n;
end;

procedure TChartBase.SetHover(AOn: boolean; AX, AY: single);
begin
  FHoverOn := AOn;
  FHX := AX;
  FHY := AY;
end;

procedure TChartBase.Panel(AW, AH: single; const ATitle, ASub: string);
begin
  // HUD frame (Data Frames style) whose fill is the plot surface
  FillPoly([0, 10, 10, 0, AW * 0.62, 0, AW * 0.62 + 10, 10, AW, 10, AW, AH - 10, AW - 10, AH, 0, AH],
    PlotSurface);
  Polygon([0, 10, 10, 0, AW * 0.62, 0, AW * 0.62 + 10, 10, AW, 10, AW, AH - 10, AW - 10, AH, 0, AH],
    1.2, Ice(170));
  Line(AW, 24, AW, 60, 2.5, White(220));
  if ATitle <> '' then Txt(14, 16, ATitle, 8, TextPrimary);
  if ASub <> '' then Txt(AW - 14, 23, ASub, 6.5, TextMuted, taRightJustify);
end;

procedure TChartBase.Dot(cx, cy, rpx: single; c: TBGRAPixel);
begin
  // filled marker with a 2 px surface ring, on the stroke layer so it
  // occludes the lines below it
  FLayer.FillEllipseAntialias(X(cx), Y(cy), (rpx + 2), (rpx + 2), PlotSurface);
  FLayer.FillEllipseAntialias(X(cx), Y(cy), rpx, rpx, c);
end;

procedure TChartBase.Hairline(x1, y1, x2, y2: single; c: TBGRAPixel; Behind: boolean);
begin
  // Behind = grid / baseline on the fill layer, under every data mark
  if Behind then
    FFill.DrawLineAntialias(X(x1), Y(y1), X(x2), Y(y2), c, 1)
  else
    FLayer.DrawLineAntialias(X(x1), Y(y1), X(x2), Y(y2), c, 1);
end;

procedure TChartBase.RoundTopBar(x0, yBase, bw, h: single; c: TBGRAPixel);
var
  rr: single;
  P: ArrayOfTPointF;
begin
  // square at the baseline, 4 px rounded data end
  if h < PX(0.5) then Exit;
  rr := Min(Min(PX(4), bw / 2), h);
  P := ArcPts(x0 + rr, yBase - h + rr, rr, 180, 270);
  P := Concat(P, ArcPts(x0 + bw - rr, yBase - h + rr, rr, 270, 360));
  SetLength(P, Length(P) + 2);
  P[High(P) - 1] := Pt(x0 + bw, yBase);
  P[High(P)] := Pt(x0, yBase);
  // fill layer: large data blocks stay crisp (no bloom)
  FFill.FillPolyAntialias(P, c);
end;

procedure TChartBase.Swatch(ax, ay, size: single; c: TBGRAPixel);
begin
  FLayer.FillRectAntialias(X(ax), Y(ay - size / 2), X(ax + size), Y(ay + size / 2), c);
end;

procedure TChartBase.Tooltip(ax, ay: single; const ATitle: string; const ANames, AValues: array of string;
  const AColors: array of TBGRAPixel);
var
  bw, bh, x0, y0: single;
  i: integer;
begin
  bw := 176;
  bh := 26 + 16 * Length(ANames);
  x0 := ax + 16;
  if x0 + bw > DesignWidth - 6 then x0 := ax - 16 - bw;
  y0 := EnsureRange(ay - bh / 2, 6, DesignHeight - 6 - bh);
  FLayer.FillRoundRectAntialias(X(x0), Y(y0), X(x0 + bw), Y(y0 + bh), 4, 4, BGRA(10, 24, 42, 245));
  FLayer.RoundRectAntialias(X(x0), Y(y0), X(x0 + bw), Y(y0 + bh), 4, 4, Ice(170), 1);
  TxtCached(x0 + 10, y0 + 12, ATitle, 8, taLeftJustify, TextPrimary);
  for i := 0 to High(ANames) do
  begin
    if i <= High(AColors) then Swatch(x0 + 10, y0 + 30 + i * 16, 8, AColors[i]);
    TxtCached(x0 + 24, y0 + 30 + i * 16, ANames[i], 7.5, taLeftJustify, TextSecondary);
    TxtCached(x0 + bw - 10, y0 + 30 + i * 16, AValues[i], 7.5, taRightJustify, TextPrimary);
  end;
end;

{ ---------- TKpiTileWidget ---------- }

const
  KW = 280;
  KH = 110;

constructor TKpiTileWidget.CreateFor(ASeries: integer);
begin
  Create;
  FSeries := ASeries;
  SetView(KW, KH);
end;

class function TKpiTileWidget.UIName: string;
begin
  Result := 'KPI Tile';
end;

class function TKpiTileWidget.UIDescription: string;
begin
  Result := 'Stat tile: latest value, change vs the previous row (status colour + ▲/▼ shape) and a sparkline.';
end;

procedure TKpiTileWidget.DrawStatic;
begin
  Panel(KW, KH, '', '');
end;

procedure TKpiTileWidget.DrawDynamic;
var
  rv, cur, prev, pct, lo, hi, sx, sy: single;
  n, r: integer;
  name, delta: string;
  acc: TBGRAPixel;
  P: ArrayOfTPointF;

  function Val(row: integer): single;
  begin
    if FSeries < 0 then Result := FData.RowTotal(row) else Result := FData.Values[FSeries][row];
  end;

begin
  rv := Reveal;
  n := FData.RowCount;
  if (FSeries >= FData.SeriesCount) or (n = 0) then
  begin
    TxtCached(18, 24, 'NO SERIES', 8, taLeftJustify, TextMuted);
    Exit;
  end;
  if FSeries < 0 then
  begin
    name := 'Total';
    acc := TotalInk;
  end
  else
  begin
    name := FData.SeriesNames[FSeries];
    acc := SeriesColor(FSeries);
  end;
  // identity: a swatch beside the (ink-coloured) label
  Swatch(16, 22, 9, acc);
  TxtCached(31, 22, name, 8, taLeftJustify, TextSecondary);
  cur := Val(n - 1);
  TxtCached(16, 58, FmtCompact(cur * rv), 24, taLeftJustify, TextPrimary);
  if n >= 2 then
  begin
    prev := Val(n - 2);
    if prev > 0 then
    begin
      pct := (cur - prev) / prev * 100;
      // status colour carried by a shape, the text stays ink
      if pct >= 0 then
        FillPoly([17, 96, 25, 96, 21, 89], StatusGood)
      else
        FillPoly([17, 89, 25, 89, 21, 96], StatusCritical);
      if pct >= 0 then delta := '+' else delta := '';
      delta := delta + Format('%.1f%% vs %s', [pct, FData.Labels[n - 2]]);
      TxtCached(30, 93, delta, 7, taLeftJustify, TextSecondary);
    end;
  end;
  // sparkline: de-emphasis line, current point in the accent colour
  lo := MaxSingle; hi := -MaxSingle;
  for r := 0 to n - 1 do
  begin
    lo := Min(lo, Val(r));
    hi := Max(hi, Val(r));
  end;
  if hi <= lo then hi := lo + 1;
  SetLength(P, 0);
  for r := 0 to Round((n - 1) * rv) do
  begin
    sx := 160 + 100 * r / Max(1, n - 1);
    sy := 84 - 44 * (Val(r) - lo) / (hi - lo);
    SetLength(P, Length(P) + 1);
    P[High(P)] := Pt(sx, sy);
  end;
  if Length(P) >= 2 then
    FLayer.DrawPolyLineAntialias(P, Ice(150), 1.5);
  if rv >= 1 then
    Dot(260, 84 - 44 * (cur - lo) / (hi - lo), 3.5, acc);
end;

procedure TKpiTileWidget.DefineDirty;
begin
  AddDirty(6, 6, KW - 6, KH - 6);
end;

procedure TKpiTileWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %d x %d. Series %d (-1 = total of all series).', [KW, KH, FSeries]));
  L.Add('  Label     swatch (series colour) + name in secondary ink');
  L.Add('  Value     latest row, compact format (1,284 / 12.9K / 4.2M), size 24, counts up');
  L.Add('  Delta     change vs the previous row: ▲ status-good / ▼ status-critical shape +');
  L.Add('            text in secondary ink ("+4.2% vs NOV")');
  L.Add('  Sparkline all rows, Ice line 1.5 px, last point = accent dot with surface ring');
end;

{ ---------- TLineChartWidget ---------- }

const
  LW = 770;
  LH = 335;
  LPL = 64;      // plot area
  LPR = 680;
  LPT = 74;
  LPB = 290;

constructor TLineChartWidget.Create;
begin
  inherited Create;
  SetView(LW, LH);
end;

class function TLineChartWidget.UIName: string;
begin
  Result := 'Line Chart';
end;

class function TLineChartWidget.UIDescription: string;
begin
  Result := 'Trend of every series over the rows: 2 px lines, end dots and end labels, legend, ' +
    'hover crosshair with a tooltip of all values at that row.';
end;

procedure TLineChartWidget.DrawStatic;
begin
  Panel(LW, LH, 'TREND BY SERIES', UpperCase(FData.Title));
end;

procedure TLineChartWidget.DrawDynamic;
var
  n, s, r, i, idx, labelStep, full: integer;
  vmax, v, rv, xs, frac_, yy, lx: single;
  stepV: double;
  P: ArrayOfTPointF;
  ends: array of single;
  order: array of integer;
  canLabel: boolean;
  names, vals: array of string;
  cols: array of TBGRAPixel;

  function XAt(row: integer): single;
  begin
    if n <= 1 then Result := (LPL + LPR) / 2 else Result := LPL + (LPR - LPL) * row / (n - 1);
  end;

  function YAt(val: single): single;
  begin
    Result := LPB - (LPB - LPT) * val / vmax;
  end;

begin
  n := FData.RowCount;
  if (n = 0) or (FData.SeriesCount = 0) then Exit;
  rv := Reveal;
  vmax := NiceMax(FData.MaxValue, stepV);
  FLayer.JoinStyle := pjsRound;

  // grid + y ticks (hairline, recessive), baseline
  v := stepV;
  while v <= vmax + stepV / 2 do
  begin
    Hairline(LPL, YAt(v), LPR, YAt(v), GridInk, True);
    TxtCached(LPL - 8, YAt(v), FmtCompact(v), 7, taRightJustify, TextMuted);
    v += stepV;
  end;
  Hairline(LPL, LPB, LPR, LPB, BaseInk, True);
  TxtCached(LPL - 8, LPB, '0', 7, taRightJustify, TextMuted);
  // x labels, thinned to ~12
  labelStep := Max(1, Ceil(n / 12));
  for r := 0 to n - 1 do
    if r mod labelStep = 0 then
      TxtCached(XAt(r), LPB + 13, FData.Labels[r], 7, taCenter, TextMuted);

  // series lines, drawn in from left to right
  xs := rv * (n - 1);
  full := Floor(xs);
  frac_ := xs - full;
  for s := 0 to FData.SeriesCount - 1 do
  begin
    SetLength(P, 0);
    for r := 0 to Min(full, n - 1) do
    begin
      SetLength(P, Length(P) + 1);
      P[High(P)] := Pt(XAt(r), YAt(FData.Values[s][r]));
    end;
    if (full < n - 1) and (frac_ > 0) then
    begin
      SetLength(P, Length(P) + 1);
      P[High(P)] := Pt(XAt(full) + (XAt(full + 1) - XAt(full)) * frac_,
        YAt(FData.Values[s][full] + (FData.Values[s][full + 1] - FData.Values[s][full]) * frac_));
    end;
    if Length(P) >= 2 then
      FLayer.DrawPolyLineAntialias(P, SeriesColor(s), 2);
  end;

  if rv >= 1 then
  begin
    // end dots
    for s := 0 to FData.SeriesCount - 1 do
      Dot(XAt(n - 1), YAt(FData.Values[s][n - 1]), 4, SeriesColor(s));
    // direct end labels only when <= 4 series and they do not collide
    canLabel := FData.SeriesCount <= 4;
    if canLabel then
    begin
      SetLength(ends, FData.SeriesCount);
      SetLength(order, FData.SeriesCount);
      for s := 0 to FData.SeriesCount - 1 do
      begin
        ends[s] := YAt(FData.Values[s][n - 1]);
        order[s] := s;
      end;
      for i := 0 to High(order) do
        for s := i + 1 to High(order) do
          if ends[order[s]] < ends[order[i]] then
          begin
            r := order[i]; order[i] := order[s]; order[s] := r;
          end;
      for i := 1 to High(order) do
        if ends[order[i]] - ends[order[i - 1]] < 14 then canLabel := False;
    end;
    if canLabel then
      for s := 0 to FData.SeriesCount - 1 do
        TxtCached(LPR + 12, ends[s], FData.SeriesNames[s], 7.5, taLeftJustify, TextSecondary);
  end;

  // legend (always for >= 2 series)
  if FData.SeriesCount >= 2 then
  begin
    lx := LPL;
    for s := 0 to FData.SeriesCount - 1 do
    begin
      FLayer.DrawLineAntialias(X(lx), Y(46), X(lx + 16), Y(46), SeriesColor(s), 2);
      TxtCached(lx + 21, 46, FData.SeriesNames[s], 7.5, taLeftJustify, TextSecondary);
      lx += 34 + Length(FData.SeriesNames[s]) * 6;
    end;
  end;

  // hover: crosshair at the nearest row + tooltip with every series
  if FHoverOn and (FHX >= LPL - 12) and (FHX <= LPR + 12) and (FHY >= LPT - 30) and (FHY <= LPB + 20) then
  begin
    if n <= 1 then idx := 0 else idx := EnsureRange(Round((FHX - LPL) / ((LPR - LPL) / (n - 1))), 0, n - 1);
    Hairline(XAt(idx), LPT - 6, XAt(idx), LPB, Ice(150));
    SetLength(names, FData.SeriesCount);
    SetLength(vals, FData.SeriesCount);
    SetLength(cols, FData.SeriesCount);
    for s := 0 to FData.SeriesCount - 1 do
    begin
      yy := YAt(FData.Values[s][idx]);
      Dot(XAt(idx), yy, 4, SeriesColor(s));
      names[s] := FData.SeriesNames[s];
      vals[s] := FmtNum(FData.Values[s][idx]);
      cols[s] := SeriesColor(s);
    end;
    Tooltip(XAt(idx), FHY, FData.Labels[idx], names, vals, cols);
  end;
end;

procedure TLineChartWidget.DefineDirty;
begin
  AddDirty(6, 30, LW - 6, LH - 8);
end;

procedure TLineChartWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %d x %d, plot (%d,%d)-(%d,%d).', [LW, LH, LPL, LPT, LPR, LPB]));
  L.Add('  Y axis    one scale 0..nice max (ticks 1/2/2.5/5 x 10^n), hairline grid, muted labels');
  L.Add('  X axis    row labels, thinned to about 12');
  L.Add('  Lines     2 px, round joins, series slot colours, drawn in left to right');
  L.Add('  End dots  r 4 px + 2 px surface ring; end labels (name) when <= 4 series and');
  L.Add('            no two ends are closer than 14 units - otherwise legend only');
  L.Add('  Legend    line keys + names above the plot (>= 2 series)');
  L.Add('  Hover     vertical hairline at the nearest row, ringed dots, tooltip');
end;

{ ---------- TDonutWidget ---------- }

const
  DW = 400;
  DH = 335;
  DCX = 120;
  DCY = 185;
  DR1 = 66;
  DR2 = 98;

constructor TDonutWidget.Create;
begin
  inherited Create;
  SetView(DW, DH);
end;

class function TDonutWidget.UIName: string;
begin
  Result := 'Donut Chart';
end;

class function TDonutWidget.UIDescription: string;
begin
  Result := 'Share of each series in the grand total (part-to-whole at a glance), total in the centre, ' +
    'legend with percentages, hover lifts a segment.';
end;

procedure TDonutWidget.DrawStatic;
begin
  Panel(DW, DH, 'SHARE BY SERIES', '');
  Ring(DCX, DCY, DR2 + 10, 1, Ice(90));
  Ticks(DCX, DCY, DR2 + 12, DR2 + 16, 72, 0, 360, 0.8, Ice(110));
end;

procedure TDonutWidget.DrawDynamic;
var
  total, cum, share, a0, a1, mid, gap, sweep, rv, d, ang, off: single;
  s, hov: integer;
  cx, cy: single;
begin
  total := FData.GrandTotal;
  if total <= 0 then Exit;
  rv := Reveal;
  sweep := 360 * rv;
  gap := RadToDeg(PX(2) / ((DR1 + DR2) / 2));   // 2 px surface gap
  // hovered segment
  hov := -1;
  if FHoverOn then
  begin
    d := Hypot(FHX - DCX, FHY - DCY);
    if (d >= DR1 - 6) and (d <= DR2 + 10) then
    begin
      ang := NormDeg(RadToDeg(ArcTan2(FHY - DCY, FHX - DCX)) + 90);  // 0 = 12 o'clock
      cum := 0;
      for s := 0 to FData.SeriesCount - 1 do
      begin
        share := FData.SeriesTotal(s) / total;
        if (ang >= cum * 360) and (ang < (cum + share) * 360) then hov := s;
        cum += share;
      end;
    end;
  end;
  cum := 0;
  for s := 0 to FData.SeriesCount - 1 do
  begin
    share := FData.SeriesTotal(s) / total;
    a0 := -90 + cum * 360;
    a1 := Min(a0 + share * 360, -90 + sweep);
    cum += share;
    if a1 - a0 <= gap then Continue;
    mid := DegToRad((a0 + a1) / 2);
    if s = hov then off := 7 else off := 0;
    cx := DCX + off * Cos(mid);
    cy := DCY + off * Sin(mid);
    Band(cx, cy, DR1, DR2, a0 + gap / 2, a1 - gap / 2, SeriesColor(s));
  end;
  // centre: total
  TxtCached(DCX, DCY - 6, FmtCompact(total * rv), 20, taCenter, TextPrimary);
  TxtCached(DCX, DCY + 18, 'TOTAL', 7, taCenter, TextMuted);
  // legend with shares
  for s := 0 to FData.SeriesCount - 1 do
  begin
    Swatch(244, 96 + s * 24, 9, SeriesColor(s));
    TxtCached(259, 96 + s * 24, FData.SeriesNames[s], 7.5, taLeftJustify, TextSecondary);
    TxtCached(386, 96 + s * 24, Format('%.1f%%', [100 * FData.SeriesTotal(s) / total]), 7.5,
      taRightJustify, TextPrimary);
  end;
  if hov >= 0 then
    Tooltip(FHX, FHY, FData.SeriesNames[hov], ['Total', 'Share'],
      [FmtNum(FData.SeriesTotal(hov)), Format('%.1f%%', [100 * FData.SeriesTotal(hov) / total])],
      [SeriesColor(hov)]);
end;

procedure TDonutWidget.DefineDirty;
begin
  AddDirty(6, 30, DW - 6, DH - 8);
end;

procedure TDonutWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %d x %d, centre (%d,%d), ring r %d..%d.', [DW, DH, DCX, DCY, DR1, DR2]));
  L.Add('  Segments  one per series (slot colour), clockwise from 12 o''clock, 2 px gap');
  L.Add('  Centre    grand total (compact) + "TOTAL"');
  L.Add('  Legend    swatch + name (secondary ink) + share % (primary ink)');
  L.Add('  Hover     segment lifts 7 units outwards + tooltip (total, share)');
  L.Add('  Note      part-to-whole at a glance only; compare close values in the line chart');
end;

{ ---------- TBarChartWidget ---------- }

const
  BW_ = 1180;
  BH_ = 262;
  BPL = 70;
  BPR = 1150;
  BPT = 56;
  BPB = 214;

constructor TBarChartWidget.Create;
begin
  inherited Create;
  SetView(BW_, BH_);
end;

class function TBarChartWidget.UIName: string;
begin
  Result := 'Column Chart';
end;

class function TBarChartWidget.UIDescription: string;
begin
  Result := 'Total of all series per row: columns <= 24 px with a rounded data end, value labels on the ' +
    'maximum and the last column, hover tooltip with the per-series breakdown.';
end;

procedure TBarChartWidget.DrawStatic;
begin
  Panel(BW_, BH_, 'TOTAL PER ' + UpperCase(FData.XTitle), '');
end;

procedure TBarChartWidget.DrawDynamic;
var
  n, r, s, hov, imax, labelStep: integer;
  vmax, v, slot, bw, cx, h, rv, tot, best: single;
  stepV: double;
  c: TBGRAPixel;
  names, vals: array of string;
  cols: array of TBGRAPixel;
begin
  n := FData.RowCount;
  if n = 0 then Exit;
  rv := Reveal;
  vmax := NiceMax(FData.MaxRowTotal, stepV);
  v := stepV;
  while v <= vmax + stepV / 2 do
  begin
    Hairline(BPL, BPB - (BPB - BPT) * v / vmax, BPR, BPB - (BPB - BPT) * v / vmax, GridInk, True);
    TxtCached(BPL - 8, BPB - (BPB - BPT) * v / vmax, FmtCompact(v), 7, taRightJustify, TextMuted);
    v += stepV;
  end;
  TxtCached(BPL - 8, BPB, '0', 7, taRightJustify, TextMuted);
  slot := (BPR - BPL) / n;
  bw := Min(slot * 0.62, PX(24));
  hov := -1;
  if FHoverOn and (FHX >= BPL) and (FHX < BPR) and (FHY >= BPT - 20) and (FHY <= BPB + 18) then
    hov := EnsureRange(Floor((FHX - BPL) / slot), 0, n - 1);
  imax := 0;
  best := -1;
  for r := 0 to n - 1 do
    if FData.RowTotal(r) > best then
    begin
      best := FData.RowTotal(r);
      imax := r;
    end;
  labelStep := Max(1, Ceil(n / 16));
  for r := 0 to n - 1 do
  begin
    tot := FData.RowTotal(r);
    cx := BPL + slot * (r + 0.5);
    h := (BPB - BPT) * tot / vmax * rv;
    if (hov >= 0) and (r <> hov) then c := Ice(110) else c := TotalInk;
    RoundTopBar(cx - bw / 2, BPB, bw, h, c);
    if r mod labelStep = 0 then
      TxtCached(cx, BPB + 13, FData.Labels[r], 7, taCenter, TextMuted);
    // selective value labels: the maximum and the latest column
    if (rv >= 1) and ((r = imax) or (r = n - 1)) then
      TxtCached(cx, BPB - h - 9, FmtCompact(tot), 7.5, taCenter, TextPrimary);
  end;
  Hairline(BPL, BPB, BPR, BPB, BaseInk, True);
  if hov >= 0 then
  begin
    SetLength(names, FData.SeriesCount + 1);
    SetLength(vals, FData.SeriesCount + 1);
    SetLength(cols, FData.SeriesCount + 1);
    for s := 0 to FData.SeriesCount - 1 do
    begin
      names[s] := FData.SeriesNames[s];
      vals[s] := FmtNum(FData.Values[s][hov]);
      cols[s] := SeriesColor(s);
    end;
    names[FData.SeriesCount] := 'Total';
    vals[FData.SeriesCount] := FmtNum(FData.RowTotal(hov));
    cols[FData.SeriesCount] := TotalInk;
    Tooltip(BPL + slot * (hov + 0.5), Max(FHY, BPT + 40), FData.Labels[hov], names, vals, cols);
  end;
end;

procedure TBarChartWidget.DefineDirty;
begin
  AddDirty(6, 30, BW_ - 6, BH_ - 8);
end;

procedure TBarChartWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %d x %d, plot (%d,%d)-(%d,%d).', [BW_, BH_, BPL, BPT, BPR, BPB]));
  L.Add('  Columns   total per row, Ice (the total is not a series slot), width');
  L.Add('            min(62% of the slot, 24 px), 4 px rounded data end, square baseline');
  L.Add('  Labels    value on the cap of the maximum and the latest column only');
  L.Add('  Hover     other columns dim, tooltip with every series + total');
end;

{ ---------- THUDChartWidget ---------- }

constructor THUDChartWidget.Create;
var
  i: integer;
  W: TChartBase;
begin
  inherited Create;
  SetView(1200, 750);
  SetParamByName('Max zoom', 2);
  SetParamByName('Glow intensity', 0.9);   // data first: a softer bloom than the kit
  FData := TChartData.Create;
  FLiveInterval := 1;
  FRevealDur := 0.9;
  AddParam('Live data', 'Data', '1 = append a random-walk row every "Live interval s" (keeps the last 24 rows).',
    FLive, 0, 1, 0, False);
  AddParam('Live interval s', 'Data', 'Seconds between live rows.', FLiveInterval, 0.1, 10, 1, False);
  AddParam('Reveal time s', 'Charts', 'Duration of the draw-in animation for a new dataset (0 = none).',
    FRevealDur, 0, 5, 1, False);

  W := TKpiTileWidget.CreateFor(-1);
  W.FData := FData;
  AddChild(W, 10, 8, 'KPI Total');
  for i := 0 to 2 do
  begin
    W := TKpiTileWidget.CreateFor(i);
    W.FData := FData;
    AddChild(W, 10 + (i + 1) * 297, 8, Format('KPI series %d', [i + 1]));
  end;
  W := TLineChartWidget.Create;
  W.FData := FData;
  AddChild(W, 10, 128, 'Line Chart');
  W := TDonutWidget.Create;
  W.FData := FData;
  AddChild(W, 790, 128, 'Donut Chart');
  W := TBarChartWidget.Create;
  W.FData := FData;
  AddChild(W, 10, 475, 'Column Chart');
  FSeenSet := FData.DataSetVersion;
end;

destructor THUDChartWidget.Destroy;
begin
  inherited Destroy;
  FData.Free;
end;

class function THUDChartWidget.UIName: string;
begin
  Result := 'HUD Chart';
end;

class function THUDChartWidget.UIDescription: string;
begin
  Result := 'Data charts in the HUD style: KPI tiles, line, donut and column charts with hover tooltips. ' +
    'Open a CSV from the toolbar or switch on Live data.';
end;

class function THUDChartWidget.UnitFile: string;
begin
  Result := 'HUDChart\uhudchart.pas';
end;

procedure THUDChartWidget.DrawDynamic;
var
  i: integer;
begin
  if (FLive >= 1) and (T - FLastLive >= FLiveInterval) then
  begin
    FData.AppendLive;
    FLastLive := T;
  end;
  // a new dataset changes titles (static); charts also replay the reveal
  if FData.DataSetVersion <> FSeenSet then
  begin
    FSeenSet := FData.DataSetVersion;
    for i := 0 to ChildCount - 1 do Children[i].InvalidateStatic;
  end;
  for i := 0 to ChildCount - 1 do
    TChartBase(Children[i]).FRevealDur := FRevealDur;
  inherited DrawDynamic;
end;

procedure THUDChartWidget.HoverAt(px, py: integer);
var
  i: integer;
  p, o: TPointF;
  C: THUDWidget;
begin
  p := PixelToDesign(px, py);
  for i := 0 to ChildCount - 1 do
  begin
    C := Children[i];
    o := ChildOrigin(i);
    TChartBase(C).SetHover(
      (p.x >= o.x) and (p.x < o.x + C.DesignWidth) and (p.y >= o.y) and (p.y < o.y + C.DesignHeight),
      p.x - o.x, p.y - o.y);
  end;
end;

procedure THUDChartWidget.HoverOff;
var
  i: integer;
begin
  for i := 0 to ChildCount - 1 do
    TChartBase(Children[i]).SetHover(False, 0, 0);
end;

procedure THUDChartWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('Canvas 1200 x 750 design units.');
  L.Add('');
  L.Add('LAYOUT');
  for i := 0 to ChildCount - 1 do
    L.Add(Format('  %-16s %-18s (%4.0f,%4.0f)  %4.0f x %3.0f', [ChildCaption(i), Children[i].ClassName,
      ChildOrigin(i).x, ChildOrigin(i).y, Children[i].DesignWidth, Children[i].DesignHeight]));
  L.Add('');
  L.Add('COLOUR SLOTS (fixed order, series i = slot i, validated on #162d4a dark)');
  for i := 0 to MaxSeries - 1 do
    L.Add(Format('  slot %d  %s', [i + 1, SeriesHex[i]]));
  L.Add('  Validator: lightness band, chroma floor, adjacent CVD dE 8.4, normal-vision');
  L.Add('  dE 19.3 all PASS; slot 6 (green) is under 3:1 on the surface -> legend,');
  L.Add('  labels and the data table (Live tab) carry identity.');
  L.Add('  Total = Ice (not a series slot). Up/down = status good/critical + shape.');
  L.Add('');
  L.Add('CSV FORMAT');
  L.Add('  Month,North,South,...      header: x title, series names');
  L.Add('  JAN,3200,2400,...          one row per category');
  L.Add('  Separator , ; or TAB (with ; the decimal comma is used).');
  L.Add('  More than 6 series: the tail is summed into "Other".');
  L.Add('');
  L.Add('INTERACTION   hover any chart for a tooltip; click a chart to inspect it.');
end;

procedure THUDChartWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add('Dataset             ' + FData.Title);
  L.Add(Format('Rows x series       %d x %d', [FData.RowCount, FData.SeriesCount]));
  L.Add(Format('Grand total         %s', [FmtNum(FData.GrandTotal)]));
  L.Add('');
  L.Add('DATA TABLE');
  FData.DescribeTable(L);
end;

{ ---------- toolbar and mouse ---------- }

type
  TChartController = class(TComponent)
  private
    FForm: THUDHostForm;
    function Chart: THUDChartWidget;
    procedure OpenClick(Sender: TObject);
    procedure SampleClick(Sender: TObject);
    procedure LiveClick(Sender: TObject);
    procedure Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Leave(Sender: TObject);
    procedure LoadFile(const AFileName: string);
  end;

function TChartController.Chart: THUDChartWidget;
begin
  Result := FForm.Widget as THUDChartWidget;
end;

procedure TChartController.LoadFile(const AFileName: string);
begin
  try
    Chart.Data.LoadCSV(AFileName);
    Chart.SetParamValue(Chart.ParamIndex('Live data'), 0);
    FForm.RefreshInfo;
    FForm.SetStatus(Format('Loaded %s: %d rows x %d series', [ExtractFileName(AFileName),
      Chart.Data.RowCount, Chart.Data.SeriesCount]));
  except
    on E: Exception do FForm.SetStatus('CSV not loaded: ' + E.Message);
  end;
end;

procedure TChartController.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(nil);
  try
    D.Filter := 'CSV files (*.csv;*.txt)|*.csv;*.txt|All files (*.*)|*.*';
    D.InitialDir := ExtractFilePath(Application.ExeName) + 'samples';
    if D.Execute then LoadFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TChartController.SampleClick(Sender: TObject);
begin
  Chart.Data.LoadSample;
  Chart.SetParamValue(Chart.ParamIndex('Live data'), 0);
  FForm.RefreshInfo;
  FForm.SetStatus('Sample data loaded');
end;

procedure TChartController.LiveClick(Sender: TObject);
var
  i: integer;
begin
  i := Chart.ParamIndex('Live data');
  Chart.SetParamValue(i, 1 - Chart.Params[i].Value^);
  FForm.RefreshInfo;
  FForm.SetStatus(BoolToStr(Chart.Params[i].Value^ >= 1, 'Live data ON', 'Live data OFF'));
end;

procedure TChartController.Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  Chart.HoverAt(X, Y);
end;

procedure TChartController.Leave(Sender: TObject);
begin
  Chart.HoverOff;
end;

procedure SetupChart(AForm: THUDHostForm);
var
  C: TChartController;
  Bar: TFlowPanel;

  procedure Btn(const ACaption: string; AClick: TNotifyEvent);
  var
    B: TButton;
  begin
    B := TButton.Create(AForm);
    B.Parent := Bar;
    B.Caption := ACaption;
    B.AutoSize := True;
    B.OnClick := AClick;
    B.BorderSpacing.Around := 2;
  end;

begin
  if not (AForm.Widget is THUDChartWidget) then Exit;
  C := TChartController.Create(AForm);
  C.FForm := AForm;
  Bar := TFlowPanel.Create(AForm);
  Bar.Parent := AForm;
  Bar.Align := alTop;
  Bar.AutoSize := True;
  Bar.BevelOuter := bvNone;
  Bar.BorderSpacing.Around := 2;
  Btn('Open CSV...', @C.OpenClick);
  Btn('Sample data', @C.SampleClick);
  Btn('Live data on/off', @C.LiveClick);
  AForm.View.OnMouseMove := @C.Move;
  AForm.View.OnMouseLeave := @C.Leave;
  AForm.SetStatus('Hover a chart for values   Click: inspect a chart   Space: pause   Esc: exit');
  // HUDChart.exe --csv file.csv : start with a CSV
  if (ParamCount >= 2) and (ParamStr(1) = '--csv') then
    C.LoadFile(ParamStr(2));
end;

initialization
  HostSetupProc := @SetupChart;

end.
