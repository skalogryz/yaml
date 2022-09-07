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
   ,ytkLiteral
   ,ytkFolded
   ,ytkSQuotedStr
   ,ytkDQuotedStr
   ,ytkDirective
   ,ytkReserved

   ,ytkEoln
   ,ytkIdent
   ,ytkStartOfDoc
   ,ytkEndOfDoc
  );

type
  { TYamlScanner }

  TYamlScanner = class(TObject)
    function DoScanNext: TYamlToken;
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
    blockCount    : integer; 
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
   ,'|'
   ,'>'
   ,#39
   ,'"'
   ,'%'
   ,'<res>'
   ,'<eoln>'
   ,'<ident>'
   ,'<startdoc>'
   ,'<eodoc>'
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

  YamlDecDig = ['0'..'9'];
  YamlHexDig = ['0'..'9','a'..'f','A'..'F'];
  YamlAlpha  = ['a'..'z','A'..'Z'];

  YamlIndicator = c_indicator;

  YamlIdentFirstTest = ['?',':','-'];
  YamlIdentFirst     = ns_char - YamlIndicator + YamlIdentFirstTest;
  YamlIdentSafe      = YamlIdentFirst;
  YamlIdentInBlock   = nb_char - c_flow_indicator;
  YamlIdentOutBlock  = nb_char;

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

// it's trusted that the first character has already been verified by IsPlainFirst() function
function ScanPlainIdent(const buf: string; var idx: integer; const AllowedChars: TCharSet): string;
var
  j : integer;
begin
  j:=idx;
 
  repeat
    inc(idx);
    if (idx<=length(buf)) then begin
      if (buf[idx] = '#') and (buf[idx-1] in WhiteSpaceChars) then begin
        dec(idx); // falling back! we've found the command
        break;
      end else if (buf[idx] = ':') and not (SafeChar(buf, idx+1) in YamlIdentSafe+[#0]) then
        break
      else if not (buf[idx] in AllowedChars) then
        break;
    end;
  until idx>length(buf);
  Result := Copy(buf, j, idx-j);
end;

function ScanDblQuote(const buf: string; var idx: integer): string;
var
  j : integer;
begin
  if (idx>length(buf)) or (buf[idx]<>'"') then begin
    Result:='';
    Exit;
  end;
  j:=idx;
  inc(idx);
  while (idx<=length(buf)) do begin
    SkipTo(buf, idx, ['"','\']);
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
    end;
  end;
  Result := Copy(buf, j, idx-j);
end;

function ScanSingleQuote(const buf: string; var idx: integer): string;
var
  j : integer;
begin
  if (idx>length(buf)) or (buf[idx]<>#39) then begin
    Result:='';
    Exit;
  end;
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
  Result := Copy(buf, j, idx-j);
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
  s : string;
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

  if IsPlainFirst(buf, idx) then begin
    Result := ytkIdent;
    if blockCount = 0 then begin
      if IsDocStruct(buf, idx, Result, text) then
        Exit;
      text := ScanPlainIdent(buf, idx, YamlIdentOutBlock);
    end else
      text := ScanPlainIdent(buf, idx, YamlIdentInBlock);
  end else if buf[idx] = '"' then begin
    identQuotes := 2;
    text := ScanDblQuote(buf, idx);
    Result := ytkIdent;
  end else if buf[idx] = #39 then begin
    identQuotes := 1;
    text := ScanSingleQuote(buf, idx);
    Result := ytkIdent;
  end else begin
    tokenIndent := idx - newLineOfs;
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
        Exit;
      end;
      '-': begin Result := ytkSequence; inc(idx); end;
      ':': begin Result := ytkMapValue; inc(idx); end;
      ',': begin Result := ytkSeparator; inc(idx); end;
      '[': begin Result := ytkBlockOpen; inc(idx); inc(blockCount); end;
      ']': begin Result := ytkBlockClose; inc(idx); dec(blockCount); end;
      '{': begin Result := ytkMapStart; inc(idx); inc(blockCount); end;
      '}': begin Result := ytkMapClose; inc(idx); dec(blockCount); end;
      '&': begin Result := ytkAnchor; inc(idx); end;
      '*': begin Result := ytkAlias; inc(idx); end;
      '!': begin
         Result := ytkNodeTag;
         text := StrWhile(buf, idx, YamlTagChars);
      end;
      '|': begin Result := ytkLiteral; inc(idx); end;
      '>': begin Result := ytkFolded; inc(idx); end;
      '%': begin
         Result := ytkDirective; inc(idx);
         text := StrTo(buf, idx, ['#']+LineBreaks);
      end;
      '@','`': begin Result := ytkReserved; inc(idx); end;
    else
      Result := ytkError;
    end;
  end;
  SkipWhile(buf, idx, WhiteSpaceChars);
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

