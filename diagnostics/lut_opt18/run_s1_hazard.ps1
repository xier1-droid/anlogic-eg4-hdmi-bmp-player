param([string]$RunName='lut18_hazard_equiv1')
# v0.18 S1 batch 2: hazard_layer against the frozen v0.17.0 module, clock by
# clock, plus mutants that must be detected.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64'
$src="$root/user_source/hdl_source/scene/hazard_layer.v"
function Run-Equiv([string]$name,[string]$dutFile,[bool]$expectPass,[string[]]$extra){
 $dir=Join-Path $out $name; New-Item -ItemType Directory -Path $dir | Out-Null
 $lib="$dir/work".Replace('\','/')
 & "$sim/vlib.exe" $lib *> "$dir/library.log"
 & "$sim/vlog.exe" -sv -work $lib $dutFile "$PSScriptRoot/hazard_layer_v017.v" "$PSScriptRoot/tb_hazard_equiv.sv" *> "$dir/compile.log"
 if($LASTEXITCODE){throw "Compile failed: $dir/compile.log"}
 Push-Location $dir
 try{
  & "$sim/vsim.exe" -c -quiet -lib $lib tb_hazard_equiv @extra -l "$dir/tb.log" -do 'run -all; quit -f' *> "$dir/console.log"
  $log=Get-Content "$dir/tb.log" -Raw
  $pass=(-not $LASTEXITCODE) -and ($log -match 'PASS ') -and ($log -notmatch '\*\* (Fatal|Error|Warning)')
 }finally{Pop-Location}
 if($expectPass -and -not $pass){throw "Test failed: $dir/tb.log"}
 if(-not $expectPass -and $pass){throw "Mutant not detected: $dir"}
 if($expectPass){Write-Output "PASS $name $(([regex]'PASS [^\r\n]*').Match($log).Value)"}else{Write-Output "DETECTED $name"}
}
Run-Equiv 'seed18' $src $true @()
Run-Equiv 'seed7' $src $true @('-gSEED=7','-gFRAMES=24')
# Mutants: wrong corner offset for h11; nsx=3 fraction taken one bit off.
$mut=Join-Path $out 'mutant_src'; New-Item -ItemType Directory -Path $mut | Out-Null
$text=Get-Content $src -Raw
function Mutant([string]$name,[string]$from,[string]$to){
 if(-not $text.Contains($from)){throw "Mutant $name pattern missing"}
 $text.Replace($from,$to) | Set-Content "$mut/$name.v" -NoNewline
 Run-Equiv "mut_$name" "$mut/$name.v" $false @('-gFRAMES=8')
}
Mutant 'corner' "nxy+8'd224" "nxy+8'd223"
Mutant 'shift' "3'd3:begin fx={nu[2:0],1'b0}" "3'd3:begin fx={nu[3:0]}"
Mutant 'fleck' "hazard==FL ? yf[8:1] : yg[7:0]" "hazard==FL ? yf[7:0] : yg[7:0]"
