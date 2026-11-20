unit uMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, UnitAbout, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Menus, TAGraph, TASeries, BGRABitmap, BGRABitmapTypes, uGameManager, uAbout;

type
  { TMainForm }
  TMainForm = class(TForm)
    ChartOscilloscope: TChart;
    edtCommand: TEdit;
    lblICEWarning: TLabel;
    lblOverlayTitle: TLabel;
    lblOverlayDesc: TLabel;
    LineSeries1: TLineSeries;
    LineSeries2: TLineSeries;
    MainMenu1: TMainMenu;
    memTerminal: TMemo;
    MenuItem1: TMenuItem;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    mnAbout: TMenuItem;
    mnTerminate: TMenuItem;
    mnTutorial: TMenuItem;
    pbCRT: TPaintBox;
    pbHeader: TPaintBox;  // <-- Kanvas HUD Modern di bagian atas
    pbInfoBox: TPaintBox; // <-- PaintBox di sebelah Chart
    pnlBottomBar: TPanel; // <-- Kontainer bawah yang menampung Chart dan InfoBox
    pnlCRT: TPanel;
    pnlHeader: TPanel;
    pnlTerminal: TPanel;
    pnlTerminalInput: TPanel;
    pnlOverlay: TPanel;
    Separator1: TMenuItem;
    tmrUIUpdate: TTimer;

    procedure edtCommandKeyPress(Sender: TObject; var Key: char);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure mnAboutClick(Sender: TObject);
    procedure pbCRTPaint(Sender: TObject);
    procedure pbCRTResize(Sender: TObject);
    procedure pbHeaderPaint(Sender: TObject);  // <-- Handler render HUD Header
    procedure pbHeaderResize(Sender: TObject); // <-- Handler resize HUD Header
    procedure pbInfoBoxPaint(Sender: TObject);
    procedure pbInfoBoxResize(Sender: TObject);
    procedure tmrUIUpdateTimer(Sender: TObject);
  private
    FMainCanvas: TBGRABitmap;
    FHeaderCanvas: TBGRABitmap; // <-- Kanvas terpisah untuk Cyber-HUD Header
    FInfoCanvas: TBGRABitmap;   // <-- Kanvas terpisah untuk InfoBox
    FGameManager: TGameManager;
    procedure ClearTerminalBuffer;
    procedure ShowAboutDialog;
    procedure ShowEndScreen(AIsWin: Boolean);
  public
    procedure LogTerminal(const AMsg: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  { Inisialisasi kanvas BGRABitmap sesuai ukuran awal masing-masing PaintBox }
  FMainCanvas := TBGRABitmap.Create(pbCRT.Width, pbCRT.Height, BGRAPixelTransparent);
  FHeaderCanvas := TBGRABitmap.Create(pbHeader.Width, pbHeader.Height, BGRAPixelTransparent);
  FInfoCanvas := TBGRABitmap.Create(pbInfoBox.Width, pbInfoBox.Height, BGRAPixelTransparent);

  { Konfigurasi awal UI Terminal }
  memTerminal.Clear;
  LogTerminal('ECHO-OS v1.99 - Terminal Ready.');
  LogTerminal('Type "help" for a list of commands.');

  { Sembunyikan layar overlay Game Over/Win dan peringatan ICE saat awal mulai }
  pnlOverlay.Visible := False;
  lblICEWarning.Visible := False;

  { Inisialisasi Orchestrator GameManager }
  FGameManager := TGameManager.Create(
    ChartOscilloscope,
    LineSeries1,
    LineSeries2,
    @LogTerminal,
    @ClearTerminalBuffer,
    @ShowAboutDialog
  );
  FGameManager.InitializeGame(Self.Handle);

  { Mulai timer siklus frame UI (60 FPS -> Interval 16ms) }
  tmrUIUpdate.Interval := 16;
  tmrUIUpdate.Enabled := True;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  tmrUIUpdate.Enabled := False;
  if Assigned(FGameManager) then
    FreeAndNil(FGameManager);
  if Assigned(FMainCanvas) then
    FreeAndNil(FMainCanvas);
  if Assigned(FHeaderCanvas) then
    FreeAndNil(FHeaderCanvas);
  if Assigned(FInfoCanvas) then
    FreeAndNil(FInfoCanvas);
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  edtCommand.SetFocus;
end;

procedure TMainForm.mnAboutClick(Sender: TObject);
var
  FA: TFormAbout;
begin
  if Assigned(FGameManager) then
    FGameManager.SetPaused(True);
  tmrUIUpdate.Enabled := False;

  FA := nil;
  try
    FA := TFormAbout.Create(Self);
    FA.ShowModal;
  finally
    FA.Free;
    if Assigned(FGameManager) then
      FGameManager.SetPaused(False);
    tmrUIUpdate.Enabled := True;
  end;
end;

procedure TMainForm.edtCommandKeyPress(Sender: TObject; var Key: char);
var
  CmdStr: string;
begin
  if Key = #13 then
  begin
    Key := #0;
    CmdStr := Trim(edtCommand.Text);
    if CmdStr <> '' then
    begin
      LogTerminal('root@echo-os:~# ' + CmdStr);
      if Assigned(FGameManager) then
        FGameManager.ProcessCommand(CmdStr);
      edtCommand.Clear;
    end;
  end;
end;

procedure TMainForm.pbCRTResize(Sender: TObject);
begin
  if Assigned(FMainCanvas) and (pbCRT.Width > 0) and (pbCRT.Height > 0) then
    FMainCanvas.SetSize(pbCRT.Width, pbCRT.Height);
end;

procedure TMainForm.pbHeaderResize(Sender: TObject);
begin
  if Assigned(FHeaderCanvas) and (pbHeader.Width > 0) and (pbHeader.Height > 0) then
    FHeaderCanvas.SetSize(pbHeader.Width, pbHeader.Height);
end;

procedure TMainForm.pbInfoBoxResize(Sender: TObject);
begin
  if Assigned(FInfoCanvas) and (pbInfoBox.Width > 0) and (pbInfoBox.Height > 0) then
  begin
    FInfoCanvas.SetSize(pbInfoBox.Width, pbInfoBox.Height);
    if Assigned(FGameManager) and Assigned(FGameManager.BGRAEffects) then
      FGameManager.BGRAEffects.InvalidateBlurCache;
  end;
end;

procedure TMainForm.pbCRTPaint(Sender: TObject);
begin
  if Assigned(FMainCanvas) and Assigned(FGameManager) then
  begin
    if (FMainCanvas.Width <> pbCRT.Width) or (FMainCanvas.Height <> pbCRT.Height) then
      FMainCanvas.SetSize(pbCRT.Width, pbCRT.Height);

    FGameManager.RenderCRT(FMainCanvas);
    FMainCanvas.Draw(pbCRT.Canvas, 0, 0, True);
  end;
end;

procedure TMainForm.pbHeaderPaint(Sender: TObject);
begin
  if Assigned(FHeaderCanvas) and Assigned(FGameManager) then
  begin
    if (FHeaderCanvas.Width <> pbHeader.Width) or (FHeaderCanvas.Height <> pbHeader.Height) then
      FHeaderCanvas.SetSize(pbHeader.Width, pbHeader.Height);

    FGameManager.RenderHeader(FHeaderCanvas);
    FHeaderCanvas.Draw(pbHeader.Canvas, 0, 0, True);
  end;
end;

procedure TMainForm.pbInfoBoxPaint(Sender: TObject);
begin
  if Assigned(FInfoCanvas) and Assigned(FGameManager) then
  begin
    if (FInfoCanvas.Width <> pbInfoBox.Width) or (FInfoCanvas.Height <> pbInfoBox.Height) then
      FInfoCanvas.SetSize(pbInfoBox.Width, pbInfoBox.Height);

    { Kosongkan latar belakang kanvas informasi }
    FInfoCanvas.Fill(BGRA(0, 0, 0, 255));

    { Minta GameManager menggambar UI tambahan (Glass Popup) ke kanvas ini }
    FGameManager.RenderAuxiliaryUI(FInfoCanvas);

    FInfoCanvas.Draw(pbInfoBox.Canvas, 0, 0, True);
  end;
end;

procedure TMainForm.tmrUIUpdateTimer(Sender: TObject);
begin
  if Assigned(FGameManager) and (not FGameManager.IsPaused) then
  begin
    FGameManager.UpdateTick;

    { UI Peringatan Serangan Balik (Active ICE) }
    if FGameManager.IsICEAttackActive then
    begin
      lblICEWarning.Visible := True;
      lblICEWarning.Caption := Format('[!] INCOMING ATTACK DETECTED! TIME REMAINING: %.1fs [!]',
                                      [FGameManager.ICEAttackTimeLeft / 1000.0]);

      { Efek teks berkedip }
      if (GetTickCount64 mod 500) > 250 then
        lblICEWarning.Font.Color := clWhite
      else
        lblICEWarning.Font.Color := clYellow;
    end
    else
    begin
      lblICEWarning.Visible := False;
    end;

    { Cek Kondisi Menang atau Kalah secara konstan }
    if FGameManager.IsGameOver and not pnlOverlay.Visible then
      ShowEndScreen(False)
    else if FGameManager.IsGameWon and not pnlOverlay.Visible then
      ShowEndScreen(True);
  end;

  pbHeader.Invalidate; // <-- Refresh Cyber-HUD Header setiap frame
  pbCRT.Invalidate;
  pbInfoBox.Invalidate;
end;

procedure TMainForm.ClearTerminalBuffer;
begin
  memTerminal.Clear;
end;

procedure TMainForm.ShowAboutDialog;
var
  FA: TFormAbout;
begin
  if Assigned(FGameManager) then
    FGameManager.SetPaused(True);
  tmrUIUpdate.Enabled := False;

  FA := nil;
  try
    FA := TFormAbout.Create(Self);
    FA.ShowModal;
  finally
    FA.Free;
    if Assigned(FGameManager) then
      FGameManager.SetPaused(False);
    tmrUIUpdate.Enabled := True;
  end;
end;

procedure TMainForm.ShowEndScreen(AIsWin: Boolean);
begin
  { Mengunci input pemain }
  edtCommand.Enabled := False;

  { Menampilkan Layar Penuh (Overlay) }
  pnlOverlay.Visible := True;
  pnlOverlay.BringToFront;

  if AIsWin then
  begin
    lblOverlayTitle.Font.Color := clLime;
    lblOverlayTitle.Caption := 'MISSION ACCOMPLISHED';

    lblOverlayDesc.Font.Color := clLime;
    lblOverlayDesc.Caption := 'THE SIGNAL CARTEL HAS BEEN EXPOSED. SYSTEM DISCONNECTING...';
  end
  else
  begin
    lblOverlayTitle.Font.Color := clRed;
    lblOverlayTitle.Caption := 'CRITICAL FAILURE';

    lblOverlayDesc.Font.Color := clRed;
    lblOverlayDesc.Caption := 'PHYSICAL LOCATION TRACED. SYSTEM PURGED.';
  end;
end;

procedure TMainForm.LogTerminal(const AMsg: string);
begin
  memTerminal.Lines.Add(AMsg);
  memTerminal.SelStart := Length(memTerminal.Text);
end;

end.
