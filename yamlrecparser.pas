unit yamlrecparser;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, yamlscanner, yamlunicode, yamlparser;

type
  TYamlDataType = (
    ydtDoc,
    ydtMap,
    ydtArray,
    ydrScalar,
    ydrNull
  );

  { TYamlData }

  TYamlData = class(TObject)
  public
    dtype     : TYamlDataType;
    value     : string;
    tag       : string;
    children  : TList;
    names     : TList;
    //parent    : TYamlData;
    constructor Create(adtype: TYamlDataType; aparent: TYamlData = nil);
    constructor CreateScalar(const txt: string);
    constructor CreateNull;
    destructor Destroy; override;
    function Add(adata: TYamlData): TYamlData;
    function AddName(aname: TYamlData): TYamlData;
    function AddVal(adata: TYamlData): TYamlData;
    procedure Remove(adata: TYamlData);
  end;

  { TYamlRecParser }

  TYamlRecParser = class(TObject)
  protected
    sc : TYamlScanner;
    curDoc : TYamlData;
    procedure DoParse(aparent: TYamlData; ind: integer);
    function ParseArrBlock: TYamlData;
    function ParseMapBlock: TYamlData;
  public
    docs : TList; // documents
    constructor Create;
    destructor Destroy; override;
    procedure Parse(const buf: string);
  end;


implementation

{ TYamlRecParser }

procedure TYamlRecParser.DoParse(aparent: TYamlData; ind: integer);
var
  left  : TYamlData;
  right : TYamlData;
  t     : TYamlData;
  addTo : TYamlData;
  mp    : TYamlData;
  key   : TYamlData;
  c     : integer;
begin
  while true do begin
    if sc.tokenIndent < ind then Break;

    case sc.token of
      ytkStartOfDoc, ytkEndOfDoc:
        break;

      ytkScalar: begin
        aparent.Add( TYamlData.CreateScalar(sc.text));
        sc.ScanNext;
      end;

      ytkMapValue: begin
        if Assigned(aparent.children) and (aparent.children.Count>0) then begin
          c := aparent.children.Count - 1;
          key := TYamlData(aparent.children[c]);
          aparent.children.Delete(c);
        end else
          key := TYamlData.CreateNull;
        mp := TYamlData.Create(ydtMap);
        mp.AddName(key);
        aparent.Add(mp);
        sc.ScanNext;
        ParseMapValue(mp);
      end;

      ytkSequence: begin
        t := ParseArrBlock;
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
      sc.ScanNext;
      if sc.tokenIndent < sc.blockIndent then Break;
      if (sc.tokenIndent = sc.blockIndent) and (sc.token <> ytkSequence) then
        raise EYamlExpected.Create(sc, ytkSequence);
      DoParse(Result, sc.blockIndent);
    end;
  finally
    sc.blockIndent := bi;
  end;
end;

function TYamlRecParser.ParseMapBlock(implKey: TYamlData): TYamlData;
begin
  Result := TYamlData.Create(ydtMap);
  bi := sc.blockIndent;

  if Assigned(implKey) then begin
    Result.Add(implKey);

  // todo: indent needs to be delivered from the emplicit key
  sc.blockIndent := sc.tokenIndent;

  try
    while true do begin
      sc.ScanNext;
      if sc.tokenIndent < sc.blockIndent then Break;
      if (sc.tokenIndent = sc.blockIndent) and (sc.token <> ytkSequence) then
        raise EYamlExpected.Create(sc, ytkSequence);
      DoParse(Result, sc.blockIndent);
    end;
  finally
    sc.blockIndent := bi;
  end;

end;

constructor TYamlRecParser.Create;
begin
  inherited Create;
  docs := TList.Create;
end;

destructor TYamlRecParser.Destroy;
begin
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

{ TYamlData }

constructor TYamlData.Create(adtype: TYamlDataType; aparent: TYamlData);
begin
  inherited Create;
  dtype:=adtype;
  //parent := aparent;
  if adtype = ydtMap then
    names := TList.Create;
  if adtype in [ydtMap,ydtArray,ydtDoc] then
    children := TList.Create;
end;

constructor TYamlData.CreateScalar(const txt: string);
begin
  Create(ydrScalar);
  value := txt;
end;

constructor TYamlData.CreateNull;
begin
  Create(ydrNull);
end;

destructor TYamlData.Destroy;
var
  i : integer;
begin
  if Assigned(children) then begin
    for i:=0 to children.Count-1 do
      TObject(children[i]).Free;
    children.Free;
    children := nil;
  end;
  inherited Destroy;
end;

function TYamlData.Add(adata: TYamlData): TYamlData;
begin
  Result := adata;
  if not ASsigned(Adata) then Exit;
  if (dtype = ydtMap) and (names.Count = children.Count) then begin
    AddName(adata);
  end else
    AddVal(adata);
end;

function TYamlData.AddName(aname: TYamlData): TYamlData;
begin
  if not ASsigned(names) then
    names := TList.Create;
  names.Add(aname);
end;

function TYamlData.AddVal(adata: TYamlData): TYamlData;
begin
  Result :=adata;
  if not Assigned(adata) then Exit;

  if not Assigned(children) then
    children := TList.Create;
  children.Add(adata);
end;

procedure TYamlData.Remove(adata: TYamlData);
begin
  children.Remove(adata);
end;

end.

