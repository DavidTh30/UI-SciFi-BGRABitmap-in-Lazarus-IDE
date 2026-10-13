unit UHUDClock;

{ HUD Clock - date & time in the Sci-Fi HUD style.

  Analog clock (smooth second hand, seconds arc), digital clock with date,
  day-of-year and ISO week, month calendar with today ringed, world clocks
  for cities without daylight saving (fixed UTC offsets, always correct) and
  four kit loaders showing how much of the day / week / month / year has
  passed. Everything follows the system clock; Pause freezes the animation
  only, not the time. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, DateUtils, BGRABitmap, BGRABitmapTypes, HUDCore,
  UChevronLoader, UPillLoader, UBlockLoader, USlantLoader;

type

  { TAnalogClockWidget }

  TAnalogClockWidget = class(THUDWidget)
  private
    FSmooth: single;
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
  end;

  { TDigitalClockWidget }

  TDigitalClockWidget = class(THUDWidget)
  private
    F24h: single;
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
  end;

  { TCalendarWidget }

  TCalendarWidget = class(THUDWidget)
  private
    FShownDay: TDateTime;     // static part is drawn for this date
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
  end;

  { TWorldClockWidget }

  TWorldClockWidget = class(THUDWidget)
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
  end;

  { THUDClockWidget }

  THUDClockWidget = class(THUDComposite)
  private
    FDay: TChevronLoaderWidget;
    FWeek: TSlantLoaderWidget;
    FMonth: TBlockLoaderWidget;
    FYear: TPillLoaderWidget;
  protected
    procedure DrawDynamic; override;
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
  end;

implementation

type
  TCityZone = record
    City: string;
    OffsetMin: integer;   // minutes from UTC (zones without daylight saving)
  end;

const
  Cities: array[0..6] of TCityZone = (
    (City: 'UTC';        OffsetMin: 0),
    (City: 'DUBAI';      OffsetMin: 240),
    (City: 'MUMBAI';     OffsetMin: 330),
    (City: 'BANGKOK';    OffsetMin: 420),
    (City: 'SINGAPORE';  OffsetMin: 480),
    (City: 'TOKYO';      OffsetMin: 540),
    (City: 'BRISBANE';   OffsetMin: 600));

  DayNames: array[1..7] of string = ('MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY',
    'SATURDAY', 'SUNDAY');

function NowUTC: TDateTime;
begin
  Result := LocalTimeToUniversal(Now);
end;

function UtcOffsetText(minutes: integer): string;
begin
  if minutes >= 0 then Result := '+' else Result := '-';
  Result := Format('UTC%s%.2d:%.2d', [Result, Abs(minutes) div 60, Abs(minutes) mod 60]);
end;

{ ---------- TAnalogClockWidget ---------- }

const
  AW = 460;
  ACX = 230;
  ACY = 230;

constructor TAnalogClockWidget.Create;
begin
  inherited Create;
  SetView(AW, AW);
  FSmooth := 1;
  AddParam('Smooth seconds', 'Clock', '1 = the second hand glides, 0 = it ticks once per second.',
    FSmooth, 0, 1, 0, False);
end;

class function TAnalogClockWidget.UIName: string;
begin
  Result := 'Analog Clock';
end;

class function TAnalogClockWidget.UIDescription: string;
begin
  Result := 'HUD clock face: minute ticks, hour marks and numerals, hour / minute hands, a gliding second ' +
    'hand and a seconds arc.';
end;

class function TAnalogClockWidget.UnitFile: string;
begin
  Result := 'HUDClock\uhudclock.pas';
end;

procedure TAnalogClockWidget.DrawStatic;
var
  i: integer;
  a: single;
begin
  SoftDisc(FFill, ACX, ACY, 215, Ice(35));
  Disc(ACX, ACY, 200, Navy(170));
  Ring(ACX, ACY, 214, 1.5, Ice(150));
  Ticks(ACX, ACY, 206, 212, 120, 0, 360, 0.7, Ice(110));
  Ring(ACX, ACY, 200, 2.5, White);
  Ticks(ACX, ACY, 186, 196, 60, 0, 360, 1.2, Ice(170));
  Ticks(ACX, ACY, 176, 196, 12, 0, 360, 4, White);
  for i := 1 to 12 do
  begin
    a := DegToRad(i * 30 - 90);
    Txt(ACX + 156 * Cos(a), ACY + 156 * Sin(a), Format('%.2d', [i]), 13, White(230), taCenter);
  end;
  Ring(ACX, ACY, 132, 1, Ice(110));
  Arc(ACX, ACY, 120, 200, 250, 3, White(220));
  Arc(ACX, ACY, 120, 20, 70, 3, White(220));
  Txt(ACX, ACY + 70, 'HUD CHRONO', 8, Ice(190), taCenter);
end;

procedure TAnalogClockWidget.DrawDynamic;
var
  nowT: TDateTime;
  h, m, s, ms: word;
  sec, minA, hourA, secA: single;
begin
  nowT := Now;
  DecodeTime(nowT, h, m, s, ms);
  if FSmooth >= 1 then sec := s + ms / 1000 else sec := s;
  secA := sec * 6 - 90;
  minA := (m + sec / 60) * 6 - 90;
  hourA := ((h mod 12) + m / 60 + sec / 3600) * 30 - 90;
  // seconds arc around the face
  Arc(ACX, ACY, 222, -90, secA, 3, Ice);
  // hour hand: wide band, minute hand: long band
  Band(ACX, ACY, 0, 100, hourA - 3.2, hourA + 3.2, White);
  Band(ACX, ACY, 0, 168, minA - 1.6, minA + 1.6, White);
  Disc(ACX + 100 * Cos(DegToRad(hourA)), ACY + 100 * Sin(DegToRad(hourA)), 4, White);
  // second hand with a counterweight
  Line(ACX - 30 * Cos(DegToRad(secA)), ACY - 30 * Sin(DegToRad(secA)),
       ACX + 190 * Cos(DegToRad(secA)), ACY + 190 * Sin(DegToRad(secA)), 1.6, Ice);
  Disc(ACX + 190 * Cos(DegToRad(secA)), ACY + 190 * Sin(DegToRad(secA)), 3.5, Ice);
  Disc(ACX, ACY, 9, Navy(255));
  Ring(ACX, ACY, 9, 2, White);
  Disc(ACX, ACY, 3, Ice);
end;

procedure TAnalogClockWidget.DefineDirty;
begin
  AddDirty(ACX - 226, ACY - 226, ACX + 226, ACY + 226);
end;

procedure TAnalogClockWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 460 x 460, centre (230, 230).');
  L.Add('  Static   face disc r200 Navy, rims r200/r214, 120 + 60 ticks, 12 hour marks,');
  L.Add('           numerals 01..12 at r156, inner ring r132 with two accent arcs');
  L.Add('  Dynamic  seconds arc r222 (Ice, 12 o''clock -> current second),');
  L.Add('           hour hand band r0..100 (6.4 deg), minute hand band r0..168 (3.2 deg),');
  L.Add('           second hand line -30..190 with tip dot, centre cap');
  L.Add('  Param    Smooth seconds: glide (ms resolution) or tick');
end;

{ ---------- TDigitalClockWidget ---------- }

const
  DW = 740;
  DH = 190;

constructor TDigitalClockWidget.Create;
begin
  inherited Create;
  SetView(DW, DH);
  F24h := 1;
  AddParam('24-hour', 'Clock', '1 = 24-hour time, 0 = 12-hour with AM / PM.', F24h, 0, 1, 0, False);
end;

class function TDigitalClockWidget.UIName: string;
begin
  Result := 'Digital Clock';
end;

class function TDigitalClockWidget.UIDescription: string;
begin
  Result := 'Large time readout with seconds, the full date, day of the year, ISO week and UTC offset.';
end;

class function TDigitalClockWidget.UnitFile: string;
begin
  Result := 'HUDClock\uhudclock.pas';
end;

procedure TDigitalClockWidget.DrawStatic;
var
  i: integer;
begin
  FillPoly([0, 12, 12, 0, 460, 0, 472, 12, DW, 12, DW, DH - 12, DW - 12, DH, 0, DH], Steel(45));
  Polygon([0, 12, 12, 0, 460, 0, 472, 12, DW, 12, DW, DH - 12, DW - 12, DH, 0, DH], 1.3, Ice(180));
  for i := 0 to 5 do
    Line(414 + i * 7, 9, 421 + i * 7, 2, 2, White(200));
  Line(DW, 30, DW, 100, 3, White);
  Txt(16, 16, '\\LOCAL TIME', 8, White(230));
  Line(40, 128, DW - 40, 128, 1, Ice(110));
  Line(300, 128, DW - 300, 128, 2.5, White);
end;

procedure TDigitalClockWidget.DrawDynamic;
var
  nowT: TDateTime;
  h, m, s, ms: word;
  hh: integer;
  suffix, main: string;
  offMin: integer;
begin
  nowT := Now;
  DecodeTime(nowT, h, m, s, ms);
  hh := h;
  suffix := '';
  if F24h < 1 then
  begin
    if h < 12 then suffix := 'AM' else suffix := 'PM';
    hh := h mod 12;
    if hh = 0 then hh := 12;
  end;
  main := Format('%.2d:%.2d:%.2d', [hh, m, s]);
  TxtCached(DW / 2 - 20, 74, main, 60, taCenter);
  TxtCached(DW / 2 + 200, 92, Format('.%.3d', [ms]), 14, taLeftJustify, Ice(200));
  if suffix <> '' then
    TxtCached(DW / 2 + 200, 58, suffix, 14, taLeftJustify, Ice(220));
  TxtCached(DW / 2, 148, Format('%s  %s', [DayNames[DayOfTheWeek(nowT)],
    UpperCase(FormatDateTime('dd mmmm yyyy', nowT))]), 11, taCenter, White(230));
  offMin := Round((nowT - NowUTC) * 24 * 60);
  TxtCached(DW / 2, 170, Format('DAY %d  -  ISO WEEK %d  -  %s', [DayOfTheYear(nowT), WeekOfTheYear(nowT),
    UtcOffsetText(offMin)]), 8, taCenter, Ice(180));
end;

procedure TDigitalClockWidget.DefineDirty;
begin
  AddDirty(30, 26, DW - 30, DH - 8);
end;

procedure TDigitalClockWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 740 x 190.');
  L.Add('  Time     hh:nn:ss size 60 + .mmm size 14 (+ AM/PM when 24-hour = 0)');
  L.Add('  Date     day name + dd mmmm yyyy, size 11');
  L.Add('  Info     day of the year, ISO week, local UTC offset');
end;

{ ---------- TCalendarWidget ---------- }

const
  CW = 360;
  CH = 270;

constructor TCalendarWidget.Create;
begin
  inherited Create;
  SetView(CW, CH);
end;

class function TCalendarWidget.UIName: string;
begin
  Result := 'Calendar';
end;

class function TCalendarWidget.UIDescription: string;
begin
  Result := 'Month grid (weeks start on Monday) with the ISO week numbers and today ringed.';
end;

class function TCalendarWidget.UnitFile: string;
begin
  Result := 'HUDClock\uhudclock.pas';
end;

procedure TCalendarWidget.DrawStatic;
var
  first: TDateTime;
  yr, mo, d, last, col, row, i: integer;
  cx, cy: single;
  c: TBGRAPixel;
begin
  FShownDay := Date;
  FillPoly([0, 12, 12, 0, 220, 0, 232, 12, CW, 12, CW, CH - 12, CW - 12, CH, 0, CH], Steel(45));
  Polygon([0, 12, 12, 0, 220, 0, 232, 12, CW, 12, CW, CH - 12, CW - 12, CH, 0, CH], 1.3, Ice(180));
  yr := YearOf(FShownDay);
  mo := MonthOf(FShownDay);
  Txt(16, 16, UpperCase(FormatDateTime('mmmm yyyy', FShownDay)), 8, White(230));
  for i := 0 to 6 do
    Txt(64 + i * 40, 46, Copy(DayNames[i + 1], 1, 2), 7.5, Ice(180), taCenter);
  Txt(26, 46, 'WK', 7, Ice(120), taCenter);
  Line(14, 56, CW - 14, 56, 1, Ice(110));
  first := EncodeDate(yr, mo, 1);
  last := DaysInAMonth(yr, mo);
  col := DayOfTheWeek(first) - 1;
  row := 0;
  for d := 1 to last do
  begin
    cx := 64 + col * 40;
    cy := 74 + row * 32;
    if col >= 5 then c := Ice(170) else c := White(225);
    Txt(cx, cy, IntToStr(d), 9, c, taCenter);
    if (col = 0) or (d = 1) then
      Txt(26, cy, IntToStr(WeekOfTheYear(EncodeDate(yr, mo, d))), 7, Ice(120), taCenter);
    Inc(col);
    if col = 7 then
    begin
      col := 0;
      Inc(row);
    end;
  end;
end;

procedure TCalendarWidget.DrawDynamic;
var
  first: TDateTime;
  col, row, d: integer;
  cx, cy: single;
begin
  // a new day: redraw the grid (month / year may have changed too)
  if Trunc(Date) <> Trunc(FShownDay) then InvalidateStatic;
  first := EncodeDate(YearOf(Date), MonthOf(Date), 1);
  d := DayOf(Date);
  col := (DayOfTheWeek(first) - 1 + d - 1) mod 7;
  row := (DayOfTheWeek(first) - 1 + d - 1) div 7;
  cx := 64 + col * 40;
  cy := 74 + row * 32;
  Ring(cx, cy, 14, 2, White);
  Arc(cx, cy, 18, T * 120, T * 120 + 60, 1.5, Ice);
  Arc(cx, cy, 18, T * 120 + 180, T * 120 + 240, 1.5, Ice);
end;

procedure TCalendarWidget.DefineDirty;
begin
  AddDirty(20, 50, CW - 10, CH - 4);
end;

procedure TCalendarWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 360 x 270. Columns MO..SU every 40 units from x 64, rows every 32 from y 74.');
  L.Add('  Static   month title, weekday header, day numbers (weekend in Ice), ISO week numbers');
  L.Add('  Dynamic  today: ring r14 + two orbiting arcs; the grid is redrawn when the date changes');
end;

{ ---------- TWorldClockWidget ---------- }

const
  WW = 360;
  WH = 270;

constructor TWorldClockWidget.Create;
begin
  inherited Create;
  SetView(WW, WH);
end;

class function TWorldClockWidget.UIName: string;
begin
  Result := 'World Clocks';
end;

class function TWorldClockWidget.UIDescription: string;
begin
  Result := 'Time in cities that do not use daylight saving (fixed UTC offsets), day difference and a ' +
    '24-hour day/night bar.';
end;

class function TWorldClockWidget.UnitFile: string;
begin
  Result := 'HUDClock\uhudclock.pas';
end;

procedure TWorldClockWidget.DrawStatic;
var
  i: integer;
begin
  FillPoly([0, 12, 12, 0, 220, 0, 232, 12, WW, 12, WW, WH - 12, WW - 12, WH, 0, WH], Steel(45));
  Polygon([0, 12, 12, 0, 220, 0, 232, 12, WW, 12, WW, WH - 12, WW - 12, WH, 0, WH], 1.3, Ice(180));
  Txt(16, 16, '\\WORLD CLOCKS', 8, White(230));
  for i := 0 to High(Cities) do
  begin
    Txt(18, 52 + i * 31, Cities[i].City, 8, White(225));
    Txt(18, 64 + i * 31, UtcOffsetText(Cities[i].OffsetMin), 6, Ice(150));
    // 24 h track
    Line(200, 66 + i * 31, 340, 66 + i * 31, 2, Steel(160));
  end;
end;

procedure TWorldClockWidget.DrawDynamic;
var
  i, dayDiff: integer;
  utc, t2: TDateTime;
  frac_: single;
  extra: string;
begin
  utc := NowUTC;
  for i := 0 to High(Cities) do
  begin
    t2 := utc + Cities[i].OffsetMin / (24 * 60);
    dayDiff := Trunc(t2) - Trunc(Now);
    if dayDiff > 0 then extra := ' +1D' else if dayDiff < 0 then extra := ' -1D' else extra := '';
    TxtCached(340, 52 + i * 31, FormatDateTime('hh:nn', t2) + extra, 11, taRightJustify);
    frac_ := Frac(t2);
    // day (06-18) bright, night dim
    if (frac_ >= 0.25) and (frac_ < 0.75) then
      FLayer.FillEllipseAntialias(X(200 + 140 * frac_), Y(66 + i * 31), 3.5, 3.5, White)
    else
      FLayer.FillEllipseAntialias(X(200 + 140 * frac_), Y(66 + i * 31), 3.5, 3.5, Ice(140));
  end;
end;

procedure TWorldClockWidget.DefineDirty;
begin
  AddDirty(190, 38, WW - 6, WH - 6);
end;

procedure TWorldClockWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('View 360 x 270, one row per city every 31 units.');
  L.Add('  Static   city name, UTC offset, 24 h track (x 200..340)');
  L.Add('  Dynamic  hh:nn (+1D / -1D vs local date), position dot on the track');
  L.Add('           (white between 06:00 and 18:00, dim at night)');
  L.Add('  Cities   (no daylight saving, so a fixed offset is always right)');
  for i := 0 to High(Cities) do
    L.Add(Format('           %-10s %s', [Cities[i].City, UtcOffsetText(Cities[i].OffsetMin)]));
end;

{ ---------- THUDClockWidget ---------- }

constructor THUDClockWidget.Create;
begin
  inherited Create;
  SetView(1240, 600);
  SetParamByName('Max zoom', 2);
  AddChild(TAnalogClockWidget.Create, 10, 10, 'Analog Clock');
  AddChild(TDigitalClockWidget.Create, 490, 10, 'Digital Clock');
  AddChild(TCalendarWidget.Create, 490, 212, 'Calendar');
  AddChild(TWorldClockWidget.Create, 870, 212, 'World Clocks');
  FDay := TChevronLoaderWidget.Create;
  FDay.Caption := 'DAY';
  FDay.SetParamByName('Auto progress', 0);
  AddChild(FDay, 10, 505, 'Day progress (Chevron Loader)');
  FWeek := TSlantLoaderWidget.Create;
  FWeek.Caption := 'WEEK';
  FWeek.SetParamByName('Auto progress', 0);
  AddChild(FWeek, 315, 505, 'Week progress (Slant Loader)');
  FMonth := TBlockLoaderWidget.Create;
  FMonth.Caption := 'MONTH';
  FMonth.SetParamByName('Auto progress', 0);
  AddChild(FMonth, 620, 505, 'Month progress (Block Loader)');
  FYear := TPillLoaderWidget.Create;
  FYear.Caption := 'YEAR';
  FYear.SetParamByName('Auto progress', 0);
  AddChild(FYear, 925, 505, 'Year progress (Pill Loader)');
end;

class function THUDClockWidget.UIName: string;
begin
  Result := 'HUD Clock';
end;

class function THUDClockWidget.UIDescription: string;
begin
  Result := 'Date and time in the HUD style: analog and digital clocks, calendar, world clocks and the ' +
    'progress of the day, week, month and year.';
end;

class function THUDClockWidget.UnitFile: string;
begin
  Result := 'HUDClock\uhudclock.pas';
end;

procedure THUDClockWidget.DrawDynamic;
var
  nowT, startY: TDateTime;
  dayP, weekP, monthP, yearP: double;
begin
  nowT := Now;
  dayP := Frac(nowT);
  weekP := (DayOfTheWeek(nowT) - 1 + dayP) / 7;
  monthP := (DayOf(nowT) - 1 + dayP) / DaysInMonth(nowT);
  startY := StartOfTheYear(nowT);
  yearP := (nowT - startY) / DaysInYear(nowT);
  FDay.SetParamValue(FDay.ParamIndex('Progress %'), 100 * dayP);
  FWeek.SetParamValue(FWeek.ParamIndex('Progress %'), 100 * weekP);
  FMonth.SetParamValue(FMonth.ParamIndex('Progress %'), 100 * monthP);
  FYear.SetParamValue(FYear.ParamIndex('Progress %'), 100 * yearP);
  inherited DrawDynamic;
end;

procedure THUDClockWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('Canvas 1240 x 600 design units.');
  L.Add('');
  L.Add('LAYOUT');
  for i := 0 to ChildCount - 1 do
    L.Add(Format('  %-32s %-22s (%4.0f,%4.0f)', [ChildCaption(i), Children[i].ClassName,
      ChildOrigin(i).x, ChildOrigin(i).y]));
  L.Add('');
  L.Add('PROGRESS LOADERS');
  L.Add('  Day = time of day / 24 h, Week = Monday 00:00 -> Sunday 24:00,');
  L.Add('  Month = day of month / days in month, Year = since 1 Jan / days in year.');
  L.Add('All values come from the system clock (Now); the info panel time is the');
  L.Add('animation clock, which only drives the decorative motion.');
end;

procedure THUDClockWidget.DescribeLive(L: TStrings);
var
  nowT: TDateTime;
begin
  inherited DescribeLive(L);
  nowT := Now;
  L.Add('Local time          ' + FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', nowT));
  L.Add('UTC                 ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', NowUTC));
  L.Add(Format('Day / week / month  %.1f %% / %.1f %% / %.1f %%', [100 * Frac(nowT),
    100 * (DayOfTheWeek(nowT) - 1 + Frac(nowT)) / 7, 100 * (DayOf(nowT) - 1 + Frac(nowT)) / DaysInMonth(nowT)]));
  L.Add(Format('Year                %.2f %%', [100 * (nowT - StartOfTheYear(nowT)) / DaysInYear(nowT)]));
end;

end.
