$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$release = Join-Path $repoRoot 'releases/v0.4.0-stability-s0-local.1'
$evidence = Join-Path $release 'evidence'
if (Test-Path (Join-Path $release 'SHA256.json')) { throw 'S0 candidate already frozen; create a new revision rather than overwrite it.' }
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
foreach ($file in @('demo.bit','demo_phy.ts','demo_phy.area','demo_pr.timing','demo_exception.timing')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "TD_project/demo_Runs/phy_1/$file") -Destination $release
}
foreach ($run in @('syn_1','phy_1')) {
    foreach ($file in @('demo.prj','settings.cfg','build_stability_s0_local1.log')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "TD_project/demo_Runs/$run/$file") -Destination (Join-Path $evidence "${run}_$file")
    }
}
foreach ($file in @('TD_project/demo.al','user_source/constraints_source/pin.adc','user_source/constraints_source/timing.sdc')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination $release
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'output/stability_s0') -Destination $evidence -Recurse
foreach ($directory in @('modelsim_check','modelsim_audio_r2_s2','modelsim_hdmi_r2_s5','modelsim_video_r2_s4','modelsim_hdmi_r2_s9','modelsim_reset_r2_s9')) {
    $destination = Join-Path $evidence $directory
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "output/$directory") -File |
        Where-Object { $_.Extension -in @('.log','.txt') } |
        Copy-Item -Destination $destination
}
$utf8 = [Text.UTF8Encoding]::new($false)
$files = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'user_source') -Recurse -File)
$files += Get-Item -LiteralPath (Join-Path $repoRoot 'TD_project/demo.al')
$inventory = @($files | ForEach-Object {
    [PSCustomObject]@{ Path=$_.FullName.Substring($repoRoot.Length + 1).Replace('\','/'); Length=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
})
[IO.File]::WriteAllText((Join-Path $release 'source_inventory.json'), (ConvertTo-Json -InputObject $inventory -Depth 4), $utf8)
$hashes = @(Get-ChildItem -LiteralPath $release -Recurse -File | Where-Object { $_.Name -ne 'SHA256.json' } | ForEach-Object {
    [PSCustomObject]@{ Path=$_.FullName.Substring($release.Length + 1).Replace('\','/'); Length=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
})
[IO.File]::WriteAllText((Join-Path $release 'SHA256.json'), (ConvertTo-Json -InputObject $hashes -Depth 4), $utf8)
Write-Output "Frozen S0 evidence: $release"
