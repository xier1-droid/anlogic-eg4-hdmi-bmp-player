param([string]$Prefix='m3r')
# Regressions affected by M3: the M1 set (load chain, four bank, thumbnails,
# PCM with tb_pcm_preview_rescan, production top, preview and full system)
# plus the video_delay equivalence test, which pins the SYNC_EXTRA=0 default
# to the pre-optimisation reference.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$summary=Join-Path $root "diagnostics/output/${Prefix}_summary.log"
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/run_m1_regression.ps1" -Prefix $Prefix
$log=Join-Path $root "diagnostics/output/${Prefix}_video_delay.console.log"
$start=Get-Date
$ErrorActionPreference='Continue'
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root/diagnostics/lut_reduction/run_batch2.ps1" -RunName "${Prefix}_video_delay1" *> $log
$ErrorActionPreference='Stop'
$line="{0} video_delay ({1:n0}s)" -f $(if($LASTEXITCODE){'FAIL'}else{'PASS'}),((Get-Date)-$start).TotalSeconds
Add-Content $summary $line;Write-Output $line
