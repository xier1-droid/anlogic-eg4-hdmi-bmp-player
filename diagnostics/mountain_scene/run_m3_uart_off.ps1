param([string]$RunName='m3_uart_off1')
# UART log/subtitle removal: tb_m3_uart_off compares the default top with the
# previous wiring, then a mutant (replaced fixed subtitle text) must be caught.
# The file list comes from the TD project, as the production top in run_m3.ps1.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
$sim='d:/modelsim/win64'
$td='d:/TD/anlogic/TD6.2.1'
$m='diagnostics/mountain_scene'
Push-Location "$root/TD_project"
try {
 [xml]$project=(Get-Content demo.al -Encoding UTF8 -Raw).Replace('UsedInP&R','UsedInP&amp;R')
 $rtl=@($project.SelectNodes('/Project/Source_Files/Verilog/File') | Where-Object {!$_.SelectSingleNode("FileInfo/Attr[@Name='AutoExcluded' and @Val='true']")} | ForEach-Object {$_.GetAttribute('Path')})
 $enc=@($rtl | Where-Object {$_ -like '*.enc.v'})
 $plain=@($rtl | Where-Object {$_ -notlike '*.enc.v' -and $_ -notlike '*sys_pll_s3.v'})
 $vendor=Get-ChildItem "$td/sim_release/eg4/*.v","$td/sim_release/common/*.v" | ForEach-Object {$_.FullName}
 foreach($case in @(@('normal',''),@('mutant','+define+MUTANT'))){
  $name=$case[0];$lib="$out/${name}_work".Replace('\','/')
  & "$sim/vlib.exe" $lib *> "$out/${name}_library.log"
  & "$sim/vlog.exe" -work $lib @vendor *> "$out/${name}_vendor.log"
  if($LASTEXITCODE){throw 'Vendor compile failed'}
  & "$sim/vlog.exe" -work $lib '../user_source/ip_source/s3_single_pll/sys_pll_s3.v' *> "$out/${name}_pll.log"
  if($LASTEXITCODE){throw 'PLL compile failed'}
  & "$sim/vlog.exe" -work $lib '+incdir+../user_source/hdl_source/include' @enc *> "$out/${name}_encrypted.log"
  if($LASTEXITCODE){throw 'Encrypted compile failed'}
  $defs=@('+define+SIMULATION');if($case[1]){$defs+=$case[1]}
  & "$sim/vlog.exe" -sv @defs -work $lib '+incdir+../user_source/hdl_source/include' @plain "$root/$m/tb_m3_uart_off.sv" *> "$out/${name}_compile.log"
  if($LASTEXITCODE){throw "Compile failed: $out/${name}_compile.log"}
  & "$sim/vsim.exe" -c -quiet -lib $lib tb_m3_uart_off glbl -l "$out/${name}.log" -do 'run -all; quit -f' *> "$out/${name}.console.log"
  $log=Get-Content "$out/${name}.log" -Raw
  $pass=!$LASTEXITCODE -and $log -notmatch '\*\* (Fatal|Error):' -and $log -match 'PASS UART removal'
  if($name -eq 'normal'){
   if(!$pass){throw "UART removal test failed: $out/${name}.log"}
   Write-Output ([regex]::Match($log,'PASS UART removal[^\r\n]*').Value)
  } else {
   if($pass -or $log -notmatch 'old [0-9a-f]+ new'){throw "Mutant not detected: $out/${name}.log"}
   Write-Output 'PASS mutant detected'
  }
 }
} finally { Pop-Location }
