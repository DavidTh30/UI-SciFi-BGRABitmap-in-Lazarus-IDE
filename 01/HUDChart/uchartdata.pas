unit UChartData;

{ Data model of HUD Chart: rows = categories (x axis, e.g. months),
  columns = series. Sources: built-in sample, CSV file, live random walk.

  CSV: first row = header (first cell = x-axis title, then series names),
  following rows = label, value, value, ...  Separator , ; or TAB is
  detected; decimal point '.' (or ',' when ';' separates). More than
  MaxSeries series: the tail is folded into "Other" (colors never cycle). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

const
  MaxSeries = 6;     // categorical slots used; the rest folds into "Other"
  MaxLiveRows = 24;

type

  { TChartData }

  TChartData = class
  private
    FLiveCount: integer;
  public
    Title: string;
    XTitle: string;
    Labels: TStringList;
    SeriesNames: TStringList;
    Values: array of array of double;   // [series][row]
    DataSetVersion: integer;            // new dataset -> charts replay the reveal
    ValueVersion: integer;              // any change
    constructor Create;
    destructor Destroy; override;
    function RowCount: integer;
    function SeriesCount: integer;
    function RowTotal(row: integer): double;
    function SeriesTotal(s: integer): double;
    function GrandTotal: double;
    function MaxRowTotal: double;
    function MaxValue: double;
    procedure LoadSample;
    procedure LoadCSV(const AFileName: string);
    procedure AppendLive;
    procedure DescribeTable(L: TStrings);
  end;

function FmtNum(v: double): string;       // 12,345
function FmtCompact(v: double): string;   // 1,284 / 12.9K / 4.2M
function NiceMax(v: double; out stepOut: double): double;

implementation

function FmtNum(v: double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.ThousandSeparator := ',';
  fs.DecimalSeparator := '.';
  if (Abs(v) < 10) and (Frac(v) <> 0) then
    Result := FormatFloat('0.0#', v, fs)
  else
    Result := FormatFloat('#,##0', v, fs);
end;

function FmtCompact(v: double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if Abs(v) >= 1e6 then Result := FormatFloat('0.0', v / 1e6, fs) + 'M'
  else if Abs(v) >= 1e4 then Result := FormatFloat('0.0', v / 1e3, fs) + 'K'
  else Result := FmtNum(v);
end;

function NiceMax(v: double; out stepOut: double): double;
var
  raw, mag, f: double;
begin
  // clean axis: 4-5 ticks of 1/2/2.5/5 x 10^n
  if v <= 0 then v := 1;
  raw := v / 4;
  mag := Power(10, Floor(Log10(raw)));
  f := raw / mag;
  if f <= 1 then f := 1
  else if f <= 2 then f := 2
  else if f <= 2.5 then f := 2.5
  else if f <= 5 then f := 5
  else f := 10;
  stepOut := f * mag;
  Result := Ceil(v / stepOut) * stepOut;
end;

{ TChartData }

constructor TChartData.Create;
begin
  inherited Create;
  Labels := TStringList.Create;
  SeriesNames := TStringList.Create;
  LoadSample;
end;

destructor TChartData.Destroy;
begin
  Labels.Free;
  SeriesNames.Free;
  inherited Destroy;
end;

function TChartData.RowCount: integer;
begin
  Result := Labels.Count;
end;

function TChartData.SeriesCount: integer;
begin
  Result := SeriesNames.Count;
end;

function TChartData.RowTotal(row: integer): double;
var
  s: integer;
begin
  Result := 0;
  for s := 0 to SeriesCount - 1 do Result += Values[s][row];
end;

function TChartData.SeriesTotal(s: integer): double;
var
  r: integer;
begin
  Result := 0;
  for r := 0 to RowCount - 1 do Result += Values[s][r];
end;

function TChartData.GrandTotal: double;
var
  s: integer;
begin
  Result := 0;
  for s := 0 to SeriesCount - 1 do Result += SeriesTotal(s);
end;

function TChartData.MaxRowTotal: double;
var
  r: integer;
begin
  Result := 0;
  for r := 0 to RowCount - 1 do Result := Max(Result, RowTotal(r));
end;

function TChartData.MaxValue: double;
var
  s, r: integer;
begin
  Result := 0;
  for s := 0 to SeriesCount - 1 do
    for r := 0 to RowCount - 1 do
      Result := Max(Result, Values[s][r]);
end;

procedure TChartData.LoadSample;
const
  Months: array[0..11] of string = ('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC');
  Names: array[0..3] of string = ('North', 'South', 'East', 'West');
  Base: array[0..3] of double = (3200, 2400, 1800, 1300);
  Growth: array[0..3] of double = (0.025, 0.04, 0.012, 0.06);
  Season: array[0..3] of double = (0.18, 0.10, 0.22, 0.08);
var
  s, r: integer;
begin
  Title := 'Sample: regional output';
  XTitle := 'Month';
  Labels.Clear;
  SeriesNames.Clear;
  for r := 0 to 11 do Labels.Add(Months[r]);
  SetLength(Values, 4);
  for s := 0 to 3 do
  begin
    SeriesNames.Add(Names[s]);
    SetLength(Values[s], 12);
    for r := 0 to 11 do
      // deterministic: trend + seasonality + a fixed wobble
      Values[s][r] := Round(Base[s] * Power(1 + Growth[s], r) *
        (1 + Season[s] * Sin((r - 2 + s) / 12 * 2 * Pi)) * (1 + 0.04 * Sin(r * 2.7 + s)));
  end;
  FLiveCount := 0;
  Inc(DataSetVersion);
  Inc(ValueVersion);
end;

procedure TChartData.LoadCSV(const AFileName: string);
var
  L, cells: TStringList;
  sep: char;
  i, s, r, nSeries, keep: integer;
  head: string;
  v: double;
  fs: TFormatSettings;
  raw: array of array of double;
  names: TStringList;
begin
  L := TStringList.Create;
  cells := TStringList.Create;
  names := TStringList.Create;
  try
    L.LoadFromFile(AFileName);
    while (L.Count > 0) and (Trim(L[L.Count - 1]) = '') do L.Delete(L.Count - 1);
    if L.Count < 2 then raise Exception.Create('CSV needs a header row and at least one data row');
    head := L[0];
    if Pos(#9, head) > 0 then sep := #9
    else if Pos(';', head) > 0 then sep := ';'
    else sep := ',';
    fs := DefaultFormatSettings;
    if sep = ';' then fs.DecimalSeparator := ',' else fs.DecimalSeparator := '.';
    cells.StrictDelimiter := True;
    cells.Delimiter := sep;
    cells.DelimitedText := head;
    if cells.Count < 2 then raise Exception.Create('CSV needs at least one value column');
    XTitle := Trim(cells[0]);
    nSeries := cells.Count - 1;
    for i := 1 to cells.Count - 1 do names.Add(Trim(cells[i]));
    SetLength(raw, nSeries);
    Labels.Clear;
    for r := 1 to L.Count - 1 do
    begin
      if Trim(L[r]) = '' then Continue;
      cells.DelimitedText := L[r];
      Labels.Add(Trim(cells[0]));
      for s := 0 to nSeries - 1 do
      begin
        SetLength(raw[s], Labels.Count);
        v := 0;
        if s + 1 < cells.Count then
          if not TryStrToFloat(Trim(cells[s + 1]), v, fs) then v := 0;
        raw[s][Labels.Count - 1] := Max(0, v);  // charts here show magnitudes
      end;
    end;
    // fold the tail into "Other" (never generate a 7th+ hue)
    SeriesNames.Clear;
    if nSeries > MaxSeries then keep := MaxSeries - 1 else keep := nSeries;
    SetLength(Values, Min(nSeries, MaxSeries));
    for s := 0 to keep - 1 do
    begin
      SeriesNames.Add(names[s]);
      Values[s] := Copy(raw[s]);
    end;
    if nSeries > MaxSeries then
    begin
      SeriesNames.Add('Other');
      SetLength(Values[keep], Labels.Count);
      for r := 0 to Labels.Count - 1 do
      begin
        Values[keep][r] := 0;
        for s := keep to nSeries - 1 do Values[keep][r] += raw[s][r];
      end;
    end;
    Title := ExtractFileName(AFileName);
    FLiveCount := 0;
    Inc(DataSetVersion);
    Inc(ValueVersion);
  finally
    names.Free;
    cells.Free;
    L.Free;
  end;
end;

procedure TChartData.AppendLive;
var
  s, r, n: integer;
  last: double;
begin
  // random walk from the last value, oldest row dropped past MaxLiveRows
  n := RowCount;
  if n = 0 then Exit;
  Inc(FLiveCount);
  Labels.Add(Format('T+%d', [FLiveCount]));
  for s := 0 to SeriesCount - 1 do
  begin
    last := Values[s][n - 1];
    SetLength(Values[s], n + 1);
    Values[s][n] := Max(0, Round(last * (1 + (Random - 0.48) * 0.16)));
  end;
  while RowCount > MaxLiveRows do
  begin
    Labels.Delete(0);
    for s := 0 to SeriesCount - 1 do
    begin
      for r := 0 to High(Values[s]) - 1 do Values[s][r] := Values[s][r + 1];
      SetLength(Values[s], Length(Values[s]) - 1);
    end;
  end;
  Inc(ValueVersion);
end;

procedure TChartData.DescribeTable(L: TStrings);
var
  s, r: integer;
  line: string;
begin
  line := Format('%-10s', [XTitle]);
  for s := 0 to SeriesCount - 1 do line += Format('%12s', [SeriesNames[s]]);
  L.Add(line + Format('%12s', ['Total']));
  for r := 0 to RowCount - 1 do
  begin
    line := Format('%-10s', [Labels[r]]);
    for s := 0 to SeriesCount - 1 do line += Format('%12s', [FmtNum(Values[s][r])]);
    L.Add(line + Format('%12s', [FmtNum(RowTotal(r))]));
  end;
end;

end.
