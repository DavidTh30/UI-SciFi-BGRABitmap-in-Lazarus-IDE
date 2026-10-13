unit USysMonitor;

{ Live system readings for the HUD System Monitor (Windows API, no extra
  packages): CPU load, memory, disk C:, network throughput, process count,
  uptime. Call Sample() periodically (e.g. every 500 ms); rates are computed
  from the difference with the previous sample. }

{$mode objfpc}{$H+}

interface

uses
  Windows, Classes, SysUtils, Math;

type

  { TSysMonitor }

  TSysMonitor = class
  private
    FLastIdle, FLastKernel, FLastUser: QWord;
    FLastRx, FLastTx: QWord;      // accumulated octets (32-bit counters unwrapped)
    FPrevIdx, FPrevRx32, FPrevTx32: array of DWORD;  // per interface (dwIndex)
    FLastSampleMs: QWord;
    FHaveCpu, FHaveNet: boolean;
    procedure SampleCpu;
    procedure SampleMemory;
    procedure SampleDisk;
    procedure SampleNet(dtSec: double);
    procedure SampleProcesses;
  public
    CpuPercent: double;           // 0..100, all cores
    MemPercent: double;
    MemUsed, MemTotal: QWord;     // bytes
    DiskPercent: double;          // drive C:
    DiskUsed, DiskTotal: QWord;
    NetRxRate, NetTxRate: double; // bytes per second
    NetLinkSpeed: QWord;          // bits per second of the fastest active adapter
    Processes: integer;
    UptimeSec: QWord;
    Cores: integer;
    HostName: string;
    Samples: integer;
    constructor Create;
    procedure Sample;
  end;

function FormatBytes(b: double): string;
function FormatRate(bytesPerSec: double): string;
function FormatUptime(sec: QWord): string;

implementation

type
  TMemoryStatusEx = record
    dwLength: DWORD;
    dwMemoryLoad: DWORD;
    ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile,
    ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual: QWord;
  end;

  // MIB_IFROW from iphlpapi (860 bytes)
  TMibIfRow = record
    wszName: array[0..255] of WideChar;
    dwIndex, dwType, dwMtu, dwSpeed, dwPhysAddrLen: DWORD;
    bPhysAddr: array[0..7] of Byte;
    dwAdminStatus, dwOperStatus, dwLastChange, dwInOctets, dwInUcastPkts,
    dwInNUcastPkts, dwInDiscards, dwInErrors, dwInUnknownProtos, dwOutOctets,
    dwOutUcastPkts, dwOutNUcastPkts, dwOutDiscards, dwOutErrors, dwOutQLen,
    dwDescrLen: DWORD;
    bDescr: array[0..255] of Byte;
  end;
  PMibIfRow = ^TMibIfRow;

const
  IF_TYPE_ETHERNET_CSMACD = 6;
  IF_TYPE_IEEE80211 = 71;
  IF_OPER_STATUS_OPERATIONAL = 5;

function GetSystemTimes(var lpIdleTime, lpKernelTime, lpUserTime: TFileTime): BOOL;
  stdcall; external 'kernel32.dll';
function GlobalMemoryStatusEx(var lpBuffer: TMemoryStatusEx): BOOL;
  stdcall; external 'kernel32.dll';
function GetTickCount64: QWord; stdcall; external 'kernel32.dll';
function EnumProcesses(lpidProcess: PDWORD; cb: DWORD; var cbNeeded: DWORD): BOOL;
  stdcall; external 'psapi.dll';
function GetIfTable(pIfTable: Pointer; var pdwSize: ULONG; bOrder: BOOL): DWORD;
  stdcall; external 'iphlpapi.dll';

function FT64(const f: TFileTime): QWord; inline;
begin
  Result := (QWord(f.dwHighDateTime) shl 32) or f.dwLowDateTime;
end;

function FormatBytes(b: double): string;
const
  U: array[0..4] of string = ('B', 'KB', 'MB', 'GB', 'TB');
var
  i: integer;
begin
  i := 0;
  while (b >= 1024) and (i < High(U)) do
  begin
    b := b / 1024;
    Inc(i);
  end;
  if i = 0 then Result := Format('%.0f %s', [b, U[i]])
  else Result := Format('%.1f %s', [b, U[i]]);
end;

function FormatRate(bytesPerSec: double): string;
begin
  Result := FormatBytes(bytesPerSec) + '/s';
end;

function FormatUptime(sec: QWord): string;
begin
  Result := Format('%dd %.2d:%.2d:%.2d', [sec div 86400, (sec div 3600) mod 24, (sec div 60) mod 60, sec mod 60]);
end;

{ TSysMonitor }

constructor TSysMonitor.Create;
var
  buf: array[0..MAX_COMPUTERNAME_LENGTH] of Char;
  n: DWORD;
  si: TSystemInfo;
begin
  inherited Create;
  n := Length(buf);
  if GetComputerNameA(@buf[0], n) then HostName := buf else HostName := '?';
  GetSystemInfo(si);
  Cores := si.dwNumberOfProcessors;
  Sample;
end;

procedure TSysMonitor.SampleCpu;
var
  fi, fk, fu: TFileTime;
  idle, kernel, user, total: QWord;
begin
  if not GetSystemTimes(fi, fk, fu) then Exit;
  idle := FT64(fi); kernel := FT64(fk); user := FT64(fu);
  if FHaveCpu then
  begin
    // kernel time includes idle time
    total := (kernel - FLastKernel) + (user - FLastUser);
    if total > 0 then
      CpuPercent := EnsureRange(100 * (1 - (idle - FLastIdle) / total), 0, 100);
  end;
  FLastIdle := idle; FLastKernel := kernel; FLastUser := user;
  FHaveCpu := True;
end;

procedure TSysMonitor.SampleMemory;
var
  ms: TMemoryStatusEx;
begin
  FillChar(ms, SizeOf(ms), 0);
  ms.dwLength := SizeOf(ms);
  if not GlobalMemoryStatusEx(ms) then Exit;
  MemTotal := ms.ullTotalPhys;
  MemUsed := ms.ullTotalPhys - ms.ullAvailPhys;
  if MemTotal > 0 then MemPercent := 100 * MemUsed / MemTotal;
end;

procedure TSysMonitor.SampleDisk;
var
  total, avail: Int64;
begin
  total := DiskSize(3);  // 3 = C:
  avail := DiskFree(3);
  if total <= 0 then Exit;
  DiskTotal := total;
  DiskUsed := total - avail;
  DiskPercent := 100 * DiskUsed / DiskTotal;
end;

procedure TSysMonitor.SampleNet(dtSec: double);
var
  size: ULONG;
  buf: array of Byte;
  count, i, j, k, n: integer;
  row: PMibIfRow;
  rx, tx: QWord;
  seen: array of QWord;
  key: QWord;
  dup: boolean;
begin
  size := 0;
  GetIfTable(nil, size, False);
  if size = 0 then Exit;
  SetLength(buf, size);
  if GetIfTable(@buf[0], size, False) <> 0 then Exit;
  count := PDWORD(@buf[0])^;
  rx := 0; tx := 0; n := 0;
  NetLinkSpeed := 0;
  SetLength(seen, count);
  for i := 0 to count - 1 do
  begin
    row := PMibIfRow(@buf[4 + i * SizeOf(TMibIfRow)]);
    if not (row^.dwType in [IF_TYPE_ETHERNET_CSMACD, IF_TYPE_IEEE80211]) then Continue;
    if row^.dwOperStatus <> IF_OPER_STATUS_OPERATIONAL then Continue;
    if (row^.dwInOctets = 0) and (row^.dwOutOctets = 0) then Continue;
    // Windows lists filter layers of the same adapter with identical counters
    key := (QWord(row^.dwInOctets) shl 32) or row^.dwOutOctets;
    dup := False;
    for j := 0 to n - 1 do
      if seen[j] = key then dup := True;
    if dup then Continue;
    seen[n] := key;
    Inc(n);
    // previous counters of this interface (rows can change order)
    k := 0;
    while (k < Length(FPrevIdx)) and (FPrevIdx[k] <> row^.dwIndex) do Inc(k);
    if k = Length(FPrevIdx) then
    begin
      SetLength(FPrevIdx, k + 1);
      SetLength(FPrevRx32, k + 1);
      SetLength(FPrevTx32, k + 1);
      FPrevIdx[k] := row^.dwIndex;
    end
    else
    begin
      // 32-bit counters: the DWORD difference handles wrap-around
      rx += DWORD(row^.dwInOctets - FPrevRx32[k]);
      tx += DWORD(row^.dwOutOctets - FPrevTx32[k]);
    end;
    FPrevRx32[k] := row^.dwInOctets;
    FPrevTx32[k] := row^.dwOutOctets;
    // $FFFFFFFF = unknown / too fast for the 32-bit field
    if (row^.dwSpeed <> High(DWORD)) and (row^.dwSpeed > NetLinkSpeed) then
      NetLinkSpeed := row^.dwSpeed;
  end;
  if FHaveNet and (dtSec > 0) then
  begin
    NetRxRate := rx / dtSec;
    NetTxRate := tx / dtSec;
  end;
  FLastRx += rx;
  FLastTx += tx;
  FHaveNet := True;
end;

procedure TSysMonitor.SampleProcesses;
var
  ids: array[0..4095] of DWORD;
  needed: DWORD;
begin
  if EnumProcesses(@ids[0], SizeOf(ids), needed) then
    Processes := needed div SizeOf(DWORD);
end;

procedure TSysMonitor.Sample;
var
  now: QWord;
  dt: double;
begin
  now := GetTickCount64;
  if FLastSampleMs = 0 then dt := 0 else dt := (now - FLastSampleMs) / 1000;
  FLastSampleMs := now;
  UptimeSec := now div 1000;
  SampleCpu;
  SampleMemory;
  SampleDisk;
  SampleNet(dt);
  SampleProcesses;
  Inc(Samples);
end;

end.
