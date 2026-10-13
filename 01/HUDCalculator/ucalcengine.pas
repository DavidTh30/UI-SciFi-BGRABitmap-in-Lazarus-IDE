unit UCalcEngine;

{ Expression evaluator of HUD Calculator.

  Grammar (highest binding last):
    expr    := term { ('+' | '-') term }
    term    := unary { ('*' | '/') unary  |  implicit-multiply unary }
    unary   := ('+' | '-') unary | power
    power   := postfix [ '^' unary ]            (right-associative, -2^2 = -4)
    postfix := primary { '!' | '%' }
    primary := number | 'pi' | 'e' | 'ans' | func '(' expr ')' | '(' expr ')'
    func    := sin cos tan asin acos atan ln log sqrt abs exp

  Implicit multiplication: 2pi, 3(4+1), (1+2)(3+4), 2sin(30).
  Missing closing parentheses at the end are added automatically.
  Errors raise ECalcError with a readable message. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math;

type
  ECalcError = class(Exception);

  { TCalcEngine }

  TCalcEngine = class
  private
    FS: string;
    FPos: integer;
    procedure SkipSpaces;
    function Peek: char;
    function Expr: double;
    function Term: double;
    function Unary: double;
    function Power_: double;
    function Postfix: double;
    function Primary: double;
    function StartsPrimary: boolean;
    function ReadIdent: string;
    function ToRad(v: double): double;
    function FromRad(v: double): double;
    function Check(v: double): double;
  public
    Degrees: boolean;
    Ans: double;
    function Evaluate(const AExpr: string): double;
  end;

function FormatResult(v: double): string;

implementation

function FormatResult(v: double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if IsNan(v) then Exit('NaN');
  if IsInfinite(v) then Exit('Infinity');
  // 12 significant digits hides binary noise such as 0.1 + 0.2 = 0.30000000000000004
  Result := FloatToStrF(v, ffGeneral, 12, 0, fs);
  if Result = '-0' then Result := '0';
end;

{ TCalcEngine }

procedure TCalcEngine.SkipSpaces;
begin
  while (FPos <= Length(FS)) and (FS[FPos] = ' ') do Inc(FPos);
end;

function TCalcEngine.Peek: char;
begin
  SkipSpaces;
  if FPos <= Length(FS) then Result := FS[FPos] else Result := #0;
end;

function TCalcEngine.Check(v: double): double;
begin
  if IsNan(v) then raise ECalcError.Create('Undefined result');
  if IsInfinite(v) then raise ECalcError.Create('Overflow');
  Result := v;
end;

function TCalcEngine.ToRad(v: double): double;
begin
  if Degrees then Result := DegToRad(v) else Result := v;
end;

function TCalcEngine.FromRad(v: double): double;
begin
  if Degrees then Result := RadToDeg(v) else Result := v;
end;

function TCalcEngine.Evaluate(const AExpr: string): double;
var
  depth, i: integer;
begin
  FS := LowerCase(AExpr);
  // auto-close missing parentheses
  depth := 0;
  for i := 1 to Length(FS) do
    if FS[i] = '(' then Inc(depth)
    else if FS[i] = ')' then Dec(depth);
  if depth < 0 then raise ECalcError.Create('Unbalanced ")"');
  FS := FS + StringOfChar(')', depth);
  FPos := 1;
  if Trim(FS) = '' then raise ECalcError.Create('Empty expression');
  try
    Result := Expr;
  except
    // FPU errors (10^400, exp(1000), ...) become calculator messages
    on E: EOverflow do raise ECalcError.Create('Overflow');
    on E: EUnderflow do Result := 0;
    on E: EZeroDivide do raise ECalcError.Create('Division by zero');
    on E: EInvalidOp do raise ECalcError.Create('Undefined result');
  end;
  if Peek <> #0 then raise ECalcError.CreateFmt('Unexpected "%s"', [Peek]);
  Result := Check(Result);
end;

function TCalcEngine.Expr: double;
var
  c: char;
begin
  Result := Term;
  repeat
    c := Peek;
    if c = '+' then begin Inc(FPos); Result := Check(Result + Term); end
    else if c = '-' then begin Inc(FPos); Result := Check(Result - Term); end
    else Break;
  until False;
end;

function TCalcEngine.StartsPrimary: boolean;
var
  c: char;
begin
  c := Peek;
  Result := (c in ['0'..'9', '.', '(', 'a'..'z']) or (c = #$CF) {UTF-8 lead byte of π};
end;

function TCalcEngine.Term: double;
var
  c: char;
  d: double;
begin
  Result := Unary;
  repeat
    c := Peek;
    if c = '*' then begin Inc(FPos); Result := Check(Result * Unary); end
    else if c = '/' then
    begin
      Inc(FPos);
      d := Unary;
      if d = 0 then raise ECalcError.Create('Division by zero');
      Result := Check(Result / d);
    end
    else if StartsPrimary then
      Result := Check(Result * Unary)      // implicit multiplication
    else Break;
  until False;
end;

function TCalcEngine.Unary: double;
var
  c: char;
begin
  c := Peek;
  // Unary() with parentheses: a bare "Unary" here would be the result variable
  if c = '-' then begin Inc(FPos); Result := -Unary(); end
  else if c = '+' then begin Inc(FPos); Result := Unary(); end
  else Result := Power_;
end;

function TCalcEngine.Power_: double;
var
  b, ex: double;
begin
  b := Postfix;
  if Peek = '^' then
  begin
    Inc(FPos);
    ex := Unary;
    if (b < 0) and (Frac(ex) <> 0) then raise ECalcError.Create('Negative base needs an integer power');
    if (b = 0) and (ex < 0) then raise ECalcError.Create('Division by zero');
    Result := Check(Math.Power(b, ex));
  end
  else
    Result := b;
end;

function TCalcEngine.Postfix: double;
var
  c: char;
  i, n: integer;
begin
  Result := Primary;
  repeat
    c := Peek;
    if c = '!' then
    begin
      Inc(FPos);
      if (Frac(Result) <> 0) or (Result < 0) or (Result > 170) then
        raise ECalcError.Create('n! needs a whole number 0..170');
      n := Round(Result);
      Result := 1;
      for i := 2 to n do Result := Result * i;
    end
    else if c = '%' then
    begin
      Inc(FPos);
      Result := Result / 100;
    end
    else Break;
  until False;
end;

function TCalcEngine.ReadIdent: string;
begin
  Result := '';
  SkipSpaces;
  while (FPos <= Length(FS)) and (FS[FPos] in ['a'..'z']) do
  begin
    Result += FS[FPos];
    Inc(FPos);
  end;
end;

function TCalcEngine.Primary: double;
var
  c: char;
  start: integer;
  id, num: string;
  arg, deg: double;
  fmt: TFormatSettings;
begin
  c := Peek;
  if c = '(' then
  begin
    Inc(FPos);
    Result := Expr;
    if Peek <> ')' then raise ECalcError.Create('Missing ")"');
    Inc(FPos);
    Exit;
  end;
  if c in ['0'..'9', '.'] then
  begin
    start := FPos;
    while (FPos <= Length(FS)) and (FS[FPos] in ['0'..'9', '.']) do Inc(FPos);
    // scientific notation: 1.5e3, 2e-4 (only when digits follow the e)
    if (FPos < Length(FS)) and (FS[FPos] = 'e') and
       ((FS[FPos + 1] in ['0'..'9']) or ((FPos + 1 < Length(FS)) and (FS[FPos + 1] in ['+', '-']) and
        (FS[FPos + 2] in ['0'..'9']))) then
    begin
      Inc(FPos, 2);
      while (FPos <= Length(FS)) and (FS[FPos] in ['0'..'9']) do Inc(FPos);
    end;
    num := Copy(FS, start, FPos - start);
    fmt := DefaultFormatSettings;
    fmt.DecimalSeparator := '.';
    if not TryStrToFloat(num, Result, fmt) then raise ECalcError.CreateFmt('Bad number "%s"', [num]);
    Exit;
  end;
  // π written as the UTF-8 character
  if (c = #$CF) and (FPos < Length(FS)) and (FS[FPos + 1] = #$80) then
  begin
    Inc(FPos, 2);
    Exit(Pi);
  end;
  id := ReadIdent;
  if id = '' then
  begin
    if c = #0 then raise ECalcError.Create('Incomplete expression')
    else raise ECalcError.CreateFmt('Unexpected "%s"', [c]);
  end;
  if id = 'pi' then Exit(Pi);
  if id = 'e' then Exit(Exp(1));
  if id = 'ans' then Exit(Ans);
  if Peek <> '(' then raise ECalcError.CreateFmt('"%s" needs "(" ', [id]);
  Inc(FPos);
  arg := Expr;
  if Peek <> ')' then raise ECalcError.Create('Missing ")"');
  Inc(FPos);
  if id = 'sin' then
  begin
    // exact zeros at multiples of 180 degrees
    if Degrees and (Frac(arg / 180) = 0) then Exit(0);
    Result := Sin(ToRad(arg));
  end
  else if id = 'cos' then
  begin
    if Degrees and (Frac((arg - 90) / 180) = 0) then Exit(0);
    Result := Cos(ToRad(arg));
  end
  else if id = 'tan' then
  begin
    deg := arg;
    if not Degrees then deg := RadToDeg(arg);
    if Degrees and (Frac((deg - 90) / 180) = 0) then raise ECalcError.Create('tan is undefined here');
    if Degrees and (Frac(deg / 180) = 0) then Exit(0);
    Result := Tan(ToRad(arg));
  end
  else if id = 'asin' then
  begin
    if Abs(arg) > 1 then raise ECalcError.Create('asin needs -1..1');
    Result := FromRad(ArcSin(arg));
  end
  else if id = 'acos' then
  begin
    if Abs(arg) > 1 then raise ECalcError.Create('acos needs -1..1');
    Result := FromRad(ArcCos(arg));
  end
  else if id = 'atan' then Result := FromRad(ArcTan(arg))
  else if id = 'ln' then
  begin
    if arg <= 0 then raise ECalcError.Create('ln needs a positive number');
    Result := Ln(arg);
  end
  else if id = 'log' then
  begin
    if arg <= 0 then raise ECalcError.Create('log needs a positive number');
    Result := Log10(arg);
  end
  else if id = 'sqrt' then
  begin
    if arg < 0 then raise ECalcError.Create('Square root of a negative number');
    Result := Sqrt(arg);
  end
  else if id = 'abs' then Result := Abs(arg)
  else if id = 'exp' then Result := Check(Exp(arg))
  else
    raise ECalcError.CreateFmt('Unknown function "%s"', [id]);
end;

end.
