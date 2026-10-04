param([string]$Prefix = 'stage4')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tool_paths.ps1')
$simDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))) 'modelsim_check'
$simLib = (Join-Path $simDir 'work').Replace('\', '/')
$repoDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
Push-Location $repoDir
try {
    if (-not (Test-Path -LiteralPath "$simLib/_info")) {
        New-Item -ItemType Directory -Path $simDir -Force | Out-Null
        & "$simTools/vlib.exe" $simLib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $rtl = @('media_display_control', 'media_player_control', 'media_policy',
        'dual_key_event_router', 'key_gesture_control', 'key_press_debounce', 'mode_key_control', 'sd_card_bmp', 'bmp_read',
        'sd_card_top', 'sd_card_sec_read_write', 'sd_card_cmd', 'spi_master') |
        ForEach-Object { "user_source/hdl_source/SD/$_.v" }
    $rtl += @('user_source/hdl_source/audio/media_commit_cdc.v','user_source/hdl_source/audio/pcm_media_tone.v')
    $benches = @('diagnostics/history/v0.3.0/tb_picture_requests.sv', 'diagnostics/history/v0.3.0/tb_mode_key_control.sv',
        'diagnostics/history/v0.3.0/tb_dual_key_event_router.sv', 'diagnostics/history/v0.3.0/tb_media_player_control.sv',
        'diagnostics/history/v0.3.0/tb_media_display_control.sv', 'diagnostics/history/v0.3.0/tb_key_gesture_control.sv')
    & "$simTools/vlog.exe" -work $simLib -sv @rtl @benches
    if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    $tests = @('tb_picture_requests', 'tb_mode_key_control',
        'tb_dual_key_event_router', 'tb_media_player_control',
        'tb_media_display_control', 'tb_key_gesture_control')
    foreach ($test in $tests) {
        $testLog = Join-Path $simDir "${Prefix}_${test}.log"
        & "$simTools/vsim.exe" -c -quiet -voptargs=+acc -lib $simLib $test -l $testLog -do 'run -all; quit -f'
        $result = Get-Content -LiteralPath $testLog -Raw
        if ($LASTEXITCODE -ne 0 -or $result -match '\*\* (Fatal|Error):' -or
            $result -notmatch 'PASS ' -or $result -notmatch 'Errors: 0, Warnings: 0') {
            throw "Simulation failed: $test ($testLog)"
        }
    }
} finally {
    Pop-Location
}
