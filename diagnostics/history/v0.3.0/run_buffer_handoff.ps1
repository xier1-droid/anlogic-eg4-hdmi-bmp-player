param([switch]$Baseline)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tool_paths.ps1')
$simDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))) 'modelsim_check'
$simLib = (Join-Path $simDir 'handoff_work').Replace('\', '/')
if ($Baseline) { $simLib = (Join-Path $simDir 'handoff_baseline_work').Replace('\', '/') }
Push-Location ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')))
try {
    if (-not (Test-Path -LiteralPath "$simLib/_info")) {
        New-Item -ItemType Directory -Path $simDir -Force | Out-Null
        & "$simTools/vlib.exe" $simLib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    # Separate library: this bench supplies behavioral BMP/SD and vendor FIFO models.
    $rtl = @('media_display_control','media_player_control','media_policy',
        'key_gesture_control', 'key_press_debounce', 'mode_key_control','dual_key_event_router','sd_card_bmp',
        'frame_fifo_read','frame_fifo_write','frame_read_write') |
        ForEach-Object { "user_source/hdl_source/SD/$_.v" }
    if ($Baseline) {
        # Only interface adaptation: old application ignores the new ack and
        # drives request=0. Its buffer reuse behavior is unchanged.
        $oldSource = (& git show 'v0.1.7:user_source/hdl_source/SD/sd_card_bmp.v') -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read v0.1.7 source' }
        $oldSource = $oldSource.Replace('input                       write_finish_toggle,',
            "input                       write_finish_toggle,`n    input display_commit_ack,`n    output [1:0] committed_image,`n    output committed_valid,`n    input committed_ready,`n    output display_commit_request,")
        $oldSource = $oldSource.Replace('key_next', 'key1').Replace('key_auto', 'key2')
        $oldSource = $oldSource.Replace('input                       key2,', "input                       key2,`n    input key4,`n    input [1:0] mode,")
        $oldSource = $oldSource.Replace('assign ctrl_request_accept', "assign display_commit_request = 1'b0;`nassign ctrl_request_accept")
        $oldSource = $oldSource.Replace('.key1(key1)', '.key_next(key1)').Replace('.key2(key2)', '.key_auto(key2)')
        $oldPath = Join-Path $simDir 'stage4_baseline_sd_card_bmp.v'
        [IO.File]::WriteAllText($oldPath, $oldSource, [Text.UTF8Encoding]::new($false))
        $rtl = $rtl | ForEach-Object { if ($_ -like '*/sd_card_bmp.v') { $oldPath } else { $_ } }
    }
    & "$simTools/vlog.exe" -work $simLib -sv @rtl diagnostics/history/v0.3.0/tb_buffer_handoff.sv
    if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    foreach ($scenario in @(@(17,2), @(19,16), @(23,64))) {
        $pixelHalf = $scenario[0]
        $sourceGap = $scenario[1]
        $mode = if ($Baseline) { 'baseline' } else { 'handoff' }
        $testLog = Join-Path $simDir "stage4_${mode}_${pixelHalf}_${sourceGap}.log"
        & "$simTools/vsim.exe" -c -quiet -voptargs=+acc -lib $simLib tb_buffer_handoff "-gPIX_HALF=$pixelHalf" "-gSOURCE_GAP=$sourceGap" -l $testLog -do 'run -all; quit -f'
        $result = Get-Content -LiteralPath $testLog -Raw
        # The slowest baseline scenario already passes; retain it as a control.
        if ($Baseline -and $sourceGap -lt 64) {
            if ($result -notmatch 'buffer reused before reader released it' -or
                $result -notmatch 'old_buffer_writes=[1-9]') {
                throw "Baseline did not reproduce expected ownership failure: $testLog"
            }
        } elseif ($LASTEXITCODE -ne 0 -or $result -match '\*\* (Fatal|Error):' -or
            $result -notmatch 'PASS asynchronous buffer ownership' -or
            $result -notmatch 'Errors: 0, Warnings: 0') { throw "Handoff test failed: $testLog" }
    }
} finally { Pop-Location }
