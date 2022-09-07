unit yamlparsetojson;

{$mode ObjFPC}{$H+}
// this is based on the FPC FCL-Json

interface

uses
  Classes, SysUtils, fpjson, yamlscanner, yamlparser;

type
  TYamlToJsonOptions = set of (y2jMultiDocToArray);

const
  DefaultOpts = [y2jMultiDocToArray];

// may raise EYamlParserException
function ParseToJson(sc: TYamlScanner; const opts: TYamlToJsonOptions = DefaultOpts): TJSONData;
// catches EYamlParserException and reports it as an err
function ParseToJson(sc: TYamlScanner; const opts: TYamlToJsonOptions; out err: string): TJSONData;

implementation

function JsonValueFromTag(const tag: string): TJSONData;
begin
  if tag = '' then Result := TJSONString.Create('')
  else if tag ='!!int' then Result := TJSONInt64Number.Create(0)
  else Result := TJSONString.Create('');
end;

function ParseToJsonData(pr: TYamlParser; const opts: TYamlToJsonOptions): TJSONData; forward;

procedure ParseToJsonArr(pr: TYamlParser; const opts: TYamlToJsonOptions; dst: TJSONArray);
begin
  while (pr.ParseNext) do begin
    if pr.entry = yeArrayEnd then break;
    dst.Add( ParseToJsonData(pr, opts));
  end;
end;

procedure ParseToJsonObj(pr: TYamlParser; const opts: TYamlToJsonOptions; dst: TJSONObject);
var
  k : TJSONData;
  v : TJSONData;
begin
  if pr.entry <> yeKeyMapStart then
    Exit;

  repeat
    k := ParseToJsonData(pr, opts);
    pr.ParseNext;
    v := ParseToJsonData(pr, opts);
    pr.ParseNext;
    dst.Add(k.AsString, v);
  until pr.entry = yeKeyMapClose;
end;

function ParseToJsonData(pr: TYamlParser; const opts: TYamlToJsonOptions): TJSONData;
var
  dstObj : TJSONObject;
  dstArr : TJSONArray;
begin
  Result := nil;
  while (pr.ParseNext) do begin
    case pr.entry of
      yeDocStart: begin
        // todo: support multi-document yaml
      end;
      yeKeyMapStart: begin
        dstObj := TJSONObject.Create;
        ParseToJsonObj(pr, opts, dstObj);
        Result := dstObj;
        break;
      end;
      yeArrayStart: begin
        dstArr := TJSONArray.Create;
        ParseToJsonArr(pr, opts, dstArr);
        Result := dstArr;
        break;
      end;
      yeScalarNull: begin
        Result := TJSONNull.Create;
        break;
      end;
      yeScalar:
      begin
        Result := JsonValueFromTag(pr.tag);
        Result.AsString := pr.scalar;
        break;
      end;
      else
        break;
    end; // of case
  end; // of while
end;

function ParseToJson(sc: TYamlScanner; const opts: TYamlToJsonOptions = DefaultOpts): TJSONData;
var
  p : TYamlParser;
begin
  p := TYamlParser.Create;
  try
    p.SetScanner(sc, false);
    Result := ParseToJsonData(p, opts);
  finally
    p.Free;
  end;
end;

function ParseToJson(sc: TYamlScanner; const opts: TYamlToJsonOptions; out err: string): TJSONData;
begin
  try
    err := '';
    Result := ParseToJson(sc, opts);
  except
    on e: EYamlParserError do begin
      if e.lineNum>0 then
        err :='['+IntToStr(e.lineNum)+':'+IntToStr(e.charOfs)+'] ';
      err := err+e.message;
      Result := nil;
    end;
  end;
end;

end.


