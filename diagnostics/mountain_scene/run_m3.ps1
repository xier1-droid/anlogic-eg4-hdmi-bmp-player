param([string]$RunName='m3_hazard1',[string]$Python='',[string]$SceneName='valley_village')
# M3 hazard_layer: regenerate the board card's scene pack (-SceneName), build vectors from
# the M2 reference model, then run the exhaustive T x t sweep, the card frames
# against the expected PNGs, the display-chain alignment against the v0.16.0
# video_delay, the temporary t/stage driver, the production top wiring, and
# three mutants that must fail.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64';$lib="$out/work".Replace('\','/')
$td='d:/TD/anlogic/TD6.2.1'
# Needs Pillow, numpy and PyYAML; the scoop Python 3.11 has them (HANDOFF).
$python=$Python
if(!$python){$python=(Get-Command python -ErrorAction SilentlyContinue).Source}
if(!$python){$python="$env:USERPROFILE/scoop/apps/python/current/python.exe"}
$scene="$out/scene".Replace('\','/');$vec="$out/vectors".Replace('\','/')
& $python -I "$root/tools/make_scene_pack.py" "$root/tools/scenes/$SceneName/scene.yaml" --out $scene *> "$out/scene.log"
if($LASTEXITCODE){throw 'scene pack generation failed'}
# The card the board test uses must be the one simulated.
$card="$root/tools/scenes/$SceneName/out/sd"
foreach($n in 1..4){
 $a=[IO.File]::ReadAllBytes("$scene/sd/PIC$n.BMP")
 if(Test-Path "$card/PIC$n.BMP"){
  $b=[IO.File]::ReadAllBytes("$card/PIC$n.BMP")
  $same=$a.Length -eq $b.Length
  for($i=0;$same -and $i -lt $a.Length;$i++){if($a[$i] -ne $b[$i]){$same=$false}}
  $line="PIC$n.BMP $($a.Length) bytes, tools/scenes/$SceneName/out/sd copy: $(if($same){'byte-identical'}else{'DIFFERENT'})"
  if(!$same){throw $line}
 } else {$line="PIC$n.BMP $($a.Length) bytes, no tools/scenes/$SceneName/out/sd copy"}
 Add-Content "$out/card_compare.log" $line;Write-Output $line
}
& $python -I "$root/diagnostics/mountain_scene/make_hazard_vectors.py" $scene $vec *> "$out/vectors.log"
if($LASTEXITCODE){throw 'vector generation failed'}
Get-Content "$out/vectors.log"
# v0.16.0 video_delay as the alignment reference.
$base=((& git -C $root show 'v0.16.0:user_source/hdl_source/SD/video_delay.v') -join "`n") -replace '\bmodule video_delay\b','module video_delay_base'
[IO.File]::WriteAllText("$out/video_delay_base.v",$base)

$m='diagnostics/mountain_scene'
$units=@("$root/user_source/hdl_source/scene/hazard_layer.v","$root/user_source/hdl_source/scene/hazard_test_source.v",
 "$root/user_source/hdl_source/SD/video_delay.v","$out/video_delay_base.v")
$tbs=@('tb_m3_hazard_sweep','tb_m3_hazard_card','tb_m3_chain','tb_m3_test_source') | ForEach-Object {"$root/$m/$_.sv"}
function Compile($library,$sources,$log){
 & "$sim/vlib.exe" $library *> "$log.lib"
 & "$sim/vlog.exe" -sv -work $library "+incdir+$root/$m" @sources *> $log
 if($LASTEXITCODE){throw "Compile failed: $log"}
}
function Run($library,$name,$top,$pattern,$extra){
 $log="$out/$name.log"
 & "$sim/vsim.exe" -c -quiet -lib $library $top @extra -l $log -do 'run -all; quit -f' *> "$out/$name.console.log"
 $text=Get-Content $log -Raw
 $ok=!$LASTEXITCODE -and $text -match $pattern -and $text -notmatch '\*\* (Fatal|Error|Warning)'
 return @{ok=$ok;log=$log}
}
function Check($r,$name){if(!$r.ok){throw "Failed: $name; see $($r.log)"};Write-Output "PASS $name"}
Compile $lib ($units+$tbs) "$out/compile.log"
Push-Location $out
try {
 Check (Run $lib 'tb_m3_hazard_sweep' 'tb_m3_hazard_sweep' 'PASS hazard sweep' @("-gVEC_DIR=$vec")) 'tb_m3_hazard_sweep'
 Check (Run $lib 'tb_m3_hazard_card' 'tb_m3_hazard_card' 'PASS hazard card frames=52' @("-gVEC_DIR=$vec","-gFILE_DIR=$scene/sd")) 'tb_m3_hazard_card'
 Check (Run $lib 'tb_m3_chain' 'tb_m3_chain' 'PASS M3 chain' @()) 'tb_m3_chain'
 Check (Run $lib 'tb_m3_test_source' 'tb_m3_test_source' 'PASS hazard test source' @()) 'tb_m3_test_source'

 # Mutants: each must be rejected by the named test.
 $hl=Get-Content "$root/user_source/hdl_source/scene/hazard_layer.v" -Raw
 $mutants=@(
  @('mut_front5',$hl.Replace("age<8'd6","age<8'd5"),'tb_m3_hazard_sweep',@("-gVEC_DIR=$vec")),
  @('mut_rain',$hl.Replace("drop<5'd12","drop<5'd11"),'tb_m3_hazard_card',@("-gVEC_DIR=$vec","-gFILE_DIR=$scene/sd")),
  @('mut_blink_bit',$hl.Replace("frame_cnt[3] : frame_cnt[4]","frame_cnt[4] : frame_cnt[4]"),'tb_m3_hazard_sweep',@("-gVEC_DIR=$vec")),
  @('mut_sync1',$hl,'tb_m3_chain',@('-G/tb_m3_chain/u_delay/SYNC_EXTRA=1'))
 )
 foreach($mu in $mutants){
  if($mu[1] -eq $hl -and $mu[0] -ne 'mut_sync1'){throw "mutant $($mu[0]) did not change the source"}
  $src="$out/$($mu[0])_hazard_layer.v";[IO.File]::WriteAllText($src,$mu[1])
  $mlib="$out/$($mu[0])_work".Replace('\','/')
  Compile $mlib (@($src)+$units[1..3]+$tbs) "$out/$($mu[0])_compile.log"
  $r=Run $mlib $mu[0] $mu[2] 'PASS' $mu[3]
  if($r.ok){throw "Mutant $($mu[0]) was not detected; see $($r.log)"}
  Write-Output "PASS mutant $($mu[0]) detected by $($mu[2])"
 }
} finally {Pop-Location}

# Production top: the TD project file list, as media_adjust/run_top.ps1.
$tlib="$out/top_work".Replace('\','/')
& "$sim/vlib.exe" $tlib *> "$out/top_library.log"
$vendor=Get-ChildItem "$td/sim_release/eg4/*.v","$td/sim_release/common/*.v" | ForEach-Object {$_.FullName}
& "$sim/vlog.exe" -work $tlib @vendor *> "$out/top_vendor.log"
if($LASTEXITCODE){throw 'Vendor compile failed'}
Push-Location "$root/TD_project"
try {
 [xml]$project=(Get-Content demo.al -Encoding UTF8 -Raw).Replace('UsedInP&R','UsedInP&amp;R')
 $rtl=@($project.SelectNodes('/Project/Source_Files/Verilog/File') | Where-Object {!$_.SelectSingleNode("FileInfo/Attr[@Name='AutoExcluded' and @Val='true']")} | ForEach-Object {$_.GetAttribute('Path')})
 $enc=@($rtl | Where-Object {$_ -like '*.enc.v'})
 $plain=@($rtl | Where-Object {$_ -notlike '*.enc.v' -and $_ -notlike '*sys_pll_s3.v'})
 & "$sim/vlog.exe" -work $tlib '../user_source/ip_source/s3_single_pll/sys_pll_s3.v' *> "$out/top_pll.log"
 if($LASTEXITCODE){throw 'PLL compile failed'}
 & "$sim/vlog.exe" -work $tlib '+incdir+../user_source/hdl_source/include' @enc *> "$out/top_encrypted.log"
 if($LASTEXITCODE){throw 'Encrypted compile failed'}
 & "$sim/vlog.exe" -sv +define+SIMULATION -work $tlib '+incdir+../user_source/hdl_source/include' "+incdir+$root/$m" @plain "$root/$m/tb_m3_top.sv" *> "$out/top_compile.log"
 if($LASTEXITCODE){throw 'Top compile failed'}
 & "$sim/vsim.exe" -c -quiet -lib $tlib tb_m3_top glbl -l "$out/tb_m3_top.log" -do 'run -all; quit -f' *> "$out/tb_m3_top.console.log"
 $log=Get-Content "$out/tb_m3_top.log" -Raw
 if($LASTEXITCODE -or $log -match '\*\* (Fatal|Error):' -or $log -notmatch 'PASS M3 production top'){throw "Top test failed: $out/tb_m3_top.log"}
 Write-Output 'PASS tb_m3_top'
} finally {Pop-Location}
