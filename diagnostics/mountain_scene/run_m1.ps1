param([string]$RunName='m1_alpha1')
# M1 32bpp alpha path: scale stream (24/32bpp, 1:1/enlarge/shrink) and
# FAT32 reader preflight + load (fixed and scaled) with a 32bpp PIC1.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64';$lib="$out/work".Replace('\','/')
$python=(Get-Command python -ErrorAction SilentlyContinue).Source
if(!$python){$python="$env:LOCALAPPDATA\Programs\Python\Python313\python.exe"}
$fixtures="$out/fixtures".Replace('\','/')
& $python -I "$root/diagnostics/mountain_scene/make_alpha_fixture.py" $fixtures *> "$out/fixtures.log"
if($LASTEXITCODE){throw 'fixture generation failed'}
& "$sim/vlib.exe" $lib *> "$out/library.log"
$rtl=@('fat32_bmp_reader','sd_sector_adapter','sd_sector_service','fat32_volume_scanner','fat32_file_streamer',
 'bmp_header_check','bmp24_decoder','bmp_scale_stream','bmp_sector_buffer','image_scale_nearest') | ForEach-Object {"$root/user_source/hdl_source/SD/$_.v"}
& "$sim/vlog.exe" -sv -work $lib d:/TD/anlogic/TD6.2.1/sim_release/common/al_map_lut.v @rtl `
 "$root/diagnostics/mountain_scene/tb_m1_alpha_stream.sv" "$root/diagnostics/mountain_scene/tb_m1_reader_alpha.sv" *> "$out/compile.log"
if($LASTEXITCODE){throw 'Compile failed'}
function Check($name,$log,$pattern){
 $text=Get-Content $log -Raw
 if($LASTEXITCODE -or $text -notmatch $pattern -or $text -match '\*\* (Fatal|Error)' -or $text -notmatch 'Errors: 0, Warnings: 0'){throw "Failed: $name; see $log"}
 Write-Output "PASS $name"
}
Push-Location $out
try {
 & "$sim/vsim.exe" -c -quiet -lib $lib tb_m1_alpha_stream -l "$out/tb_m1_alpha_stream.log" -do 'run -all; quit -f' *> "$out/tb_m1_alpha_stream.console.log"
 Check 'tb_m1_alpha_stream' "$out/tb_m1_alpha_stream.log" 'PASS alpha stream suite'
 foreach($case in 0,1){ foreach($scale in 0,1){ foreach($gap in 0,2){
  $name="reader_case${case}_scale${scale}_gap${gap}"
  & "$sim/vsim.exe" -c -quiet -lib $lib tb_m1_reader_alpha "-gCASE_ID=$case" "-gSCALE_TEST=$scale" "-gBYTE_GAP=$gap" "-gFIXTURE_DIR=$fixtures" -l "$out/$name.log" -do 'run -all; quit -f' *> "$out/$name.console.log"
  Check $name "$out/$name.log" 'PASS M1 reader alpha'
 }}}
} finally {Pop-Location}
