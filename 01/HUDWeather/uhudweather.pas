unit UHUDWeather;

{ HUD Weather - weather in the Sci-Fi HUD style (data: Open-Meteo).

  Current conditions with a drawn HUD weather icon, wind compass, sun arc
  (sunrise / sunset, sun position, UV), 24-hour temperature + rain chance
  chart with hover, 7-day forecast with min/max range bars, and kit loaders
  for humidity, cloud cover and today's rain chance.
  Location panel (HUD): city box + SEARCH, REFRESH. Data refreshes every 15 minutes; the
  last city is kept in weather.ini. Without internet: demo data, labelled. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, DateUtils, IniFiles, Graphics, Forms, Controls, StdCtrls, ExtCtrls, LCLType,
  BGRABitmap, BGRABitmapTypes, HUDCore, HUDHost, HUDPanels, UWeatherData,
  UChevronLoader, UPillLoader, UBlockLoader;

type

  { TWeatherBase - shared data pointer, units and the weather icon }

  TWeatherBase = class(THUDWidget)
  protected
    FData: ^TWeatherData;
    FUnitF: ^single;
    function TempStr(c: double; withUnit: boolean = True): string;
    procedure WeatherIcon(code: integer; isDay: boolean; cx, cy, size: single);
    procedure Frame(AW, AH: single; const ATitle: string);
  public
    class function UnitFile: string; override;
  end;

  TCurrentWidget = class(TWeatherBase)
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

  TWindWidget = class(TWeatherBase)
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

  TSunWidget = class(TWeatherBase)
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

  THourlyWidget = class(TWeatherBase)
  public
    HoverOn: boolean;
    HX, HY: single;
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

  TDailyWidget = class(TWeatherBase)
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

  { TSearchPanelWidget - HUD location bar: input frame (a TEdit is placed in
    it), SEARCH / REFRESH buttons drawn in the HUD style, status at the right }

  TSearchPanelWidget = class(TWeatherBase)
  public
    HoverBtn, FlashBtn: integer;   // 0 = search, 1 = refresh
    FlashT0: single;
    EditFocused, Loading: boolean;
    StatusText, CoordText: string;
    function ButtonAt(lx, ly: single): integer;
    procedure Flash(btn: integer);
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

  { THUDWeatherWidget }

  THUDWeatherWidget = class(THUDComposite)
  private
    FUnitF: single;
    FRefreshMin: single;
  public
    Data: TWeatherData;
    Loading: boolean;
    LastRequest: TDateTime;
    City: string;
    Search: TSearchPanelWidget;
    Current: TCurrentWidget;
    Wind: TWindWidget;
    Sun: TSunWidget;
    Hourly: THourlyWidget;
    Daily: TDailyWidget;
    Humidity: TPillLoaderWidget;
    Clouds: TBlockLoaderWidget;
    Rain: TChevronLoaderWidget;
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
    procedure Request(const ACity: string);
    procedure Received(const AData: TWeatherData);
    function IniFile: string;
  protected
    procedure DrawDynamic; override;
  end;

implementation

{ ---------- TWeatherBase ---------- }

class function TWeatherBase.UnitFile: string;
begin
  Result := 'HUDWeather\uhudweather.pas';
end;

function TWeatherBase.TempStr(c: double; withUnit: boolean): string;
begin
  if (FUnitF <> nil) and (FUnitF^ >= 1) then
  begin
    Result := Format('%.0f', [c * 9 / 5 + 32]);
    if withUnit then Result += '°F';
  end
  else
  begin
    Result := Format('%.0f', [c]);
    if withUnit then Result += '°C';
  end;
  if Result = '-0°C' then Result := '0°C';
end;

procedure TWeatherBase.Frame(AW, AH: single; const ATitle: string);
var
  notch: single;
begin
  notch := Min(AW * 0.62, AW - 60);
  FillPoly([0, 12, 12, 0, notch, 0, notch + 12, 12, AW, 12, AW, AH - 12, AW - 12, AH, 0, AH], Steel(45));
  Polygon([0, 12, 12, 0, notch, 0, notch + 12, 12, AW, 12, AW, AH - 12, AW - 12, AH, 0, AH], 1.3, Ice(180));
  Line(AW, 28, AW, Min(90, AH - 20), 3, White);
  Txt(16, 16, ATitle, 8, White(230));
end;

procedure TWeatherBase.WeatherIcon(code: integer; isDay: boolean; cx, cy, size: single);
var
  kind_, i: integer;
  s, streak: single;

  procedure Cloud(ox, oy, sc: single; c: TBGRAPixel);
  begin
    // a cloud of four discs on a flat base
    Disc(ox - 0.45 * sc, oy + 0.1 * sc, 0.32 * sc, c);
    Disc(ox - 0.05 * sc, oy - 0.15 * sc, 0.42 * sc, c);
    Disc(ox + 0.4 * sc, oy + 0.05 * sc, 0.34 * sc, c);
    FillPoly([ox - 0.75 * sc, oy + 0.1 * sc, ox + 0.72 * sc, oy + 0.1 * sc,
              ox + 0.72 * sc, oy + 0.42 * sc, ox - 0.75 * sc, oy + 0.42 * sc], c);
  end;

  procedure Sun(ox, oy, sc: single);
  begin
    Disc(ox, oy, 0.36 * sc, White);
    Ring(ox, oy, 0.5 * sc, 0.06 * sc, Ice(200));
    Ticks(ox, oy, 0.62 * sc, 0.82 * sc, 8, T * 8, 360 + T * 8, 0.09 * sc, White);
  end;

  procedure Moon(ox, oy, sc: single);
  begin
    Disc(ox, oy, 0.42 * sc, White);
    Disc(ox + 0.2 * sc, oy - 0.14 * sc, 0.36 * sc, Navy(255));
    Ring(ox, oy, 0.55 * sc, 0.04 * sc, Ice(150));
  end;

begin
  kind_ := CodeKind(code);
  s := size;
  if kind_ = 4 then streak := 0.04 else streak := 0.07;
  case kind_ of
    0: if isDay then Sun(cx, cy, s) else Moon(cx, cy, s);
    1:
      begin
        if isDay then Sun(cx - 0.3 * s, cy - 0.3 * s, s * 0.8) else Moon(cx - 0.3 * s, cy - 0.3 * s, s * 0.8);
        Cloud(cx + 0.1 * s, cy + 0.15 * s, s * 0.85, Ice(235));
      end;
    2: begin Cloud(cx - 0.25 * s, cy - 0.25 * s, s * 0.6, Steel(230)); Cloud(cx + 0.1 * s, cy + 0.1 * s, s * 0.85, Ice(235)); end;
    3:
      begin
        Cloud(cx, cy - 0.2 * s, s * 0.75, Steel(230));
        for i := 0 to 2 do
          Line(cx - 0.7 * s + i * 0.1 * s, cy + 0.35 * s + i * 0.16 * s, cx + 0.7 * s - i * 0.1 * s,
            cy + 0.35 * s + i * 0.16 * s, 0.06 * s, Ice(220));
      end;
    4, 5, 7:
      begin
        Cloud(cx, cy - 0.2 * s, s * 0.85, Ice(235));
        if kind_ = 7 then
          FillPoly([cx + 0.05 * s, cy + 0.15 * s, cx - 0.2 * s, cy + 0.55 * s, cx, cy + 0.55 * s,
                    cx - 0.12 * s, cy + 0.9 * s, cx + 0.25 * s, cy + 0.42 * s, cx + 0.05 * s, cy + 0.42 * s], White)
        else
          for i := 0 to 3 do
            Line(cx - 0.45 * s + i * 0.3 * s, cy + 0.35 * s + 0.1 * s * Frac(T + i * 0.3),
              cx - 0.55 * s + i * 0.3 * s, cy + 0.6 * s + 0.1 * s * Frac(T + i * 0.3),
              streak * s, Ice);
      end;
    6:
      begin
        Cloud(cx, cy - 0.2 * s, s * 0.85, Ice(235));
        for i := 0 to 5 do
          Disc(cx - 0.5 * s + (i mod 3) * 0.5 * s + 0.12 * s * (i div 3), cy + 0.38 * s + 0.2 * s * (i div 3) +
            0.05 * s * Sin(T * 2 + i), 0.06 * s, White);
      end;
  end;
end;

{ ---------- TCurrentWidget ---------- }

constructor TCurrentWidget.Create;
begin
  inherited Create;
  SetView(600, 300);
end;

class function TCurrentWidget.UIName: string;
begin
  Result := 'Current Conditions';
end;

class function TCurrentWidget.UIDescription: string;
begin
  Result := 'City, temperature, condition with a drawn HUD icon, feels-like, humidity, pressure, update time.';
end;

procedure TCurrentWidget.DrawStatic;
begin
  Frame(600, 300, '\\CURRENT');
  Line(30, 196, 380, 196, 1, Ice(100));
  Ring(470, 140, 92, 1, Ice(110));
  Ticks(470, 140, 96, 101, 60, 0, 360, 0.8, Ice(110));
end;

procedure TCurrentWidget.DrawDynamic;
var
  D: TWeatherData;
  place: string;
begin
  D := FData^;
  if not D.Valid then
  begin
    TxtCached(30, 120, 'NO DATA', 22, taLeftJustify, Ice(200));
    TxtCached(30, 160, FitText(D.Status, 60), 8, taLeftJustify, Ice(170));
    Exit;
  end;
  place := UpperCase(D.City);
  if D.Country <> '' then place += '  ·  ' + UpperCase(D.Country);
  TxtCached(30, 48, FitText(place, 46), 12, taLeftJustify);
  TxtCached(30, 128, TempStr(D.Temp), 60, taLeftJustify);
  TxtCached(30, 180, UpperCase(CodeText(D.Code)), 11, taLeftJustify, Ice(230));
  TxtCached(30, 218, Format('FEELS LIKE %s    HUMIDITY %.0f%%', [TempStr(D.Feels), D.Humidity]), 8,
    taLeftJustify, Ice(210));
  TxtCached(30, 240, Format('PRESSURE %.0f HPA    PRECIPITATION %.1f MM', [D.Pressure, D.Precip]), 8,
    taLeftJustify, Ice(210));
  TxtCached(30, 272, FitText(Format('LOCAL %s   UPDATED %s   %s',
    [FormatDateTime('ddd hh:nn', D.LocalNow), FormatDateTime('hh:nn', D.Fetched), D.Status]), 90), 6.5,
    taLeftJustify, Ice(150));
  WeatherIcon(D.Code, D.IsDay, 470, 140, 110);
  if D.Demo then
    TxtCached(580, 30, 'DEMO DATA', 8, taRightJustify, White);
end;

procedure TCurrentWidget.DefineDirty;
begin
  AddDirty(20, 30, 592, 292);
end;

procedure TCurrentWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 600 x 300.');
  L.Add('  Text     city · country (12), temperature (60), condition (11), feels-like +');
  L.Add('           humidity, pressure + precipitation, local time / update / source');
  L.Add('  Icon     drawn at (470,140) size 110 from the WMO weather code:');
  L.Add('           sun (rotating rays) / moon, cloud, fog lines, rain / drizzle streaks,');
  L.Add('           snow flakes, lightning bolt; day / night from is_day');
end;

{ ---------- TWindWidget ---------- }

constructor TWindWidget.Create;
begin
  inherited Create;
  SetView(300, 300);
end;

class function TWindWidget.UIName: string;
begin
  Result := 'Wind Compass';
end;

class function TWindWidget.UIDescription: string;
begin
  Result := 'Compass with an arrow showing where the wind blows to, speed, gusts and source direction.';
end;

procedure TWindWidget.DrawStatic;
const
  Lbl: array[0..3] of string = ('N', 'E', 'S', 'W');
var
  i: integer;
begin
  Frame(300, 300, '\\WIND');
  Disc(150, 165, 100, Navy(170));
  Ring(150, 165, 100, 2, White);
  Ticks(150, 165, 103, 109, 72, 0, 360, 0.8, Ice(150));
  Ticks(150, 165, 100, 112, 8, -90, 270, 2, White(220));
  Ring(150, 165, 64, 0.8, Ice(110));
  for i := 0 to 3 do
    Txt(150 + 82 * Cos(DegToRad(i * 90 - 90)), 165 + 82 * Sin(DegToRad(i * 90 - 90)), Lbl[i], 10,
      Ice(220), taCenter);
end;

procedure TWindWidget.DrawDynamic;
var
  D: TWeatherData;
  a, ca, sa: single;
begin
  D := FData^;
  if not D.Valid then Exit;
  // direction is where the wind comes FROM: the arrow points where it goes
  a := DegToRad(D.WindDir + 180 - 90);
  ca := Cos(a);
  sa := Sin(a);
  Line(150 - 70 * ca, 165 - 70 * sa, 150 + 60 * ca, 165 + 60 * sa, 3, White);
  FillPoly([150 + 76 * ca, 165 + 76 * sa, 150 + 52 * ca - 10 * sa, 165 + 52 * sa + 10 * ca,
            150 + 52 * ca + 10 * sa, 165 + 52 * sa - 10 * ca], White);
  Disc(150 - 70 * ca, 165 - 70 * sa, 5, Ice);
  Disc(150, 165, 30, Navy(255));
  Ring(150, 165, 30, 1.5, Ice(200));
  TxtCached(150, 159, Format('%.0f', [D.WindSpeed]), 16, taCenter);
  TxtCached(150, 178, 'KM/H', 6.5, taCenter, Ice(180));
  TxtCached(150, 282, Format('FROM %s %.0f°   GUSTS %.0f KM/H', [Cardinal(D.WindDir), D.WindDir, D.Gust]),
    7, taCenter, Ice(210));
end;

procedure TWindWidget.DefineDirty;
begin
  AddDirty(40, 55, 260, 292);
end;

procedure TWindWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 300 x 300, dial centre (150,165) r100, N E S W labels.');
  L.Add('  Arrow    points where the wind blows TO (direction + 180°); the dot is the');
  L.Add('           side it comes from. Centre: speed km/h. Bottom: source direction');
  L.Add('           (16-point) and gusts.');
end;

{ ---------- TSunWidget ---------- }

constructor TSunWidget.Create;
begin
  inherited Create;
  SetView(300, 300);
end;

class function TSunWidget.UIName: string;
begin
  Result := 'Sun Arc';
end;

class function TSunWidget.UIDescription: string;
begin
  Result := 'Arc from sunrise to sunset with the sun at the current local time, day length and UV max.';
end;

procedure TSunWidget.DrawStatic;
begin
  Frame(300, 300, '\\SUN');
  Arc(150, 200, 110, 180, 360, 1.2, Ice(130));
  Line(20, 200, 280, 200, 1, Ice(150));
  Ticks(150, 200, 104, 110, 12, 180, 360, 1, Ice(140));
end;

procedure TSunWidget.DrawDynamic;
var
  D: TWeatherData;
  f, a, len: double;
begin
  D := FData^;
  if not D.Valid then Exit;
  len := D.DSunset[0] - D.DSunrise[0];
  if len > 0 then f := (D.LocalNow - D.DSunrise[0]) / len else f := 0.5;
  if (f >= 0) and (f <= 1) then
  begin
    a := 180 + 180 * f;
    Arc(150, 200, 110, 180, a, 3, Ice);
    Disc(150 + 110 * Cos(DegToRad(a)), 200 + 110 * Sin(DegToRad(a)), 10, White);
    Ring(150 + 110 * Cos(DegToRad(a)), 200 + 110 * Sin(DegToRad(a)), 16, 1, Ice(180));
  end
  else
    TxtCached(150, 160, 'NIGHT', 12, taCenter, Ice(200));
  TxtCached(28, 220, 'RISE ' + FormatDateTime('hh:nn', D.DSunrise[0]), 8, taLeftJustify, Ice(220));
  TxtCached(272, 220, 'SET ' + FormatDateTime('hh:nn', D.DSunset[0]), 8, taRightJustify, Ice(220));
  TxtCached(150, 252, Format('DAYLIGHT %dh %.2dm', [Trunc(len * 24), Round(Frac(len * 24) * 60) mod 60]), 9,
    taCenter);
  TxtCached(150, 278, Format('UV INDEX MAX %.1f', [D.DUV[0]]), 8, taCenter, Ice(210));
end;

procedure TSunWidget.DefineDirty;
begin
  AddDirty(22, 60, 280, 292);
end;

procedure TSunWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 300 x 300. Half-circle r110 centred (150,200) = sunrise (left) .. sunset (right).');
  L.Add('  Sun dot at (local time - sunrise) / day length; "NIGHT" outside daylight.');
  L.Add('  Texts: sunrise, sunset, day length, today''s UV index maximum.');
end;

{ ---------- THourlyWidget ---------- }

const
  HW = 900;
  HH = 250;
  HPL = 60;
  HPR = 880;
  HTT = 50;      // temperature plot
  HTB = 160;
  HRT = 180;     // rain strip
  HRB = 222;

constructor THourlyWidget.Create;
begin
  inherited Create;
  SetView(HW, HH);
end;

class function THourlyWidget.UIName: string;
begin
  Result := 'Next 24 Hours';
end;

class function THourlyWidget.UIDescription: string;
begin
  Result := 'Temperature line for the next 24 hours and, on its own scale below, the hourly chance of rain.';
end;

procedure THourlyWidget.DrawStatic;
begin
  Frame(HW, HH, '\\NEXT 24 HOURS');
  Txt(HPL - 10, HRT - 6, 'RAIN %', 6.5, Ice(150), taRightJustify);
  Line(HPL, HRB, HPR, HRB, 1, Ice(110));
end;

procedure THourlyWidget.DrawDynamic;
var
  D: TWeatherData;
  i, idx, imax, imin: integer;
  lo, hi, tx, ty, bw: single;
  P: ArrayOfTPointF;

  function XAt(i: integer): single;
  begin
    Result := HPL + (HPR - HPL) * i / (HoursShown - 1);
  end;

  function YAt(v: double): single;
  begin
    Result := HTB - (HTB - HTT) * (v - lo) / (hi - lo);
  end;

begin
  D := FData^;
  if not D.Valid then Exit;
  lo := MaxSingle; hi := -MaxSingle;
  imax := 0; imin := 0;
  for i := 0 to HoursShown - 1 do
  begin
    if D.HTemp[i] < lo then begin lo := D.HTemp[i]; imin := i; end;
    if D.HTemp[i] > hi then begin hi := D.HTemp[i]; imax := i; end;
  end;
  lo := Floor(lo) - 1;
  hi := Ceil(hi) + 1;
  // temperature axis: min and max gridlines with labels
  FFill.DrawLineAntialias(X(HPL), Y(YAt(hi - 1)), X(HPR), Y(YAt(hi - 1)), BGRA(42, 68, 100), 1);
  FFill.DrawLineAntialias(X(HPL), Y(YAt(lo + 1)), X(HPR), Y(YAt(lo + 1)), BGRA(42, 68, 100), 1);
  TxtCached(HPL - 10, YAt(hi - 1), TempStr(hi - 1), 7, taRightJustify, Ice(150));
  TxtCached(HPL - 10, YAt(lo + 1), TempStr(lo + 1), 7, taRightJustify, Ice(150));
  SetLength(P, HoursShown);
  for i := 0 to HoursShown - 1 do P[i] := Pt(XAt(i), YAt(D.HTemp[i]));
  FLayer.JoinStyle := pjsRound;
  FLayer.DrawPolyLineAntialias(P, Ice, 2.2);
  // label only the extremes
  TxtCached(XAt(imax), YAt(D.HTemp[imax]) - 12, TempStr(D.HTemp[imax]), 8, taCenter);
  TxtCached(XAt(imin), YAt(D.HTemp[imin]) + 13, TempStr(D.HTemp[imin]), 8, taCenter);
  FLayer.FillEllipseAntialias(X(XAt(0)), Y(YAt(D.HTemp[0])), 6, 6, BGRA(22, 45, 74));
  FLayer.FillEllipseAntialias(X(XAt(0)), Y(YAt(D.HTemp[0])), 4, 4, White);
  // rain chance strip (own 0..100 % scale)
  bw := Min(24 / Max(K, 0.01), (HPR - HPL) / HoursShown * 0.6);   // <= 24 px
  for i := 0 to HoursShown - 1 do
    if D.HRain[i] > 0 then
      FFill.FillRectAntialias(X(XAt(i) - bw / 2), Y(HRB - (HRB - HRT) * D.HRain[i] / 100),
        X(XAt(i) + bw / 2), Y(HRB), Steel(220));
  // hour labels every 3 hours
  for i := 0 to HoursShown - 1 do
    if i mod 3 = 0 then
      if i = 0 then TxtCached(XAt(i), HRB + 14, 'NOW', 7, taCenter, Ice(160))
      else TxtCached(XAt(i), HRB + 14, FormatDateTime('hh', D.HTime[i]), 7, taCenter, Ice(160));
  // hover
  if HoverOn and (HX >= HPL - 10) and (HX <= HPR + 10) and (HY >= HTT - 20) and (HY <= HRB + 10) then
  begin
    idx := EnsureRange(Round((HX - HPL) / ((HPR - HPL) / (HoursShown - 1))), 0, HoursShown - 1);
    FLayer.DrawLineAntialias(X(XAt(idx)), Y(HTT - 8), X(XAt(idx)), Y(HRB), Ice(150), 1);
    FLayer.FillEllipseAntialias(X(XAt(idx)), Y(YAt(D.HTemp[idx])), 6, 6, BGRA(22, 45, 74));
    FLayer.FillEllipseAntialias(X(XAt(idx)), Y(YAt(D.HTemp[idx])), 4, 4, White);
    tx := XAt(idx) + 14;
    if tx + 170 > HW - 8 then tx := XAt(idx) - 184;
    ty := HTT;
    FLayer.FillRoundRectAntialias(X(tx), Y(ty), X(tx + 170), Y(ty + 70), 4, 4, BGRA(10, 24, 42, 245));
    FLayer.RoundRectAntialias(X(tx), Y(ty), X(tx + 170), Y(ty + 70), 4, 4, Ice(170), 1);
    TxtCached(tx + 10, ty + 13, FormatDateTime('ddd hh:nn', D.HTime[idx]), 8, taLeftJustify);
    TxtCached(tx + 10, ty + 32, 'Temp ' + TempStr(D.HTemp[idx]), 7.5, taLeftJustify, Ice(220));
    TxtCached(tx + 10, ty + 48, Format('Rain %.0f%%', [D.HRain[idx]]), 7.5, taLeftJustify, Ice(220));
    TxtCached(tx + 10, ty + 62, CodeText(D.HCode[idx]), 6.5, taLeftJustify, Ice(170));
  end;
end;

procedure THourlyWidget.DefineDirty;
begin
  AddDirty(10, 30, HW - 6, HH - 6);
end;

procedure THourlyWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 900 x 250.');
  L.Add('  Temperature  line 2.2 px Ice, its own scale (min - 1 .. max + 1), labels on the');
  L.Add('               highest and lowest hour only, ringed dot at NOW');
  L.Add('  Rain chance  separate strip below with its own 0..100 % scale (never a second');
  L.Add('               axis on the temperature plot), Steel columns');
  L.Add('  Hover        hairline, ringed dot and a tooltip (time, temperature, rain, condition)');
end;

{ ---------- TDailyWidget ---------- }

constructor TDailyWidget.Create;
begin
  inherited Create;
  SetView(310, 370);
end;

class function TDailyWidget.UIName: string;
begin
  Result := '7-Day Forecast';
end;

class function TDailyWidget.UIDescription: string;
begin
  Result := 'One row per day: name, icon, rain chance, min and max temperature with a range bar on a shared ' +
    'weekly scale.';
end;

procedure TDailyWidget.DrawStatic;
begin
  Frame(310, 370, '\\7 DAYS');
end;

procedure TDailyWidget.DrawDynamic;
var
  D: TWeatherData;
  i: integer;
  ry, wlo, whi, x0, x1: single;
  name: string;
begin
  D := FData^;
  if not D.Valid then Exit;
  wlo := MaxSingle; whi := -MaxSingle;
  for i := 0 to DaysShown - 1 do
  begin
    wlo := Min(wlo, D.DMin[i]);
    whi := Max(whi, D.DMax[i]);
  end;
  if whi <= wlo then whi := wlo + 1;
  for i := 0 to DaysShown - 1 do
  begin
    ry := 62 + i * 44;
    if i = 0 then name := 'TODAY' else name := UpperCase(FormatDateTime('ddd', D.DDate[i]));
    TxtCached(18, ry, name, 8, taLeftJustify);
    WeatherIcon(D.DCode[i], True, 88, ry, 26);
    TxtCached(122, ry, Format('%.0f%%', [D.DRain[i]]), 7, taLeftJustify, Ice(170));
    TxtCached(184, ry, TempStr(D.DMin[i], False), 8, taRightJustify, Ice(200));
    TxtCached(296, ry, TempStr(D.DMax[i], False), 8, taRightJustify);
    // range bar on the weekly scale
    x0 := 190 + 80 * (D.DMin[i] - wlo) / (whi - wlo);
    x1 := 190 + 80 * (D.DMax[i] - wlo) / (whi - wlo);
    FFill.FillRectAntialias(X(190), Y(ry - 1.5), X(270), Y(ry + 1.5), Steel(120));
    FLayer.FillRoundRectAntialias(X(x0), Y(ry - 2.5), X(Max(x1, x0 + 3)), Y(ry + 2.5), 2, 2, Ice);
    if i < DaysShown - 1 then
      FFill.DrawLineAntialias(X(14), Y(ry + 22), X(296), Y(ry + 22), BGRA(42, 68, 100), 1);
  end;
end;

procedure TDailyWidget.DefineDirty;
begin
  AddDirty(10, 36, 304, 364);
end;

procedure TDailyWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 310 x 370, one row every 44 units: day, icon (size 26), rain chance,');
  L.Add('min, range bar (x 190..270 on the whole week''s min..max), max.');
end;

{ ---------- TSearchPanelWidget ---------- }

const
  SPW = 1220;
  SPH = 58;
  BoxX0 = 140;      // input frame
  BoxX1 = 720;
  BoxY0 = 13;
  BoxY1 = 45;
  BtnX0: array[0..1] of single = (736, 870);
  BtnW = 122;
  BtnCaption: array[0..1] of string = ('SEARCH', 'REFRESH');

constructor TSearchPanelWidget.Create;
begin
  inherited Create;
  SetView(SPW, SPH);
  HoverBtn := -1;
  FlashBtn := -1;
end;

class function TSearchPanelWidget.UIName: string;
begin
  Result := 'Location Panel';
end;

class function TSearchPanelWidget.UIDescription: string;
begin
  Result := 'City input in a HUD frame, SEARCH and REFRESH buttons, loading / update status.';
end;

function TSearchPanelWidget.ButtonAt(lx, ly: single): integer;
var
  i: integer;
begin
  Result := -1;
  if (ly < BoxY0) or (ly > BoxY1) then Exit;
  for i := 0 to 1 do
    if (lx >= BtnX0[i]) and (lx <= BtnX0[i] + BtnW) then Exit(i);
end;

procedure TSearchPanelWidget.Flash(btn: integer);
begin
  FlashBtn := btn;
  FlashT0 := T;
end;

procedure TSearchPanelWidget.DrawStatic;
var
  i: integer;
  x0: single;
begin
  FillPoly([0, 10, 10, 0, SPW, 0, SPW, SPH - 10, SPW - 10, SPH, 0, SPH], Steel(45));
  Polygon([0, 10, 10, 0, SPW, 0, SPW, SPH - 10, SPW - 10, SPH, 0, SPH], 1.3, Ice(180));
  Line(0, 14, 0, 44, 3, White);
  for i := 0 to 4 do
    Line(SPW - 52 + i * 7, 8, SPW - 45 + i * 7, 1, 2, White(200));
  Txt(16, 29, '\\LOCATION', 8, White(230));
  // magnifier glyph
  Ring(118, 27, 7, 1.6, Ice(220));
  Line(123, 32, 129, 38, 2, Ice(220));
  // input frame (the TEdit sits inside it)
  FillPoly([BoxX0 + 6, BoxY0, BoxX1, BoxY0, BoxX1, BoxY1 - 6, BoxX1 - 6, BoxY1, BoxX0, BoxY1, BoxX0, BoxY0 + 6],
    BGRA(14, 30, 50));
  // buttons
  for i := 0 to 1 do
  begin
    x0 := BtnX0[i];
    FillPoly([x0 + 6, BoxY0, x0 + BtnW, BoxY0, x0 + BtnW, BoxY1 - 6, x0 + BtnW - 6, BoxY1, x0, BoxY1, x0, BoxY0 + 6],
      Steel(90 + 40 * Ord(i = 0)));
    Polygon([x0 + 6, BoxY0, x0 + BtnW, BoxY0, x0 + BtnW, BoxY1 - 6, x0 + BtnW - 6, BoxY1, x0, BoxY1, x0, BoxY0 + 6],
      1.2, Ice(210));
    Txt(x0 + BtnW / 2, (BoxY0 + BoxY1) / 2, BtnCaption[i], 8.5, White, taCenter);
  end;
end;

procedure TSearchPanelWidget.DrawDynamic;
var
  x0, age: single;
  edge: TBGRAPixel;
begin
  // input frame: brighter while typing
  if EditFocused then edge := White else edge := Ice(180);
  Polygon([BoxX0 + 6, BoxY0, BoxX1, BoxY0, BoxX1, BoxY1 - 6, BoxX1 - 6, BoxY1, BoxX0, BoxY1, BoxX0, BoxY0 + 6],
    1.4 + 0.8 * Ord(EditFocused), edge);
  if HoverBtn >= 0 then
  begin
    x0 := BtnX0[HoverBtn];
    FillPoly([x0 + 6, BoxY0, x0 + BtnW, BoxY0, x0 + BtnW, BoxY1 - 6, x0 + BtnW - 6, BoxY1, x0, BoxY1, x0, BoxY0 + 6],
      White(40));
    Polygon([x0 + 6, BoxY0, x0 + BtnW, BoxY0, x0 + BtnW, BoxY1 - 6, x0 + BtnW - 6, BoxY1, x0, BoxY1, x0, BoxY0 + 6],
      2, White);
  end;
  if FlashBtn >= 0 then
  begin
    age := T - FlashT0;
    x0 := BtnX0[FlashBtn];
    if (age >= 0) and (age < 0.3) then
      Polygon([x0 - 3, BoxY0 - 3, x0 + BtnW + 3, BoxY0 - 3, x0 + BtnW + 3, BoxY1 + 3, x0 - 3, BoxY1 + 3], 2.5,
        White(Round(255 * (1 - age / 0.3))));
  end;
  // status at the right
  if Loading then
  begin
    Arc(1018, 29, 10, T * 360, T * 360 + 100, 2.5, Ice);
    Arc(1018, 29, 10, T * 360 + 180, T * 360 + 280, 2.5, Ice);
    TxtCached(1036, 29, 'LOADING...', 8, taLeftJustify);
  end
  else
  begin
    TxtCached(1010, 21, FitText(StatusText, 32), 7, taLeftJustify, Ice(220));
    TxtCached(1010, 38, FitText(CoordText, 32), 6.5, taLeftJustify, Ice(150));
  end;
end;

procedure TSearchPanelWidget.DefineDirty;
begin
  AddDirty(BoxX0 - 4, 6, SPW - 60, SPH - 6);
end;

procedure TSearchPanelWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 1220 x 58.');
  L.Add(Format('  Input     frame x %d..%d, y %d..%d; a styled TEdit is placed inside it', [BoxX0, BoxX1, BoxY0, BoxY1]));
  L.Add('           (HUDPanels.PlaceControl); the border brightens while typing');
  L.Add('  Buttons   SEARCH (x 736) and REFRESH (x 870), 122 wide, chamfered, hover =');
  L.Add('           white outline + wash, press = fading frame');
  L.Add('  Status    spinning arcs + LOADING..., or update time and coordinates');
end;

{ ---------- THUDWeatherWidget ---------- }

constructor THUDWeatherWidget.Create;
var
  ini: TIniFile;

  procedure Bind(W: TWeatherBase);
  begin
    W.FData := @Data;
    W.FUnitF := @FUnitF;
  end;

begin
  inherited Create;
  SetView(1240, 768);
  SetParamByName('Max zoom', 2);
  SetParamByName('Glow intensity', 0.9);
  FRefreshMin := 15;
  AddParam('Fahrenheit', 'Weather', '1 = temperatures in °F, 0 = °C.', FUnitF, 0, 1, 0, False);
  AddParam('Refresh minutes', 'Weather', 'Automatic refresh interval.', FRefreshMin, 1, 240, 0, False);
  Search := TSearchPanelWidget.Create; Bind(Search); AddChild(Search, 10, 10, 'Location panel');
  Current := TCurrentWidget.Create;   Bind(Current);  AddChild(Current, 10, 78, 'Current conditions');
  Wind := TWindWidget.Create;         Bind(Wind);     AddChild(Wind, 620, 78, 'Wind compass');
  Sun := TSunWidget.Create;           Bind(Sun);      AddChild(Sun, 930, 78, 'Sun arc');
  Hourly := THourlyWidget.Create;     Bind(Hourly);   AddChild(Hourly, 10, 388, 'Next 24 hours');
  Daily := TDailyWidget.Create;       Bind(Daily);    AddChild(Daily, 920, 388, '7-day forecast');
  Humidity := TPillLoaderWidget.Create;
  Humidity.Caption := 'HUMIDITY';
  Humidity.SetParamByName('Auto progress', 0);
  AddChild(Humidity, 10, 658, 'Humidity (Pill Loader)');
  Clouds := TBlockLoaderWidget.Create;
  Clouds.Caption := 'CLOUD COVER';
  Clouds.SetParamByName('Auto progress', 0);
  AddChild(Clouds, 310, 658, 'Cloud cover (Block Loader)');
  Rain := TChevronLoaderWidget.Create;
  Rain.Caption := 'RAIN CHANCE TODAY';
  Rain.SetParamByName('Auto progress', 0);
  AddChild(Rain, 610, 658, 'Rain chance (Chevron Loader)');
  City := 'Bangkok';
  if FileExists(IniFile) then
  begin
    ini := TIniFile.Create(IniFile);
    try
      City := ini.ReadString('Weather', 'City', City);
    finally
      ini.Free;
    end;
  end;
  Data := Default(TWeatherData);
  Data.City := City;
  Data.Status := 'Loading...';
end;

class function THUDWeatherWidget.UIName: string;
begin
  Result := 'HUD Weather';
end;

class function THUDWeatherWidget.UIDescription: string;
begin
  Result := 'Weather in the HUD style from Open-Meteo: current conditions, wind, sun, next 24 hours and ' +
    '7 days. Type a city in the LOCATION panel and press Enter or SEARCH.';
end;

class function THUDWeatherWidget.UnitFile: string;
begin
  Result := 'HUDWeather\uhudweather.pas';
end;

function THUDWeatherWidget.IniFile: string;
begin
  Result := ExtractFilePath(Application.ExeName) + 'weather.ini';
end;

procedure THUDWeatherWidget.Request(const ACity: string);
begin
  if Loading or (Trim(ACity) = '') then Exit;
  Loading := True;
  City := Trim(ACity);
  LastRequest := Now;
  TWeatherFetch.Start(City, @Received);
end;

procedure THUDWeatherWidget.Received(const AData: TWeatherData);
var
  ini: TIniFile;
begin
  Loading := False;
  if AData.Valid then
  begin
    Data := AData;
    City := AData.City;
    try
      ini := TIniFile.Create(IniFile);
      try
        ini.WriteString('Weather', 'City', City);
      finally
        ini.Free;
      end;
    except
      // read-only folder: the city is just not remembered
    end;
  end
  else if not Data.Valid or Data.Demo then
    Data := MakeDemo(City, AData.Status)     // nothing real yet: show labelled demo data
  else
    Data.Status := 'Refresh failed: ' + AData.Status;  // keep the last good data
end;

procedure THUDWeatherWidget.DrawDynamic;
var
  ns, ew: string;
begin
  Search.Loading := Loading;
  if Data.Valid then
  begin
    if Data.Demo then
      Search.StatusText := 'DEMO DATA'
    else
      Search.StatusText := 'UPDATED ' + FormatDateTime('hh:nn', Data.Fetched) + '  ·  ' + UpperCase(Data.City);
    if Data.Lat >= 0 then ns := 'N' else ns := 'S';
    if Data.Lon >= 0 then ew := 'E' else ew := 'W';
    Search.CoordText := Format('%.2f%s  %.2f%s', [Abs(Data.Lat), ns, Abs(Data.Lon), ew]);
  end
  else
  begin
    Search.StatusText := 'NO DATA';
    Search.CoordText := '';
  end;
  if Data.Valid then
  begin
    Humidity.SetParamValue(Humidity.ParamIndex('Progress %'), Data.Humidity);
    Clouds.SetParamValue(Clouds.ParamIndex('Progress %'), Data.Cloud);
    Rain.SetParamValue(Rain.ParamIndex('Progress %'), Data.DRain[0]);
  end;
  if (not Loading) and (MinutesBetween(Now, LastRequest) >= FRefreshMin) then
    Request(City);
  inherited DrawDynamic;
end;

procedure THUDWeatherWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('Canvas 1240 x 768 design units.');
  L.Add('');
  L.Add('LAYOUT');
  for i := 0 to ChildCount - 1 do
    L.Add(Format('  %-28s %-20s (%4.0f,%4.0f)', [ChildCaption(i), Children[i].ClassName,
      ChildOrigin(i).x, ChildOrigin(i).y]));
  L.Add('');
  L.Add('DATA (uweatherdata.pas)');
  L.Add('  Open-Meteo geocoding (city -> lat/lon) + forecast (current, hourly, daily,');
  L.Add('  timezone=auto) over HTTPS with WinINet, in a background thread.');
  L.Add('  Refresh: toolbar, or every "Refresh minutes". City kept in weather.ini.');
  L.Add('  No connection and no data yet: labelled demo values; a failed refresh keeps');
  L.Add('  the last real data and shows the error.');
  L.Add('  Weather codes: WMO (0 clear .. 99 thunderstorm with hail) -> text + icon.');
end;

procedure THUDWeatherWidget.DescribeLive(L: TStrings);
var
  i: integer;
begin
  inherited DescribeLive(L);
  L.Add('City                ' + Data.City + ' ' + Data.Country);
  L.Add(Format('Coordinates         %.3f, %.3f  (%s)', [Data.Lat, Data.Lon, Data.TimeZone]));
  L.Add('Status              ' + BoolToStr(Loading, 'loading', Data.Status));
  L.Add(Format('Now                 %.1f °C, %s, wind %.0f km/h from %s', [Data.Temp, CodeText(Data.Code),
    Data.WindSpeed, Cardinal(Data.WindDir)]));
  L.Add('');
  L.Add('DAILY TABLE');
  for i := 0 to DaysShown - 1 do
    L.Add(Format('  %s  %5.1f .. %5.1f °C  rain %3.0f%%  UV %4.1f  %s', [FormatDateTime('ddd dd', Data.DDate[i]),
      Data.DMin[i], Data.DMax[i], Data.DRain[i], Data.DUV[i], CodeText(Data.DCode[i])]));
end;

{ ---------- location panel input and mouse ---------- }

type
  TWeatherInput = class(TComponent)
  private
    FForm: THUDHostForm;
    FCity: TEdit;
    function W: THUDWeatherWidget;
    function Local(px, py: integer; C: THUDWidget; out lx, ly: single): boolean;
    procedure SearchClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure CityKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure Leave(Sender: TObject);
    procedure Place(Sender: TObject);
    procedure Tick(Sender: TObject);
  end;

function TWeatherInput.W: THUDWeatherWidget;
begin
  Result := FForm.Widget as THUDWeatherWidget;
end;

function TWeatherInput.Local(px, py: integer; C: THUDWidget; out lx, ly: single): boolean;
var
  p, o: TPointF;
  i: integer;
begin
  Result := False;
  lx := 0;
  ly := 0;
  p := W.PixelToDesign(px, py);
  for i := 0 to W.ChildCount - 1 do
    if W.Children[i] = C then
    begin
      o := W.ChildOrigin(i);
      lx := p.x - o.x;
      ly := p.y - o.y;
      Exit((lx >= 0) and (ly >= 0) and (lx < C.DesignWidth) and (ly < C.DesignHeight));
    end;
end;

procedure TWeatherInput.SearchClick(Sender: TObject);
begin
  W.Search.Flash(0);
  W.Request(FCity.Text);
end;

procedure TWeatherInput.RefreshClick(Sender: TObject);
begin
  W.Search.Flash(1);
  FCity.Text := W.City;
  W.Request(W.City);
end;

procedure TWeatherInput.CityKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    SearchClick(nil);
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    FCity.Text := W.City;     // cancel the edit, keep the window open
    FForm.View.SetFocus;
    Key := 0;
  end;
end;

procedure TWeatherInput.Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  lx, ly: single;
begin
  W.Hourly.HoverOn := Local(X, Y, W.Hourly, lx, ly);
  W.Hourly.HX := lx;
  W.Hourly.HY := ly;
  if Local(X, Y, W.Search, lx, ly) then
    W.Search.HoverBtn := W.Search.ButtonAt(lx, ly)
  else
    W.Search.HoverBtn := -1;
end;

procedure TWeatherInput.Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  lx, ly: single;
begin
  FForm.View.SetFocus;
  if (Button = mbLeft) and Local(X, Y, W.Search, lx, ly) then
    case W.Search.ButtonAt(lx, ly) of
      0: SearchClick(nil);
      1: RefreshClick(nil);
    end;
end;

procedure TWeatherInput.Leave(Sender: TObject);
begin
  W.Hourly.HoverOn := False;
  W.Search.HoverBtn := -1;
end;

procedure TWeatherInput.Place(Sender: TObject);
var
  i: integer;
begin
  // keep the edit inside the HUD input frame at any window size
  for i := 0 to W.ChildCount - 1 do
    if W.Children[i] = W.Search then
      PlaceControl(FCity, W, W.ChildOrigin(i), BoxX0 + 10, BoxY0 + 6, BoxX1 - 8, BoxY1 - 6);
  FCity.Font.Height := -Max(10, Round(15 * W.Scale));
  W.Search.EditFocused := FCity.Focused;
end;

procedure TWeatherInput.Tick(Sender: TObject);
begin
  if W.Loading then
    FForm.SetStatus('Loading weather for ' + W.City + '...')
  else
    FForm.SetStatus('Weather: ' + W.Data.City + '   ' + W.Data.Status +
      '   Data: Open-Meteo (open-meteo.com), CC BY 4.0');
  if (FCity.Text = '') and not FCity.Focused then FCity.Text := W.City;
end;

procedure SetupWeather(AForm: THUDHostForm);
var
  i: integer;
  inp: TWeatherInput;
  T: TTimer;
begin
  if not (AForm.Widget is THUDWeatherWidget) then Exit;
  inp := TWeatherInput.Create(AForm);
  inp.FForm := AForm;
  // the city box lives inside the HUD location panel (no LCL toolbar)
  inp.FCity := TEdit.Create(AForm);
  inp.FCity.Parent := AForm.View;
  StyleControl(inp.FCity);
  inp.FCity.TextHint := 'Type a city, e.g. Bangkok, Tokyo, Paris - Enter to search';
  inp.FCity.OnKeyDown := @inp.CityKey;
  AForm.View.OnMouseMove := @inp.Move;
  AForm.View.OnMouseDown := @inp.Down;
  AForm.View.OnMouseLeave := @inp.Leave;
  AForm.View.OnAfterPaint := @inp.Place;
  T := TTimer.Create(AForm);
  T.Interval := 500;
  T.OnTimer := @inp.Tick;
  // HUDWeather.exe --city "Tokyo"  (anywhere on the command line)
  for i := 1 to ParamCount - 1 do
    if ParamStr(i) = '--city' then
      (AForm.Widget as THUDWeatherWidget).City := ParamStr(i + 1);
  inp.FCity.Text := (AForm.Widget as THUDWeatherWidget).City;
  with AForm.Widget as THUDWeatherWidget do
    if (ParamStr(1) = '--shot') or (ParamStr(1) = '--info') then
    begin
      // one-frame renders need the data now: fetch synchronously
      try
        Received(FetchWeather(City));
      except
        on E: Exception do Received(MakeDemo(City, E.Message));
      end;
      LastRequest := Now;
    end
    else
      Request(City);
end;

initialization
  HostSetupProc := @SetupWeather;

end.
