unit yamlscanner;

{$ifdef fpc}
{$mode delphi}{$H+}
{$define hasinline}
{$endif}

interface

uses
  Classes, SysUtils, parseutils;

type
  TYamlToken = (
    ytkEof
   ,ytkError
   ,ytkSequence
   ,ytkMapKey
   ,ytkMapValue
   ,ytkSeparator
   ,ytkBlockOpen
   ,ytkBlockClose
   ,ytkMapStart
   ,ytkMapClose
   ,ytkComment
   ,ytkAnchor
   ,ytkAlias
   ,ytkNodeTag
   ,ytkDirective
   ,ytkReserved

   ,ytkEoln
   ,ytkScalar
   ,ytkStartOfDoc
   ,ytkEndOfDoc
  );

  TYamlScannerError = (
    errNoError        // no error
   ,errUnexpectedEof  // unexpected end of file
   ,errNeedEoln       // expected end of line, but something else was found
   ,errInvalidChar    // invalid character encountered
   ,errInvalidIndent  // invalid (or inconsistent) indentation
  );

const
  ytkIdent = ytkScalar;


type
  { TYamlScanner }

  TYamlScanner = class(TObject)
  protected
    function DoScanNext: TYamlToken;
    function ScanLiteral(out txt: string): TYamlScannerError;
    function ScanDblQuote(out txt: string): TYamlScannerError;
    function ScanSingleQuote(out txt: string): TYamlScannerError;
    function ScanPlainScalar(out atoken: TYamlToken; out txt: string): TYamlScannerError;
  public
    newLineOfs    : Integer;
    isNewLine     : Boolean;
    idx           : Integer;
    buf           : string;
    tokenIndent   : Integer;
    identQuotes   : integer;
    tabsSpaceMod  : Integer; // tabs to space modifier
    text          : string;
    token         : TYamlToken;
    flowCount     : integer;
    lineNum       : integer;
    tokenIdx      : integer;
    blockIndent   : Integer; // if negative, then ignored
    error         : TYamlScannerError;
    constructor Create;
    procedure SetBuffer(const abuf: string);
    function ScanNext: TYamlToken;
    function GetValue: string;
  end;

const
  YamlTokenStr : array [TYamlToken] of string = (
    '<eof>'
   ,'<error>'
   ,'-'
   ,'?'
   ,':'
   ,','
   ,'['
   ,']'
   ,'{'
   ,'}'
   ,'#'
   ,'&'
   ,'*'
   ,'!'
   ,'%'
   ,'<res>'
   ,'<eoln>'
   ,'<ident>'
   ,'<startdoc>'
   ,'<eodoc>'
  );

  YamlErrorStr : array [TYamlScannerError] of string = (
    'no error'
   ,'unexpected end of file'
   ,'expected end of line'
   ,'invalid character encountered'
   ,'invalid indentation'
  );

const
  c_printable = [
    #$09                 // Tab (\t)
  , #$0A                 // Line feed (LF \n)
  , #$0D                 // Carriage Return (CR \r)
  , #32..#255            // Printable ASCII
                         // 16 bit
  // x85                  // Next Line (NEL)
  // [xA0-xD7FF]          // Basic Multilingual Plane (BMP)
  // [xE000-xFFFD]        // Additional Unicode Areas
  // [x010000-x10FFFF]    // 32 bit
  ];
  nb_json   = [#09, #32..#255];
  c_byte_order = $FEFF;
  c_indicator = [
     '-','?',':',',','[',']','{','}','#','&'
    ,'*','!','|','>',#39,'"','%','@','`'];
  c_flow_indicator = [',','[',']','{','}'];
  b_line_feed = #$0a;
  b_carriage_return = #$0d;
  b_char = [b_line_feed, b_carriage_return];
  nb_char = c_printable - b_char; // - c_byte_order_mark
  s_space = #32;
  s_tab   = #9;
  s_white = [s_space, s_tab];
  ns_char = nb_char - s_white;
  ns_anchor_name = ns_char - c_flow_indicator;

  YamlDecDig = ['0'..'9'];
  YamlHexDig = ['0'..'9','a'..'f','A'..'F'];
  YamlAlpha  = ['a'..'z','A'..'Z'];

  YamlIndicator = c_indicator;

  YamlIdentFirstTest = ['?',':','-'];
  YamlIdentFirst     = ns_char - YamlIndicator + YamlIdentFirstTest;
  YamlIdentSafe      = YamlIdentFirst;
  YamlIdentInFlow    = nb_char - c_flow_indicator;
  YamlIdentOutFlow   = nb_char;

  YamlURI    = YamlAlpha + YamlDecDig + ['%','#'
                ,';' ,'/' ,'?' ,':' ,'@' ,'&' ,'='
                ,'+' ,'$' ,',' ,'_' ,'.' ,'!' ,'~'
                ,'*' ,#39 ,'(' ,')' ,'[' ,']'];
  YamlTagChar = YamlURI - ['!',',','[',']','{','}'];

  YamlTagChars = ['!']+ YamlAlpha  + YamlDecDig +['-','<','>'];

function IsPlainFirst(const buf: string; idx: integeR): Boolean; {$ifdef hasline}inline;{$endif}

function GetTextToValue(const text: string): string;
function SQuoteToValue(const text: string): string;
function DQuoteToValue(const text: string): string;

implementation

function IsPlainFirst(const buf: string; idx: integeR): Boolean; {$ifdef hasline}inline;{$endif}
begin
  Result := (buf[idx] in YamlIdentFirst)
    and (
      not (buf[idx] in YamlIdentFirstTest)
      or (SafeChar(buf, idx+1) in YamlIdentSafe+[#0])
      )
end;

function IsDocStruct(const buf: string; var idx: integer; var tkn: TYamlToken; var tknText: string ): Boolean;
var
  n : integer;
begin
  n := idx+2;
  Result := (n<=length(buf));
  if not Result then Exit;

  // the 4th character must not be, or must be line break
  if (n+1 <= length(buf)) and not (buf[n+1] in WhiteSpaceChars+LineBreaks) then
    Result := false;
  if not Result then Exit;

  if (buf[idx]='-') and (buf[idx+1]='-') and (buf[idx+2]='-') then begin
    Result := true;
    tknText := '---';
    tkn:=ytkStartOfDoc;
    inc(idx, 3);
  end else if (buf[idx]='.') and (buf[idx+1]='.') and (buf[idx+2]='.') then begin
    Result := true;
    tknText := '...';
    tkn:=ytkEndOfDoc;
    inc(idx, 3);
  end else
    Result := false;
  if Result then
    SkipWhile(buf, idx, WhiteSpaceChars);
end;

function TYamlScanner.ScanDblQuote(out txt: string): TYamlScannerError;
var
  j : integer;
  s : string;
begin
  txt:='';
  if (idx>length(buf)) then begin
    Result := errUnexpectedEof;
    Exit;
  end;
  if (buf[idx]<>'"') then begin
    Result := errInvalidChar;
    Exit;
  end;
  Result := errNoError;
  j:=idx;
  inc(idx);
  while (idx<=length(buf)) do begin
    SkipTo(buf, idx, ['"','\']+LineBreaks);
    if (idx > length(buf)) then break;
    if (buf[idx] = '\') then begin
      inc(idx);
      if (idx <= length(buf)) and (buf[idx] in ['x','u','U']) then begin
        inc(idx);
        SkipWhile(buf, idx, YamlHexDig);
      end else
        inc(idx);
    end else if (buf[idx] = '"') then begin
      inc(idx);
      break;
    end else if (buf[idx] in LineBreaks) then begin
      s := TrimLeft(Copy(buf, j, idx-j));
      SkipOneEoln(buf, idx);
      newLineOfs:=idx;
      inc(lineNum);
      if s ='' then txt := txt+#10
      else begin
        if txt = '' then txt := s
        else txt := txt + ' ' +s;
      end;
      SkipWhile(buf, idx, WhiteSpaceChars);
      j:=idx;
    end;
  end;

  s := Copy(buf, j, idx-j);
  if txt = '' then txt := s
  else txt := txt + ' ' +s;
end;

function TYamlScanner.ScanSingleQuote(out txt: string): TYamlScannerError;
var
  j : integer;
begin
  txt := '';
  if (idx>length(buf)) then begin
    Result := errUnexpectedEof;
    Exit;
  end;
  if (buf[idx]<>#39) then begin
    Result := errInvalidChar;
    Exit;
  end;
  Result := errNoError;
  j:=idx;
  inc(idx);
  while (idx<=length(buf)) do begin
    SkipTo(buf, idx, [#39]);
    if (idx > length(buf)) then break;
    if (buf[idx] = #39) then begin
      if (idx<length(buf)) and (buf[idx+1]=#39) then 
        inc(idx,2)
      else
        break;
    end else
      inc(idx);
  end;
  if (idx <= length(buf)) then inc(idx);
  txt := Copy(buf, j, idx-j);
end;

{ TYamlScanner }

constructor TYamlScanner.Create;
begin
  inherited Create;
  tabsSpaceMod := 1;
  idx := 1;
end;

procedure TYamlScanner.SetBuffer(const abuf: string);
begin
  buf := abuf;
  idx := 1;
  isNewLine := true;
  newLineOfs := 1;
  lineNum := 1;
  blockIndent := -1;
end;

function StrToIdent(const s: string; tabsSpaceMod: integer): integer;
var
  i : integer;
  tb : integer;
begin
  Result := 0;
  tb := 0;
  for i := 1 to length(s) do
    if s[i] = #9 then inc(tb);
  if (tabsSpaceMod<0) then tabsSpaceMod := 0
  else dec(tabsSpaceMod);
  Result := length(s) + tb * tabsSpaceMod;
end;

function TYamlScanner.DoScanNext: TYamlToken;
var
  s        : string;
  isFirst  : Boolean;
begin
  text := '';
  identQuotes := 0;
  if idx>length(buf) then begin
    Result := ytkEof;
    Exit;
  end;

  if isNewLine then begin
    newLineOfs := idx;
    isNewLine := false;
    s := StrWhile(buf, idx, WhiteSpaceChars);
    tokenIndent := StrToIdent(s, tabsSpaceMod);
    if (idx>length(buf)) then begin
      Result := ytkEof;
      Exit;
    end;
  end;

  tokenIdx := idx;
  tokenIndent := idx - newLineOfs;
  if IsPlainFirst(buf, idx) then begin
    isFirst := true;
    error := ScanPlainScalar(Result, text);
    if error<>errNoError then
      Result := ytkError;
  end else if buf[idx] = '"' then begin
    identQuotes := 2;
    error := ScanDblQuote(text);
    if error<>errNoError then
      Result := ytkError
    else
      Result := ytkIdent;
  end else if buf[idx] = #39 then begin
    identQuotes := 1;
    error := ScanSingleQuote(text);
    if error<>errNoError then
      Result := ytkError
    else
    Result := ytkIdent;
  end else begin
    case buf[idx] of
      '#': begin
        Result := ytkComment;
        inc(idx);
        SkipWhile(buf, idx, WhiteSpaceChars);
        text := StrTo(buf, idx, LineBreaks);
      end;
      #13,#10: begin
        text := StrOneEoln(buf, idx);
        Result := ytkEoln;
        isNewLine := true;
        inc(lineNum);
        Exit;
      end;
      '-': begin Result := ytkSequence; inc(idx); end;
      '?': begin Result := ytkMapKey; inc(idx); end;
      ':': begin Result := ytkMapValue; inc(idx); end;
      ',': begin Result := ytkSeparator; inc(idx); end;
      '[': begin Result := ytkBlockOpen; inc(idx); inc(flowCount); end;
      ']': begin Result := ytkBlockClose; inc(idx); dec(flowCount); end;
      '{': begin Result := ytkMapStart; inc(idx); inc(flowCount); end;
      '}': begin Result := ytkMapClose; inc(idx); dec(flowCount); end;
      '&': begin
        Result := ytkAnchor;
        inc(idx);
        text := StrWhile(buf, idx, ns_anchor_name);
      end;
      '*': begin Result := ytkAlias; inc(idx); end;
      '!': begin
        Result := ytkNodeTag;
        text := StrWhile(buf, idx, YamlTagChars);
      end;
      '|','>': begin
        error := ScanLiteral(text);
        if error = errNoError then
          Result := ytkIdent
        else
          Result := ytkError;
      end;
      '%': begin
         Result := ytkDirective; inc(idx);
         text := StrTo(buf, idx, ['#']+LineBreaks);
      end;
      '@','`': begin Result := ytkReserved; inc(idx); end;
    else
      error := errInvalidChar;
      Result := ytkError;
    end;
  end;

  SkipWhile(buf, idx, WhiteSpaceChars);
end;

function TYamlScanner.ScanPlainScalar(out atoken: TYamlToken; out txt: string): TYamlScannerError;
var
  s       : string;
  isFirst : Boolean;
  j       : integer;
  ofs     : integer;
  AllowedChars : TCharSet;
begin
  atoken := ytkScalar;;
  txt := '';
  Result := errNoError;
  isFirst := true;

  if flowCount > 0 then
    AllowedChars := YamlIdentInFlow
  else
    AllowedChars := YamlIdentOutFlow;

  j := idx;
  while (idx<=length(buf)) do begin

    if isFirst and IsDocStruct(buf, idx, atoken, txt) then begin
      // this is some other token, not indent
      Break;
    end;

    if (buf[idx] in LineBreaks) then begin
      s := Trim(Copy(buf, j, idx-j));
      isFirst := false;
      SkipOneEoln(buf, idx);
      newLineOfs:=idx;
      inc(lineNum);

      SkipWhile(buf, idx, WhiteSpaceChars);
      if s = '' then
        txt := txt+#10
      else begin
        if txt = '' then txt := s
        else txt := txt + ' '+s;
      end;

      if s<>'' then begin
        ofs := idx - newLineOfs;
        if ofs<=blockIndent then break; // we're done!
      end;

      j:=idx;
    end;
    if (buf[idx] = '#') and (buf[idx-1] in WhiteSpaceChars) then begin
      dec(idx); // falling back! we've found the command
      break;
    end else if (buf[idx] = ':') and not (SafeChar(buf, idx+1) in YamlIdentSafe+[#0]) then
      break
    else if not (buf[idx] in AllowedChars) then
      break
    else
      inc(idx);
  end;

  s := Trim(Copy(buf, j, idx-j));
  if s <> '' then begin
    if txt = '' then txt := s
    else txt := txt + ' '+s;
  end;

end;

procedure ScanIndNum(const buf: string; var idx: integer; var ind: integer);
begin
  if (idx<=length(buf)) and (buf[idx] in ['1'..'9']) then begin
    ind := byte(buf[idx]) - byte('0');
    inc(idx);
  end;
end;

procedure ScanChomp(const buf: string; var idx: integer; var chomp: char);
begin
  if (idx<=length(buf)) and (buf[idx] in ['-','+']) then begin
    chomp := buf[idx];
    inc(idx);
  end;
end;

procedure ScanLitHeader(const buf: string; var idx: integer; var ind: integer; var chomp: char);
begin
  if (idx > length(buf)) then Exit;
  if buf[idx] in ['1'..'9'] then begin
    ScanIndNum(buf, idx, ind);
    ScanChomp(buf, idx, chomp);
  end else begin
    ScanChomp(buf, idx, chomp);
    ScanIndNum(buf, idx, ind);
  end;
end;

function TYamlScanner.ScanLiteral(out txt: string): TYamlScannerError;
var
  isFolded: Boolean;
  ind     : integer;
  chomp   : char;
  j       : integer;
  ofs     : integer;
  ts      : string;
begin
  txt := '';
  if (idx > length(buf)) then begin
    Result  := errUnexpectedEof;
    Exit;
  end;

  isFolded := buf[idx]='>';
  if not (isFolded or (buf[idx]='|')) then begin
    error := errInvalidChar;
    Exit;
  end;

  inc(idx);
  ind := -1;
  chomp := #0;
  // scanning header
  ScanLitHeader(buf, idx, ind, chomp);
  SkipWhile(buf, idx, WhiteSpaceChars);
  // header scannerd.

  Result := errNoError;
  while (idx <= length(buf)) do begin
    if not (buf[idx] in LineBreaks) then begin
      // expecting eoln to be here
      Result := errNeedEoln;
      Exit;
    end;
    SkipOneEoln(buf, idx);
    inc(lineNum);
    newLineOfs := idx;

    j := idx;
    SkipWhile(buf, idx, WhiteSpaceChars);
    if (idx<=length(buf)) and (buf[idx] in LineBreaks) then begin
      // we have an empty line
      txt := txt+#10;
      continue;
    end;
    ofs := idx - newLineOfs;

    if (blockIndent >= 0) and (ofs <= blockIndent) then begin
      // the character begins with the block ident, that means the scalar has finished
      // we're done here
      Break;
    end;
    if (ind < 0) then ind := ofs;

    if (ofs < ind) then begin
      // invalid indentation ?
      // Result := errInvalidIndent;
      break;
    end;
    ts := StrTo(buf, idx, LineBreaks);
    if ofs > ind then txt := txt + StringOfChar(#32, ofs - ind);
    if not isFolded then begin
      txt := txt + ts + #10;
    end else begin
      if txt='' then txt := ts
      else txt := txt + ' ' + ts;
    end;
  end;

  if Result = errNoError then begin
    // todo: fold here!

    case chomp of
      '-':
        if (txt<>'') and (txt[length(txt)]=#10) then
          txt := TrimRight(txt);
      '+':
         if (txt = '') then txt := #10;
    else
      j := length(txt);
      if (j > 0) and (txt[length(txt)] <> #10) then begin
        txt := txt + #10;
      end else begin
        while (j>1) and (txt[j-1]=#10) do dec(j);
        txt := Copy(txt,1,j);
      end;
    end;
  end;
end;

function TYamlScanner.ScanNext: TYamlToken;
begin
  token := DoScanNext;
  Result := token;
end;

function TYamlScanner.GetValue: string;
begin
  Result := GetTextToValue(text);
end;

function SQuoteToValue(const text: string): string;
var
  i : integer;
  j : integer;
  ln : integer;
begin
  if (text ='') or (text[1]<>#39) then begin
    Result:=text;
    exit;
  end;
  Result := '';
  j:=2;
  ln := length(text)-1;
  i:=2;
  while i<=ln do begin
    if text[i]=#39 then begin
      Result := Result+Copy(text, j, i-j);
      j:=i+1;
      inc(i, 2);
    end else
      inc(i);
  end;
  if j = 2 then Result := Copy(text, 2, length(text)-2)
  else Result := Result+Copy(text, j, length(text)-j);
end;

function CodeToStr(ch: Char; const code: string): string;
begin
  //todo:
  Result := '';
end;

function DQuoteToValue(const text: string): string;
var
  i : integer;
  j : integer;
  ln : integer;
  ch : char;
  cd : string;
begin
  Result := '';
  if text ='' then Exit;
  if (text[1]<>'"') then begin
    Result := text;
    Exit;
  end;
  i := 2;
  j := 2;
  ln := length(text);
  while i<ln do begin
    if text[i] = '\' then begin
      Result := Result + Copy(text, j, i-j);
      inc(i);
      if i>=ln then begin
        j := i+2;
        Break;
      end;
      ch := text[i];
      inc(i);
      case ch of
        '0': Result := Result+#0;
        'a': Result := Result+#7;
        'b': Result := Result+#8;
        't': Result := Result+#9;
        'n': Result := Result+#10;
        'v': Result := Result+#11;
        'f': Result := Result+#12;
        'r': Result := Result+#13;
        'e': Result := Result+#27;
        '"': Result := Result+'"';
        '/': Result := Result+'/';
        '\': Result := Result+'\';
        'N': Result := Result+#$85;
        '_': Result := Result+#$A0;
        'L': Result := Result+#$E2#$80#$A8;
        'P': Result := Result+#$E2#$80#$A9;
        'x','u','U': begin
          cd := StrWhile(text, i, YamlHexDig);
          Result := Result+CodeToStr(ch, cd);
        end;
      else
        Result := Result+ch;
      end;
      j := i;
    end else
      inc(i);
  end;
  Result := Result + Copy(text, j, length(text)-j);
end;

function GetTextToValue(const text: string): string;
begin
  if text = '' then Result := text
  else if text[1]=#39 then Result := SQuoteToValue(text)
  else if text[1]='"' then Result := DQuoteToValue(text)
  else Result := text;
end;

end.

