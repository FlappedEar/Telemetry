# Runs the NSIS installer (installer.nsi) silently against the real per-user
# folder and checks that it never touches a folder it does not own: default
# install, a /D= attempt at a decoy folder with a sentinel file, a running app,
# a misplaced uninstaller, uninstall, and a foreign folder at the install path.
#
# Run it on a disposable Windows machine such as a CI runner: it installs and
# removes "%LOCALAPPDATA%\Programs\FlappedEar Telemetry" and refuses to start
# when that folder already exists.
#
#   ./test-installer.ps1 -ReleaseDir <flutter build windows output, .../Release>
param([Parameter(Mandatory)][string]$ReleaseDir)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$canonical = Join-Path $env:LOCALAPPDATA 'Programs\FlappedEar Telemetry'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\FlappedEarTelemetry'
$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\FlappedEar Telemetry.lnk'
$work = Join-Path ([IO.Path]::GetTempPath()) ('fe-installer-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$decoy = Join-Path $work 'decoy'            # no spaces: /D= must not be quoted
$decoy2 = Join-Path $work 'decoy2'
$setup = Join-Path $work 'setup.exe'
$script:app = $null

function Assert([bool]$condition, [string]$message) {
  if (-not $condition) { throw "FAILED: $message" }
  Write-Host "ok: $message"
}

function Run([string]$file, [string[]]$arguments) {
  $process = Start-Process -FilePath $file -ArgumentList $arguments -Wait -PassThru
  $process.WaitForExit()
  return $process.ExitCode
}

function Install([string[]]$arguments = @()) { Run $setup (@('/S') + $arguments) }

function Reset-Decoy([string]$path) {
  New-Item -ItemType Directory -Force (Join-Path $path 'nested') | Out-Null
  Set-Content (Join-Path $path 'sentinel.txt') 'keep'
  Set-Content (Join-Path $path 'nested\sentinel.txt') 'keep'
}

function Assert-DecoyIntact([string]$path) {
  Assert (Test-Path (Join-Path $path 'sentinel.txt')) "$path keeps sentinel.txt"
  Assert (Test-Path (Join-Path $path 'nested\sentinel.txt')) "$path keeps nested\sentinel.txt"
  Assert (-not (Test-Path (Join-Path $path 'telemetry.exe'))) "$path got no app files"
}

function Wait-Gone([string]$path, [int]$seconds = 90) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Test-Path $path) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
  return -not (Test-Path $path)
}

function Find-Makensis {
  $found = Get-Command makensis -ErrorAction SilentlyContinue
  if ($found) { return $found.Source }
  $default = Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe'
  if (-not (Test-Path $default)) { choco install nsis -y --no-progress | Out-Host }
  if (-not (Test-Path $default)) { throw 'makensis was not found and could not be installed.' }
  return $default
}

if (Test-Path $canonical) { throw "$canonical exists; run this on a disposable machine." }
if (-not (Test-Path (Join-Path $ReleaseDir 'telemetry.exe'))) { throw "$ReleaseDir has no telemetry.exe." }

New-Item -ItemType Directory -Force $work | Out-Null
try {
  & (Find-Makensis) -V2 "-DVERSION=0.0.0" "-DSOURCE_DIR=$((Resolve-Path $ReleaseDir).Path)" "-DOUTFILE=$setup" (Join-Path $here 'installer.nsi')
  if ($LASTEXITCODE -ne 0) { throw 'makensis failed.' }
  Reset-Decoy $decoy
  Reset-Decoy $decoy2

  Write-Host '== default install'
  Assert ((Install) -eq 0) 'silent install exits 0'
  Assert (Test-Path "$canonical\telemetry.exe") 'telemetry.exe is installed'
  Assert (Test-Path "$canonical\Uninstall.exe") 'Uninstall.exe is installed'
  Assert (Test-Path "$canonical\.flappedear-telemetry-install") 'install marker is written'
  Assert (-not (Test-Path "$canonical.new") -and -not (Test-Path "$canonical.old")) 'no staging leftovers'
  Assert (Test-Path $shortcut) 'Start menu shortcut exists'
  Assert ((Get-ItemProperty $uninstallKey).InstallLocation -eq $canonical) 'registry InstallLocation is the fixed folder'

  Write-Host '== /D= pointing at a folder with a sentinel file, over an existing install'
  Set-Content "$canonical\stale.dll" 'old'
  New-Item -ItemType Directory "$canonical\data" -Force | Out-Null
  Set-Content "$canonical\data\stale.bin" 'old'
  Assert ((Install @("/D=$decoy")) -eq 0) 'install with /D= exits 0 (the argument is ignored)'
  Assert-DecoyIntact $decoy
  Assert (Test-Path "$canonical\telemetry.exe") 'app is in the fixed folder'
  Assert (-not (Test-Path "$canonical\stale.dll") -and -not (Test-Path "$canonical\data\stale.bin")) 'files of the old version are gone after the update'
  Assert ((Get-ItemProperty $uninstallKey).InstallLocation -eq $canonical) 'registry InstallLocation is still the fixed folder'

  Write-Host '== update while the app runs'
  Copy-Item "$env:SystemRoot\System32\cmd.exe" "$canonical\telemetry.exe" -Force
  $script:app = Start-Process "$canonical\telemetry.exe" -ArgumentList '/c', 'ping -n 600 127.0.0.1 > nul' -WindowStyle Hidden -PassThru
  Start-Sleep -Seconds 2
  Set-Content "$canonical\stale.dll" 'old'
  Assert ((Install) -ne 0) 'install stops while the app runs'
  Assert (Test-Path "$canonical\stale.dll") 'the running install was not changed'
  Assert (-not (Test-Path "$canonical.new") -and -not (Test-Path "$canonical.old")) 'no staging leftovers after the refusal'
  Stop-Process -Id $script:app.Id -Force
  $script:app.WaitForExit()
  Assert ((Install) -eq 0) 'install works once the app is closed'
  Assert (-not (Test-Path "$canonical\stale.dll")) 'update replaced the old files'

  Write-Host '== uninstaller started in another folder'
  Copy-Item "$canonical\Uninstall.exe" "$decoy2\Uninstall.exe"
  Copy-Item "$canonical\.flappedear-telemetry-install" "$decoy2\.flappedear-telemetry-install"
  Assert ((Run "$decoy2\Uninstall.exe" @('/S', "_?=$decoy2")) -ne 0) 'uninstaller refuses a folder other than the fixed one'
  Assert (Test-Path "$decoy2\sentinel.txt") 'decoy2 keeps sentinel.txt'
  Assert (Test-Path "$decoy2\nested\sentinel.txt") 'decoy2 keeps nested\sentinel.txt'
  Assert (Test-Path "$canonical\telemetry.exe") 'the install is untouched'

  Write-Host '== uninstall'
  $null = Start-Process "$canonical\Uninstall.exe" -ArgumentList '/S' -PassThru
  Assert (Wait-Gone $canonical) 'the install folder is removed'
  Assert (Wait-Gone $uninstallKey) 'registry key is removed'
  Assert (-not (Test-Path $shortcut)) 'Start menu shortcut is removed'
  Assert-DecoyIntact $decoy

  Write-Host '== a foreign folder at the install path'
  New-Item -ItemType Directory $canonical -Force | Out-Null
  Set-Content "$canonical\mine.txt" 'keep'
  Assert ((Install) -ne 0) 'install refuses a folder it did not create'
  Assert (Test-Path "$canonical\mine.txt") 'the foreign file survives'
  Assert (-not (Test-Path "$canonical\telemetry.exe")) 'nothing was written into it'
  Remove-Item $canonical -Recurse -Force

  Write-Host '== an empty folder at the install path'
  New-Item -ItemType Directory $canonical -Force | Out-Null
  Assert ((Install) -eq 0) 'install into an empty folder works'
  Assert (Test-Path "$canonical\telemetry.exe") 'telemetry.exe is installed'
  $null = Start-Process "$canonical\Uninstall.exe" -ArgumentList '/S' -PassThru
  Assert (Wait-Gone $canonical) 'the install folder is removed again'
  Assert-DecoyIntact $decoy
  Write-Host 'Installer checks passed.'
}
finally {
  if ($script:app -and -not $script:app.HasExited) { Stop-Process -Id $script:app.Id -Force }
  Remove-Item $canonical, "$canonical.new", "$canonical.old" -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $shortcut -Force -ErrorAction SilentlyContinue
  Remove-Item $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
