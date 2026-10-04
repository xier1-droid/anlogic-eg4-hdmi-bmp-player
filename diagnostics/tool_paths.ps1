param([string]$SimTools = '', [string]$TdRoot = '')
$simCandidates = @($SimTools, $env:MODELSIM_BIN, 'F:/modelsim/win64', 'D:/modelsim/win64') | Where-Object { $_ }
$simTools = $simCandidates | Where-Object { Test-Path (Join-Path $_ 'vsim.exe') } | Select-Object -First 1
if (-not $simTools) { throw 'ModelSim not found; set MODELSIM_BIN to its executable directory.' }
$tdCandidates = @($TdRoot, $env:TD_ROOT, 'E:/TD', 'D:/TD/anlogic/TD6.2.1') | Where-Object { $_ }
$tdRoot = $tdCandidates | Where-Object { Test-Path (Join-Path $_ 'bin/td_commands_prompt.exe') } | Select-Object -First 1
if (-not $tdRoot) { throw 'TD not found; set TD_ROOT to its installation root.' }
$vendor = Join-Path $tdRoot 'sim_release/eg4'
$pythonCandidates = @($env:PYTHON_EXE, (Join-Path $env:LOCALAPPDATA 'Python/pythoncore-3.14-64/python.exe')) | Where-Object { $_ }
$pythonExe = $pythonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $pythonExe) { $pythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source }
if (-not $pythonExe) { throw 'Python 3 not found; set PYTHON_EXE to its executable path.' }
