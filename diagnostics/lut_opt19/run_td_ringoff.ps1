param([string]$BuildName='lut19_ringoff_a_s3',[ValidateRange(1,11)][int]$PlacementStrategy=3)
# Isolated TD build with AUDIO_VIS_ENABLE=0 patched into the copy only; production sources stay unchanged.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$BuildName"
if(Test-Path $out){throw 'Choose a new BuildName'}
New-Item -ItemType Directory -Path "$out/TD_project","$out/diagnostics" -Force | Out-Null
Copy-Item "$root/user_source" "$out/user_source" -Recurse
Copy-Item "$root/TD_project/demo.al" "$out/TD_project/demo.al"
Copy-Item "$root/diagnostics/run_td_build.ps1" "$out/diagnostics/run_td_build.ps1"
$top="$out/user_source/hdl_source/top_tf_hdmi_audio.v"
$text=[IO.File]::ReadAllText($top)
$old='parameter integer AUDIO_VIS_ENABLE = 1;'
if(-not $text.Contains($old)){throw 'AUDIO_VIS_ENABLE line not found'}
[IO.File]::WriteAllText($top,$text.Replace($old,'parameter integer AUDIO_VIS_ENABLE = 0;'),[Text.UTF8Encoding]::new($false))
& powershell -NoProfile -ExecutionPolicy Bypass -File "$out/diagnostics/run_td_build.ps1" -BuildName $BuildName -HighFanoutOptimization -TimingOptimization high -PostPlaceOptimization high -PlacementStrategy $PlacementStrategy
if($LASTEXITCODE){throw 'TD build failed'}
$report=Get-Content "$out/TD_project/demo_Runs/phy_1/final_timing.rpt" -Raw
$setup=[regex]::Match($report,'SWNS:\s*([-\d.]+)ns');$hold=[regex]::Match($report,'HWNS:\s*([-\d.]+)ns')
if(!$setup.Success -or !$hold.Success){throw 'Missing timing summary'}
Write-Output "routed timing: Setup $($setup.Groups[1].Value) ns, Hold $($hold.Groups[1].Value) ns"
