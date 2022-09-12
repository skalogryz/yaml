unit yamltreetypes;

interface

{$ifdef fpc}{$mode delphi}{$endif}

uses
  Classes, SysUtils;

type
  TYamlDataType = (
    ydtDoc,
    ydtMap,
    ydtArray,
    ydtScalar,
    ydtNull
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

implementation

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
  Create(ydtScalar);
  value := txt;
end;

constructor TYamlData.CreateNull;
begin
  Create(ydtNull);
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
  end else begin
    AddVal(adata);
  end;
end;

function TYamlData.AddName(aname: TYamlData): TYamlData;
begin
  Result := aname;
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
