unit uSplash;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls;

type
  { TSplashForm }
  TSplashForm = class(TForm)
    lblTitle: TLabel;
    lblSubtitle: TLabel;
    lblStatus: TLabel;
    pnlBackground: TPanel;
    tmrAnim: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure tmrAnimTimer(Sender: TObject);
  private
    FAnimStep: Integer;
  public
  end;

var
  SplashForm: TSplashForm;

implementation

{$R *.lfm}

{ TSplashForm }

procedure TSplashForm.FormCreate(Sender: TObject);
begin
  { Pengaturan dasar form splash screen ala retro terminal }
  BorderStyle := bsNone;
  Position := poScreenCenter;
  Color := clBlack;
  FAnimStep := 0;

  { Pastikan timer aktif saat form dibuat }
  if Assigned(tmrAnim) then
  begin
    tmrAnim.Interval := 250;
    tmrAnim.Enabled := True;
  end;
end;

procedure TSplashForm.tmrAnimTimer(Sender: TObject);
const
  LoadingText: array[0..3] of string = (
    '[*] Booting ECHO-OS kernel...',
    '[*] Initializing Acoustic Mesh Interface...',
    '[*] Loading BASS Audio DSP modules...',
    '[!] Establishing secure proxy connection...'
  );
begin
  { Animasi terminal loading sederhana }
  if FAnimStep <= High(LoadingText) then
  begin
    lblStatus.Caption := LoadingText[FAnimStep];
    Inc(FAnimStep);
  end
  else
    FAnimStep := 0;
end;

end.

