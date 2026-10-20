param([string]$RunName='lut18_ring1')
# v0.18 S2 batch 8: audio ring in production mode against the frozen v0.17.0
# pair, clock by clock (two seeds), the existing audio_vis unit tests on the
# default mode, and mutants that must be detected.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64'
$av="$root/user_source/hdl_source/audio_vis"
$frozen=@('audio_ring_levels_v017','audio_ring_overlay_v017','audio_ring_rom_v017') | ForEach-Object {"$PSScriptRoot/$_.v"}
function Run-Tb([string]$name,[string[]]$files,[string]$top,[string[]]$extra,[bool]$expectPass){
 $dir=Join-Path $out $name; New-Item -ItemType Directory -Path $dir | Out-Null
 $lib="$dir/work".Replace('\','/')
 & "$sim/vlib.exe" $lib *> "$dir/library.log"
 & "$sim/vlog.exe" -sv -work $lib @files *> "$dir/compile.log"
 if($LASTEXITCODE){throw "Compile failed: $dir/compile.log"}
 Push-Location $dir
 try{
  & "$sim/vsim.exe" -c -quiet -lib $lib $top @extra -l "$dir/tb.log" -do 'run -all; quit -f' *> "$dir/console.log"
  $log=Get-Content "$dir/tb.log" -Raw
  $pass=(-not $LASTEXITCODE) -and ($log -match 'PASS ') -and ($log -notmatch '\*\* (Fatal|Error|Warning)')
 }finally{Pop-Location}
 if($expectPass -and -not $pass){throw "Test failed: $dir/tb.log"}
 if(-not $expectPass -and $pass){throw "Mutant not detected: $dir"}
 if($expectPass){Write-Output "PASS $name $(([regex]'PASS [^\r\n]*').Match($log).Value)"}else{Write-Output "DETECTED $name"}
}
function Ring-Files([string]$levels,[string]$overlay){
 return @($levels,$overlay,"$av/audio_ring_rom.v")+$frozen+@("$PSScriptRoot/tb_ring_lockstep.sv")
}
$lv="$av/audio_ring_levels.v";$ov="$av/audio_ring_overlay.v"
Run-Tb 'seed18' (Ring-Files $lv $ov) 'tb_ring_lockstep' @() $true
Run-Tb 'seed7' (Ring-Files $lv $ov) 'tb_ring_lockstep' @('-gSEED=7','-gFRAMES=24') $true
# Default-mode unit tests (unchanged behaviour for other users of the modules).
Run-Tb 'unit_levels' @($lv,"$root/diagnostics/audio_vis/tb_audio_ring.sv") 'tb_audio_ring' @() $true
Run-Tb 'unit_pixels' @($ov,"$av/audio_ring_rom.v","$root/diagnostics/audio_vis/tb_ring_pixels.sv") 'tb_ring_pixels' @() $true
# Mutants: next-pixel ROM address off by one; colour from the unregistered
# bar index; display read address one bar off.
$mut=Join-Path $out 'mutant_src'; New-Item -ItemType Directory -Path $mut | Out-Null
function Mutant([string]$name,[string]$file,[string]$from,[string]$to){
 $text=Get-Content $file -Raw
 if(-not $text.Contains($from)){throw "Mutant $name pattern missing"}
 $m="$mut/$name.v";$text.Replace($from,$to) | Set-Content $m -NoNewline
 if($file -eq $lv){$files=Ring-Files $m $ov}else{$files=Ring-Files $lv $m}
 Run-Tb "mut_$name" $files 'tb_ring_lockstep' @('-gFRAMES=6') $false
}
Mutant 'next_x' $ov "wire [9:0] next_x=pixel_x+1'b1;" "wire [9:0] next_x=pixel_x+2'd2;"
Mutant 'color' $ov 'wire [6:0] color_bar=LEVEL_LATENCY ? bar_index_q : bar_index;' 'wire [6:0] color_bar=bar_index;'
Mutant 'display' $lv 'display_q <= display_heights[bar_index];' 'display_q <= display_heights[bar_index+1''b1];'
