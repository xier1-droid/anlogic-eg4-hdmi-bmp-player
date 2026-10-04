param([ValidateSet('pcm')][string]$Suite = 'pcm')
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $PSScriptRoot '../../tool_paths.ps1')
$simDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))) 'modelsim_audio_r2_s2'
$lib = (Join-Path $simDir "${Suite}_work").Replace('\','/')
New-Item -ItemType Directory -Path $simDir -Force | Out-Null
Push-Location $repoRoot
try {
    if (-not (Test-Path "$lib/_info")) {
        & "$simTools/vlib.exe" $lib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $module = 'pcm_test_tone'
    $rtl = "user_source/hdl_source/audio/$module.v"
    & "$simTools/vlog.exe" -work $lib -sv -l "$simDir/${Suite}_compile.log" $rtl "diagnostics/history/v0.3.0/tb_$module.sv"
    if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    & "$simTools/vsim.exe" -c -quiet -voptargs=+acc -lib $lib "tb_$module" -l "$simDir/${Suite}_test.log" -do 'run -all; quit -f'
    $log = Get-Content -LiteralPath "$simDir/${Suite}_test.log" -Raw
    if ($LASTEXITCODE -ne 0 -or $log -match '\*\* (Fatal|Error):' -or $log -notmatch 'PASS ' -or $log -notmatch 'Errors: 0, Warnings: 0') {
        throw "$Suite simulation failed"
    }
} finally { Pop-Location }
