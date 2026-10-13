unit UWeatherData;

{ Weather data for HUD Weather.

  Source: Open-Meteo (https://open-meteo.com, free, no API key):
    geocoding  https://geocoding-api.open-meteo.com/v1/search?name=<city>&count=1
    forecast   https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..
               &current=...&hourly=...&daily=...&timezone=auto&forecast_days=7
  HTTP: WinINet (Windows' own HTTPS stack, no OpenSSL DLLs needed), run in a
  background thread (TWeatherFetch) so the window never freezes.
  Without a connection the caller can fall back to MakeDemo (marked Demo). }

{$mode objfpc}{$H+}

interface

uses
  Windows, WinInet, Classes, SysUtils, Math, DateUtils, fpjson, jsonparser;

const
  HoursShown = 24;
  DaysShown = 7;

type
  TWeatherData = record
    Valid, Demo: boolean;
    Status: string;            // last error / note
    City, Country: string;
    Lat, Lon: double;
    TimeZone: string;
    LocalNow: TDateTime;       // "current.time" at the location
    Fetched: TDateTime;        // local clock of this PC
    // current
    Temp, Feels, Humidity, Precip, Cloud, Pressure, WindSpeed, WindDir, Gust: double;
    Code: integer;
    IsDay: boolean;
    // next 24 hours (from the current hour)
    HTime: array[0..HoursShown - 1] of TDateTime;
    HTemp, HRain: array[0..HoursShown - 1] of double;
    HCode: array[0..HoursShown - 1] of integer;
    // 7 days
    DDate: array[0..DaysShown - 1] of TDateTime;
    DCode: array[0..DaysShown - 1] of integer;
    DMax, DMin, DUV, DRain: array[0..DaysShown - 1] of double;
    DSunrise, DSunset: array[0..DaysShown - 1] of TDateTime;
  end;

  TWeatherDone = procedure(const AData: TWeatherData) of object;

  { TWeatherFetch - downloads + parses in a thread, reports on the main thread }

  TWeatherFetch = class(TThread)
  private
    FCity: string;
    FResult: TWeatherData;
    FOnDone: TWeatherDone;
    procedure Deliver;
  protected
    procedure Execute; override;
  public
    constructor Start(const ACity: string; AOnDone: TWeatherDone);
  end;

function FetchWeather(const ACity: string): TWeatherData;   // blocking
function MakeDemo(const ACity, AReason: string): TWeatherData;
function CodeText(code: integer): string;
function CodeKind(code: integer): integer;  // 0 clear 1 partly 2 cloudy 3 fog 4 drizzle 5 rain 6 snow 7 storm
function Cardinal(deg: double): string;
function HttpGet(const AUrl: string): string;
function UrlEncode(const S: string): string;

implementation

function UrlEncode(const S: string): string;
var
  i: integer;
begin
  // S is UTF-8: percent-encode every byte except unreserved characters
  Result := '';
  for i := 1 to Length(S) do
    if S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'] then
      Result += S[i]
    else
      Result += '%' + IntToHex(Ord(S[i]), 2);
end;

function HttpGet(const AUrl: string): string;
var
  hNet, hUrl: HINTERNET;
  buf: array[0..16383] of byte;
  got: DWORD;
  ms: TStringStream;
  status, len, idx: DWORD;
begin
  Result := '';
  hNet := InternetOpenW('HUDWeather/1.0', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if hNet = nil then raise Exception.CreateFmt('No internet API (%d)', [GetLastError]);
  try
    hUrl := InternetOpenUrlW(hNet, PWideChar(UnicodeString(AUrl)), nil, 0,
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_SECURE, 0);
    if hUrl = nil then raise Exception.CreateFmt('Cannot connect (WinINet error %d)', [GetLastError]);
    try
      status := 0;
      len := SizeOf(status);
      idx := 0;
      if HttpQueryInfoW(hUrl, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @status, len, idx) and
         (status <> 200) then
        raise Exception.CreateFmt('Server answered HTTP %d', [status]);
      ms := TStringStream.Create('');
      try
        repeat
          got := 0;
          if not InternetReadFile(hUrl, @buf[0], SizeOf(buf), got) then
            raise Exception.CreateFmt('Read failed (%d)', [GetLastError]);
          if got > 0 then ms.WriteBuffer(buf[0], got);
        until got = 0;
        Result := ms.DataString;
      finally
        ms.Free;
      end;
    finally
      InternetCloseHandle(hUrl);
    end;
  finally
    InternetCloseHandle(hNet);
  end;
end;

function IsoToDateTime(const S: string): TDateTime;
var
  y, mo, d, h, mi: integer;
begin
  // "2026-10-14T02:00" or "2026-10-14"
  y := StrToIntDef(Copy(S, 1, 4), 2000);
  mo := StrToIntDef(Copy(S, 6, 2), 1);
  d := StrToIntDef(Copy(S, 9, 2), 1);
  h := StrToIntDef(Copy(S, 12, 2), 0);
  mi := StrToIntDef(Copy(S, 15, 2), 0);
  Result := EncodeDateTime(y, mo, d, h, mi, 0, 0);
end;

function Num(O: TJSONObject; const AName: string; ADefault: double = 0): double;
var
  D: TJSONData;
begin
  D := O.Find(AName);
  if (D = nil) or (D.JSONType = jtNull) then Result := ADefault else Result := D.AsFloat;
end;

function FetchWeather(const ACity: string): TWeatherData;
var
  J, Cur, Hr, Dy, G: TJSONData;
  O: TJSONObject;
  url, body: string;
  i, start, n: integer;
  fs: TFormatSettings;
  times: TJSONArray;
begin
  Result := Default(TWeatherData);
  Result.City := ACity;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  // 1) city -> coordinates
  body := HttpGet('https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=' +
    UrlEncode(Trim(ACity)));
  G := GetJSON(body);
  try
    if (G.FindPath('results') = nil) or (TJSONArray(G.FindPath('results')).Count = 0) then
      raise Exception.CreateFmt('City "%s" not found', [ACity]);
    O := TJSONObject(TJSONArray(G.FindPath('results')).Items[0]);
    Result.City := O.Get('name', ACity);
    Result.Country := O.Get('country', '');
    Result.Lat := Num(O, 'latitude');
    Result.Lon := Num(O, 'longitude');
  finally
    G.Free;
  end;
  // 2) forecast
  url := Format('https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s' +
    '&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,' +
    'weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m' +
    '&hourly=temperature_2m,precipitation_probability,weather_code' +
    '&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,' +
    'precipitation_probability_max&timezone=auto&forecast_days=7',
    [FloatToStrF(Result.Lat, ffFixed, 8, 4, fs), FloatToStrF(Result.Lon, ffFixed, 8, 4, fs)]);
  J := GetJSON(HttpGet(url));
  try
    Result.TimeZone := TJSONObject(J).Get('timezone', '');
    Cur := J.FindPath('current');
    if Cur = nil then raise Exception.Create('Unexpected answer (no "current")');
    O := TJSONObject(Cur);
    Result.LocalNow := IsoToDateTime(O.Get('time', ''));
    Result.Temp := Num(O, 'temperature_2m');
    Result.Feels := Num(O, 'apparent_temperature');
    Result.Humidity := Num(O, 'relative_humidity_2m');
    Result.Precip := Num(O, 'precipitation');
    Result.Cloud := Num(O, 'cloud_cover');
    Result.Pressure := Num(O, 'pressure_msl');
    Result.WindSpeed := Num(O, 'wind_speed_10m');
    Result.WindDir := Num(O, 'wind_direction_10m');
    Result.Gust := Num(O, 'wind_gusts_10m');
    Result.Code := Round(Num(O, 'weather_code'));
    Result.IsDay := Round(Num(O, 'is_day', 1)) = 1;
    // hourly: start at the current hour
    Hr := J.FindPath('hourly');
    times := TJSONArray(Hr.FindPath('time'));
    start := 0;
    for i := 0 to times.Count - 1 do
      if IsoToDateTime(times.Strings[i]) <= Result.LocalNow then start := i;
    for i := 0 to HoursShown - 1 do
    begin
      n := Min(start + i, times.Count - 1);
      Result.HTime[i] := IsoToDateTime(times.Strings[n]);
      Result.HTemp[i] := TJSONArray(Hr.FindPath('temperature_2m')).Items[n].AsFloat;
      if TJSONArray(Hr.FindPath('precipitation_probability')).Items[n].JSONType = jtNull then
        Result.HRain[i] := 0
      else
        Result.HRain[i] := TJSONArray(Hr.FindPath('precipitation_probability')).Items[n].AsFloat;
      Result.HCode[i] := TJSONArray(Hr.FindPath('weather_code')).Items[n].AsInteger;
    end;
    // daily
    Dy := J.FindPath('daily');
    for i := 0 to DaysShown - 1 do
    begin
      Result.DDate[i] := IsoToDateTime(TJSONArray(Dy.FindPath('time')).Strings[i]);
      Result.DCode[i] := TJSONArray(Dy.FindPath('weather_code')).Items[i].AsInteger;
      Result.DMax[i] := TJSONArray(Dy.FindPath('temperature_2m_max')).Items[i].AsFloat;
      Result.DMin[i] := TJSONArray(Dy.FindPath('temperature_2m_min')).Items[i].AsFloat;
      Result.DSunrise[i] := IsoToDateTime(TJSONArray(Dy.FindPath('sunrise')).Strings[i]);
      Result.DSunset[i] := IsoToDateTime(TJSONArray(Dy.FindPath('sunset')).Strings[i]);
      if TJSONArray(Dy.FindPath('uv_index_max')).Items[i].JSONType <> jtNull then
        Result.DUV[i] := TJSONArray(Dy.FindPath('uv_index_max')).Items[i].AsFloat;
      if TJSONArray(Dy.FindPath('precipitation_probability_max')).Items[i].JSONType <> jtNull then
        Result.DRain[i] := TJSONArray(Dy.FindPath('precipitation_probability_max')).Items[i].AsFloat;
    end;
  finally
    J.Free;
  end;
  Result.Valid := True;
  Result.Fetched := Now;
  Result.Status := 'Open-Meteo, ' + Result.TimeZone;
end;

function MakeDemo(const ACity, AReason: string): TWeatherData;
const
  DemoCodes: array[0..DaysShown - 1] of integer = (2, 61, 80, 3, 95, 1, 2);
  DemoRain: array[0..DaysShown - 1] of integer = (20, 70, 60, 30, 80, 10, 25);
var
  i: integer;
  base: TDateTime;
begin
  // plausible tropical values so the screen is never empty; clearly marked
  Result := Default(TWeatherData);
  Result.Valid := True;
  Result.Demo := True;
  Result.City := ACity;
  Result.Country := 'DEMO DATA';
  Result.Status := 'Offline demo - ' + AReason;
  Result.LocalNow := RecodeMinute(Now, 0);
  Result.Fetched := Now;
  Result.Temp := 29.4; Result.Feels := 34.1; Result.Humidity := 74; Result.Cloud := 40;
  Result.Pressure := 1009; Result.WindSpeed := 12; Result.WindDir := 225; Result.Gust := 24;
  Result.Code := 2;
  Result.IsDay := (HourOf(Now) >= 6) and (HourOf(Now) < 18);
  for i := 0 to HoursShown - 1 do
  begin
    Result.HTime[i] := Result.LocalNow + i / 24;
    Result.HTemp[i] := 28 + 4 * Sin((HourOf(Result.HTime[i]) - 9) / 24 * 2 * Pi);
    Result.HRain[i] := Max(0, 60 * Sin((HourOf(Result.HTime[i]) - 12) / 24 * 2 * Pi));
    if Result.HRain[i] > 40 then Result.HCode[i] := 61 else Result.HCode[i] := 2;
  end;
  base := Trunc(Now);
  for i := 0 to DaysShown - 1 do
  begin
    Result.DDate[i] := base + i;
    Result.DMax[i] := 32 + (i mod 3);
    Result.DMin[i] := 25 + (i mod 2);
    Result.DCode[i] := DemoCodes[i];
    Result.DRain[i] := DemoRain[i];
    Result.DUV[i] := 9 - (i mod 3);
    Result.DSunrise[i] := base + i + EncodeTime(6, 10, 0, 0);
    Result.DSunset[i] := base + i + EncodeTime(18, 5, 0, 0);
  end;
end;

function CodeText(code: integer): string;
begin
  case code of
    0: Result := 'Clear sky';
    1: Result := 'Mainly clear';
    2: Result := 'Partly cloudy';
    3: Result := 'Overcast';
    45, 48: Result := 'Fog';
    51, 53, 55: Result := 'Drizzle';
    56, 57: Result := 'Freezing drizzle';
    61: Result := 'Light rain';
    63: Result := 'Rain';
    65: Result := 'Heavy rain';
    66, 67: Result := 'Freezing rain';
    71, 73, 75, 77: Result := 'Snow';
    80, 81: Result := 'Rain showers';
    82: Result := 'Violent showers';
    85, 86: Result := 'Snow showers';
    95: Result := 'Thunderstorm';
    96, 99: Result := 'Thunderstorm, hail';
  else
    Result := Format('Code %d', [code]);
  end;
end;

function CodeKind(code: integer): integer;
begin
  case code of
    0: Result := 0;
    1, 2: Result := 1;
    3: Result := 2;
    45, 48: Result := 3;
    51..57: Result := 4;
    61..67, 80..82: Result := 5;
    71..77, 85, 86: Result := 6;
    95..99: Result := 7;
  else
    Result := 2;
  end;
end;

function Cardinal(deg: double): string;
const
  N: array[0..15] of string = ('N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW');
begin
  Result := N[Round(deg / 22.5) mod 16];
end;

{ TWeatherFetch }

constructor TWeatherFetch.Start(const ACity: string; AOnDone: TWeatherDone);
begin
  FCity := ACity;
  FOnDone := AOnDone;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TWeatherFetch.Execute;
begin
  try
    FResult := FetchWeather(FCity);
  except
    on E: Exception do
    begin
      FResult := Default(TWeatherData);
      FResult.Valid := False;
      FResult.City := FCity;
      FResult.Status := E.Message;
    end;
  end;
  Synchronize(@Deliver);
end;

procedure TWeatherFetch.Deliver;
begin
  if Assigned(FOnDone) then FOnDone(FResult);
end;

end.
