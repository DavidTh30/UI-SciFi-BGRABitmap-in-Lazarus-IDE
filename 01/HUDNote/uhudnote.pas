unit UHUDNote;

{ HUD Note - notes in the Sci-Fi HUD style.

  Left: search box and the list of notes (newest first). Right: header with
  the note title and save state, and a real text editor (TMemo placed over
  the HUD frame, so typing, selection, clipboard and undo work as usual).
  Bottom: kit loaders for words / characters / lines.

  Notes are plain UTF-8 .txt files in <exe folder>\notes. The title of a note
  is its first non-empty line. Changes are saved automatically one second
  after the last keystroke, when switching notes and when closing.
  Keys: Ctrl+N new, Ctrl+S save, Ctrl+F search, Ctrl+Delete delete note. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, DateUtils, LazUTF8, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  LCLType, LCLIntf, BGRABitmap, BGRABitmapTypes, HUDCore, HUDHost, HUDPanels,
  UChevronLoader, UBlockLoader, UPillLoader;

type
  TNote = record
    FileName: string;
    Title: string;
    Text: string;
    Modified: TDateTime;
  end;

  { TNoteHeaderWidget }

  TNoteHeaderWidget = class(THUDWidget)
  public
    TitleText, StateText: string;
    Dirty: boolean;
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

  { THUDNoteWidget }

  THUDNoteWidget = class(THUDComposite)
  private
    FWordGoal, FCharGoal, FLineGoal: single;
  public
    Notes: array of TNote;
    Visible_: array of integer;     // list row -> note index (search filter)
    Current: integer;               // note index being edited, -1 = none
    List: THUDListWidget;
    Search: TFrameWidget;
    Editor: TFrameWidget;
    Header: TNoteHeaderWidget;
    Words: TChevronLoaderWidget;
    Chars: TBlockLoaderWidget;
    Lines: TPillLoaderWidget;
    Filter: string;
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
    function NotesDir: string;
    procedure LoadAll;
    procedure RebuildList;
    function SaveNote(i: integer): boolean;
    function NewNote: integer;
    function BringToTop(i: integer): integer;  // returns the new index of note i (0)
    procedure DeleteNote(i: integer);
    procedure UpdateCounters(const AText: string; lineCount: integer);
  end;

function NoteTitle(const AText: string): string;
function WordCount(const AText: string): integer;

implementation

function NoteTitle(const AText: string): string;
var
  L: TStringList;
  i: integer;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Text := AText;
    for i := 0 to L.Count - 1 do
      if Trim(L[i]) <> '' then
      begin
        Result := UTF8Copy(Trim(L[i]), 1, 60);
        Break;
      end;
  finally
    L.Free;
  end;
  if Result = '' then Result := 'Untitled';
end;

function WordCount(const AText: string): integer;
var
  i: integer;
  inWord: boolean;
begin
  // whitespace-separated tokens (scripts without spaces, e.g. Thai, count per run)
  Result := 0;
  inWord := False;
  for i := 1 to Length(AText) do
    if AText[i] in [' ', #9, #10, #13] then inWord := False
    else if not inWord then
    begin
      inWord := True;
      Inc(Result);
    end;
end;

{ ---------- TNoteHeaderWidget ---------- }

constructor TNoteHeaderWidget.Create;
begin
  inherited Create;
  SetView(880, 52);
end;

class function TNoteHeaderWidget.UIName: string;
begin
  Result := 'Note Header';
end;

class function TNoteHeaderWidget.UIDescription: string;
begin
  Result := 'Title of the current note and its save state.';
end;

class function TNoteHeaderWidget.UnitFile: string;
begin
  Result := 'HUDNote\uhudnote.pas';
end;

procedure TNoteHeaderWidget.DrawStatic;
var
  i: integer;
begin
  FillPoly([0, 10, 10, 0, 880, 0, 880, 42, 870, 52, 0, 52], Steel(45));
  Polygon([0, 10, 10, 0, 880, 0, 880, 42, 870, 52, 0, 52], 1.3, Ice(180));
  for i := 0 to 5 do
    Line(820 + i * 7, 8, 827 + i * 7, 1, 2, White(200));
  Line(0, 16, 0, 42, 3, White);
end;

procedure TNoteHeaderWidget.DrawDynamic;
begin
  TxtCached(16, 22, FitText(TitleText, 70), 11, taLeftJustify);
  if Dirty then
  begin
    // pulsing marker while there are unsaved changes
    Disc(864, 26, 4, White(Round(140 + 115 * Abs(Sin(T * 4)))));
    TxtCached(852, 26, StateText, 7, taRightJustify, Ice(220));
  end
  else
  begin
    Disc(864, 26, 4, Ice(200));
    TxtCached(852, 26, StateText, 7, taRightJustify, Ice(170));
  end;
  TxtCached(16, 41, 'Ctrl+N new   Ctrl+S save   Ctrl+F search   Ctrl+Del delete', 6, taLeftJustify, Ice(130));
end;

procedure TNoteHeaderWidget.DefineDirty;
begin
  AddDirty(8, 6, 876, 50);
end;

procedure TNoteHeaderWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add('View 880 x 52: note title (size 11), save state at the right with a marker');
  L.Add('(pulsing white while unsaved, steady Ice when saved), shortcut hints.');
end;

{ ---------- THUDNoteWidget ---------- }

constructor THUDNoteWidget.Create;
begin
  inherited Create;
  SetView(1240, 770);
  SetParamByName('Max zoom', 2);
  SetParamByName('Glow intensity', 0.8);
  FWordGoal := 500;
  FCharGoal := 3000;
  FLineGoal := 100;
  AddParam('Word goal', 'Counters', 'Words that fill the WORDS loader.', FWordGoal, 10, 100000, 0, False);
  AddParam('Character goal', 'Counters', 'Characters that fill the CHARACTERS loader.', FCharGoal, 10, 1000000, 0, False);
  AddParam('Line goal', 'Counters', 'Lines that fill the LINES loader.', FLineGoal, 5, 100000, 0, False);
  Current := -1;

  Search := TFrameWidget.CreateFrame(330, 52, '');
  AddChild(Search, 10, 10, 'Search box');
  List := THUDListWidget.CreateList(330, 600, '\\NOTES');
  List.EmptyText := 'NO NOTES - CTRL+N TO START';
  AddChild(List, 10, 72, 'Note list');
  Header := TNoteHeaderWidget.Create;
  AddChild(Header, 350, 10, 'Note header');
  Editor := TFrameWidget.CreateFrame(880, 600, '\\EDITOR');
  AddChild(Editor, 350, 72, 'Editor frame');
  Words := TChevronLoaderWidget.Create;
  Words.Caption := 'WORDS';
  Words.SetParamByName('Auto progress', 0);
  AddChild(Words, 10, 684, 'Words (Chevron Loader)');
  Chars := TBlockLoaderWidget.Create;
  Chars.Caption := 'CHARACTERS';
  Chars.SetParamByName('Auto progress', 0);
  AddChild(Chars, 330, 684, 'Characters (Block Loader)');
  Lines := TPillLoaderWidget.Create;
  Lines.Caption := 'LINES';
  Lines.SetParamByName('Auto progress', 0);
  AddChild(Lines, 650, 684, 'Lines (Pill Loader)');
  LoadAll;
end;

class function THUDNoteWidget.UIName: string;
begin
  Result := 'HUD Note';
end;

class function THUDNoteWidget.UIDescription: string;
begin
  Result := 'Notes in the HUD style: search, note list, editor with autosave and word / character / line ' +
    'counters. Notes are .txt files next to the program.';
end;

class function THUDNoteWidget.UnitFile: string;
begin
  Result := 'HUDNote\uhudnote.pas';
end;

function THUDNoteWidget.NotesDir: string;
begin
  Result := ExtractFilePath(Application.ExeName) + 'notes' + PathDelim;
  ForceDirectories(Result);
end;

procedure THUDNoteWidget.LoadAll;
var
  sr: TSearchRec;
  n, i, j: integer;
  L: TStringList;
  tmp: TNote;
begin
  Notes := nil;
  L := TStringList.Create;
  try
    if FindFirst(NotesDir + '*.txt', faAnyFile, sr) = 0 then
    try
      repeat
        L.LoadFromFile(NotesDir + sr.Name);
        n := Length(Notes);
        SetLength(Notes, n + 1);
        Notes[n].FileName := sr.Name;
        Notes[n].Text := L.Text;
        Notes[n].Title := NoteTitle(L.Text);
        Notes[n].Modified := FileDateToDateTime(sr.Time);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
  finally
    L.Free;
  end;
  // newest first
  for i := 1 to High(Notes) do
  begin
    tmp := Notes[i];
    j := i - 1;
    while (j >= 0) and (Notes[j].Modified < tmp.Modified) do
    begin
      Notes[j + 1] := Notes[j];
      Dec(j);
    end;
    Notes[j + 1] := tmp;
  end;
  Current := -1;
  RebuildList;
end;

procedure THUDNoteWidget.RebuildList;
var
  i, n: integer;
  f: string;
begin
  List.Clear;
  Visible_ := nil;
  f := UTF8LowerCase(Filter);
  for i := 0 to High(Notes) do
    if (f = '') or (Pos(f, UTF8LowerCase(Notes[i].Text)) > 0) then
    begin
      n := Length(Visible_);
      SetLength(Visible_, n + 1);
      Visible_[n] := i;
      List.Add(Notes[i].Title, FormatDateTime('mm-dd hh:nn', Notes[i].Modified), ikNote);
      if i = Current then List.Selected := n;
    end;
  if Filter <> '' then
    List.SetTitle(Format('\\NOTES  %d / %d', [Length(Visible_), Length(Notes)]))
  else
    List.SetTitle(Format('\\NOTES  %d', [Length(Notes)]));
end;

function THUDNoteWidget.SaveNote(i: integer): boolean;
var
  L: TStringList;
begin
  Result := False;
  if (i < 0) or (i > High(Notes)) then Exit;
  L := TStringList.Create;
  try
    L.Text := Notes[i].Text;
    L.WriteBOM := False;
    L.SaveToFile(NotesDir + Notes[i].FileName);
    Notes[i].Modified := Now;
    Notes[i].Title := NoteTitle(Notes[i].Text);
    Result := True;
  finally
    L.Free;
  end;
end;

function THUDNoteWidget.NewNote: integer;
var
  i: integer;
begin
  // newest first: insert at the top
  SetLength(Notes, Length(Notes) + 1);
  for i := High(Notes) downto 1 do Notes[i] := Notes[i - 1];
  Notes[0].FileName := FormatDateTime('"note_"yyyymmdd"_"hhnnss"_"zzz', Now) + '.txt';
  Notes[0].Text := '';
  Notes[0].Title := 'Untitled';
  Notes[0].Modified := Now;
  SaveNote(0);
  Result := 0;
end;

function THUDNoteWidget.BringToTop(i: integer): integer;
var
  tmp: TNote;
  j: integer;
begin
  // newest first: a saved note moves to index 0
  Result := i;
  if (i <= 0) or (i > High(Notes)) then Exit;
  tmp := Notes[i];
  for j := i downto 1 do Notes[j] := Notes[j - 1];
  Notes[0] := tmp;
  if Current = i then Current := 0
  else if (Current >= 0) and (Current < i) then Inc(Current);
  Result := 0;
end;

procedure THUDNoteWidget.DeleteNote(i: integer);
var
  j: integer;
begin
  if (i < 0) or (i > High(Notes)) then Exit;
  DeleteFile(NotesDir + Notes[i].FileName);
  for j := i to High(Notes) - 1 do Notes[j] := Notes[j + 1];
  SetLength(Notes, Length(Notes) - 1);
  Current := -1;
end;

procedure THUDNoteWidget.UpdateCounters(const AText: string; lineCount: integer);
var
  w, c: integer;
begin
  w := WordCount(AText);
  c := UTF8Length(StringReplace(StringReplace(AText, #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]));
  Words.Caption := Format('WORDS %d / %.0f', [w, FWordGoal]);
  Chars.Caption := Format('CHARACTERS %d / %.0f', [c, FCharGoal]);
  Lines.Caption := Format('LINES %d / %.0f', [lineCount, FLineGoal]);
  Words.SetParamValue(Words.ParamIndex('Progress %'), Min(100, 100 * w / FWordGoal));
  Chars.SetParamValue(Chars.ParamIndex('Progress %'), Min(100, 100 * c / FCharGoal));
  Lines.SetParamValue(Lines.ParamIndex('Progress %'), Min(100, 100 * lineCount / FLineGoal));
end;

procedure THUDNoteWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('Canvas 1240 x 770 design units.');
  L.Add('');
  L.Add('LAYOUT');
  for i := 0 to ChildCount - 1 do
    L.Add(Format('  %-28s %-22s (%4.0f,%4.0f)', [ChildCaption(i), Children[i].ClassName,
      ChildOrigin(i).x, ChildOrigin(i).y]));
  L.Add('  + TEdit over "Search box" and TMemo over "Editor frame" (HUDPanels.PlaceControl)');
  L.Add('');
  L.Add('STORAGE');
  L.Add('  <exe>\notes\note_yyyymmdd_hhnnss_zzz.txt, UTF-8 without BOM, one note per file.');
  L.Add('  Title = first non-empty line (max 60 characters).');
  L.Add('  Autosave 1 s after the last change, when switching notes and on close.');
  L.Add('  Delete asks for confirmation and removes the file (it does not go to the');
  L.Add('  Recycle Bin).');
  L.Add('');
  L.Add('COUNTERS');
  L.Add('  Words = whitespace-separated tokens (languages written without spaces,');
  L.Add('  such as Thai, count one word per run), characters = UTF-8 characters');
  L.Add('  without line breaks, lines = editor lines.');
end;

procedure THUDNoteWidget.DescribeLive(L: TStrings);
begin
  inherited DescribeLive(L);
  L.Add('Notes folder        ' + NotesDir);
  L.Add(Format('Notes / shown       %d / %d', [Length(Notes), Length(Visible_)]));
  if Current >= 0 then L.Add('Editing             ' + Notes[Current].FileName);
  L.Add('Search              ' + Filter);
end;

{ ---------- controller: editor, search, keys ---------- }

type
  TNoteController = class(TComponent)
  private
    FForm: THUDHostForm;
    FMemo: TMemo;
    FEdit: TEdit;
    FTimer: TTimer;
    FDirty, FLoading, FCountDirty: boolean;
    FLastChange: TDateTime;
    FOldKeyDown: TKeyEvent;
    function W: THUDNoteWidget;
    procedure Open(noteIndex: integer);
    procedure UpdateHeader;
    procedure Place(Sender: TObject);
    procedure MemoChange(Sender: TObject);
    procedure SearchChange(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure NewClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure FolderClick(Sender: TObject);
    function ListRowAt(px, py: integer): integer;
  end;

function TNoteController.W: THUDNoteWidget;
begin
  Result := FForm.Widget as THUDNoteWidget;
end;

procedure TNoteController.Place(Sender: TObject);
var
  i: integer;
begin
  // keep the real controls exactly over their HUD frames (any window size)
  for i := 0 to W.ChildCount - 1 do
    if W.Children[i] = W.Editor then
      PlaceControl(FMemo, W, W.ChildOrigin(i), 16, 34, 864, 586)
    else if W.Children[i] = W.Search then
      PlaceControl(FEdit, W, W.ChildOrigin(i), 16, 16, 314, 40);
  FMemo.Font.Height := -Max(10, Round(15 * W.Scale));
  FEdit.Font.Height := -Max(10, Round(15 * W.Scale));
end;

procedure TNoteController.UpdateHeader;
begin
  if W.Current < 0 then
  begin
    W.Header.TitleText := 'NO NOTE SELECTED';
    W.Header.StateText := '';
    W.Header.Dirty := False;
    W.UpdateCounters('', 0);
    Exit;
  end;
  W.Header.TitleText := NoteTitle(FMemo.Text);
  W.Header.Dirty := FDirty;
  if FDirty then
    W.Header.StateText := 'EDITING - AUTOSAVE'
  else
    W.Header.StateText := 'SAVED ' + FormatDateTime('hh:nn:ss', W.Notes[W.Current].Modified);
  // counter captions are part of the static cache: refresh them on the
  // timer, not on every keystroke
  FCountDirty := True;
end;

procedure TNoteController.Open(noteIndex: integer);
begin
  FLoading := True;
  try
    W.Current := noteIndex;
    if noteIndex >= 0 then FMemo.Text := W.Notes[noteIndex].Text else FMemo.Clear;
    FMemo.Enabled := noteIndex >= 0;
    FDirty := False;
    W.RebuildList;
    UpdateHeader;
  finally
    FLoading := False;
  end;
end;

procedure TNoteController.MemoChange(Sender: TObject);
begin
  if FLoading or (W.Current < 0) then Exit;
  FDirty := True;
  FLastChange := Now;
  UpdateHeader;
end;

procedure TNoteController.Tick(Sender: TObject);
var
  cur: integer;
begin
  if FCountDirty then
  begin
    FCountDirty := False;
    if W.Current >= 0 then W.UpdateCounters(FMemo.Text, FMemo.Lines.Count)
    else W.UpdateCounters('', 0);
  end;
  // autosave one second after the last keystroke
  if FDirty and (MilliSecondsBetween(Now, FLastChange) >= 1000) and (W.Current >= 0) then
  begin
    cur := W.Current;
    W.Notes[cur].Text := FMemo.Text;
    if W.SaveNote(cur) then FDirty := False;
    W.BringToTop(cur);
    W.RebuildList;
    UpdateHeader;
  end;
end;

procedure TNoteController.SearchChange(Sender: TObject);
begin
  W.Filter := FEdit.Text;
  W.RebuildList;
end;

function TNoteController.ListRowAt(px, py: integer): integer;
var
  p, o: TPointF;
  i: integer;
begin
  Result := -1;
  p := W.PixelToDesign(px, py);
  for i := 0 to W.ChildCount - 1 do
    if W.Children[i] = W.List then
    begin
      o := W.ChildOrigin(i);
      if (p.x >= o.x) and (p.y >= o.y) and (p.x < o.x + W.List.DesignWidth) and (p.y < o.y + W.List.DesignHeight) then
        Result := W.List.RowAt(p.x - o.x, p.y - o.y)
      else
        Result := -2;   // outside the list
    end;
end;

procedure TNoteController.Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  row, target, cur: integer;
begin
  row := ListRowAt(X, Y);
  if (Button <> mbLeft) or (row < 0) or (row > High(W.Visible_)) then Exit;
  target := W.Visible_[row];
  if FDirty and (W.Current >= 0) and (W.Current <> target) then
  begin
    cur := W.Current;
    W.Notes[cur].Text := FMemo.Text;
    W.SaveNote(cur);
    W.BringToTop(cur);
    if target < cur then Inc(target);   // notes above the saved one shifted down
  end;
  Open(target);
  if FMemo.CanFocus then FMemo.SetFocus;
end;

procedure TNoteController.Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  W.List.Hover := Max(-1, ListRowAt(X, Y));
end;

procedure TNoteController.Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
begin
  if ListRowAt(MousePos.X, MousePos.Y) >= -1 then
  begin
    W.List.ScrollBy(-Sign(WheelDelta) * 3);
    Handled := True;
  end;
end;

procedure TNoteController.NewClick(Sender: TObject);
begin
  if FDirty and (W.Current >= 0) then
  begin
    W.Notes[W.Current].Text := FMemo.Text;
    W.SaveNote(W.Current);
  end;
  FEdit.Text := '';
  W.Filter := '';
  Open(W.NewNote);
  if FMemo.CanFocus then FMemo.SetFocus;
end;

procedure TNoteController.SaveClick(Sender: TObject);
begin
  if W.Current < 0 then Exit;
  W.Notes[W.Current].Text := FMemo.Text;
  if W.SaveNote(W.Current) then FDirty := False;
  W.BringToTop(W.Current);
  W.RebuildList;
  UpdateHeader;
  FForm.SetStatus('Saved ' + W.NotesDir + W.Notes[W.Current].FileName);
end;

procedure TNoteController.DeleteClick(Sender: TObject);
begin
  if W.Current < 0 then Exit;
  if MessageDlg('Delete note', 'Delete "' + W.Notes[W.Current].Title + '"?' + LineEnding +
    'The file is removed permanently.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  W.DeleteNote(W.Current);
  FDirty := False;
  Open(-1);
  FForm.SetStatus('Note deleted');
end;

procedure TNoteController.FolderClick(Sender: TObject);
begin
  OpenDocument(W.NotesDir);
end;

procedure TNoteController.KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if ssCtrl in Shift then
    case Key of
      VK_N: begin NewClick(nil); Key := 0; Exit; end;
      VK_S: begin SaveClick(nil); Key := 0; Exit; end;
      VK_F: begin FEdit.SetFocus; FEdit.SelectAll; Key := 0; Exit; end;
      VK_DELETE: begin DeleteClick(nil); Key := 0; Exit; end;
    end;
  if Assigned(FOldKeyDown) then FOldKeyDown(Sender, Key, Shift);
end;

procedure TNoteController.CloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FDirty and (W.Current >= 0) then
  begin
    W.Notes[W.Current].Text := FMemo.Text;
    W.SaveNote(W.Current);
  end;
  CanClose := True;
end;

procedure SetupNotes(AForm: THUDHostForm);
var
  C: TNoteController;
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
  if not (AForm.Widget is THUDNoteWidget) then Exit;
  C := TNoteController.Create(AForm);
  C.FForm := AForm;
  Bar := TFlowPanel.Create(AForm);
  Bar.Parent := AForm;
  Bar.Align := alTop;
  Bar.AutoSize := True;
  Bar.BevelOuter := bvNone;
  Bar.BorderSpacing.Around := 2;
  Btn('New', @C.NewClick);
  Btn('Save', @C.SaveClick);
  Btn('Delete', @C.DeleteClick);
  Btn('Open notes folder', @C.FolderClick);

  C.FMemo := TMemo.Create(AForm);
  C.FMemo.Parent := AForm.View;
  StyleControl(C.FMemo);
  C.FMemo.ScrollBars := ssAutoVertical;
  C.FMemo.WordWrap := True;
  C.FMemo.WantTabs := True;
  C.FMemo.OnChange := @C.MemoChange;
  C.FEdit := TEdit.Create(AForm);
  C.FEdit.Parent := AForm.View;
  StyleControl(C.FEdit);
  C.FEdit.TextHint := 'Search notes...';
  C.FEdit.OnChange := @C.SearchChange;
  C.FTimer := TTimer.Create(AForm);
  C.FTimer.Interval := 250;
  C.FTimer.OnTimer := @C.Tick;

  AForm.View.OnAfterPaint := @C.Place;
  AForm.View.OnMouseDown := @C.Down;
  AForm.View.OnMouseMove := @C.Move;
  AForm.View.OnMouseWheel := @C.Wheel;
  C.FOldKeyDown := AForm.OnKeyDown;
  AForm.OnKeyDown := @C.KeyDown;
  AForm.OnCloseQuery := @C.CloseQuery;
  AForm.SetStatus('Click a note to edit   Ctrl+N new   Ctrl+S save   Ctrl+F search   Ctrl+Del delete');
  // open the newest note, or start one
  if Length(C.W.Notes) = 0 then
  begin
    C.W.NewNote;
    C.W.Notes[0].Text := 'Welcome to HUD Note' + LineEnding + LineEnding +
      'Type here. Notes save automatically one second after you stop typing.' + LineEnding +
      'The first line is the title shown in the list.';
    C.W.SaveNote(0);
  end;
  C.Open(0);
end;

initialization
  HostSetupProc := @SetupNotes;

end.
