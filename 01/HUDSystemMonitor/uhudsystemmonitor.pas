unit UHUDSystemMonitor;

{ HUD System Monitor - a real dashboard built from the Sci-Fi HUD kit.
  Live Windows data (USysMonitor) drives the kit's widgets:

    CPU load      -> Chevron loader %, Optic Scanner speed, Hex Core pulse
    Memory        -> Pill loader %, Shield Core pulse
    Disk C:       -> Block loader %
    Network       -> Slant loader % (log scale), Target Lock + Crosshair speed
    Alerts        -> HUD Icon Set warnings blink (CPU > 85 % or RAM > 90 %)
    Exact values  -> System Status readout panel (TSysReadoutWidget)

  The widgets are the same classes as the single programs; this unit only
  adds the layout, two small dashboard widgets and the data binding. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, DateUtils, BGRABitmap, BGRABitmapTypes, HUDCore, USysMonitor,
  UOpticScanner, UTargetLock, UShieldCore, UHUDIconSet, URadarSweep, UHexCore,
  UTargetCrosshair, UChevronLoader, UPillLoader, UBlockLoader, USlantLoader;

type

  { TCaptionWidget - static section title with an underline }

  TCaptionWidget = class(THUDWidget)
  private
    FText: string;
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
  public
    constructor CreateText(const AText: string);
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  end;

  { TSysReadoutWidget - clock and exact readings in a HUD frame }

  TSysReadoutWidget = class(THUDWidget)
  private
    FMon: TSysMonitor;
    FAlert: string;            // '' = nominal
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

  { THUDSystemMonitorWidget - the dashboard }

  THUDSystemMonitorWidget = class(THUDComposite)
  private
    FMon: TSysMonitor;
    FSampleMs: single;         // sampling interval (param)
    FSmoothing: single;        // 1/s, how fast the gauges follow the data
    FCpuAlert, FMemAlert: single;
    FLastSample, FLastFrame: double;
    FCpu, FMem, FDisk, FNet: double;     // smoothed percentages
    FAlertOn: boolean;
    FOptic: TOpticScannerWidget;
    FLock: TTargetLockWidget;
    FShield: TShieldCoreWidget;
    FIcons: THUDIconSetWidget;
    FHex: THexCoreWidget;
    FCross: TTargetCrosshairWidget;
    FCpuBar: TChevronLoaderWidget;
    FMemBar: TPillLoaderWidget;
    FDiskBar: TBlockLoaderWidget;
    FNetBar: TSlantLoaderWidget;
    FReadout: TSysReadoutWidget;
    function NetPercent: double;
    procedure Drive(W: THUDWidget; const AParam: string; v: double);
    procedure UpdateData;
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
  end;

implementation

const
  NetFullScale = 100 * 1024 * 1024;  // 100 MB/s = 100 % on the network gauge

{ ---------- TCaptionWidget ---------- }

constructor TCaptionWidget.CreateText(const AText: string);
begin
  Create;
  FText := AText;
  SetView(200, 24);
end;

class function TCaptionWidget.UIName: string;
begin
  Result := 'Caption';
end;

class function TCaptionWidget.UIDescription: string;
begin
  Result := 'Static section title with a split underline (dashboard helper).';
end;

class function TCaptionWidget.UnitFile: string;
begin
  Result := 'HUDSystemMonitor\uhudsystemmonitor.pas';
end;

procedure TCaptionWidget.DrawStatic;
begin
  Txt(100, 9, FText, 8, Ice(230), taCenter);
  Line(10, 19, 190, 19, 1, Ice(120));
  Line(70, 19, 130, 19, 2.5, White);
  FillPoly([4, 15, 10, 15, 10, 23, 4, 23], White(200));
  FillPoly([190, 15, 196, 15, 196, 23, 190, 23], White(200));
end;

procedure TCaptionWidget.DrawDynamic;
begin
end;

procedure TCaptionWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 200 x 24. Text "' + FText + '" size 8 Ice a230 centred at y 9,');
  L.Add('underline w1 Ice a120 (x 10..190) with a bright w2.5 centre (x 70..130),');
  L.Add('end blocks 6 x 8 White a200. Static only.');
end;

{ ---------- TSysReadoutWidget ---------- }

const
  RW = 440;   // readout view
  RH = 340;
  RowY0 = 128;
  RowStep = 23;
  RowLabels: array[0..7] of string =
    ('UPTIME', 'PROCESSES', 'CPU', 'MEMORY', 'DISK C:', 'NET DOWN', 'NET UP', 'LINK');

constructor TSysReadoutWidget.Create;
begin
  inherited Create;
  SetView(RW, RH);
end;

class function TSysReadoutWidget.UIName: string;
begin
  Result := 'System Status';
end;

class function TSysReadoutWidget.UIDescription: string;
begin
  Result := 'Readout panel: clock, date and the exact system readings (uptime, processes, CPU, ' +
    'memory, disk, network) plus the alert status line.';
end;

class function TSysReadoutWidget.UnitFile: string;
begin
  Result := 'HUDSystemMonitor\uhudsystemmonitor.pas';
end;

procedure TSysReadoutWidget.DrawStatic;
var
  i: integer;
begin
  // frame in the Data Frames style
  FillPoly([0, 12, 12, 0, 300, 0, 312, 12, RW, 12, RW, RH - 12, RW - 12, RH, 0, RH], Steel(50));
  Polygon([0, 12, 12, 0, 300, 0, 312, 12, RW, 12, RW, RH - 12, RW - 12, RH, 0, RH], 1.5, Ice(200));
  for i := 0 to 6 do
    Line(250 + i * 7, 9, 257 + i * 7, 2, 2, White(200));
  Line(RW, 60, RW, 140, 3, White);
  Line(0, 200, 0, 260, 3, White(220));
  Txt(14, 14, '\\SYSTEM STATUS', 7, White(230));
  if FMon <> nil then
    Txt(RW - 14, 26, 'HOST ' + UpperCase(FMon.HostName), 6.5, Ice(200), taRightJustify);
  // clock underline
  Line(80, 100, RW - 80, 100, 1, Ice(130));
  Line(180, 100, RW - 180, 100, 2.5, White);
  // row labels and separators
  for i := 0 to High(RowLabels) do
  begin
    Txt(24, RowY0 + i * RowStep, RowLabels[i], 8, Ice(210));
    Line(24, RowY0 + i * RowStep + 11, RW - 24, RowY0 + i * RowStep + 11, 0.6, Ice(60));
  end;
  // status bar track
  FillPoly([20, RH - 42, RW - 20, RH - 42, RW - 30, RH - 20, 20, RH - 20], Navy(200));
  Polygon([20, RH - 42, RW - 20, RH - 42, RW - 30, RH - 20, 20, RH - 20], 1, Ice(160));
end;

procedure TSysReadoutWidget.DrawDynamic;
var
  v: array[0..7] of string;
  i: integer;
  nowDT: TDateTime;
  blink: boolean;
begin
  if FMon = nil then Exit;
  nowDT := Now;
  TxtCached(RW / 2, 66, FormatDateTime('hh:nn:ss', nowDT), 30, taCenter);
  TxtCached(RW / 2, 112, UpperCase(FormatDateTime('ddd dd mmm yyyy', nowDT)), 8, taCenter);
  v[0] := FormatUptime(FMon.UptimeSec);
  v[1] := IntToStr(FMon.Processes);
  v[2] := Format('%.1f %%  /  %d CORES', [FMon.CpuPercent, FMon.Cores]);
  v[3] := Format('%s / %s', [FormatBytes(FMon.MemUsed), FormatBytes(FMon.MemTotal)]);
  v[4] := Format('%s / %s', [FormatBytes(FMon.DiskUsed), FormatBytes(FMon.DiskTotal)]);
  v[5] := FormatRate(FMon.NetRxRate);
  v[6] := FormatRate(FMon.NetTxRate);
  if FMon.NetLinkSpeed > 0 then
    v[7] := Format('%.0f MBIT/S', [FMon.NetLinkSpeed / 1e6])
  else
    v[7] := 'UNKNOWN';
  for i := 0 to High(v) do
    TxtCached(RW - 24, RowY0 + i * RowStep, v[i], 9, taRightJustify);
  // status line: steady when nominal, blinking when alerting
  blink := Frac(T * 1.5) < 0.6;
  if FAlert = '' then
  begin
    FillPoly([24, RH - 38, 60, RH - 38, 56, RH - 24, 24, RH - 24], Ice(200));
    TxtCached(70, RH - 31, 'STATUS: NOMINAL', 8, taLeftJustify);
  end
  else
  begin
    if blink then
      FillPoly([24, RH - 38, RW - 24, RH - 38, RW - 33, RH - 24, 24, RH - 24], Steel(220));
    TxtCached(32, RH - 31, 'ALERT: ' + FAlert, 8, taLeftJustify);
  end;
end;

procedure TSysReadoutWidget.DefineDirty;
begin
  AddDirty(60, 40, RW - 60, 120);                                   // clock + date
  AddDirty(150, RowY0 - 9, RW - 22, RowY0 + 7 * RowStep + 9);      // values
  AddDirty(22, RH - 40, RW - 22, RH - 22);                          // status line
end;

procedure TSysReadoutWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add(Format('View %d x %d.', [RW, RH]));
  L.Add('');
  L.Add('STATIC');
  L.Add('  Frame           chamfered polygon Steel a50, border w1.5 Ice a200, hatching,');
  L.Add('                  side accents (right x=440 y60..140, left y200..260)');
  L.Add('  Title           "\\SYSTEM STATUS" size 7, host name size 6.5 right');
  L.Add('  Clock rule      y 100, w1 Ice a130 + bright w2.5 centre');
  L.Add(Format('  Rows            %d labels size 8 Ice a210 from y %d every %d, separators w0.6', [Length(RowLabels), RowY0, RowStep]));
  for i := 0 to High(RowLabels) do
    L.Add('                    ' + RowLabels[i]);
  L.Add('  Status track    navy bar at the bottom');
  L.Add('');
  L.Add('DYNAMIC (all texts are TxtCached bitmaps)');
  L.Add('  Clock           hh:nn:ss size 30 centred at y 66, date size 8 at y 112');
  L.Add('  Values          right-aligned at x = 416, size 9, one per row');
  L.Add('  Status          "STATUS: NOMINAL" with a steady marker, or "ALERT: ..." with a');
  L.Add('                  blinking Steel bar (1.5 Hz)');
  L.Add('');
  L.Add('DIRTY RECTS       clock, value column, status line');
end;

procedure TSysReadoutWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  if FAlert = '' then L.Add('Status              nominal') else L.Add('Status              ALERT ' + FAlert);
end;

{ ---------- THUDSystemMonitorWidget ---------- }

constructor THUDSystemMonitorWidget.Create;
var
  radar: THUDWidget;
begin
  inherited Create;
  SetView(1120, 700);
  SetParamByName('Max zoom', 2);
  FSampleMs := 500;
  FSmoothing := 4;
  FCpuAlert := 85;
  FMemAlert := 90;
  AddParam('Sample interval ms', 'Data', 'How often the system is sampled (milliseconds).',
    FSampleMs, 100, 5000, 0, False);
  AddParam('Gauge smoothing', 'Data', 'How fast the gauges follow the data (1/s). Higher = snappier.',
    FSmoothing, 0.5, 30, 1, False);
  AddParam('CPU alert %', 'Alerts', 'CPU load that starts the alert (clears 5 points lower).',
    FCpuAlert, 10, 100, 0, False);
  AddParam('Memory alert %', 'Alerts', 'Memory use that starts the alert (clears 3 points lower).',
    FMemAlert, 10, 100, 0, False);

  FMon := TSysMonitor.Create;

  // top row: three big instruments with captions
  FOptic := TOpticScannerWidget.Create;
  FOptic.SetParamByName('Label number', FMon.Cores);
  AddChild(FOptic, 0, 5, 'CPU core (Optic Scanner)');
  AddChild(TCaptionWidget.CreateText('CPU CORE'), 110, 292, 'Caption CPU');
  FLock := TTargetLockWidget.Create;
  AddChild(FLock, 410, 0, 'Network link (Target Lock)');
  AddChild(TCaptionWidget.CreateText('NETWORK LINK'), 470, 292, 'Caption network');
  FShield := TShieldCoreWidget.Create;
  AddChild(FShield, 730, 5, 'Memory (Shield Core)');
  AddChild(TCaptionWidget.CreateText('MEMORY SHIELD'), 780, 292, 'Caption memory');

  // bottom left: the four loaders, one per resource
  FCpuBar := TChevronLoaderWidget.Create;
  FCpuBar.Caption := 'CPU LOAD';
  FCpuBar.SetParamByName('Auto progress', 0);
  AddChild(FCpuBar, 10, 335, 'CPU load (Chevron Loader)');
  FMemBar := TPillLoaderWidget.Create;
  FMemBar.Caption := 'MEMORY';
  FMemBar.SetParamByName('Auto progress', 0);
  AddChild(FMemBar, 10, 425, 'Memory (Pill Loader)');
  FDiskBar := TBlockLoaderWidget.Create;
  FDiskBar.Caption := 'DISK C:';
  FDiskBar.SetParamByName('Auto progress', 0);
  AddChild(FDiskBar, 10, 515, 'Disk C: (Block Loader)');
  FNetBar := TSlantLoaderWidget.Create;
  FNetBar.Caption := 'NETWORK';
  FNetBar.SetParamByName('Auto progress', 0);
  AddChild(FNetBar, 10, 605, 'Network (Slant Loader)');

  // bottom middle: exact readings
  FReadout := TSysReadoutWidget.Create;
  FReadout.FMon := FMon;
  AddChild(FReadout, 330, 340, 'System Status readout');

  // bottom right: small instruments and the alert icons
  radar := TRadarSweepWidget.Create;
  AddChild(radar, 790, 335, 'Radar Sweep');
  FHex := THexCoreWidget.Create;
  AddChild(FHex, 905, 340, 'CPU pulse (Hex Core)');
  FCross := TTargetCrosshairWidget.Create;
  AddChild(FCross, 1005, 340, 'Network activity (Crosshair)');
  AddChild(TCaptionWidget.CreateText('ACTIVITY'), 855, 455, 'Caption activity');
  FIcons := THUDIconSetWidget.Create;
  AddChild(FIcons, 790, 500, 'Alerts (HUD Icon Set)');
  AddChild(TCaptionWidget.CreateText('ALERTS'), 855, 635, 'Caption alerts');

  FLastSample := NowMs;
  FLastFrame := FLastSample;
  UpdateData;
end;

destructor THUDSystemMonitorWidget.Destroy;
begin
  inherited Destroy;
  FMon.Free;
end;

class function THUDSystemMonitorWidget.UIName: string;
begin
  Result := 'HUD System Monitor';
end;

class function THUDSystemMonitorWidget.UIDescription: string;
begin
  Result := 'Live system dashboard built from the Sci-Fi HUD kit: CPU, memory, disk C:, network, ' +
    'processes, uptime and alerts. Click a gauge to inspect the UI behind it.';
end;

class function THUDSystemMonitorWidget.UnitFile: string;
begin
  Result := 'HUDSystemMonitor\uhudsystemmonitor.pas';
end;

function THUDSystemMonitorWidget.NetPercent: double;
var
  rate: double;
begin
  // log scale: 1 KB/s is visible, 100 MB/s fills the gauge
  rate := FMon.NetRxRate + FMon.NetTxRate;
  Result := EnsureRange(100 * Ln(1 + rate / 1024) / Ln(1 + NetFullScale / 1024), 0, 100);
end;

procedure THUDSystemMonitorWidget.Drive(W: THUDWidget; const AParam: string; v: double);
begin
  // like a user edit, but the reset value stays the widget's own default
  W.SetParamValue(W.ParamIndex(AParam), v);
end;

procedure THUDSystemMonitorWidget.UpdateData;
var
  blend, tNow: double;
  alert: string;
begin
  tNow := NowMs;
  if tNow - FLastSample >= FSampleMs then
  begin
    FMon.Sample;
    FLastSample := tNow;
  end;
  // exponential smoothing so the gauges glide between samples
  blend := 1 - Exp(-(tNow - FLastFrame) / 1000 * FSmoothing);
  FLastFrame := tNow;
  FCpu += (FMon.CpuPercent - FCpu) * blend;
  FMem += (FMon.MemPercent - FMem) * blend;
  FDisk += (FMon.DiskPercent - FDisk) * blend;
  FNet += (NetPercent - FNet) * blend;

  Drive(FCpuBar, 'Progress %', FCpu);
  Drive(FMemBar, 'Progress %', FMem);
  Drive(FDiskBar, 'Progress %', FDisk);
  Drive(FNetBar, 'Progress %', FNet);
  Drive(FOptic, 'Rotation speed', 8 + 1.6 * FCpu);
  Drive(FHex, 'Pulse rate', 1 + 0.12 * FCpu);
  Drive(FShield, 'Pulse rate', 1 + 0.08 * FMem);
  Drive(FLock, 'Rotation speed', 5 + 1.5 * FNet);
  Drive(FCross, 'Spin speed', 15 + 3 * FNet);

  // alerts with hysteresis
  if FAlertOn then
    FAlertOn := (FCpu > FCpuAlert - 5) or (FMem > FMemAlert - 3)
  else
    FAlertOn := (FCpu > FCpuAlert) or (FMem > FMemAlert);
  alert := '';
  if FAlertOn then
  begin
    if FCpu > FCpuAlert - 5 then alert := Format('CPU %.0f%%', [FCpu]);
    if FMem > FMemAlert - 3 then
    begin
      if alert <> '' then alert += '  ';
      alert += Format('MEMORY %.0f%%', [FMem]);
    end;
  end;
  FReadout.FAlert := alert;
  // blink rate is a static parameter (it changes the dirty rects): set on change only
  if FAlertOn <> (FIcons.Params[FIcons.ParamIndex('Alert blink rate')].Value^ > 0) then
    Drive(FIcons, 'Alert blink rate', IfThen(FAlertOn, 2, 0));
end;

procedure THUDSystemMonitorWidget.DrawDynamic;
begin
  UpdateData;
  inherited DrawDynamic;
end;

procedure THUDSystemMonitorWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
  o: TPointF;
begin
  L.Add('Canvas 1120 x 700 design units.');
  L.Add('');
  L.Add('DATA BINDING (THUDSystemMonitorWidget.UpdateData)');
  L.Add('  CPU %           -> Chevron Loader Progress %, Optic Scanner speed 8 + 1.6 cpu,');
  L.Add('                     Hex Core pulse 1 + 0.12 cpu');
  L.Add('  Memory %        -> Pill Loader Progress %, Shield Core pulse 1 + 0.08 mem');
  L.Add('  Disk C: %       -> Block Loader Progress %');
  L.Add('  Network         -> Slant Loader % = 100 ln(1 + rate/1KB) / ln(1 + 100MB/1KB),');
  L.Add('                     Target Lock speed 5 + 1.5 net, Crosshair spin 15 + 3 net');
  L.Add('  Alerts          -> CPU > CPU alert % or memory > Memory alert % (hysteresis)');
  L.Add('                     -> HUD Icon Set blink 2 Hz + ALERT line in the readout');
  L.Add('  Readout         <- exact values from TSysMonitor (usysmonitor.pas)');
  L.Add('  Gauges follow the samples with exponential smoothing (Gauge smoothing).');
  L.Add('');
  L.Add('DATA SOURCES (Windows API, usysmonitor.pas)');
  L.Add('  CPU      GetSystemTimes (idle vs kernel + user since the last sample)');
  L.Add('  Memory   GlobalMemoryStatusEx      Disk  DiskSize / DiskFree (C:)');
  L.Add('  Network  GetIfTable (Ethernet/Wi-Fi, operational, filter duplicates removed)');
  L.Add('  Procs    EnumProcesses             Uptime GetTickCount64');
  L.Add('');
  L.Add('LAYOUT');
  L.Add(Format('%-32s %-24s %s', ['UI', 'Class', 'Origin']));
  for i := 0 to ChildCount - 1 do
  begin
    o := ChildOrigin(i);
    L.Add(Format('%-32s %-24s (%4.0f,%4.0f)', [ChildCaption(i), Children[i].ClassName, o.x, o.y]));
  end;
end;

procedure THUDSystemMonitorWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('CPU                 %.1f %%  (gauge %.1f)', [FMon.CpuPercent, FCpu]));
  L.Add(Format('Memory              %.1f %%  %s / %s', [FMon.MemPercent, FormatBytes(FMon.MemUsed), FormatBytes(FMon.MemTotal)]));
  L.Add(Format('Disk C:             %.1f %%  %s / %s', [FMon.DiskPercent, FormatBytes(FMon.DiskUsed), FormatBytes(FMon.DiskTotal)]));
  L.Add(Format('Network down / up   %s / %s  (gauge %.1f %%)', [FormatRate(FMon.NetRxRate), FormatRate(FMon.NetTxRate), FNet]));
  L.Add(Format('Processes           %d', [FMon.Processes]));
  L.Add(Format('Uptime              %s', [FormatUptime(FMon.UptimeSec)]));
  L.Add(Format('Samples taken       %d', [FMon.Samples]));
  L.Add('Alert               ' + BoolToStr(FAlertOn, 'ON', 'off'));
end;

end.
