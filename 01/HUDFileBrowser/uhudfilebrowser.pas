unit UHUDFileBrowser;

{ HUD File Browser - open files and folders in the Sci-Fi HUD style.

  Left:   places (Home, Desktop, Documents, Downloads, Pictures, Music,
          Videos) and drives with free space, usage gauge of the current
          drive, folder statistics.
  Middle: path bar and the folder listing (folders first, then files).
  Right:  details of the selected item and a preview (images, text).

  Mouse: click = select, double-click = open folder / open file with its
  default program, wheel = scroll the list under the mouse.
  Keys (view focused): Up/Down/PgUp/PgDn/Home/End, Enter = open,
  Backspace = parent folder, F5 = refresh. }

{$mode objfpc}{$H+}

interface

uses
  Windows, ShellApi, Classes, SysUtils, Math, LazUTF8, Forms, Controls, StdCtrls, ExtCtrls,
  LCLType, BGRABitmap, BGRABitmapTypes, HUDCore, HUDHost, HUDPanels, UPillLoader;

type
  TEntry = record
    Name: string;
    IsDir: boolean;
    Size: Int64;
    Time: TDateTime;
    Attr: integer;
  end;

  { TPathBarWidget }

  TPathBarWidget = class(THUDWidget)
  public
    PathText: string;
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

  { TInfoTextWidget - frame with label/value rows and an optional preview }

  TInfoTextWidget = class(THUDWidget)
  private
    FW, FH: single;
    FTitle: string;
  public
    Labels, Values: TStringList;
    PreviewLines: TStringList;
    Preview: TBGRABitmap;       // source image (owned)
    PreviewCache: TBGRABitmap;  // resampled to the current scale
    constructor CreateInfo(AW, AH: single; const ATitle: string);
    destructor Destroy; override;
    procedure ClearInfo;
    procedure SetPreviewImage(B: TBGRABitmap);
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  end;

  { THUDFileBrowserWidget }

  THUDFileBrowserWidget = class(THUDComposite)
  private
    FShowHidden: single;
    FEntries: array of TEntry;
    FPlacePaths: TStringList;
    FTotalSize: Int64;
    FDirCount, FFileCount: integer;
    FListError: string;
    procedure FillPlaces;
    procedure UpdateDetails;
    procedure UpdateDrive;
  public
    Path: string;
    Places: THUDListWidget;
    Files: THUDListWidget;
    PathBar: TPathBarWidget;
    Details: TInfoTextWidget;
    Stats: TInfoTextWidget;
    DriveGauge: TPillLoaderWidget;
    constructor Create; override;
    destructor Destroy; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
    procedure Navigate(const APath: string);
    procedure Refresh;
    procedure GoUp;
    procedure SelectFile(i: integer);
    procedure OpenItem(i: integer);
    procedure OpenPlace(i: integer);
    function SelectedPath: string;
  end;

function FormatSize(b: Int64): string;

implementation

const
  CSIDL_PERSONAL = $05;
  CSIDL_MYMUSIC = $0D;
  CSIDL_MYVIDEO = $0E;
  CSIDL_DESKTOPDIRECTORY = $10;
  CSIDL_MYPICTURES = $27;
  CSIDL_PROFILE = $28;

function SHGetFolderPathW(hwnd: HWND; csidl: integer; hToken: THandle; dwFlags: DWORD;
  pszPath: PWideChar): HRESULT; stdcall; external 'shell32.dll';

function SpecialFolder(csidl: integer): string;
var
  buf: array[0..MAX_PATH] of WideChar;
begin
  if SHGetFolderPathW(0, csidl, 0, 0, @buf[0]) = 0 then
    Result := UTF16ToUTF8(UnicodeString(PWideChar(@buf[0])))
  else
    Result := '';
end;

function FormatSize(b: Int64): string;
const
  U: array[0..4] of string = ('B', 'KB', 'MB', 'GB', 'TB');
var
  v: double;
  i: integer;
begin
  v := b;
  i := 0;
  while (v >= 1024) and (i < High(U)) do
  begin
    v := v / 1024;
    Inc(i);
  end;
  if i = 0 then Result := Format('%d B', [b]) else Result := Format('%.1f %s', [v, U[i]]);
end;

function IsImageExt(const ext: string): boolean;
begin
  Result := (ext = '.png') or (ext = '.jpg') or (ext = '.jpeg') or (ext = '.bmp') or (ext = '.gif');
end;

function IsTextExt(const ext: string): boolean;
const
  T: array[0..19] of string = ('.txt', '.pas', '.pp', '.lpr', '.lpi', '.lfm', '.md', '.csv', '.ini',
    '.json', '.xml', '.log', '.bat', '.cmd', '.py', '.js', '.html', '.css', '.hud', '.inc');
var
  i: integer;
begin
  for i := 0 to High(T) do
    if ext = T[i] then Exit(True);
  Result := False;
end;

{ ---------- TPathBarWidget ---------- }

constructor TPathBarWidget.Create;
begin
  inherited Create;
  SetView(920, 56);
end;

class function TPathBarWidget.UIName: string;
begin
  Result := 'Path Bar';
end;

class function TPathBarWidget.UIDescription: string;
begin
  Result := 'Current folder path.';
end;

class function TPathBarWidget.UnitFile: string;
begin
  Result := 'HUDFileBrowser\uhudfilebrowser.pas';
end;

procedure TPathBarWidget.DrawStatic;
begin
  FillPoly([0, 10, 10, 0, 920, 0, 920, 46, 910, 56, 0, 56], Steel(45));
  Polygon([0, 10, 10, 0, 920, 0, 920, 46, 910, 56, 0, 56], 1.3, Ice(180));
  Txt(14, 15, '\\PATH', 7, Ice(190));
  Line(0, 18, 0, 46, 3, White);
end;

procedure TPathBarWidget.DrawDynamic;
begin
  TxtCached(14, 36, FitText(PathText, 190), 9, taLeftJustify);
end;

procedure TPathBarWidget.DefineDirty;
begin
  AddDirty(8, 22, 912, 52);
end;

procedure TPathBarWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 920 x 56: frame, "\\PATH" label, current path (size 9, UTF-8 ellipsis).');
end;

{ ---------- TInfoTextWidget ---------- }

constructor TInfoTextWidget.CreateInfo(AW, AH: single; const ATitle: string);
begin
  Create;
  FW := AW;
  FH := AH;
  FTitle := ATitle;
  Labels := TStringList.Create;
  Values := TStringList.Create;
  PreviewLines := TStringList.Create;
  SetView(AW, AH);
end;

destructor TInfoTextWidget.Destroy;
begin
  Labels.Free;
  Values.Free;
  PreviewLines.Free;
  Preview.Free;
  PreviewCache.Free;
  inherited Destroy;
end;

procedure TInfoTextWidget.ClearInfo;
begin
  Labels.Clear;
  Values.Clear;
  PreviewLines.Clear;
  SetPreviewImage(nil);
end;

procedure TInfoTextWidget.SetPreviewImage(B: TBGRABitmap);
begin
  FreeAndNil(Preview);
  FreeAndNil(PreviewCache);
  Preview := B;
end;

class function TInfoTextWidget.UIName: string;
begin
  Result := 'Info Panel';
end;

class function TInfoTextWidget.UIDescription: string;
begin
  Result := 'Label / value rows with an optional image or text preview.';
end;

class function TInfoTextWidget.UnitFile: string;
begin
  Result := 'HUDFileBrowser\uhudfilebrowser.pas';
end;

procedure TInfoTextWidget.DrawStatic;
var
  notch: single;
begin
  notch := Min(FW * 0.62, FW - 60);
  FillPoly([0, 12, 12, 0, notch, 0, notch + 12, 12, FW, 12, FW, FH - 12, FW - 12, FH, 0, FH], Steel(45));
  Polygon([0, 12, 12, 0, notch, 0, notch + 12, 12, FW, 12, FW, FH - 12, FW - 12, FH, 0, FH], 1.3, Ice(180));
  Line(FW, 28, FW, 90, 3, White);
  Txt(16, 16, FTitle, 8, White(230));
end;

procedure TInfoTextWidget.DrawDynamic;
var
  i: integer;
  y0, boxX, boxY, boxW, boxH, sc: single;
  pw, ph: integer;
begin
  y0 := 44;
  for i := 0 to Labels.Count - 1 do
  begin
    TxtCached(16, y0, Labels[i], 7, taLeftJustify, Ice(170));
    if i < Values.Count then
      TxtCached(16, y0 + 13, FitText(Values[i], Floor((FW - 30) / 5.2)), 8, taLeftJustify);
    y0 += 32;
  end;
  // preview area below the rows
  boxX := 14;
  boxY := y0 + 6;
  boxW := FW - 28;
  boxH := FH - boxY - 14;
  if (Preview <> nil) and (boxH > 30) then
  begin
    sc := Min(boxW / Preview.Width, boxH / Preview.Height) * K;
    sc := Min(sc, K * 2);
    pw := Max(1, Round(Preview.Width * sc));
    ph := Max(1, Round(Preview.Height * sc));
    if (PreviewCache = nil) or (PreviewCache.Width <> pw) or (PreviewCache.Height <> ph) then
    begin
      FreeAndNil(PreviewCache);
      PreviewCache := Preview.Resample(pw, ph, rmFineResample) as TBGRABitmap;
    end;
    // on the fill layer: an image must not bloom
    FFill.PutImage(Round(X(boxX + boxW / 2) - pw / 2), Round(Y(boxY)), PreviewCache, dmDrawWithTransparency);
    FLayer.RectangleAntialias(X(boxX + boxW / 2) - pw / 2 - 2, Y(boxY) - 2,
      X(boxX + boxW / 2) + pw / 2 + 2, Y(boxY) + ph + 2, Ice(140), 1);
  end
  else
    for i := 0 to Min(PreviewLines.Count - 1, Floor(boxH / 11) - 1) do
      TxtCached(boxX + 2, boxY + 6 + i * 11, FitText(PreviewLines[i], Floor((boxW - 4) / 4)), 6.5,
        taLeftJustify, Ice(200));
end;

procedure TInfoTextWidget.DefineDirty;
begin
  AddDirty(8, 30, FW - 6, FH - 6);
end;

procedure TInfoTextWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %.0f x %.0f, title "%s".', [FW, FH, FTitle]));
  L.Add('  Rows     label (size 7, Ice) above value (size 8, white), every 32 units');
  L.Add('  Preview  image scaled to fit (max 2x), drawn without glow, or up to');
  L.Add('           the first text lines (size 6.5)');
end;

{ ---------- THUDFileBrowserWidget ---------- }

constructor THUDFileBrowserWidget.Create;
begin
  inherited Create;
  SetView(1240, 724);
  SetParamByName('Max zoom', 2);
  SetParamByName('Glow intensity', 0.8);
  AddParam('Show hidden', 'Browser', '1 = also list hidden and system files.', FShowHidden, 0, 1, 0, False);
  FPlacePaths := TStringList.Create;

  Places := THUDListWidget.CreateList(300, 330, '\\PLACES & DRIVES');
  AddChild(Places, 10, 10, 'Places & drives');
  DriveGauge := TPillLoaderWidget.Create;
  DriveGauge.SetParamByName('Auto progress', 0);
  AddChild(DriveGauge, 10, 346, 'Drive usage (Pill Loader)');
  Stats := TInfoTextWidget.CreateInfo(300, 280, '\\FOLDER');
  AddChild(Stats, 10, 434, 'Folder statistics');
  PathBar := TPathBarWidget.Create;
  AddChild(PathBar, 320, 10, 'Path bar');
  Files := THUDListWidget.CreateList(600, 640, '\\CONTENTS');
  Files.EmptyText := 'EMPTY FOLDER';
  AddChild(Files, 320, 74, 'Folder listing');
  Details := TInfoTextWidget.CreateInfo(300, 640, '\\DETAILS');
  AddChild(Details, 930, 74, 'Details & preview');

  FillPlaces;
  Navigate(ExtractFilePath(Application.ExeName));
end;

destructor THUDFileBrowserWidget.Destroy;
begin
  FPlacePaths.Free;
  inherited Destroy;
end;

class function THUDFileBrowserWidget.UIName: string;
begin
  Result := 'HUD File Browser';
end;

class function THUDFileBrowserWidget.UIDescription: string;
begin
  Result := 'Open files and folders in the HUD style: places and drives, folder listing, details and ' +
    'preview. Double-click to open.';
end;

class function THUDFileBrowserWidget.UnitFile: string;
begin
  Result := 'HUDFileBrowser\uhudfilebrowser.pas';
end;

procedure THUDFileBrowserWidget.FillPlaces;

  procedure AddPlace(const ATitle, APath: string);
  begin
    if (APath <> '') and DirectoryExists(APath) then
    begin
      Places.Add(ATitle, '', ikPlace);
      FPlacePaths.Add(IncludeTrailingPathDelimiter(APath));
    end;
  end;

var
  mask: DWORD;
  i: integer;
  root, detail: string;
  freeB, totalB, totalFree: ULARGE_INTEGER;
  kind: UINT;
begin
  Places.Clear;
  FPlacePaths.Clear;
  AddPlace('Home', SpecialFolder(CSIDL_PROFILE));
  AddPlace('Desktop', SpecialFolder(CSIDL_DESKTOPDIRECTORY));
  AddPlace('Documents', SpecialFolder(CSIDL_PERSONAL));
  AddPlace('Downloads', IncludeTrailingPathDelimiter(SpecialFolder(CSIDL_PROFILE)) + 'Downloads');
  AddPlace('Pictures', SpecialFolder(CSIDL_MYPICTURES));
  AddPlace('Music', SpecialFolder(CSIDL_MYMUSIC));
  AddPlace('Videos', SpecialFolder(CSIDL_MYVIDEO));
  mask := GetLogicalDrives;
  for i := 0 to 25 do
    if (mask and (1 shl i)) <> 0 then
    begin
      root := Chr(Ord('A') + i) + ':\';
      kind := GetDriveTypeA(PChar(root));
      detail := '';
      // only local fixed / removable drives are measured (no CD or network waits)
      if (kind = DRIVE_FIXED) or (kind = DRIVE_REMOVABLE) then
        if GetDiskFreeSpaceExA(PChar(root), @freeB, @totalB, @totalFree) and (totalB.QuadPart > 0) then
          detail := Format('%d%% of %s', [Round(100 - 100 * freeB.QuadPart / totalB.QuadPart),
            FormatSize(totalB.QuadPart)]);
      if kind = DRIVE_REMOTE then detail := 'network';
      if kind = DRIVE_CDROM then detail := 'optical';
      Places.Add(root, detail, ikDrive);
      FPlacePaths.Add(root);
    end;
end;

procedure THUDFileBrowserWidget.UpdateDrive;
var
  root: string;
  freeB, totalB, totalFree: ULARGE_INTEGER;
  pct: single;
begin
  root := ExtractFileDrive(Path) + '\';
  pct := 0;
  if GetDiskFreeSpaceExA(PChar(root), @freeB, @totalB, @totalFree) and (totalB.QuadPart > 0) then
  begin
    pct := 100 - 100 * freeB.QuadPart / totalB.QuadPart;
    DriveGauge.Caption := Format('DRIVE %s  %s FREE OF %s', [ExtractFileDrive(Path),
      FormatSize(freeB.QuadPart), FormatSize(totalB.QuadPart)]);
  end
  else
    DriveGauge.Caption := 'DRIVE ' + ExtractFileDrive(Path);
  DriveGauge.SetParamValue(DriveGauge.ParamIndex('Progress %'), pct);
end;

procedure THUDFileBrowserWidget.Navigate(const APath: string);
var
  sr: TSearchRec;
  n, i, j: integer;
  tmp: TEntry;
  mask: integer;
begin
  if not DirectoryExists(APath) then
  begin
    FListError := 'Folder not found: ' + APath;
    Exit;
  end;
  Path := IncludeTrailingPathDelimiter(APath);
  PathBar.PathText := Path;
  FEntries := nil;
  FTotalSize := 0;
  FDirCount := 0;
  FFileCount := 0;
  FListError := '';
  mask := faAnyFile;
  if FindFirst(Path + '*', mask, sr) = 0 then
  try
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then Continue;
      if (FShowHidden < 1) and ((sr.Attr and (faHidden or faSysFile)) <> 0) then Continue;
      n := Length(FEntries);
      SetLength(FEntries, n + 1);
      FEntries[n].Name := sr.Name;
      FEntries[n].IsDir := (sr.Attr and faDirectory) <> 0;
      FEntries[n].Size := sr.Size;
      FEntries[n].Time := FileDateToDateTime(sr.Time);
      FEntries[n].Attr := sr.Attr;
      if FEntries[n].IsDir then Inc(FDirCount)
      else
      begin
        Inc(FFileCount);
        FTotalSize += sr.Size;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end
  else
    FListError := 'Cannot read this folder (access denied?)';
  // folders first, then files, each A..Z (simple insertion sort, fine for listings)
  for i := 1 to High(FEntries) do
  begin
    tmp := FEntries[i];
    j := i - 1;
    while (j >= 0) and ((Ord(FEntries[j].IsDir) < Ord(tmp.IsDir)) or
      ((FEntries[j].IsDir = tmp.IsDir) and (UTF8CompareText(FEntries[j].Name, tmp.Name) > 0))) do
    begin
      FEntries[j + 1] := FEntries[j];
      Dec(j);
    end;
    FEntries[j + 1] := tmp;
  end;
  Files.Clear;
  if Length(ExtractFileDir(ExcludeTrailingPathDelimiter(Path))) < Length(ExcludeTrailingPathDelimiter(Path)) then
    Files.Add('..', 'parent', ikUp);
  for i := 0 to High(FEntries) do
    if FEntries[i].IsDir then
      Files.Add(FEntries[i].Name, '<DIR>', ikFolder)
    else
      Files.Add(FEntries[i].Name, FormatSize(FEntries[i].Size) + '  ' +
        FormatDateTime('yyyy-mm-dd', FEntries[i].Time), ikFile);
  if FListError <> '' then Files.EmptyText := FListError else Files.EmptyText := 'EMPTY FOLDER';
  Stats.ClearInfo;
  Stats.Labels.Add('FOLDERS');   Stats.Values.Add(IntToStr(FDirCount));
  Stats.Labels.Add('FILES');     Stats.Values.Add(IntToStr(FFileCount));
  Stats.Labels.Add('FILE SIZE'); Stats.Values.Add(FormatSize(FTotalSize));
  Stats.Labels.Add('FOLDER');    Stats.Values.Add(ExtractFileName(ExcludeTrailingPathDelimiter(Path)));
  UpdateDrive;
  SelectFile(-1);
end;

procedure THUDFileBrowserWidget.Refresh;
begin
  Navigate(Path);
end;

procedure THUDFileBrowserWidget.GoUp;
var
  parent: string;
begin
  parent := ExtractFileDir(ExcludeTrailingPathDelimiter(Path));
  if (parent <> '') and (parent <> ExcludeTrailingPathDelimiter(Path)) then
    Navigate(parent);
end;

function THUDFileBrowserWidget.SelectedPath: string;
var
  e: integer;
begin
  Result := '';
  e := Files.Selected;
  if (Files.Count > 0) and (Files.Items[0] = '..') then Dec(e);
  if (e >= 0) and (e <= High(FEntries)) then Result := Path + FEntries[e].Name;
end;

procedure THUDFileBrowserWidget.UpdateDetails;
var
  e: integer;
  ent: TEntry;
  ext, attrs: string;
  F: TFileStream;
  buf: string;
  B: TBGRABitmap;
  n: integer;
begin
  Details.ClearInfo;
  e := Files.Selected;
  if (Files.Count > 0) and (Files.Items[0] = '..') then Dec(e);
  if (e < 0) or (e > High(FEntries)) then
  begin
    Details.Labels.Add('SELECTION');
    Details.Values.Add('nothing selected');
    Exit;
  end;
  ent := FEntries[e];
  ext := LowerCase(ExtractFileExt(ent.Name));
  Details.Labels.Add('NAME');      Details.Values.Add(ent.Name);
  Details.Labels.Add('TYPE');
  if ent.IsDir then Details.Values.Add('Folder')
  else if ext <> '' then Details.Values.Add(UpperCase(Copy(ext, 2, MaxInt)) + ' file')
  else Details.Values.Add('File');
  if not ent.IsDir then
  begin
    Details.Labels.Add('SIZE');
    Details.Values.Add(Format('%s  (%.0n bytes)', [FormatSize(ent.Size), ent.Size * 1.0]));
  end;
  Details.Labels.Add('MODIFIED');  Details.Values.Add(FormatDateTime('yyyy-mm-dd hh:nn:ss', ent.Time));
  attrs := '';
  if (ent.Attr and faReadOnly) <> 0 then attrs += 'read-only ';
  if (ent.Attr and faHidden) <> 0 then attrs += 'hidden ';
  if (ent.Attr and faSysFile) <> 0 then attrs += 'system ';
  if attrs = '' then attrs := 'normal';
  Details.Labels.Add('ATTRIBUTES'); Details.Values.Add(Trim(attrs));
  if ent.IsDir then Exit;
  // preview (synchronous, size-limited)
  try
    if IsImageExt(ext) and (ent.Size < 40 * 1024 * 1024) then
    begin
      B := TBGRABitmap.Create(Path + ent.Name);
      Details.SetPreviewImage(B);
      Details.Labels.Add('IMAGE');
      Details.Values.Add(Format('%d x %d px', [B.Width, B.Height]));
    end
    else if IsTextExt(ext) then
    begin
      F := TFileStream.Create(Path + ent.Name, fmOpenRead or fmShareDenyNone);
      try
        n := Min(F.Size, 6000);
        SetLength(buf, n);
        if n > 0 then F.ReadBuffer(buf[1], n);
      finally
        F.Free;
      end;
      buf := StringReplace(buf, #9, '  ', [rfReplaceAll]);
      Details.PreviewLines.Text := buf;
    end;
  except
    on E: Exception do
    begin
      Details.Labels.Add('PREVIEW');
      Details.Values.Add('not available: ' + E.Message);
    end;
  end;
end;

procedure THUDFileBrowserWidget.SelectFile(i: integer);
begin
  if i >= Files.Count then i := Files.Count - 1;
  Files.Selected := i;
  Files.EnsureVisible(i);
  UpdateDetails;
end;

procedure THUDFileBrowserWidget.OpenItem(i: integer);
var
  p: string;
begin
  if (i < 0) or (i >= Files.Count) then Exit;
  if Files.Items[i] = '..' then
  begin
    GoUp;
    Exit;
  end;
  SelectFile(i);
  p := SelectedPath;
  if p = '' then Exit;
  if DirectoryExists(p) then
    Navigate(p)
  else
    // the user double-clicked / pressed Enter: open with the default program
    ShellExecuteW(0, 'open', PWideChar(UTF8ToUTF16(p)), nil, PWideChar(UTF8ToUTF16(Path)), SW_SHOWNORMAL);
end;

procedure THUDFileBrowserWidget.OpenPlace(i: integer);
begin
  if (i < 0) or (i >= FPlacePaths.Count) then Exit;
  Places.Selected := i;
  Navigate(FPlacePaths[i]);
end;

procedure THUDFileBrowserWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('Canvas 1240 x 724 design units.');
  L.Add('');
  L.Add('LAYOUT');
  for i := 0 to ChildCount - 1 do
    L.Add(Format('  %-26s %-22s (%4.0f,%4.0f)', [ChildCaption(i), Children[i].ClassName,
      ChildOrigin(i).x, ChildOrigin(i).y]));
  L.Add('');
  L.Add('BEHAVIOUR');
  L.Add('  Listing    FindFirst/FindNext; folders first then files, A..Z (UTF-8 compare);');
  L.Add('             hidden/system files only with "Show hidden" = 1');
  L.Add('  Places     Windows known folders (SHGetFolderPath) + Downloads + drives;');
  L.Add('             only fixed / removable drives are measured');
  L.Add('  Open       double-click / Enter: folder -> enter, file -> ShellExecute "open"');
  L.Add('  Preview    png jpg bmp gif (< 40 MB) scaled to fit; text-like files: first 6 KB');
  L.Add('  Keys       arrows, PgUp/PgDn, Home/End, Enter, Backspace (parent), F5 (refresh)');
end;

procedure THUDFileBrowserWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add('Path                ' + Path);
  L.Add(Format('Folders / files     %d / %d  (%s)', [FDirCount, FFileCount, FormatSize(FTotalSize)]));
  L.Add('Selected            ' + SelectedPath);
  if FListError <> '' then L.Add('Error               ' + FListError);
end;

{ ---------- input wiring ---------- }

type
  TBrowserInput = class(TComponent)
  private
    FForm: THUDHostForm;
    FOldKeyDown: TKeyEvent;
    FHidden: TCheckBox;
    function B: THUDFileBrowserWidget;
    function ListUnder(px, py: integer; out L: THUDListWidget; out row: integer): boolean;
    procedure Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DblClick(Sender: TObject);
    procedure Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure UpClick(Sender: TObject);
    procedure HomeClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure ExplorerClick(Sender: TObject);
    procedure HiddenClick(Sender: TObject);
  end;

function TBrowserInput.B: THUDFileBrowserWidget;
begin
  Result := FForm.Widget as THUDFileBrowserWidget;
end;

function TBrowserInput.ListUnder(px, py: integer; out L: THUDListWidget; out row: integer): boolean;
var
  p, o: TPointF;
  i: integer;
begin
  Result := False;
  L := nil;
  row := -1;
  p := B.PixelToDesign(px, py);
  for i := 0 to B.ChildCount - 1 do
    if B.Children[i] is THUDListWidget then
    begin
      o := B.ChildOrigin(i);
      if (p.x >= o.x) and (p.y >= o.y) and (p.x < o.x + B.Children[i].DesignWidth) and
         (p.y < o.y + B.Children[i].DesignHeight) then
      begin
        L := THUDListWidget(B.Children[i]);
        row := L.RowAt(p.x - o.x, p.y - o.y);
        Exit(True);
      end;
    end;
end;

procedure TBrowserInput.Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  L: THUDListWidget;
  row: integer;
begin
  B.Places.Hover := -1;
  B.Files.Hover := -1;
  if ListUnder(X, Y, L, row) then L.Hover := row;
end;

procedure TBrowserInput.Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  L: THUDListWidget;
  row: integer;
begin
  FForm.View.SetFocus;
  if (Button <> mbLeft) or not ListUnder(X, Y, L, row) or (row < 0) then Exit;
  if L = B.Places then B.OpenPlace(row)       // one click on a place navigates
  else if L = B.Files then B.SelectFile(row);
end;

procedure TBrowserInput.DblClick(Sender: TObject);
var
  pt: TPoint;
  L: THUDListWidget;
  row: integer;
begin
  pt := FForm.View.ScreenToClient(Mouse.CursorPos);
  if ListUnder(pt.X, pt.Y, L, row) and (L = B.Files) and (row >= 0) then
    B.OpenItem(row);
end;

procedure TBrowserInput.Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  L: THUDListWidget;
  row: integer;
begin
  if ListUnder(MousePos.X, MousePos.Y, L, row) then
  begin
    L.ScrollBy(-Sign(WheelDelta) * 3);
    Handled := True;
  end;
end;

procedure TBrowserInput.KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  F: THUDListWidget;
  page: integer;
begin
  if FForm.ActiveControl = FForm.View then
  begin
    F := B.Files;
    page := Max(1, Floor((F.DesignHeight - 50) / F.RowH) - 1);
    case Key of
      VK_UP: B.SelectFile(Max(0, F.Selected - 1));
      VK_DOWN: B.SelectFile(Min(F.Count - 1, F.Selected + 1));
      VK_PRIOR: B.SelectFile(Max(0, F.Selected - page));
      VK_NEXT: B.SelectFile(Min(F.Count - 1, F.Selected + page));
      VK_HOME: B.SelectFile(0);
      VK_END: B.SelectFile(F.Count - 1);
      VK_RETURN: B.OpenItem(F.Selected);
      VK_BACK: B.GoUp;
      VK_F5: B.Refresh;
    else
      if Assigned(FOldKeyDown) then FOldKeyDown(Sender, Key, Shift);
      Exit;
    end;
    Key := 0;
    Exit;
  end;
  if Assigned(FOldKeyDown) then FOldKeyDown(Sender, Key, Shift);
end;

procedure TBrowserInput.UpClick(Sender: TObject);
begin
  B.GoUp;
end;

procedure TBrowserInput.HomeClick(Sender: TObject);
begin
  B.OpenPlace(0);
end;

procedure TBrowserInput.RefreshClick(Sender: TObject);
begin
  B.Refresh;
end;

procedure TBrowserInput.OpenClick(Sender: TObject);
begin
  B.OpenItem(B.Files.Selected);
end;

procedure TBrowserInput.ExplorerClick(Sender: TObject);
var
  p: string;
begin
  p := B.SelectedPath;
  if p <> '' then
    ShellExecuteW(0, 'open', 'explorer.exe', PWideChar(UTF8ToUTF16('/select,"' + p + '"')), nil, SW_SHOWNORMAL)
  else
    ShellExecuteW(0, 'open', PWideChar(UTF8ToUTF16(B.Path)), nil, nil, SW_SHOWNORMAL);
end;

procedure TBrowserInput.HiddenClick(Sender: TObject);
begin
  B.SetParamValue(B.ParamIndex('Show hidden'), Ord(FHidden.Checked));
  B.Refresh;
  FForm.RefreshInfo;
end;

procedure SetupBrowser(AForm: THUDHostForm);
var
  inp: TBrowserInput;
  Bar: TFlowPanel;

  procedure Btn(const ACaption: string; AClick: TNotifyEvent);
  var
    Bt: TButton;
  begin
    Bt := TButton.Create(AForm);
    Bt.Parent := Bar;
    Bt.Caption := ACaption;
    Bt.AutoSize := True;
    Bt.OnClick := AClick;
    Bt.BorderSpacing.Around := 2;
  end;

begin
  if not (AForm.Widget is THUDFileBrowserWidget) then Exit;
  inp := TBrowserInput.Create(AForm);
  inp.FForm := AForm;
  Bar := TFlowPanel.Create(AForm);
  Bar.Parent := AForm;
  Bar.Align := alTop;
  Bar.AutoSize := True;
  Bar.BevelOuter := bvNone;
  Bar.BorderSpacing.Around := 2;
  Btn('Up', @inp.UpClick);
  Btn('Home', @inp.HomeClick);
  Btn('Refresh', @inp.RefreshClick);
  Btn('Open', @inp.OpenClick);
  Btn('Show in Explorer', @inp.ExplorerClick);
  inp.FHidden := TCheckBox.Create(AForm);
  inp.FHidden.Parent := Bar;
  inp.FHidden.Caption := 'Show hidden';
  inp.FHidden.BorderSpacing.Around := 6;
  inp.FHidden.OnClick := @inp.HiddenClick;
  AForm.View.OnMouseMove := @inp.Move;
  AForm.View.OnMouseDown := @inp.Down;
  AForm.View.OnDblClick := @inp.DblClick;
  AForm.View.OnMouseWheel := @inp.Wheel;
  inp.FOldKeyDown := AForm.OnKeyDown;
  AForm.OnKeyDown := @inp.KeyDown;
  AForm.SetStatus('Click: select   Double-click / Enter: open   Backspace: up   Wheel: scroll   F5: refresh');
  // HUDFileBrowser.exe --path <folder>
  if (ParamCount >= 2) and (ParamStr(1) = '--path') then
    (AForm.Widget as THUDFileBrowserWidget).Navigate(ParamStr(2));
end;

initialization
  HostSetupProc := @SetupBrowser;

end.
