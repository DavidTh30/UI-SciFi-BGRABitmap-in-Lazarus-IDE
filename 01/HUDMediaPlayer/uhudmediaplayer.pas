unit UHUDMediaPlayer;

{ HUD Media Player - audio player in the Sci-Fi HUD style.

  Playback: Windows MCI ("mpegvideo" device = DirectShow / Media Foundation
  decoders): mp3, wav, wma, m4a, aac. Tags: ID3v2 (TIT2/TPE1/TALB) and ID3v1.
  Screen: spinning disc (Optic Scanner, turns while playing), now-playing
  panel with time, seek bar and volume, HUD transport buttons, a decorative
  spectrum effect (MCI gives no audio samples, so it is an animation that
  follows the play state, not an analysis) and the playlist.

  Mouse: click the seek / volume bar, transport buttons; double-click a
  track to play it; drop files on the window to add them.
  Keys (view focused): Space play/pause, Left/Right -/+5 s, Up/Down volume,
  PgUp/PgDn previous/next, Enter play the selected track, Del remove it.
  The playlist is kept in playlist.m3u next to the program. }

{$mode objfpc}{$H+}

interface

uses
  Windows, Classes, SysUtils, Math, LazUTF8, LConvEncoding, Forms, Controls, StdCtrls, ExtCtrls,
  Dialogs, LCLType, BGRABitmap, BGRABitmapTypes, HUDCore, HUDHost, HUDPanels, UOpticScanner;

type
  TPlayState = (psStopped, psPlaying, psPaused);

  TTrack = record
    FileName: string;
    Title, Artist, Album: string;
  end;

  { TNowPlayingWidget }

  TNowPlayingWidget = class(THUDWidget)
  public
    Title, Artist, Album, FileText, StateText: string;
    PosMs, LenMs: integer;
    Volume: single;           // 0..100
    HoverSeek: single;        // -1 = none, else 0..1
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
    function SeekAt(lx, ly: single): single;    // 0..1, -1 = not on the bar
    function VolumeAt(lx, ly: single): single;  // 0..100, -1 = not on the bar
  end;

  { TTransportWidget }

  TTransportWidget = class(THUDWidget)
  public
    Playing: boolean;
    HoverBtn: integer;
    RepeatMode, Shuffle: integer;
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
    function ButtonAt(lx, ly: single): integer;   // 0 prev 1 play 2 stop 3 next 4 repeat 5 shuffle
  end;

  { TSpectrumWidget }

  TSpectrumWidget = class(THUDWidget)
  public
    Level: single;    // 0 (paused) .. 1 (playing), eased
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

  { THUDMediaPlayerWidget }

  THUDMediaPlayerWidget = class(THUDComposite)
  private
    FVolume, FRepeat, FShuffle: single;
  public
    Tracks: array of TTrack;
    CurrentTrack: integer;
    State: TPlayState;
    LastError: string;
    DiscW: TOpticScannerWidget;
    Now_: TNowPlayingWidget;
    Transport: TTransportWidget;
    Spectrum: TSpectrumWidget;
    Playlist: THUDListWidget;
    constructor Create; override;
    destructor Destroy; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
    procedure AddFile(const AFileName: string);
    procedure AddFolder(const ADir: string);
    procedure RebuildPlaylist;
    procedure PlayTrack(i: integer);
    procedure TogglePlay;
    procedure StopPlayback;
    procedure NextTrack(manual: boolean);
    procedure PrevTrack;
    procedure SeekTo(ms: integer);
    procedure ApplyVolume;
    procedure Poll;          // called by a timer: position, end of track
    procedure SavePlaylist;
    procedure LoadPlaylist;
    function PlaylistFile: string;
  protected
    procedure DrawDynamic; override;
  end;

function IsAudioFile(const AFileName: string): boolean;
procedure ReadTags(const AFileName: string; var Tr: TTrack);
function FmtTime(ms: integer): string;

implementation

const
  Alias = 'hudmedia';

function mciSendStringW(lpstrCommand, lpstrReturnString: PWideChar; uReturnLength: UINT;
  hwndCallback: HWND): DWORD; stdcall; external 'winmm.dll';
function mciGetErrorStringW(mcierr: DWORD; pszText: PWideChar; cchText: UINT): BOOL;
  stdcall; external 'winmm.dll';

function Mci(const Cmd: string; out Reply: string): DWORD;
var
  buf: array[0..511] of WideChar;
begin
  buf[0] := #0;
  Result := mciSendStringW(PWideChar(UTF8ToUTF16(Cmd)), @buf[0], Length(buf), 0);
  Reply := UTF16ToUTF8(UnicodeString(PWideChar(@buf[0])));
end;

function MciErr(code: DWORD): string;
var
  buf: array[0..255] of WideChar;
begin
  if mciGetErrorStringW(code, @buf[0], Length(buf)) then
    Result := UTF16ToUTF8(UnicodeString(PWideChar(@buf[0])))
  else
    Result := Format('MCI error %d', [code]);
end;

function IsAudioFile(const AFileName: string): boolean;
var
  e: string;
begin
  e := LowerCase(ExtractFileExt(AFileName));
  Result := (e = '.mp3') or (e = '.wav') or (e = '.wma') or (e = '.m4a') or (e = '.aac');
end;

function FmtTime(ms: integer): string;
begin
  if ms < 0 then ms := 0;
  Result := Format('%.2d:%.2d', [ms div 60000, (ms div 1000) mod 60]);
end;

{ ---------- tags ---------- }

function DecodeTagText(const raw: RawByteString): string;
var
  enc: byte;
  body: RawByteString;
  ws: UnicodeString;
  i, n: integer;
  be: boolean;
begin
  Result := '';
  if raw = '' then Exit;
  enc := Ord(raw[1]);
  body := Copy(raw, 2, MaxInt);
  case enc of
    0: Result := CP1252ToUTF8(body);
    3: Result := body;
    1, 2:
      begin
        be := enc = 2;
        i := 1;
        if (Length(body) >= 2) and (enc = 1) then
        begin
          be := (body[1] = #$FE) and (body[2] = #$FF);
          if ((body[1] = #$FF) and (body[2] = #$FE)) or be then i := 3;
        end;
        n := (Length(body) - i + 1) div 2;
        SetLength(ws, n);
        for n := 1 to Length(ws) do
        begin
          if be then ws[n] := WideChar(Ord(body[i]) shl 8 or Ord(body[i + 1]))
          else ws[n] := WideChar(Ord(body[i + 1]) shl 8 or Ord(body[i]));
          Inc(i, 2);
        end;
        Result := UTF16ToUTF8(ws);
      end;
  end;
  // cut at the first terminator
  i := Pos(#0, Result);
  if i > 0 then SetLength(Result, i - 1);
  Result := Trim(Result);
end;

function V1Field(const tag: array of AnsiChar; offset: integer): string;
var
  raw: RawByteString;
  i: integer;
begin
  // fixed 30-byte, null-padded Latin-1 field
  SetString(raw, PAnsiChar(@tag[offset]), 30);
  i := Pos(#0, raw);
  if i > 0 then SetLength(raw, i - 1);
  Result := Trim(CP1252ToUTF8(raw));
end;

procedure ReadTags(const AFileName: string; var Tr: TTrack);
var
  F: TFileStream;
  hdr: array[0..9] of byte;
  tag: array[0..127] of AnsiChar;
  size, p, fsize, ver: integer;
  id: string;
  data: RawByteString;
begin
  Tr.Title := '';
  Tr.Artist := '';
  Tr.Album := '';
  try
    F := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      // ID3v2 at the start
      if (F.Size > 10) and (F.Read(hdr, 10) = 10) and (hdr[0] = Ord('I')) and (hdr[1] = Ord('D')) and
         (hdr[2] = Ord('3')) then
      begin
        ver := hdr[3];
        size := (hdr[6] shl 21) or (hdr[7] shl 14) or (hdr[8] shl 7) or hdr[9];
        p := 10;
        while (p + 10 < size + 10) and (p + 10 < F.Size) do
        begin
          F.Position := p;
          if F.Read(hdr, 10) <> 10 then Break;
          if hdr[0] = 0 then Break;   // padding
          id := Chr(hdr[0]) + Chr(hdr[1]) + Chr(hdr[2]) + Chr(hdr[3]);
          if ver >= 4 then
            fsize := (hdr[4] shl 21) or (hdr[5] shl 14) or (hdr[6] shl 7) or hdr[7]
          else
            fsize := (hdr[4] shl 24) or (hdr[5] shl 16) or (hdr[6] shl 8) or hdr[7];
          if (fsize <= 0) or (fsize > 1 shl 20) then Break;
          if (id = 'TIT2') or (id = 'TPE1') or (id = 'TALB') then
          begin
            SetLength(data, fsize);
            F.ReadBuffer(data[1], fsize);
            if id = 'TIT2' then Tr.Title := DecodeTagText(data)
            else if id = 'TPE1' then Tr.Artist := DecodeTagText(data)
            else Tr.Album := DecodeTagText(data);
          end;
          p := p + 10 + fsize;
        end;
      end;
      // ID3v1 at the end (fills what v2 did not)
      if F.Size >= 128 then
      begin
        F.Position := F.Size - 128;
        F.ReadBuffer(tag, 128);
        if (tag[0] = 'T') and (tag[1] = 'A') and (tag[2] = 'G') then
        begin
          if Tr.Title = '' then Tr.Title := V1Field(tag, 3);
          if Tr.Artist = '' then Tr.Artist := V1Field(tag, 33);
          if Tr.Album = '' then Tr.Album := V1Field(tag, 63);
        end;
      end;
    finally
      F.Free;
    end;
  except
    // unreadable file: fall back to the file name
  end;
  if Tr.Title = '' then Tr.Title := ChangeFileExt(ExtractFileName(AFileName), '');
end;

{ ---------- TNowPlayingWidget ---------- }

const
  NW = 800;
  NH = 290;
  SeekX0 = 30;
  SeekX1 = 610;
  SeekY = 226;
  VolX0 = 660;
  VolX1 = 770;
  VolY = 226;

constructor TNowPlayingWidget.Create;
begin
  inherited Create;
  SetView(NW, NH);
  HoverSeek := -1;
end;

class function TNowPlayingWidget.UIName: string;
begin
  Result := 'Now Playing';
end;

class function TNowPlayingWidget.UIDescription: string;
begin
  Result := 'Title / artist / album, play state, elapsed and total time, seek bar and volume bar.';
end;

class function TNowPlayingWidget.UnitFile: string;
begin
  Result := 'HUDMediaPlayer\uhudmediaplayer.pas';
end;

procedure TNowPlayingWidget.DrawStatic;
var
  i: integer;
begin
  FillPoly([0, 12, 12, 0, 500, 0, 512, 12, NW, 12, NW, NH - 12, NW - 12, NH, 0, NH], Steel(45));
  Polygon([0, 12, 12, 0, 500, 0, 512, 12, NW, 12, NW, NH - 12, NW - 12, NH, 0, NH], 1.3, Ice(180));
  for i := 0 to 5 do
    Line(454 + i * 7, 9, 461 + i * 7, 2, 2, White(200));
  Line(NW, 30, NW, 110, 3, White);
  Txt(16, 16, '\\NOW PLAYING', 8, White(230));
  // seek track and volume track
  FillPoly([SeekX0, SeekY - 4, SeekX1, SeekY - 4, SeekX1, SeekY + 4, SeekX0, SeekY + 4], Navy(230));
  Polygon([SeekX0, SeekY - 4, SeekX1, SeekY - 4, SeekX1, SeekY + 4, SeekX0, SeekY + 4], 1, Steel(170));
  Txt(VolX0, VolY - 16, 'VOLUME', 6.5, Ice(170));
  FillPoly([VolX0, VolY - 4, VolX1, VolY - 4, VolX1, VolY + 4, VolX0, VolY + 4], Navy(230));
  Polygon([VolX0, VolY - 4, VolX1, VolY - 4, VolX1, VolY + 4, VolX0, VolY + 4], 1, Steel(170));
end;

procedure TNowPlayingWidget.DrawDynamic;
var
  frac_, xv, xh: single;
begin
  TxtCached(30, 56, FitText(Title, 46), 18, taLeftJustify);
  TxtCached(30, 92, FitText(Artist, 70), 10, taLeftJustify, Ice(220));
  TxtCached(30, 112, FitText(Album, 80), 8, taLeftJustify, Ice(170));
  TxtCached(30, 134, FitText(FileText, 110), 6.5, taLeftJustify, Ice(130));
  TxtCached(NW - 30, 56, StateText, 9, taRightJustify, Ice(220));
  TxtCached(30, 190, FmtTime(PosMs), 26, taLeftJustify);
  TxtCached(SeekX1, 196, '/ ' + FmtTime(LenMs), 12, taRightJustify, Ice(200));
  // seek fill + head
  if LenMs > 0 then frac_ := EnsureRange(PosMs / LenMs, 0, 1) else frac_ := 0;
  xh := SeekX0 + (SeekX1 - SeekX0) * frac_;
  if frac_ > 0 then
    FLayer.FillRectAntialias(X(SeekX0 + 1), Y(SeekY - 2.5), X(xh), Y(SeekY + 2.5), Ice);
  Disc(xh, SeekY, 6, White);
  Ring(xh, SeekY, 10, 1, Ice(160));
  if HoverSeek >= 0 then
  begin
    xv := SeekX0 + (SeekX1 - SeekX0) * HoverSeek;
    Line(xv, SeekY - 12, xv, SeekY + 12, 1, Ice(200));
    TxtCached(xv, SeekY + 22, FmtTime(Round(HoverSeek * LenMs)), 7, taCenter, Ice(220));
  end;
  // volume
  xv := VolX0 + (VolX1 - VolX0) * Volume / 100;
  if Volume > 0 then
    FLayer.FillRectAntialias(X(VolX0 + 1), Y(VolY - 2.5), X(xv), Y(VolY + 2.5), Ice);
  Disc(xv, VolY, 4.5, White);
  TxtCached(VolX1, VolY + 18, Format('%.0f%%', [Volume]), 7, taRightJustify, Ice(200));
end;

procedure TNowPlayingWidget.DefineDirty;
begin
  AddDirty(20, 34, NW - 10, NH - 10);
end;

function TNowPlayingWidget.SeekAt(lx, ly: single): single;
begin
  if (lx >= SeekX0 - 6) and (lx <= SeekX1 + 6) and (Abs(ly - SeekY) <= 12) then
    Result := EnsureRange((lx - SeekX0) / (SeekX1 - SeekX0), 0, 1)
  else
    Result := -1;
end;

function TNowPlayingWidget.VolumeAt(lx, ly: single): single;
begin
  if (lx >= VolX0 - 6) and (lx <= VolX1 + 6) and (Abs(ly - VolY) <= 12) then
    Result := EnsureRange(100 * (lx - VolX0) / (VolX1 - VolX0), 0, 100)
  else
    Result := -1;
end;

procedure TNowPlayingWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 800 x 290.');
  L.Add('  Texts    title size 18, artist 10, album 8, file name 6.5, state at the right');
  L.Add(Format('  Time     elapsed size 26, total size 12; seek bar x %d..%d at y %d', [SeekX0, SeekX1, SeekY]));
  L.Add(Format('  Volume   bar x %d..%d at y %d (click to set)', [VolX0, VolX1, VolY]));
  L.Add('  Hover    the seek bar shows the time under the mouse');
end;

{ ---------- TTransportWidget ---------- }

const
  TW = 420;
  TH = 110;
  BtnX: array[0..5] of single = (60, 130, 200, 270, 340, 390);

constructor TTransportWidget.Create;
begin
  inherited Create;
  SetView(TW, TH);
  HoverBtn := -1;
end;

class function TTransportWidget.UIName: string;
begin
  Result := 'Transport';
end;

class function TTransportWidget.UIDescription: string;
begin
  Result := 'Previous, play/pause, stop, next, repeat and shuffle buttons.';
end;

class function TTransportWidget.UnitFile: string;
begin
  Result := 'HUDMediaPlayer\uhudmediaplayer.pas';
end;

function TTransportWidget.ButtonAt(lx, ly: single): integer;
var
  i: integer;
  r: single;
begin
  Result := -1;
  for i := 0 to High(BtnX) do
  begin
    if i >= 4 then r := 16 else r := 26;
    if Hypot(lx - BtnX[i], ly - 55) <= r then Exit(i);
  end;
end;

procedure TTransportWidget.DrawStatic;
var
  i: integer;
begin
  FillPoly([0, 10, 10, 0, TW, 0, TW, TH - 10, TW - 10, TH, 0, TH], Steel(45));
  Polygon([0, 10, 10, 0, TW, 0, TW, TH - 10, TW - 10, TH, 0, TH], 1.3, Ice(180));
  for i := 0 to 3 do
    Ring(BtnX[i], 55, 26, 1.5, Ice(200));
  Ring(BtnX[1], 55, 32, 1, Ice(120));
  // icons
  FillPoly([BtnX[0] + 8, 45, BtnX[0] - 4, 55, BtnX[0] + 8, 65], White);
  FillPoly([BtnX[0] - 6, 45, BtnX[0] - 3, 45, BtnX[0] - 3, 65, BtnX[0] - 6, 65], White);
  FillPoly([BtnX[2] - 8, 47, BtnX[2] + 8, 47, BtnX[2] + 8, 63, BtnX[2] - 8, 63], White);
  FillPoly([BtnX[3] - 8, 45, BtnX[3] + 4, 55, BtnX[3] - 8, 65], White);
  FillPoly([BtnX[3] + 3, 45, BtnX[3] + 6, 45, BtnX[3] + 6, 65, BtnX[3] + 3, 65], White);
end;

procedure TTransportWidget.DrawDynamic;
var
  i: integer;
  r: single;
begin
  if HoverBtn >= 0 then
  begin
    if HoverBtn >= 4 then r := 18 else r := 28;
    Ring(BtnX[HoverBtn], 55, r, 2, White);
  end;
  // play / pause glyph
  if Playing then
  begin
    FillPoly([BtnX[1] - 9, 43, BtnX[1] - 3, 43, BtnX[1] - 3, 67, BtnX[1] - 9, 67], White);
    FillPoly([BtnX[1] + 3, 43, BtnX[1] + 9, 43, BtnX[1] + 9, 67, BtnX[1] + 3, 67], White);
    Arc(BtnX[1], 55, 32, T * 120, T * 120 + 50, 2.5, Ice);
    Arc(BtnX[1], 55, 32, T * 120 + 180, T * 120 + 230, 2.5, Ice);
  end
  else
    FillPoly([BtnX[1] - 7, 42, BtnX[1] + 12, 55, BtnX[1] - 7, 68], White);
  // repeat: ring arrows; 0 off (dim), 1 all, 2 one
  if RepeatMode > 0 then r := 255 else r := 110;
  Arc(BtnX[4], 55, 9, 30, 300, 1.6, White(Round(r)));
  FillPoly([BtnX[4] + 9, 50, BtnX[4] + 13, 57, BtnX[4] + 5, 57], White(Round(r)));
  if RepeatMode = 2 then TxtCached(BtnX[4], 55, '1', 6, taCenter);
  // shuffle: two crossing lines
  if Shuffle > 0 then r := 255 else r := 110;
  Line(BtnX[5] - 9, 49, BtnX[5] + 9, 61, 1.6, White(Round(r)));
  Line(BtnX[5] - 9, 61, BtnX[5] + 9, 49, 1.6, White(Round(r)));
  for i := 4 to 5 do
    Ring(BtnX[i], 55, 16, 1, Ice(140));
end;

procedure TTransportWidget.DefineDirty;
begin
  AddDirty(20, 14, TW - 6, TH - 10);
end;

procedure TTransportWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 420 x 110, buttons centred at y 55:');
  L.Add('  x 60 previous, 130 play/pause (orbiting arcs while playing), 200 stop,');
  L.Add('  270 next, 340 repeat (off / all / one), 390 shuffle. Hover = white ring.');
end;

{ ---------- TSpectrumWidget ---------- }

const
  SW = 420;
  SH = 290;
  Bars = 28;

constructor TSpectrumWidget.Create;
begin
  inherited Create;
  SetView(SW, SH);
end;

class function TSpectrumWidget.UIName: string;
begin
  Result := 'Spectrum Effect';
end;

class function TSpectrumWidget.UIDescription: string;
begin
  Result := 'Decorative spectrum: animated bars that move while playing and settle when paused. ' +
    'MCI gives no audio samples, so this is not a real frequency analysis.';
end;

class function TSpectrumWidget.UnitFile: string;
begin
  Result := 'HUDMediaPlayer\uhudmediaplayer.pas';
end;

procedure TSpectrumWidget.DrawStatic;
var
  i: integer;
begin
  FillPoly([0, 12, 12, 0, 260, 0, 272, 12, SW, 12, SW, SH - 12, SW - 12, SH, 0, SH], Steel(45));
  Polygon([0, 12, 12, 0, 260, 0, 272, 12, SW, 12, SW, SH - 12, SW - 12, SH, 0, SH], 1.3, Ice(180));
  Txt(16, 16, '\\SIGNAL (EFFECT)', 8, White(230));
  for i := 1 to 4 do
    Line(20, 250 - i * 45, SW - 20, 250 - i * 45, 0.6, Ice(50));
  Line(20, 250, SW - 20, 250, 1, Ice(140));
end;

procedure TSpectrumWidget.DrawDynamic;
var
  i: integer;
  bx, bw, h, v: single;
begin
  bw := (SW - 40) / Bars;
  for i := 0 to Bars - 1 do
  begin
    // smooth pseudo-random motion: sum of a few sines per bar
    v := 0.5 + 0.25 * Sin(T * (3.1 + i * 0.37) + i) + 0.15 * Sin(T * (7.3 + i * 0.11) + i * 2.1) +
      0.1 * Sin(T * 13 + i * 0.7);
    v := v * (1 - 0.5 * i / Bars);                // lows taller than highs
    h := 6 + 180 * EnsureRange(v, 0, 1) * Level;
    bx := 20 + i * bw;
    FillPoly([bx + 1, 250 - h, bx + bw - 2, 250 - h, bx + bw - 2, 250, bx + 1, 250], Ice(Round(120 + 100 * v * Level)));
    Line(bx + 1, 250 - h - 4, bx + bw - 2, 250 - h - 4, 1.5, White(Round(120 + 120 * Level)));
  end;
end;

procedure TSpectrumWidget.DefineDirty;
begin
  AddDirty(16, 40, SW - 16, 256);
end;

procedure TSpectrumWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %d x %d, %d bars over a baseline at y 250.', [SW, SH, Bars]));
  L.Add('  Bars     height = sum of sines (different speed per bar) x Level;');
  L.Add('           Level eases to 1 while playing and to 0 when paused/stopped');
  L.Add('  Note     decorative: MCI does not expose the audio samples');
end;

{ ---------- THUDMediaPlayerWidget ---------- }

constructor THUDMediaPlayerWidget.Create;
begin
  inherited Create;
  SetView(1240, 730);
  SetParamByName('Max zoom', 2);
  SetParamByName('Glow intensity', 0.9);
  FVolume := 80;
  AddParam('Volume', 'Player', 'Playback volume 0..100.', FVolume, 0, 100, 0, False);
  AddParam('Repeat', 'Player', '0 = off, 1 = repeat the playlist, 2 = repeat the current track.',
    FRepeat, 0, 2, 0, False);
  AddParam('Shuffle', 'Player', '1 = next track is picked at random.', FShuffle, 0, 1, 0, False);
  CurrentTrack := -1;

  DiscW := TOpticScannerWidget.Create;
  DiscW.SetParamByName('Label number', 0);
  AddChild(DiscW, 0, 10, 'Disc (Optic Scanner)');
  Now_ := TNowPlayingWidget.Create;
  AddChild(Now_, 430, 10, 'Now playing');
  Transport := TTransportWidget.Create;
  AddChild(Transport, 0, 310, 'Transport buttons');
  Spectrum := TSpectrumWidget.Create;
  AddChild(Spectrum, 0, 430, 'Spectrum effect');
  Playlist := THUDListWidget.CreateList(800, 420, '\\PLAYLIST');
  Playlist.EmptyText := 'DROP AUDIO FILES HERE OR USE ADD FILES / ADD FOLDER';
  AddChild(Playlist, 430, 310, 'Playlist');
  LoadPlaylist;
end;

destructor THUDMediaPlayerWidget.Destroy;
var
  r: string;
begin
  Mci('close ' + Alias, r);
  inherited Destroy;
end;

class function THUDMediaPlayerWidget.UIName: string;
begin
  Result := 'HUD Media Player';
end;

class function THUDMediaPlayerWidget.UIDescription: string;
begin
  Result := 'Audio player in the HUD style: playlist, transport buttons, seek and volume bars, tags. ' +
    'Drop files on the window or use Add files / Add folder.';
end;

class function THUDMediaPlayerWidget.UnitFile: string;
begin
  Result := 'HUDMediaPlayer\uhudmediaplayer.pas';
end;

function THUDMediaPlayerWidget.PlaylistFile: string;
begin
  Result := ExtractFilePath(Application.ExeName) + 'playlist.m3u';
end;

procedure THUDMediaPlayerWidget.AddFile(const AFileName: string);
var
  n: integer;
begin
  if not (IsAudioFile(AFileName) and FileExists(AFileName)) then Exit;
  n := Length(Tracks);
  SetLength(Tracks, n + 1);
  Tracks[n].FileName := AFileName;
  ReadTags(AFileName, Tracks[n]);
end;

procedure THUDMediaPlayerWidget.AddFolder(const ADir: string);
var
  sr: TSearchRec;
  L: TStringList;
  i: integer;
begin
  L := TStringList.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if ((sr.Attr and faDirectory) = 0) and IsAudioFile(sr.Name) then
          L.Add(IncludeTrailingPathDelimiter(ADir) + sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    L.Sort;
    for i := 0 to L.Count - 1 do AddFile(L[i]);
  finally
    L.Free;
  end;
end;

procedure THUDMediaPlayerWidget.RebuildPlaylist;
var
  i, sel: integer;
  detail: string;
begin
  sel := Playlist.Selected;
  Playlist.Clear;
  for i := 0 to High(Tracks) do
  begin
    detail := UpperCase(Copy(ExtractFileExt(Tracks[i].FileName), 2, 4));
    if Tracks[i].Artist <> '' then detail := FitText(Tracks[i].Artist, 22) + '  ' + detail;
    if i = CurrentTrack then
      Playlist.Add(Format('%.2d  %s', [i + 1, Tracks[i].Title]), detail, ikPlaying)
    else
      Playlist.Add(Format('%.2d  %s', [i + 1, Tracks[i].Title]), detail, ikAudio);
  end;
  Playlist.Selected := Min(sel, High(Tracks));
  Playlist.SetTitle(Format('\\PLAYLIST  %d TRACKS', [Length(Tracks)]));
end;

procedure THUDMediaPlayerWidget.ApplyVolume;
var
  r: string;
begin
  if State <> psStopped then
    Mci(Format('setaudio %s volume to %d', [Alias, Round(FVolume * 10)]), r);
end;

procedure THUDMediaPlayerWidget.PlayTrack(i: integer);
var
  r: string;
  err: DWORD;
begin
  if (i < 0) or (i > High(Tracks)) then Exit;
  Mci('close ' + Alias, r);
  State := psStopped;
  LastError := '';
  CurrentTrack := i;
  Now_.PosMs := 0;      // never show the previous track's time
  Now_.LenMs := 0;
  Playlist.Selected := i;
  err := Mci(Format('open "%s" type mpegvideo alias %s', [Tracks[i].FileName, Alias]), r);
  if err <> 0 then
  begin
    LastError := MciErr(err);
    RebuildPlaylist;
    Exit;
  end;
  Mci('set ' + Alias + ' time format milliseconds', r);
  Mci('status ' + Alias + ' length', r);
  Now_.LenMs := StrToIntDef(r, 0);
  err := Mci('play ' + Alias, r);
  if err <> 0 then LastError := MciErr(err) else State := psPlaying;
  ApplyVolume;
  DiscW.SetParamByName('Label number', i + 1);
  Playlist.Selected := i;
  Playlist.EnsureVisible(i);
  RebuildPlaylist;
end;

procedure THUDMediaPlayerWidget.TogglePlay;
var
  r: string;
begin
  case State of
    psPlaying:
      begin
        Mci('pause ' + Alias, r);
        State := psPaused;
      end;
    psPaused:
      begin
        Mci('resume ' + Alias, r);
        State := psPlaying;
      end;
  else
    if Playlist.Selected >= 0 then PlayTrack(Playlist.Selected)
    else if Length(Tracks) > 0 then PlayTrack(Max(0, CurrentTrack));
  end;
end;

procedure THUDMediaPlayerWidget.StopPlayback;
var
  r: string;
begin
  Mci('stop ' + Alias, r);
  Mci('seek ' + Alias + ' to start', r);
  State := psStopped;
  Now_.PosMs := 0;
end;

procedure THUDMediaPlayerWidget.NextTrack(manual: boolean);
var
  n: integer;
begin
  if Length(Tracks) = 0 then Exit;
  if (not manual) and (Round(FRepeat) = 2) then
  begin
    PlayTrack(CurrentTrack);
    Exit;
  end;
  if FShuffle >= 1 then
    n := Random(Length(Tracks))
  else
    n := CurrentTrack + 1;
  if n > High(Tracks) then
  begin
    if manual or (Round(FRepeat) = 1) then n := 0
    else
    begin
      StopPlayback;
      Exit;
    end;
  end;
  PlayTrack(n);
end;

procedure THUDMediaPlayerWidget.PrevTrack;
begin
  if Length(Tracks) = 0 then Exit;
  // more than 3 s in: restart the track, else go to the previous one
  if Now_.PosMs > 3000 then PlayTrack(CurrentTrack)
  else PlayTrack(Max(0, CurrentTrack - 1));
end;

procedure THUDMediaPlayerWidget.SeekTo(ms: integer);
var
  r: string;
begin
  if State = psStopped then Exit;
  ms := EnsureRange(ms, 0, Max(0, Now_.LenMs - 100));
  if State = psPlaying then
    Mci(Format('play %s from %d', [Alias, ms]), r)
  else
    Mci(Format('seek %s to %d', [Alias, ms]), r);
  Now_.PosMs := ms;
end;

procedure THUDMediaPlayerWidget.Poll;
var
  r, mode: string;
begin
  if State = psStopped then Exit;
  Mci('status ' + Alias + ' position', r);
  Now_.PosMs := StrToIntDef(r, Now_.PosMs);
  Mci('status ' + Alias + ' mode', mode);
  // MCI stops by itself at the end of the track
  if (State = psPlaying) and (mode = 'stopped') and (Now_.LenMs > 0) and (Now_.PosMs >= Now_.LenMs - 250) then
    NextTrack(False);
end;

procedure THUDMediaPlayerWidget.SavePlaylist;
var
  L: TStringList;
  i: integer;
begin
  L := TStringList.Create;
  try
    L.Add('#EXTM3U');
    for i := 0 to High(Tracks) do L.Add(Tracks[i].FileName);
    try
      L.SaveToFile(PlaylistFile);
    except
      // read-only folder: the playlist is just not kept
    end;
  finally
    L.Free;
  end;
end;

procedure THUDMediaPlayerWidget.LoadPlaylist;
var
  L: TStringList;
  i: integer;
begin
  Tracks := nil;
  if FileExists(PlaylistFile) then
  begin
    L := TStringList.Create;
    try
      L.LoadFromFile(PlaylistFile);
      for i := 0 to L.Count - 1 do
        if (Trim(L[i]) <> '') and (L[i][1] <> '#') then AddFile(Trim(L[i]));
    finally
      L.Free;
    end;
  end;
  RebuildPlaylist;
end;

procedure THUDMediaPlayerWidget.DrawDynamic;
var
  playing: boolean;
begin
  playing := State = psPlaying;
  // the disc spins while playing and stops when paused
  DiscW.SetParamValue(DiscW.ParamIndex('Rotation speed'), IfThen(playing, 40, 0));
  Spectrum.Level += ((Ord(playing) * 1.0) - Spectrum.Level) * 0.08;
  Transport.Playing := playing;
  Transport.RepeatMode := Round(FRepeat);
  Transport.Shuffle := Round(FShuffle);
  Now_.Volume := FVolume;
  if (CurrentTrack >= 0) and (CurrentTrack <= High(Tracks)) then
  begin
    Now_.Title := Tracks[CurrentTrack].Title;
    Now_.Artist := Tracks[CurrentTrack].Artist;
    Now_.Album := Tracks[CurrentTrack].Album;
    Now_.FileText := Tracks[CurrentTrack].FileName;
  end
  else
  begin
    Now_.Title := 'NO TRACK';
    Now_.Artist := 'Add files or drop them on the window';
    Now_.Album := '';
    Now_.FileText := '';
  end;
  if LastError <> '' then Now_.StateText := 'ERROR: ' + FitText(LastError, 40)
  else
    case State of
      psPlaying: Now_.StateText := 'PLAYING';
      psPaused: Now_.StateText := 'PAUSED';
    else
      Now_.StateText := 'STOPPED';
    end;
  inherited DrawDynamic;
end;

procedure THUDMediaPlayerWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('Canvas 1240 x 730 design units.');
  L.Add('');
  L.Add('LAYOUT');
  for i := 0 to ChildCount - 1 do
    L.Add(Format('  %-24s %-22s (%4.0f,%4.0f)', [ChildCaption(i), Children[i].ClassName,
      ChildOrigin(i).x, ChildOrigin(i).y]));
  L.Add('');
  L.Add('PLAYBACK (Windows MCI, winmm.dll)');
  L.Add('  open "<file>" type mpegvideo alias hudmedia / play / pause / resume / stop,');
  L.Add('  status position|length|mode (polled every 100 ms), play from <ms>,');
  L.Add('  setaudio volume to 0..1000. Formats: mp3 wav wma m4a aac (system decoders).');
  L.Add('  End of track: mode "stopped" at the end -> next / repeat / shuffle rules.');
  L.Add('TAGS       ID3v2 TIT2 / TPE1 / TALB (Latin-1, UTF-16, UTF-8), then ID3v1;');
  L.Add('           title falls back to the file name.');
  L.Add('PLAYLIST   <exe>\playlist.m3u, saved on close and after changes.');
  L.Add('SPECTRUM   decorative animation (MCI does not expose audio samples).');
end;

procedure THUDMediaPlayerWidget.DescribeLive(L: TStrings);
const
  SN: array[TPlayState] of string = ('stopped', 'playing', 'paused');
begin
  inherited DescribeLive(L);
  L.Add('State               ' + SN[State]);
  L.Add(Format('Track               %d / %d', [CurrentTrack + 1, Length(Tracks)]));
  L.Add(Format('Position            %s / %s', [FmtTime(Now_.PosMs), FmtTime(Now_.LenMs)]));
  if LastError <> '' then L.Add('Last MCI error      ' + LastError);
end;

{ ---------- controller ---------- }

type
  TPlayerInput = class(TComponent)
  private
    FForm: THUDHostForm;
    FTimer: TTimer;
    FOldKeyDown: TKeyEvent;
    FLastVolume: single;
    function P: THUDMediaPlayerWidget;
    function Local(px, py: integer; W: THUDWidget; out lx, ly: single): boolean;
    procedure Tick(Sender: TObject);
    procedure Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DblClick(Sender: TObject);
    procedure Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Drop(Sender: TObject; const FileNames: array of string);
    procedure CloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure AddFilesClick(Sender: TObject);
    procedure AddFolderClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure SetVolume(v: single);
  end;

function TPlayerInput.P: THUDMediaPlayerWidget;
begin
  Result := FForm.Widget as THUDMediaPlayerWidget;
end;

function TPlayerInput.Local(px, py: integer; W: THUDWidget; out lx, ly: single): boolean;
var
  i: integer;
  d, o: TPointF;
begin
  Result := False;
  d := P.PixelToDesign(px, py);
  for i := 0 to P.ChildCount - 1 do
    if P.Children[i] = W then
    begin
      o := P.ChildOrigin(i);
      lx := d.x - o.x;
      ly := d.y - o.y;
      Result := (lx >= 0) and (ly >= 0) and (lx < W.DesignWidth) and (ly < W.DesignHeight);
      Exit;
    end;
end;

procedure TPlayerInput.SetVolume(v: single);
begin
  P.SetParamValue(P.ParamIndex('Volume'), v);
end;

procedure TPlayerInput.Tick(Sender: TObject);
begin
  P.Poll;
  // volume changed (bar, keys or the Parameters tab)
  if P.Params[P.ParamIndex('Volume')].Value^ <> FLastVolume then
  begin
    FLastVolume := P.Params[P.ParamIndex('Volume')].Value^;
    P.ApplyVolume;
  end;
end;

procedure TPlayerInput.Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  lx, ly: single;
begin
  P.Transport.HoverBtn := -1;
  P.Playlist.Hover := -1;
  P.Now_.HoverSeek := -1;
  if Local(X, Y, P.Transport, lx, ly) then P.Transport.HoverBtn := P.Transport.ButtonAt(lx, ly);
  if Local(X, Y, P.Playlist, lx, ly) then P.Playlist.Hover := P.Playlist.RowAt(lx, ly);
  if Local(X, Y, P.Now_, lx, ly) and (P.State <> psStopped) then
  begin
    P.Now_.HoverSeek := P.Now_.SeekAt(lx, ly);
    if (ssLeft in Shift) and (P.Now_.VolumeAt(lx, ly) >= 0) then SetVolume(P.Now_.VolumeAt(lx, ly));
  end;
end;

procedure TPlayerInput.Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  lx, ly, f: single;
  row: integer;
begin
  FForm.View.SetFocus;
  if Button <> mbLeft then Exit;
  if Local(X, Y, P.Transport, lx, ly) then
    case P.Transport.ButtonAt(lx, ly) of
      0: P.PrevTrack;
      1: P.TogglePlay;
      2: P.StopPlayback;
      3: P.NextTrack(True);
      4: P.SetParamValue(P.ParamIndex('Repeat'), (Round(P.Params[P.ParamIndex('Repeat')].Value^) + 1) mod 3);
      5: P.SetParamValue(P.ParamIndex('Shuffle'), 1 - P.Params[P.ParamIndex('Shuffle')].Value^);
    end;
  if Local(X, Y, P.Playlist, lx, ly) then
  begin
    row := P.Playlist.RowAt(lx, ly);
    if row >= 0 then P.Playlist.Selected := row;
  end;
  if Local(X, Y, P.Now_, lx, ly) then
  begin
    f := P.Now_.SeekAt(lx, ly);
    if f >= 0 then P.SeekTo(Round(f * P.Now_.LenMs));
    f := P.Now_.VolumeAt(lx, ly);
    if f >= 0 then SetVolume(f);
  end;
end;

procedure TPlayerInput.DblClick(Sender: TObject);
var
  pt: TPoint;
  lx, ly: single;
  row: integer;
begin
  pt := FForm.View.ScreenToClient(Mouse.CursorPos);
  if Local(pt.X, pt.Y, P.Playlist, lx, ly) then
  begin
    row := P.Playlist.RowAt(lx, ly);
    if row >= 0 then P.PlayTrack(row);
  end;
end;

procedure TPlayerInput.Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  lx, ly: single;
begin
  if Local(MousePos.X, MousePos.Y, P.Playlist, lx, ly) then
    P.Playlist.ScrollBy(-Sign(WheelDelta) * 3)
  else
    SetVolume(P.Params[P.ParamIndex('Volume')].Value^ + Sign(WheelDelta) * 5);
  Handled := True;
end;

procedure TPlayerInput.KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  vol: single;
begin
  if FForm.ActiveControl = FForm.View then
  begin
    vol := P.Params[P.ParamIndex('Volume')].Value^;
    case Key of
      VK_SPACE: P.TogglePlay;           // replaces the host's animation pause here
      VK_LEFT: P.SeekTo(P.Now_.PosMs - 5000);
      VK_RIGHT: P.SeekTo(P.Now_.PosMs + 5000);
      VK_UP: SetVolume(vol + 5);
      VK_DOWN: SetVolume(vol - 5);
      VK_PRIOR: P.PrevTrack;
      VK_NEXT: P.NextTrack(True);
      VK_RETURN: if P.Playlist.Selected >= 0 then P.PlayTrack(P.Playlist.Selected);
      VK_DELETE: RemoveClick(nil);
    else
      if Assigned(FOldKeyDown) then FOldKeyDown(Sender, Key, Shift);
      Exit;
    end;
    Key := 0;
    Exit;
  end;
  if Assigned(FOldKeyDown) then FOldKeyDown(Sender, Key, Shift);
end;

procedure TPlayerInput.Drop(Sender: TObject; const FileNames: array of string);
var
  i, before: integer;
begin
  before := Length(P.Tracks);
  for i := 0 to High(FileNames) do
    if DirectoryExists(FileNames[i]) then P.AddFolder(FileNames[i]) else P.AddFile(FileNames[i]);
  P.RebuildPlaylist;
  P.SavePlaylist;
  FForm.SetStatus(Format('Added %d track(s)', [Length(P.Tracks) - before]));
  if (P.State = psStopped) and (before = 0) and (Length(P.Tracks) > 0) then P.PlayTrack(0);
end;

procedure TPlayerInput.CloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  P.SavePlaylist;
  CanClose := True;
end;

procedure TPlayerInput.AddFilesClick(Sender: TObject);
var
  D: TOpenDialog;
  files: array of string;
  i: integer;
begin
  D := TOpenDialog.Create(nil);
  try
    D.Filter := 'Audio (*.mp3;*.wav;*.wma;*.m4a;*.aac)|*.mp3;*.wav;*.wma;*.m4a;*.aac|All files (*.*)|*.*';
    D.Options := D.Options + [ofAllowMultiSelect];
    if D.Execute then
    begin
      SetLength(files, D.Files.Count);
      for i := 0 to D.Files.Count - 1 do files[i] := D.Files[i];
      Drop(nil, files);
    end;
  finally
    D.Free;
  end;
end;

procedure TPlayerInput.AddFolderClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(nil);
  try
    if D.Execute then Drop(nil, [D.FileName]);
  finally
    D.Free;
  end;
end;

procedure TPlayerInput.RemoveClick(Sender: TObject);
var
  i, j: integer;
begin
  i := P.Playlist.Selected;
  if (i < 0) or (i > High(P.Tracks)) then Exit;
  if i = P.CurrentTrack then
  begin
    P.StopPlayback;
    P.CurrentTrack := -1;
  end
  else if i < P.CurrentTrack then
    Dec(P.CurrentTrack);
  for j := i to High(P.Tracks) - 1 do P.Tracks[j] := P.Tracks[j + 1];
  SetLength(P.Tracks, Length(P.Tracks) - 1);
  P.RebuildPlaylist;
  P.SavePlaylist;
end;

procedure TPlayerInput.ClearClick(Sender: TObject);
begin
  P.StopPlayback;
  P.CurrentTrack := -1;
  P.Tracks := nil;
  P.RebuildPlaylist;
  P.SavePlaylist;
end;

procedure SetupPlayer(AForm: THUDHostForm);
var
  C: TPlayerInput;
  Bar: TFlowPanel;
  files: array of string;
  i: integer;

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
  if not (AForm.Widget is THUDMediaPlayerWidget) then Exit;
  C := TPlayerInput.Create(AForm);
  C.FForm := AForm;
  C.FLastVolume := -1;
  Bar := TFlowPanel.Create(AForm);
  Bar.Parent := AForm;
  Bar.Align := alTop;
  Bar.AutoSize := True;
  Bar.BevelOuter := bvNone;
  Bar.BorderSpacing.Around := 2;
  Btn('Add files...', @C.AddFilesClick);
  Btn('Add folder...', @C.AddFolderClick);
  Btn('Remove selected', @C.RemoveClick);
  Btn('Clear playlist', @C.ClearClick);
  C.FTimer := TTimer.Create(AForm);
  C.FTimer.Interval := 100;
  C.FTimer.OnTimer := @C.Tick;
  AForm.View.OnMouseMove := @C.Move;
  AForm.View.OnMouseDown := @C.Down;
  AForm.View.OnDblClick := @C.DblClick;
  AForm.View.OnMouseWheel := @C.Wheel;
  AForm.AllowDropFiles := True;
  AForm.OnDropFiles := @C.Drop;
  C.FOldKeyDown := AForm.OnKeyDown;
  AForm.OnKeyDown := @C.KeyDown;
  AForm.OnCloseQuery := @C.CloseQuery;
  AForm.SetStatus('Space: play/pause   Left/Right: seek   Up/Down/wheel: volume   PgUp/PgDn: prev/next   ' +
    'Double-click: play   Drop files to add');
  // HUDMediaPlayer.exe --play <file|folder> ... : add and start playing
  if (ParamCount >= 2) and (ParamStr(1) = '--play') then
  begin
    SetLength(files, ParamCount - 1);
    for i := 2 to ParamCount do files[i - 2] := ParamStr(i);
    C.P.Tracks := nil;
    C.Drop(nil, files);
  end;
end;

initialization
  HostSetupProc := @SetupPlayer;

end.
