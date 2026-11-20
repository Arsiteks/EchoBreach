unit uAbout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls;

type
  { TAboutForm }
  TAboutForm = class(TForm)
    btnClose: TButton;
    lblTitle: TLabel;
    lblVersion: TLabel;
    memCredits: TMemo;
    pnlMain: TPanel;
    procedure btnCloseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
  public
  end;

var
  AboutForm: TAboutForm;

implementation

{$R *.lfm}

{ TAboutForm }

procedure TAboutForm.btnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TAboutForm.FormCreate(Sender: TObject);
begin
  { Setup tema terminal untuk form About }
  Color := clBlack;
  BorderStyle := bsNone;
  Position := poMainFormCenter;

  memCredits.Lines.Clear;
  memCredits.Lines.Add('=========================================');
  memCredits.Lines.Add('      ECHO_BREACH: THE SIGNAL CARTEL     ');
  memCredits.Lines.Add('=========================================');
  memCredits.Lines.Add('');
  memCredits.Lines.Add('CORE TECH STACK:');
  memCredits.Lines.Add(' > Compiler   : Free Pascal (FPC)');
  memCredits.Lines.Add(' > Framework  : Lazarus (LCL)');
  memCredits.Lines.Add(' > Graphics   : BGRABitmap & TAChart');
  memCredits.Lines.Add(' > Audio DSP  : BASS Audio Engine');
  memCredits.Lines.Add(' > Networking : mORMot 2 (Microservices)');
  memCredits.Lines.Add(' > Database   : SQLite3');
  memCredits.Lines.Add('');
  memCredits.Lines.Add('DEVELOPED BY  : Lead 2D Game Designer');
  memCredits.Lines.Add('YEAR          : 2026');
  memCredits.Lines.Add('=========================================');
  memCredits.SelStart := 0;
end;

end.

