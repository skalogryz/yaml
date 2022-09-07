unit yamlparser;

interface

uses
  Classes, SysUtils, yamlscanner;

const
  ytkComma = ytkSeparator;
  ytkColon = ytkMapValue;
  ytkDash = ytkSequence;
  ytkBracketOpen = ytkBlockOpen;
  ytkBracketClose = ytkBlockClose;
  ytkCurlyOpen = ytkMapStart;
  ytkCurlyClose = ytkMapClose;

  ytkEndOfScan = [ytkEof, ytkEndOfDoc];

type
  TSetOfYamlTokens = set of TYamlToken;

// Parsing functions don't check if scanner is non nil.
// Make sure to do the check first

function ParseTag(sc: TYamlScanner; out tag: string): Boolean;
function ParseAnchor(sc: TYamlScanner; out anch: string): Boolean;

procedure ParseTagAnchor(sc: TYamlScanner; out tag, anch: string);

type
  EYamlParserError = class(Exception);

procedure SkipToNewline(sc: TYamlScanner);

function ParseKeyScalar(sc: TYamlScanner): string;
function SkipComments(sc: TYamlScanner): string;
function SkipCommentsEoln(sc: TYamlScanner): string;

implementation

procedure SkipToNewline(sc: TYamlScanner);
begin
  while not (sc.token in [ytkEndOfDoc, ytkEoln, ytkEof, ytkError]) do
    sc.ScanNext;
  if (sc.token = ytkEoln) then sc.ScanNext;
end;

procedure ParseTagAnchor(sc: TYamlScanner; out tag, anch: string);
begin
  if sc.token = ytkNodeTag then begin
    ParseTag(sc, tag);
    ParseAnchor(sc, anch);
  end else if sc.token = ytkAnchor then begin
    ParseAnchor(sc, anch);
    ParseTag(sc, tag);
  end else begin
    tag := '';
    anch := '';
  end;
end;

function ParseTag(sc: TYamlScanner; out tag: string): Boolean;
begin
  tag := '';
  Result := sc.token = ytkNodeTag;
  if not Result then Exit;
  tag := sc.Text;
  sc.ScanNext;
end;

function ParseAnchor(sc: TYamlScanner; out anch: string): Boolean;
begin
  anch := '';
  Result := false;
end;

function ParseKeyScalar(sc: TYamlScanner): string;
begin
  Result := '';
  if sc.token = ytkIdent then begin
    Result := sc.GetValue;
    sc.ScanNext;
  end else
    Result := '';
end;

function SkipComments(sc: TYamlScanner): string;
begin
  if sc.token = ytkComment then sc.ScanNext;
end;

function SkipCommentsEoln(sc: TYamlScanner): string;
begin
  while sc.token in [ytkComment,ytkEoln] do
    sc.ScanNext;
end;

end.
