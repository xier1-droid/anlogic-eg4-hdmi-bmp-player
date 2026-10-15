param([string]$Prefix='m3r')
# Regressions affected by M3: the M1 set (load chain, four bank, thumbnails,
# PCM with tb_pcm_preview_rescan, production top, preview and full system)
# plus video_delay at the default SYNC_EXTRA=0 against the pre-BRAM
# reference. lut_reduction/run_batch2.ps1 is not used: its pcm_media_tone
# half reports 13 reset-time mismatches on unmodified v0.16.0 sources too.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$summary=Join-Path $root "diagnostics/output/${Prefix}_summary.log"
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/run_m1_regression.ps1" -Prefix $Prefix
$out=Join-Path $root "diagnostics/output/${Prefix}_video_delay1"
if(Test-Path $out){throw 'Choose a new Prefix'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64';$lib="$out/work".Replace('\','/')
$start=Get-Date
& "$sim/vlib.exe" $lib *> "$out/library.log"
& "$sim/vlog.exe" -sv -work $lib "$root/user_source/hdl_source/SD/video_delay.v" "$root/diagnostics/lut_reduction/video_delay_ref.v" "$PSScriptRoot/tb_m3_video_delay_equiv.sv" *> "$out/compile.log"
$ok=!$LASTEXITCODE
if($ok){
 & "$sim/vsim.exe" -c -quiet -lib $lib tb_m3_video_delay_equiv -l "$out/tb_m3_video_delay_equiv.log" -do 'run -all; quit -f' *> "$out/console.log"
 $log=Get-Content "$out/tb_m3_video_delay_equiv.log" -Raw
 $ok=!$LASTEXITCODE -and $log -match 'PASS video_delay equivalence' -and $log -notmatch '\*\* (Fatal|Error|Warning)'
}
$line="{0} video_delay ({1:n0}s)" -f $(if($ok){'PASS'}else{'FAIL'}),((Get-Date)-$start).TotalSeconds
Add-Content $summary $line;Write-Output $line
