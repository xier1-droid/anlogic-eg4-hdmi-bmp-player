param([string]$Prefix='m1r')
# Regressions affected by the M1 32-bit load chain, run in sequence with the
# same scripts that produced the v0.16.0 S2 evidence (s2f_*).
# bmp_decoder/run_sim.ps1 is excluded: it fails identically on v0.16.0 RTL
# (matrix640 normal depth=24 err=3, plus unconnected-port warnings).
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(!(Get-Command python -ErrorAction SilentlyContinue)){$env:PATH="$env:LOCALAPPDATA\Programs\Python\Python313;$env:PATH"}
$summary=Join-Path $root "diagnostics/output/${Prefix}_summary.log"
$runs=@(
 @('scaler','media_adjust/run_scaler.ps1','-RunName',"${Prefix}_scaler1"),
 @('reader0','fat32/run_reader.ps1','-RunName',"${Prefix}_reader0",'-ByteGap','0'),
 @('reader2','fat32/run_reader.ps1','-RunName',"${Prefix}_reader2",'-ByteGap','2'),
 @('reader_scale','fat32/run_reader.ps1','-RunName',"${Prefix}_reader_scale",'-Cases','0','-ByteGap','0','-ScaleTest','1'),
 @('format_dimensions','fat32/run_reader.ps1','-RunName',"${Prefix}_reader_modes",'-Cases','0','-TestMode','1','-ByteGap','0'),
 @('format_bitcount','fat32/run_reader.ps1','-RunName',"${Prefix}_reader_modes",'-Cases','0','-TestMode','2','-ByteGap','0'),
 @('format_length','fat32/run_reader.ps1','-RunName',"${Prefix}_reader_modes",'-Cases','0','-TestMode','3','-ByteGap','0'),
 @('ack_timeout','fat32/run_reader.ps1','-RunName',"${Prefix}_reader_modes",'-Cases','0','-TestMode','4','-ByteGap','0'),
 @('last_byte_end','fat32/run_reader.ps1','-RunName',"${Prefix}_reader_modes",'-Cases','0','-TestMode','5','-ByteGap','0'),
 @('regression','four_bank/run_regression.ps1','-RunName',"${Prefix}_regression1"),
 @('paths','four_bank/run_sim.ps1','-RunName',"${Prefix}_paths1"),
 @('loader','image_scaling/run_thumbnail_loader.ps1','-RunName',"${Prefix}_loader1"),
 @('memory','image_scaling/run_memory.ps1','-RunName',"${Prefix}_memory1"),
 @('production','pcm_audio/run_production.ps1','-RunName',"${Prefix}_production1",'-Tests','TESTLIST'),
 @('top','media_adjust/run_top.ps1','-RunName',"${Prefix}_top1"),
 @('preview','image_scaling/run_preview.ps1','-RunName',"${Prefix}_preview1",'-Mixed','0','-Audio','-Failures'),
 @('system','image_scaling/run_system.ps1','-RunName',"${Prefix}_system1")
)
foreach($run in $runs){
 $script=Join-Path $root "diagnostics/$($run[1])"
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$script)
 if($run.Count -gt 2){$arguments+=$run[2..($run.Count-1)]}
 # -File cannot pass a string array; the PCM pair must compile together.
 if($run -contains 'TESTLIST'){$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-Command',"& '$script' -RunName $($run[3]) -Tests tb_pcm_production,tb_pcm_preview_rescan; exit `$LASTEXITCODE")}
 $log=Join-Path $root "diagnostics/output/${Prefix}_$($run[0]).console.log"
 $start=Get-Date
 # Record a failing child and continue with the remaining runs.
 $ErrorActionPreference='Continue'
 & powershell @arguments *> $log
 $ErrorActionPreference='Stop'
 $code=$LASTEXITCODE
 $line="{0} {1} ({2:n0}s)" -f $(if($code){'FAIL'}else{'PASS'}),$run[0],((Get-Date)-$start).TotalSeconds
 Add-Content $summary $line;Write-Output $line
}
