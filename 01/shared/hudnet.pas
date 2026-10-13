unit HUDNet;

{ Small HTTP helpers for HUD programs that read web APIs (Windows).
  HttpGet uses WinINet, so HTTPS works with Windows' own TLS stack and no
  OpenSSL DLLs. Call it from a background thread: it blocks. }

{$mode objfpc}{$H+}

interface

uses
  Windows, WinInet, Classes, SysUtils;

function HttpGet(const AUrl: string; const AAgent: string = 'HUDApp/1.0'): string;
function UrlEncode(const S: string): string;   // UTF-8 -> %XX
function JsonDecodeUnicodeEscapes(const S: string): string;

implementation

function UrlEncode(const S: string): string;
var
  i: integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'] then
      Result += S[i]
    else
      Result += '%' + IntToHex(Ord(S[i]), 2);
end;

function CodePointToUTF8(cp: cardinal): string;
begin
  if cp < $80 then Result := Chr(cp)
  else if cp < $800 then Result := Chr($C0 or (cp shr 6)) + Chr($80 or (cp and $3F))
  else if cp < $10000 then
    Result := Chr($E0 or (cp shr 12)) + Chr($80 or ((cp shr 6) and $3F)) + Chr($80 or (cp and $3F))
  else
    Result := Chr($F0 or (cp shr 18)) + Chr($80 or ((cp shr 12) and $3F)) + Chr($80 or ((cp shr 6) and $3F)) +
      Chr($80 or (cp and $3F));
end;

function JsonDecodeUnicodeEscapes(const S: string): string;
var
  i, n: integer;
  cp, lo: longint;
begin
  // FPC 3.2.2's fpjson corrupts runs of \uXXXX escapes (it drops every second
  // character). Turn them into UTF-8 before parsing; quote, backslash and
  // control characters stay escaped so the JSON remains valid.
  Result := '';
  i := 1;
  n := Length(S);
  while i <= n do
  begin
    if (S[i] = '\') and (i < n) then
    begin
      if (S[i + 1] = 'u') and (i + 5 <= n) then
      begin
        cp := StrToIntDef('$' + Copy(S, i + 2, 4), -1);
        if (cp >= $D800) and (cp <= $DBFF) and (i + 11 <= n) and (S[i + 6] = '\') and (S[i + 7] = 'u') then
        begin
          lo := StrToIntDef('$' + Copy(S, i + 8, 4), 0);
          if (lo >= $DC00) and (lo <= $DFFF) then
          begin
            Result += CodePointToUTF8($10000 + ((cp - $D800) shl 10) + (lo - $DC00));
            Inc(i, 12);
            Continue;
          end;
        end;
        if (cp >= $20) and (cp <> $22) and (cp <> $5C) and ((cp < $D800) or (cp > $DFFF)) then
        begin
          Result += CodePointToUTF8(cp);
          Inc(i, 6);
          Continue;
        end;
      end;
      // any other escape (\n, \", \\, control characters) is copied as is
      Result += S[i] + S[i + 1];
      Inc(i, 2);
      Continue;
    end;
    Result += S[i];
    Inc(i);
  end;
end;

function HttpGet(const AUrl: string; const AAgent: string): string;
var
  hNet, hUrl: HINTERNET;
  buf: array[0..16383] of byte;
  got: DWORD;
  ms: TStringStream;
  status, len, idx: DWORD;
begin
  Result := '';
  hNet := InternetOpenW(PWideChar(UnicodeString(AAgent)), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
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

end.
