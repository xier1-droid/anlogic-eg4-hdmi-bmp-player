param([string]$RunName='lut19_error_flag1')
# Lockstep check of fat32_pcm_stream error_flag; the mutant (flag never set) must be detected.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64';$td='d:/TD/anlogic/TD6.2.1/sim_release'
$hdl="$root/user_source/hdl_source"
$deps=@("$hdl/SD/fat32_file_streamer.v","$PSScriptRoot/fat32_pcm_stream_v018.v","$td/common/al_map_lut.v","$td/eg4/eg_logic_io.v","$td/eg4/eg_phy_glbl.v")
function Run-Case([string]$name,[string]$stream,[bool]$expectPass){
 $dir=Join-Path $out $name; New-Item -ItemType Directory -Path $dir | Out-Null
 $lib="$dir/work".Replace('\','/')
 & "$sim/vlib.exe" $lib *> "$dir/library.log"
 & "$sim/vlog.exe" -sv -work $lib "+incdir+$hdl/SD" "+incdir+$hdl/include" $stream @deps "$PSScriptRoot/tb_error_flag.sv" *> "$dir/compile.log"
 if($LASTEXITCODE){throw "Compile failed: $dir/compile.log"}
 Push-Location $dir
 try{
  & "$sim/vsim.exe" -c -quiet -lib $lib tb_error_flag glbl -l "$dir/tb_error_flag.log" -do 'run -all; quit -f' *> "$dir/console.log"
  $log=Get-Content "$dir/tb_error_flag.log" -Raw
  $pass=(-not $LASTEXITCODE) -and ($log -match 'PASS ') -and ($log -notmatch '\*\* (Fatal|Error|Warning)')
 }finally{Pop-Location}
 if($expectPass -and -not $pass){throw "Test failed: $dir/tb_error_flag.log"}
 if(-not $expectPass -and $pass){throw "Mutant not detected: $dir"}
 if($expectPass){Write-Output "PASS $name"}else{Write-Output "DETECTED $name"}
}
Run-Case 'equiv' "$hdl/audio/fat32_pcm_stream.v" $true
$mutant="$out/mut_no_flag.v"
$text=[IO.File]::ReadAllText("$hdl/audio/fat32_pcm_stream.v")
$mutated=$text.Replace("error_code<=fs_error;error_flag<=1;","error_code<=fs_error;")
if($mutated -eq $text){throw 'Mutation not applied'}
[IO.File]::WriteAllText($mutant,$mutated)
Run-Case 'mut_no_flag' $mutant $false
