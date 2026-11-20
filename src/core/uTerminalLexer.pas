unit uTerminalLexer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections;

type
  { Kategori token untuk syntax terminal Unix-like }
  TTokenType = (ttCommand, ttFlag, ttValue);

  { TTerminalToken - Struktur ringan penyimpan entitas token }
  TTerminalToken = record
    TokenType: TTokenType;
    Text: string;
  end;

  TTokenList = specialize TList<TTerminalToken>;
  TArgDictionary = specialize TDictionary<string, string>;

  { TParsedCommand - Menyimpan hasil ekstraksi perintah beserta flag dan argumennya }
  TParsedCommand = class
  private
    FCommandName: string;
    FFlags: TArgDictionary;
    FPositionalArgs: TStringList;
    FRawTokens: TTokenList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;

    { Fungsi utilitas untuk mengecek keberadaan flag (misal: -bp atau --stealth) }
    function HasFlag(const AFlag: string): Boolean;

    { Mengambil nilai dari flag (misal: -r 20-50 -> GetFlagValue('r') = '20-50') }
    function GetFlagValue(const AFlag: string; const ADefault: string = ''): string;

    property CommandName: string read FCommandName write FCommandName;
    property Flags: TArgDictionary read FFlags;
    property PositionalArgs: TStringList read FPositionalArgs;
    property RawTokens: TTokenList read FRawTokens;
  end;

  { TTerminalLexer - State Machine Lexer untuk memecah string input terminal }
  TTerminalLexer = class
  public
    { Memproses baris perintah menjadi struktur TParsedCommand secara efisien via pointer }
    class function Tokenize(const AInput: string; AOutput: TParsedCommand): Boolean;
  end;

implementation

{ TParsedCommand }

constructor TParsedCommand.Create;
begin
  inherited Create;
  FFlags := TArgDictionary.Create;
  FPositionalArgs := TStringList.Create;
  FRawTokens := TTokenList.Create;
end;

destructor TParsedCommand.Destroy;
begin
  FreeAndNil(FRawTokens);
  FreeAndNil(FPositionalArgs);
  FreeAndNil(FFlags);
  inherited Destroy;
end;

procedure TParsedCommand.Clear;
begin
  FCommandName := '';
  FFlags.Clear;
  FPositionalArgs.Clear;
  FRawTokens.Clear;
end;

function TParsedCommand.HasFlag(const AFlag: string): Boolean;
begin
  Result := FFlags.ContainsKey(LowerCase(AFlag));
end;

function TParsedCommand.GetFlagValue(const AFlag: string; const ADefault: string): string;
begin
  if not FFlags.TryGetValue(LowerCase(AFlag), Result) then
    Result := ADefault;
end;

{ TTerminalLexer }

class function TTerminalLexer.Tokenize(const AInput: string; AOutput: TParsedCommand): Boolean;
type
  TLexState = (lsWhitespace, lsNormal, lsQuoted);
var
  P, PEnd: PChar;
  State: TLexState;
  QuoteChar: Char;
  CurToken: string;
  RawStrings: TStringList;
  i: Integer;
  S, CurrentFlag: string;
  TokenRec: TTerminalToken;
begin
  Result := False;
  if not Assigned(AOutput) then Exit;
  AOutput.Clear;

  S := Trim(AInput);
  if S = '' then Exit;

  RawStrings := TStringList.Create;
  try
    { 1. Lexical Analysis menggunakan iterasi PChar untuk performa maksimal }
    P := PChar(S);
    PEnd := P + Length(S);
    State := lsWhitespace;
    CurToken := '';
    QuoteChar := #0;

    while P < PEnd do
    begin
      case State of
        lsWhitespace:
          begin
            if not (P^ in [' ', #9, #10, #13]) then
            begin
              if P^ in ['"', ''''] then
              begin
                QuoteChar := P^;
                State := lsQuoted;
              end
              else
              begin
                CurToken := P^;
                State := lsNormal;
              end;
            end;
          end;

        lsNormal:
          begin
            if P^ in [' ', #9, #10, #13] then
            begin
              RawStrings.Add(CurToken);
              CurToken := '';
              State := lsWhitespace;
            end
            else if (P^ = '\') and ((P + 1) < PEnd) then
            begin
              { Dukungan karakter escape }
              Inc(P);
              CurToken := CurToken + P^;
            end
            else
              CurToken := CurToken + P^;
          end;

        lsQuoted:
          begin
            if P^ = QuoteChar then
            begin
              RawStrings.Add(CurToken);
              CurToken := '';
              State := lsWhitespace;
            end
            else if (P^ = '\') and ((P + 1) < PEnd) and ((P + 1)^ = QuoteChar) then
            begin
              Inc(P);
              CurToken := CurToken + P^;
            end
            else
              CurToken := CurToken + P^;
          end;
      end;
      Inc(P);
    end;

    { Tambahkan sisa token terakhir }
    if (State in [lsNormal, lsQuoted]) and (CurToken <> '') then
      RawStrings.Add(CurToken);

    if RawStrings.Count = 0 then Exit;

    { 2. Syntactic Analysis: Klasifikasi Command, Flag, dan Value }
    AOutput.CommandName := LowerCase(RawStrings[0]);
    TokenRec.TokenType := ttCommand;
    TokenRec.Text := AOutput.CommandName;
    AOutput.RawTokens.Add(TokenRec);

    CurrentFlag := '';
    for i := 1 to RawStrings.Count - 1 do
    begin
      S := RawStrings[i];

      { Deteksi apakah token merupakan Flag (diawali '-' atau '--') }
      if (Length(S) > 1) and (S[1] = '-') and not (S[2] in ['0'..'9']) then
      begin
        { Jika ada flag sebelumnya yang belum punya value, simpan sebagai boolean flag (nilai kosong) }
        if CurrentFlag <> '' then
          AOutput.Flags.AddOrSetValue(CurrentFlag, '');

        if S[2] = '-' then
          CurrentFlag := LowerCase(Copy(S, 3, MaxInt))
        else
          CurrentFlag := LowerCase(Copy(S, 2, MaxInt));

        TokenRec.TokenType := ttFlag;
        TokenRec.Text := CurrentFlag;
        AOutput.RawTokens.Add(TokenRec);
      end
      else
      begin
        { Token adalah Value untuk flag sebelumnya, atau Positional Argument }
        TokenRec.TokenType := ttValue;
        TokenRec.Text := S;
        AOutput.RawTokens.Add(TokenRec);

        if CurrentFlag <> '' then
        begin
          AOutput.Flags.AddOrSetValue(CurrentFlag, S);
          CurrentFlag := '';
        end
        else
          AOutput.PositionalArgs.Add(S);
      end;
    end;

    { Pastikan flag terakhir yang berdiri sendiri tetap tersimpan }
    if CurrentFlag <> '' then
      AOutput.Flags.AddOrSetValue(CurrentFlag, '');

    Result := True;
  finally
    RawStrings.Free;
  end;
end;

end.

