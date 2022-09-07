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


// parsing { key:value, ... } flow
procedure ParseKeyValueBlock(sc: TYamlScanner; const opts: TYamlToJsonOptions; dst: TJSONOBject); forward;
procedure ParseToArray(sc: TYamlScanner; const opts: TYamlToJsonOptions; dst: TJSONArray; stayIdent: integer); forward;
// tries to parse a value buy current status of the scanner
function ParseToJsonInt(sc: TYamlScanner; const opts: TYamlToJsonOptions; indent: integer; const ExtraStops: TSetOfYamlTokens = []): TJSONData; forward;

// This is an explicit Key/Value block. Expecting "}" to be reported
procedure ParseKeyValueBlock(sc: TYamlScanner; const opts: TYamlToJsonOptions; dst: TJSONOBject);
var
  done : Boolean;
  key  : string;
  vl   : TJSONData;
  suba : TJSONArray;
begin
  if sc.token <> ytkCurlyOpen then Exit;
  sc.ScanNext;

  done := false;
  while not done do begin
    SkipCommentsEoln(sc);
    key := ParseKeyScalar(sc);
    SkipCommentsEoln(sc);
    vl := nil;
    if sc.token = ytkColon then begin
      sc.ScanNext;
      SkipCommentsEoln(sc);
    end;

    case sc.token of
      ytkCurlyClose: begin
        sc.ScanNext;
        done := true;
      end;
      ytkComma: begin
        sc.ScanNext;
        SkipCommentsEoln(sc);
        // the last comma after the last value is allowed
        // { k:v, k2:v, }
        if (sc.token = ytkCurlyClose) then begin
          sc.ScanNext;
          done := true;
        end;
      end;
      ytkBracketOpen:  begin
        suba := TJSONArray.Create();
        ParseToArray(sc, opts, suba, sc.tokenIndent);
        vl := suba;
      end;
    else
      vl := ParseToJsonInt(sc, opts, sc.tokenIndent, [ytkCurlyClose, ytkComma]);
    end;
    if vl = nil then
      vl := TJSONNull.Create;
    dst.Add(key, vl);
  end;
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

function ParseToJsonInt(sc: TYamlScanner; const opts: TYamlToJsonOptions; indent: integer; const ExtraStops: TSetOfYamlTokens): TJSONData;
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
    SkipCommentsEoln(sc);
    tk := sc.Token;
    // out of the parent
    if sc.tokenIndent < indent then break;
    if tk = ytkError then break;
    if tk = ytkEof then break;
    if (ExtraStops <> []) and (tk in ExtraStops) then break;

    if (tk = ytkStartOfDoc) then
      // doing nothing about it
    else if tk = ytkSequence then begin
      arr := TJSONArray.Create;
      if Result = nil then Result := arr;
      ParseToArray(sc, opts, arr, sc.tokenIndent);
    end else if tk=ytkCurlyOpen then begin;
      obj := TJSONObject.Create;
      if Result = nil then Result := obj;
      ParseKeyValueBlock(sc, opts, obj);

    end else if tk = ytkIdent then begin
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
  if not Assigned(Result) then
    Result := TJSONNull.Create;
end;

function ParseToJson(sc: TYamlScanner; const opts: TYamlToJsonOptions = DefaultOpts): TJSONData;
begin
  sc.ScanNext;
  Result := ParseToJsonInt(sc, opts, sc.tokenIndent);
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


