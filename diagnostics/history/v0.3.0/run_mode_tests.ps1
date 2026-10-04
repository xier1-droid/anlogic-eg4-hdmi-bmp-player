$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tool_paths.ps1')
$simDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))) 'modelsim_check'
$simLib = (Join-Path $simDir 'mode_work').Replace('\', '/')
Push-Location ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')))
try {
    if (-not (Test-Path -LiteralPath "$simLib/_info")) {
        New-Item -ItemType Directory -Path $simDir -Force | Out-Null
        & "$simTools/vlib.exe" $simLib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $rtl = @('switch_mode_control', 'seg_decoder', 'seg_scan', 'seg7_panel') |
        ForEach-Object { "user_source/hdl_source/SD/$_.v" }
    & "$simTools/vlog.exe" -work $simLib -sv @rtl diagnostics/history/v0.3.0/tb_switch_mode_panel.sv
    if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    $testLog = Join-Path $simDir 'mode_stage1_panel.log'
    & "$simTools/vsim.exe" -c -quiet -lib $simLib tb_switch_mode_panel -l $testLog -do 'run -all; quit -f'
    $result = Get-Content -LiteralPath $testLog -Raw
    if ($LASTEXITCODE -ne 0 -or $result -match '\*\* (Fatal|Error):' -or
        $result -notmatch 'PASS ' -or $result -notmatch 'Errors: 0, Warnings: 0') {
        throw "Simulation failed: $testLog"
    }
} finally {
    Pop-Location
}
