param([string]$RunName='lut18_keys1')
# v0.18 S1 batch 4: mode_key_control on the shared 1 ms tick against the
# frozen v0.17.0 module at 20 clocks per ms (edges within one tick), three
# seeds, plus mutants that must be detected.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64'
$src="$root/user_source/hdl_source/SD/mode_key_control.v"
$deb="$root/user_source/hdl_source/SD/key_press_debounce.v"
function Run-Keys([string]$name,[string]$dutFile,[bool]$expectPass,[string[]]$extra){
 $dir=Join-Path $out $name; New-Item -ItemType Directory -Path $dir | Out-Null
 $lib="$dir/work".Replace('\','/')
 & "$sim/vlib.exe" $lib *> "$dir/library.log"
 & "$sim/vlog.exe" -sv -work $lib $dutFile $deb "$PSScriptRoot/mode_key_control_v017.v" "$PSScriptRoot/tb_keys_tick.sv" *> "$dir/compile.log"
 if($LASTEXITCODE){throw "Compile failed: $dir/compile.log"}
 Push-Location $dir
 try{
  & "$sim/vsim.exe" -c -quiet -lib $lib tb_keys_tick @extra -l "$dir/tb.log" -do 'run -all; quit -f' *> "$dir/console.log"
  $log=Get-Content "$dir/tb.log" -Raw
  $pass=(-not $LASTEXITCODE) -and ($log -match 'PASS ') -and ($log -notmatch '\*\* (Fatal|Error|Warning)')
 }finally{Pop-Location}
 if($expectPass -and -not $pass){throw "Test failed: $dir/tb.log"}
 if(-not $expectPass -and $pass){throw "Mutant not detected: $dir"}
 if($expectPass){Write-Output "PASS $name $(([regex]'PASS [^\r\n]*').Match($log).Value)"}else{Write-Output "DETECTED $name"}
}
foreach($seed in 18,7,3){Run-Keys "seed$seed" $src $true @("-gSEED=$seed")}
# Mutants: no tick correction; debounce one tick short; KEY4 long press limit at 300 ms.
$mut=Join-Path $out 'mutant_src'; New-Item -ItemType Directory -Path $mut | Out-Null
$text=Get-Content $src -Raw
function Mutant([string]$name,[string]$from,[string]$to){
 if(-not $text.Contains($from)){throw "Mutant $name pattern missing"}
 $text.Replace($from,$to) | Set-Content "$mut/$name.v" -NoNewline
 Run-Keys "mut_$name" "$mut/$name.v" $false @()
}
Mutant 'no_adjust' 'localparam integer TICK_ADJ = MS_CYCLES > 1 ? 1 : 0;' 'localparam integer TICK_ADJ = 0;'
Mutant 'debounce' 'if (cnt >= DEBOUNCE_MS - 1) begin' 'if (cnt >= DEBOUNCE_MS - 2) begin'
Mutant 'long4' 'localparam LONG=1000+TICK_ADJ;' 'localparam LONG=300+TICK_ADJ;'
