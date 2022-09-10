program parsersample;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, Classes, yamlscanner, yamlparser;

procedure ParseYaml(const fn: string);
var
  fs  : TFileStream;
  res : string;
  pr  : TYamlParser;
  err : string;
  ind : string;
const
  STRNOTE : array [TYamlEntry] of string = (
    '=VAL' ,'=VAL' ,'+DOC' ,'-DOC' ,'+MAP' ,'-MAP' ,'+SEQ' ,'-SEQ' ,'+STR'
  );
  IndNOTE : array [TYamlEntry] of integer = (
    0, 0, 1, -1, +1, -1, +1 ,-1,+1
  );
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
      write(STRNOTE[pr.entry]:8,' ');
      write(pr.entry:15);
      write(pr.ParserState:20);
      if pr.tag <>''then write(' [',pr.tag,']');
      if pr.entry = yeScalar then write(' :',pr.scalar);
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
  ParseYaml(ParamStr(1));
end.

