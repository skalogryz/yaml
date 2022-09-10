program yamplscannersample;
{$ifdef mswindows}
{$APPTYPE CONSOLE}
{$endif}

uses
  SysUtils, Classes, yamlscanner
  ,yamlunicode;


procedure ScanYaml(const fn: string);
var
  fs : TfileStream;
  buf : string;
  sc  : TYamlScanner;
  tk  : TYamlToken;
begin
  fs := TfileStream.Create(fn, fmOpenRead or fmShareDenyNone);
  try
    if fs.Size=0 then Exit;
    SetLength(buf, fs.Size);
    fs.Read(buf[1], length(buf));
    buf := ReplaceUtf8WhiteSpaces(buf);

    sc := TYamlScanner.Create;
    sc.SetBuffer(buf);
    while true do begin
      tk := sc.ScanNext;
      if tk = ytkEof then Break;
      if tk = ytkError then begin
        writeln('error: ', YamlErrorStr[sc.error]);
        break;
      end;
      write(sc.tokenIndent:8,YamlTokenStr[tk]:10,' ');
      if tk <> ytkEoln then write(sc.text);
      writeln;
    end;
  finally
    fs.Free;
  end;
end;

begin
  if ParamCount=0 then begin
    writeln('please sepcify the file name');
    exit;
  end;
  ScanYaml(ParamStr(1));
end.
