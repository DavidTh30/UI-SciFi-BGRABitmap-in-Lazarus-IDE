unit UTranslate;

{ Translation backend of HUD Translator: MyMemory (https://mymemory.translated.net).

  GET https://api.mymemory.translated.net/get?q=<text>&langpair=<src>|<dst>
  - free, no key; anonymous use is limited (about 5000 characters per day)
  - one request carries at most 500 bytes: longer text is split at sentence /
    line boundaries (never inside a UTF-8 character) and the pieces joined
  - responseStatus <> 200 (e.g. quota reached) is reported as an error
  The text you translate is sent to MyMemory. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, LazUTF8, fpjson, jsonparser, HUDNet;

type
  TLanguage = record
    Code, Name: string;
  end;

  TTranslation = record
    OK: boolean;
    Text: string;
    Match: double;        // 0..1 quality reported by MyMemory (lowest chunk)
    Error: string;
    Chunks: integer;
  end;

  TTranslateDone = procedure(const R: TTranslation) of object;

  { TTranslateJob }

  TTranslateJob = class(TThread)
  private
    FText, FSrc, FDst: string;
    FResult: TTranslation;
    FOnDone: TTranslateDone;
    procedure Deliver;
  protected
    procedure Execute; override;
  public
    constructor Start(const AText, ASrc, ADst: string; AOnDone: TTranslateDone);
  end;

const
  MaxChunkBytes = 450;    // MyMemory accepts 500 bytes per request

function LanguageCount: integer;
function Language(i: integer): TLanguage;
function LanguageIndex(const ACode: string): integer;
function TranslateText(const AText, ASrc, ADst: string): TTranslation;   // blocking
function SplitChunks(const AText: string): TStringList;

implementation

const
  Langs: array[0..27] of TLanguage = (
    (Code: 'autodetect'; Name: 'AUTO DETECT'),
    (Code: 'en'; Name: 'ENGLISH'),
    (Code: 'th'; Name: 'THAI'),
    (Code: 'ja'; Name: 'JAPANESE'),
    (Code: 'zh-CN'; Name: 'CHINESE (SIMPL.)'),
    (Code: 'zh-TW'; Name: 'CHINESE (TRAD.)'),
    (Code: 'ko'; Name: 'KOREAN'),
    (Code: 'vi'; Name: 'VIETNAMESE'),
    (Code: 'lo'; Name: 'LAO'),
    (Code: 'km'; Name: 'KHMER'),
    (Code: 'my'; Name: 'BURMESE'),
    (Code: 'ms'; Name: 'MALAY'),
    (Code: 'id'; Name: 'INDONESIAN'),
    (Code: 'hi'; Name: 'HINDI'),
    (Code: 'ar'; Name: 'ARABIC'),
    (Code: 'fr'; Name: 'FRENCH'),
    (Code: 'de'; Name: 'GERMAN'),
    (Code: 'es'; Name: 'SPANISH'),
    (Code: 'it'; Name: 'ITALIAN'),
    (Code: 'pt'; Name: 'PORTUGUESE'),
    (Code: 'nl'; Name: 'DUTCH'),
    (Code: 'ru'; Name: 'RUSSIAN'),
    (Code: 'uk'; Name: 'UKRAINIAN'),
    (Code: 'pl'; Name: 'POLISH'),
    (Code: 'tr'; Name: 'TURKISH'),
    (Code: 'sv'; Name: 'SWEDISH'),
    (Code: 'el'; Name: 'GREEK'),
    (Code: 'he'; Name: 'HEBREW'));

function LanguageCount: integer;
begin
  Result := Length(Langs);
end;

function Language(i: integer): TLanguage;
begin
  Result := Langs[EnsureRange(i, 0, High(Langs))];
end;

function LanguageIndex(const ACode: string): integer;
begin
  for Result := 0 to High(Langs) do
    if SameText(Langs[Result].Code, ACode) then Exit;
  Result := -1;
end;

function SplitChunks(const AText: string): TStringList;
var
  i, cut, start, n: integer;
  piece: string;
begin
  // greedy: take up to MaxChunkBytes, then step back to the last sentence end,
  // line break or space; never split a UTF-8 character
  Result := TStringList.Create;
  start := 1;
  n := Length(AText);
  while start <= n do
  begin
    if n - start + 1 <= MaxChunkBytes then
    begin
      Result.Add(Copy(AText, start, MaxInt));
      Break;
    end;
    cut := start + MaxChunkBytes - 1;
    i := cut;
    while (i > start + MaxChunkBytes div 3) and not (AText[i] in ['.', '!', '?', #10, ' ']) do Dec(i);
    if i > start + MaxChunkBytes div 3 then cut := i
    else
      // no boundary: back off to the start of a UTF-8 character
      while (cut > start) and ((Ord(AText[cut + 1]) and $C0) = $80) do Dec(cut);
    piece := Copy(AText, start, cut - start + 1);
    Result.Add(piece);
    start := cut + 1;
  end;
end;

function TranslateOne(const AText, ASrc, ADst: string; out Match: double): string;
var
  J: TJSONData;
  status: integer;
  details: string;
begin
  J := GetJSON(JsonDecodeUnicodeEscapes(HttpGet('https://api.mymemory.translated.net/get?q=' +
    UrlEncode(AText) + '&langpair=' + UrlEncode(ASrc) + '|' + UrlEncode(ADst), 'HUDTranslator/1.0')));
  try
    status := J.FindPath('responseStatus').AsInteger;
    Result := '';
    if J.FindPath('responseData.translatedText') <> nil then
      Result := J.FindPath('responseData.translatedText').AsString;
    if status <> 200 then
    begin
      details := Result;
      if details = '' then details := 'status ' + IntToStr(status);
      raise Exception.Create('MyMemory: ' + details);
    end;
    Match := 0;
    if (J.FindPath('responseData.match') <> nil) and (J.FindPath('responseData.match').JSONType = jtNumber) then
      Match := J.FindPath('responseData.match').AsFloat;
  finally
    J.Free;
  end;
end;

function TranslateText(const AText, ASrc, ADst: string): TTranslation;
var
  parts: TStringList;
  i: integer;
  m: double;
  piece: string;
begin
  Result := Default(TTranslation);
  Result.Match := 1;
  parts := SplitChunks(AText);
  try
    Result.Chunks := parts.Count;
    for i := 0 to parts.Count - 1 do
    begin
      if Trim(parts[i]) = '' then
      begin
        Result.Text += parts[i];
        Continue;
      end;
      piece := TranslateOne(parts[i], ASrc, ADst, m);
      // keep the spacing / line breaks between pieces
      if (Result.Text <> '') and (parts[i][1] in [' ', #10, #13]) then Result.Text += parts[i][1];
      Result.Text += piece;
      Result.Match := Min(Result.Match, m);
    end;
    Result.OK := True;
  finally
    parts.Free;
  end;
end;

{ TTranslateJob }

constructor TTranslateJob.Start(const AText, ASrc, ADst: string; AOnDone: TTranslateDone);
begin
  FText := AText;
  FSrc := ASrc;
  FDst := ADst;
  FOnDone := AOnDone;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TTranslateJob.Execute;
begin
  try
    FResult := TranslateText(FText, FSrc, FDst);
  except
    on E: Exception do
    begin
      FResult := Default(TTranslation);
      FResult.Error := E.Message;
    end;
  end;
  Synchronize(@Deliver);
end;

procedure TTranslateJob.Deliver;
begin
  if Assigned(FOnDone) then FOnDone(FResult);
end;

end.
