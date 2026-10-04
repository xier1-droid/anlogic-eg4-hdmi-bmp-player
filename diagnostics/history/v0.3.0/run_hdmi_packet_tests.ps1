$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $PSScriptRoot '../../tool_paths.ps1')
$simDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))) 'modelsim_hdmi_r2_s5'
$lib = (Join-Path $simDir 'hdmi_work').Replace('\','/')
New-Item -ItemType Directory -Path $simDir -Force | Out-Null
Push-Location $repoRoot
try {
    if (-not (Test-Path "$lib/_info")) {
        & "$simTools/vlib.exe" $lib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $rtl = @(Get-ChildItem -LiteralPath user_source/hdl_source/hdmi_audio -Filter '*.v' | ForEach-Object { $_.FullName })
    & "$simTools/vlog.exe" -work $lib -sv -l "$simDir/hdmi_compile.log" @rtl user_source/hdl_source/audio/pcm_test_tone.v diagnostics/history/v0.3.0/tb_hdmi_packets.sv diagnostics/history/v0.3.0/tb_hdmi_primitives.sv
    if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    Push-Location $simDir
    try {
        & "$simTools/vsim.exe" -c -quiet -lib $lib tb_hdmi_primitives -l "$simDir/primitives.log" -do 'run -all; quit -f'
        $log = Get-Content -LiteralPath "$simDir/primitives.log" -Raw
        if ($LASTEXITCODE -ne 0 -or $log -match '\*\* (Fatal|Error):' -or
            $log -notmatch 'PASS primitive' -or $log -notmatch 'Errors: 0, Warnings: 0') {
            throw 'HDMI primitive simulation failed'
        }
        foreach ($pattern in @(0,1)) {
            $logPath = "$simDir/hdmi_pattern_$pattern.log"
            & "$simTools/vsim.exe" -c -quiet -voptargs=+acc -lib $lib tb_hdmi_packets "-gPATTERN=$pattern" -l $logPath -do 'run -all; quit -f'
            $log = Get-Content -LiteralPath $logPath -Raw
            if ($LASTEXITCODE -ne 0 -or $log -match '\*\* (Fatal|Error):' -or
                $log -notmatch 'PASS HDMI symbols' -or $log -notmatch 'Errors: 0, Warnings: 0') {
                throw "HDMI simulation failed: $pattern"
            }
        }
        & $pythonExe -X utf8 "$repoRoot/diagnostics/history/v0.3.0/check_hdmi_packets.py" primitives.txt tone_packets.txt pattern_packets.txt
        if ($LASTEXITCODE -ne 0) { throw 'Independent packet reference failed' }
    } finally { Pop-Location }
} finally { Pop-Location }
