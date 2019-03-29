unit Utils;

interface

uses
  Classes, SysUtils, Windows, Forms;

type
  TStrings = array of string;
  TCharSet = set of Char;

  TApplicationVersion = record
    Major, Minor, Release, Build: Word;
  end;

const
  Space: string = ' ';
  LineBreak: string = #13#10;

  HexCharSet: TCharSet =  ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'A', 'B', 'C', 'D', 'E', 'F'];
  UserNameCharSet: TCharSet = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i',
    'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
    'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '_', '-'];

function ApplicationVersion: TApplicationVersion;
function ApplicationFileName: string;
function SettingsFileName: string;
procedure WriteStrToFile(const Str: string; const FileName: string);
function CharCount(const Ch: Char; const Str: string): Integer;
function CharPos(const Ch: Char; const Str: string): Integer;
function StrConsistsOfChars(const Str: string; const CharSet: TCharSet): Boolean;
function DisAssembleStr(const Str: string; const Delimiter: Char): TStrings;
function EncodeStr(const Str: string; const EmptyStrCode: string;
  const CharsPerEncodedChar: Integer): string;
function DecodeStr(const Str: string; const EmptyStrCode: string;
  const CharsPerEncodedChar: Integer): string;

implementation

function ApplicationVersion: TApplicationVersion;
const
  VersionShrBits: Integer = 16;
  HexFullBits: Integer = $FFFF;
var
  Info: Pointer;
  FileInfo: PVSFixedFileInfo;
  InfoSize, FileSize: Cardinal;
begin
  InfoSize := GetFileVersionInfoSize(PChar(Application.ExeName), FileSize);
  GetMem(Info, InfoSize);
  try
    GetFileVersionInfo(PChar(Application.ExeName), 0, InfoSize, Info);
    VerQueryValue(Info, '\', Pointer(FileInfo), FileSize);

    Result.Major := FileInfo.dwFileVersionMS shr VersionShrBits;
    Result.Minor := FileInfo.dwFileVersionMS and HexFullBits;
    Result.Release := FileInfo.dwFileVersionLS shr VersionShrBits;
    Result.Build := FileInfo.dwFileVersionLS and HexFullBits;
  finally
    FreeMem(Info);
  end;
end;

function ApplicationFileName: string;
begin
  Result := ParamStr(0);
end;

function SettingsFileName: string;
const
  SettingsFileExt: string = '.ini';
begin
  Result := ChangeFileExt(ParamStr(0), SettingsFileExt);
end;

procedure WriteStrToFile(const Str: string; const FileName: string);
var
  S: string;
  F: TFileStream;
  PStr: PChar;
  StrLength: Integer;
begin
  S := Str + LineBreak;
  StrLength := Length(S);
  PStr := StrAlloc(StrLength + 1);
  StrPCopy(PStr, S);

  try
    if FileExists(FileName) then
    begin
      F := TFileStream.Create(FileName, fmOpenWrite);
    end
    else
    begin
      F := TFileStream.Create(FileName, fmCreate);
    end;

    try
      F.Position := F.Size;
      F.Write(PStr^, StrLength);
    finally
      F.Free;
    end;
  finally
    StrDispose(PStr);
  end;
end;

function CharCount(const Ch: Char; const Str: string): Integer;
var
  CharCounter: Integer;
begin
  Result := 0;

  for CharCounter := 1 to Length(Str) do
  begin
    if Str[CharCounter] = Ch then
    begin
      Inc(Result);
    end;
  end;
end;

function CharPos(const Ch: Char; const Str: string): Integer;
var
  CharCounter: Integer;
begin
  Result := 0;

  for CharCounter := 1 to Length(Str) do
  begin
    if Str[CharCounter] = Ch then
    begin
      Result := CharCounter;
      Break;
    end;
  end;
end;

function StrConsistsOfChars(const Str: string; const CharSet: TCharSet): Boolean;
var
  CharCounter: Integer;
begin
  Result := True;

  if (Str <> EmptyStr) and (CharSet <> []) then
  begin
    for CharCounter := 1 to Length(Str) do
    begin
      if not (Str[CharCounter] in CharSet) then
      begin
        Result := False;
        Break;
      end;
    end;
  end
  else
  begin
    Result := False;
  end;
end;

function DisAssembleStr(const Str: string; const Delimiter: Char): TStrings;
var
  CharCounter, StrLength, ChPos, SubstrCount: Integer;
  Substr: string;
begin
  SetLength(Result, 0);

  StrLength := Length(Str);
  SubstrCount := 0;
  ChPos := 1;

  for CharCounter := 1 to StrLength do
  begin
    if (Str[CharCounter] = Delimiter) or (CharCounter = StrLength) then
    begin
      Inc(SubstrCount);
      SetLength(Result, SubstrCount);

      if StrLength <> CharCounter then
        Substr := Copy(Str, ChPos, CharCounter - ChPos)
      else
        Substr := Copy(Str, ChPos, CharCounter - ChPos + 1);

      Result[SubstrCount - 1] := Substr;
      ChPos := CharCounter + 1;
    end;
  end;
end;

function EncodeStr(const Str: string; const EmptyStrCode: string;
  const CharsPerEncodedChar: Integer): string;
var
  CharCounter: Integer;
begin
  if Str = EmptyStr then
  begin
    Result := EmptyStrCode;
  end
  else
  begin
    Result := EmptyStr;

    for CharCounter := 1 to Length(Str) do
    begin
      Result := Result + IntToHex(Ord(Str[CharCounter]), CharsPerEncodedChar);
    end;
  end;
end;

function DecodeStr(const Str: string; const EmptyStrCode: string;
  const CharsPerEncodedChar: Integer): string;
var
  CharCounter: Integer;
  EncodedCharStr: string;
begin
  Result := EmptyStr;

  if Str <> EmptyStrCode then
  begin
    EncodedCharStr := EmptyStr;
    for CharCounter := 1 to Length(Str) do
    begin
      EncodedCharStr := EncodedCharStr + Str[CharCounter];
      if Length(EncodedCharStr) = CharsPerEncodedChar then
      begin
        Result := Result + Chr(StrToInt('$' + EncodedCharStr));
        EncodedCharStr := EmptyStr;
      end;
    end;
  end;  
end;

end.
