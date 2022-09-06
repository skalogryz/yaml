unit parseutils;

{$ifdef fpc}{$mode delphi}
{$define hasinline}{$endif}

interface

type
  TCharSet = set of char;

const
  WhiteSpaceChars = [#32,#9];
  AlphaChar = ['a'..'z','A'..'Z'];
  NumChars = ['0'..'9'];
  LineBreaks = [#10,#13];
  AlphaNumChars = AlphaChar+NumChars;
  AlphaNumUnderChars = AlphaNumChars+['_'];
  AlphaUnderChars = AlphaChar+['_'];

procedure SkipTo(const s: string; var idx: integer; const toChars: TCharSet); {$ifdef hasline}inline;{$endif}
function StrTo(const s: string; var idx: integer; const toChars: TCharSet): string; {$ifdef hasline}inline;{$endif}

procedure SkipWhile(const s: string; var idx: integer; const skipChars: TCharSet); {$ifdef hasline}inline;{$endif}
function StrWhile(const s: string; var idx: integer; const whileChars: TCharSet): string; {$ifdef hasline}inline;{$endif}

function ScanIdent(const s: string; var idx: integer; const InitChars, OtherChars: TCharSet): string; {$ifdef hasline}inline;{$endif}

function SafeChar(const s: string; idx: integer; const defChar: char = #0): char; {$ifdef hasline}inline;{$endif}

// skipping exactly one line break. Meaning #10#13 or #13#10 or #10 or #13
procedure SkipOneEoln(const s: string; var idx: integer);
function StrOneEoln(const s: string; var idx: integer): string;

implementation

function SafeChar(const s: string; idx: integer; const defChar: char = #0): char;
begin
  if (idx<=0) or (idx>length(s)) then Result := defChar
  else Result := s[idx];
end;

procedure SkipTo(const s: string; var idx: integer; const toChars: TCharSet); {$ifdef hasline}inline;{$endif}
begin
  while (idx<=length(s)) and not (s[idx] in toChars) do inc(idx);
end;

function StrTo(const s: string; var idx: integer; const toChars: TCharSet): string; {$ifdef hasline}inline;{$endif}
var
  j : integer;
begin
  j := idx;
  SkipTo(s, idx, toChars);
  Result := Copy(s, j, idx-j);
end;

procedure SkipWhile(const s: string; var idx: integer; const skipChars: TCharSet); {$ifdef hasline}inline;{$endif}
begin
  while (idx<=length(s)) and (s[idx] in skipChars) do inc(idx);
end;

function StrWhile(const s: string; var idx: integer; const whileChars: TCharSet): string; {$ifdef hasline}inline;{$endif}
var
  j : integer;
begin
  j := idx;
  SkipWhile(s, idx, whileChars);
  Result := Copy(s, j, idx-j);
end;

function ScanIdent(const s: string; var idx: integer; const InitChars, OtherChars: TCharSet): string; {$ifdef hasline}inline;{$endif}
var
  j : integer;
begin
  if (idx>length(s)) or not (s[idx] in InitChars) then begin
    Result := '';
    Exit;
  end;
  j := idx;
  inc(idx);
  SkipWhile(s, idx, OtherChars);
  Result := Copy(s, j, idx-j);
end;

procedure SkipOneEoln(const s: string; var idx: integer);
begin
  if (idx<0) or (idx>length(s)) then Exit;
  if s[idx] in LineBreaks then begin
    inc(idx);
    if (idx<=length(s)) and (s[idx] in LineBreaks) and (s[idx]<>s[idx-1]) then
      inc(idx);
  end;
end;

function StrOneEoln(const s: string; var idx: integer): string;
var
  j : integer;
begin
  j := idx;
  SkipOneEoln(s, idx);
  Result := Copy(s, j, idx-j);
end;

end.
