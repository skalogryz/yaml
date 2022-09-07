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

function ParseToJson(sc: TYamlScanner; const opts: TYamlToJsonOptions = DefaultOpts): TJSONData;

implementation

function JsonValueFromTag(const tag: string): TJSONData;
begin
  if tag = '' then Result := TJSONString.Create('')
  else if tag ='!!int' then Result := TJSONInt64Number.Create(0)
  else Result := TJSONString.Create('');
end;

// sc is at "sequence" and everyone else here are expected to be sequences
procedure ParseToArray(sc: TYamlScanner; const opts: TYamlToJsonOptions; dst: TJSONArray; stayIdent: integer);
var
  tag  : string;
  anch : string;
  js   : TJSONData;
  done : Boolean;
  suba : TJSONArray;
begin
  if not (sc.token in [ytkComma, ytkDash, ytkBracketOpen]) then Exit;
  sc.ScanNext;
  done := false;
  while not done do begin
    if (sc.token = ytkDash) then begin
      suba := TJSONArray.Create();
      ParseToArray(sc, opts, suba, sc.tokenIndent);
      dst.Add(suba);

    end else begin
      ParseTagAnchor(sc, tag, anch);

      js := JsonValueFromTag(tag);

      if sc.token = ytkIdent then begin
        js.AsString := sc.GetValue;
        dst.Add(js);
      end;
      SkipToNewline(sc);
      if (sc.tokenIndent < stayIdent) or (sc.token in ytkEndOfScan) then begin
        done := true
      end else if sc.token in [ytkBlockClose] then begin
        sc.ScanNext;
        done := true;
      end else if (sc.tokenIndent = stayIdent) and (sc.token in [ytkDash, ytkComma]) then begin
        sc.ScanNext;
      end;
    end;
  end;
end;

function ParseToJsonInt(sc: TYamlScanner; const opts: TYamlToJsonOptions; indent: integer): TJSONData;
var
  tk : TYamlToken;

  hasKey : Boolean;
  obj    : TJSONObject;
  key    : string;
  arr    : TJSONArray;
begin
  Result := nil;
  hasKey := false;
  obj := nil;
  arr := nil;
  while true do begin
    tk := sc.Token;
    // out of the parent
    if sc.tokenIndent < indent then break;
    if tk = ytkError then break;
    if tk = ytkEof then break;

    if tk = ytkSequence then begin
      arr := TJSONArray.Create;
      if Result = nil then Result := arr;
      ParseToArray(sc, opts, arr, sc.tokenIndent);
    end;

    if tk = ytkIdent then begin
      if not hasKey then begin
        key := sc.GetValue;
        hasKey := true;
      end else begin
        if not Assigned (obj) then obj := TJSONObject.Create;
        obj.add(key, sc.GetValue);

        if not Assigned(result) then result := obj;
        hasKey:=false;
      end;
    end;

    tk := sc.ScanNext;
  end;

  if not Assigned(Result) and hasKey then begin
    Result := TJSONString.Create(key);
  end;
end;

function ParseToJson(sc: TYamlScanner; const opts: TYamlToJsonOptions = DefaultOpts): TJSONData;
begin
  sc.ScanNext;
  Result := ParseToJsonInt(sc, opts, sc.tokenIndent);
end;

end.


