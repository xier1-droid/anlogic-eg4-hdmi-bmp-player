$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $PSScriptRoot '../../tool_paths.ps1')
$simDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output'))) 'modelsim_video_r2_s4'
$lib = (Join-Path $simDir 'video_work').Replace('\','/')
New-Item -ItemType Directory -Path $simDir -Force | Out-Null
Push-Location $repoRoot
try {
    if (-not (Test-Path "$lib/_info")) {
        & "$simTools/vlib.exe" $lib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $baseline = @()
    foreach ($module in @('color_bar','video_timing_data','video_delay')) {
        $source = (& git show "v0.3.0-s1-board.1:user_source/hdl_source/SD/$module.v") -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "Cannot read S1 $module" }
        $source = $source -replace '\bcolor_bar\b','s1_color_bar'
        $source = $source -replace '\bvideo_timing_data\b','s1_video_timing_data'
        $source = $source -replace '\bvideo_delay\b','s1_video_delay'
        $path = Join-Path $simDir "s1_$module.v"
        [IO.File]::WriteAllText($path,$source,[Text.UTF8Encoding]::new($false))
        $baseline += $path
    }
    $rtl = @('color_bar','video_timing_data','video_delay') |
        ForEach-Object { "user_source/hdl_source/SD/$_.v" }
    & "$simTools/vlog.exe" -work $lib -sv '+incdir+user_source/hdl_source/SD' -l "$simDir/video_compile.log" @rtl @baseline diagnostics/history/v0.3.0/tb_video_alignment.sv
    if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    & "$simTools/vsim.exe" -c -quiet -voptargs=+acc -lib $lib tb_video_alignment -l "$simDir/video_test.log" -do 'run -all; quit -f'
    $log = Get-Content -LiteralPath "$simDir/video_test.log" -Raw
    if ($LASTEXITCODE -ne 0 -or $log -match '\*\* (Fatal|Error):' -or
        $log -notmatch 'PASS reset/restart' -or $log -notmatch 'Errors: 0, Warnings: 0') {
        throw 'video alignment simulation failed'
    }
} finally { Pop-Location }
