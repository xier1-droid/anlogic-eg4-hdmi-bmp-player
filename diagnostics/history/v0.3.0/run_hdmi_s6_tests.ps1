param([ValidateSet('s6','s7','s8','s9')][string]$Stage = 's6')
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $PSScriptRoot '../../tool_paths.ps1')
$simDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))) "modelsim_hdmi_r2_$Stage"
$lib = (Join-Path $simDir "${Stage}_work").Replace('\','/')
New-Item -ItemType Directory -Path $simDir -Force | Out-Null
Push-Location $repoRoot
try {
    if (-not (Test-Path "$lib/_info")) {
        & "$simTools/vlib.exe" $lib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $rtl = @(Get-ChildItem user_source/hdl_source/hdmi_audio -Filter '*.v' | ForEach-Object {$_.FullName})
    & "$simTools/vlog.exe" -sv -work $lib '+incdir+user_source/hdl_source/SD' -l "$simDir/compile.log" @rtl `
        user_source/hdl_source/reset_sync.v user_source/hdl_source/audio/media_commit_cdc.v user_source/hdl_source/audio/pcm_media_tone.v user_source/hdl_source/audio/pcm_test_tone.v user_source/hdl_source/SD/color_bar.v `
        user_source/hdl_source/SD/video_timing_data.v user_source/hdl_source/SD/video_delay.v `
        user_source/hdl_source/hdmi_phy_warpper.v user_source/hdl_source/lane_lvds_10_1.v `
        "$vendor/eg_logic_io.v" "$vendor/eg_phy_glbl.v" diagnostics/history/v0.3.0/tb_hdmi_packets.sv diagnostics/history/v0.3.0/tb_hdmi_s6_phy.sv diagnostics/history/v0.3.0/tb_pcm_media_tone.sv diagnostics/history/v0.3.0/tb_media_commit_cdc.sv
    if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    Push-Location $simDir
    try {
        $tests = if ($Stage -in @('s8','s9')) { @('tb_hdmi_packets','tb_hdmi_s6_phy','tb_pcm_media_tone','tb_media_commit_cdc') } else { @('tb_hdmi_packets','tb_hdmi_s6_phy') }
        foreach ($test in $tests) {
            $simOptions = @()
            $silence = if ($Stage -eq 's6') { 1 } else { 0 }
            if ($test -in @('tb_hdmi_packets','tb_hdmi_s6_phy')) { $simOptions += "-gSILENCE=$silence" }
            if ($Stage -in @('s8','s9') -and $test -in @('tb_hdmi_packets','tb_hdmi_s6_phy')) { $simOptions += "-gMEDIA=1" }
            if ($Stage -eq 's9' -and $test -eq 'tb_hdmi_s6_phy') { $simOptions += '-gLOCAL_RESET=1' }
            & "$simTools/vsim.exe" -c -quiet -voptargs=+acc -lib $lib $test glbl @simOptions -l "$simDir/$test.log" -do 'run -all; quit -f'
            $log = Get-Content "$simDir/$test.log" -Raw
            if ($LASTEXITCODE -ne 0 -or $log -match '\*\* (Fatal|Error):' -or $log -notmatch 'PASS ' -or $log -notmatch 'Errors: 0, Warnings: 0') {
                throw "S6 simulation failed: $test"
            }
        }
        & $pythonExe -X utf8 "$repoRoot/diagnostics/history/v0.3.0/check_hdmi_packets.py" tone_packets.txt
        if ($LASTEXITCODE -ne 0) { throw 'S6 packet reference failed' }
        if ($Stage -eq 's6') {
            $nonzero = Get-Content tone_packets.txt | Where-Object { $_ -like 'A *' -and $_ -ne 'A 0000 0000' }
            if ($nonzero) { throw 'S6 PCM is not silent' }
            Write-Output 'PASS S6 all accepted and decoded PCM samples are zero'
        } elseif ($Stage -eq 's7') {
            & $pythonExe -X utf8 "$repoRoot/diagnostics/history/v0.3.0/check_s7_tone.py" tone_packets.txt
            if ($LASTEXITCODE -ne 0) { throw 'S7 independent tone reference failed' }
        }
    } finally { Pop-Location }
} finally { Pop-Location }
