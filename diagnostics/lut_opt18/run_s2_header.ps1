param([string]$RunName='lut18_header1',[string]$Python='')
# v0.18 S2 batch 5: shared header checker. The new fat32_bmp_reader runs
# beside the frozen v0.17.0 reader on every fat32 fixture case (scale path
# and fixed path, byte gaps 0 and 2, rejected-header and timeout modes) and
# must match it on every clock; mutants of the select must be detected.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64'
$python=$Python
if(!$python){$python=(Get-Command python -ErrorAction SilentlyContinue).Source}
if(!$python){$python="$env:USERPROFILE/scoop/apps/python/current/python.exe"}
$fix="$out/fixtures".Replace('\','/')
Push-Location $root
try{
 & $python -I diagnostics/fat32/generate_core_fixtures.py $fix *> "$out/fixtures.log"
 if($LASTEXITCODE){throw 'fixture generation failed'}
}finally{Pop-Location}
$manifest=Get-Content "$fix/manifest.json" -Raw | ConvertFrom-Json
$cases=@($manifest | ForEach-Object {$_.id})
$sd="$root/user_source/hdl_source/SD"
$shared=@('sd_sector_adapter','sd_sector_service','fat32_volume_scanner','fat32_file_streamer','bmp_header_check','bmp_sector_buffer','image_scale_nearest') | ForEach-Object {"$sd/$_.v"}
$frozen=@('fat32_bmp_reader_v017','bmp_scale_stream_v017','bmp24_decoder_v017') | ForEach-Object {"$PSScriptRoot/$_.v"}
$lut='d:/TD/anlogic/TD6.2.1/sim_release/common/al_map_lut.v'
function Compile([string]$name,[string[]]$changed){
 $dir=Join-Path $out $name; New-Item -ItemType Directory -Path $dir | Out-Null
 $lib="$dir/work".Replace('\','/')
 & "$sim/vlib.exe" $lib *> "$dir/library.log"
 & "$sim/vlog.exe" -sv -work $lib @changed @shared @frozen $lut "$PSScriptRoot/tb_reader_lockstep.sv" *> "$dir/compile.log"
 if($LASTEXITCODE){throw "Compile failed: $dir/compile.log"}
 return $dir
}
function Run-Case([string]$dir,[int]$scale,[int]$id,[int]$gap,[int]$mode){
 $log="$dir/s${scale}_case${id}_gap${gap}_mode${mode}.log"
 # The fixture contracts assume the fixed path; on the scale path only case 0
 # in mode 0 (the regression's reader_scale case) keeps them, the rest are
 # lockstep only.
 $contract=[int]($scale -eq 0 -or ($id -eq 0 -and $mode -eq 0))
 & "$sim/vsim.exe" -c -quiet -lib "$dir/work".Replace('\','/') tb_reader_lockstep "-gSCALE_TEST=$scale" "-gCASE_ID=$id" "-gBYTE_GAP=$gap" "-gTEST_MODE=$mode" "-gCHECK_CONTRACT=$contract" "-gFIXTURE_DIR=$fix" -l $log -do 'run -all; quit -f' *> "$log.console"
 $text=Get-Content $log -Raw
 return (-not $LASTEXITCODE) -and ($text -match 'PASS reader lockstep') -and ($text -match 'Errors: 0, Warnings: 0')
}
$new=@('fat32_bmp_reader','bmp_scale_stream','bmp24_decoder') | ForEach-Object {"$sd/$_.v"}
$dir=Compile 'lockstep' $new
$runs=0
foreach($scale in 1,0){
 foreach($gap in 0,2){
  foreach($id in $cases){
   if(-not (Run-Case $dir $scale $id $gap 0)){throw "lockstep failed: scale $scale case $id gap $gap"}
   $runs++
  }
 }
 # Rejected headers (width, bit count, file length), ack timeout, last byte with end.
 foreach($mode in 1,2,3,4,5){
  if(-not (Run-Case $dir $scale 0 2 $mode)){throw "lockstep failed: scale $scale mode $mode"}
  $runs++
 }
}
Write-Output "PASS lockstep: $runs runs ($($cases.Count) cases x 2 gaps x 2 paths + 5 modes x 2 paths)"
# Mutants on the scale path, case 0 gap 2: select never switches to the
# decoder; decoder offset replaced by the sector index; decoder bytes not
# marked valid (stale preflight header). Rescans after a load are covered by
# the preview/system regressions, not by this single-scan bench.
$mut=Join-Path $out 'mutant_src'; New-Item -ItemType Directory -Path $mut | Out-Null
$text=Get-Content "$sd/fat32_bmp_reader.v" -Raw
function Mutant([string]$name,[string]$from,[string]$to){
 if(-not $text.Contains($from)){throw "Mutant $name pattern missing"}
 $text.Replace($from,$to) | Set-Content "$mut/fat32_bmp_reader.v" -NoNewline
 $d=Compile "mut_$name" @("$mut/fat32_bmp_reader.v","$sd/bmp_scale_stream.v","$sd/bmp24_decoder.v")
 if(Run-Case $d 1 0 2 0){throw "Mutant not detected: $name"}
 Write-Output "DETECTED $name"
}
Mutant 'never_load' 'else if(load_start)header_load<=1;' 'else if(load_start)header_load<=0;'
Mutant 'offset' '{23''d0,header_load ? dec_offset : sector_index}' '{23''d0,sector_index}'
Mutant 'valid' '.file_valid(header_load ? dec_valid : preflight_valid)' '.file_valid(preflight_valid)'
