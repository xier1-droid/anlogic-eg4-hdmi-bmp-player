param([string]$RunName='m5_text1',[string]$Python='')
# M5 FONT/TEXT, scene OSD, warning mode and speed item: the tool check
# (check_scene_text.py) and two generated cards (landslide, quake: --text),
# unit benches (scenario_fsm warning/speed, keys and the speed item, scene
# OSD pixel model per card, subtitle BRAM font against the case font),
# sd_card_bmp FONT/TEXT load and warning flow on the production file list,
# the production top wiring, and mutants that must fail.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64'
$td='d:/TD/anlogic/TD6.2.1'
if(!$Python){$Python=Join-Path $env:USERPROFILE 'scoop/apps/python/current/python.exe'}
$m="$root/diagnostics/mountain_scene";$h="$root/user_source/hdl_source"
function Compile($library,$sources,$log){
 & "$sim/vlib.exe" $library *> "$log.lib"
 & "$sim/vlog.exe" -sv -work $library @sources *> $log
 if($LASTEXITCODE){throw "Compile failed: $log"}
}
function Run($library,$name,$top,$pattern,$extra){
 $log="$out/$name.log"
 & "$sim/vsim.exe" -c -quiet -voptargs=+acc -lib $library $top @extra -l $log -do 'run -all; quit -f' *> "$out/$name.console.log"
 $text=Get-Content $log -Raw
 $ok=!$LASTEXITCODE -and $text -match $pattern -and $text -notmatch '\*\* (Fatal|Error|Warning)'
 return @{ok=$ok;log=$log}
}
function Check($r,$name){if(!$r.ok){throw "Failed: $name; see $($r.log)"};Write-Output "PASS $name"}

# Tool: text check, then the cards used by the benches.
& $Python -I "$m/check_scene_text.py" $root *> "$out/check_scene_text.log"
if($LASTEXITCODE -or (Get-Content "$out/check_scene_text.log" -Raw) -notmatch 'PASS M5 scene text'){throw "Failed: check_scene_text; see $out/check_scene_text.log"}
Write-Output 'PASS check_scene_text'
$cards=@('landslide','quake')
foreach($c in $cards){
 & $Python -I "$root/tools/make_scene_pack.py" "$root/tools/scenes/${c}_village/scene.yaml" --out "$out/card_$c" --text *> "$out/card_$c.log"
 if($LASTEXITCODE){throw "Card $c failed: $out/card_$c.log"}
}
$card="$out/card_landslide/sd".Replace('\','/')

# Unit benches.
$unitRtl=@("$h/scene/scenario_fsm.v","$h/SD/mode_key_control.v","$h/SD/key_press_debounce.v","$h/adjust/media_adjust_control.v",
 "$h/adjust/adjust_osd_overlay.v","$h/osd/osd_font_5x7.v","$h/osd/osd_pixel_position.v","$h/osd/osd_font_cn_16x16.v",
 "$h/osd/scroll_text_overlay.v","$h/scene/scene_osd.v","$h/scene/bin_to_bram_loader.v")
$unitTb=@('tb_m5_fsm','tb_m5_keys','tb_m5_osd','tb_m5_scroll_font') | ForEach-Object {"$m/$_.sv"}
$lib="$out/unit_work".Replace('\','/')
Compile $lib ($unitRtl+$unitTb) "$out/unit_compile.log"
$units=@(
 @('tb_m5_fsm','tb_m5_fsm','PASS M5 scenario_fsm',@()),
 @('tb_m5_keys','tb_m5_keys','PASS M5 keys',@()),
 @('tb_m5_scroll_font','tb_m5_scroll_font','PASS M5 subtitle font',@("-gFONT_FILE=$card/FONT.BIN"))
)
foreach($c in $cards){
 $d="$out/card_$c/sd".Replace('\','/')
 $units+=,@("tb_m5_osd_$c",'tb_m5_osd','PASS M5 scene OSD',@("-gFONT_FILE=$d/FONT.BIN","-gTEXT_FILE=$d/TEXT.BIN"))
}
Push-Location $out
try {
 $env:MSYS_NO_PATHCONV='1'
 foreach($u in $units){Check (Run $lib $u[0] $u[1] $u[2] $u[3]) $u[0]}
 $osdArgs=@("-gFONT_FILE=$card/FONT.BIN","-gTEXT_FILE=$card/TEXT.BIN")
 $mutants=@(
  @('mut_sub_row',"$h/scene/scene_osd.v","y[3:0]+4'd4","y[3:0]+4'd3",'tb_m5_osd',$osdArgs),
  @('mut_cell_len',"$h/scene/scene_osd.v",'rel[12:4]<{1''b0,len}','rel[12:4]<={1''b0,len}','tb_m5_osd',$osdArgs),
  @('mut_desc_addr',"$h/scene/scene_osd.v","{seg_s,2'b00}+{2'd0,fstep}-6'd1","{seg_s,2'b00}+{2'd0,fstep}",'tb_m5_osd',$osdArgs),
  @('mut_scroll_step',"$h/scene/scene_osd.v","scroll<=scroll+13'd2","scroll<=scroll+13'd1",'tb_m5_osd',$osdArgs),
  @('mut_status_band',"$h/scene/scene_osd.v",'status_area ? rgb_plain : rgb_in','rgb_in','tb_m5_osd',$osdArgs),
  @('mut_next_char',"$h/osd/scroll_text_overlay.v",'wire signed [31:0] next_x = text_x + 1;','wire signed [31:0] next_x = text_x;','tb_m5_scroll_font',@("-gFONT_FILE=$card/FONT.BIN")),
  @('mut_warn_t',"$h/scene/scenario_fsm.v","t_now<=warn ? 8'd239 : t_next;",'t_now<=t_next;','tb_m5_fsm',@()),
  @('mut_warn_key',"$h/SD/mode_key_control.v",'else if (!scene_mode) warn_mode <= 0;','','tb_m5_keys',@()),
  @('mut_speed_clamp',"$h/adjust/media_adjust_control.v",'3:if(increase && speed<2)','3:if(increase && speed<3)','tb_m5_keys',@())

 )
 foreach($mu in $mutants){
  $text=[IO.File]::ReadAllText($mu[1])
  if(!$text.Contains($mu[2])){throw "mutant $($mu[0]): pattern not found"}
  $src="$out/$($mu[0])_$(Split-Path $mu[1] -Leaf)";[IO.File]::WriteAllText($src,$text.Replace($mu[2],$mu[3]))
  $mlib="$out/$($mu[0])_work".Replace('\','/')
  Compile $mlib (@($src)+@($unitRtl | Where-Object {$_ -ne $mu[1]})+@("$m/$($mu[4]).sv")) "$out/$($mu[0])_compile.log"
  $r=Run $mlib $mu[0] $mu[4] 'PASS' $mu[5]
  if($r.ok){throw "Mutant $($mu[0]) was not detected; see $($r.log)"}
  Write-Output "PASS mutant $($mu[0]) detected by $($mu[4])"
 }
} finally {Pop-Location}

# sd_card_bmp FONT/TEXT and warning on the production file list.
[xml]$project=(Get-Content "$root/TD_project/demo.al" -Encoding UTF8 -Raw).Replace('UsedInP&R','UsedInP&amp;R')
$modeled=@('sys_pll_s3.v','sys_pll.v','video_pll.v','sdram.v','afifo_16_32_256.v','afifo_32_16_256.v','sdr_as_ram.enc.v','sdr_init_ref.enc.v','sdr_wrrd.enc.v')
$rtl=@($project.SelectNodes('/Project/Source_Files/Verilog/File') | ForEach-Object {
 $p=$_.GetAttribute('Path');if((Split-Path $p -Leaf) -notin $modeled){[IO.Path]::GetFullPath((Join-Path "$root/TD_project" $p))}
})
$slib="$out/scene_work".Replace('\','/')
$sceneTb=@("$m/tb_m5_scene.sv","$td/sim_release/common/al_map_lut.v")
Compile $slib ($rtl+$sceneTb) "$out/scene_compile.log"
Push-Location $out
try {
 Check (Run $slib 'tb_m5_scene' 'tb_m5_scene' 'PASS M5 scene' @()) 'tb_m5_scene'
 $smut=@(
  @('mut_text_magic',"$h/SD/fat32_bmp_reader.v",'stream_offset[0] ? "X" : "T"','stream_offset[0] ? "Y" : "T"'),
  @('mut_bin_limit',"$h/SD/fat32_bmp_reader.v","bin_size>13'd4096","bin_size>13'd8191"),
  @('mut_warn_target',"$h/SD/sd_card_bmp.v",'(warn_jump?last_image:ctrl_target_image)','ctrl_target_image'),
  @('mut_warn_next',"$h/SD/sd_card_bmp.v",'(media_next_request && !(warn_mode && mode==0))','media_next_request'),
  @('mut_font_name',"$h/SD/fat32_volume_scanner.v",'font_match<=font_match && sector_byte=="O"','font_match<=font_match && sector_byte=="0"')
 )
 foreach($mu in $smut){
  $text=[IO.File]::ReadAllText($mu[1])
  if(!$text.Contains($mu[2])){throw "mutant $($mu[0]): pattern not found"}
  $src="$out/$($mu[0])_$(Split-Path $mu[1] -Leaf)";[IO.File]::WriteAllText($src,$text.Replace($mu[2],$mu[3]))
  $mlib="$out/$($mu[0])_work".Replace('\','/')
  Compile $mlib (@($src)+@($rtl | Where-Object {(Split-Path $_ -Leaf) -ne (Split-Path $mu[1] -Leaf)})+$sceneTb) "$out/$($mu[0])_compile.log"
  $r=Run $mlib $mu[0] 'tb_m5_scene' 'PASS' @()
  if($r.ok){throw "Mutant $($mu[0]) was not detected; see $($r.log)"}
  Write-Output "PASS mutant $($mu[0]) detected by tb_m5_scene"
 }
} finally {Pop-Location}

# Production top: the TD project file list, as run_m4.ps1.
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
 & "$sim/vlog.exe" -sv +define+SIMULATION -work $tlib '+incdir+../user_source/hdl_source/include' @plain "$m/tb_m5_top.sv" "$m/tb_m4_top.sv" *> "$out/top_compile.log"
 if($LASTEXITCODE){throw 'Top compile failed'}
 foreach($t in @(@('tb_m5_top','PASS M5 production top'),@('tb_m4_top','PASS M4 production top'))){
  & "$sim/vsim.exe" -c -quiet -voptargs=+acc -lib $tlib $t[0] glbl -l "$out/$($t[0]).log" -do 'run -all; quit -f' *> "$out/$($t[0]).console.log"
  $log=Get-Content "$out/$($t[0]).log" -Raw
  if($LASTEXITCODE -or $log -match '\*\* (Fatal|Error):' -or $log -notmatch $t[1]){throw "Top test failed: $out/$($t[0]).log"}
  Write-Output "PASS $($t[0])"
 }
} finally {Pop-Location}
