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

function ParseToJson(sc: TYamlScanner; const opts: TYamlToJsonOptions): TJSONData;
var
  tk : TYamlToken;

  hasKey : Boolean;
  obj    : TJSONObject;
  key    : string;
begin
  Result := nil;
  hasKey := false;
  obj := nil;

  while true do begin
    tk := sc.ScanNext;
    if tk = ytkError then break;
    if tk = ytkEof then break;

    if tk = ytkIdent then begin
      if not hasKey then begin
        key := sc.GetValue;
        hasKey := true;
      end else begin
        if not Assigned (obj) then obj := TJSONObject.Create;
        obj.add(key, sc.GetValue);

        if not Assigned(result) then result := obj;
      end;
    end;
  end;
end;

end.

