param([string]$RunName='m3v3_hazard1',[string]$Python='')
# M3 v3 hazard_layer: regenerate the four format 3 board cards (landslide,
# debris flow, flood, earthquake), check each against its out/sd copy, build
# vectors from tools/hazard_v3.render, then run the exhaustive kind x T x t
# sweep, every card image frame by frame, the display-chain alignment and
# shake against the v0.16.0 video_delay, the kind CDC with the temporary t
# source, the FAT32 reader scene-kind path, the production top wiring, and
# mutants that must fail.
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
$cards=@('landslide_village','debris_village','flood_village','quake_village')
$cardOut=@()
foreach($c in $cards){
 $dst="$out/scene_$c".Replace('\','/')
 & $python -I "$root/tools/make_scene_pack.py" "$root/tools/scenes/$c/scene.yaml" --out $dst *> "$out/scene_$c.log"
 if($LASTEXITCODE){throw "scene pack $c failed"}
 # The card the board test uses must be the one simulated.
 foreach($n in 1..4){
  $a=[IO.File]::ReadAllBytes("$dst/sd/PIC$n.BMP")
  $copy="$root/tools/scenes/$c/out/sd/PIC$n.BMP"
  if(!(Test-Path $copy)){throw "$copy missing; run make_scene_pack for $c"}
  $b=[IO.File]::ReadAllBytes($copy)
  $same=$a.Length -eq $b.Length
  for($i=0;$same -and $i -lt $a.Length;$i++){if($a[$i] -ne $b[$i]){$same=$false}}
  $line="$c PIC$n.BMP $($a.Length) bytes, kind $($a[6])/$($a[7]), out/sd copy: $(if($same){'byte-identical'}else{'DIFFERENT'})"
  Add-Content "$out/card_compare.log" $line;Write-Output $line
  if(!$same){throw $line}
 }
 $cardOut+=$dst
}
$vec="$out/vectors".Replace('\','/')
& $python -I "$root/diagnostics/mountain_scene/make_hazard_vectors3.py" $vec @cardOut *> "$out/vectors.log"
if($LASTEXITCODE){throw 'vector generation failed'}
Get-Content "$out/vectors.log"
$frames=[int]([regex]::Match((Get-Content "$out/vectors.log" -Raw),'cards (\d+) frames').Groups[1].Value)
# v0.16.0 video_delay as the alignment reference.
$base=((& git -C $root show 'v0.16.0:user_source/hdl_source/SD/video_delay.v') -join "`n") -replace '\bmodule video_delay\b','module video_delay_base'
[IO.File]::WriteAllText("$out/video_delay_base.v",$base)

$m='diagnostics/mountain_scene'
$units=@("$root/user_source/hdl_source/scene/hazard_layer.v","$root/user_source/hdl_source/scene/hazard_test_source.v",
 "$root/user_source/hdl_source/scene/scene_kind_cdc.v","$root/user_source/hdl_source/SD/video_delay.v","$out/video_delay_base.v")
$tbs=@('tb_m3v3_sweep','tb_m3v3_card','tb_m3_chain','tb_m3_test_source') | ForEach-Object {"$root/$m/$_.sv"}
function Compile($library,$sources,$log){
 & "$sim/vlib.exe" $library *> "$log.lib"
 & "$sim/vlog.exe" -sv -work $library @sources *> $log
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
 Check (Run $lib 'tb_m3v3_sweep' 'tb_m3v3_sweep' 'PASS hazard v3 sweep' @("-gVEC_DIR=$vec")) 'tb_m3v3_sweep'
 Check (Run $lib 'tb_m3v3_card' 'tb_m3v3_card' "PASS hazard v3 cards frames=$frames " @("-gVEC_DIR=$vec","-gFRAMES=$frames")) 'tb_m3v3_card'
 Check (Run $lib 'tb_m3_chain' 'tb_m3_chain' 'PASS M3 chain' @()) 'tb_m3_chain'
 Check (Run $lib 'tb_m3_test_source' 'tb_m3_test_source' 'PASS hazard test source' @()) 'tb_m3_test_source'

 # Mutants: each must be rejected by the named test.
 $hl=Get-Content "$root/user_source/hdl_source/scene/hazard_layer.v" -Raw
 $mutants=@(
  @('mut_rain_len',$hl.Replace("rd0<7'd14","rd0<7'd13"),'tb_m3v3_sweep',@("-gVEC_DIR=$vec")),
  @('mut_noise',$hl.Replace("2'd1:begin nu=x12-{frame_cnt,2'b00}","2'd1:begin nu=x12-{frame_cnt,2'b01}"),'tb_m3v3_sweep',@("-gVEC_DIR=$vec")),
  @('mut_dust',$hl.Replace("8'd64 : 8'd140","8'd64 : 8'd141"),'tb_m3v3_sweep',@("-gVEC_DIR=$vec")),
  @('mut_shake_clamp',$hl.Replace("s>0 ? first_px : last_px","s>0 ? last_px : first_px"),'tb_m3_chain',@()),
  @('mut_sync',$hl,'tb_m3_chain',@('-G/tb_m3_chain/u_delay/SYNC_EXTRA=9'))
 )
 foreach($mu in $mutants){
  if($mu[1] -eq $hl -and $mu[0] -ne 'mut_sync'){throw "mutant $($mu[0]) did not change the source"}
  $src="$out/$($mu[0])_hazard_layer.v";[IO.File]::WriteAllText($src,$mu[1])
  $mlib="$out/$($mu[0])_work".Replace('\','/')
  Compile $mlib (@($src)+$units[1..4]+$tbs) "$out/$($mu[0])_compile.log"
  $r=Run $mlib $mu[0] $mu[2] 'PASS' $mu[3]
  if($r.ok){throw "Mutant $($mu[0]) was not detected; see $($r.log)"}
  Write-Output "PASS mutant $($mu[0]) detected by $($mu[2])"
 }
} finally {Pop-Location}

# FAT32 reader: PIC1 carries scene kind 4/2, PIC2 an out-of-range 9/1 (none).
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root/$m/run_m1.ps1" -RunName "${RunName}_reader" *> "$out/reader.console.log"
if($LASTEXITCODE){throw "reader scene-kind run failed: $out/reader.console.log"}
$kinds=@(Get-ChildItem "$root/diagnostics/output/${RunName}_reader/reader_case*.log" | Where-Object {$_.Name -notlike '*console*'})
if($kinds.Count -ne 8){throw "expected 8 reader logs, found $($kinds.Count)"}
foreach($k in $kinds){
 $t=Get-Content $k.FullName -Raw
 if($t -notmatch 'image=0 depth=32 .* kind=100010' -or $t -notmatch 'image=1 depth=24 .* kind=000000'){throw "scene kind not observed in $($k.Name)"}
}
Write-Output "PASS reader scene kind ($($kinds.Count) runs)"

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
 & "$sim/vlog.exe" -sv +define+SIMULATION -work $tlib '+incdir+../user_source/hdl_source/include' @plain "$root/$m/tb_m3_top.sv" *> "$out/top_compile.log"
 if($LASTEXITCODE){throw 'Top compile failed'}
 & "$sim/vsim.exe" -c -quiet -lib $tlib tb_m3_top glbl -l "$out/tb_m3_top.log" -do 'run -all; quit -f' *> "$out/tb_m3_top.console.log"
 $log=Get-Content "$out/tb_m3_top.log" -Raw
 if($LASTEXITCODE -or $log -match '\*\* (Fatal|Error):' -or $log -notmatch 'PASS M3 production top'){throw "Top test failed: $out/tb_m3_top.log"}
 Write-Output 'PASS tb_m3_top'
} finally {Pop-Location}
