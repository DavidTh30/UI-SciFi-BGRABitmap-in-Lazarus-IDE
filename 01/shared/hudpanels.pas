unit HUDPanels;

{ Shared HUD building blocks for application-style programs
  (HUDNote, HUDMediaPlayer, HUDFileBrowser, HUDClock):

  TFrameWidget     chamfered HUD frame with a title (static only)
  THUDListWidget   scrollable list drawn in the HUD style: icon, text,
                   right-aligned detail, selection, hover, scrollbar
  PlaceControl     puts a real LCL control (TMemo, TEdit...) exactly over a
                   rectangle of a hosted widget, in pixels of the HUD view
  StyleControl     dark HUD colours for such a control }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, Controls, StdCtrls, LazUTF8,
  BGRABitmap, BGRABitmapTypes, HUDCore;

const
  // list item kinds (icon)
  ikNone = 0;
  ikFile = 1;
  ikFolder = 2;
  ikDrive = 3;
  ikUp = 4;
  ikPlace = 5;
  ikAudio = 6;
  ikPlaying = 7;
  ikNote = 8;

type

  { TFrameWidget }

  TFrameWidget = class(THUDWidget)
  private
    FTitle: string;
    FW, FH: single;
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
  public
    constructor CreateFrame(AW, AH: single; const ATitle: string);
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure SetTitle(const ATitle: string);
  end;

  { THUDListWidget }

  THUDListWidget = class(THUDWidget)
  private
    FW, FH: single;
    FTitle: string;
    function GetCount: integer;
    function VisibleRows: integer;
  public
    Items: TStringList;       // text
    Details: TStringList;     // right-aligned text
    Kinds: array of integer;  // ik* per item
    Selected, Hover, TopRow: integer;
    EmptyText: string;
    RowH: single;
    constructor CreateList(AW, AH: single; const ATitle: string);
    destructor Destroy; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
    procedure Clear;
    procedure Add(const AText, ADetail: string; AKind: integer);
    function RowAt(LocalX, LocalY: single): integer;   // -1 = none
    procedure ScrollBy(rows: integer);
    procedure EnsureVisible(i: integer);
    procedure SetTitle(const ATitle: string);
    property Count: integer read GetCount;
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
    procedure DrawIcon(kind: integer; ax, ay: single; c: TBGRAPixel);
  end;

procedure PlaceControl(C: TControl; Host: THUDWidget; Origin: TPointF; x1, y1, x2, y2: single);
procedure StyleControl(C: TControl);
function FitText(const S: string; maxChars: integer): string;

implementation

function FitText(const S: string; maxChars: integer): string;
begin
  // UTF-8 aware: never cut a multi-byte character
  if UTF8Length(S) <= maxChars then Exit(S);
  Result := UTF8Copy(S, 1, Max(1, maxChars - 1)) + '…';
end;

procedure PlaceControl(C: TControl; Host: THUDWidget; Origin: TPointF; x1, y1, x2, y2: single);
var
  a, b: TPointF;
  R: TRect;
begin
  a := Host.DesignToPixel(Origin.x + x1, Origin.y + y1);
  b := Host.DesignToPixel(Origin.x + x2, Origin.y + y2);
  R := Rect(Round(a.x), Round(a.y), Round(b.x), Round(b.y));
  if (C.Left <> R.Left) or (C.Top <> R.Top) or (C.Width <> R.Right - R.Left) or
     (C.Height <> R.Bottom - R.Top) then
    C.SetBounds(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
end;

procedure StyleControl(C: TControl);
begin
  C.Color := RGBToColor(14, 30, 50);
  C.Font.Color := RGBToColor(200, 228, 245);
  C.Font.Name := 'Consolas';
  C.Font.Size := 11;
  if C is TCustomMemo then TCustomMemo(C).BorderStyle := bsNone;
  if C is TCustomEdit then TCustomEdit(C).BorderStyle := bsNone;
end;

{ ---------- TFrameWidget ---------- }

constructor TFrameWidget.CreateFrame(AW, AH: single; const ATitle: string);
begin
  Create;
  FW := AW;
  FH := AH;
  FTitle := ATitle;
  SetView(AW, AH);
end;

class function TFrameWidget.UIName: string;
begin
  Result := 'Frame';
end;

class function TFrameWidget.UIDescription: string;
begin
  Result := 'Chamfered HUD frame with a title (static).';
end;

class function TFrameWidget.UnitFile: string;
begin
  Result := 'shared\hudpanels.pas';
end;

procedure TFrameWidget.SetTitle(const ATitle: string);
begin
  if ATitle = FTitle then Exit;
  FTitle := ATitle;
  InvalidateStatic;
end;

procedure TFrameWidget.DrawStatic;
var
  i: integer;
  notch: single;
begin
  notch := Min(FW * 0.62, FW - 60);
  FillPoly([0, 12, 12, 0, notch, 0, notch + 12, 12, FW, 12, FW, FH - 12, FW - 12, FH, 0, FH], Steel(45));
  Polygon([0, 12, 12, 0, notch, 0, notch + 12, 12, FW, 12, FW, FH - 12, FW - 12, FH, 0, FH], 1.3, Ice(180));
  for i := 0 to 4 do
    Line(notch - 46 + i * 7, 9, notch - 39 + i * 7, 2, 2, White(200));
  Line(FW, 28, FW, Min(90, FH - 20), 3, White);
  Line(0, FH - 50, 0, FH - 18, 3, White(200));
  if FTitle <> '' then Txt(16, 16, FTitle, 8, White(230));
end;

procedure TFrameWidget.DrawDynamic;
begin
end;

procedure TFrameWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %.0f x %.0f, title "%s".', [FW, FH, FTitle]));
  L.Add('Fill Steel a45, border w1.3 Ice a180, hatching at the notch, white side accents.');
end;

{ ---------- THUDListWidget ---------- }

constructor THUDListWidget.CreateList(AW, AH: single; const ATitle: string);
begin
  Create;
  FW := AW;
  FH := AH;
  FTitle := ATitle;
  RowH := 22;
  Items := TStringList.Create;
  Details := TStringList.Create;
  Selected := -1;
  Hover := -1;
  EmptyText := 'EMPTY';
  SetView(AW, AH);
end;

destructor THUDListWidget.Destroy;
begin
  Items.Free;
  Details.Free;
  inherited Destroy;
end;

class function THUDListWidget.UIName: string;
begin
  Result := 'HUD List';
end;

class function THUDListWidget.UIDescription: string;
begin
  Result := 'Scrollable list in the HUD style: icon, text, right-aligned detail, selection, hover, scrollbar.';
end;

class function THUDListWidget.UnitFile: string;
begin
  Result := 'shared\hudpanels.pas';
end;

function THUDListWidget.GetCount: integer;
begin
  Result := Items.Count;
end;

function THUDListWidget.VisibleRows: integer;
begin
  Result := Max(1, Floor((FH - 50) / RowH));
end;

procedure THUDListWidget.SetTitle(const ATitle: string);
begin
  if ATitle = FTitle then Exit;
  FTitle := ATitle;
  InvalidateStatic;
end;

procedure THUDListWidget.Clear;
begin
  Items.Clear;
  Details.Clear;
  Kinds := nil;
  Selected := -1;
  Hover := -1;
  TopRow := 0;
end;

procedure THUDListWidget.Add(const AText, ADetail: string; AKind: integer);
begin
  Items.Add(AText);
  Details.Add(ADetail);
  SetLength(Kinds, Items.Count);
  Kinds[High(Kinds)] := AKind;
end;

function THUDListWidget.RowAt(LocalX, LocalY: single): integer;
begin
  Result := -1;
  if (LocalX < 8) or (LocalX > FW - 14) or (LocalY < 40) then Exit;
  Result := TopRow + Floor((LocalY - 40) / RowH);
  if (Result >= Items.Count) or (Result >= TopRow + VisibleRows) then Result := -1;
end;

procedure THUDListWidget.ScrollBy(rows: integer);
begin
  TopRow := EnsureRange(TopRow + rows, 0, Max(0, Items.Count - VisibleRows));
end;

procedure THUDListWidget.EnsureVisible(i: integer);
begin
  if i < 0 then Exit;
  if i < TopRow then TopRow := i
  else if i >= TopRow + VisibleRows then TopRow := i - VisibleRows + 1;
  ScrollBy(0);
end;

procedure THUDListWidget.DrawStatic;
var
  notch: single;
begin
  notch := Min(FW * 0.62, FW - 60);
  FillPoly([0, 12, 12, 0, notch, 0, notch + 12, 12, FW, 12, FW, FH - 12, FW - 12, FH, 0, FH], Steel(45));
  Polygon([0, 12, 12, 0, notch, 0, notch + 12, 12, FW, 12, FW, FH - 12, FW - 12, FH, 0, FH], 1.3, Ice(180));
  Line(FW, 28, FW, Min(90, FH - 20), 3, White);
  if FTitle <> '' then Txt(16, 16, FTitle, 8, White(230));
end;

procedure THUDListWidget.DrawIcon(kind: integer; ax, ay: single; c: TBGRAPixel);
begin
  case kind of
    ikFolder:
      begin
        FillPoly([ax, ay - 5, ax + 4, ay - 5, ax + 6, ay - 3, ax + 12, ay - 3, ax + 12, ay + 5, ax, ay + 5], c);
      end;
    ikFile, ikNote:
      begin
        Polygon([ax + 1, ay - 6, ax + 7, ay - 6, ax + 10, ay - 3, ax + 10, ay + 6, ax + 1, ay + 6], 1, c);
        if kind = ikNote then
        begin
          Line(ax + 3, ay - 1, ax + 8, ay - 1, 0.8, c);
          Line(ax + 3, ay + 2, ax + 8, ay + 2, 0.8, c);
        end;
      end;
    ikDrive:
      begin
        Polygon([ax, ay - 4, ax + 12, ay - 4, ax + 12, ay + 4, ax, ay + 4], 1.2, c);
        Disc(ax + 9, ay, 1.3, c);
      end;
    ikUp:
      PolyLine([ax + 1, ay + 1, ax + 6, ay - 5, ax + 11, ay + 1], 1.6, c);
    ikPlace:
      Polygon([ax + 6, ay - 6, ax + 12, ay, ax + 6, ay + 6, ax, ay], 1.2, c);
    ikAudio:
      begin
        Line(ax + 8, ay - 6, ax + 8, ay + 3, 1.2, c);
        Disc(ax + 6, ay + 4, 2.3, c);
        Line(ax + 8, ay - 6, ax + 11, ay - 4, 1.2, c);
      end;
    ikPlaying:
      FillPoly([ax + 2, ay - 5, ax + 11, ay, ax + 2, ay + 5], c);
  end;
end;

procedure THUDListWidget.DrawDynamic;
var
  i, rows, maxChars, last: integer;
  ry, thumbH, thumbY: single;
  c: TBGRAPixel;
  detail: string;
begin
  rows := VisibleRows;
  if Items.Count = 0 then
  begin
    TxtCached(FW / 2, 40 + RowH * 1.5, EmptyText, 8, taCenter, Ice(150));
    Exit;
  end;
  TopRow := EnsureRange(TopRow, 0, Max(0, Items.Count - rows));
  last := Min(Items.Count - 1, TopRow + rows - 1);
  for i := TopRow to last do
  begin
    ry := 40 + (i - TopRow) * RowH;
    if i = Selected then
    begin
      FillPoly([8, ry + 1, FW - 16, ry + 1, FW - 16, ry + RowH - 1, 8, ry + RowH - 1], Steel(150));
      FLayer.FillRectAntialias(X(8), Y(ry + 1), X(11), Y(ry + RowH - 1), White);
    end
    else if i = Hover then
      FillPoly([8, ry + 1, FW - 16, ry + 1, FW - 16, ry + RowH - 1, 8, ry + RowH - 1], Steel(70));
    if i = Selected then c := White else c := Ice(210);
    if (i <= High(Kinds)) and (Kinds[i] <> ikNone) then
      DrawIcon(Kinds[i], 16, ry + RowH / 2, c);
    if i < Details.Count then detail := Details[i] else detail := '';
    // 7.5 pt Consolas is about 4.6 units per character
    maxChars := Max(4, Floor((FW - 70 - UTF8Length(detail) * 4.6) / 4.6));
    TxtCached(34, ry + RowH / 2, FitText(Items[i], maxChars), 7.5, taLeftJustify, c);
    if detail <> '' then
      TxtCached(FW - 22, ry + RowH / 2, detail, 7, taRightJustify, Ice(150));
  end;
  // scrollbar
  if Items.Count > rows then
  begin
    FLayer.FillRectAntialias(X(FW - 10), Y(40), X(FW - 7), Y(40 + rows * RowH), Steel(120));
    thumbH := Max(16, rows * RowH * rows / Items.Count);
    thumbY := 40 + (rows * RowH - thumbH) * TopRow / Max(1, Items.Count - rows);
    FLayer.FillRectAntialias(X(FW - 11), Y(thumbY), X(FW - 6), Y(thumbY + thumbH), Ice(230));
  end;
end;

procedure THUDListWidget.DefineDirty;
begin
  AddDirty(6, 32, FW - 4, FH - 6);
end;

procedure THUDListWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %.0f x %.0f, row height %.0f, %d visible rows.', [FW, FH, RowH, VisibleRows]));
  L.Add('  Rows      icon (folder/file/drive/place/up/audio/playing/note), text (UTF-8');
  L.Add('            safe ellipsis), right-aligned detail in muted Ice');
  L.Add('  Selected  Steel a150 bar + white edge; Hover Steel a70');
  L.Add('  Scroll    mouse wheel / keyboard; thumb on the right edge');
end;

procedure THUDListWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add(Format('Items / selected    %d / %d', [Items.Count, Selected]));
  L.Add(Format('Top row / hover     %d / %d', [TopRow, Hover]));
end;

end.
