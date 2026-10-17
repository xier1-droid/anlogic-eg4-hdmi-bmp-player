param([string]$RunName='m3v3_syn1',[string]$Source='')
# Synthesize hazard_layer alone (gate level, TD 6.2.1) and print its LUT, DSP
# and register count, to compare RTL variants without a full build. Numbers
# are standalone: they include no cross-module optimization.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root "diagnostics/output/$RunName"
if(Test-Path $out){throw 'Choose a new RunName'}
New-Item -ItemType Directory -Path $out | Out-Null
if(!$Source){$Source="$root/user_source/hdl_source/scene/hazard_layer.v"}
$src=$Source.Replace('\','/')
$prj=@"
<?xml version="1.0" encoding="UTF-8"?>
<Project Version="1" Path="$($out.Replace('\','/'))">
 <Project_Created_Time></Project_Created_Time>
 <TD_Version>6.2.168116</TD_Version>
 <Name>hz</Name>
 <HardWare><Family>EG4</Family><Device>EG4S20BG256</Device><Speed></Speed></HardWare>
 <Source_Files><Verilog><File Path="$src"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="1"/></FileInfo></File></Verilog></Source_Files>
 <FileSets><FileSet Name="design_1" Type="DesignFiles"></FileSet></FileSets>
 <TOP_MODULE><LABEL></LABEL><MODULE>hazard_layer</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE>
</Project>
"@
[IO.File]::WriteAllText("$out/hz.prj",$prj,[Text.UTF8Encoding]::new($false))
$tcl=@"
import_device eagle_s20.db -package EG4S20BG256
open_project {$($out.Replace('\','/'))/hz.prj}
elaborate -top hazard_layer
optimize_rtl
optimize_gate -packarea hz_gate.area
report_area -file hz_gate.area
exit
"@
[IO.File]::WriteAllText("$out/syn.tcl",$tcl,[Text.UTF8Encoding]::new($false))
Push-Location $out
try{
 & 'd:/TD/anlogic/TD6.2.1/bin/td_commands_prompt.exe' "$($out.Replace('\','/'))/syn.tcl" *> "$out/syn.log"
 if(!(Test-Path "$out/hz_gate.area")){throw "synthesis failed: $out/syn.log"}
 $a=Get-Content "$out/hz_gate.area" -Raw
 $lut=[regex]::Match($a,'#lut\s+(\d+)').Groups[1].Value
 $reg=[regex]::Match($a,'#reg\s+(\d+)').Groups[1].Value
 $dsp=[regex]::Match($a,'#dsp\s+(\d+)').Groups[1].Value
 Write-Output "hazard_layer standalone: lut=$lut reg=$reg dsp=$dsp ($Source)"
}finally{Pop-Location}
