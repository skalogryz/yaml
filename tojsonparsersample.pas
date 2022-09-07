program tojsonparsersample;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, Classes, yamlscanner, yamlparsetojson, fpjson, jsonConf;

procedure ToJson(const fn: string);
var
  fs  : TFileStream;
  res : string;
  sc  : TYamlScanner;
  j   : TJSONData;
  st  : TFPJSStream;
begin
  res := '';
  fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);
  try
    SetLength(res, fs.Size);
    fs.Read(res[1], length(res));
  finally
    fs.Free;
  end;
  sc := TYamlScanner.Create;
  try
    sc.SetBuffer(res);
    j := ParseToJson(sc);

    st := TFPJSStream.Create;
    try
      j.DumpJSON(st);
      SetLength(res, st.Size);
      st.Position:=0;
      if length(res)>0 then
        st.REad(res[1], length(res));
      writeln(res);
    finally
      st.Free;
    end;

    j.Free;
  finally
    sc.Free;
  end;
end;

begin
  if ParamCount=0 then begin
    writeln('please specify yaml file name');
    exit;
  end;
  ToJson(ParamStr(1));
end.

