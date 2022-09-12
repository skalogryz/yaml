program recparsersample;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, Classes, yamlrecparser, yamlunicode, yamltreetypes, yamltreeutils
  { you can add units after this };

procedure ParseYaml(const fn: string);
var
  fs : TFileStream;
  b  : string;
  rc : TYamlRecParser;
  i  : integer;
begin
  rc := TYamlRecParser.Create;
  fs := nil;
  try
    fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);
    SetLength(b, fs.Size);
    if length(b)>0 then fs.Read(b[1], length(b));
    b := ReplaceUtf8WhiteSpaces(b);
    rc.OwnDocs := true;
    rc.Parse(b);
    for i := 0 to rc.docs.Count-1 do begin
      DumpData(TYamlData(rc.docs[i]));
    end;
  finally
    rc.Free;
    fs.Free;
  end;
end;

begin
  if ParamCount=0 then begin
    writeln('please specify input file name');
    exit;
  end;
  ParseYaml(ParamStr(1));
end.

