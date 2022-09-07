program tojsonparsersample;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, Classes, yamlscanner, yamlparser;

procedure ToJson(const fn: string);
var
  fs  : TFileStream;
  res : string;
  pr  : TYamlParser;
  err : string;
begin
  res := '';
  fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);
  try
    SetLength(res, fs.Size);
    fs.Read(res[1], length(res));
  finally
    fs.Free;
  end;
  pr := TYamlParser.Create;
  try
    pr.SetBuffer(res);

    while pr.ParseNext do begin
      write(pr.entry:15);
      write(pr.ParserState:20);
      if pr.tag <>''then write(' [',pr.tag,']');
      if pr.entry = yeScalar then write(' ',pr.scalar);
      writeln;
    end;

    if pr.errorMsg<>'' then begin
      if pr.errorLine>0 then
        write('[',pr.errorLine,':', pr.errorChar,'] ');
      writeln(pr.errorMsg);
      writeln('Parser State: ', pr.errorState);
    end;

  finally
    pr.Free;
  end;
end;

begin
  if ParamCount=0 then begin
    writeln('please specify yaml file name');
    exit;
  end;
  ToJson(ParamStr(1));
end.

