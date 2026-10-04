param([string]$Prefix = 'stability_s0')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$output = Join-Path $PSScriptRoot 'output/stability_s0'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$tests = @(
    @{ Name='control'; Script='run_control_tests.ps1'; Args=@('-Prefix', $Prefix) },
    @{ Name='mode'; Script='run_mode_tests.ps1'; Args=@() },
    @{ Name='buffer'; Script='run_buffer_handoff.ps1'; Args=@() },
    @{ Name='pcm'; Script='run_audio_tests.ps1'; Args=@() },
    @{ Name='packets'; Script='run_hdmi_packet_tests.ps1'; Args=@() },
    @{ Name='video'; Script='run_video_alignment.ps1'; Args=@() },
    @{ Name='media_phy'; Script='run_hdmi_s6_tests.ps1'; Args=@('-Stage', 's9') },
    @{ Name='reset'; Script='run_s9_reset_tests.ps1'; Args=@() }
)
Push-Location $repoRoot
try {
    foreach ($test in $tests) {
        $log = Join-Path $output ($test.Name + '.log')
        $script = Join-Path $PSScriptRoot ('history/v0.3.0/' + $test.Script)
        $arguments = $test.Args
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script @arguments *> $log
        if ($LASTEXITCODE -ne 0) { throw "Baseline failed: $($test.Name); see $log" }
        Write-Output "PASS S0 $($test.Name): $log"
    }
} finally { Pop-Location }
