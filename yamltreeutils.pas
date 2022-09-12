unit yamltreeutils;

interface

uses
  Classes, SysUtils, yamltreetypes;

procedure DumpData(const dt: TYamlData; const ind: string = '');

implementation

procedure DumpData(const dt: TYamlData; const ind: string = '');
var
  i : integer;
  s : TYamlData;
  nxind : string;
begin
  case dt.dtype of
    ydtDoc: writeln('---');
    ydtMap: write('? ');
    ydtArray: write('- ');
    ydtScalar: write(dt.value);
  end;
  if dt.dtype = ydtDoc then
    nxind := ind
  else
    nxind := ind + '  ';

  if (dt.dtype <> ydtScalar) and (dt.dtype <> ydtNull) then begin
    for i := 0 to dt.children.count-1 do begin
      if (i > 0) then begin
        write(ind);
        if dt.dtype = ydtArray then write('- ');
      end;
      if dt.dtype = ydtMap then begin
        s := TYamlData(dt.names[i]);
        DumpData(s, nxind);
        write(ind,': ');
      end;
      s := TYamlData(dt.children[i]);
      DumpData(s, nxind);
    end;
  end;

  if not (dt.dtype in [ydtArray,ydtMap]) or (dt.children.count=0) then
    writeln;
end;

end.
