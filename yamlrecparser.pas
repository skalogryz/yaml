unit yamlrecparser;

{$ifdef fpc}{$mode delphi}{$H+}{$endif}

interface

uses
  Classes, SysUtils, yamlscanner, yamlparser, yamltreetypes;

type
  { TYamlRecParser }

  TYamlRecParser = class(TObject)
  protected
    sc : TYamlScanner;
    curDoc : TYamlData;
    procedure DoParse(aparent: TYamlData; ind: integer);
    function ParseArrBlock: TYamlData;
    function ParseMapBlock(implKey: TYamlData): TYamlData;
    function ParseArrFlow: TYamlData;
    function ParseMapFlow: TYamlData;
  public
    docs : TList; // documents
    ownDocs : Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Parse(const buf: string);
  end;


implementation

{ TYamlRecParser }

procedure TYamlRecParser.DoParse(aparent: TYamlData; ind: integer);
var
  t     : TYamlData;
  mp    : TYamlData;
  key   : TYamlData;
  c     : integer;
begin
  while true do begin
    if sc.tokenIndent < ind then Break;

    case sc.token of
      ytkStartOfDoc, ytkEndOfDoc:
        break;

      ytkComma, ytkBracketClose, ytkCurlyClose:
        // indicators... handled else where
        break;

      ytkScalar: begin
        aparent.Add( TYamlData.CreateScalar(sc.text));
        sc.ScanNext;
      end;

      ytkMapKey: begin
        mp := ParseMapBlock(nil);
        aparent.Add(mp);
      end;

      ytkMapValue: begin
        // the parent knows about the stuff, it should be able to parse things out
        if (aparent.dtype = ydtMap) then
          break;

        if Assigned(aparent.children) and (aparent.children.Count>0) then begin
          c := aparent.children.Count - 1;
          key := TYamlData(aparent.children[c]);
          aparent.children.Delete(c);
        end else
          key := TYamlData.CreateNull;
        mp := ParseMapBlock(key);
        aparent.children.Add(mp);
      end;

      ytkSequence: begin
        t := ParseArrBlock;
        aparent.Add(t);
      end;

      ytkBracketOpen: begin
        t := ParseArrFlow;
        aparent.add(t);
      end;

      ytkCurlyOpen: begin
        t := ParseMapFlow;
        aparent.add(t);
      end;

      ytkEof:
        break;
      else
        sc.ScanNext;
    end;
  end;
end;

function TYamlRecParser.ParseArrBlock: TYamlData;
var
  bi  : integer;
begin
  Result := TYamlData.Create(ydtArray);
  bi := sc.blockIndent;
  sc.blockIndent := sc.tokenIndent;
  try
    while true do begin
      if sc.tokenIndent < sc.blockIndent then Break;
      if (sc.tokenIndent = sc.blockIndent) and (sc.token <> ytkSequence) then
        break; // end of the block

      sc.ScanNext;
        //raise EYamlExpected.Create(sc, ytkSequence);
      DoParse(Result, sc.blockIndent+1);
    end;
  finally
    sc.blockIndent := bi;
  end;
end;

function TYamlRecParser.ParseMapBlock(implKey: TYamlData): TYamlData;
var
  bi     : integer;
  hasKey : Boolean;
begin
  Result := TYamlData.Create(ydtMap);
  bi := sc.blockIndent;

  if Assigned(implKey) then begin
    Result.Add(implKey);
    hasKey := true;
  end else
    hasKey := false;

  // todo: indent needs to be delivered from the emplicit key
  sc.blockIndent := sc.tokenIndent;

  try
    while true do begin
      if sc.tokenIndent < sc.blockIndent then Break;
      if sc.token in ytkFlowSeparate then Break;

      if (sc.tokenIndent = sc.blockIndent) and
        hasKey and not (sc.token in [ytkMapValue, ytkMapKey]) then
        raise EYamlExpected.Create(sc, ytkMapValue);

      if hasKey and (sc.token in [ytkMapKey]) then begin
        hasKey := false;
        Result.Add(TYamlData.Create(ydtNull));
        sc.ScanNext;
      end else if not hasKey and (sc.token in [ytkMapValue]) then begin
        hasKey := true;
        Result.Add(TYamlData.Create(ydtNull));
        sc.ScanNext;
      end else begin
        hasKey := not hasKey;
        if sc.token in [ytkMapValue, ytkMapKey] then
          sc.ScanNext;
      end;
      DoParse(Result, sc.blockIndent+1);
    end;

  finally
    sc.blockIndent := bi;
  end;

end;

function TYamlRecParser.ParseMapFlow: TYamlData;
var
  anyComma : boolean;
  hasKey   : Boolean;
  hasValue : Boolean;
begin
  Result := TYamlData.Create(ydtMap);

  if sc.token <> ytkCurlyOpen then
    raise EYamlExpected.Create(sc, ytkCurlyOpen, sc.token);

  sc.ScanNext;

  while true do begin
    SkipCommentsEoln(sc);
    hasKey := not (sc.token in [ytkMapVAlue, ytkCurlyClose]);
    if hasKey then begin
      DoParse(Result, sc.blockIndent);
      SkipCommentsEoln(sc);
    end;
    if sc.token = ytkMapValue then begin
      sc.ScanNext;

      if not hasKey then begin
        Result.Add(TYamlData.Create(ydtNull));
      end;

      hasValue := not (sc.token in [ytkCurlyClose]);
      if hasValue then begin
        DoParse(Result, sc.blockIndent)
      end else begin
        Result.Add(TYamlData.Create(ydtNull));
      end;
    end;

    anyComma := false;
    while sc.token = ytkComma do begin
      anyComma := true;
      sc.ScanNext;
      SkipCommentsEoln(sc);
    end;

    if sc.token = ytkCurlyClose then begin
      sc.ScanNext;
      break;
    end else if not anyComma then
      raise EYamlExpected.Create(sc, ytkCurlyClose, sc.token);
  end;
end;

function TYamlRecParser.ParseArrFlow: TYamlData;
var
  anyComma : boolean;
begin
  Result := TYamlData.Create(ydtArray);

  if sc.token <> ytkBracketOpen then
    raise EYamlExpected.Create(sc, ytkBracketOpen, sc.token);

  sc.ScanNext;

  while true do begin
    DoParse(Result, sc.blockIndent);
    SkipCommentsEoln(sc);

    anyComma := false;
    while sc.token = ytkComma do begin
      anyComma := true;
      sc.ScanNext;
      SkipCommentsEoln(sc);
    end;

    if sc.token = ytkBracketClose then begin
      sc.ScanNext;
      break;
    end else if not anyComma then
      raise EYamlExpected.Create(sc, ytkBracketClose, sc.token);
  end;
end;

constructor TYamlRecParser.Create;
begin
  inherited Create;
  docs := TList.Create;
end;

destructor TYamlRecParser.Destroy;
var
  i : integer;
begin
  if ownDocs then
    for i:=0 to docs.Count-1 do
      TObject(docs[i]).Free;
  docs.Free;
  inherited Destroy;
end;

procedure TYamlRecParser.Parse(const buf: string);
var
  ind : integer;
begin
  sc := TYamlScanner.Create;
  try
    sc.SetBuffer(buf);
    sc.ScanNext;
    while sc.token <> ytkEof do begin
      curDoc := TYamlData.Create(ydtDoc);
      docs.Add(curdoc);
      if sc.token = ytkStartOfDoc then begin
        ind := sc.tokenIndent;
        sc.ScanNext;
      end else
        ind := sc.tokenIndent;
      DoParse(curDoc, ind);

      if sc.token = ytkEndOfDoc then
        sc.ScanNext;
    end;
  finally
    sc.Free;
  end;
end;

end.

