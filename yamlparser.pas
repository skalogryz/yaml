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

  { EYamlParserError }

  EYamlParserError = class(Exception)
  public
    lineNum  : integer;
    charOfs  : integer;
    ascanner : TYamlScanner;
    constructor Create(const msg: string);
    constructor Create(sc: TYamlScanner; const msg: string);
  end;

  { EYamlExpected }

  EYamlExpected = class(EYamlParserError)
  public
    constructor Create(sc: TYamlScanner; const msg: string); overload;
    constructor Create(sc: TYamlScanner; const want: TYamlToken); overload;
    constructor Create(sc: TYamlScanner; const want, need: TYamlToken); overload;
  end;

  { EYamlInvalidToken }

  EYamlInvalidToken = class(EYamlParserError)
  public
    constructor Create(sc: TYamlScanner;const msg: string); overload;
    constructor Create(sc: TYamlScanner; const unexpect: TYamlToken); overload;
    constructor Create(sc: TYamlScanner);
  end;

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

{ EYamlParserError }

constructor EYamlParserError.Create(const msg: string);
begin
  inherited Create(msg);
end;

constructor EYamlParserError.Create(sc: TYamlScanner; const msg: string);
begin
  Create(msg);
  if Assigned(sc) then begin
    ascanner := sc;
    lineNum := sc.lineNum;
    charOfs := sc.tokenIdx-sc.newLineOfs+1;
  end;
end;

{ EYamlInvalidToken }

constructor EYamlInvalidToken.Create(sc: TYamlScanner; const msg: string);
begin
  inherited Create(sc, msg);
end;

constructor EYamlInvalidToken.Create(sc: TYamlScanner; const unexpect: TYamlToken);
begin
  Create(sc, 'Unexpected '+YamlTokenStr[unexpect]+' found');
end;

constructor EYamlInvalidToken.Create(sc: TYamlScanner);
begin
  Create(sc, sc.Token);
end;

{ EYamlExpected }

constructor EYamlExpected.Create(sc: TYamlScanner; const msg: string);
begin
  inherited Create(sc, msg);
end;

constructor EYamlExpected.Create(sc: TYamlScanner; const want: TYamlToken);
begin
  Create(sc, 'expected: ' + YamlTokenStr[want]);
end;

constructor EYamlExpected.Create(sc: TYamlScanner; const want, need: TYamlToken);
begin
  Create(sc, 'expected: ' + YamlTokenStr[want]+', but '+YamlTokenStr[need]+' found');
end;

end.
