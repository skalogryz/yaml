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

  { TYamlScanner }

  TYamlScanner = class(TObject)
  private
    isNewLine: Boolean;
  public
    idx           : Integer;
    buf           : string;
    tokenIdent    : Integer;
    identQuotes   : integer;
    tabsSpaceMod  : Integer; // tabs to space modifier
    text          : string;
    blockCount    : integer; 
    constructor Create;
    procedure SetBuffer(const abuf: string);
    function ScanNext: TYamlToken;
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

function IsPlainFirst(const buf: string; idx: integeR): Boolean; {$ifdef hasline}inline;{$endif}

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

function TYamlScanner.ScanNext: TYamlToken;
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
    isNewLine := false;
    s := StrWhile(buf, idx, WhiteSpaceChars);
    tokenIdent := StrToIdent(s, tabsSpaceMod);
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
    case buf[idx] of
      '#': begin
        Result := ytkComment;
        inc(idx);
        SkipWhile(buf, idx, WhiteSpaceChars);
        text := StrTo(buf, idx, LineBreaks);
      end;
      #13,#10: begin
        SkipWhile(buf, idx, LineBreaks);
        Result := ytkEoln;
        isNewLine := true;
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
      '!': begin Result := ytkNodeTag; inc(idx); end;
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

end.

