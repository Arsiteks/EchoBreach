program EchoBreach;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, tachartlazaruspkg,
  uMain in 'src\forms\uMain.pas', UnitAbout,
  BASS;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title:='ECHO_BREACH: The Signal Cartel';
  Application.Scaled:=True;
  Application.Initialize;

  Application.CreateForm(TMainForm, MainForm);



  Application.CreateForm(TFormAbout, FormAbout);
  Application.Run;
end.

