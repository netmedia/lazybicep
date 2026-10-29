#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyBicep  -  initintoproject.ps1                                      ║
#  ║   Puts the kit into a project's infra folder, or updates it              ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyBicep  -  https://github.com/netmedia/lazybicep          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
.SYNOPSIS
    Puts LazyBicep into a project's infra folder (an empty instance), or updates the kit's files there.

.AUTHOR
    Netmedia  |  https://netmedia.agency  |  netmedia@netmedia.hr

.DESCRIPTION
    LazyBicep keeps a project's Azure infrastructure in one map (infra\infra.map.json) and sets it up,
    checks it, changes it and removes it environment by environment, with a terminal UI.

    New project:
      Copies the kit (infra\ of this repository: the files kit.json lists) and the starting
      naming.json into the target. Then, from the project's root, .\infra\lazybicep.ps1 (n: new
      project) or .\infra\azure-setup.ps1 -Init starts the project's map.

    Update (-Update):
      Replaces the kit's files in a project that has LazyBicep. The project's own files are never
      touched (infra.map.json, naming.json, environments\, README.md); a project's own extra catalog
      kinds stay. Then it checks whether main.bicep is still what the map makes.
      A project from when the kit was LazyAzure loses lazyazure.ps1, lazyazure.exe and LAZYAZURE.md
      (and the root's lazyazure.exe): lazybicep.* replaces them.

.PARAMETER Target
    (Required) The project's infra folder, e.g. D:\Development\Netmedia\MyProject\infra.
    Created when missing. A folder not named infra (or infrastructure, iac, azure, bicep, deploy)
    asks: create <Target>\infra there (Yes), or put the kit right into <Target> (No).

.PARAMETER Update
    Update the kit's files of a project that has LazyBicep.

.PARAMETER DryRun
    Show what would be copied, change nothing.

.PARAMETER Help
    Display the usage guide and exit.

.EXAMPLE
    # A new project
    .\initintoproject.ps1 D:\Development\Netmedia\MyProject\infra

.EXAMPLE
    # A project's kit up to date with this repository
    .\initintoproject.ps1 D:\Development\Netmedia\MyProject\infra -Update

.NOTES
    LazyBicep is a Netmedia product: https://netmedia.agency, netmedia@netmedia.hr,
    https://github.com/netmedia/lazybicep. Documentation: infra\LAZYBICEP.md.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Target,

    [Alias('h')]
    [switch]$Help,

    [switch]$Update,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$kit = Join-Path $PSScriptRoot 'infra'
$manifest = Get-Content (Join-Path $kit 'kit.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# --- OUTPUT HELPERS ---------------------------------------------------------------------------------------

function Write-Banner([string]$msg) {
    $pad = 60
    $line = [string]::new([char]0x2500, $pad)
    Write-Host "`n  $([char]0x256D)$line$([char]0x256E)" -ForegroundColor Cyan
    Write-Host "  $([char]0x2502)  $($msg.PadRight($pad - 2))$([char]0x2502)" -ForegroundColor Cyan
    Write-Host "  $([char]0x2570)$line$([char]0x256F)`n" -ForegroundColor Cyan
}
function Write-OK([string]$msg) { Write-Host "  $([char]0x2713) $msg" -ForegroundColor Green }
function Write-Skip([string]$msg) { Write-Host "  $([char]0x00B7) $msg" -ForegroundColor DarkGray }
function Write-Info([string]$msg) { Write-Host "  $([char]0x2139) $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host "  $([char]0x26A0) $msg" -ForegroundColor Magenta }
function Write-Err([string]$msg) { Write-Host "  $([char]0x2717) $msg" -ForegroundColor Red }

function Show-Author {
    $width = 64
    $hLine = [string]::new([char]0x2500, $width)
    $v = [char]0x2502
    $esc = [char]27
    function Row([string]$display, [string]$measure = $display, [string]$color = 'White') {
        $pad = [Math]::Max(0, $width - $measure.Length)
        $left = [Math]::Floor($pad / 2)
        Write-Host "  $v" -NoNewline -ForegroundColor Cyan
        Write-Host "$(' ' * $left)$display$(' ' * ($pad - $left))" -NoNewline -ForegroundColor $color
        Write-Host $v -ForegroundColor Cyan
    }
    $title = 'LazyBicep  -  initintoproject.ps1'
    Write-Host ''
    Write-Host "  $([char]0x256D)$hLine$([char]0x256E)" -ForegroundColor Cyan
    Row ''
    Row "$esc[1m$title$esc[0m" $title 'Cyan'
    Row 'A project''s Azure infrastructure from one map' -color 'White'
    Row 'puts the kit into a project, or updates it there' -color 'White'
    Row ''
    Row "by Netmedia  |  LazyBicep $($manifest.version)" -color 'DarkGray'
    Row 'https://netmedia.agency  |  netmedia@netmedia.hr' -color 'DarkGray'
    Row ''
    Write-Host "  $([char]0x2570)$hLine$([char]0x256F)" -ForegroundColor Cyan
    Write-Host ''
}

function Show-Usage {
    $hr = '  ' + [string]::new([char]0x2500, 66)
    $b = { param($t) Write-Host "  $t" -ForegroundColor White }
    $d = { param($t) Write-Host "  $t" -ForegroundColor DarkGray }
    $g = { param($t) Write-Host "  $t" -ForegroundColor Green }
    $y = { param($t) Write-Host "  $t" -ForegroundColor Yellow }
    & $b 'USAGE'
    & $g '  .\initintoproject.ps1  <Target>  [-Update]  [-DryRun]'
    Write-Host ''
    & $b 'ARGUMENTS'
    & $y '  <Target>  (required)'
    & $d '    The project''s infra folder, e.g. D:\Development\Netmedia\MyProject\infra.'
    & $d '    Created when missing. Not named infra (or infrastructure, iac, azure, bicep,'
    & $d '    deploy): asks whether to create <Target>\infra (Yes) or use <Target> as is (No).'
    Write-Host ''
    & $b 'OPTIONS'
    & $y '  -Update'
    & $d '    The project has LazyBicep: replace the kit''s files (kit.json lists them), keep'
    & $d '    the project''s (infra.map.json, naming.json, environments\, README.md).'
    & $y '  -DryRun'
    & $d '    Show what would be copied; change nothing.'
    & $y '  -Help  (-h)'
    & $d '    Show this usage guide and exit.'
    Write-Host ''
    & $b 'EXAMPLES'
    & $g '  # A new project: the kit into its infra folder'
    & $g '  .\initintoproject.ps1  D:\Development\Netmedia\MyProject\infra'
    Write-Host ''
    & $g '  # A project''s kit up to date with this repository'
    & $g '  .\initintoproject.ps1  D:\Development\Netmedia\MyProject\infra  -Update'
    Write-Host ''
    & $b 'THEN, FROM THE PROJECT''S ROOT'
    & $d '  1. .\lazybicep.exe   (or .\infra\lazybicep.ps1)    n: a new project (name, prefix,'
    & $d '                                                 then its resources from the catalog)'
    & $d '     or .\infra\azure-setup.ps1 -Init -SpecFile spec.json   (examples\spec.example.json)'
    & $d '  2. .\infra\azure-setup.ps1 -DryRun -Environment test   what would be created'
    & $d '  3. .\infra\azure-setup.ps1 -Start  -Environment test   creates it'
    & $d '  4. commit infra\ (the map, naming.json, main.bicep, environments\)'
    Write-Host ''
    & $d '  Everything about it: infra\LAZYBICEP.md'
    Write-Host $hr -ForegroundColor Cyan
    Write-Host ''
}

# ==========================================================================================================
# MAIN EXECUTION
# ==========================================================================================================

Show-Author

if ($Help -or [string]::IsNullOrWhiteSpace($Target)) {
    if (-not $Help) { Write-Host "`n  ERROR: <Target> is required." -ForegroundColor Red }
    Show-Usage
    exit 0
}

$Target = [IO.Path]::GetFullPath($Target).TrimEnd('\', '/')
# A path that isn't an infra folder (e.g. the project's root): the kit into <Target>\infra, or right there?
$infraNames = @('infra', 'infrastructure', 'iac', 'azure', 'bicep', 'deploy')
if (-not (Test-Path (Join-Path $Target 'azure-setup.ps1')) -and $infraNames -notcontains (Split-Path $Target -Leaf).ToLowerInvariant()) {
    $sub = Join-Path $Target 'infra'
    Write-Warn "$Target doesn't look like an infra folder."
    Write-Host "    Yes: create $sub and put LazyBicep there (lazybicep.exe goes into $Target)" -ForegroundColor DarkGray
    Write-Host "    No:  put it right into $Target" -ForegroundColor DarkGray
    $answer = Read-Host '  Create the infra folder? [Y/n]'
    if ($null -eq $answer) { $answer = '' }
    if ($answer.Trim() -notmatch '^(n|no)$') { $Target = $sub }
}
$has =Test-Path (Join-Path $Target 'azure-setup.ps1')
if ($has -and -not $Update) { Write-Err "$Target has LazyBicep already: -Update replaces the kit's files there."; exit 1 }
if (-not $has -and $Update) { Write-Err "$Target has no LazyBicep to update: leave -Update out to put it there."; exit 1 }
if ($DryRun) { Write-Host "`n  == DRY RUN - nothing is copied ==" -ForegroundColor Cyan }

$mode = 'new project'
if ($Update) { $mode = 'update' }
Write-Banner "[1/2] LazyBicep $($manifest.version) -> $mode"
Write-Info "kit:    $kit"
Write-Info "target: $Target"
$before = $null
if ($Update -and (Test-Path (Join-Path $Target 'kit.json'))) { $before = (Get-Content (Join-Path $Target 'kit.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version }
if ($before) { Write-Info "the project has LazyBicep $before" }
Write-Host ''
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $Target | Out-Null }
foreach ($f in @($manifest.files)) {
    $from = Join-Path $kit $f
    $to = Join-Path $Target $f
    if ($DryRun) { Write-Skip "would copy $f"; continue }
    if (Test-Path $from -PathType Container) {
        New-Item -ItemType Directory -Force -Path $to | Out-Null
        Copy-Item -Path (Join-Path $from '*') -Destination $to -Recurse -Force
    } else { Copy-Item -Path $from -Destination $to -Force }
    Write-OK $f
}
if (-not $Update) {
    if ($DryRun) { Write-Skip 'would copy naming.json (the project''s from then on)' }
    else {
        Copy-Item -Path (Join-Path $kit 'naming.json') -Destination (Join-Path $Target 'naming.json') -Force
        Write-OK 'naming.json (the project''s from now on)'
    }
} else {
    foreach ($p in @($manifest.projectFiles)) { if (Test-Path (Join-Path $Target $p)) { Write-Skip "kept: $p (the project's)" } }
    # The kit was LazyAzure before: its files under the old name go (lazybicep.* replaces them).
    $legacy = @('lazyazure.ps1', 'lazyazure.exe', 'LAZYAZURE.md' | ForEach-Object { Join-Path $Target $_ }) + @(Join-Path (Split-Path $Target -Parent) 'lazyazure.exe')
    foreach ($old in $legacy) {
        if (-not (Test-Path $old -PathType Leaf)) { continue }
        if ($DryRun) { Write-Skip "would remove $old (the kit's old name)"; continue }
        try { Remove-Item $old -Force; Write-OK "removed $old (the kit's old name)" }
        catch { Write-Warn "$old`: $($_.Exception.Message) (is it running? close it and run this again)" }
    }
}
# lazybicep.exe in the project's root as well: it starts infra\lazybicep.ps1, so lazybicep runs from there.
$projectRoot = Split-Path $Target -Parent
foreach ($f in @($manifest.rootFiles)) {
    if (-not $f) { continue }
    if ($DryRun) { Write-Skip "would copy $f to the project's root ($projectRoot)"; continue }
    try {
        Copy-Item -Path (Join-Path $kit $f) -Destination (Join-Path $projectRoot $f) -Force
        Write-OK "$f in the project's root ($projectRoot)"
    } catch { Write-Warn "$f in the project's root: $($_.Exception.Message) (is it running? close it and run this again)" }
}

Write-Banner '[2/2] Next'
if ($DryRun) { Write-Info 'Run it again without -DryRun to copy.'; exit 0 }
if (-not $Update) {
    Write-OK "LazyBicep $($manifest.version) is in $Target."
    Write-Host ''
    Write-Host '  From the project''s root:' -ForegroundColor White
    Write-Host '    .\lazybicep.exe                                 n: a new project (also .\infra\lazybicep.exe)' -ForegroundColor Green
    Write-Host '    .\infra\azure-setup.ps1 -Init [-SpecFile spec.json]' -ForegroundColor Green
    Write-Host '    .\infra\azure-setup.ps1 -Help                   every mode and option' -ForegroundColor Green
    Write-Host ''
    exit 0
}
Write-OK "LazyBicep $before -> $($manifest.version) in $Target."
if (Test-Path (Join-Path $Target 'infra.map.json')) {
    & (Join-Path $Target 'generate.ps1') -Check -Quiet
    if ($LASTEXITCODE -eq 0) { Write-OK 'main.bicep is still what the map makes.' }
    else { Write-Warn 'main.bicep changes with this kit: run .\infra\generate.ps1, then a dry run shows what that means in Azure.' }
}
Write-Host ''
