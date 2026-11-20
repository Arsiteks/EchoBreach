unit uChartRenderer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, TAGraph, TASeries, TAChartUtils, uFFTProcessor;

type
  { TChartRenderer - Mengelola optimasi dan rendering real-time TAChart (60 FPS)
    untuk memvisualisasikan gelombang osiloskop dan spektrum FFT tanpa membebani LCL }
  TChartRenderer = class
  private
    FChart: TChart;
    FPrimarySeries: TLineSeries;
    FSecondarySeries: TLineSeries;
    FSampleCapacity: Integer;
    procedure ConfigureChartAppearance;
  public
    constructor Create(AChart: TChart; APrimary, ASecondary: TLineSeries;
      ASampleCapacity: Integer = 128);
    destructor Destroy; override;

    { Memperbarui titik koordinat grafik secara batch (BeginUpdate/EndUpdate) }
    procedure RenderSpectrum(AProcessor: TFFTProcessor);

    { Mengubah skema warna garis osiloskop saat anomali sinyal atau kunci sadapan ditemukan }
    procedure SetAlertMode(AAnomalyDetected: Boolean);

    procedure ClearChart;
  end;

implementation

{ TChartRenderer }

constructor TChartRenderer.Create(AChart: TChart; APrimary, ASecondary: TLineSeries;
  ASampleCapacity: Integer);
begin
  inherited Create;
  FChart := AChart;
  FPrimarySeries := APrimary;
  FSecondarySeries := ASecondary;
  FSampleCapacity := ASampleCapacity;

  ConfigureChartAppearance;
end;

destructor TChartRenderer.Destroy;
begin
  inherited Destroy;
end;

procedure TChartRenderer.ConfigureChartAppearance;
begin
  if not Assigned(FChart) then Exit;

  { Nonaktifkan fitur interaktif bawaan TAChart untuk menghemat siklus CPU }
  FChart.AllowZoom := False;
  FChart.AllowPanning := False;
  FChart.AntiAliasingMode := camNone; // Diperbaiki: Menggunakan TChartAntialiasingMode (camNone)
  FChart.DoubleBuffered := True;

  { Kunci rentang sumbu Y (Amplitude) dan X (Frequency Bins) agar skala tidak melompat-lompat }
  FChart.LeftAxis.Range.Min := -1.2;
  FChart.LeftAxis.Range.Max := 1.2;
  FChart.LeftAxis.Range.UseMin := True;
  FChart.LeftAxis.Range.UseMax := True;

  FChart.BottomAxis.Range.Min := 0;
  FChart.BottomAxis.Range.Max := FSampleCapacity - 1;
  FChart.BottomAxis.Range.UseMin := True;
  FChart.BottomAxis.Range.UseMax := True;

  { Optimasi GDI/Windows: LinePen.Cosmetic := True mempercepat penggambaran garis 1px/2px }
  if Assigned(FPrimarySeries) then
  begin
    FPrimarySeries.LinePen.Cosmetic := True;
    FPrimarySeries.LinePen.Color := clLime;
    FPrimarySeries.LinePen.Width := 2;
  end;

  if Assigned(FSecondarySeries) then
  begin
    FSecondarySeries.LinePen.Cosmetic := True;
    FSecondarySeries.LinePen.Color := $000080FF; // Warna Oranye/Amber gelombang pembawa
    FSecondarySeries.LinePen.Width := 1;
  end;
end;

procedure TChartRenderer.RenderSpectrum(AProcessor: TFFTProcessor);
var
  i, Count: Integer;
  PrimaryData, SecondaryData: array of Single;
begin
  if not Assigned(FChart) or not Assigned(AProcessor) then Exit;

  PrimaryData := AProcessor.SmoothedData;
  SecondaryData := AProcessor.ModulatedWave;
  Count := Length(PrimaryData);
  if Count = 0 then Exit;

  { Gunakan BeginUpdate/EndUpdate pada ListSource untuk mencegah repaint berulang per-titik }
  FChart.DisableRedrawing;
  try
    if Assigned(FPrimarySeries) then
    begin
      FPrimarySeries.ListSource.BeginUpdate;
      try
        FPrimarySeries.Clear;
        for i := 0 to Count - 1 do
          FPrimarySeries.AddXY(i, PrimaryData[i]);
      finally
        FPrimarySeries.ListSource.EndUpdate;
      end;
    end;

    if Assigned(FSecondarySeries) and (Length(SecondaryData) = Count) then
    begin
      FSecondarySeries.ListSource.BeginUpdate;
      try
        FSecondarySeries.Clear;
        for i := 0 to Count - 1 do
          FSecondarySeries.AddXY(i, SecondaryData[i]);
      finally
        FSecondarySeries.ListSource.EndUpdate;
      end;
    end;

    { Sesuaikan indikator warna jika SNR melewati ambang batas anomali }
    SetAlertMode(AProcessor.LastAnalysis.AnomalyDetected);
  finally
    FChart.EnableRedrawing;
    FChart.Invalidate;
  end;
end;

procedure TChartRenderer.SetAlertMode(AAnomalyDetected: Boolean);
begin
  if not Assigned(FPrimarySeries) then Exit;

  if AAnomalyDetected then
  begin
    { Berubah menjadi kuning terang/sian saat sinyal kunci terdeteksi }
    if FPrimarySeries.LinePen.Color <> clYellow then
      FPrimarySeries.LinePen.Color := clYellow;
  end
  else
  begin
    if FPrimarySeries.LinePen.Color <> clLime then
      FPrimarySeries.LinePen.Color := clLime;
  end;
end;

procedure TChartRenderer.ClearChart;
begin
  if Assigned(FPrimarySeries) then FPrimarySeries.Clear;
  if Assigned(FSecondarySeries) then FSecondarySeries.Clear;
end;

end.
