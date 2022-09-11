unit yamlunicode;

interface

{$ifdef fpc}
{$mode delphi}{$H+}
{$define hasinline}
{$endif}

uses
  Classes;

// the unicode related utilities
// heavily depend on the compiler run-time

function ReplaceUtf8WhiteSpaces(const buf: string): string;

function UTF8HexToStr(const code: string): string;

implementation

// #E290A3 - open box

function ReplaceUtf8WhiteSpaces(const buf: string): string;
var
  j  : integer;
  i  : integer;
  ln : integer;
  cns : integer;
begin
  Result := '';
  j := 1;
  i := 1;
  ln := length(buf);
  while i<=ln do begin
    if (buf[i]= #$e2) then begin
      cns := 0;
      if (i+2<=ln) and (buf[i+1]=#$90) and (buf[i+2]=#$a3) then
        cns := 3;
      if cns>0 then begin
        Result := Result+Copy(buf, j,i-j)+' ';
        inc(i,cns);
        j:=i;
      end else
        inc(i);
    end else
      inc(i);
  end;
  if (Result = '') and (j = 1) then
    Result := buf
  else
    Result := Result+Copy(buf, j, length(buf)-j+1);
end;


function UTF8HexToStr(const code: string): string;
begin
 {$ifndef fpc}
 assert(false,'not implemented');
 {$else}
 SetLength(Result, length(code) div 2);
 HexToBin(@code[1], @Result[1], length(Result));
 {$endif}
end;

end.
