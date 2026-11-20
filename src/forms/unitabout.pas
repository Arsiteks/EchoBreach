unit UnitAbout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, LCLIntf, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Buttons, ComCtrls;

type

  { TFormAbout }

  TFormAbout = class(TForm)
    BtnClose: TButton;
    Image1: TImage;
    Image2: TImage;
    Label1: TLabel;
    Label2: TLabel;
    lbLink: TLabel;
    LblTech: TLabel;
    LblTitle: TLabel;
    LblVersion: TLabel;
    LblCopyright: TLabel;
    PageControl1: TPageControl;
    PanelHeader: TPanel;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    procedure BtnCloseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure lbLinkClick(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
  end;

var
  FormAbout: TFormAbout;

implementation

{$R *.lfm}

{ TFormAbout }

procedure TFormAbout.FormCreate(Sender: TObject);
begin
  Self.Caption := 'About Mes';


end;

procedure TFormAbout.lbLinkClick(Sender: TObject);
begin
  OpenDocument('https://github.com/CodeInPas?tab=repositories');
end;

procedure TFormAbout.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

end.
