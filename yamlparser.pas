unit yamlparser;

interface

{$ifdef fpc}
{$mode delphi}{$H+}
{$define hasinline}
{$endif}

uses
  Classes, SysUtils, yamlscanner, yamlunicode;

// The parser cannot be implemented easily, due to necesity support
// complex keys:
//
// [
//  [ a, [ [[b,c]]: d, e]]: 23
// ]
//
// this should be finished as:
// +seq
//   +map
//
// however "+map" cannot be detected until ":" is found. By that time
// a lot of other tokens are already reported


const
  ytkComma = ytkSeparator;
  ytkColon = ytkMapValue;
  ytkQuestion = ytkMapKey;
  ytkDash = ytkSequence;
  ytkBracketOpen = ytkBlockOpen;
  ytkBracketClose = ytkBlockClose;
  ytkCurlyOpen = ytkMapStart;
  ytkCurlyClose = ytkMapClose;

  ytkEndOfScan = [ytkEof, ytkEndOfDoc];

  // valid tokens for start
  DocStarters = [
    ytkSequence
   ,ytkMapKey
   ,ytkMapValue
   ,ytkSeparator
   ,ytkBlockOpen
   ,ytkMapStart
   ,ytkAnchor
   ,ytkAlias
   ,ytkNodeTag
   ,ytkIdent
   ,ytkStartOfDoc
   ,ytkEndOfDoc // if we found this one, we should also report, as if the document got started
  ];

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
    scanErr  : TYamlScannerError;
    constructor Create(const msg: string); overload;
    constructor Create(sc: TYamlScanner; const msg: string); overload;
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


  { EYamlScannerError }

  EYamlScannerError = class(EYamlParserError)
  public
    constructor Create(sc: TYamlScanner);
  end;

  EYamlInvalidIndentation = class(EYamlParserError)
  end;

procedure SkipToNewline(sc: TYamlScanner);

function ParseKeyScalar(sc: TYamlScanner): string;
procedure SkipComments(sc: TYamlScanner);
procedure SkipCommentsEoln(sc: TYamlScanner);

type
  TYamlEntry = (
    yeScalar,        // "scalar" is filled, "tag" is filled
    yeScalarNull,
    yeDocStart,
    yeDocEnd,
    yeKeyMapStart,   // "key" is not filled, "tag" is filled
    yeKeyMapClose,
    yeArrayStart,
    yeArrayEnd,
    yeNewDoc
  );

  TParseState = (
    psError,             // an error occurred
    psInit,              // before start of a document
    psDetect,            // trying to figure out what value we're looking at
    psReportKey,         // we've found a scalar, that seems to be the key, but so we need to report it
    psReportNullKey,     // we've ran into ":" character, but it seems to be w/o key
    psReportStartDoc,    // need to re-report the document start
    psConsumeKeyBlock,   // the start of the map has been detected "{" consume key
    psConsumeValue,      // we've reported the key, we need a value now
    psConsumeKeyValChar, // expecting ":" character
    psConsumeMapKeyFlow, // the start of the map has been detected "{" consume key
    psConsumeMapValFlow, // consume value of the { } map
    psConsumeArrElmFlow, // array element (in a flow)
    psEof

  );

  { TParserContext }

  TParserContext = class(TObject)
    isStarted  : Boolean; // has been reported as started or not;
                          // if it was started, it must also be closed
    indent     : integer; // the indentation used to start the context
    isArray    : Boolean; // if true, then sequence, otherwise - map

    vals       : Integer; // number of values
    isKeyFound : Boolean; // the key was found (used for map)
                          // if the key is not found, we must report "non-existing" value
                          // but the context is finished
    isFlow     : Boolean; // true if, {} or [] were used to start the context
    prev       : TParserContext;

    function IsFlowClose(tk: TYamlToken):Boolean;
    function GetParserState: TParseState;
  end;

  { TYamlParser }

  TYamlParser = class(TObject)
  protected
    fscanner   : TYamlScanner;
    fState     : TParseState;
    hasDoc     : Boolean;
    ctx        : TParserContext;
    dst        : TParserContext;
    root       : TParserContext;
    procedure InitParser;
    function DoParseNext: Boolean;
    procedure ResetContext;
    function PopupContext: TYamlEntry;

    procedure SwitchContext(isArray, isFlow: Boolean; out isNewContext: Boolean; indent: integer = -1);

    procedure ConsumeDirective(const dir: string); virtual;
    procedure CheckValidIndent(out dstContext: TParserContext);
  public
    ownScanner : Boolean;

    tag        : string;
    scalar     : string;
    entry      : TYamlEntry;


    errorMsg   : string;
    errorLine  : Integer;
    errorChar  : Integer;
    errorState : TParseState;
    constructor Create;
    destructor Destroy; override;
    procedure SetBuffer(const buf: string; removeUtf8ws: Boolean = true);
    procedure SetScanner(ascanner: TYamlScanner; aownScanner: Boolean);

    function ParseNext: Boolean;
    property ParserState: TParseState read fState;
    property Scanner: TYamlScanner read fScanner;
  end;

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
    Result := sc.text;
    sc.ScanNext;
  end else
    Result := '';
end;

procedure SkipComments(sc: TYamlScanner);
begin
  if sc.token = ytkComment then sc.ScanNext;
end;

procedure SkipCommentsEoln(sc: TYamlScanner);
begin
  while sc.token in [ytkComment,ytkEoln] do
    sc.ScanNext;
end;

{ EYamlScannerError }

constructor EYamlScannerError.Create(sc: TYamlScanner);
begin
  inherited Create(sc, 'scanner error: '+YamlErrorStr[sc.error]);
  scanErr := sc.error;
end;

{ TParserContext }

function TParserContext.IsFlowClose(tk: TYamlToken): Boolean;
begin
  Result :=
    isStarted // if not started, there's nothing to close
    and isFlow // if it's not flow, then there's no closing symbol
    and (
      (not isArray and (tk = ytkCurlyClose))
       or (isArray and (tk = ytkBracketClose))
      );
end;

function TParserContext.GetParserState: TParseState;
begin
  if not isStarted then begin
    Result := psDetect;
  end else if isArray then begin
    if not isFlow then Result := psDetect
    else Result := psConsumeArrElmFlow;
  end else begin
    if isFlow then begin
      if not isKeyFound
        then Result := psConsumeMapKeyFlow
        else Result := psConsumeMapValFlow;
    end else begin
      Result := psConsumeKeyBlock;
    end;
  end;
end;

{ TYamlParser }

constructor TYamlParser.Create;
begin
  inherited Create;
  root := TParserContext.Create;
end;

destructor TYamlParser.Destroy;
begin
  ResetContext;
  root.Free;
  if ownScanner then scanner.Free;
  inherited Destroy;
end;

procedure TYamlParser.SetBuffer(const buf: string; removeUtf8ws: Boolean );
begin
  if not Assigned(scanner) then begin
    fscanner := TYamlScanner.Create;
    ownScanner := true;
  end;
  if removeUtf8ws then
    scanner.SetBuffer(ReplaceUtf8WhiteSpaces(buf))
  else
    scanner.SetBuffer(buf);
  InitParser;
end;

procedure TYamlParser.SetScanner(ascanner: TYamlScanner; aownScanner: Boolean);
begin
  fscanner := ascanner;
  ownScanner := aownScanner;
  InitParser;
end;

function TYamlParser.ParseNext: Boolean;
begin
  try
    if scanner = nil then begin
      Result := false;
      Exit;
    end;
    if fState = psError then begin
      // we're in error. don't want to parse anything anymore
      // call SetBuffer to reset the state
      Result := false;
      Exit;
    end;
    Result := DoParseNext;
  except
    on e: EYamlParserError do begin
      errorMsg := e.Message;
      errorLine := e.lineNum;
      errorChar := e.charOfs;
      errorState := fState;
      Result := false;
      fState := psError;
    end;
  end
end;

function TYamlParser.DoParseNext: Boolean;
var
  done : Boolean;
  isNew : Boolean;
  tempInd : integer;
  initState : TParseState;
begin
  Result := false;

  if entry in [yeScalar, yeArrayStart, yeKeyMapStart] then begin
    // cleanup
    tag := '';
    if (entry = yeScalar) then scalar := '';
  end;

  initState := fState;
  repeat
    done := true;
    case fState of
      psInit:
      begin
        SkipCommentsEoln(scanner);
        if scanner.token = ytkDirective then begin
          Result := true;
          ConsumeDirective(scanner.text);
          scanner.ScanNext;
          SkipCommentsEoln(scanner);
          done := false;
        end else if scanner.token in DocStarters then begin
          Result := true;
          hasDoc := true;
          entry := yeDocStart;
          if scanner.token = ytkStartOfDoc then
            scanner.ScanNext;
          fState := psDetect;
        end else
          raise EYamlInvalidToken.Create(scanner);
      end;

      //psConsumeValue:
      psConsumeMapValFlow,
      psConsumeMapKeyFlow,
      psConsumeArrElmFlow,
      psDetect:
      begin
        //if (fState = psDetect) then
        SkipCommentsEoln(scanner);

        if (fState in [psConsumeMapKeyFlow,psConsumeMapValFlow]) and (scanner.token = ytkColon) then
        begin
          scanner.ScanNext;
          fState := psConsumeMapValFlow;
          done := false;
        end;

        CheckValidIndent(dst);
        if dst<>ctx then begin;
          entry := PopupContext;
          Result := true;
          break;
        end;

        // level down
        if (ctx.isStarted) and (scanner.tokenIndent < ctx.indent) then begin
          entry := PopupContext;
          Result := true;
        end else if (scanner.token = ytkColon) and (fState in [psDetect]) then begin
          SwitchContext(false, false, isNew);
          if isNew then begin
            entry := yeKeyMapStart;
            fState := psReportNullKey;
          end else begin
            entry := yeScalarNull;
            fState := psConsumeValue;
          end;
          Result := true;
        end else if scanner.token = ytkIdent then begin
          tempInd := scanner.tokenIndent;
          scalar := ParseKeyScalar(scanner);
          // we have found a "key: " combination. The previous "start map" was not reported
          // and thus we should report it now
          if (scanner.token = ytkColon) and (fState in [psDetect]) then begin
            SwitchContext(false, false, isNew, tempInd);
            if isNew then begin
              entry := yeKeyMapStart;
              fState := psReportKey;
            end else begin
              entry := yeScalar;
              fState := psConsumeValue;
            end;
            Result := true;
          end else begin
            entry := yeScalar;
            Result := true;
          end;
        end else if scanner.token = ytkDash then begin
          SwitchContext(True, False, isNew);
          if isNew then
            entry := yeArrayStart
          else
            // we're at the same array. let's just read the next value
            done := false;
          scanner.ScanNext;
          Result := true;
        end else if scanner.token = ytkQuestion then begin
          SwitchContext(false, False, isNew);
          if isNew then
            entry := yeKeyMapStart
          else
            done := false;
          scanner.ScanNext;
          fState := psConsumeKeyBlock;
          Result := true;
        end else if scanner.token = ytkCurlyOpen then begin
          SwitchContext(false, true, isNew);
          entry := yeKeyMapStart;
          scanner.ScanNext;
          fState := psConsumeMapKeyFlow;
          Result := true;
        end else if scanner.token = ytkBracketOpen then begin
          SwitchContext(true, true, isNew);
          entry := yeArrayStart;
          scanner.ScanNext;
          fState := psConsumeArrElmFlow;
          Result := true;
        end else if ctx.IsFlowClose(scanner.token) then begin
          Result := true;
          done := true;
          scanner.ScanNext;
          entry := PopupContext;
          fState := ctx.GetParserState;
        end else if (scanner.token = ytkComma) and (ctx.isStarted) then begin
          scanner.ScanNext;
          done := false;
        end else if scanner.token = ytkNodeTag then begin
          tag := scanner.text;
          scanner.ScanNext;
          done := false;
        end else if scanner.token = ytkStartOfDoc then begin
          Result := true;
          if hasDoc then begin
            fState := psReportStartDoc;
            entry := yeDocEnd;
          end else
            entry := yeDocStart;
          scanner.ScanNext;
          hasDoc := true;
        end else if scanner.token = ytkEof then begin
          fState := psEof;
          done := false;
        end else if scanner.token = ytkEndOfDoc then begin
          Result := true;
          if (ctx = root) and (not ctx.isStarted) then begin
            entry := yeDocEnd;
            scanner.ScanNext;
            hasDoc := false;
          end else begin
            entry := PopupContext;
          end;
        end else begin
          raise EYamlInvalidToken.Create(scanner);
        end;

        if initState = psConsumeMapKeyFlow then begin
          ctx.isKeyFound := true;
        end;
      end;

      psReportKey:
      begin
        entry := yeScalar;
        fState := psConsumeKeyValChar;
        Result := true;
      end;

      psReportNullKey:
      begin
        entry := yeScalarNull;
        fState := psConsumeKeyValChar;
        Result := true;
      end;

      psReportStartDoc: begin
        entry := yeDocStart;
        fState := psDetect;
        Result := true;
      end;

      psConsumeKeyBlock: begin
        if scanner.token = ytkIdent then begin
          scalar := ParseKeyScalar(scanner);
          entry := yeScalar;
          fState := psConsumeValue;
          Result := true;
          Exit;

        end else
          raise EYamlInvalidToken.Create(scanner);
      end;

      psConsumeKeyValChar:
      begin
        if scanner.token <> ytkColon then
          raise EYamlInvalidToken.Create(scanner);
        scanner.ScanNext;
        fState := psConsumeValue;
        done := false;
      end;

      psConsumeValue:
      begin
        Result := true;
        SkipCommentsEoln(scanner);
        if scanner.token = ytkColon then begin
          scanner.ScanNext;
          SkipCommentsEoln(scanner);
          done := false;
        end else if scanner.token = ytkMapKey then begin
          // we were expecting the value, but encountered MapKey.
          // that MapKey can be the value (if it's SUB consume)
          // OR, if it's the same, then it's a "null" value
          if (ctx.isStarted) and (not ctx.isArray) and (scanner.tokenIndent = ctx.indent) then begin
            entry := yeScalarNull;
            fState := psDetect;
          end else begin
            // "psDetect" should be able to handle creating the context
            done := false;
            fState := psDetect;
          end;
        end else if scanner.token = ytkEof then begin
          // we were expecting the value. But it's EOF now.
          // let's report it as null, and shutdown everything
          entry := yeScalarNull;
          fState := psEof;
        end else begin
          // trying to parse the value
          fState := psDetect;
          done := false;
        end;
      end;

      psEof:
        if (ctx.isStarted) then begin
          entry := PopupContext;
          Result := true;
        end else if not root.isStarted then begin
          if hasDoc then begin
            entry := yeDocEnd;
            Result := true;
            hasDoc := false;
          end else
            // we're done!
            Result := false;
        end;
    end; // case of fState
  until done;
end;

procedure TYamlParser.ResetContext;
var
  t: TParserContext;
begin
  while Assigned(ctx) and (ctx<>root) do begin
    t:=ctx;
    ctx := ctx.prev;
    t.Free;
  end;
  root.isKeyFound := false;
  root.isArray := false;
  ctx:=root;
end;

function TYamlParser.PopupContext: TYamlEntry;
var
  t : TParserContext;
  ind : integer;
begin
  if ctx=root then begin
    if root.isStarted then begin
      root.isStarted := false;
      if root.isArray then Result := yeArrayEnd
      else Result := yeKeyMapClose;
    end else
      Result := yeScalar;
    Exit;
  end;
  t := ctx;
  ctx := ctx.prev;
  if t.isArray then Result := yeArrayEnd
  else Result := yeKeyMapClose;

  t.Free;

  t:=ctx;

  // falling back the block indent
  ind := -1;
  while Assigned(t) and t.isFlow do
    t:=t.prev;
  if Assigned(t) then ind := t.indent;
  scanner.blockIndent := ind;
end;

procedure TYamlParser.SwitchContext(isArray, isFlow: Boolean; out isNewContext: Boolean; indent: integer = -1);
var
  n  : TParserContext;
  ind : integer;
  flowMatch : Boolean;
begin
  isNewContext := false;
  if indent < 0 then
    ind := scanner.tokenIndent
  else
    ind := indent;

  flowMatch := (not ctx.isFlow) and (not isFlow) and (ctx.indent = ind);

  isNewContext := (not ctx.isStarted)
    or ((ctx.isStarted) and ((ctx.isArray <> isArray) or (not flowMatch)));

  if not (isNewContext) then Exit;
  if ctx.isStarted  then begin
    n := TParserContext.Create;
    n.prev := ctx;
    ctx := n;
  end;

  ctx.isStarted := true;
  ctx.isArray := isArray;
  ctx.isflow := isFlow;
  ctx.indent := ind;

  if not isFlow then
    Scanner.blockIndent:= ind;
end;

procedure TYamlParser.ConsumeDirective(const dir: string);
begin

end;

procedure TYamlParser.CheckValidIndent(out dstContext: TParserContext);
var
  ind : integer;
  t   : TParserContext;
begin
  ind := Scanner.tokenIndent;
  dstContext := ctx;
  if ind >= ctx.indent then Exit; // same or other is fine!

  t := ctx.prev;
  while Assigned(t) do begin
    if ind > t.indent then
      // invalid indentation
      raise EYamlInvalidIndentation.Create(scanner, 'Invalid indentation '+IntToStr(ind));
    if ind = t.indent then begin
      dstContext := t;
      Exit;
    end;
    t := t.prev;
  end;
  raise EYamlInvalidIndentation.Create(scanner, 'Invalid indentation '+IntToStr(ind));
end;

procedure TYamlParser.InitParser;
begin
  fState := psInit;
  errorMsg   := '';
  errorLine  := 0;
  errorChar  := 0;
  errorState := psInit;
  ResetContext;
  hasDoc := false;

  scanner.ScanNext;
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
