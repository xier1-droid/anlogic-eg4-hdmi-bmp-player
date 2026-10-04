$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $PSScriptRoot '../../tool_paths.ps1')
$simDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))) 'modelsim_reset_r2_s9'
$lib = (Join-Path $simDir 'reset_work').Replace('\','/')
New-Item -ItemType Directory -Path $simDir -Force | Out-Null
Push-Location $repoRoot
try {
    if (-not (Test-Path "$lib/_info")) {
        & "$simTools/vlib.exe" $lib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    [xml]$project = (Get-Content TD_project/demo.al -Raw).Replace('UsedInP&R','UsedInP&amp;R')
    $modeled = @('sys_pll.v','video_pll.v','sdram.v','afifo_16_32_256.v','afifo_32_16_256.v',
        'sdr_as_ram.enc.v','sdr_init_ref.enc.v','sdr_wrrd.enc.v')
    $rtl = @($project.SelectNodes('/Project/Source_Files/Verilog/File') | ForEach-Object {
        $path = $_.GetAttribute('Path')
        if ((Split-Path $path -Leaf) -notin $modeled) { Join-Path "$repoRoot/TD_project" $path }
    })
    & "$simTools/vlog.exe" -sv -work $lib '+incdir+user_source/hdl_source/SD' -l "$simDir/compile.log" @rtl `
        "$vendor/eg_logic_io.v" "$vendor/eg_phy_glbl.v" diagnostics/history/v0.3.0/tb_s9_reset.sv
    if ($LASTEXITCODE -ne 0) { throw 'reset top compile failed' }
    & "$simTools/vsim.exe" -c -quiet -voptargs=+acc -lib $lib tb_s9_reset glbl -l "$simDir/reset.log" -do 'run -all; quit -f'
    $log = Get-Content "$simDir/reset.log" -Raw
    if ($LASTEXITCODE -ne 0 -or $log -match '\*\* (Fatal|Error):' -or $log -notmatch 'PASS S9' -or $log -notmatch 'Errors: 0, Warnings: 0') {
        throw 'reset top simulation failed'
    }
} finally { Pop-Location }
