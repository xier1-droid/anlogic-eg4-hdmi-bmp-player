param([string]$RunName='m4_scene1')
# M4 scenario_fsm, SND1-4 and fade_mute: unit benches (scenario_fsm, fade
# gain, scene keys, SND scanner slots at byte gaps 0 and 2, plus the updated
# pcm_audio/tb_audio_scan), sd_card_bmp scene audio on the production file
# list, the production top wiring, and mutants that must fail.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64'
$td='d:/TD/anlogic/TD6.2.1'
$m="$root/diagnostics/mountain_scene";$h="$root/user_source/hdl_source"
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

# Unit benches.
$unitRtl=@("$h/scene/scenario_fsm.v","$h/adjust/pcm_master_volume.v","$h/SD/mode_key_control.v","$h/SD/key_press_debounce.v","$h/SD/fat32_volume_scanner.v")
$unitTb=@('tb_m4_fsm','tb_m4_fade','tb_m4_keys','tb_m4_scanner') | ForEach-Object {"$m/$_.sv"}
$unitTb+="$root/diagnostics/pcm_audio/tb_audio_scan.sv"
$lib="$out/unit_work".Replace('\','/')
Compile $lib ($unitRtl+$unitTb) "$out/unit_compile.log"
$units=@(
 @('tb_m4_fsm','tb_m4_fsm','PASS M4 scenario_fsm',@()),
 @('tb_m4_fade','tb_m4_fade','PASS M4 fade',@()),
 @('tb_m4_keys','tb_m4_keys','PASS M4 keys',@()),
 @('tb_m4_scanner_gap0','tb_m4_scanner','PASS M4 scanner: .* gap=0',@()),
 @('tb_m4_scanner_gap2','tb_m4_scanner','PASS M4 scanner: .* gap=2',@('-gGAP=2')),
 @('tb_audio_scan_gap0','tb_audio_scan','PASS audio scan: .* gap=0',@()),
 @('tb_audio_scan_gap2','tb_audio_scan','PASS audio scan: .* gap=2',@('-gGAP=2'))
)
Push-Location $out
try {
 foreach($u in $units){Check (Run $lib $u[0] $u[1] $u[2] $u[3]) $u[0]}
 # Unit mutants: each must be rejected by the named bench.
 $mutants=@(
  @('mut_fade_step',"$h/adjust/pcm_master_volume.v","17'd14:17'd256","17'd15:17'd256",'tb_m4_fade'),
  @('mut_sample_step',"$h/scene/scenario_fsm.v",'if(sample_count>=sample_last)','if(sample_count>sample_last)','tb_m4_fsm'),
  @('mut_hold_restart',"$h/scene/scenario_fsm.v",'if((saw_stop && audio_running) ||','if(audio_running ||','tb_m4_fsm'),
  @('mut_t_frozen',"$h/scene/scenario_fsm.v",'if(!hold && t_next!=8''d239)','if(t_next!=8''d239)','tb_m4_fsm'),
  @('mut_snd_name',"$h/SD/fat32_volume_scanner.v",'snd_match<=snd_match && sector_byte=="D"','snd_match<=snd_match && sector_byte=="E"','tb_m4_scanner'),
  @('mut_scan_stop',"$h/SD/fat32_volume_scanner.v",'(bgm_found && snd_found==4''hf)','bgm_found','tb_m4_scanner'),
  @('mut_scene_prev',"$h/SD/mode_key_control.v",'((press_mode == 0 && !scene_mode) ||','((press_mode == 0) ||','tb_m4_keys'),
  @('mut_auto_press',"$h/SD/mode_key_control.v",'press_mode==mode && mode==3);','press_mode==mode && (mode==0 || mode==3));','tb_m4_keys')
 )
 foreach($mu in $mutants){
  $text=[IO.File]::ReadAllText($mu[1])
  if(!$text.Contains($mu[2])){throw "mutant $($mu[0]): pattern not found"}
  $src="$out/$($mu[0])_$(Split-Path $mu[1] -Leaf)";[IO.File]::WriteAllText($src,$text.Replace($mu[2],$mu[3]))
  $mlib="$out/$($mu[0])_work".Replace('\','/')
  Compile $mlib (@($src)+@($unitRtl | Where-Object {$_ -ne $mu[1]})+$unitTb) "$out/$($mu[0])_compile.log"
  $r=Run $mlib $mu[0] $mu[4] 'PASS' @()
  if($r.ok){throw "Mutant $($mu[0]) was not detected; see $($r.log)"}
  Write-Output "PASS mutant $($mu[0]) detected by $($mu[4])"
 }
} finally {Pop-Location}

# sd_card_bmp scene audio on the production file list (as pcm_audio/run_production.ps1).
[xml]$project=(Get-Content "$root/TD_project/demo.al" -Encoding UTF8 -Raw).Replace('UsedInP&R','UsedInP&amp;R')
$modeled=@('sys_pll_s3.v','sys_pll.v','video_pll.v','sdram.v','afifo_16_32_256.v','afifo_32_16_256.v','sdr_as_ram.enc.v','sdr_init_ref.enc.v','sdr_wrrd.enc.v')
$rtl=@($project.SelectNodes('/Project/Source_Files/Verilog/File') | ForEach-Object {
 $p=$_.GetAttribute('Path');if((Split-Path $p -Leaf) -notin $modeled){[IO.Path]::GetFullPath((Join-Path "$root/TD_project" $p))}
})
$slib="$out/scene_work".Replace('\','/')
Compile $slib ($rtl+@("$m/tb_m4_scene_audio.sv","$td/sim_release/common/al_map_lut.v")) "$out/scene_compile.log"
Push-Location $out
try {
 Check (Run $slib 'tb_m4_scene_audio' 'tb_m4_scene_audio' 'PASS M4 scene audio' @()) 'tb_m4_scene_audio'
 # Without the per-stage SND check a missing SND3 plays nothing instead of BGM.
 $bmp="$h/SD/sd_card_bmp.v";$text=[IO.File]::ReadAllText($bmp)
 $pat='(scene_mode && snd_found[committed_image])';if(!$text.Contains($pat)){throw 'mutant mut_no_fallback: pattern not found'}
 $src="$out/mut_no_fallback_sd_card_bmp.v";[IO.File]::WriteAllText($src,$text.Replace($pat,'scene_mode'))
 $mlib="$out/mut_no_fallback_work".Replace('\','/')
 Compile $mlib (@($src)+@($rtl | Where-Object {(Split-Path $_ -Leaf) -ne 'sd_card_bmp.v'})+@("$m/tb_m4_scene_audio.sv","$td/sim_release/common/al_map_lut.v")) "$out/mut_no_fallback_compile.log"
 $r=Run $mlib 'mut_no_fallback' 'tb_m4_scene_audio' 'PASS' @()
 if($r.ok){throw "Mutant mut_no_fallback was not detected; see $($r.log)"}
 Write-Output 'PASS mutant mut_no_fallback detected by tb_m4_scene_audio'
} finally {Pop-Location}

# Production top: the TD project file list, as run_m3.ps1.
$tlib="$out/top_work".Replace('\','/')
& "$sim/vlib.exe" $tlib *> "$out/top_library.log"
$vendor=Get-ChildItem "$td/sim_release/eg4/*.v","$td/sim_release/common/*.v" | ForEach-Object {$_.FullName}
& "$sim/vlog.exe" -work $tlib @vendor *> "$out/top_vendor.log"
if($LASTEXITCODE){throw 'Vendor compile failed'}
Push-Location "$root/TD_project"
try {
 $all=@($project.SelectNodes('/Project/Source_Files/Verilog/File') | Where-Object {!$_.SelectSingleNode("FileInfo/Attr[@Name='AutoExcluded' and @Val='true']")} | ForEach-Object {$_.GetAttribute('Path')})
 $enc=@($all | Where-Object {$_ -like '*.enc.v'})
 $plain=@($all | Where-Object {$_ -notlike '*.enc.v' -and $_ -notlike '*sys_pll_s3.v'})
 & "$sim/vlog.exe" -work $tlib '../user_source/ip_source/s3_single_pll/sys_pll_s3.v' *> "$out/top_pll.log"
 if($LASTEXITCODE){throw 'PLL compile failed'}
 & "$sim/vlog.exe" -work $tlib '+incdir+../user_source/hdl_source/include' @enc *> "$out/top_encrypted.log"
 if($LASTEXITCODE){throw 'Encrypted compile failed'}
 & "$sim/vlog.exe" -sv +define+SIMULATION -work $tlib '+incdir+../user_source/hdl_source/include' @plain "$m/tb_m4_top.sv" *> "$out/top_compile.log"
 if($LASTEXITCODE){throw 'Top compile failed'}
 & "$sim/vsim.exe" -c -quiet -lib $tlib tb_m4_top glbl -l "$out/tb_m4_top.log" -do 'run -all; quit -f' *> "$out/tb_m4_top.console.log"
 $log=Get-Content "$out/tb_m4_top.log" -Raw
 if($LASTEXITCODE -or $log -match '\*\* (Fatal|Error):' -or $log -notmatch 'PASS M4 production top'){throw "Top test failed: $out/tb_m4_top.log"}
 Write-Output 'PASS tb_m4_top'
} finally {Pop-Location}
