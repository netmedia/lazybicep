#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyBicep  -  azure-setup.ps1                                          ║
#  ║   A project's Azure infrastructure from one map: set up, check, change   ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyBicep  -  https://github.com/netmedia/lazybicep          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
.SYNOPSIS
LazyBicep by Netmedia: creates, checks and updates the whole Azure infrastructure of one environment, as
infra/infra.map.json maps it; adds and removes resources of the map; starts the map of a new project.

.AUTHOR
Netmedia  |  https://netmedia.agency  |  netmedia@netmedia.hr

.DESCRIPTION
LazyBicep (infra/LAZYBICEP.md). One environment (prod, test, stag, dev, accp) with the Azure CLI.
infra/infra.map.json lists its resources (apps, databases, queues, vaults, telemetry...), how they are
named, asked, connected and checked; infra/main.bicep, generated from it by infra/generate.ps1, creates
them. Then the apps' database users, the GitHub -> Azure trust, the GitHub environment with its variables
and deployment tokens, and the custom domains. infra/lazybicep.ps1 is the same in a terminal UI.

It also changes the map: -AddResource adds a resource of the catalog (infra/catalog) with its
connections, -RemoveResource takes one out, -Init starts the map of a new project.

It asks for the environment and every name (defaults from the naming rules in infra/naming.json, then
from the environment's saved answers), checks every step and only does what is missing, each change
asked first. Enter accepts the value in brackets; '<' goes back to the previous question (until the
answers are saved and the first change is made). When the environment's answers are saved, it first asks
"Change anything?": no (the default) keeps them all and goes straight on; yes goes through the questions.

  0. Answers: environment, subscription, prefix, the sub application name of each deployment target,
     region, every name and size of the map's resources, custom domains, the GitHub repository and the
     branch that deploys to the environment. A name found in the subscription is used (shared resources
     also from another resource group, as they are); a new one is created. Saved in
     infra/environments/<env>.json (commit it).
  1. Azure resources: resource providers, the resource group, infra/main.bicep (what-if shown first). A
     container app keeps the image it runs (a new one starts with the placeholder until its workflow runs);
     one with sign-in gets its app registration (Sign-in app registrations), then main.bicep again.
  2. GitHub -> Azure trust (OIDC): app registration, service principal, federated credential for the
     GitHub environment, the deploy role on each app.
  3. GitHub environment: deployments only from its branch, the map's variables and the Static Web Apps'
     deployment tokens (with the GitHub CLI; without it the script prints what to set by hand).
  4. Custom domains: shows the DNS records and checks them until they resolve ('s' skips), then adds
     the domains with free certificates.
  5. Live: the checks the map lists (an API's health and version, a web app's home page...).
  The end lists everything still open.

Idempotent: a second run with the same answers changes nothing. Everything is looked up before it is
created; the template is deployed only when what-if shows a real change; a secret the setup keeps keeps its
value and is written to the vault only when missing or different; the deployment token is set in GitHub
only when missing, when its Static Web App is new, or with -RefreshToken. The Azure CLI's default subscription
is never changed.

Run without a switch, it shows this help and then asks what to do:
  1. Dry run - asks every question, shows what would be created or changed; changes nothing.
  2. Check   - checks an environment that is set up, with its saved answers and no questions; changes
               nothing.
  3. Start   - asks every question, then creates and updates what is missing, each change asked first.
  4. Remove all - deletes what the setup created for an environment: shown first, confirmed by typing the
               resource group's name.

.PARAMETER DryRun
Dry run without the menu: asks every question (Enter = the value in brackets), compares Azure and GitHub
with the answers and reports what would be created or changed. Changes nothing, saves nothing. Exits with
1 when anything is still open.

.PARAMETER Check
Check without the menu: takes every answer from infra/environments/<env>.json (no questions besides the
environment) and reports what is in place and what is missing. Changes nothing. Exits with 1 when
anything is still open; for scheduled checks or before a release.

.PARAMETER Remove
Removes what the setup created for an environment (from its saved answers): the resources the template
made, with the resource group when nothing else is in it, the app registration GitHub Actions deploys
with, and the GitHub environment. Shared resources from other groups and anything else are kept. All of
it is shown first and confirmed by typing the resource group's name; the Key Vault can be purged (asked,
no by default), the saved answers deleted (asked, no by default). The DNS records are listed to remove by
hand.

.PARAMETER Start
Start without the menu: asks every question, then creates and updates what is missing, each change asked
first.

.PARAMETER Environment
The environment to start with: prod, test, stag, dev or accp (infra/naming.json). Without it, the
script asks (default prod).

.PARAMETER RefreshToken
Also sets the Static Web Apps' deployment tokens in the GitHub environment again, e.g. after resetting one in the
Azure portal.

.PARAMETER Currency
Currency of the estimated monthly cost (Azure list prices from prices.azure.com): EUR by default, or USD,
GBP...

.PARAMETER Ui
For infra/lazybicep.ps1: writes events instead of text (one JSON object per line, after '@@ui ') and
reads the answers from standard input, one per line. Needs -DryRun, -Check, -Start or -Remove.

.PARAMETER AddResource
Adds a resource of the catalog to infra/infra.map.json (what it needs, which apps use it), then generates
and compiles main.bicep. Nothing in Azure changes.

.PARAMETER Kind
With -AddResource: the kind to add (sqlDatabase, serviceBus, storageQueue, functionApp, appService...).

.PARAMETER RemoveResource
Takes a resource out of the map with everything that refers to it, then generates main.bicep. Azure keeps
the resource (the end says how to delete it).

.PARAMETER Key
With -RemoveResource: the resource's key in the map.

.PARAMETER Init
Starts the map of a new project (an empty instance): its name and prefix, then its resources. First asks
whether to analyze the solution (infra/analyze.ps1 suggests the resources) or to add them by hand.

.PARAMETER Analyze
With -Init: analyzes the solution without asking (infra/analyze.ps1). Each suggested resource is offered
with what it was found from; the usual questions follow, with its answers as their defaults.

.PARAMETER Import
With -Init or -AddResource: imports from Azure without asking first (infra/import.ps1): the subscription, the resource
groups and their resources are asked; each suggested resource is offered, and the real names become the
environment's answers.

.PARAMETER ResourceGroup
With -Init -Import: the resource groups to import from (comma-separated); asked when left out.

.PARAMETER SpecFile
With -Init: a spec file with the project and its resources (infra/LAZYBICEP.md, "A new project"); no
questions.

.PARAMETER Help
Shows this help.

.EXAMPLE
.\infra\azure-setup.ps1
Shows the help, then asks: dry run, check or start.

.EXAMPLE
.\infra\azure-setup.ps1 -DryRun
Asks the questions, shows what exists and what would be created or changed, changes nothing.

.EXAMPLE
.\infra\azure-setup.ps1 -Check -Environment prod
Checks production with its saved answers, without questions.

.EXAMPLE
.\infra\azure-setup.ps1 -Start -Environment test
Sets up (or updates) the test environment.

.EXAMPLE
.\infra\azure-setup.ps1 -Start -RefreshToken
Also puts the Static Web Apps' current deployment tokens into GitHub again.

.NOTES
Needs: the Azure CLI signed in (az login; add --tenant if the subscription is in another tenant), Owner
(or Contributor + User Access Administrator) on the subscription and the right to create app
registrations; the GitHub CLI signed in (gh auth login) as an admin of the repository for step 3.
Runs in Windows PowerShell 5.1 and PowerShell 7, from the repository root. If scripts are blocked:
powershell -ExecutionPolicy Bypass -File .\infra\azure-setup.ps1

LazyBicep is a Netmedia product: https://netmedia.agency, netmedia@netmedia.hr,
https://github.com/netmedia/lazybicep.

.LINK
infra/LAZYBICEP.md
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Check,
    [switch]$Start,
    [Alias('RemoveAll')]
    [switch]$Remove,
    [string]$Environment,
    [switch]$RefreshToken,
    [Alias('h')]
    [switch]$Help,
    [string]$Currency = 'EUR',
    [switch]$Ui,
    [switch]$AddResource,
    [string]$Kind,
    [switch]$RemoveResource,
    [string]$Key,
    [switch]$Init,
    [switch]$Analyze,
    [switch]$Import,
    [string[]]$ResourceGroup,
    [string]$SpecFile
)

# --- Netmedia: who made it, how to use it ---------------------------------------------------------------

$kitVersion = ''
if (Test-Path (Join-Path $PSScriptRoot 'kit.json')) { $kitVersion = (Get-Content (Join-Path $PSScriptRoot 'kit.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version }

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
    $title = 'LazyBicep  -  azure-setup.ps1'
    Write-Host ''
    Write-Host "  $([char]0x256D)$hLine$([char]0x256E)" -ForegroundColor Cyan
    Row ''
    Row "$esc[1m$title$esc[0m" $title 'Cyan'
    Row 'A project''s Azure infrastructure from one map' -color 'White'
    Row 'set up, checked, changed and removed per environment' -color 'White'
    Row ''
    Row "by Netmedia$(if ($kitVersion) { "  |  LazyBicep $kitVersion" })" -color 'DarkGray'
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
    $kinds = @()
    if (Test-Path (Join-Path $PSScriptRoot 'catalog')) {
        $kinds = @(Get-ChildItem (Join-Path $PSScriptRoot 'catalog') -Filter '*.json' | Where-Object { $_.Name -ne 'roles.json' } |
                ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Where-Object { $_.addable } | ForEach-Object { $_.kind } | Sort-Object)
    }
    & $b 'USAGE'
    & $g '  .\infra\azure-setup.ps1  [mode]  [-Environment <env>]  [options]'
    & $g '  .\infra\lazybicep.ps1                         # the same in a terminal UI'
    & $d '  Run from the repository root. Without a mode: this guide, then a menu.'
    Write-Host ''
    & $b 'ENVIRONMENT MODES  (Azure; every change asked first)'
    & $y '  -DryRun'
    & $d '    Asks every question, shows what exists and what would be created or changed.'
    & $d '    Changes and saves nothing. The safe first run.'
    & $y '  -Check'
    & $d '    An environment that is set up: its saved answers, no questions; reports what is'
    & $d '    in place and what is missing. Changes nothing (exit 1 when anything is open).'
    & $y '  -Start'
    & $d '    Asks every question, then creates and updates what is missing: resources,'
    & $d '    database users, GitHub -> Azure trust (OIDC), GitHub environment, domains.'
    & $y '  -Remove  (-RemoveAll)'
    & $d '    Deletes what the setup created for an environment: shown first, confirmed by'
    & $d '    typing the resource group''s name. Shared resources and DNS stay.'
    Write-Host ''
    & $b 'MAP MODES  (infra/infra.map.json; nothing in Azure changes)'
    & $y '  -AddResource  [-Kind <kind> | -Import [-ResourceGroup <rg>,...]]'
    & $d '    Adds a resource of the catalog with its connections (what it needs, which'
    & $d '    apps use it), then generates and compiles main.bicep. Or imports resources'
    & $d '    from Azure (asked first; -Import: without asking): connected, their names go'
    & $d '    into the environment''s answers; what the map has already is left out.'
    & $y '  -RemoveResource  -Key <key>'
    & $d '    Takes a resource out of the map with everything that refers to it; then'
    & $d '    offers to DELETE it from Azure (no by default; per environment its exact name'
    & $d '    typed, "delete prod" too for production; only what the setup made).'
    & $y '  -Init  [-Analyze | -Import [-ResourceGroup <rg>,...]]  [-SpecFile <spec.json>]'
    & $d '    Starts the map of a new project (an empty instance). Asks first: analyze the'
    & $d '    solution (infra/analyze.ps1 suggests the apps, databases, Service Bus, storage,'
    & $d '    Key Vault, Application Insights), import from Azure (infra/import.ps1: pick'
    & $d '    resource groups and resources; their real names become the environment''s'
    & $d '    answers), or add the resources by hand. Each suggestion is offered, then the'
    & $d '    usual questions. -Analyze / -Import: without asking. A spec file answers all.'
    Write-Host ''
    & $b 'OPTIONS'
    & $y '  -Environment <env>'
    & $d "    $((@($naming.environments.PSObject.Properties | ForEach-Object { $_.Name })) -join ', ') (infra/naming.json); asked when left out."
    & $y '  -RefreshToken'
    & $d '    Puts a Static Web App''s deployment token into GitHub again (after a reset).'
    & $y '  -Currency <EUR|USD|GBP...>'
    & $d '    Currency of the estimated monthly cost (Azure list prices). Default EUR.'
    & $y '  -Help  (-h)'
    & $d '    Shows this guide and exits.'
    Write-Host ''
    if ($kinds.Count) {
        & $b 'KINDS  (infra/catalog; several of one kind are fine)'
        # Wrapped to the width of the guide.
        $line = ' '
        foreach ($k in $kinds) {
            if (($line + $k).Length -gt 76) { & $d "  $($line.TrimEnd())"; $line = ' ' }
            $line += "$k  "
        }
        & $d "  $($line.TrimEnd())"
        Write-Host ''
    }
    & $b 'EXAMPLES'
    & $g '  # A new environment: preview, then create it'
    & $g '  .\infra\azure-setup.ps1 -DryRun -Environment test'
    & $g '  .\infra\azure-setup.ps1 -Start  -Environment test'
    Write-Host ''
    & $g '  # Is production as the map says? (before a release; no questions)'
    & $g '  .\infra\azure-setup.ps1 -Check -Environment prod'
    Write-Host ''
    & $g '  # Add a SQL database (and a server, if there is none), then create it'
    & $g '  .\infra\azure-setup.ps1 -AddResource -Kind sqlDatabase'
    & $g '  .\infra\azure-setup.ps1 -Start -Environment test'
    Write-Host ''
    & $g '  # A new project from an analysis of the solution (each suggestion offered)'
    & $g '  .\infra\azure-setup.ps1 -Init -Analyze'
    Write-Host ''
    & $g '  # A new project from what is in Azure already'
    & $g '  .\infra\azure-setup.ps1 -Init -Import -ResourceGroup contoso-shop-resgr-prod'
    Write-Host ''
    & $g '  # A new project from a spec file'
    & $g '  .\infra\azure-setup.ps1 -Init -SpecFile spec.json'
    Write-Host ''
    & $b 'A RUN, STEP BY STEP'
    & $d '  0. Answers (saved in infra/environments/<env>.json; Enter keeps the value in'
    & $d '     brackets, < goes back to change an answer; the monthly budget after the cost)'
    & $d '  1. Azure resources   Sign-in app registrations (container apps: by their saved'
    & $d '     client id; by name only what you alone own)   Database access'
    & $d '     Budget (mails at 80 % and 100 %, and forecast)'
    & $d '  2. GitHub -> Azure trust   3. GitHub environment'
    & $d '     First image (container apps still on the placeholder: their workflow with'
    & $d '     push-only, then main.bicep with the image)'
    & $d '  4. Custom domains   5. Live'
    & $d '  Then the next steps by hand and everything still open.'
    Write-Host ''
    & $b 'NEEDS'
    & $d '  Azure CLI (az login), Owner on the subscription (or Contributor + User Access'
    & $d '  Administrator), the right to create app registrations; GitHub CLI (gh auth login)'
    & $d '  as an admin of the repository. Windows PowerShell 5.1 or PowerShell 7.'
    & $d '  Everything else: infra/LAZYBICEP.md'
    Write-Host $hr -ForegroundColor Cyan
    Write-Host ''
}

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8 # az and gh write UTF-8
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$infra = $PSScriptRoot
$root = Split-Path $infra -Parent
$naming = Get-Content (Join-Path $infra 'naming.json') -Raw -Encoding UTF8 | ConvertFrom-Json
# An empty instance (the kit dropped into a project) has no map yet: -Init makes it.
$mapFile = Join-Path $infra 'infra.map.json'
$map = $null
$defs = @()
if (Test-Path $mapFile) {
    $map = Get-Content $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $defs = @($map.resources)
}
$staticLocations = @($map.regions.staticWebApp) # main.bicep's @allowed list
if ($Help) {
    Show-Author
    Show-Usage
    exit 0
}
$managedBy = [string]$map.project.managedByTag # the tag main.bicep puts on what it creates
$utf8 = New-Object Text.UTF8Encoding $false

$script:ui = [bool]$Ui
$script:results = New-Object System.Collections.ArrayList
$script:subscription = $null
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('infra-setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

# The map's resources by key, and what the run learns about them: the answers (names, groups, found),
# the apps as Azure shows them, the choices (sizes, domains...), the values {braces} are filled with.
function Get-Def([string]$Key) { return $defs | Where-Object { $_.key -eq $Key } | Select-Object -First 1 }
$appTypes = @('Microsoft.Web/sites', 'Microsoft.Web/staticSites', 'Microsoft.App/containerApps')
# Every app's own user-assigned identity (infra/LAZYBICEP.md, "Identity"): made and removed with its app,
# deleted after the apps that use it.
$identityType = 'Microsoft.ManagedIdentity/userAssignedIdentities'
$identityAppTypes = @('Microsoft.Web/sites', 'Microsoft.App/containerApps')
# Container Apps (docs/architecture/container-apps.md): the infrastructure never changes the image an app runs.
# A new app starts with the public placeholder (main.bicep: <key>Image = ''); every later start passes the image
# Azure runs now; the app's workflow deploys its own. Removed before their environment and registry.
$containerAppType = 'Microsoft.App/containerApps'
$containerEnvType = 'Microsoft.App/managedEnvironments'
$registryType = 'Microsoft.ContainerRegistry/registries'
$placeholderImage = 'mcr.microsoft.com/k8se/quickstart@sha256:3a4d93c34c6753f24765ab17a36f1754aee9b02082b7d9553d17697b9e8252c4'
# The resource providers these kinds need, registered in step 1 when the map uses them.
$usedProviders = @('Microsoft.App', 'Microsoft.ContainerRegistry', 'Microsoft.ManagedIdentity', 'Microsoft.OperationalInsights')
$script:res = [ordered]@{}
$script:apps = @{}
$script:choices = [ordered]@{}
$script:vals = @{}
$script:secrets = @{}

# --- output and questions -------------------------------------------------------------------------

# With -Ui every line is an event for infra/lazybicep.ps1.
function Send($Event) { [Console]::Out.WriteLine('@@ui ' + (ConvertTo-Json -InputObject $Event -Depth 10 -Compress)) }
function Say([string]$Text, [string]$Color) {
    if ($script:replaying) { return } # already on the screen (see Read-Answer)
    if ($script:ui) { Send ([ordered]@{ t = 'line'; text = $Text; color = $Color }); return }
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}
# While earlier answers are replayed after '<' (see Read-Answer), the output they caused is already on
# the screen, so it is not shown again.
function Head([string]$Text) {
    if ($script:replaying) { return }
    if ($script:ui) { Send ([ordered]@{ t = 'head'; text = $Text }); return }
    Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan
}
function Ok([string]$Text) {
    [void]$script:results.Add(@{ Done = $true; Text = $Text })
    if ($script:replaying) { return }
    if ($script:ui) { Send ([ordered]@{ t = 'ok'; text = $Text }); return }
    Write-Host "  OK $Text" -ForegroundColor Green
}
function Missing([string]$Text) {
    [void]$script:results.Add(@{ Done = $false; Text = $Text })
    if ($script:replaying) { return }
    if ($script:ui) { Send ([ordered]@{ t = 'missing'; text = $Text }); return }
    Write-Host "  -- $Text" -ForegroundColor Yellow
}
function Note([string]$Text) {
    if ($script:replaying) { return }
    if ($script:ui) { Send ([ordered]@{ t = 'note'; text = $Text }); return }
    Write-Host "    $Text"
}
# What is known about a resource of the map (state: new, exists, ours, shared, problem, created, gone).
function Mark([string]$Key, [string]$Name, [string]$State, [string]$Group) {
    if ($script:ui) { Send ([ordered]@{ t = 'res'; key = $Key; name = $Name; state = $State; group = $Group }) }
}

# Going back: '<' at any question before the first change goes to the previous question. The questions
# start over and everything typed before that question is answered again by itself (quietly; matched by
# the question's text, so a question whose default changed is asked again), and every lookup runs again
# with the new answers.
$script:typed = New-Object System.Collections.ArrayList  # @{ Prompt; Answer } of this round
$script:replay = New-Object System.Collections.ArrayList # what the next round answers by itself
$script:replaying = $false
$script:previous = $null # after <: the answer given before to the question asked again
$script:canGoBack = $false
$backSignal = 'infra-setup:back'

# Reads from the console or from piped input alike. $Meta describes the question for -Ui (kind: text,
# select, confirm, menu; question, default, options).
function Read-Answer([string]$Prompt, $Meta) {
    for ($i = 0; $i -lt $script:replay.Count; $i++) {
        if ($script:replay[$i].Prompt -ne $Prompt) { continue }
        $entry = $script:replay[$i]
        $script:replay.RemoveRange(0, $i + 1)
        [void]$script:typed.Add($entry)
        $script:replaying = $script:replay.Count -gt 0
        return $entry.Answer
    }
    $script:replaying = $false
    while ($true) {
        if ($script:ui) {
            $e = [ordered]@{ t = 'ask'; prompt = $Prompt.Trim(); kind = 'text'; question = $Prompt.Trim(); default = ''; options = @() }
            if ($Meta) { foreach ($k in $Meta.Keys) { $e[$k] = $Meta[$k] } }
            $e.canBack = [bool]($script:canGoBack -and $script:typed.Count)
            if ($script:previous -and $script:previous.Prompt -eq $Prompt) { $e.previous = [string]$script:previous.Answer }
            Send $e
        } else {
            if ($script:previous -and $script:previous.Prompt -eq $Prompt -and $script:previous.Answer) { Write-Host "    (you answered: $($script:previous.Answer); Enter keeps it)" -ForegroundColor DarkGray }
            Write-Host -NoNewline $Prompt
        }
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { throw 'The input ended before every question was answered.' }
        if ([Console]::IsInputRedirected -and -not $script:ui) { Write-Host $line }
        $line = $line.Trim()
        # Asked again after '<': Enter keeps what was answered before (lazybicep fills it in instead).
        if (-not $line -and -not $script:ui -and $script:previous -and $script:previous.Prompt -eq $Prompt -and $script:previous.Answer) { $line = [string]$script:previous.Answer }
        if ($line -eq '<') {
            if (-not $script:canGoBack) { Note "X '<' goes back only while answering, before the first change"; continue }
            if (-not $script:typed.Count) { Note 'X this is the first question'; continue }
            throw $backSignal
        }
        [void]$script:typed.Add(@{ Prompt = $Prompt; Answer = $line })
        $script:previous = $null # shown once, for the question asked again
        $script:replaying = $script:replay.Count -gt 0
        return $line
    }
}
# Check mode answers every question with its saved default; the same question twice means a saved
# answer was rejected, which needs a dry run or a start to fix.
$script:lastAuto = $null
function Ask([string]$Question, [string]$Default, [string[]]$Options, [string]$Title) {
    $suffix = ''
    if ($Default) { $suffix = " [$Default]" }
    if (-not $Title) { $Title = $Question }
    if ($script:auto) {
        if ($script:lastAuto -ne $Question) {
            $script:lastAuto = $Question
            if (-not $script:ui) { Write-Host "  $Question$($suffix)" -ForegroundColor DarkGray }
            elseif (-not $script:replaying) { Send ([ordered]@{ t = 'auto'; question = $Title; value = $Default }) }
            return $Default
        }
        # The same question again: its saved answer was rejected. A check stops; a dry run or start asks it.
        if ($script:mode -eq 'check') { throw "The saved answer to '$Question' ($Default) is not valid any more: run a dry run or start to answer it again." }
        Note 'X the saved answer is not valid any more: answer this one'
    }
    $kind = 'text'
    if ($Options) { $kind = 'select' }
    $a = Read-Answer "  $Question$($suffix): " ([ordered]@{ kind = $kind; question = $Title; default = $Default; options = @($Options | Where-Object { $_ }) })
    if ($a) { return $a }
    return $Default
}
function Confirm-Step([string]$Question, [switch]$DefaultNo, [switch]$Danger) {
    if ($script:readOnly) { return $false }
    if ($DefaultNo) {
        $a = (Read-Answer "  $Question [y/N] " ([ordered]@{ kind = 'confirm'; question = $Question; default = 'n'; danger = [bool]$Danger })).ToLower()
        return $a.StartsWith('y')
    }
    $a = (Read-Answer "  $Question [Y/n] " ([ordered]@{ kind = 'confirm'; question = $Question; default = 'y' })).ToLower()
    return (-not $a) -or $a.StartsWith('y')
}
function Select-Option([string]$Question, [string[]]$Options, [string]$Default) {
    while ($true) {
        $a = Ask "$Question ($($Options -join ', '))" $Default $Options $Question
        $hit = $Options | Where-Object { $_ -ieq $a } | Select-Object -First 1
        if ($hit) { return $hit }
        Note "X one of $($Options -join ', ')"
    }
}

# --- az, gh, files --------------------------------------------------------------------------------

# az on Windows is az.cmd, and PowerShell starts a .cmd/.bat through cmd.exe, which parses the arguments again:
# & | < > ^ ( ) run or redirect something else, " ends quoting, % and ! expand variables, a line break ends the
# command. PowerShell quotes an argument only when it has whitespace, so 'x&echo.INJECTED' reaches cmd.exe bare and
# runs echo. So cmd.exe never sees az's arguments: the Azure CLI's az.cmd only runs
# "<its folder>\..\python.exe -IBm azure.cli %*" (AZ_INSTALLER=MSI), and that python is started directly here.
# Any other batch file (or an az.cmd without that python) gets only arguments cmd.exe leaves alone
# (Assert-BatchSafe). JSON never goes inline (--body @file).
$script:nativeExe = @{}
# How $Exe runs: @{ Path; Batch (a .cmd/.bat); Python (the Azure CLI's python.exe next to az.cmd, else '') }.
function Resolve-NativeExe([string]$Exe) {
    if (-not $script:nativeExe.ContainsKey($Exe)) {
        $path = [string](@(Get-Command $Exe -CommandType Application -ErrorAction SilentlyContinue) | Select-Object -First 1 | ForEach-Object { $_.Source })
        if (-not $path) { $path = $Exe }
        $python = ''
        if ([IO.Path]::GetFileName($path) -ieq 'az.cmd' -and [IO.Path]::IsPathRooted($path)) {
            $candidate = [IO.Path]::GetFullPath([IO.Path]::Combine([IO.Path]::GetDirectoryName($path), '..', 'python.exe'))
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $python = $candidate }
        }
        $script:nativeExe[$Exe] = [pscustomobject]@{ Path = $path; Batch = [bool]($path -match '\.(cmd|bat)$'); Python = $python }
    }
    return $script:nativeExe[$Exe]
}
# An argument for a batch file: only characters cmd.exe takes literally (an allow-list, not a deny-list). One with a
# space PowerShell puts in quotes, inside which cmd.exe leaves & | < > ^ ( ) alone - but a " would end the quotes,
# % and ! still expand, a control character ends the line, and a \ before the closing quote escapes it for the
# program: those stay refused.
function Assert-BatchSafe([string]$Exe, [string[]]$Arguments) {
    foreach ($a in @($Arguments)) {
        $s = [string]$a
        if ($s -cmatch '^[A-Za-z0-9 @._:/=,+~\\\[\]''?*{}$#-]*$' -and -not ($s.Contains(' ') -and $s.EndsWith('\'))) { continue }
        if ($s.Contains(' ') -and $s -notmatch '["%!\x00-\x1f\x7f]' -and -not $s.EndsWith('\')) { continue }
        throw "refused: an argument for $Exe (a batch file, parsed again by cmd.exe) has a character cmd.exe would act on: $($s -replace '[\x00-\x1f\x7f]', ' ')"
    }
}
# An argument for a program started directly (the Azure CLI's python): Windows PowerShell 5.1 passes a " inside an
# argument unescaped (the program would split it into several), a control character has no place in one, and a \
# at the end of an argument with a space escapes the closing quote.
function Assert-DirectSafe([string]$Exe, [string[]]$Arguments) {
    foreach ($a in @($Arguments)) {
        $s = [string]$a
        if ($s -notmatch '["\x00-\x1f\x7f]' -and -not ($s -match '\s' -and $s.EndsWith('\'))) { continue }
        throw "refused: an argument for $Exe has a "", a control character or (with a space) a \ at its end: $($s -replace '[\x00-\x1f\x7f]', ' ')"
    }
}
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $n = Resolve-NativeExe $Exe
    $prev = $ErrorActionPreference
    $prevInstaller = $env:AZ_INSTALLER
    if ($n.Python) { Assert-DirectSafe $Exe $Arguments }
    elseif ($n.Batch) { Assert-BatchSafe $Exe $Arguments }
    $ErrorActionPreference = 'Continue'
    try {
        if ($n.Python) {
            # What az.cmd does, without cmd.exe in between.
            $env:AZ_INSTALLER = 'MSI'
            $out = & $n.Python -IBm azure.cli @Arguments 2>&1
        } else { $out = & $Exe @Arguments 2>&1 }
    } finally {
        $ErrorActionPreference = $prev
        if ($n.Python) { $env:AZ_INSTALLER = $prevInstaller }
    }
    $code = $LASTEXITCODE
    $errors = @($out | Where-Object { $_ -is [Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() })
    $text = (@($out | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] }) -join "`n").Trim()
    return [pscustomobject]@{ Code = $code; Text = $text; Errors = ($errors -join "`n") }
}
# JSON answers come back as objects; lists unroll, so callers wrap them in @().
function Invoke-Az([string[]]$Arguments) {
    $all = @($Arguments)
    if ($script:subscription -and (@('ad', 'account', 'rest') -notcontains $Arguments[0])) { $all += @('--subscription', $script:subscription) }
    $all += @('--only-show-errors', '-o', 'json')
    $r = Invoke-Native 'az' $all
    if ($r.Code -ne 0) { throw "az $((@($Arguments) | Select-Object -First 4) -join ' ') failed:`n$($r.Errors)" }
    if ($r.Text) { return ($r.Text | ConvertFrom-Json) }
}
function Try-Az([string[]]$Arguments) {
    try { return Invoke-Az $Arguments } catch { }
}
# The GitHub CLI, also right after winget installed it (before a new terminal has it on the PATH).
$ghExe = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $ghExe -and (Test-Path 'C:\Program Files\GitHub CLI\gh.exe')) { $ghExe = 'C:\Program Files\GitHub CLI\gh.exe' }
function Invoke-Gh([string[]]$Arguments, [switch]$Json) {
    $r = Invoke-Native $ghExe $Arguments
    if ($r.Code -ne 0) { throw "gh $((@($Arguments) | Select-Object -First 3) -join ' ') failed:`n$($r.Errors)" }
    if ($Json) { if ($r.Text) { return ($r.Text | ConvertFrom-Json) } } else { return $r.Text }
}
function Try-Gh([string[]]$Arguments, [switch]$Json) {
    try { if ($Json) { return Invoke-Gh $Arguments -Json } else { return Invoke-Gh $Arguments } } catch { }
}
function Test-Gh([string[]]$Arguments) { return (Invoke-Native $ghExe $Arguments).Code -eq 0 }

function Write-TempJson([string]$Name, $Value) {
    $file = Join-Path $tmp $Name
    [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $Value -Depth 10 -Compress), $utf8)
    return $file
}
function Read-Json([string]$Path) {
    if (Test-Path $Path) { return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
}
function New-Secret {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
function Get-Url([string]$Url) {
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30
        return [pscustomobject]@{ Status = [int]$r.StatusCode; Text = [string]$r.Content }
    } catch {
        $status = 0
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        return [pscustomobject]@{ Status = $status; Text = $_.Exception.Message }
    }
}

# --- the map's values ------------------------------------------------------------------------------

# One {braces} value (infra.map.json, "$comment"), or $null while it isn't known.
function Get-Value([string]$Key) {
    if ($script:vals.ContainsKey($Key)) { return $script:vals[$Key] }
    if ($Key.StartsWith('secret.')) { return $script:secrets[$Key.Substring(7)] }
    $parts = $Key.Split('.')
    if ($parts.Count -eq 1) {
        $v = $script:choices[$Key]
        if ($v -and $v -ne '-') { return $v }
        return $null
    }
    if ($parts[1] -eq 'name' -and $script:res[$parts[0]]) { return $script:res[$parts[0]].Name }
    # Host names known from the name alone (also for a server shared from another group).
    $hostDef = Get-Def $parts[0]
    if ($parts[1] -eq 'host' -and $hostDef -and $script:res[$parts[0]] -and $script:res[$parts[0]].Name) {
        if ($hostDef.kind -eq 'sqlServer') { return $script:res[$parts[0]].Name + '.database.windows.net' }
        if ($hostDef.kind -eq 'serviceBus') { return $script:res[$parts[0]].Name + '.servicebus.windows.net' }
        if ($hostDef.kind -eq 'appConfiguration') { return $script:res[$parts[0]].Name + '.azconfig.io' }
    }
    # An app's identity: its client id (AZURE_CLIENT_ID...), principal id and resource id, once it exists.
    if ($hostDef -and $hostDef.armType -eq $identityType -and @('clientId', 'principalId', 'id') -contains $parts[1]) {
        $ident = Get-IdentityOf $parts[0]
        if ($ident) { return $ident.($parts[1]) }
        return $null
    }
    # A resource's group: the environment's, or the one it is shared from (GitHub variables AZURE_<KEY>_GROUP).
    if ($parts[1] -eq 'group' -and $script:res[$parts[0]] -and $script:res[$parts[0]].Name) {
        if ($script:res[$parts[0]].Group) { return $script:res[$parts[0]].Group }
        return $script:rgName
    }
    $app = $script:apps[$parts[0]]
    if ($app -and $parts[1] -eq 'host') { return Get-AppHost $app }
    if ($app -and $parts[1] -eq 'id') { return $app.id }
    return $null
}
# A text with {braces} filled in; $null when one of them isn't known yet.
function Expand([string]$Text) {
    $known = $true
    $out = $Text
    foreach ($m in @([regex]::Matches($Text, '\{([^{}]+)\}'))) {
        $value = $null
        foreach ($k in $m.Groups[1].Value.Split('|')) { if (-not $value) { $value = Get-Value $k } }
        if (-not $value) { $known = $false; continue }
        $out = $out.Replace($m.Value, [string]$value)
    }
    if ($known) { return $out }
    return $null
}
function Format-Text([string]$Text, [hashtable]$Values) {
    foreach ($k in $Values.Keys) { $Text = $Text.Replace("{$k}", [string]$Values[$k]) }
    return $Text
}

# --- cost --------------------------------------------------------------------------------------------

# Azure list prices (prices.azure.com, public). Without it: the West Europe prices in EUR of 2026-10-17.
$fallbackPrices = @{ B1 = 11.53; B2 = 23.14; P0v3 = 57.16; P1v3 = 114.32; StaticStandard = 7.92; LogsPerGb = 2.63; LogsFreeGb = 5
    # Container registry a month (the catalog's prices, EUR 2026-11-19); Container Apps Consumption per second.
    RegistryBasic = 4.30; RegistryStandard = 17.20; RegistryPremium = 43.00; ContainerVcpuSecond = 0.0000216; ContainerGibSecond = 0.0000027 }
$script:pricesLive = $true
function Get-RetailItems([string]$Filter) {
    $url = "https://prices.azure.com/api/retail/prices?currencyCode=$Currency&`$filter=" + [uri]::EscapeDataString($Filter)
    try { return @((Invoke-RestMethod -Uri $url -TimeoutSec 20).Items) } catch { $script:pricesLive = $false; return @() }
}
function Get-PlanMonthly([string]$Sku, [string]$Region) {
    $names = @($Sku, ($Sku -replace '^(P\d)(v\d)$', '$1 $2')) | Select-Object -Unique # P1v3 is listed as 'P1 v3'
    $or = ($names | ForEach-Object { "skuName eq '$_'" }) -join ' or '
    $hit = Get-RetailItems "serviceName eq 'Azure App Service' and armRegionName eq '$Region' and priceType eq 'Consumption' and ($or)" |
        Where-Object { $_.productName -like '*Linux*' -and $_.unitOfMeasure -eq '1 Hour' } | Select-Object -First 1
    if ($hit) { return [double]$hit.retailPrice * 730 }
    $script:pricesLive = $false
    return [double]$fallbackPrices[$Sku]
}
function Get-StaticMonthly([string]$Sku, [string]$Region) {
    if ($Sku -ne 'Standard') { return 0.0 }
    $hit = Get-RetailItems "serviceName eq 'Azure App Service' and armRegionName eq '$Region' and meterName eq 'Standard App' and priceType eq 'Consumption'" |
        Where-Object { $_.productName -like '*Static Web*' } | Select-Object -First 1
    if ($hit) { return [double]$hit.retailPrice }
    $script:pricesLive = $false
    return [double]$fallbackPrices.StaticStandard
}
function Get-LogsPrice([string]$Region) {
    $items = Get-RetailItems "serviceName eq 'Log Analytics' and armRegionName eq '$Region' and meterName eq 'Analytics Logs Data Ingestion' and priceType eq 'Consumption'"
    $paid = $items | Where-Object { [double]$_.retailPrice -gt 0 } | Select-Object -First 1
    if ($paid) { return [pscustomobject]@{ PerGb = [double]$paid.retailPrice; FreeGb = [double]$paid.tierMinimumUnits } }
    $script:pricesLive = $false
    return [pscustomobject]@{ PerGb = $fallbackPrices.LogsPerGb; FreeGb = $fallbackPrices.LogsFreeGb }
}
# A container registry's monthly price by its SKU (Basic, Standard, Premium): a daily unit price.
function Get-RegistryMonthly([string]$Sku, [string]$Region) {
    if (@('Basic', 'Standard', 'Premium') -notcontains $Sku) { $Sku = 'Basic' }
    $hit = Get-RetailItems "serviceName eq 'Container Registry' and armRegionName eq '$Region' and priceType eq 'Consumption' and meterName eq '$Sku Registry Unit'" |
        Where-Object { $_.unitOfMeasure -eq '1/Day' -and [double]$_.retailPrice -gt 0 } | Select-Object -First 1
    if ($hit) { return [double]$hit.retailPrice * 730 / 24 }
    $script:pricesLive = $false
    return [double]$fallbackPrices["Registry$Sku"]
}
# Container Apps Consumption: the active price of a vCPU second and a GiB second (the idle price is lower).
function Get-ContainerAppsPrices([string]$Region) {
    $items = @(Get-RetailItems "serviceName eq 'Azure Container Apps' and armRegionName eq '$Region' and priceType eq 'Consumption' and skuName eq 'Standard'")
    $cpu = $items | Where-Object { $_.meterName -eq 'Standard vCPU Active Usage' -and [double]$_.retailPrice -gt 0 } | Select-Object -First 1
    $mem = $items | Where-Object { $_.meterName -eq 'Standard Memory Active Usage' -and [double]$_.retailPrice -gt 0 } | Select-Object -First 1
    if ($cpu -and $mem) { return [pscustomobject]@{ VcpuSecond = [double]$cpu.retailPrice; GibSecond = [double]$mem.retailPrice } }
    $script:pricesLive = $false
    return [pscustomobject]@{ VcpuSecond = $fallbackPrices.ContainerVcpuSecond; GibSecond = $fallbackPrices.ContainerGibSecond }
}
# The cost row of a Container Apps resource without a "cost" in the map (the kit's own rule for these kinds).
function Get-ContainerCost($Def) {
    switch ([string]$Def.armType) {
        $registryType { return [pscustomobject]@{ kind = 'containerRegistry'; order = 3; label = 'Container registry {name} ({size})' } }
        $containerEnvType { return [pscustomobject]@{ kind = 'containerAppsEnvironment'; order = 2; label = 'Container Apps environment {name} (Consumption)' } }
        $containerAppType { return [pscustomobject]@{ kind = 'containerApp'; order = 2; label = 'Container app {name}' } }
    }
    return $null
}
# A container app's monthly cost at the Consumption active price: what its minimum replicas cost when they run all
# month (an upper bound: idle replicas cost less, the subscription's monthly free grant comes first). $null when it
# scales to zero (then it costs only what it runs).
function Get-ContainerAppMonthly($Def, [string]$Region) {
    $min = 0
    if ($null -ne $Def.minReplicas) { [void][int]::TryParse([string]$Def.minReplicas, [ref]$min) }
    if ($min -lt 1) { return $null }
    $cpu = 0.5
    $mem = 1.0
    if ($Def.cpu) { [void][double]::TryParse(([string]$Def.cpu), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$cpu) }
    if ($Def.memory) { [void][double]::TryParse(([string]$Def.memory -replace '[^0-9.]', ''), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$mem) }
    $p = Get-ContainerAppsPrices $Region
    return $min * ($cpu * $p.VcpuSecond + $mem * $p.GibSecond) * 730 * 3600
}
# The estimate of one environment's answers: what it adds to the monthly bill at list prices, one row per
# resource with a "cost" in the map. Shared resources from other groups add nothing (their own
# environment pays for them).
function Write-CostEstimate([string]$Location, [string]$StaticLocation) {
    $rows = New-Object System.Collections.ArrayList
    function Row([string]$What, $Amount, [string]$Text) { [void]$rows.Add([pscustomobject]@{ What = $What; Amount = $Amount; Text = $Text }) }
    $pennies = '< ' + (0.1).ToString('0.00') # in the current culture, like the other amounts
    # The Container Apps kinds have the kit's own rows when the map gives them none.
    $costed = @($defs | ForEach-Object {
            $c = $_.cost
            if (-not $c) { $c = Get-ContainerCost $_ }
            if ($c) { [pscustomobject]@{ Def = $_; Cost = $c } }
        } | Sort-Object { [int]$_.Cost.order })
    foreach ($item in $costed) {
        $def = $item.Def
        $cost = $item.Cost
        $r = $script:res[$def.key]
        if (-not $r -or -not $r.Name) { continue }
        $size = ''
        if ($def.size) { $size = [string]$script:choices[$def.size.answer] }
        $values = @{ name = $r.Name; size = $size; group = $r.Group }
        $label = Format-Text $cost.label $values
        $kind = [string]$cost.kind
        if ($kind -eq 'containerRegistry') {
            if (-not $size) { $size = 'Basic' }
            $label = Format-Text $cost.label @{ name = $r.Name; size = $size; group = $r.Group }
            if ($r.Group) { Row "$label (shared from $($r.Group))" 0.0 '' }
            else { Row $label (Get-RegistryMonthly $size $Location) '' }
            continue
        }
        if ($kind -eq 'containerAppsEnvironment') {
            if ($r.Group) { Row "$label (shared from $($r.Group))" 0.0 ''; continue }
            Row $label $null 'per use: vCPU and memory seconds and requests of its apps, after the subscription''s monthly free grant (180,000 vCPU-s, 360,000 GiB-s, 2 million requests); 0.00 while they scale to zero'
            continue
        }
        if ($kind -eq 'containerApp') {
            $monthly = Get-ContainerAppMonthly $def $Location
            if ($null -eq $monthly) { Row $label $null 'per use (scales to zero)' }
            else {
                $cpuText = '0.5'; if ($def.cpu) { $cpuText = [string]$def.cpu }
                $memText = '1Gi'; if ($def.memory) { $memText = [string]$def.memory }
                Row "$label ($($def.minReplicas) always-on replica(s) at $cpuText vCPU / $memText, at most; less when idle)" $monthly ''
            }
            continue
        }
        if ($kind -eq 'appServicePlan') {
            if ($r.Group) { Row (Format-Text $def.cost.sharedLabel $values) 0.0 '' }
            else { Row $label (Get-PlanMonthly $size $Location) '' }
        } elseif ($kind -eq 'staticWebApp') { Row $label (Get-StaticMonthly $size $StaticLocation) '' }
        elseif ($kind -eq 'pennies') { Row $label $null $pennies }
        elseif ($kind -eq 'table') {
            # A price per size (list prices, approximate), else a text, else a fixed amount.
            $price = $null
            if ($def.cost.prices -and $size -and $null -ne $def.cost.prices.$size) { $price = [double]$def.cost.prices.$size }
            $text = ''
            if ($def.cost.texts -and $size -and $def.cost.texts.$size) { $text = [string]$def.cost.texts.$size }
            if ($r.Group) { Row "$label (shared from $($r.Group))" 0.0 '' }
            elseif ($null -ne $price) { Row $label $price '' }
            elseif ($text) { Row $label $null $text }
            elseif ($def.cost.text) { Row $label $null ([string]$def.cost.text) }
            else { Row $label ([double]$def.cost.otherwise) '' }
        }
        elseif ($kind -eq 'logs') {
            $logs = Get-LogsPrice $Location
            Row $label 0.0 ('{0:0.00} up to {1:0} GB of logs a month, then {2:0.00} per GB' -f 0.0, $logs.FreeGb, $logs.PerGb)
        }
    }
    foreach ($extra in @($map.costExtras)) { if ($extra) { Row $extra 0.0 '' } }
    $total = 0.0
    foreach ($r in $rows) { if ($r.Amount) { $total += [double]$r.Amount } }
    $script:costTotal = $total # the budget's default (Read-Budget)
    $source = "list prices from prices.azure.com, $Location"
    if (-not $script:pricesLive) { $source = 'prices.azure.com not reachable: West Europe list prices in EUR of 2026-10' }
    $title = "Estimated monthly cost ($Currency; $source)"
    $totalText = "$($total.ToString('0.00')) $Currency a month (+ logs beyond the free amount; without VAT and discounts)"
    $shown = @(foreach ($r in $rows) {
            $amount = $r.Text
            if ($null -ne $r.Amount -and -not $r.Text) { $amount = ([double]$r.Amount).ToString('0.00') }
            [ordered]@{ what = $r.What; amount = $amount }
        })
    if ($script:ui) {
        Head $title
        Send ([ordered]@{ t = 'cost'; currency = $Currency; source = $source; rows = $shown; total = $total.ToString('0.00'); totalText = $totalText })
        return
    }
    Head $title
    foreach ($r in $shown) { Note ("{0,-64} {1}" -f $r.what, $r.amount) }
    Note ('-' * 80)
    Note ("{0,-64} {1}" -f 'Total, about', $totalText)
}

# --- names -----------------------------------------------------------------------------------------

function Fill([string]$Pattern, [string]$Type, [string]$Sub) {
    $n = $Pattern.Replace('{prefix}', $script:prefix).Replace('{sub}', $Sub).Replace('{type}', $Type).Replace('{env}', $script:envAbbr)
    return (($n -replace '-+', '-') -replace '^-|-$', '')
}
# The sub application name belongs to a deployment target (naming.json "targets": the web app, the API,
# functions...), asked for each; the environment's shared resources have none.
$script:subs = [ordered]@{}
function Get-Sub([string]$Type) {
    if ($script:subs.Contains($Type)) { return [string]$script:subs[$Type] }
    return ''
}
function Get-SavedSub([string]$Type) {
    if ($script:saved -and $script:saved.subs -and $script:saved.subs.$Type) { return [string]$script:saved.subs.$Type }
    return ''
}
function Read-Sub([string]$Type, [string]$Label, [string]$DefType) {
    while ($true) {
        $default = Get-SavedSub $Type
        # A target named after its naming type (apiapp, statapp...) starts without one; a second resource of a
        # type (another API: target api2) starts with its target as the sub application name.
        if (-not $default -and $Type -ne $DefType) { $default = $Type }
        if (-not $default) { $default = '-' }
        $s = (Ask "Sub application name of $Label ('-' for none)" $default).ToLower()
        if ($s -eq '-') { $s = '' }
        if (-not $s -or $s -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $script:subs[$Type] = $s; return }
        Note 'X lowercase letters and digits, parts separated by single hyphens'
    }
}
# The name the naming rules give a type, with the sub application name of its deployment target (by
# default the type itself: the API's target is apiapp; a second API's is api2).
function Get-RuleName([string]$Type, [string]$Target) {
    if (-not $Target) { $Target = $Type }
    $n = Fill $naming.pattern $Type (Get-Sub $Target)
    if (@($naming.noHyphens) -contains $Type) { $n = $n.Replace('-', '') }
    return $n
}
# An app's own identity is named after its app (naming.json "identityPattern"; {apptype}: the app's naming
# type): contoso-shop-apiapp-ident-prod, contoso-shop-api2-apiapp-ident-prod, so two apps without a sub
# application name never get the same one. $Target: the app's deployment target (its sub application name).
function Get-IdentityRuleName([string]$Type, [string]$Target, [string]$AppType) {
    $pattern = [string]$naming.identityPattern
    if (-not $pattern) { $pattern = '{prefix}-{sub}-{apptype}-ident-{env}' } # a naming.json from before 0.2.0
    return Fill $pattern.Replace('{apptype}', $AppType) $Type (Get-Sub $Target)
}
# Saved names are the defaults while the prefix (and the target's sub application name) stay the same;
# a new one starts from the rules again.
function Get-Default([string]$Key, [string]$Rule, [string]$Target) {
    if ($Target -and (Get-SavedSub $Target) -ne (Get-Sub $Target)) { return $Rule }
    if ($script:samePrefix -and $script:saved -and $script:saved.names -and $script:saved.names.$Key) { return [string]$script:saved.names.$Key }
    return $Rule
}
function Test-Name([string]$Type, [string]$Name) {
    $max = 63
    if ($naming.maxLength.$Type) { $max = [int]$naming.maxLength.$Type }
    if ($Name.Length -gt $max) { return "$Name is $($Name.Length) characters, at most $max" }
    if ($Type -eq 'store' -and $Name -notmatch '^[a-z0-9]{3,24}$') { return "${Name}: 3-24 lowercase letters and digits only" }
    if ($Type -eq 'kv' -and $Name -notmatch '^[a-z][a-z0-9-]{1,22}[a-z0-9]$') { return "${Name}: 3-24 letters, digits and hyphens, starting with a letter" }
    # Container Apps (checked here, before Azure is asked): an app 2-32, an environment 2-60 lowercase letters, digits
    # and single hyphens, starting with a letter; a registry 5-50 letters and digits.
    if ($Type -eq 'contapp' -and ($Name -cnotmatch '^[a-z][a-z0-9-]{0,30}[a-z0-9]$' -or $Name.Contains('--'))) { return "${Name}: 2-32 lowercase letters, digits and single hyphens, starting with a letter" }
    if ($Type -eq 'contenv' -and ($Name -cnotmatch '^[a-z][a-z0-9-]{0,58}[a-z0-9]$' -or $Name.Contains('--'))) { return "${Name}: 2-60 lowercase letters, digits and single hyphens, starting with a letter" }
    if ($Type -eq 'contreg' -and $Name -cnotmatch '^[a-z0-9]{5,50}$') { return "${Name}: 5-50 lowercase letters and digits only" }
    if ($Type -ne 'store' -and $Name -cnotmatch '^[a-z0-9][a-z0-9-]*[a-z0-9]$') { return "${Name}: lowercase letters, digits and hyphens" }
}
# The names an environment's saved answers hold (infra/environments/<env>.json), checked by their naming rule as a
# typed name is (letter case aside: Azure's names ignore it), and the resource groups of shared resources by
# Azure's rule for a group (letters, digits . _ - ( ), at most 90, not ending in '.'): a name edited into the file
# would otherwise reach az unchecked. The problems, empty when there are none.
function Get-SavedNameProblems($Saved) {
    $out = @()
    if (-not $Saved) { return $out }
    if ($Saved.names) {
        foreach ($p in @($Saved.names.PSObject.Properties)) {
            $def = Get-Def $p.Name
            if (-not $def) { continue } # not in the map (any more): never used
            $problem = Test-Name ([string]$def.type) (([string]$p.Value).ToLowerInvariant())
            if ($problem) { $out += "names.$($p.Name): $problem" }
        }
    }
    if ($Saved.groups) {
        foreach ($p in @($Saved.groups.PSObject.Properties)) {
            $g = [string]$p.Value
            if ($g -and ($g -cnotmatch '^[A-Za-z0-9._()-]{1,90}$' -or $g.EndsWith('.'))) { $out += "groups.$($p.Name): $g is no resource group name" }
        }
    }
    return $out
}
function Assert-SavedNames($Saved, [string]$File) {
    $problems = @(Get-SavedNameProblems $Saved)
    if ($problems.Count) { throw "$File holds names that break the naming rules (fix them there, or run a start of a fresh environment): $($problems -join '; ')" }
}
function Read-Name([string]$Label, [string]$Type, [string]$Default) {
    while ($true) {
        $name = (Ask $Label $Default).ToLower()
        $problem = Test-Name $Type $name
        # Several resources of one kind (two APIs...): each needs its own name (a sub application name).
        $current = $script:currentDef
        if (-not $problem -and $current) {
            foreach ($k in @($script:res.Keys)) {
                $other = Get-Def $k
                if ($k -ne $current.key -and $other -and $other.armType -eq $current.armType -and $script:res[$k].Name -ieq $name) { $problem = "$name is already the name of $($other.title) (give one of them a sub application name)" }
            }
        }
        if (-not $problem) { return $name }
        Note "X $problem"
    }
}
function Find-Resource([string]$Name, [string]$ArmType) {
    return @(Invoke-Az @('resource', 'list', '--name', $Name, '--resource-type', $ArmType)) | Where-Object { $_ -and $_.name -ieq $Name } | Select-Object -First 1
}
function Test-NameFree([string]$Provider, [string]$Type, [string]$Name, [string]$Version) {
    $url = "https://management.azure.com/subscriptions/$($script:subscription)/providers/$Provider/checkNameAvailability?api-version=$Version"
    $body = Write-TempJson 'name.json' @{ name = $Name; type = $Type }
    $r = Invoke-Az @('rest', '--method', 'post', '--url', $url, '--body', "@$body")
    # Microsoft.Sql answers "available", the other providers "nameAvailable".
    if (-not ($r.nameAvailable -or $r.available)) { return "$Name is taken: $($r.message)" }
}
function Test-InGroup($Resource) { return $Resource.resourceGroup -ieq $script:rgName }
function Test-Ours($Resource) { return ($Resource.tags -and $Resource.tags.'managed-by' -eq $managedBy -and (Test-InGroup $Resource)) }

# The map's name checks ("free": a new name; "check": an existing resource). A problem, or nothing.
function Test-Free($Def, [string]$Name) {
    # A user-assigned identity's name is unique per resource group only (Select-Own checks the group).
    if ($Def.armType -eq $identityType) { return }
    switch ([string]$Def.free) {
        'nameAvailable' { return Test-NameFree $Def.armType.Split('/')[0] $Def.armType $Name $Def.apiVersion }
        # A container registry's name is global (<name>.azurecr.io).
        'registryName' {
            $r = Invoke-Az @('acr', 'check-name', '--name', $Name)
            if (-not $r.nameAvailable) { return "$Name is taken: $($r.message)" }
        }
        'vaultSoftDelete' {
            # A deleted vault keeps its name for 30 days (soft delete).
            $deleted = Try-Az @('keyvault', 'show-deleted', '--name', $Name)
            if ($deleted) {
                if (-not (Confirm-Step "Key Vault $Name is soft-deleted ($(($deleted.properties.vaultId -split '/')[4])). Recover it?")) { return "$Name is soft-deleted (recover or purge it, or pick another name)" }
                Invoke-Az @('keyvault', 'recover', '--name', $Name) | Out-Null
                Ok "Key Vault $Name recovered"
                return
            }
            return Test-NameFree 'Microsoft.KeyVault' $Def.armType $Name $Def.apiVersion
        }
    }
}
function Test-Found($Def, $Found) {
    switch ([string]$Def.check) {
        'linuxPlanInRegion' {
            if ($Found.kind -notmatch 'linux') { return "$($Found.name) is a Windows plan; the apps on it need Linux" }
            if ($Found.location -ne $script:location) { return "$($Found.name) is in $($Found.location), the environment in $($script:location)" }
        }
        'sameRegion' {
            if ($Found.location -ne $script:location) { return "$($Found.name) is in $($Found.location), the environment in $($script:location)" }
        }
        'rbacVault' {
            if (-not (Invoke-Az @('keyvault', 'show', '--name', $Found.name, '-g', $Found.resourceGroup)).properties.enableRbacAuthorization) { return "$($Found.name) uses access policies; the API's access is an RBAC role" }
        }
    }
}

# A resource that always lives in this environment's group (ask "own"): an existing one is used only
# there; a new name must be free.
function Select-Own($Def, [string]$Label, [string]$Default) {
    while ($true) {
        $name = Read-Name $Label $Def.type $Default
        $found = Find-Resource $name $Def.armType
        $problem = $null
        if ($found -and -not (Test-InGroup $found)) { $problem = "$name exists in $($found.resourceGroup); it belongs in $($script:rgName) (pick another name)" }
        if (-not $found -and $Def.free) { $problem = Test-Free $Def $name }
        if ($problem) {
            Note "X $problem"
            if (-not $script:readOnly) { continue }
            Missing "$Label ${name}: $problem"
            Mark $Def.key $name 'problem' ''
        }
        if ($found) {
            if (Test-Ours $found) { Note 'exists, made by this template'; Mark $Def.key $name 'ours' '' }
            else { Note 'exists (not made by this template: it will be configured by it)'; Mark $Def.key $name 'exists' '' }
        } else { Note "new, created in $($script:rgName)"; if (-not $problem) { Mark $Def.key $name 'new' '' } }
        return [pscustomobject]@{ Name = $name; Group = ''; Found = $found }
    }
}

# A resource that may also be shared from another group (ask "shared"): used as it is there (Group
# set), unless it is in this group (Group empty: the template manages it).
function Select-Shared($Def, [string]$Label, [string]$Default) {
    while ($true) {
        $name = Read-Name $Label $Def.type $Default
        $found = Find-Resource $name $Def.armType
        $problem = $null
        if ($found -and $Def.check) { $problem = Test-Found $Def $found }
        if (-not $found -and $Def.free) {
            $problem = Test-Free $Def $name
            if (-not $problem) { $found = Find-Resource $name $Def.armType } # recovered from soft delete
        }
        if ($problem) {
            Note "X $problem"
            if (-not $script:readOnly) { continue }
            Missing "$Label ${name}: $problem"
            Mark $Def.key $name 'problem' ''
        }
        if (-not $found) {
            Note "new, created in $($script:rgName)"
            if (-not $problem) { Mark $Def.key $name 'new' '' }
            return [pscustomobject]@{ Name = $name; Group = ''; Found = $null }
        }
        if (Test-InGroup $found) {
            if (Test-Ours $found) { Note 'exists, made by this template: kept up to date'; Mark $Def.key $name 'ours' '' }
            else { Note 'exists in this resource group: configured by the template'; Mark $Def.key $name 'exists' '' }
            return [pscustomobject]@{ Name = $name; Group = ''; Found = $found }
        }
        Note "exists in $($found.resourceGroup) ($($found.location)): used as it is"
        Mark $Def.key $name 'shared' $found.resourceGroup
        return [pscustomobject]@{ Name = $name; Group = $found.resourceGroup; Found = $found }
    }
}

# A field of a resource, from its variant for the current choice when it has one ("variants").
function Get-Field($Def, [string]$Field) {
    if ($Def.choice -and $Def.variants) {
        $variant = $Def.variants.([string]$script:choices[$Def.choice.answer])
        if ($variant -and $null -ne $variant.$Field) { return $variant.$Field }
    }
    return $Def.$Field
}
function Test-When($Def) {
    if (-not $Def.when) { return $true }
    foreach ($p in $Def.when.PSObject.Properties) { if ([string]$script:choices[$p.Name] -ne [string]$p.Value) { return $false } }
    return $true
}

# One resource of the map: its questions (sub application name, choice, name, size), its checks.
function Read-Resource($Def) {
    $script:currentDef = $Def
    $target = [string]$Def.target
    # An app's own identity has its app's deployment target: the sub application name is the app's question.
    $owner = $null
    if ($Def.owner) { $owner = Get-Def ([string]$Def.owner) }
    if ($target -and -not $script:subs.Contains($target)) {
        if ($owner) { Read-Sub $target $owner.targetLabel $owner.type } else { Read-Sub $target $Def.targetLabel $Def.type }
    }
    $saved = $script:saved
    if ($Def.choice) {
        $default = [string]$Def.choice.default
        if ($saved -and $saved.($Def.choice.answer)) { $default = $saved.($Def.choice.answer) }
        $script:choices[$Def.choice.answer] = Select-Option $Def.choice.label @($Def.choice.options) $default
    }
    $none = [pscustomobject]@{ Name = ''; Group = ''; Found = $null }
    if (-not (Test-When $Def)) { return $none }

    $label = [string](Get-Field $Def 'label')
    $pattern = [string](Get-Field $Def 'pattern')
    $for = [string](Get-Field $Def 'for')
    if ($pattern) { $rule = Fill $naming.$pattern $for (Get-Sub $for) } else { $rule = Get-RuleName $Def.type $target }
    if ($owner -and -not $pattern) { $rule = Get-IdentityRuleName $Def.type $target ([string]$owner.type) }
    # A name the same in every environment (a blob container's, an Event Grid subscription's).
    if ($Def.nameDefault) { $rule = [string]$Def.nameDefault }
    $nameTarget = $target
    if (-not $nameTarget) { $nameTarget = $for }
    $default = Get-Default $Def.key $rule $nameTarget

    switch ([string]$Def.ask) {
        'own' { $r = Select-Own $Def $label $default }
        'shared' { $r = Select-Shared $Def $label $default }
        'name' { $r = [pscustomobject]@{ Name = (Read-Name $label $Def.type $default); Group = ''; Found = $null } }
        'child' {
            # A resource inside another (a database on its server, a queue in its storage account): only a name;
            # the template creates it.
            $name = Read-Name $label $Def.type $default
            $r = [pscustomobject]@{ Name = $name; Group = ''; Found = $null }
            $exists = Test-Child $Def $name
            if ($exists -eq $true) { Note 'exists'; Mark $Def.key $name 'exists' '' }
            elseif ($exists -eq $false) { Note 'new, created by the template'; Mark $Def.key $name 'new' '' }
            else { Note 'created by the template when missing'; Mark $Def.key $name 'saved' '' }
        }
        'workspace' {
            # Needed while one of its Application Insights is created or managed here; its default is the
            # workspace a managed one already uses.
            $group = ''
            if ($saved -and $saved.groups -and $saved.groups.($Def.key)) { $group = $saved.groups.($Def.key) }
            $r = [pscustomobject]@{ Name = $default; Group = $group; Found = $null }
            # One asked after it (the map's order) counts as made here.
            $users = @($Def.neededBy | Where-Object { $_ } | ForEach-Object {
                    if ($script:res.Contains($_)) { $script:res[$_] } else { [pscustomobject]@{ Name = '?'; Group = ''; Found = $null } }
                } | Where-Object { $_ -and $_.Name })
            if (@($users | Where-Object { -not $_.Group }).Count) {
                $managed = $users | Where-Object { $_.Found -and -not $_.Group } | Select-Object -First 1
                if ($managed) {
                    $linked = (Invoke-Az @('resource', 'show', '--ids', $managed.Found.id)).properties.($Def.linkProperty)
                    if ($linked) { $default = ($linked -split '/')[-1] }
                }
                $r = Select-Shared $Def $label $default
            } elseif ($script:ui) { Mark $Def.key $r.Name 'unused' $group }
        }
    }

    # The Entra admin of a server the template makes (SQL): a user's sign-in name or a group's name, saved as
    # "User|<sign-in>|<object id>" or "Group|<name>|<object id>".
    if ($Def.admin -and $r.Name -and -not $r.Group) {
        $savedAdmin = ''
        if ($saved -and $saved.($Def.admin.answer)) { $savedAdmin = [string]$saved.($Def.admin.answer) }
        $parts = $savedAdmin.Split('|')
        $defaultLogin = [string]$script:vals['me']
        if ($savedAdmin) { $defaultLogin = $parts[1] }
        while ($true) {
            $login = Ask $Def.admin.label $defaultLogin
            if ($savedAdmin -and $login -eq $parts[1]) { $script:choices[$Def.admin.answer] = $savedAdmin; break }
            $user = Try-Az @('ad', 'user', 'show', '--id', $login)
            if ($user) { $script:choices[$Def.admin.answer] = "User|$($user.userPrincipalName)|$($user.id)"; Note "Entra admin: the user $($user.displayName)"; break }
            $group = Try-Az @('ad', 'group', 'show', '--group', $login)
            if ($group) { $script:choices[$Def.admin.answer] = "Group|$($group.displayName)|$($group.id)"; Note "Entra admin: the group $($group.displayName) (its members)"; break }
            Note "X no Entra user or group $login"
        }
    }

    if ($Def.size) {
        $size = $Def.size
        $options = @($size.options)
        $value = [string]$size.default
        if ($saved -and $saved.($size.answer)) { $value = $saved.($size.answer) }
        if (-not $r.Group) {
            if ($size.readCurrent -and $r.Found) {
                $current = (Invoke-Az @('resource', 'show', '--ids', $r.Found.id)).sku.name
                if ($options -contains $current) { $value = $current }
                else { Note "the $($Def.title.ToLower()) is $current now; the template sizes it to one of these" }
            }
            if ($options -notcontains $value) { $value = [string]$size.default }
            $value = Select-Option $size.label $options $value
        }
        $script:choices[$size.answer] = $value
    }
    return $r
}

# Whether a resource inside another exists: $true, $false, or $null when it can't be told (a storage
# queue: only its data roles could list it).
function Test-Child($Def, [string]$Name) {
    if ($Def.probe -ne 'sqlDatabase') { return $null }
    $hostLink = @($map.connections | Where-Object { $_.from -eq $Def.key -and $_.kind -eq 'host' }) | Select-Object -First 1
    $server = $null
    if ($hostLink) { $server = $script:res[$hostLink.to] }
    if (-not $server -or -not $server.Name) { return $null }
    if (-not $server.Found) { return $false }
    $group = $server.Group
    if (-not $group) { $group = $script:rgName }
    return [bool](Try-Az @('sql', 'db', 'show', '-g', $group, '-s', $server.Name, '-n', $Name))
}

# --- the apps' identities ----------------------------------------------------------------------------

# Every app signs in as its own user-assigned identity (the map's "identity": a resource of kind appIdentity
# with the app as its "owner"; infra/LAZYBICEP.md, "Identity"). An app entry without one (a map from before
# 0.2.0) still has its system-assigned identity. Role assignments, database users and removal go through it.

# An identity of the map as Azure has it (clientId, principalId, id), or $null while it doesn't exist. Only a
# found one is kept for the run (the template creates it during the run).
$script:identities = @{}
function Get-IdentityOf([string]$Key) {
    if ($script:identities.ContainsKey($Key)) { return $script:identities[$Key] }
    $r = $script:res[$Key]
    if (-not $r -or -not $r.Name -or -not $script:rgName) { return $null }
    $ident = Try-Az @('identity', 'show', '-g', $script:rgName, '-n', $r.Name)
    if ($ident -and $ident.principalId) { $script:identities[$Key] = $ident }
    return $ident
}
# The identity an app signs in with: Name, Id, PrincipalId, ClientId (empty for a system-assigned identity: its
# service principal's appId, read when needed) and System. $null while there is none. $IdentityName: the
# app's own identity (in $Group, the environment's); $App: the app as Azure shows it, for an entry without one.
function Get-AppIdentity($Def, [string]$Group, [string]$IdentityName, $App) {
    if ($Def.identity) {
        if (-not $IdentityName -or -not $Group) { return $null }
        $ident = Try-Az @('identity', 'show', '-g', $Group, '-n', $IdentityName)
        if (-not ($ident -and $ident.principalId)) { return $null }
        return [pscustomobject]@{ Name = [string]$ident.name; Id = [string]$ident.id; PrincipalId = [string]$ident.principalId; ClientId = [string]$ident.clientId; System = $false }
    }
    if (-not ($App -and $App.identity -and $App.identity.principalId)) { return $null }
    return [pscustomobject]@{ Name = [string]$App.name; Id = ''; PrincipalId = [string]$App.identity.principalId; ClientId = ''; System = $true }
}
# The same during a run (the answers and the apps as this run found them).
function Get-RunIdentity([string]$AppKey) {
    $def = Get-Def $AppKey
    if (-not $def) { return $null }
    if ($def.identity) {
        $ident = Get-IdentityOf ([string]$def.identity)
        if (-not $ident) { return $null }
        return [pscustomobject]@{ Name = [string]$ident.name; Id = [string]$ident.id; PrincipalId = [string]$ident.principalId; ClientId = [string]$ident.clientId; System = $false }
    }
    return Get-AppIdentity $def $script:rgName '' $script:apps[$AppKey]
}
# An app's settings as main.bicep writes them: the map's, and for a function app with its own identity the
# <Name>__credential / <Name>__clientId that follow each identity-based connection (<Name>__fullyQualifiedNamespace,
# __serviceUri, __accountName... to a resource of the map: the Functions host's triggers and bindings) unless the map
# sets them; the same rule as infra/generate.ps1 (Get-Settings). Other apps get AZURE_CLIENT_ID only. Other settings
# an app has are never flagged.
$identityConnections = @('accountName', 'fullyQualifiedNamespace', 'serviceUri', 'blobServiceUri', 'queueServiceUri', 'tableServiceUri', 'endpoint', 'uri')
function Get-ExpectedSettings($Def) {
    $settings = @($Def.appSettings | Where-Object { $_ })
    if (-not $Def.identity -or $Def.kind -ne 'functionApp') { return $settings }
    $have = @($settings | ForEach-Object { [string]$_.name })
    $out = @()
    foreach ($s in $settings) {
        $out += $s
        $name = [string]$s.name
        $at = $name.LastIndexOf('__')
        if ($at -lt 1 -or $name -like 'ConnectionStrings__*' -or $identityConnections -notcontains $name.Substring($at + 2)) { continue }
        if (-not @([regex]::Matches([string]$s.value, '[{|](\w+)\.') | Where-Object { Get-Def $_.Groups[1].Value }).Count) { continue }
        $prefix = $name.Substring(0, $at)
        foreach ($p in @(@('credential', 'managedidentity'), @('clientId', "{$($Def.identity).clientId}"))) {
            $n = "${prefix}__$($p[0])"
            if ($have -contains $n) { continue }
            $have += $n
            $out += [pscustomobject]@{ name = $n; value = $p[1] }
        }
    }
    return $out
}
# Role assignments of an identity, wherever they are (a vault shared from another group too).
function Get-RoleAssignments([string]$PrincipalId) {
    return @(Try-Az @('role', 'assignment', 'list', '--assignee', $PrincipalId, '--all') | Where-Object { $_ })
}

# The two ways an app's identity can be misused, reported only (nothing is changed): an identity in the
# environment's group that no app of the map owns (its app deleted outside the setup, or made by hand: it keeps
# its roles), and a role at an app identity's own scope that lets someone attach it to another resource
# (Microsoft.ManagedIdentity/userAssignedIdentities/assign/action). Roles inherited from the group or the
# subscription are the administrators' and not reported.
$borrowRoles = @('Managed Identity Operator', 'Managed Identity Contributor', 'Contributor', 'Owner', 'User Access Administrator')
function Test-AppIdentities {
    $owned = @{}
    foreach ($d in @($defs | Where-Object { $_.owner -and $_.armType -eq $identityType })) {
        $n = [string]$script:res[$d.key].Name
        if ($n) { $owned[$n.ToLower()] = $d }
    }
    foreach ($ident in @(Try-Az @('identity', 'list', '-g', $script:rgName) | Where-Object { $_ })) {
        $d = $owned[([string]$ident.name).ToLower()]
        if (-not $d) {
            $made = 'not made by this template'
            if ($ident.tags -and $ident.tags.'managed-by' -eq $managedBy) { $made = 'made by this template' }
            Missing "identity $($ident.name) in $($script:rgName) ($made): no app of the map owns it; it keeps its roles (remove it once nothing uses it: az identity delete --ids $($ident.id))"
            continue
        }
        $risky = @(Try-Az @('role', 'assignment', 'list', '--scope', $ident.id) | Where-Object { $_ -and ([string]$_.scope) -ieq [string]$ident.id -and $borrowRoles -contains [string]$_.roleDefinitionName })
        foreach ($a in $risky) {
            $who = [string]$a.principalName
            if (-not $who) { $who = [string]$a.principalId }
            Missing "identity $($ident.name) of $($d.owner): $($a.roleDefinitionName) for $who ($($a.principalType)) on it lets them attach it to other resources (az role assignment delete --ids $($a.id))"
        }
        if (-not $risky.Count) { Ok "identity $($ident.name) of $($d.owner): no role at its own scope to attach it elsewhere" }
    }
}

# --- container apps: image, secrets, sign-in ----------------------------------------------------------------

# The container apps of the map that run in an environment or pull from a registry (their "environment" /
# "registry", or a connection to it).
function Get-ContainerAppsUsing([string]$Key) {
    $out = @()
    foreach ($a in @($defs | Where-Object { $_.armType -eq $containerAppType })) {
        $linked = @($map.connections | Where-Object { $_ -and $_.from -eq $a.key -and @(([string]$_.to).Split('|')) -contains $Key }).Count
        if ([string]$a.environment -eq $Key -or [string]$a.registry -eq $Key -or $linked) { $out += [string]$a.key }
    }
    return $out
}
# main.bicep's image of a container app (<key>Image): the image Azure runs now, '' for the placeholder (a new app, or
# one still on it). Unknown ($null) when the app exists but its image can't be read: then the template is not deployed
# (it would put the placeholder back).
function Get-ImageParam([string]$Key) {
    $r = $script:res[$Key]
    if (-not ($r -and $r.Found)) { return '' }
    $image = Get-AppImage $script:apps[$Key]
    if (-not $image) { return $null }
    if (Test-PlaceholderImage $image) { return '' }
    return $image
}
# The newest image a container app's workflow pushed to its registry (repository: the app's key in lowercase words,
# adminApi -> admin-api, tagged with the commit), as <login server>/<repository>:<tag>; '' when there is none.
function Get-PushedImage($Def, [string]$Tag) {
    $regKey = [string]$Def.registry
    if (-not $regKey) { $regKey = [string](@($map.connections | Where-Object { $_.from -eq $Def.key -and (Get-Def $_.to).armType -eq $registryType } | ForEach-Object { $_.to }) | Select-Object -First 1) }
    $reg = $script:res[$regKey]
    if (-not ($reg -and $reg.Name -and $reg.Found)) { return '' }
    $repo = ([string]$Def.key -creplace '([a-z0-9])([A-Z])', '$1-$2').ToLowerInvariant()
    $tags = @(Try-Az @('acr', 'repository', 'show-tags', '--name', $reg.Name, '--repository', $repo, '--orderby', 'time_desc', '--top', '10') | Where-Object { $_ })
    if (-not $tags.Count) { return '' }
    # A given tag (the commit a run built) only when it is there; else the newest.
    $pick = [string]$tags[0]
    if ($Tag) { if ($tags -contains $Tag) { $pick = $Tag } else { return '' } }
    $server = [string](Try-Az @('acr', 'show', '--name', $reg.Name, '--query', 'loginServer'))
    if (-not $server) { $server = "$($reg.Name).azurecr.io" }
    return "$server/${repo}:$pick"
}
# Whether the sign-in in front of a container app is on in Azure with this client id (its first image waits for it).
function Test-SignInReady($Def, [string]$ClientId) {
    if (-not $ClientId) { return $false }
    $auth = Try-Az @('containerapp', 'auth', 'show', '-g', $script:rgName, '-n', [string]$script:res[$Def.key].Name)
    $cfg = $auth
    if ($auth -and $auth.properties) { $cfg = $auth.properties }
    if (-not ($cfg -and $cfg.platform -and $cfg.platform.enabled -eq $true -and $cfg.identityProviders -and $cfg.identityProviders.azureActiveDirectory)) { return $false }
    $aad = $cfg.identityProviders.azureActiveDirectory
    return [bool]($aad.enabled -ne $false -and $aad.registration -and [string]$aad.registration.clientId -eq $ClientId)
}
# The Key Vault secrets a container app's settings read (@Microsoft.KeyVault(VaultName=...;SecretName=...)) that are
# not in their vault yet, as @{ Vault; Secret; Ref } (names only). Its first image waits for them: a revision with a
# missing Key Vault secret doesn't start. ({secret.<name>}: the setup keeps it, main.bicep writes it.)
function Get-MissingMapSecrets($Def) {
    $out = @()
    foreach ($s in @($Def.appSettings | Where-Object { $_ })) {
        $v = [string]$s.value
        if ($v -notmatch 'SecretName=([^;)\s]+)') { continue }
        $secret = $Matches[1]
        if (-not (Test-SecretName $secret)) { Missing "$($Def.key): its setting $($s.name) names the Key Vault secret $secret (letters, digits and - only): not checked"; continue }
        $vault = ''
        if ($v -match 'VaultName=\{(\w+)\.name\}') { if ($script:res[$Matches[1]]) { $vault = [string]$script:res[$Matches[1]].Name } }
        elseif ($v -match 'VaultName=([^;)\s{}]+)') { $vault = $Matches[1] }
        if (-not $vault) { continue }
        $id = Get-VaultId $vault
        if (-not $id) { continue }
        if (-not (Try-Az @('resource', 'show', '--ids', "$id/secrets/$secret"))) { $out += [pscustomobject]@{ Vault = $vault; Secret = $secret; Ref = [string]$s.name } }
    }
    return $out
}
# The command that makes an app read its Key Vault secrets again: a container app's revision restarted (a versionless
# Key Vault reference also restarts it by itself within about 30 minutes of a new version), an App Service restarted.
function Get-RestartCommand([string]$Key) {
    $d = Get-Def $Key
    $n = [string]$script:res[$Key].Name
    $g = $script:rgName
    if ($d.armType -eq $containerAppType) {
        $rev = "(az containerapp show -g $g -n $n --query properties.latestRevisionName -o tsv)"
        $app = $script:apps[$Key]
        if ($app -and $app.properties -and $app.properties.latestRevisionName) { $rev = [string]$app.properties.latestRevisionName }
        return "az containerapp revision restart -g $g -n $n --revision $rev"
    }
    if ($d.kind -eq 'functionApp') { return "az functionapp restart -g $g -n $n" }
    return "az webapp restart -g $g -n $n"
}
# A vault's resource id by its name: one of the map's, else looked up (management plane only, never a secret value).
function Get-VaultId([string]$Vault) {
    foreach ($d in @($defs | Where-Object { $_.armType -eq 'Microsoft.KeyVault/vaults' })) {
        $r = $script:res[$d.key]
        if (-not ($r -and $r.Name -ieq $Vault)) { continue }
        if ($r.Found) { return [string]$r.Found.id }
        $g = $r.Group
        if (-not $g) { $g = $script:rgName }
        return "/subscriptions/$($script:subscription)/resourceGroups/$g/providers/Microsoft.KeyVault/vaults/$($r.Name)"
    }
    return [string](Try-Az @('keyvault', 'show', '--name', $Vault, '--query', 'id'))
}
# The Key Vault secrets a container app references (its secrets with a keyVaultUrl): each must exist, or the app's
# revision can't start. Checked as resources (names only); the values are never read. The missing ones, as
# @{ Vault; Secret; Ref } for the next steps.
function Test-ContainerAppSecrets([string]$Key) {
    $app = $script:apps[$Key]
    if (-not ($app -and $app.properties -and $app.properties.configuration)) { return @() }
    $name = [string]$script:res[$Key].Name
    $lacking = @()
    foreach ($s in @($app.properties.configuration.secrets | Where-Object { $_ -and $_.keyVaultUrl })) {
        if ([string]$s.keyVaultUrl -notmatch '^https://([^./]+)\.vault\.[^/]+/secrets/([^/?]+)') { continue }
        $vault = $Matches[1]
        $secretName = $Matches[2]
        if (-not (Test-SecretName $secretName)) { Missing "${name}: its secret $($s.name) names the Key Vault secret $secretName (letters, digits and - only): not checked"; continue }
        $vaultId = Get-VaultId $vault
        if (-not $vaultId) { Missing "${name}: the Key Vault $vault of its secret $($s.name) is not found"; continue }
        if (Try-Az @('resource', 'show', '--ids', "$vaultId/secrets/$secretName")) { Ok "${name}: Key Vault secret $secretName ($vault)" }
        else {
            Missing "${name}: Key Vault secret $secretName in $vault is missing (its revision can't start without it; the next steps say how)"
            $lacking += [pscustomobject]@{ Vault = $vault; Secret = $secretName; Ref = [string]$s.name }
        }
    }
    return $lacking
}

# Sign-in in front of a container app (the map's "signIn"; docs/architecture/container-apps.md): Container Apps'
# built-in sign-in with Microsoft Entra ID (main.bicep's authConfigs, made once <key>SignInClientId is known) and its
# app registration per environment, made by the step "Sign-in app registrations": named after the app, single tenant,
# redirect https://<fqdn>/.auth/login/aad/callback, ID tokens (no client secret: the platform signs users in with the
# ID token), optional identifier URI api://<client id> and app roles, Assignment required with the group asked per
# environment. The client id and the group are saved with the environment's answers.
# On with "signIn": { "provider": "entra" } or "signIn": "entra"; off without it or with provider none (infra/generate.ps1, the same rule).
function Test-SignInOn($Def) {
    if (-not ($Def -and $Def.signIn)) { return $false }
    $provider = [string]$Def.signIn
    if ($Def.signIn -isnot [string]) { $provider = [string]$Def.signIn.provider }
    return [bool]($provider -and $provider -ne 'none')
}
function Get-SignInDefs { return @($defs | Where-Object { $_.armType -eq $containerAppType -and (Test-SignInOn $_) }) }
function Get-SignInClientIdAnswer([string]$Key) { return "${Key}SignInClientId" }
function Get-SignInGroupAnswer([string]$Key) { return "${Key}SignInGroup" }
function Test-Yes($Value) {
    if ($Value -is [bool]) { return $Value }
    return @('true', 'yes', 'y', '1') -contains ([string]$Value).ToLower()
}
function Get-SignInObjectIdAnswer([string]$Key) { return "${Key}SignInObjectId" }
# GitHub Actions' app registration's client id in the environment's answers (<deploy key>ClientId).
function Get-DeployClientIdAnswer([string]$Key) { return "${Key}ClientId" }

# --- input checked before it goes to az / gh ---------------------------------------------------------------
function Test-Guid([string]$Value) { return [bool]($Value -match '^[0-9a-fA-F-]{36}$') }
function Test-SecretName([string]$Value) { return [bool]($Value -cmatch '^[0-9A-Za-z-]{1,127}$') }
# A redirect or identifier URI the setup writes into an app registration.
function Test-SafeUri([string]$Value) { return [bool]($Value -cmatch '^(https://[A-Za-z0-9.-]+(:\d+)?(/[A-Za-z0-9._~/-]*)?|api://[0-9a-fA-F-]{36})$') }

# --- Entra objects: by their id when one is known, by display name only when owned by you alone ---------------
# A display name is no proof of ownership: anyone who may create app registrations can make one with the name the
# setup would look for. So an app registration is used by the id the environment saved (or the one Azure runs with);
# by its name only when no id is known, exactly one has the name and its owners are you alone (the allow-list:
# just the signed-in operator for now).
function Get-OperatorId {
    if ($null -eq $script:operatorId) { $script:operatorId = [string](Try-Az @('ad', 'signed-in-user', 'show', '--query', 'id')) }
    return $script:operatorId
}
function Get-AllowedOwners { return @(@(Get-OperatorId) | Where-Object { $_ }) }
# The owners of an app registration ('app') or service principal ('sp') as @{ Id; Name }: an empty list when it has
# none, $null when they can't be read.
function Get-EntraOwners([string]$Kind, [string]$Id) {
    try { $list = Invoke-Az @('ad', $Kind, 'owner', 'list', '--id', $Id) } catch { return $null }
    return , @($list | Where-Object { $_ } | ForEach-Object {
            $n = [string]$_.userPrincipalName
            if (-not $n) { $n = [string]$_.displayName }
            [pscustomobject]@{ Id = [string]$_.id; Name = $n }
        })
}
# You as an owner of a service principal (az has no command for it: Microsoft Graph, the body from a file).
function Add-SpOwner([string]$SpId, [string]$OwnerId) {
    if (-not ((Test-Guid $SpId) -and (Test-Guid $OwnerId))) { throw "not an object id: $SpId / $OwnerId" }
    $body = Write-TempJson 'owner.json' @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$OwnerId" }
    Invoke-Az @('rest', '--method', 'post', '--url', "https://graph.microsoft.com/v1.0/servicePrincipals/$SpId/owners/`$ref", '--headers', 'Content-Type=application/json', '--body', "@$body") | Out-Null
}
function Test-OwnedByOperator($Owners) {
    $op = Get-OperatorId
    if ($null -eq $Owners -or -not $op) { return $false }
    $ids = @($Owners | ForEach-Object { $_.Id })
    $allowed = @(Get-AllowedOwners)
    return [bool]($ids -contains $op -and -not @($ids | Where-Object { $allowed -notcontains $_ }).Count)
}
function Get-OwnersText($Owners) {
    if ($null -eq $Owners) { return 'unreadable' }
    if (-not @($Owners).Count) { return 'none' }
    return (@($Owners | ForEach-Object { if ($_.Name) { $_.Name } else { $_.Id } }) -join ', ')
}
# The app registrations named exactly so.
function Find-SignInRegistration([string]$DisplayName) {
    return @(Try-Az @('ad', 'app', 'list', '--display-name', $DisplayName) | Where-Object { $_ -and [string]$_.displayName -ceq $DisplayName })
}
# The credentials on an app registration that the setup didn't make: client secrets, certificates, and federated
# credentials other than GitHub Actions' with a subject in $Subjects (the sign-in app has none of its own).
# @{ Kind 'secret' / 'certificate' / 'federated'; Text } each, empty when there are none; $null when its federated
# credentials can't be read.
function Get-ForeignCredentials($Reg, [string[]]$Subjects) {
    $githubIssuer = 'https://token.actions.githubusercontent.com'
    $appId = [string]$Reg.appId
    $out = @()
    foreach ($c in @($Reg.passwordCredentials | Where-Object { $_ })) { $out += [pscustomobject]@{ Kind = 'secret'; Text = "client secret $($c.displayName) ($($c.keyId)): az ad app credential delete --id $appId --key-id $($c.keyId)" } }
    foreach ($c in @($Reg.keyCredentials | Where-Object { $_ })) { $out += [pscustomobject]@{ Kind = 'certificate'; Text = "certificate $($c.displayName) ($($c.keyId)): az ad app credential delete --id $appId --key-id $($c.keyId) --cert" } }
    try { $fics = @(Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $appId) | Where-Object { $_ }) } catch { return $null }
    foreach ($c in @($fics | Where-Object { -not ([string]$_.issuer -ceq $githubIssuer -and @($Subjects) -ccontains [string]$_.subject) })) {
        $out += [pscustomobject]@{ Kind = 'federated'; Text = "federated credential $($c.name) trusting $($c.issuer) $($c.subject): az ad app federated-credential delete --id $appId --federated-credential-id $($c.id)" }
    }
    return , $out
}
# Why an app registration found only by its display name is not taken over ('' when it may be): whoever made it can
# have put a way in before handing it to you - a client secret, a certificate, a federated credential, (sign-in app)
# a redirect other than the app's callback ($Redirect; '' while unknown: none at all), or a service principal that
# others own (they can add credentials to it). Unreadable counts as not clean. @{ Problem; App (as Entra has it) }.
function Get-AdoptionProblem([string]$AppId, [string]$Redirect, [switch]$SignIn) {
    if (-not (Test-Guid $AppId)) { return [pscustomobject]@{ Problem = "$AppId is no client id"; App = $null } }
    $full = Try-Az @('ad', 'app', 'show', '--id', $AppId)
    if (-not $full) { return [pscustomobject]@{ Problem = 'it is not readable'; App = $null } }
    $p = @()
    if (@($full.passwordCredentials | Where-Object { $_ }).Count) { $p += 'it has a client secret' }
    if (@($full.keyCredentials | Where-Object { $_ }).Count) { $p += 'it has a certificate' }
    try { $fics = @(Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $AppId) | Where-Object { $_ }) } catch { $fics = $null }
    if ($null -eq $fics) { $p += 'its federated credentials are not readable' }
    elseif ($fics.Count) { $p += "it trusts $((@($fics | ForEach-Object { [string]$_.subject })) -join ', ') (federated credentials)" }
    if ($SignIn) {
        $web = @()
        if ($full.web) { $web = @($full.web.redirectUris | Where-Object { $_ }) }
        $more = @()
        if ($full.spa) { $more += @($full.spa.redirectUris | Where-Object { $_ }) }
        if ($full.publicClient) { $more += @($full.publicClient.redirectUris | Where-Object { $_ }) }
        $webOk = (-not $web.Count) -or ($web.Count -eq 1 -and $Redirect -and [string]$web[0] -ceq $Redirect)
        if ($more.Count -or -not $webOk) { $p += "it redirects to $((@($web) + @($more)) -join ', ')$(if ($Redirect) { " (only $Redirect)" } else { ' (none while the app''s address is unknown)' })" }
    }
    try { $sps = @(Invoke-Az @('ad', 'sp', 'list', '--filter', "appId eq '$AppId'") | Where-Object { $_ }) } catch { $sps = $null }
    if ($null -eq $sps) { $p += 'its service principal is not readable' }
    foreach ($sp in @($sps | Where-Object { $_ })) {
        $spOwners = Get-EntraOwners 'sp' ([string]$sp.id)
        if (-not (Test-OwnedByOperator $spOwners)) { $p += "its service principal's owners are $(Get-OwnersText $spOwners), not you alone" }
    }
    return [pscustomobject]@{ Problem = ($p -join '; '); App = $full }
}
# The app registration to use for $DisplayName: the one with $ClientId when an id is known (one named so with
# another id is only reported, never switched to); by its name only when no id is known, exactly one has the name,
# you alone own it and it is clean (Get-AdoptionProblem; -SignIn with its $Redirect for a sign-in app).
# @{ App (or $null); Source 'id' / 'name' / 'none'; Problem; Note }.
function Resolve-EntraApp([string]$DisplayName, [string]$ClientId, [string]$Answer, [string]$Redirect = '', [switch]$SignIn) {
    $out = [pscustomobject]@{ App = $null; Source = 'none'; Problem = ''; Note = '' }
    if ($ClientId) {
        if (-not (Test-Guid $ClientId)) { $out.Problem = "$Answer $ClientId is not a client id (fix it in the environment's answers)"; return $out }
        $named = @(Find-SignInRegistration $DisplayName | Where-Object { [string]$_.appId -ne $ClientId })
        if ($named.Count) { $out.Note = "also named ${DisplayName}: $((@($named | ForEach-Object { $_.appId })) -join ', ') (not used: the saved $Answer $ClientId is)" }
        $app = Try-Az @('ad', 'app', 'show', '--id', $ClientId)
        if (-not $app) { $out.Problem = "its app registration $ClientId ($Answer) is not found or not readable (deleted? Entra keeps a deleted one 30 days); nothing is created or adopted by name instead"; return $out }
        $out.App = $app
        $out.Source = 'id'
        return $out
    }
    $regs = @(Find-SignInRegistration $DisplayName)
    if (-not $regs.Count) { return $out }
    if ($regs.Count -gt 1) { $out.Problem = "$($regs.Count) app registrations are named $DisplayName ($((@($regs | ForEach-Object { $_.appId })) -join ', ')): none is used by its name; put the right one's client id into the environment's answers as $Answer"; return $out }
    $owners = Get-EntraOwners 'app' ([string]$regs[0].appId)
    if (-not (Test-OwnedByOperator $owners)) {
        $out.Problem = "the app registration $DisplayName ($($regs[0].appId)) is not taken over by its name: its owners are $(Get-OwnersText $owners), not you alone; if it is this environment's, put its client id into the environment's answers as $Answer"
        return $out
    }
    $clean = Get-AdoptionProblem ([string]$regs[0].appId) $Redirect -SignIn:$SignIn
    if ($clean.Problem) {
        $out.Problem = "the app registration $DisplayName ($($regs[0].appId)) is not taken over by its name: $($clean.Problem); check it, then put its client id into the environment's answers as $Answer (or delete it)"
        return $out
    }
    $out.App = $clean.App
    $out.Source = 'name'
    return $out
}
# The service principal of the app registration GitHub Actions deploys with, before any role or database user is
# given to it. Whoever owns it can give it a credential and deploy as it, so (the gate of Set-SignInApp) one owned
# by you alone is used; one without owners when you become its owner (asked); one with other owners never.
# @{ Principal (or $null); Refused ($true: no role or database user for it) }.
function Get-DeployPrincipal($Entra, [string]$DeployApp) {
    $op = Get-OperatorId
    $principal = Try-Az @('ad', 'sp', 'show', '--id', [string]$Entra.appId)
    if ($principal) {
        $spOwners = Get-EntraOwners 'sp' ([string]$principal.id)
        if (Test-OwnedByOperator $spOwners) { Ok 'service principal (owned by you alone)'; return [pscustomobject]@{ Principal = $principal; Refused = $false } }
        if ($null -ne $spOwners -and -not @($spOwners).Count -and $op) {
            $spId = [string]$principal.id
            if (Invoke-Fix "${DeployApp}: its service principal has no owner (no role is given to it until you are)" "Make you the owner of the service principal of $DeployApp?" { Add-SpOwner $spId $op } "${DeployApp}: service principal owned by you") { return [pscustomobject]@{ Principal = $principal; Refused = $false } }
            return [pscustomobject]@{ Principal = $null; Refused = $true }
        }
        Missing "${DeployApp}: its service principal has the owners $(Get-OwnersText $spOwners), not you alone: no role or database user is given to it (remove the others in Enterprise applications -> $DeployApp -> Owners)"
        return [pscustomobject]@{ Principal = $null; Refused = $true }
    }
    if (-not $op) { Missing "${DeployApp}: service principal (made only by a signed-in user, its owner)"; return [pscustomobject]@{ Principal = $null; Refused = $true } }
    if (Confirm-Step 'Create its service principal (you its owner)?') {
        $principal = Invoke-Az @('ad', 'sp', 'create', '--id', [string]$Entra.appId)
        if (-not (Test-OwnedByOperator (Get-EntraOwners 'sp' ([string]$principal.id)))) { Add-SpOwner ([string]$principal.id) $op }
        Ok 'service principal created'
        return [pscustomobject]@{ Principal = $principal; Refused = $false }
    }
    Missing 'service principal'
    return [pscustomobject]@{ Principal = $null; Refused = $false }
}
# The redirect of a container app's sign-in (its callback), '' while the app's address is unknown.
function Get-SignInRedirect($Def) {
    $fqdn = Get-AppHost $script:apps[[string]$Def.key]
    if (-not $fqdn) { return '' }
    return "https://$fqdn/.auth/login/aad/callback"
}
# The client id the sign-in in front of a container app runs with in Azure (authConfigs), '' without one.
function Get-LiveSignInClientId($Def) {
    $r = $script:res[[string]$Def.key]
    if (-not ($r -and $r.Name)) { return '' }
    $g = [string]$r.Group
    if (-not $g) { $g = $script:rgName }
    $auth = Try-Az @('containerapp', 'auth', 'show', '-g', $g, '-n', [string]$r.Name)
    $cfg = $auth
    if ($auth -and $auth.properties) { $cfg = $auth.properties }
    if ($cfg -and $cfg.identityProviders -and $cfg.identityProviders.azureActiveDirectory -and $cfg.identityProviders.azureActiveDirectory.registration) {
        $id = [string]$cfg.identityProviders.azureActiveDirectory.registration.clientId
        if (Test-Guid $id) { return $id }
    }
    return ''
}
# Step 0 for one container app with sign-in: the group whose members may sign in (saved as "<name>|<object id>", or
# '-'), and the client id of its app registration, in this order: the saved one; the one Azure's sign-in runs with;
# only when neither exists, the one registration with the app's name that you alone own (Resolve-EntraApp).
function Read-SignIn($Def) {
    $key = [string]$Def.key
    $groupAnswer = Get-SignInGroupAnswer $key
    $savedGroup = ''
    if ($script:saved -and $script:saved.$groupAnswer) { $savedGroup = [string]$script:saved.$groupAnswer }
    $at = $savedGroup.LastIndexOf('|')
    $savedName = $savedGroup
    $savedId = ''
    if ($at -ge 0) { $savedName = $savedGroup.Substring(0, $at); $savedId = $savedGroup.Substring($at + 1) }
    # A saved group id that is no object id is not used (asked again).
    if ($savedId -and -not (Test-Guid $savedId)) { Note "X ${groupAnswer}: $savedId is not an object id (asked again)"; $savedId = '' }
    $default = '-'
    if ($savedName) { $default = $savedName }
    while ($true) {
        $a = Ask "Entra group whose members may sign in to $($Def.title) in $($script:envAbbr) (name or object id; '-' for none: nobody signs in until someone is assigned)" $default
        if ($a -eq '-') { $script:choices[$groupAnswer] = '-'; break }
        if ($savedId -and ($a -eq $savedName -or $a -eq $savedId)) { $script:choices[$groupAnswer] = $savedGroup; break }
        if ($a -match '["%\r\n|]') { Note "X a group name without "", %, | or line breaks"; continue }
        $group = Try-Az @('ad', 'group', 'show', '--group', $a)
        # Only the id Entra returns is used (never the typed text).
        if ($group -and (Test-Guid ([string]$group.id))) { $script:choices[$groupAnswer] = "$(([string]$group.displayName) -replace '\|', ' ')|$($group.id)"; Note "sign-in: the members of $($group.displayName)"; break }
        Note "X no Entra group $a (or no right to read it)"
    }
    $idAnswer = Get-SignInClientIdAnswer $key
    $objAnswer = Get-SignInObjectIdAnswer $key
    $clientId = ''
    $objectId = ''
    if ($script:saved -and $script:saved.$idAnswer) { $clientId = [string]$script:saved.$idAnswer }
    if ($script:saved -and $script:saved.$objAnswer) { $objectId = [string]$script:saved.$objAnswer }
    if (-not $clientId) {
        $clientId = Get-LiveSignInClientId $Def
        if ($clientId) { $objectId = ''; Note "sign-in of $($script:res[$key].Name): app registration $clientId (what its sign-in runs with in Azure)" }
    }
    $name = [string]$script:res[$key].Name
    if (-not $clientId -and $name) {
        $r = Resolve-EntraApp $name '' $idAnswer (Get-SignInRedirect $Def) -SignIn
        if ($r.App) {
            $clientId = [string]$r.App.appId
            $objectId = [string]$r.App.id
            Note "sign-in of ${name}: app registration $clientId (by its name: you alone own it)"
        }
    }
    $script:choices[$idAnswer] = $clientId
    $script:choices[$objAnswer] = $objectId
}
# Whether a container app with sign-in may not be deployed: it runs its own image, but its sign-in's app
# registration is unknown (Read-SignIn found none) - the template would go out without the sign-in in front of it.
function Test-SignInUnknown($Def) {
    if (-not (Test-SignInOn $Def)) { return $false }
    if ([string]$script:choices[(Get-SignInClientIdAnswer ([string]$Def.key))]) { return $false }
    $image = Get-ImageParam ([string]$Def.key)
    return [bool]$image
}
# The paths that pass without sign-in, the rule of infra/generate.ps1 (Get-SignInExcludedPaths): the health path
# (set and not '-'), then the map's signIn.excludedPaths, each "/x/*" preceded by "/x" (the wildcard doesn't cover
# it), without repeats.
function Get-ExcludedPaths($Def) {
    $paths = @()
    $health = [string]$Def.healthCheckPath
    if ($health -and $health -ne '-') { $paths += $health }
    if ($Def.signIn -and $Def.signIn -isnot [string]) {
        foreach ($p in @($Def.signIn.excludedPaths | Where-Object { $_ })) {
            $p = [string]$p
            if ($p.EndsWith('/*')) { $paths += $p.Substring(0, $p.Length - 2) }
            $paths += $p
        }
    }
    $unique = @()
    foreach ($p in $paths) { if ($p -and $unique -cnotcontains $p) { $unique += $p } }
    return $unique # callers wrap it: @(Get-ExcludedPaths $Def)
}
# What makes a sign-in's paths unusable ('' when nothing): the root never passes without sign-in (generate.ps1
# refuses it too) - a health path or an excluded path of '/' or '/*'.
function Get-SignInPathProblem($Def) {
    $health = [string]$Def.healthCheckPath
    if ($health -eq '/' -or $health -eq '/*') { return "health path $health with sign-in would leave the whole app without sign-in (it passes without sign-in): use a path of its own, e.g. /health" }
    if ($Def.signIn -and $Def.signIn -isnot [string]) {
        foreach ($p in @($Def.signIn.excludedPaths | Where-Object { $_ })) {
            if (-not ([string]$p).StartsWith('/') -or $p -eq '/' -or $p -eq '/*') { return "signIn.excludedPaths $p (a path from /, not all of them)" }
        }
    }
    return ''
}
# The platform's action for a request without sign-in: the map's "redirect" (the default) or "401" / "403".
function Get-UnauthenticatedAction($SignIn) {
    $u = ([string]$SignIn.unauthenticated).ToLower()
    if ($u -match '401') { return 'Return401' }
    if ($u -match '403') { return 'Return403' }
    return 'RedirectToLoginPage'
}
# One app role of the map as Microsoft Graph has it ("allowed": Application and/or User; displayName and description
# default to the value).
function ConvertTo-AppRole($Wanted, [string]$Id) {
    $allowed = @()
    foreach ($a in @($Wanted.allowed | Where-Object { $_ })) {
        switch -Regex (([string]$a).ToLower()) {
            '^app' { if ($allowed -notcontains 'Application') { $allowed += 'Application' } }
            '^user' { if ($allowed -notcontains 'User') { $allowed += 'User' } }
        }
    }
    if (-not $allowed.Count) { $allowed = @('Application') }
    $display = [string]$Wanted.displayName
    if (-not $display) { $display = [string]$Wanted.value }
    $description = [string]$Wanted.description
    if (-not $description) { $description = $display }
    return [pscustomobject][ordered]@{ allowedMemberTypes = @($allowed); description = $description; displayName = $display; id = $Id; isEnabled = $true; value = [string]$Wanted.value }
}
# The app roles to write: the registration's (by value; one of the map changed in place, keeping its id), then the
# map's new ones. Roles the map doesn't list are kept (removing one needs it disabled first: by hand). Changes: what
# differs, empty when nothing does.
function Get-AppRolesPlan($Existing, $Wanted) {
    $wantedList = @($Wanted | Where-Object { $_ -and $_.value })
    $roles = @()
    $changes = @()
    foreach ($e in @($Existing | Where-Object { $_ })) {
        $role = [pscustomobject][ordered]@{ allowedMemberTypes = @($e.allowedMemberTypes); description = [string]$e.description; displayName = [string]$e.displayName; id = [string]$e.id; isEnabled = [bool]$e.isEnabled; value = [string]$e.value }
        $w = $wantedList | Where-Object { [string]$_.value -ceq [string]$e.value } | Select-Object -First 1
        if ($w) {
            $n = ConvertTo-AppRole $w ([string]$e.id)
            $same = ((@($n.allowedMemberTypes | Sort-Object) -join ',') -eq (@($role.allowedMemberTypes | Sort-Object) -join ',')) -and $n.description -ceq $role.description -and $n.displayName -ceq $role.displayName -and $role.isEnabled
            if (-not $same) { $changes += "$($e.value) changed"; $role = $n }
        }
        $roles += $role
    }
    foreach ($w in $wantedList) {
        if (@($Existing | Where-Object { $_ -and [string]$_.value -ceq [string]$w.value }).Count) { continue }
        $roles += ConvertTo-AppRole $w ([guid]::NewGuid().ToString())
        $changes += "$($w.value) added"
    }
    return [pscustomobject]@{ Roles = @($roles); Changes = @($changes) }
}
# A difference the setup fixes when asked (a start), else reports.
function Invoke-Fix([string]$Problem, [string]$Question, [scriptblock]$Action, [string]$Done) {
    if ($script:readOnly -or -not (Confirm-Step $Question)) { Missing $Problem; return $false }
    & $Action | Out-Null
    Ok $Done
    return $true
}
# The step for one container app with sign-in: its app registration and service principal as the map says, each
# change asked. Returns the client id ('' while there is none).
function Set-SignInApp($Def) {
    $key = [string]$Def.key
    $si = $Def.signIn
    $name = [string]$script:res[$key].Name
    $idAnswer = Get-SignInClientIdAnswer $key
    $known = [string]$script:choices[$idAnswer]
    $fqdn = Get-AppHost $script:apps[$key]
    # By its id when one is known; by its name only when you alone own it and it is clean (Resolve-EntraApp).
    $found = Resolve-EntraApp $name $known $idAnswer (Get-SignInRedirect $Def) -SignIn
    if ($found.Note) { Note "sign-in of ${name}: $($found.Note)" }
    if ($found.Problem) { Missing "sign-in of ${name}: $($found.Problem)"; return $known }
    $reg = $found.App
    if (-not $fqdn) {
        Missing "sign-in of ${name}: the app comes first (step 1); its address is the app registration's redirect"
        if ($reg) { $script:choices[(Get-SignInObjectIdAnswer $key)] = [string]$reg.id; return [string]$reg.appId }
        return $known
    }
    $redirect = "https://$fqdn/.auth/login/aad/callback"
    if (-not (Test-SafeUri $redirect)) { Missing "sign-in of ${name}: the address $fqdn makes no usable redirect ($redirect)"; return $known }
    $op = Get-OperatorId
    if (-not $reg) {
        $what = "app registration $name (the sign-in in front of ${name}: this tenant only, ID tokens, redirect $redirect, no client secret, you its only owner)"
        if (-not $op) { Missing "${what}: made only by a signed-in user (az ad signed-in-user show), its owner"; return $known }
        if ($script:readOnly -or -not (Confirm-Step "Create the $($what)?")) { Missing $what; return $known }
        $reg = Invoke-Az @('ad', 'app', 'create', '--display-name', $name, '--sign-in-audience', 'AzureADMyOrg', '--web-redirect-uris', $redirect, '--enable-id-token-issuance', 'true')
        # You as its owner (Graph doesn't always add the creator): the next run finds it by its saved id, a
        # registration of the same name made by someone else is never taken.
        if (-not (Test-OwnedByOperator (Get-EntraOwners 'app' ([string]$reg.appId)))) { Invoke-Az @('ad', 'app', 'owner', 'add', '--id', [string]$reg.appId, '--owner-object-id', $op) | Out-Null }
        Ok "app registration $name created ($($reg.appId))"
    } else { Ok "app registration $name ($($reg.appId))" }
    $appId = [string]$reg.appId
    $script:choices[(Get-SignInObjectIdAnswer $key)] = [string]$reg.id
    if ($found.Source -eq 'id') {
        # Owners: you alone (one missing is added when asked; anyone else is only reported).
        $owners = Get-EntraOwners 'app' $appId
        if (Test-OwnedByOperator $owners) { Ok "${name}: owned by you alone" }
        elseif ($null -ne $owners -and -not @($owners).Count -and $op) { [void](Invoke-Fix "${name}: has no owner" "Make you the owner of $name?" { Invoke-Az @('ad', 'app', 'owner', 'add', '--id', $appId, '--owner-object-id', $op) | Out-Null } "${name}: owned by you") }
        else { Missing "${name}: owners $(Get-OwnersText $owners) (only you should own it: az ad app owner remove --id $appId --owner-object-id <id>)" }
    }
    if ([string]$reg.signInAudience -ne 'AzureADMyOrg') {
        [void](Invoke-Fix "${name}: signs in $($reg.signInAudience) (this tenant's accounts only)" "Let only this tenant's accounts sign in to $name (now $($reg.signInAudience))?" { Invoke-Az @('ad', 'app', 'update', '--id', $appId, '--sign-in-audience', 'AzureADMyOrg') | Out-Null } "${name}: this tenant only")
    }
    # Exactly one redirect: the app's callback (another one would send tokens elsewhere).
    $uris = @($reg.web.redirectUris | Where-Object { $_ })
    if ($uris.Count -eq 1 -and [string]$uris[0] -ceq $redirect) { Ok "${name}: redirect $redirect" }
    else {
        $now = 'none'
        if ($uris.Count) { $now = $uris -join ', ' }
        [void](Invoke-Fix "${name}: redirects $now (only $redirect)" "Set the redirect of $name to $redirect only (now: $now)?" { Invoke-Az @('ad', 'app', 'update', '--id', $appId, '--web-redirect-uris', $redirect) | Out-Null } "${name}: redirect $redirect")
    }
    if ($reg.web -and $reg.web.implicitGrantSettings -and $reg.web.implicitGrantSettings.enableIdTokenIssuance -eq $true) { Ok "${name}: ID tokens (the sign-in has no client secret)" }
    else { [void](Invoke-Fix "${name}: ID tokens off (the sign-in without a client secret needs them)" "Turn on ID tokens for $name?" { Invoke-Az @('ad', 'app', 'update', '--id', $appId, '--enable-id-token-issuance', 'true') | Out-Null } "${name}: ID tokens") }
    # Credentials: the sign-in uses none (no client secret), so every secret, certificate or federated credential is
    # someone's way to act as this app - reported, never removed here.
    $foreign = Get-ForeignCredentials $reg @()
    if ($null -eq $foreign) { Missing "${name}: its federated credentials are not readable (az ad app federated-credential list --id $appId)" }
    foreach ($c in @($foreign)) { Missing "${name}: has a $($c.Text) (the sign-in uses no credential)" }
    if (Test-Yes $si.identifierUri) {
        $uri = "api://$appId"
        $haveUris = @($reg.identifierUris | Where-Object { $_ })
        $odd = @($haveUris | Where-Object { -not (Test-SafeUri ([string]$_)) })
        if ($haveUris -contains $uri) { Ok "${name}: identifier URI $uri" }
        elseif (-not (Test-SafeUri $uri) -or $odd.Count) { Missing "${name}: no identifier URI $uri; not added here (its URIs $($odd -join ', ') aren't https://host/path or api://<id>): add it by hand" }
        else { [void](Invoke-Fix "${name}: no identifier URI $uri" "Give $name the identifier URI $uri (the audience of tokens other applications request)?" { Invoke-Az (@('ad', 'app', 'update', '--id', $appId, '--identifier-uris') + @(@($reg.identifierUris | Where-Object { $_ }) + $uri)) | Out-Null } "${name}: identifier URI $uri") }
    }
    $wantedRoles = @($si.appRoles | Where-Object { $_ })
    if ($wantedRoles.Count) {
        $plan = Get-AppRolesPlan @($reg.appRoles) $wantedRoles
        if (-not $plan.Changes.Count) { Ok "${name}: app roles $((@($wantedRoles | ForEach-Object { $_.value })) -join ', ')" }
        else {
            $objectId = [string]$reg.id
            [void](Invoke-Fix "${name}: app roles ($($plan.Changes -join ', '))" "Set the app roles of $name ($($plan.Changes -join ', '))?" {
                    $body = Write-TempJson 'approles.json' @{ appRoles = @($plan.Roles) }
                    Invoke-Az @('rest', '--method', 'patch', '--url', "https://graph.microsoft.com/v1.0/applications/$objectId", '--headers', 'Content-Type=application/json', '--body', "@$body") | Out-Null
                } "${name}: app roles $((@($wantedRoles | ForEach-Object { $_.value })) -join ', ')")
        }
        foreach ($extra in @($reg.appRoles | Where-Object { $_ -and @($wantedRoles | ForEach-Object { [string]$_.value }) -cnotcontains [string]$_.value })) { Note "${name}: keeps the app role $($extra.value) the map doesn't list (disable it, then remove it, by hand)" }
    }

    # The service principal (enterprise application) of this app registration (by its appId): Assignment required,
    # the group assigned. One with owners besides you is not used.
    $sp = Try-Az @('ad', 'sp', 'show', '--id', $appId)
    if ($sp) {
        $spOwners = Get-EntraOwners 'sp' ([string]$sp.id)
        if (Test-OwnedByOperator $spOwners) { Ok "${name}: service principal (owned by you alone)" }
        elseif ($null -ne $spOwners -and -not @($spOwners).Count -and $op) {
            $spId = [string]$sp.id
            if (-not (Invoke-Fix "${name}: its service principal has no owner" "Make you the owner of the service principal of $name?" { Add-SpOwner $spId $op } "${name}: service principal owned by you")) { return $appId }
        } else { Missing "${name}: its service principal has the owners $(Get-OwnersText $spOwners), not you alone: not used (remove the others in Enterprise applications -> $name -> Owners)"; return $appId }
    } elseif (-not $op) { Missing "${name}: service principal (made only by a signed-in user, its owner)"; return $appId }
    elseif (-not $script:readOnly -and (Confirm-Step "Create the service principal of $name (its enterprise application in this tenant, you its owner)?")) {
        $sp = Invoke-Az @('ad', 'sp', 'create', '--id', $appId)
        if (-not (Test-OwnedByOperator (Get-EntraOwners 'sp' ([string]$sp.id)))) { Add-SpOwner ([string]$sp.id) $op }
        Ok "${name}: service principal created"
    } else { Missing "${name}: service principal"; return $appId }
    if ($sp.appRoleAssignmentRequired -eq $true) { Ok "${name}: assignment required (only assigned users and groups sign in)" }
    else { [void](Invoke-Fix "${name}: anyone in the tenant can sign in (assignment required is off)" "Require an assignment to sign in to $name (only the assigned group)?" { Invoke-Az @('ad', 'sp', 'update', '--id', $appId, '--set', 'appRoleAssignmentRequired=true') | Out-Null } "${name}: assignment required") }
    $group = [string]$script:choices[(Get-SignInGroupAnswer $key)]
    $assigned = @()
    $listed = Try-Az @('rest', '--method', 'get', '--url', "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo")
    if ($listed) { $assigned = @($listed.value | Where-Object { $_ }) }
    $groupId = ''
    $at = $group.LastIndexOf('|')
    if (-not $group -or $group -eq '-') {
        Say "    ! ${name}: no group in the answers of $($script:envAbbr): nobody can sign in until a user or group is assigned (a dry run or start asks it)" 'Yellow'
    } elseif ($at -lt 0 -or -not (Test-Guid $group.Substring($at + 1))) {
        Missing "${name}: the group $group in the answers of $($script:envAbbr) has no object id (<name>|<object id>): not assigned (a dry run or start asks it again)"
    } else {
        $groupName = $group.Substring(0, [Math]::Max(0, $at))
        $groupId = $group.Substring($at + 1)
        if (@($assigned | Where-Object { [string]$_.principalId -eq $groupId }).Count) { Ok "${name}: $groupName assigned (its members sign in)" }
        else {
            $spId = [string]$sp.id
            [void](Invoke-Fix "${name}: the group $groupName is not assigned (its members can't sign in)" "Assign the group $groupName to $name (its members may sign in)?" {
                    $body = Write-TempJson 'assignment.json' ([ordered]@{ principalId = $groupId; resourceId = $spId; appRoleId = '00000000-0000-0000-0000-000000000000' })
                    Invoke-Az @('rest', '--method', 'post', '--url', "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignedTo", '--headers', 'Content-Type=application/json', '--body', "@$body") | Out-Null
                } "${name}: $groupName assigned")
        }
        # A guest in the group signs in too (a single-tenant app admits B2B guests): the app must refuse them, or keep
        # them out of the group.
        $guests = @(Try-Az @('ad', 'group', 'member', 'list', '--group', $groupId) | Where-Object { $_ -and [string]$_.userPrincipalName -like '*#EXT#*' })
        if ($guests.Count) { Say "    ! ${name}: $groupName has $($guests.Count) guest account(s): they can sign in too, unless the app refuses guests" 'Yellow' }
    }
    foreach ($o in @($assigned | Where-Object { [string]$_.principalId -ne $groupId })) {
        if ($o.principalType -eq 'ServicePrincipal') { Note "${name}: the application $($o.principalDisplayName) has an app role (it calls the app with tokens)" }
        else { Note "${name}: also assigned: $($o.principalDisplayName) ($($o.principalType))" }
    }
    return $appId
}
# The sign-in in front of a container app as Azure has it: on, with the app registration's client id, the map's
# action and excluded paths. An app without it that runs its real image is reported with how to take it offline.
function Test-SignInLive($Def, [string]$ClientId) {
    $key = [string]$Def.key
    $name = [string]$script:res[$key].Name
    $app = $script:apps[$key]
    if (-not $app) { return }
    $image = Get-AppImage $app
    $offline = "take it offline until then: az containerapp ingress disable -g $($script:rgName) -n $name (never turn the sign-in off instead)"
    $auth = Try-Az @('containerapp', 'auth', 'show', '-g', $script:rgName, '-n', $name)
    $cfg = $auth
    if ($auth -and $auth.properties) { $cfg = $auth.properties }
    if (-not ($cfg -and $cfg.platform -and $cfg.platform.enabled -eq $true)) {
        if (Test-PlaceholderImage $image) { Missing "sign-in of ${name}: not there yet (it still runs the placeholder; a start makes it before the app's workflow deploys)" }
        else { Missing "sign-in of ${name}: MISSING or off while it runs $image - $offline; then run a start" }
        return
    }
    $aad = $null
    if ($cfg.identityProviders) { $aad = $cfg.identityProviders.azureActiveDirectory }
    $have = ''
    if ($aad -and $aad.registration) { $have = [string]$aad.registration.clientId }
    if (-not $aad -or $aad.enabled -eq $false -or -not $have) { Missing "sign-in of ${name}: on, but without Microsoft Entra ID ($offline)"; return }
    if ($ClientId -and $have -ne $ClientId) { Missing "sign-in of ${name}: client id $have, its app registration is $ClientId (run a start)"; return }
    $problems = @()
    $gv = $cfg.globalValidation
    $action = 'RedirectToLoginPage'
    if ($gv -and $gv.unauthenticatedClientAction) { $action = [string]$gv.unauthenticatedClientAction }
    $wantAction = Get-UnauthenticatedAction $Def.signIn
    if ($action -ne $wantAction) { $problems += "without sign-in: $action, the map: $wantAction" }
    $pathProblem = Get-SignInPathProblem $Def
    if ($pathProblem) { $problems += $pathProblem }
    $wantPaths = @(Get-ExcludedPaths $Def)
    $havePaths = @()
    if ($gv) { $havePaths = @($gv.excludedPaths | Where-Object { $_ }) }
    if (Compare-Object @($wantPaths | Sort-Object) @($havePaths | Sort-Object)) { $problems += "paths without sign-in: $(if ($havePaths.Count) { $havePaths -join ', ' } else { 'none' }), the map: $(if ($wantPaths.Count) { $wantPaths -join ', ' } else { 'none' })" }
    if ($problems.Count) { Missing "sign-in of ${name}: $($problems -join '; ') (a start deploys the map's)"; return }
    # Its app registration and service principal as the setup makes them (report only).
    $regProblems = @(Get-SignInRegistrationDrift $Def $have)
    if ($regProblems.Count) { Missing "sign-in of ${name}: its app registration $have differs: $($regProblems -join '; ') (a start fixes what it may)"; return }
    $free = ''
    if ($wantPaths.Count) { $free = "; open: $($wantPaths -join ', ')" }
    Ok "sign-in in front of $name (Microsoft Entra ID, $have$free)"
}
# How a sign-in's app registration and service principal differ from what the setup makes: exactly the app's
# callback as redirect, ID tokens on, Assignment required, you their only owner. Empty when they don't.
function Get-SignInRegistrationDrift($Def, [string]$ClientId) {
    $name = [string]$script:res[[string]$Def.key].Name
    $out = @()
    if (-not (Test-Guid $ClientId)) { return @("client id $ClientId is no id") }
    $reg = Try-Az @('ad', 'app', 'show', '--id', $ClientId)
    if (-not $reg) { return @('not found or not readable') }
    $fqdn = Get-AppHost $script:apps[[string]$Def.key]
    $uris = @($reg.web.redirectUris | Where-Object { $_ })
    if ($fqdn) {
        $redirect = "https://$fqdn/.auth/login/aad/callback"
        if (-not ($uris.Count -eq 1 -and [string]$uris[0] -ceq $redirect)) { $out += "redirects $(if ($uris.Count) { $uris -join ', ' } else { 'none' }) (only $redirect)" }
    }
    if (-not ($reg.web -and $reg.web.implicitGrantSettings -and $reg.web.implicitGrantSettings.enableIdTokenIssuance -eq $true)) { $out += 'ID tokens off' }
    $foreign = Get-ForeignCredentials $reg @()
    if ($null -eq $foreign) { $out += 'federated credentials not readable' }
    foreach ($c in @($foreign)) { $out += "a $($c.Text) (the sign-in uses no credential)" }
    $owners = Get-EntraOwners 'app' $ClientId
    if (-not (Test-OwnedByOperator $owners)) { $out += "owners $(Get-OwnersText $owners) (only you)" }
    $sp = Try-Az @('ad', 'sp', 'show', '--id', $ClientId)
    if (-not $sp) { $out += 'no service principal' }
    else {
        if ($sp.appRoleAssignmentRequired -ne $true) { $out += 'assignment required off (anyone in the tenant signs in)' }
        $spOwners = Get-EntraOwners 'sp' ([string]$sp.id)
        if (-not (Test-OwnedByOperator $spOwners)) { $out += "service principal owners $(Get-OwnersText $spOwners) (only you)" }
    }
    return $out
}
# A deleted container app's sign-in app registration, asked: no by default. By its saved client id; by its name
# only when no id is saved and you alone own it (Resolve-EntraApp). Entra keeps a deleted app registration
# restorable for 30 days.
function Remove-SignInRegistration([string]$DisplayName, [string]$ClientId, [string]$Answer) {
    $found = Resolve-EntraApp $DisplayName $ClientId $Answer '' -SignIn
    if ($found.Note) { Note $found.Note }
    if ($found.Problem) { Note "sign-in of ${DisplayName}: $($found.Problem); not deleted"; return }
    $reg = $found.App
    if (-not $reg) { return }
    if (Confirm-Step "Delete the app registration $DisplayName ($($reg.appId)), the sign-in in front of the deleted app (restorable for 30 days in Entra's deleted applications)?" -DefaultNo) {
        Invoke-Az @('ad', 'app', 'delete', '--id', [string]$reg.appId) | Out-Null # its service principal and assignments go with it
        Ok "app registration $DisplayName deleted"
    } else { Note "app registration $DisplayName kept (az ad app delete --id $($reg.appId))" }
}
# main.bicep again within a start, with some parameters changed (a sign-in's client id, a container app's first image):
# the parameters file rewritten (the same path $Deployment names), what-if shown, then the deployment asked. $true
# when it was deployed. Only parameters main.bicep declares.
function Invoke-TemplateAgain($Parameters, [hashtable]$Values, [string[]]$Deployment, [string[]]$Declared, [string]$Question) {
    foreach ($p in $Values.Keys) {
        if ($Declared -notcontains $p) { Missing "infra/$($map.project.template) has no parameter $p (run .\infra\generate.ps1)"; return $false }
        $Parameters[$p] = @{ value = $Values[$p] }
    }
    Write-TempJson 'parameters.json' ([ordered]@{
            '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
            contentVersion = '1.0.0.0'
            parameters     = $Parameters
        }) | Out-Null
    Note 'comparing Azure with the template again (what-if)...'
    $whatIf = Invoke-Az (@('deployment', 'group', 'what-if') + $Deployment + @('--no-pretty-print'))
    foreach ($c in @($whatIf.changes | Where-Object { Test-RealChange $_ })) { Note ("{0,-8} {1}" -f $c.changeType, ($c.resourceId -split '/providers/')[-1]) }
    if (-not (Confirm-Step $Question)) { return $false }
    Invoke-Az (@('deployment', 'group', 'create') + $Deployment) | Out-Null
    return $true
}
# The run this start dispatched: the workflow's run-name puts the nonce it was dispatched with into the run's title
# ("<workflow> <nonce>"), so only a run whose title holds that nonce as a word is it - on $Branch, when given. Never
# the newest run instead. @{ Ids } - more than one is never guessed between.
function Select-DispatchedRun($List, [string]$Nonce, [string]$Branch) {
    if (-not $Nonce) { return [pscustomobject]@{ Ids = @() } }
    $c = @($List | Where-Object { $_ -and (([string]$_.displayTitle) -split ' ') -ccontains $Nonce })
    if ($Branch) { $c = @($c | Where-Object { [string]$_.headBranch -ceq $Branch }) }
    return [pscustomobject]@{ Ids = @($c | ForEach-Object { [string]$_.databaseId }) }
}
# A container app's first image (the step "First image"): its workflow run with push-only on the environment's deploy
# branch (the default branch for manual-only environments), waited for, then the image it pushed (tagged with the
# run's commit) as <login server>/<repository>:<tag>. '' when it failed (reported).
function Invoke-FirstImageBuild($Def, [string]$Repo, [string]$Branch, [string]$GhEnv) {
    $wf = [string]$Def.deploy.workflow
    $name = [string]$script:res[$Def.key].Name
    $useBranch = $Branch -and $Branch -ne '-'
    # This start's run is the one whose title carries this nonce (the workflow's input nonce, its run-name).
    $nonce = [guid]::NewGuid().ToString('N')
    $run = @('workflow', 'run', $wf, '--repo', $Repo, '-f', "environment=$GhEnv", '-f', 'push-only=true', '-f', "nonce=$nonce")
    if ($useBranch) { $run += @('--ref', $Branch) }
    $r = Invoke-Native $ghExe $run
    if ($r.Code -ne 0) { Missing "${name}: its workflow $wf didn't start ($($r.Errors.Trim())); is .github/workflows/$wf pushed to $(if ($useBranch) { $Branch } else { 'the default branch' }), generated by this kit (its input nonce)?"; return '' }
    Note "${name}: $wf started (push only, $nonce); waiting for its run..."
    $pick = $null
    for ($i = 0; $i -lt 20 -and -not $pick; $i++) {
        Start-Sleep -Seconds 3
        $listArgs = @('run', 'list', '--repo', $Repo, '--workflow', $wf, '--event', 'workflow_dispatch', '--limit', '20', '--json', 'databaseId,createdAt,headBranch,displayTitle')
        if ($useBranch) { $listArgs += @('--branch', $Branch) }
        $list = @(Try-Gh $listArgs -Json | Where-Object { $_ })
        $p = Select-DispatchedRun $list $nonce $(if ($useBranch) { $Branch } else { '' })
        if ($p.Ids.Count) { $pick = $p }
    }
    if (-not $pick) { Missing "${name}: no run of $wf titled with $nonce showed up (https://github.com/$Repo/actions; a workflow without the kit's run-name never does: regenerate and push it)"; return '' }
    # Never a guess: another run of the same workflow started at the same time (someone else, another start).
    if ($pick.Ids.Count -gt 1) { Missing "${name}: $($pick.Ids.Count) runs of $wf started at the same time ($($pick.Ids -join ', ')): which one is this start's is unknown - wait for them (https://github.com/$Repo/actions), then start again"; return '' }
    $id = [string]$pick.Ids[0]
    Note "https://github.com/$Repo/actions/runs/$id (a few minutes)"
    [void](Invoke-Native $ghExe @('run', 'watch', $id, '--repo', $Repo, '--exit-status', '--interval', '15'))
    $done = Try-Gh @('run', 'view', $id, '--repo', $Repo, '--json', 'conclusion,headSha') -Json
    if (-not ($done -and $done.conclusion -eq 'success')) { Missing "${name}: the run of $wf ended $(if ($done) { $done.conclusion } else { 'unknown' }) (gh run view $id --repo $Repo --log-failed)"; return '' }
    $image = Get-PushedImage $Def ([string]$done.headSha)
    if (-not $image) { Missing "${name}: no image of the run's commit $($done.headSha) in its registry" }
    return $image
}
# One answer of the environment's saved file changed (a start, after the answers were saved: the sign-in's client id).
function Save-EnvAnswer([string]$File, [string]$Name, [string]$Value) {
    if ($script:readOnly -or -not (Test-Path $File)) { return }
    $saved = Read-Json $File
    if ([string]$saved.$Name -eq $Value) { return }
    Set-Prop $saved $Name $Value
    [IO.File]::WriteAllText($File, (ConvertTo-Json -InputObject $saved -Depth 10) + "`n", $utf8)
    $script:saved = $saved
    Note "infra/environments/$(Split-Path $File -Leaf): $Name = $Value (commit it)"
}

# --- database access (SQL): the apps' database users -----------------------------------------------------

# Azure SQL with your Entra sign-in. When the server's firewall doesn't let your address through, a start
# lets it through for this step (asked first, removed at the step's end); a check or dry run only says so.
$script:sqlRules = New-Object Collections.ArrayList
function Open-Sql([string]$Group, [string]$Server, [string]$Database) {
    $token = Try-Az @('account', 'get-access-token', '--resource', 'https://database.windows.net/')
    if (-not $token) { Missing "no Entra token for Azure SQL (az login)"; return }
    for ($try = 0; $try -lt 8; $try++) {
        $conn = New-Object System.Data.SqlClient.SqlConnection "Server=tcp:$Server.database.windows.net,1433;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30"
        $conn.AccessToken = $token.accessToken
        try { $conn.Open(); return $conn } catch {
            $msg = $_.Exception.Message
            if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
            if ($msg -match "Client with IP address '([0-9.]+)'") {
                $ip = $Matches[1]
                if (@($script:sqlRules | Where-Object { $_.Server -eq $Server }).Count) { Note 'waiting for the firewall rule...'; Start-Sleep -Seconds 15; continue }
                if ($script:readOnly) { Note "not checked: your address $ip isn't let through the firewall of $Server (a start lets it through for this step)"; return }
                if (-not (Confirm-Step "Let your address $ip through the firewall of $Server for this step (removed at its end)?")) { Missing "database access on $Server not checked (its firewall)"; return }
                Invoke-Az @('sql', 'server', 'firewall-rule', 'create', '-g', $Group, '-s', $Server, '-n', 'infra-setup', '--start-ip-address', $ip, '--end-ip-address', $ip) | Out-Null
                [void]$script:sqlRules.Add([pscustomobject]@{ Group = $Group; Server = $Server; Ip = $ip })
                Note "firewall of ${Server}: $ip let through for now"
                Start-Sleep -Seconds 15
                continue
            }
            Missing "can't sign in to $Server/${Database}: $msg (you need to be its Entra admin, or in its admin group)"
            return
        }
    }
    Missing "can't reach $Server yet (the firewall rule takes a while): run this again"
}
function Close-SqlFirewall {
    foreach ($r in @($script:sqlRules)) {
        Try-Az @('sql', 'server', 'firewall-rule', 'delete', '-g', $r.Group, '-s', $r.Server, '-n', 'infra-setup') | Out-Null
        Note "firewall of $($r.Server): $($r.Ip) closed again"
    }
    $script:sqlRules.Clear()
}
function Get-SqlRows($Conn, [string]$Text, [string]$Name) {
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $Text
    [void]$cmd.Parameters.AddWithValue('@n', $Name)
    $reader = $cmd.ExecuteReader()
    $rows = @()
    while ($reader.Read()) { $rows += [string]$reader[0] }
    $reader.Close()
    return , $rows
}
function Invoke-SqlText($Conn, [string]$Text) {
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $Text
    [void]$cmd.ExecuteNonQuery()
}
# A database user's SID from an Entra client id (application id).
function Get-EntraSid([string]$ClientId) {
    return '0x' + ((([guid]$ClientId).ToByteArray() | ForEach-Object { $_.ToString('X2') }) -join '')
}
# One "sql" connection: the app's identity as a database user (by its client id, so the server needs no
# directory rights) with the map's database roles. The user is named after the identity: the app's own one, or
# the app itself for an entry without one (its system-assigned identity).
$script:oldSqlUsers = New-Object System.Collections.ArrayList
function Grant-DatabaseUser($C) {
    $appRes = $script:res[$C.from]
    $appDef = Get-Def $C.from
    $db = $script:res[$C.to]
    $hostLink = @($map.connections | Where-Object { $_.from -eq $C.to -and $_.kind -eq 'host' }) | Select-Object -First 1
    $server = $script:res[$hostLink.to]
    $group = $server.Group
    if (-not $group) { $group = $script:rgName }
    $user = [string]$appRes.Name
    if ($appDef.identity -and $script:res[[string]$appDef.identity]) { $user = [string]$script:res[[string]$appDef.identity].Name }
    $label = "$user in $($db.Name)"
    $ident = Get-RunIdentity $C.from
    if (-not $ident) {
        if ($appDef.identity) { Missing "database user ${label}: the app's identity comes first" } else { Missing "database user ${label}: the app comes first" }
        return
    }
    if (-not (Try-Az @('sql', 'db', 'show', '-g', $group, '-s', $server.Name, '-n', $db.Name))) { Missing "database user ${label}: the database comes first"; return }
    $conn = Open-Sql $group $server.Name $db.Name
    if (-not $conn) { return }
    $quoted = '[' + $user.Replace(']', ']]') + ']'
    try {
        $sids = Get-SqlRows $conn 'SELECT CONVERT(varchar(100), sid, 1) FROM sys.database_principals WHERE name = @n' $user
        $exists = [bool]$sids.Count
        # A user of that name made from another identity (an identity deleted and made again gets a new client id):
        # it would let the old one in, not the app.
        if ($exists -and $ident.ClientId -and $sids[0] -ine (Get-EntraSid $ident.ClientId)) {
            Missing "database user ${label}: made for another identity, not $($ident.Name) ($($ident.ClientId)); drop it (DROP USER $quoted in $($db.Name)), then run this again"
            return
        }
        if ($exists) { Ok "database user $label" }
        elseif (Confirm-Step "Create the database user $user in $($db.Name) (the app's managed identity signs in as it)?") {
            $clientId = $ident.ClientId
            if (-not $clientId) { $clientId = [string](Invoke-Az @('ad', 'sp', 'show', '--id', $ident.PrincipalId)).appId }
            Invoke-SqlText $conn "CREATE USER $quoted WITH SID = $(Get-EntraSid $clientId), TYPE = E"
            Ok "database user $label created"
            $exists = $true
        } else { Missing "database user $label" }
        # The app's earlier user, made for its system-assigned identity (named after the app) before it had its own:
        # listed in the next steps, to drop by hand once the app works with its own identity.
        if ($appDef.identity -and $appRes.Name -and $appRes.Name -ne $user -and (Get-SqlRows $conn "SELECT name FROM sys.database_principals WHERE name = @n AND type = 'E'" ([string]$appRes.Name)).Count) {
            [void]$script:oldSqlUsers.Add([pscustomobject]@{ App = [string]$appRes.Name; User = [string]$appRes.Name; Database = [string]$db.Name; Server = [string]$server.Name })
        }
        if ($exists) {
            $have = Get-SqlRows $conn 'SELECT r.name FROM sys.database_role_members m JOIN sys.database_principals r ON r.principal_id = m.role_principal_id JOIN sys.database_principals u ON u.principal_id = m.member_principal_id WHERE u.name = @n' $user
            $want = @($C.dbRoles | Where-Object { $_ })
            $lacking = @($want | Where-Object { $have -notcontains $_ })
            if (-not $lacking.Count) { Ok "$label`: $($want -join ', ')" }
            elseif (Confirm-Step "Give $user $($lacking -join ', ') in $($db.Name)?") {
                foreach ($role in $lacking) { Invoke-SqlText $conn "ALTER ROLE [$($role.Replace(']', ']]'))] ADD MEMBER $quoted" }
                Ok "$label`: $($want -join ', ')"
            } else { Missing "$label`: $($lacking -join ', ')" }
            # Permissions no role carries: EXECUTE on a schema (the procedures and functions the migrations
            # create, Netmedia SQL Coding 1.3, 9.1). Only "<PERMISSION> ON SCHEMA::<schema>".
            foreach ($grant in @($C.dbGrants | Where-Object { $_ })) {
                if ([string]$grant -notmatch '^([A-Z ]+) ON SCHEMA::(\w+)$') { Missing "${label}: grant '$grant' is not '<PERMISSION> ON SCHEMA::<schema>'"; continue }
                $permission = $Matches[1].Trim()
                $schema = $Matches[2]
                $granted = Get-SqlRows $conn "SELECT p.permission_name FROM sys.database_permissions p JOIN sys.schemas s ON s.schema_id = p.major_id JOIN sys.database_principals u ON u.principal_id = p.grantee_principal_id WHERE p.class = 3 AND p.state IN ('G', 'W') AND s.name = '$schema' AND p.permission_name = '$permission' AND u.name = @n" $user
                if ($granted.Count) { Ok "$label`: $grant" }
                elseif (Confirm-Step "Grant $user $grant in $($db.Name)?") {
                    Invoke-SqlText $conn "GRANT $permission ON SCHEMA::[$schema] TO $quoted"
                    Ok "$label`: $grant"
                } else { Missing "$label`: $grant" }
            }
        }
    } catch { Missing "database user ${label}: $($_.Exception.Message)" }
    finally { $conn.Close() }
}

# The deploys that run EF Core migrations (an app's deploy.migrate, LAZYBICEP.md "Database migrations"): the
# database, its server, and the GitHub environment's variable with the connection string the workflow migrates
# with (Entra ID, no password; generate.ps1 names the variable by the same rule).
function Get-MigratingDeploys {
    foreach ($d in @($defs | Where-Object { $_.deploy -and $_.deploy.migrate })) {
        $dbKey = [string]$d.deploy.migrate.database
        $hostLink = @($map.connections | Where-Object { $_.from -eq $dbKey -and $_.kind -eq 'host' }) | Select-Object -First 1
        if (-not $hostLink) { Missing "$($d.key): deploy.migrate.database $dbKey is not a SQL database of the map"; continue }
        [pscustomobject]@{
            App        = [string]$d.key
            Database   = $dbKey
            Server     = [string]$hostLink.to
            Variable   = 'AZURE_' + (Get-Upper $dbKey) + '_CONNECTION'
            Connection = "Server=tcp:{$($hostLink.to).host},1433;Database={$dbKey.name};Authentication=Active Directory Default;Encrypt=True;"
        }
    }
}
# GitHub Actions' app registration as a database user that may change the schema (db_ddladmin) and the data
# (seed data, data scripts), for the deploys that migrate. By its client id, like the apps' users.
function Grant-DeployDatabaseUser([string]$DatabaseKey, [string]$User, [string]$AppId) {
    $db = $script:res[$DatabaseKey]
    $hostLink = @($map.connections | Where-Object { $_.from -eq $DatabaseKey -and $_.kind -eq 'host' }) | Select-Object -First 1
    $server = $script:res[$hostLink.to]
    $group = $server.Group
    if (-not $group) { $group = $script:rgName }
    $label = "$User in $($db.Name)"
    if (-not (Try-Az @('sql', 'db', 'show', '-g', $group, '-s', $server.Name, '-n', $db.Name))) { Missing "database user ${label}: the database comes first"; return }
    $conn = Open-Sql $group $server.Name $db.Name
    if (-not $conn) { return }
    $quoted = '[' + $User.Replace(']', ']]') + ']'
    $want = @('db_ddladmin', 'db_datareader', 'db_datawriter')
    try {
        $exists = [bool](Get-SqlRows $conn 'SELECT name FROM sys.database_principals WHERE name = @n' $User).Count
        if ($exists) { Ok "database user $label" }
        elseif (Confirm-Step "Create the database user $User in $($db.Name) (GitHub Actions runs the migrations as it)?") {
            $sid = '0x' + ((([guid]$AppId).ToByteArray() | ForEach-Object { $_.ToString('X2') }) -join '')
            Invoke-SqlText $conn "CREATE USER $quoted WITH SID = $sid, TYPE = E"
            Ok "database user $label created"
            $exists = $true
        } else { Missing "database user $label" }
        if ($exists) {
            $have = Get-SqlRows $conn 'SELECT r.name FROM sys.database_role_members m JOIN sys.database_principals r ON r.principal_id = m.role_principal_id JOIN sys.database_principals u ON u.principal_id = m.member_principal_id WHERE u.name = @n' $User
            $lacking = @($want | Where-Object { $have -notcontains $_ })
            if (-not $lacking.Count) { Ok "$label`: $($want -join ', ')" }
            elseif (Confirm-Step "Give $User $($lacking -join ', ') in $($db.Name) (the migrations change the schema)?") {
                foreach ($role in $lacking) { Invoke-SqlText $conn "ALTER ROLE [$role] ADD MEMBER $quoted" }
                Ok "$label`: $($want -join ', ')"
            } else { Missing "$label`: $($lacking -join ', ')" }
        }
    } catch { Missing "database user ${label}: $($_.Exception.Message)" }
    finally { $conn.Close() }
}

# The apps (App Service, Static Web App, Container App) as Azure shows them, or nothing.
function Get-App([string]$Key) {
    $def = Get-Def $Key
    $r = $script:res[$Key]
    if (-not $r -or -not $r.Name) { return }
    return Show-App ([string]$def.armType) $script:rgName $r.Name
}
# A resource of the map's id: an app as this run found it, else the resource by its name (also one shared from another
# group, or one the template created during this run); '' while it doesn't exist.
function Get-ResourceId([string]$Key) {
    $app = $script:apps[$Key]
    if ($app -and $app.id) { return [string]$app.id }
    $r = $script:res[$Key]
    $def = Get-Def $Key
    if (-not ($r -and $r.Name -and $def)) { return '' }
    if ($r.Found -and $r.Found.id) { return [string]$r.Found.id }
    $found = $null
    try { $found = Find-Resource $r.Name ([string]$def.armType) } catch { }
    if ($found) { return [string]$found.id }
    return ''
}
function Show-App([string]$ArmType, [string]$Group, [string]$Name) {
    if ($ArmType -eq 'Microsoft.Web/sites') { return Try-Az @('webapp', 'show', '-g', $Group, '-n', $Name) }
    if ($ArmType -eq 'Microsoft.Web/staticSites') { return Try-Az @('staticwebapp', 'show', '-g', $Group, '-n', $Name) }
    if ($ArmType -eq $containerAppType) { return Try-Az @('containerapp', 'show', '-g', $Group, '-n', $Name) }
}
# An app's address: App Service and Static Web Apps' default host name (staticSites: defaultHostname, the same to
# PowerShell), a Container App's ingress FQDN. Empty while it has none.
function Get-AppHost($App) {
    if (-not $App) { return '' }
    if ($App.defaultHostName) { return [string]$App.defaultHostName }
    if ($App.properties -and $App.properties.configuration -and $App.properties.configuration.ingress -and $App.properties.configuration.ingress.fqdn) { return [string]$App.properties.configuration.ingress.fqdn }
    return ''
}
# The image a Container App runs now (its first container's), '' when it can't be told.
function Get-AppImage($App) {
    if (-not ($App -and $App.properties -and $App.properties.template)) { return '' }
    $first = @($App.properties.template.containers | Where-Object { $_ }) | Select-Object -First 1
    if ($first) { return [string]$first.image }
    return ''
}
# The public placeholder a new Container App starts with (any tag of it).
function Test-PlaceholderImage([string]$Image) {
    if (-not $Image) { return $true }
    return $Image -match '^mcr\.microsoft\.com/k8se/quickstart(:|@|$)'
}
# A setting of a Container App that is a secret reference (a Key Vault secret): compared by name only, its value never read.
$secretRefMark = 'secretRef:'
# An app's settings as name -> value (empty when it can't be read). A Container App's are its first container's
# environment variables; a secret reference is "secretRef:<secret name>", never the value.
function Get-AppSettings([string]$Key) {
    $def = Get-Def $Key
    $name = $script:res[$Key].Name
    $have = @{}
    if ($def.armType -eq 'Microsoft.Web/sites') {
        foreach ($s in @(Try-Az @('webapp', 'config', 'appsettings', 'list', '-g', $script:rgName, '-n', $name))) { if ($s) { $have[$s.name] = [string]$s.value } }
    } elseif ($def.armType -eq 'Microsoft.Web/staticSites') {
        $s = Try-Az @('staticwebapp', 'appsettings', 'list', '-g', $script:rgName, '-n', $name)
        if ($s -and $s.properties) { foreach ($p in $s.properties.PSObject.Properties) { $have[$p.Name] = [string]$p.Value } }
    } elseif ($def.armType -eq $containerAppType) {
        $app = $script:apps[$Key]
        if (-not $app) { $app = Get-App $Key }
        $first = $null
        if ($app -and $app.properties -and $app.properties.template) { $first = @($app.properties.template.containers | Where-Object { $_ }) | Select-Object -First 1 }
        if ($first) {
            foreach ($e in @($first.env | Where-Object { $_ })) {
                if ($e.secretRef) { $have[[string]$e.name] = $secretRefMark + [string]$e.secretRef }
                else { $have[[string]$e.name] = [string]$e.value }
            }
        }
    }
    return $have
}

# What-if reports noise as Modify (seen on the first real deployment): read-only values Azure adds
# (Delete: freeOfferExpirationTime, stableInboundIP, provider...), write-only defaults it never returns
# (Flow_Type, Request_Source), expressions it can't evaluate before the deployment (a role assignment's
# principalId = the API's identity), and an App Service's siteConfig, which its GET doesn't return at all
# (compared here with the real configuration instead). The template never removes a property, so a
# Delete is never a real change.
$noisePaths = @('properties.Flow_Type', 'properties.Request_Source', 'properties.siteConfig.netFrameworkVersion')
function Test-RealDelta($Delta, $SiteConfig) {
    if (@('NoEffect', 'Delete') -contains $Delta.propertyChangeType) { return $false }
    if ($noisePaths -contains $Delta.path) { return $false }
    if ($Delta.after -is [string] -and $Delta.after.StartsWith('[')) { return $false }
    if ($SiteConfig -and $Delta.path -like 'properties.siteConfig.*' -and -not $Delta.children) {
        $name = $Delta.path.Substring('properties.siteConfig.'.Length)
        if ($SiteConfig.PSObject.Properties[$name] -and "$($SiteConfig.$name)" -ieq "$($Delta.after)") { return $false }
    }
    if (-not $Delta.children) { return $true }
    foreach ($child in $Delta.children) { if (Test-RealDelta $child $SiteConfig) { return $true } }
    return $false
}
# A change of a what-if result, or $null when it is noise or what-if can't tell (Unsupported: the app
# settings, checked directly in Invoke-Setup).
function Test-RealChange($Change) {
    if (-not $Change -or @('NoChange', 'Ignore', 'Unsupported') -contains $Change.changeType) { return $false }
    if ($Change.changeType -ne 'Modify') { return $true }
    $siteConfig = $null
    if ($Change.resourceId -match '/providers/Microsoft\.Web/sites/[^/]+$') { $siteConfig = Try-Az @('webapp', 'config', 'show', '--ids', $Change.resourceId) }
    return [bool](@($Change.delta | Where-Object { Test-RealDelta $_ $siteConfig }).Count)
}

# DNS instructions, as "at the DNS host of <zone>, add <type> <name> pointing to <value>". The zone is
# taken as the last two labels (example.com); the name is relative to it, as DNS hosts want it.
$script:dnsTodo = New-Object System.Collections.ArrayList # still missing at the end of the run
$script:readyNoted = @{} # what waits for an app's code, reported once a run
function Get-Zone([string]$Domain) {
    $labels = $Domain.Split('.')
    if ($labels.Count -le 2) { return $Domain }
    return ($labels[-2..-1] -join '.')
}
function Get-RelativeName([string]$Domain) {
    $zone = Get-Zone $Domain
    if ($Domain -ieq $zone) { return '@' }
    return $Domain.Substring(0, $Domain.Length - $zone.Length - 1)
}
function New-DnsRecord([string]$Type, [string]$Name, [string]$Value) {
    return [pscustomobject]@{ Type = $Type; Name = $Name; Value = $Value; Done = $false }
}
# The records of the map's custom domains; values that exist only after creation are described instead.
function Get-DnsRecords {
    $records = @()
    foreach ($dm in @($map.domains)) {
        $domain = [string]$script:choices[$dm.answer]
        if (-not $domain -or $domain -eq '-') { continue }
        $app = $script:apps[$dm.resource]
        if ($dm.dns -eq 'staticWebApp') {
            $target = "<the $($dm.what)'s address (*.azurestaticapps.net), known once it is created>"
            if ($app) { $target = $app.defaultHostname }
            $records += New-DnsRecord 'CNAME' $domain $target
        } elseif ($dm.dns -eq 'appService') {
            $records += New-DnsRecord 'CNAME' $domain "$($script:res[$dm.resource].Name).azurewebsites.net"
            $verification = "<the verification id, known once the $($dm.what) is created>"
            if ($app) { $verification = $app.customDomainVerificationId }
            $records += New-DnsRecord 'TXT' "asuid.$domain" $verification
        }
    }
    return $records
}
function Write-DnsInstructions([string]$Title, [object[]]$Records) {
    $Records = @($Records | Where-Object { $_ })
    if (-not $Records.Count) { return }
    if ($script:ui) {
        $list = @(foreach ($r in $Records) {
                $how = 'pointing to'
                if ($r.Type -eq 'TXT') { $how = 'with the value' }
                [ordered]@{ zone = (Get-Zone $r.Name); type = $r.Type; name = $r.Name; relative = (Get-RelativeName $r.Name); how = $how; value = $r.Value; done = [bool]$r.Done }
            })
        Send ([ordered]@{ t = 'dns'; title = $Title; records = $list })
        return
    }
    Write-Host ''
    Write-Host "    $Title" -ForegroundColor Cyan
    foreach ($zone in @($Records | ForEach-Object { Get-Zone $_.Name } | Select-Object -Unique)) {
        Write-Host "    At the DNS host of $zone, add:" -ForegroundColor Cyan
        foreach ($r in @($Records | Where-Object { (Get-Zone $_.Name) -eq $zone })) {
            $how = 'pointing to'
            if ($r.Type -eq 'TXT') { $how = 'with the value' }
            $mark = '  '
            if ($r.Done) { $mark = 'OK' }
            Write-Host ("      {0} {1,-5}  {2,-30} {3,-14} {4}" -f $mark, $r.Type, (Get-RelativeName $r.Name), $how, $r.Value) -ForegroundColor Cyan
        }
        Write-Host "      (full names: $((@($Records | Where-Object { (Get-Zone $_.Name) -eq $zone } | ForEach-Object { $_.Name }) | Select-Object -Unique) -join ', '))" -ForegroundColor DarkGray
    }
}

# The issued certificate of a hostname in a resource group, or nothing. Looked up as resources, since
# 'az webapp config ssl list' leaves App Service managed certificates out (seen on production).
function Find-Certificate([string]$Group, [string]$HostName) {
    foreach ($c in @(Try-Az @('resource', 'list', '-g', $Group, '--resource-type', 'Microsoft.Web/certificates'))) {
        if (-not $c) { continue }
        $full = Try-Az @('resource', 'show', '--ids', $c.id)
        if ($full -and (@($full.properties.hostNames) -contains $HostName) -and $full.properties.thumbprint) {
            return [pscustomobject]@{ thumbprint = $full.properties.thumbprint; expires = ([string]$full.properties.expirationDate).Split('T')[0] }
        }
    }
}

function Test-Dns([string]$Host_, [object[]]$Records) {
    while ($true) {
        foreach ($r in $Records) {
            if ($r.Type -eq 'CNAME') {
                $values = @(Resolve-DnsName -Name $r.Name -Type CNAME -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'CNAME' } | ForEach-Object { $_.NameHost })
            } else {
                $values = @(Resolve-DnsName -Name $r.Name -Type TXT -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'TXT' } | ForEach-Object { $_.Strings -join '' })
            }
            $r.Done = [bool](@($values | Where-Object { $_.TrimEnd('.') -ieq $r.Value }).Count)
        }
        if (@($Records | Where-Object { -not $_.Done }).Count -eq 0) {
            Ok "DNS of $Host_"
            return $true
        }
        Write-DnsInstructions "DNS for $Host_ is not there yet (OK = already resolves):" $Records
        if ($script:readOnly -or (Ask 'Enter = check DNS again (after adding it), s = skip this domain for now' '') -eq 's') {
            Missing "DNS of $Host_"
            foreach ($r in $Records) { if (-not $r.Done) { [void]$script:dnsTodo.Add($r) } }
            return $false
        }
    }
}

# Step 4 for one domain of a Static Web App: DNS, then the domain (Azure validates it and issues the
# certificate).
function Add-StaticDomain($Dm, [string]$Domain) {
    $r = $script:res[$Dm.resource]
    $app = $script:apps[$Dm.resource]
    if (-not $app) { Missing "${Domain}: the $($Dm.what) comes first"; return }
    $status = @(Try-Az @('staticwebapp', 'hostname', 'list', '-g', $script:rgName, '-n', $r.Name)) | Where-Object { $_ -and ($_.name -ieq $Domain -or $_.domainName -ieq $Domain) } | Select-Object -First 1
    if ($status -and $status.status -eq 'Ready') { Ok "https://$Domain ($($Dm.what), certificate by Azure)"; $script:domainReady[$Dm.answer] = $true }
    elseif ($status) { Missing "$Domain on the $($Dm.what): $($status.status) (validation and certificate take a few minutes)" }
    elseif (Test-Dns $Domain @(New-DnsRecord 'CNAME' $Domain $app.defaultHostname)) {
        if (Confirm-Step "Add $Domain to $($r.Name) (Azure validates it and issues the certificate, a few minutes)?") {
            Invoke-Az @('staticwebapp', 'hostname', 'set', '-g', $script:rgName, '-n', $r.Name, '--hostname', $Domain, '--no-wait') | Out-Null
            Ok "$Domain added (run -Check later to see it Ready)"
        } else { Missing "$Domain on the $($Dm.what)"; $script:domainsToAdd = $true }
    }
}
function Test-Bound([string]$Key, [string]$Name) {
    $app = $script:apps[$Key]
    return [bool]($app -and @($app.hostNameSslStates | Where-Object { $_.name -ieq $Name -and $_.sslState -eq 'SniEnabled' }).Count)
}
# Step 4 for one domain of an App Service: DNS (CNAME + TXT asuid), the hostname, a free managed
# certificate, the SNI binding.
function Add-AppServiceDomain($Dm, [string]$Domain) {
    $r = $script:res[$Dm.resource]
    $app = $script:apps[$Dm.resource]
    if (-not $app) { Missing "${Domain}: the $($Dm.what) comes first"; return }
    if (Test-Bound $Dm.resource $Domain) { Ok "https://$Domain ($($Dm.what), managed certificate)"; $script:domainReady[$Dm.answer] = $true; return }
    if (-not (Test-Dns $Domain @(
                (New-DnsRecord 'CNAME' $Domain $app.defaultHostName),
                (New-DnsRecord 'TXT' "asuid.$Domain" $app.customDomainVerificationId)))) { return }
    $added = @($app.hostNames) -contains $Domain
    if ($added) { Ok "hostname $Domain on $($r.Name)" }
    elseif (Confirm-Step "Add $Domain to $($r.Name)?") {
        Invoke-Az @('webapp', 'config', 'hostname', 'add', '-g', $script:rgName, '--webapp-name', $r.Name, '--hostname', $Domain) | Out-Null
        $added = $true
        Ok "hostname $Domain added"
    } else { Missing "hostname $Domain"; $script:domainsToAdd = $true }

    $cert = $null
    if ($added) {
        $cert = Find-Certificate $script:rgName $Domain
        if ($cert) { Ok "certificate $($cert.thumbprint) (valid until $($cert.expires))" }
        elseif (Confirm-Step "Create the free managed certificate for $Domain (a few minutes)?") {
            Invoke-Az @('webapp', 'config', 'ssl', 'create', '-g', $script:rgName, '-n', $r.Name, '--hostname', $Domain) | Out-Null
            # Azure may still be issuing it when the command returns: wait for the thumbprint.
            for ($i = 0; $i -lt 20 -and -not $cert; $i++) {
                $cert = Find-Certificate $script:rgName $Domain
                if (-not $cert) { Note 'waiting for the certificate...'; Start-Sleep -Seconds 15 }
            }
            if ($cert) { Ok "certificate $($cert.thumbprint)" }
            else { Missing "certificate for $Domain (Azure is still issuing it: run this again in a few minutes)"; $script:domainsToAdd = $true }
        } else { Missing "certificate for $Domain"; $script:domainsToAdd = $true }
    }
    if ($cert) {
        if (Confirm-Step "Bind the certificate to $Domain (SNI)?") {
            # Straight on the hostname binding: 'az webapp config ssl bind' finds certificates through the
            # same listing that leaves managed ones out.
            $binding = Write-TempJson 'binding.json' @{ properties = @{ siteName = $r.Name; hostNameType = 'Verified'; sslState = 'SniEnabled'; thumbprint = $cert.thumbprint } }
            Invoke-Az @('rest', '--method', 'put', '--url', "https://management.azure.com$($app.id)/hostNameBindings/$($Domain)?api-version=2024-04-01", '--body', "@$binding") | Out-Null
            $script:apps[$Dm.resource] = Invoke-Az @('webapp', 'show', '-g', $script:rgName, '-n', $r.Name)
            $script:domainReady[$Dm.answer] = $true
            Ok "https://$Domain ($($Dm.what), managed certificate)"
        } else { Missing "certificate not bound to $Domain"; $script:domainsToAdd = $true }
    }
}

# The order of a saved file's keys is kept, so another order of the map doesn't count as a change.
# Another environment's answers for a new one: every name of its own moved to the new environment (its
# environment part swapped, or added when it has none), shared resources from other groups kept, its
# custom domains and deploy branch left out (they belong to it).
function Copy-Answers($Source, [string]$From, [string]$To) {
    $copy = (ConvertTo-Json -InputObject $Source -Depth 10) | ConvertFrom-Json
    # A sign-in's app registration belongs to its environment (named after the app there): its client id isn't copied.
    foreach ($d in @(Get-SignInDefs)) { $copy.PSObject.Properties.Remove((Get-SignInClientIdAnswer ([string]$d.key))); $copy.PSObject.Properties.Remove((Get-SignInObjectIdAnswer ([string]$d.key))) }
    # So is GitHub Actions' app registration (one per environment).
    foreach ($d in @($defs | Where-Object { $_.ask -eq 'name' -and $_.type -eq 'deploy' })) { $copy.PSObject.Properties.Remove((Get-DeployClientIdAnswer ([string]$d.key))) }
    foreach ($p in @($copy.names.PSObject.Properties)) {
        if ($copy.groups -and $copy.groups.($p.Name)) { continue } # shared from another group: as it is
        $def = Get-Def $p.Name
        $name = [string]$p.Value
        $flat = $def -and @($naming.noHyphens) -contains $def.type
        if ($flat) {
            if ($name.EndsWith($From)) { $name = $name.Substring(0, $name.Length - $From.Length) + $To } else { $name = $name + $To }
        } else {
            $moved = [regex]::Replace($name, "(?<=^|-)$([regex]::Escape($From))(?=-|$)", $To)
            if ($moved -eq $name) { $moved = "$name-$To" }
            $name = $moved
        }
        $copy.names.($p.Name) = $name
    }
    # Custom domains follow the source's: its environment in a label swapped (dev.app.example.com ->
    # test.app.example.com), else the environment added to the first label, in the same DNS zone
    # (app.example.com -> app-test.example.com).
    foreach ($dm in @($map.domains)) {
        if (-not $copy.PSObject.Properties[$dm.answer]) { continue }
        $domain = [string]$copy.($dm.answer)
        if (-not $domain -or $domain -eq '-') { continue }
        $moved = [regex]::Replace($domain, "(?<=^|[.-])$([regex]::Escape($From))(?=[.-])", $To)
        if ($moved -eq $domain) {
            $labels = $domain.Split('.')
            $labels[0] = "$($labels[0])-$To"
            $moved = $labels -join '.'
        }
        $copy.($dm.answer) = $moved
    }
    # The deploy branch follows the source's: its full environment name (production -> test), its short one
    # (prod -> test), or the environment in the name swapped (release-prod -> release-test); else manual runs.
    if ($copy.PSObject.Properties['branch']) {
        $branch = [string]$copy.branch
        $fromFull = [string]$naming.environments.$From
        $toFull = [string]$naming.environments.$To
        $script:copyBranch = $branch # the branch a new one starts from (a start offers to create it)
        if (-not $branch -or $branch -eq '-') { $copy.branch = '-' }
        elseif ($branch -eq $fromFull) { $copy.branch = $toFull }
        elseif ($branch -eq $From) { $copy.branch = $To }
        else {
            $moved = [regex]::Replace($branch, "(?<=^|[/_.-])$([regex]::Escape($fromFull))(?=$|[/_.-])", $toFull)
            if ($moved -eq $branch) { $moved = [regex]::Replace($branch, "(?<=^|[/_.-])$([regex]::Escape($From))(?=$|[/_.-])", $To) }
            if ($moved -ne $branch) { $copy.branch = $moved } else { $copy.branch = '-'; $script:copyBranch = '' }
        }
    }
    return $copy
}

function Get-OrderedLike($New, $Old) {
    if (-not $Old) { return $New }
    $out = [ordered]@{}
    foreach ($p in $Old.PSObject.Properties) { if ($New.Contains($p.Name)) { $out[$p.Name] = $New[$p.Name] } }
    foreach ($k in $New.Keys) { if (-not $out.Contains($k)) { $out[$k] = $New[$k] } }
    return $out
}

# --- the map's files ---------------------------------------------------------------------------------

# JSON as the map is written by hand: two spaces, short objects and lists on one line, a blank line
# between the top-level sections (a "$x" comment stays with the "x" after it), text as it is.
function Get-JsonText([string]$Text) {
    $sb = New-Object Text.StringBuilder '"'
    foreach ($c in $Text.ToCharArray()) {
        switch ($c) {
            '"' { [void]$sb.Append('\"') }
            '\' { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default { if ([int]$c -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) } else { [void]$sb.Append($c) } }
        }
    }
    return $sb.Append('"').ToString()
}
function Get-JsonProps($Value) {
    if ($Value -is [Collections.IDictionary]) { return @(foreach ($k in $Value.Keys) { , @([string]$k, $Value[$k]) }) }
    return @(foreach ($p in $Value.PSObject.Properties) { , @($p.Name, $p.Value) })
}
function Test-JsonObject($Value) { return ($Value -is [Collections.IDictionary] -or $Value -is [Management.Automation.PSCustomObject]) }
function Get-JsonCompact($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } return 'false' }
    if ($Value -is [string]) { return Get-JsonText $Value }
    if ($Value -is [ValueType]) { return ([IFormattable]$Value).ToString($null, [Globalization.CultureInfo]::InvariantCulture) }
    if (Test-JsonObject $Value) {
        $props = @(Get-JsonProps $Value)
        if (-not $props.Count) { return '{}' }
        return '{ ' + ((@($props | ForEach-Object { (Get-JsonText $_[0]) + ': ' + (Get-JsonCompact $_[1]) })) -join ', ') + ' }'
    }
    $items = @($Value)
    if (-not $items.Count) { return '[]' }
    return '[' + ((@($items | ForEach-Object { Get-JsonCompact $_ })) -join ', ') + ']'
}
function Get-JsonPretty($Value, [int]$Level) {
    $pad = '  ' * $Level
    $compact = Get-JsonCompact $Value
    $isObject = Test-JsonObject $Value
    $isList = -not $isObject -and $Value -isnot [string] -and $Value -is [Collections.IEnumerable]
    if ((-not $isObject -and -not $isList) -or ($Level -gt 0 -and $pad.Length + $compact.Length -le 110)) { return $compact }
    $inner = '  ' * ($Level + 1)
    if ($isList) {
        $items = @($Value)
        if (-not $items.Count) { return '[]' }
        return "[`n" + ((@($items | ForEach-Object { $inner + (Get-JsonPretty $_ ($Level + 1)) })) -join ",`n") + "`n$pad]"
    }
    $props = @(Get-JsonProps $Value)
    if (-not $props.Count) { return '{}' }
    $out = @()
    for ($i = 0; $i -lt $props.Count; $i++) {
        $line = $inner + (Get-JsonText $props[$i][0]) + ': ' + (Get-JsonPretty $props[$i][1] ($Level + 1))
        if ($Level -eq 0 -and $i -gt 0 -and -not ([string]$props[$i - 1][0]).StartsWith('$')) { $line = "`n" + $line }
        $out += $line
    }
    return "{`n" + ($out -join ",`n") + "`n$pad}"
}
function Write-JsonFile([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, (Get-JsonPretty $Value 0) + "`n", $utf8)
}
function Set-Prop($Object, [string]$Name, $Value) {
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value } else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# --- adding and removing resources (the catalog) -------------------------------------------------------

function Get-Blueprint([string]$Kind) {
    $file = Join-Path $infra "catalog\$Kind.json"
    if (-not (Test-Path $file)) { throw "No blueprint for $Kind (infra/catalog/$Kind.json)." }
    return Read-Json $file
}
function Get-Blueprints {
    return @(Get-ChildItem (Join-Path $infra 'catalog') -Filter '*.json' | Where-Object { $_.Name -ne 'roles.json' } | ForEach-Object { Read-Json $_.FullName })
}
function Test-Answers($When, [hashtable]$Answers) {
    if (-not $When) { return $true }
    foreach ($p in $When.PSObject.Properties) { if ([string]$Answers[$p.Name] -ne [string]$p.Value) { return $false } }
    return $true
}
# A blueprint's template with its <placeholders> filled in; list items whose "when" doesn't match the
# answers are left out. Unknown <...> (like <name> in a question) stay as they are.
function Get-Filled($Value, [hashtable]$Ph, [hashtable]$Answers) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        if ($Value -match '^<q\.(\w+)\[\]>$') { return @(([string]$Answers[$Matches[1]]).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        $out = $Value
        foreach ($k in $Ph.Keys) { $out = $out.Replace("<$k>", [string]$Ph[$k]) }
        return $out
    }
    if (Test-JsonObject $Value) {
        $o = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $o[$p.Name] = Get-Filled $p.Value $Ph $Answers }
        return [pscustomobject]$o
    }
    if ($Value -is [Collections.IEnumerable]) {
        $list = @(foreach ($item in @($Value)) {
                if ((Test-JsonObject $item) -and $item.PSObject.Properties['when']) {
                    if (-not (Test-Answers $item.when $Answers)) { continue }
                    $copy = Get-Filled $item $Ph $Answers
                    $copy.PSObject.Properties.Remove('when')
                    , $copy
                } else { , (Get-Filled $item $Ph $Answers) }
            })
        return , $list
    }
    return $Value
}
# Placeholders by exact name (<key>, <Key> and <KEY> are three): a case-sensitive table.
function New-Placeholders([string]$K, [string]$Title) {
    $ph = New-Object Collections.Hashtable ([StringComparer]::Ordinal)
    $ph['key'] = $K; $ph['Key'] = Get-Pascal $K; $ph['KEY'] = Get-Upper $K; $ph['title'] = $Title
    return $ph
}
function Get-Pascal([string]$Key) { return $Key.Substring(0, 1).ToUpper() + $Key.Substring(1) }
function Get-Upper([string]$Key) { return ($Key -creplace '([a-z0-9])([A-Z])', '$1_$2').ToUpper() }
function Get-MapKeys { return @($map.resources | ForEach-Object { $_.key }) }
function Add-Connection($Connection) {
    $map.connections = @($map.connections) + $Connection
    # Log Analytics knows the Application Insights that need it (main.bicep creates it only for them).
    if ($Connection.kind -eq 'logs') {
        $ws = Get-Def $Connection.to
        if ($ws -and @($ws.neededBy) -notcontains $Connection.from) { Set-Prop $ws 'neededBy' (@(@($ws.neededBy) | Where-Object { $_ }) + $Connection.from) }
    }
    Note "connection: $($Connection.from) -> $($Connection.to) ($($Connection.kind)$(if ($Connection.roles) { ': ' + (@($Connection.roles) -join ', ') }))"
}
# A resource's short tag, from the map alone: a choice per environment ("shared/separate"), or that it
# exists only for some answers ("only if separate"). Empty for the rest; a "tag" in the map wins.
function Get-Tag($Def) {
    if (-not $Def) { return '' }
    if ($Def.tag) { return [string]$Def.tag }
    if ($Def.when) { return 'only if ' + ((@($Def.when.PSObject.Properties | ForEach-Object { [string]$_.Value })) -join ', ') }
    if ($Def.choice) { return (@($Def.choice.options) -join '/') }
    return ''
}
function Select-Many([string]$Question, [string[]]$Options, [string[]]$Default) {
    # From a spec (-Init -Spec): the defaults are its answers.
    if ($script:auto) {
        $picked = @($Default | Where-Object { $_ -and $Options -contains $_ })
        $shown = '-'
        if ($picked.Count) { $shown = $picked -join ', ' }
        if (-not $script:ui) { Write-Host "  $Question [$shown]" -ForegroundColor DarkGray }
        else { Send ([ordered]@{ t = 'auto'; question = $Question; value = $shown }) }
        return $picked
    }
    # A suggested default (an analysis) offers only what can be picked here.
    $Default = @($Default | Where-Object { $_ -and $Options -contains $_ })
    # Resources of the map carry their tag (shared/separate, only if separate...).
    $labels = @($Options | ForEach-Object { $t = Get-Tag (Get-Def $_); if ($t) { "$_ · $t" } else { $_ } })
    $listed = @($Options | ForEach-Object { $t = Get-Tag (Get-Def $_); if ($t) { "$_ [$t]" } else { $_ } })
    while ($true) {
        $d = '-'
        if (@($Default).Count) { $d = @($Default) -join ', ' }
        $a = Read-Answer "  $Question ($($listed -join ', '); comma-separated, '-' for none) [$d]: " ([ordered]@{ kind = 'multi'; question = $Question; default = $d; options = @($Options); labels = $labels })
        if (-not $a) { $a = $d }
        if ($a -eq '-') { return @() }
        $picked = @($a.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $bad = @($picked | Where-Object { $Options -notcontains $_ })
        if (-not $bad.Count) { return $picked }
        Note "X not one of them: $($bad -join ', ')"
    }
}
# What a resource gives an app that uses it (the blueprint's "users"): the connection with its roles,
# the app's settings.
function Add-Use([string]$AppKey, [string]$ResKey, $Users, [hashtable]$Ph, $RoleDefault) {
    $app = Get-Def $AppKey
    $p = $Ph.Clone()
    $p['app'] = $AppKey; $p['App'] = Get-Pascal $AppKey; $p['APP'] = Get-Upper $AppKey; $p['app.title'] = $app.title
    $c = Get-Filled $Users.connection $p @{}
    Set-Prop $c 'from' $AppKey
    Set-Prop $c 'to' $ResKey
    if ($Users.roles) {
        $defaultRoles = @($Users.roles.default)
        if ($RoleDefault) { $defaultRoles = @($RoleDefault) }
        $roles = Select-Many (Get-Filled $Users.roles.question $p @{}) @($Users.roles.options) $defaultRoles
        if (-not $roles.Count) { Note "$AppKey gets no role on $ResKey"; return }
        Set-Prop $c 'roles' $roles
    }
    $ordered = [ordered]@{ from = $c.from; to = $c.to }
    foreach ($q in $c.PSObject.Properties) { if (@('from', 'to') -notcontains $q.Name) { $ordered[$q.Name] = $q.Value } }
    Add-Connection ([pscustomobject]$ordered)
    $settings = @($app.appSettings | Where-Object { $_ })
    $filled = Get-Filled $Users.settings $p @{} # a list (not wrapped again in @())
    foreach ($s in $filled) {
        if (-not $s) { continue }
        if (@($settings | Where-Object { $_.name -eq $s.name }).Count) { Note "${AppKey}: $($s.name) is already set, kept"; continue }
        $settings += $s
        Note "${AppKey}: setting $($s.name) = $($s.value)"
    }
    Set-Prop $app 'appSettings' $settings
}

# The runtimes Azure offers now on Linux (az): "web" (App Service: DOTNETCORE|10.0, NODE|22-lts...) or
# "function" (Functions: DOTNET-ISOLATED|10.0, Node|22...). Empty when az can't tell (then any is taken).
function Get-Runtimes([string]$Which) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { return @() }
    # Asked once per run (every app asks it).
    if (-not $script:runtimes) { $script:runtimes = @{} }
    if (-not $script:runtimes.ContainsKey($Which)) {
        if ($Which -eq 'web') { $script:runtimes[$Which] = @(Try-Az @('webapp', 'list-runtimes', '--os', 'linux') | Where-Object { $_ } | ForEach-Object { ([string]$_) -replace '^([^:]+):', '$1|' }) }
        else { $script:runtimes[$Which] = @(Try-Az @('functionapp', 'list-runtimes', '--os', 'linux') | Where-Object { $_ -and $_.linux_fx_version } | ForEach-Object { [string]$_.linux_fx_version }) }
    }
    return @($script:runtimes[$Which])
}
# A suggested runtime Azure doesn't offer any more (the project targets an old version): the closest newer
# one of the same stack, else the newest; $null when Azure's list isn't known or it is offered.
function Get-NewerRuntime([string]$Runtime, [string]$Which, [string]$Hosting) {
    $offered = @(Get-Runtimes $Which)
    if ($Hosting -eq 'flex') { $offered = @($offered | Where-Object { $_ -match '^(DOTNET-ISOLATED|Node|Python|Java|PowerShell)\|' }) }
    if (-not $offered.Count -or $offered -contains $Runtime) { return $null }
    $num = { param($r) $v = 0.0; if ($r.Split('|')[-1] -match '^(\d+(\.\d+)?)') { $v = [double]$Matches[1] }; $v }
    $stack = $Runtime.Split('|')[0]
    $same = @($offered | Where-Object { $_.Split('|')[0] -ceq $stack } | Sort-Object { & $num $_ })
    if (-not $same.Count) { return $null }
    $newer = @($same | Where-Object { (& $num $_) -gt (& $num $Runtime) })
    if ($newer.Count) { return $newer[0] }
    return $same[-1]
}
# When a runtime's support ends, as Azure reports it (Functions' Flex Consumption list has the dates;
# App Service's .NET, Node, Python versions end with the same ones). $null when unknown.
function Get-RuntimeEnd([string]$Runtime) {
    $parts = $Runtime.Split('|')
    $name = $parts[0].ToLower()
    if ($name -eq 'dotnetcore' -or $name -eq 'dotnet') { $name = 'dotnet-isolated' }
    $version = ($parts[-1] -replace '[^0-9.].*$', '') -replace '\.0$', ''
    $list = @(Try-Az @('functionapp', 'list-flexconsumption-runtimes', '--location', [string]$map.regions.default, '--runtime', $name))
    foreach ($r in $list) {
        if (-not $r -or -not $r.endOfLifeDate) { continue }
        $v = ([string]$r.sku.functionAppConfigProperties.runtime.version) -replace '\.0$', ''
        if ($v -ne $version) { continue }
        $words = ([string]$r.endOfLifeDate).Split(' ')
        try { return [datetime]::ParseExact("$($words[1]) $($words[2]) $($words[3])", 'MMM d yyyy', [Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
    }
    return $null
}
# A runtime question: what Azure offers now, refused otherwise; a warning when its support ends within a
# year. Flex Consumption runs dotnet-isolated, node, python, java and powershell.
function Read-Runtime([string]$Label, [string]$Default, [string]$Which, [string]$Hosting) {
    $offered = @(Get-Runtimes $Which)
    if ($Hosting -eq 'flex') { $offered = @($offered | Where-Object { $_ -match '^(DOTNET-ISOLATED|Node|Python|Java|PowerShell)\|' }) }
    if ($offered.Count) {
        $line = 'Azure offers now:'
        foreach ($o in $offered) {
            if (($line + $o).Length -gt 100) { Note $line; $line = '   ' }
            $line += " $o"
        }
        Note $line
    }
    while ($true) {
        $v = Ask $Label $Default
        if (-not $offered.Count -or $offered -contains $v) { break }
        Note "X $v isn't one Azure offers now (the list above)"
    }
    $end = Get-RuntimeEnd $v
    if ($end -and $end -lt (Get-Date).AddMonths(12)) {
        Say "    $v ends its support on $($end.ToString('yyyy-MM-dd')): a newer version is safer ('<' goes back to change it)." 'Yellow'
    } elseif ($end) { Note "$v is supported until $($end.ToString('yyyy-MM-dd'))" }
    return $v
}

# One resource from its blueprint, with what it needs first (recursively). Returns its key.
function Add-FromBlueprint([string]$Kind, [hashtable]$Preset, $Spec) {
    $bp = Get-Blueprint $Kind
    $taken = Get-MapKeys
    if ($Preset) {
        $title = $Preset.title
        $newKey = $Preset.key
        Head "$($bp.title): $title"
    } else {
        Head "$($bp.title)"
        Note $bp.about
        $count = @($map.resources | Where-Object { $_.kind -eq $Kind }).Count
        $default = [string]$bp.title
        if ($count) { $default = "$($bp.title) $($count + 1)" }
        if ($Spec -and $Spec.title) { $default = [string]$Spec.title }
        $title = Ask "Title of the new $($bp.title)" $default
        $suggest = [string]$bp.keyDefault
        for ($i = 2; $taken -contains $suggest; $i++) { $suggest = "$($bp.keyDefault)$i" }
        if ($Spec -and $Spec.key) { $suggest = [string]$Spec.key }
        while ($true) {
            $newKey = Ask 'Key in the map (letters and digits, starting with a small letter)' $suggest
            if ($newKey -cnotmatch '^[a-z][A-Za-z0-9]*$') { Note 'X letters and digits, starting with a small letter'; continue }
            if ($taken -contains $newKey) { Note "X $newKey is in the map already"; continue }
            break
        }
    }
    $answers = @{}
    $ph = New-Placeholders $newKey $title
    foreach ($q in @($bp.questions | Where-Object { $_ })) {
        $label = Get-Filled $q.label $ph @{}
        $qd = [string](Get-Filled ([string]$q.default) $ph @{})
        if ($Spec -and $Spec.answers -and $null -ne $Spec.answers.($q.id)) { $qd = [string]$Spec.answers.($q.id) }
        if ($q.runtimes) { $answers[$q.id] = Read-Runtime $label $qd ([string]$q.runtimes) ([string]$answers['hosting']) }
        elseif ($q.options) { $answers[$q.id] = Select-Option $label @($q.options) $qd } else { $answers[$q.id] = Ask $label $qd }
        $v = [string]$answers[$q.id]
        $ph["q.$($q.id)"] = $v
        $ph["q.$($q.id).name"] = $v.Split('|')[0].ToLower()
        $ph["q.$($q.id).version"] = $v.Split('|')[-1]
    }
    # With sign-in the health path passes without it: never the root (infra/generate.ps1 refuses it too).
    $healthQ = @($bp.questions | Where-Object { $_ -and $_.id -eq 'health' }) | Select-Object -First 1
    if ($healthQ -and $answers.ContainsKey('signIn') -and @('', 'none') -notcontains ([string]$answers['signIn']).ToLower()) {
        while (@('/', '/*') -contains ([string]$answers['health'])) {
            Note "X health path $($answers['health']) with sign-in would leave the whole app without sign-in (it passes without sign-in): a path of its own, e.g. /health"
            $answers['health'] = Ask (Get-Filled $healthQ.label $ph @{}) '/health'
            $ph['q.health'] = [string]$answers['health']
            $ph['q.health.name'] = ([string]$answers['health']).Split('|')[0].ToLower()
            $ph['q.health.version'] = ([string]$answers['health']).Split('|')[-1]
        }
    }
    # The naming type: the catalog's, or another type of naming.json a spec names ("namingType": "dfunc" for a
    # function app with Durable Functions, as analyze.ps1 suggests).
    $namingType = [string]$bp.naming.type
    if ($Spec -and $Spec.namingType) {
        if ($naming.types.([string]$Spec.namingType)) {
            $namingType = [string]$Spec.namingType
            # Its length limit: the catalog type's, when naming.json has none for it.
            $base = [string]$bp.naming.type
            if (-not $naming.maxLength.$namingType -and $naming.maxLength.$base) { Set-Prop $naming.maxLength $namingType ([int]$naming.maxLength.$base); $script:namingChanged = $true }
        }
        else { Note "X ${newKey}: namingType $($Spec.namingType) is not in naming.json; $namingType kept" }
    }
    # Its own sub application name (several APIs...): the naming type, or the key when that is taken.
    $target = $namingType
    if (@($map.resources | Where-Object { $_.target -eq $target -or $_.type -eq $target }).Count) { $target = $newKey.ToLower() }
    # An app's own identity has its app's target (named after the app, see Get-IdentityRuleName).
    if ($Preset -and $Preset.target) { $target = [string]$Preset.target }
    $ph['target'] = $target
    if ($Preset -and $Preset.owner) { $ph['owner'] = [string]$Preset.owner }

    $links = @()
    $owned = @()
    foreach ($c in @($bp.creates | Where-Object { $_ -and (Test-Answers $_.when $answers) })) {
        $subKey = [string](Get-Filled $c.key $ph $answers)
        $subPreset = @{ key = $subKey; title = [string](Get-Filled $c.title $ph $answers) } # not $preset: that is $Preset
        # The app's own identity ("owner": "<key>"): owned by it, with its target, never shared
        # (infra/LAZYBICEP.md, "Identity").
        $isOwned = $c.kind -eq 'appIdentity' -or $c.owner
        if ($isOwned) {
            $subPreset.owner = $newKey
            $subPreset.target = $target
            if ($c.owner) { $subPreset.owner = [string](Get-Filled $c.owner $ph $answers) }
            if ($c.target) { $subPreset.target = [string](Get-Filled $c.target $ph $answers) }
        }
        $sub = Add-FromBlueprint $c.kind $subPreset
        Head "$($bp.title): $title"
        if ($isOwned) { $owned += $sub }
        # Only a "creates" with a connection links it (an app's identity is named by the app's "identity").
        if ($c.connection) { $links += , @($sub, $c.connection) }
        if ($c.connection.kind -eq 'host') { $ph['host'] = $sub; $ph['host.title'] = (Get-Def $sub).title }
    }
    foreach ($r in @($bp.requires | Where-Object { $_ -and (Test-Answers $_.when $answers) })) {
        # One kind, or one of several ("kinds", named by "as" in a spec: a Front Door's origin app).
        $kinds = @($r.kind)
        if ($r.kinds) { $kinds = @($r.kinds) }
        $as = [string]$r.kind
        if ($r.as) { $as = [string]$r.as }
        # An app's own identity is never offered to another resource.
        $have = @($map.resources | Where-Object { $kinds -contains $_.kind -and -not $_.owner } | ForEach-Object { $_.key })
        $question = Get-Filled $r.question $ph $answers
        $want = $null
        if ($Spec -and $Spec.requires -and $Spec.requires.$as) { $want = [string]$Spec.requires.$as }
        if ($have.Count) {
            if (-not $want -or ($have -notcontains $want -and $want -ne 'new')) { $want = $have[0] }
            $chosen = Select-Option $question (@($have) + 'new') $want
        } else { Note "$question There is none in the map yet: a new one comes first."; $chosen = 'new' }
        if ($chosen -eq 'new') {
            $newKind = $kinds[0]
            if ($kinds.Count -gt 1) { $newKind = Select-Option 'Which kind of new one' $kinds $kinds[0] }
            $chosen = Add-FromBlueprint $newKind $null
            Head "$($bp.title): $title"
        }
        $links += , @($chosen, $r.connection)
        if ($r.field) {
            $ph[[string]$r.field] = $chosen
            # <REGISTRY> for "field": "registry": its key upper-cased, for GitHub variable names (AZURE_<REGISTRY>_NAME).
            $upper = Get-Upper ([string]$r.field)
            if (-not $ph.ContainsKey($upper)) { $ph[$upper] = Get-Upper $chosen }
        }
        if ($r.connection.kind -eq 'host') { $ph['host'] = $chosen; $ph['host.title'] = (Get-Def $chosen).title }
    }

    $entry = Get-Filled $bp.entry $ph $answers
    if ($namingType -ne [string]$bp.naming.type -and $entry.PSObject.Properties['type']) { $entry.type = $namingType }
    # An app's identity names its owner (and its target); the app names its identity.
    if ($Preset -and $Preset.owner) {
        Set-Prop $entry 'target' $target
        Set-Prop $entry 'owner' ([string]$Preset.owner)
    }
    if ($owned.Count) { Set-Prop $entry 'identity' $owned[0] }
    if ($entry.PSObject.Properties['healthCheckPath'] -and $entry.healthCheckPath -eq '-') { $entry.healthCheckPath = '' }
    # A spec's sign-in (an import of a running app): what happens without sign-in and the paths it leaves out go into
    # the entry's signIn (never a client id: that belongs to the environment's answers).
    if ($Spec -and $Spec.signIn -and $Spec.signIn -isnot [string] -and $entry.PSObject.Properties['signIn'] -and (Test-SignInOn $entry)) {
        if ($entry.signIn -is [string]) { $entry.signIn = [pscustomobject][ordered]@{ provider = [string]$entry.signIn } }
        $u = ([string]$Spec.signIn.unauthenticated).ToLower()
        if (@('redirect', '401', '403') -contains $u) { Set-Prop $entry.signIn 'unauthenticated' $u }
        elseif ($u) { Note "X ${newKey}: signIn.unauthenticated $u (redirect, 401 or 403): the catalog's kept" }
        if ($null -ne $Spec.signIn.excludedPaths) {
            $paths = @()
            foreach ($p in @($Spec.signIn.excludedPaths | Where-Object { $_ })) {
                $p = [string]$p
                if (-not $p.StartsWith('/') -or $p -eq '/' -or $p -eq '/*') { Note "X ${newKey}: signIn.excludedPaths $p left out (a path from /, not all of them)"; continue }
                if ($paths -cnotcontains $p) { $paths += $p }
            }
            Set-Prop $entry.signIn 'excludedPaths' @($paths)
        }
    }
    # The catalog's workflows build .NET: another runtime gets no generated deploy (its workflow by hand).
    if ($entry.deploy -and $entry.deploy.dotnet -and $entry.runtime -and $entry.runtime -notmatch '^DOTNET') {
        $entry.PSObject.Properties.Remove('deploy')
        Note "$($entry.runtime): the catalog's deploy workflows build .NET; write the workflow of $newKey by hand (infra/route.ps1 picks the environment)"
    }
    if ($entry.deploy) { Note "deploy: .github/workflows/$($entry.deploy.workflow) builds $($entry.deploy.source)/ on a push to an environment's branch" }
    # Before the app registration (kept last, like in the setup's questions).
    $list = @($map.resources)
    $at = $list.Count
    for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].kind -eq 'entraDeployApp') { $at = $i; break } }
    # (An app's own identity, added first by "creates", stays before it; Read-Resource asks the app's sub
    # application name for it.)
    $map.resources = @($list | Select-Object -First $at) + $entry + @($list | Select-Object -Skip $at)
    $script:defs = @($map.resources)
    Note "resource: $newKey ($Kind) - $title"
    if ($Preset -and $Preset.owner) { Note "$newKey belongs to $($Preset.owner): made and removed with it, never used by another resource" }
    foreach ($l in $links) {
        $c = [ordered]@{ from = $newKey; to = $l[0] }
        foreach ($q in (Get-Filled $l[1] $ph $answers).PSObject.Properties) { $c[$q.Name] = $q.Value }
        Add-Connection ([pscustomobject]$c)
    }

    # Apps that use it (its "users"), or, for a new app, what it uses.
    if ($bp.users) {
        $apps = @($map.resources | Where-Object { @($bp.users.kinds) -contains $_.kind -and $_.key -ne $newKey } | ForEach-Object { $_.key })
        # An app sends its telemetry to one Application Insights: the ones that have it already are left out.
        if ($bp.users.connection.kind -eq 'telemetry') {
            $have = @($apps | Where-Object { $a = $_; @($map.connections | Where-Object { $_.from -eq $a -and $_.kind -eq 'telemetry' }).Count })
            if ($have.Count) { Note "$($have -join ', ') send their telemetry elsewhere already: not offered" }
            $apps = @($apps | Where-Object { $have -notcontains $_ })
        }
        if ($apps.Count) {
            $defaultApps = @($apps | Select-Object -First 1)
            if ($script:specData -or ($Spec -and $Spec.users)) { $defaultApps = @($Spec.users | Where-Object { $_ }) }
            foreach ($a in (Select-Many (Get-Filled $bp.users.question $ph $answers) $apps $defaultApps)) {
                $rd = $null
                if ($Spec -and $Spec.roles -and $Spec.roles.$a) { $rd = @($Spec.roles.$a) }
                Add-Use $a $newKey $bp.users $ph $rd
            }
        }
    }
    if ($bp.app) {
        $usable = @()
        foreach ($d in @($map.resources)) {
            if ($d.key -eq $newKey -or -not $d.kind -or $d.owner) { continue }
            # Only what every environment has (not one that exists only for some answers, like a separate
            # Application Insights of the web app).
            if ($d.when -or $d.optional) { continue }
            $dbp = $null
            if (Test-Path (Join-Path $infra "catalog\$($d.kind).json")) { $dbp = Get-Blueprint $d.kind }
            if ($dbp -and $dbp.users -and @($dbp.users.kinds) -contains $Kind -and -not @($map.connections | Where-Object { $_.from -eq $newKey -and $_.to -eq $d.key }).Count) { $usable += $d.key }
        }
        if ($usable.Count) {
            $defaultUses = @()
            if ($Spec -and $Spec.uses) { $defaultUses = @($Spec.uses) }
            # One Application Insights per app (one telemetry connection string).
            while ($true) {
                $uses = @(Select-Many "What does $title use" $usable $defaultUses)
                $telemetry = @($uses | Where-Object { (Get-Def $_).kind -eq 'appInsights' })
                if ($telemetry.Count -le 1) { break }
                Note "X one Application Insights per app (its telemetry goes to one): pick one of $($telemetry -join ', ')"
            }
            foreach ($u in $uses) {
                $ud = Get-Def $u
                $ubp = Get-Blueprint $ud.kind
                $uph = New-Placeholders $u $ud.title
                $uhost = @($map.connections | Where-Object { $_.from -eq $u -and $_.kind -eq 'host' }) | Select-Object -First 1
                if ($uhost) { $uph['host'] = $uhost.to; $uph['host.title'] = (Get-Def $uhost.to).title }
                $rd = $null
                if ($Spec -and $Spec.roles -and $Spec.roles.$u) { $rd = @($Spec.roles.$u) }
                Add-Use $newKey $u $ubp.users $uph $rd
            }
        }
    }
    # GitHub: the deploy role and the app's name for the workflows, or a Static Web App's token.
    if ($bp.github) {
        $gh = Get-Filled $bp.github $ph $answers
        if ($gh.deployRole) {
            $map.github.deployRoles = @(@($map.github.deployRoles) | Where-Object { $_ }) + [pscustomobject][ordered]@{ role = $gh.deployRole; resource = $newKey }
            Note "GitHub Actions' app registration: $($gh.deployRole) on $newKey"
        }
        # Deploy roles on what the app deploys into besides itself (a container app's registry: AcrPush), with the
        # resource's key filled in ("resource": "<registry>").
        foreach ($dr in @($gh.deployRoles | Where-Object { $_ -and $_.role -and $_.resource })) {
            $have = @(@($map.github.deployRoles) | Where-Object { $_ -and $_.role -eq $dr.role -and $_.resource -eq $dr.resource })
            if ($have.Count) { continue }
            $map.github.deployRoles = @(@($map.github.deployRoles) | Where-Object { $_ }) + [pscustomobject][ordered]@{ role = [string]$dr.role; resource = [string]$dr.resource }
            Note "GitHub Actions' app registration: $($dr.role) on $($dr.resource)"
        }
        if ($gh.variable) { Set-Prop $map.github.variables $gh.variable "{$newKey.name}"; Note "GitHub variable $($gh.variable) = {$newKey.name}" }
        # More variables ("variables": { "AZURE_<KEY>_GROUP": "{<key>.group}", "AZURE_<REGISTRY>_NAME": "{<registry>.name}" }).
        if ($gh.variables) {
            foreach ($p in $gh.variables.PSObject.Properties) {
                $varName = [string](Get-Filled ([string]$p.Name) $ph $answers) # the names have placeholders too
                Set-Prop $map.github.variables $varName ([string]$p.Value)
                Note "GitHub variable $varName = $($p.Value)"
            }
        }
        if ($gh.tokenSecret) {
            $map.github.tokenSecrets = @(@($map.github.tokenSecrets) | Where-Object { $_ }) + [pscustomobject][ordered]@{ name = $gh.tokenSecret; resource = $newKey }
            Note "GitHub secret $($gh.tokenSecret): the deployment token of $newKey"
        }
    }
    # The naming type, providers, steps and delete order it brings.
    if ($bp.naming -and -not $naming.types.($bp.naming.type)) {
        Set-Prop $naming.types $bp.naming.type ([string]$bp.naming.about)
        if ($bp.naming.maxLength) { Set-Prop $naming.maxLength $bp.naming.type ([int]$bp.naming.maxLength) }
        $script:namingChanged = $true
        Note "naming type: $($bp.naming.type) ($($bp.naming.about))"
    }
    foreach ($p in @($bp.providers | Where-Object { $_ })) { if (@($map.providers) -notcontains $p) { $map.providers = @($map.providers) + $p; Note "resource provider: $p" } }
    foreach ($s in @($bp.steps | Where-Object { $_ })) {
        $steps = @($map.steps.setup)
        if ($steps -contains $s.name) { continue }
        $at = [array]::IndexOf($steps, [string]$s.after)
        if ($at -lt 0) { $at = $steps.Count - 1 }
        $map.steps.setup = @($steps[0..$at]) + $s.name + @($steps | Select-Object -Skip ($at + 1))
        Note "step: $($s.name)"
    }
    if ($bp.removeOrder) {
        foreach ($t in @($bp.removeOrder.types)) {
            $order = @($map.removeOrder)
            if (@($order | Where-Object { $_ -ieq $t }).Count) { continue }
            $at = $order.Count
            foreach ($b in @($bp.removeOrder.before)) { $i = [array]::IndexOf(@($order | ForEach-Object { $_.ToLower() }), $b.ToLower()); if ($i -ge 0 -and $i -lt $at) { $at = $i } }
            $map.removeOrder = @($order | Select-Object -First $at) + $t + @($order | Select-Object -Skip $at)
        }
    }
    Set-IdentityRemoveOrder
    return $newKey
}
# The apps' identities are deleted after the apps (an app's identity is added before its app, so its own
# "before" can't say that): moved right after the last app type, added there when the map has one.
function Set-IdentityRemoveOrder {
    # Container apps before their environment and registry (each kind's own "before" may not see the others).
    if ($map.PSObject.Properties['removeOrder']) {
        $fixed = @(Get-ContainerRemoveOrder @($map.removeOrder | Where-Object { $_ }))
        if (($fixed -join ',') -ne (@($map.removeOrder | Where-Object { $_ }) -join ',')) { $map.removeOrder = $fixed }
    }
    if (-not @($map.resources | Where-Object { $_.armType -eq $identityType }).Count) { return }
    $order = @($map.removeOrder | Where-Object { $_ })
    $at = [array]::IndexOf(@($order | ForEach-Object { $_.ToLower() }), $identityType.ToLower())
    $lastApp = -1
    for ($i = 0; $i -lt $order.Count; $i++) { if ($identityAppTypes -contains $order[$i]) { $lastApp = $i } }
    if ($at -ge 0 -and $at -gt $lastApp) { return }
    $rest = @($order | Where-Object { $_ -ine $identityType })
    $lastApp = -1
    for ($i = 0; $i -lt $rest.Count; $i++) { if ($identityAppTypes -contains $rest[$i]) { $lastApp = $i } }
    if ($lastApp -lt 0) { $map.removeOrder = @($rest) + $identityType; return }
    $map.removeOrder = @($rest | Select-Object -First ($lastApp + 1)) + $identityType + @($rest | Select-Object -Skip ($lastApp + 1))
}

# A remove order with container apps before the first Container Apps environment or registry in it (moved there, or
# added there when it has them but no container apps); unchanged otherwise.
function Get-ContainerRemoveOrder([object[]]$Order) {
    $list = @($Order | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $first = -1
    for ($i = 0; $i -lt $list.Count; $i++) { if (@($containerEnvType, $registryType) -contains $list[$i] -and $first -lt 0) { $first = $i } }
    if ($first -lt 0) { return $list }
    $at = -1
    for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i] -ieq $containerAppType) { $at = $i } }
    if ($at -ge 0 -and $at -lt $first) { return $list }
    $rest = @($list | Where-Object { $_ -ine $containerAppType })
    $first = -1
    for ($i = 0; $i -lt $rest.Count; $i++) { if (@($containerEnvType, $registryType) -contains $rest[$i] -and $first -lt 0) { $first = $i } }
    return @(@($rest | Select-Object -First $first) + $containerAppType + @($rest | Select-Object -Skip $first))
}

# Each round of a map mode (and each '<') starts from the files as they are: nothing half-added stays.
function Reset-MapState {
    $script:map = $null
    $script:defs = @()
    if (Test-Path $mapFile) {
        $script:map = Get-Content $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:defs = @($script:map.resources)
    }
    $script:naming = Get-Content (Join-Path $infra 'naming.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:namingChanged = $false
    $script:specData = $null
}

function Save-Map {
    $script:canGoBack = $false # files are written from here on
    Write-JsonFile (Join-Path $infra 'infra.map.json') $map
    Ok 'infra/infra.map.json written'
    if ($script:namingChanged) { Write-JsonFile (Join-Path $infra 'naming.json') $naming; Ok 'infra/naming.json written' }
    Head 'Generate'
    & (Join-Path $infra 'generate.ps1') -Quiet
    if ($LASTEXITCODE -ne 0) { Missing "infra/generate.ps1 failed: main.bicep isn't up to date"; return }
    Ok "infra/$($map.project.template) generated"
    if (Get-Command az -ErrorAction SilentlyContinue) {
        $r = Invoke-Native 'az' @('bicep', 'build', '--file', (Join-Path $infra $map.project.template), '--stdout')
        if ($r.Code -eq 0) { Ok "infra/$($map.project.template) compiles" } else { Missing "infra/$($map.project.template) doesn't compile: $($r.Errors)" }
    }
}

function Invoke-AddResource {
    Say 'Add a resource: asks what it is and what it connects to, then writes the map and generates main.bicep. Nothing in Azure changes yet.' 'Cyan'
    $script:namingChanged = $false
    $addable = @(Get-Blueprints | Where-Object { $_.addable } | Sort-Object kind)
    $kinds = @($addable | ForEach-Object { $_.kind })
    Head 'Resource'
    $from = 'catalog'
    if ($Import) { $from = 'azure' }
    elseif (-not $Kind) { $from = Select-Option 'Add from the catalog, or import from Azure (resources that exist already)' @('catalog', 'azure') 'catalog' }
    $script:imported = $null
    if ($from -eq 'azure') {
        $imp = Get-AzureImport
        if (-not $imp) { throw 'Nothing to import (see above).' }
        $script:imported = $imp
        # What the map has already, by its name in that environment's answers.
        $known = @{}
        $saved = Read-Json (Join-Path $infra "environments\$($imp.environmentName).json")
        if ($saved -and $saved.names) {
            foreach ($r in @($imp.resources)) {
                foreach ($p in $saved.names.PSObject.Properties) {
                    if ([string]$p.Value -eq [string]$r.azureName -and (Get-Def $p.Name) -and (Get-Def $p.Name).kind -eq $r.kind) { $known[[string]$r.key] = $p.Name }
                }
            }
        }
        $keysBefore = @(Get-MapKeys)
        Add-Suggested $imp $known
        $newKey = (@(Get-MapKeys | Where-Object { $keysBefore -notcontains $_ })) -join ', '
        if (-not $newKey) { Note 'nothing was added'; if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @(); code = 1; cancelled = $true }) }; return 1 }
    } else {
        if ($Kind -and $kinds -contains $Kind) { $k = $Kind; Note "kind: $Kind" }
        else {
            foreach ($b in $addable) { Note ("{0,-16} {1}" -f $b.kind, $b.title) }
            $k = Select-Option 'Kind of resource' $kinds 'sqlDatabase'
        }
        $newKey = Add-FromBlueprint $k $null
    }
    Head 'Changes'
    if (-not (Confirm-Step "Write infra/infra.map.json$(if ($script:namingChanged) { ' and naming.json' }) and generate main.bicep?")) {
        Note 'nothing was written'
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @(); code = 1; cancelled = $true }) }
        return 1
    }
    Save-Map
    if ($script:imported) {
        if ($script:importMode -eq 'connect') { Write-ImportedEnvironment $script:imported }
        else { Note "new resources: a dry run of $($script:imported.environmentName) plans them with the naming rules (the imported ones stay as they are)" }
    }
    Head 'Next steps'
    Note "A dry run asks the names of what is new and shows what would be created: .\infra\azure-setup.ps1 -DryRun"
    Note 'then a start creates it (environment by environment); commit infra/ (the map, naming.json, main.bicep).'
    $open = @($script:results | Where-Object { -not $_.Done } | ForEach-Object { $_.Text })
    if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = $open; code = [int][bool]$open.Count; added = $newKey }) }
    else { Write-Host ''; Write-Host "$newKey added to the map." -ForegroundColor Green }
    return [int][bool]$open.Count
}

# A resource of the map as an environment has it in Azure (its saved answers): id, type, group and
# whether the setup made it (the template's managed-by tag; a storage queue can't be tagged). $null when
# it isn't there.
function Find-MapResource($Def, $Saved, [string]$HostKey) {
    $name = [string]$Saved.names.($Def.key)
    $rg = [string]$Saved.names.resourceGroup
    $hostName = ''
    $hostGroup = $rg
    if ($HostKey) {
        $hostName = [string]$Saved.names.$HostKey
        if ($Saved.groups -and $Saved.groups.$HostKey) { $hostGroup = [string]$Saved.groups.$HostKey }
    }
    if ($Def.kind -eq 'sqlDatabase') {
        if (-not $hostName) { return }
        $db = Try-Az @('sql', 'db', 'show', '-g', $hostGroup, '-s', $hostName, '-n', $name)
        if (-not $db) { return }
        return [pscustomobject]@{ Id = $db.id; Type = 'SQL database'; Group = $hostGroup; Ours = [bool]($db.tags -and $db.tags.'managed-by' -eq $managedBy) }
    }
    if ($Def.kind -eq 'storageQueue') {
        if (-not $hostName) { return }
        $id = "/subscriptions/$($Saved.subscriptionId)/resourceGroups/$hostGroup/providers/Microsoft.Storage/storageAccounts/$hostName/queueServices/default/queues/$name"
        if (-not (Try-Az @('resource', 'show', '--ids', $id))) { return }
        return [pscustomobject]@{ Id = $id; Type = "queue of $hostName"; Group = $hostGroup; Ours = $true }
    }
    $r = @(Try-Az @('resource', 'list', '-g', $rg, '--name', $name, '--resource-type', $Def.armType)) | Where-Object { $_ -and $_.name -ieq $name } | Select-Object -First 1
    if (-not $r) { return }
    return [pscustomobject]@{ Id = $r.id; Type = $Def.title; Group = $rg; Ours = [bool]($r.tags -and $r.tags.'managed-by' -eq $managedBy) }
}
# Deletes it: an app's role assignments first (they'd stay as "unknown"; its own identity's, or the system-assigned
# one's of an entry without one; $Saved: the environment's answers, with the identity's name), a Key Vault's
# purge asked. The app's own identity is deleted after the app, by the caller.
function Remove-MapResource($Def, $Found, $Saved) {
    if ($Def.identity -or $identityAppTypes -contains [string]$Def.armType) {
        $app = $null
        $identityName = ''
        if ($Def.identity) { $identityName = [string]$Saved.names.([string]$Def.identity) }
        else { $app = Show-App ([string]$Def.armType) $Found.Group (($Found.Id -split '/')[-1]) }
        $ident = Get-AppIdentity $Def $Found.Group $identityName $app
        if ($ident) {
            $ras = Get-RoleAssignments $ident.PrincipalId
            foreach ($ra in $ras) { Invoke-Az @('role', 'assignment', 'delete', '--ids', $ra.id) | Out-Null }
            if ($ras.Count) { Ok "$($ras.Count) role assignment(s) of its managed identity $($ident.Name) removed" }
        }
    }
    Note 'deleting (can take a few minutes)...'
    Invoke-Az @('resource', 'delete', '--ids', $Found.Id) | Out-Null
    if ($Def.kind -eq 'keyVault') {
        $vaultName = ($Found.Id -split '/')[-1]
        if ((Try-Az @('keyvault', 'show-deleted', '--name', $vaultName)) -and (Confirm-Step "Purge Key Vault $vaultName now (frees its name; its secrets can't be recovered then)?" -DefaultNo -Danger)) {
            Invoke-Az @('keyvault', 'purge', '--name', $vaultName) | Out-Null
            Ok "Key Vault $vaultName purged"
        }
    }
}
# The environment's saved answers without the resource (its name, group and the answers asked with it).
function Remove-SavedName([string]$File, $Saved, $Def) {
    $Saved.names.PSObject.Properties.Remove($Def.key)
    if ($Saved.groups) { $Saved.groups.PSObject.Properties.Remove($Def.key) }
    $answers = @($Def.size.answer, $Def.choice.answer, $Def.admin.answer)
    if (Test-SignInOn $Def) { $answers += @((Get-SignInClientIdAnswer ([string]$Def.key)), (Get-SignInObjectIdAnswer ([string]$Def.key)), (Get-SignInGroupAnswer ([string]$Def.key))) }
    foreach ($a in @($answers | Where-Object { $_ })) { $Saved.PSObject.Properties.Remove($a) }
    [IO.File]::WriteAllText($File, (ConvertTo-Json -InputObject $Saved -Depth 10) + "`n", $utf8)
    Note "infra/environments/$(Split-Path $File -Leaf): $($Def.key) taken out"
}

# Takes a resource out of the map with everything that refers to it; what runs on it must go first.
function Invoke-RemoveResource {
    Say 'Remove a resource from the map: everything that refers to it goes too; Azure is not changed.' 'Cyan'
    $script:namingChanged = $false
    Head 'Resource'
    # An app's own identity goes with its app, never on its own.
    $keys = @($map.resources | Where-Object { @('group', 'name') -notcontains $_.ask -and -not $_.owner } | ForEach-Object { $_.key })
    foreach ($d in @($map.resources | Where-Object { $keys -contains $_.key })) { Note ("{0,-16} {1} ({2})" -f $d.key, $d.title, $d.kind) }
    if ($Key -and $keys -contains $Key) { $k = $Key; Note "resource: $Key" } else { $k = Select-Option 'Resource to remove' $keys $keys[0] }
    $def = Get-Def $k
    $ownedDefs = @($map.resources | Where-Object { $_.owner -eq $k })
    $goneKeys = @(@($k) + @($ownedDefs | ForEach-Object { [string]$_.key }))
    # What it is in or on (a database's server, a queue's storage account): needed to find it in Azure.
    $hostKey = [string](@($map.connections | Where-Object { $_.from -eq $k -and $_.kind -eq 'host' }) | Select-Object -First 1).to
    $on = @($map.connections | Where-Object { $_.to -eq $k -and @('host', 'origin', 'source', 'deliver') -contains $_.kind } | ForEach-Object { $_.from })
    # A Container Apps environment or a registry stays while a container app of the map runs in it or pulls from it.
    if (@($containerEnvType, $registryType) -contains [string]$def.armType) { $on = @(@($on) + @(Get-ContainerAppsUsing $k) | Select-Object -Unique) }
    $mirrors = @($map.resources | ForEach-Object { @($_.secrets) } | Where-Object { $_ -and $_.mirror -and $_.mirror.resource -eq $k })
    if ($on.Count -or $mirrors.Count) {
        if ($on.Count) { Missing "$k can't go while $($on -join ', ') run on it, are in it, are in front of it or take its events: remove them first" }
        if ($mirrors.Count) { Missing "$k keeps the secret $($mirrors[0].name) of a Key Vault (its mirror): change that in the map first" }
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @($script:results | Where-Object { -not $_.Done } | ForEach-Object { $_.Text }); code = 1 }) }
        return 1
    }

    Head 'Changes'
    Note "resource: $k ($($def.kind)) $($def.title)"
    foreach ($od in $ownedDefs) { Note "resource: $($od.key) ($($od.kind)) $($od.title), owned by $k" }
    $pattern = '\{([^{}|]*\|)*(' + ((@($goneKeys | ForEach-Object { [regex]::Escape($_) })) -join '|') + ')\.'
    # The registries a removed container app pulled from (before its connections go): only their deploy role
    # (AcrPush) is looked at again below, never another registry's.
    $goneRegistries = @()
    if ([string]$def.armType -eq $containerAppType) {
        if ($def.registry) { $goneRegistries += [string]$def.registry }
        $goneRegistries += @($map.connections | Where-Object { $_ -and $_.from -eq $k } | ForEach-Object { @(([string]$_.to).Split('|')) } | Where-Object { (Get-Def $_).armType -eq $registryType })
        $goneRegistries = @($goneRegistries | Select-Object -Unique)
    }
    $conns = @()
    foreach ($c in @($map.connections)) {
        $alts = @($c.to.Split('|'))
        $left = @($alts | Where-Object { $goneKeys -notcontains $_ })
        if ($goneKeys -contains $c.from -or -not $left.Count) { Note "connection: $($c.from) -> $($c.to) ($($c.kind))"; continue }
        if ($left.Count -lt $alts.Count) { $c.to = $left -join '|'; Note "connection: $($c.from) -> $($c.to) (without $k)" }
        $conns += $c
    }
    $map.connections = $conns
    foreach ($d in @($map.resources)) {
        if ($goneKeys -contains $d.key) { continue }
        if ($d.appSettings) {
            $keep = @()
            foreach ($s in @($d.appSettings)) { if ([string]$s.value -match $pattern) { Note "$($d.key): setting $($s.name) (uses $k)" } else { $keep += $s } }
            Set-Prop $d 'appSettings' $keep
        }
        if ($d.neededBy -and @($d.neededBy) -contains $k) { Set-Prop $d 'neededBy' @(@($d.neededBy) | Where-Object { $_ -ne $k }) }
        # A deploy that migrated it (deploy.migrate) migrates nothing any more.
        if ($d.deploy -and $d.deploy.migrate -and [string]$d.deploy.migrate.database -eq $k) {
            $d.deploy.PSObject.Properties.Remove('migrate')
            Note "$($d.key): its deploy doesn't migrate $k any more (deploy.migrate)"
        }
        if ($d.stateStorage -eq $k) { Missing "$($d.key) keeps its state in ${k}: give it another stateStorage first" }
    }
    $map.resources = @($map.resources | Where-Object { $goneKeys -notcontains $_.key })
    $script:defs = @($map.resources)
    foreach ($p in @($map.github.variables.PSObject.Properties)) { if ([string]$p.Value -match $pattern) { $map.github.variables.PSObject.Properties.Remove($p.Name); Note "GitHub variable $($p.Name)" } }
    $map.github.deployRoles = @($map.github.deployRoles | Where-Object { $_ -and $_.resource -ne $k })
    # The deploy role on the removed app's registry (AcrPush) goes with the last container app that deploys into it
    # (the removed registry's own went above; other registries' roles are left as they are).
    $unusedRegistry = { param($dr) $goneRegistries -contains [string]$dr.resource -and -not @(Get-ContainerAppsUsing ([string]$dr.resource)).Count }
    foreach ($dr in @($map.github.deployRoles | Where-Object { $_ -and (& $unusedRegistry $_) })) {
        Note "GitHub Actions' app registration: $($dr.role) on $($dr.resource) (no container app deploys into it any more)"
    }
    $map.github.deployRoles = @($map.github.deployRoles | Where-Object { $_ -and -not (& $unusedRegistry $_) })
    $map.github.tokenSecrets = @($map.github.tokenSecrets | Where-Object { $_ -and $_.resource -ne $k })
    foreach ($dm in @($map.domains | Where-Object { $_.resource -eq $k })) { Note "custom domain $($dm.answer)" }
    $map.domains = @($map.domains | Where-Object { $_.resource -ne $k })
    $map.live = @($map.live | Where-Object { $_.resource -ne $k })
    if ($map.PSObject.Properties['values']) {
        foreach ($mv in @($map.values | Where-Object { $_ -and $_.app -eq $k })) { Note "value $($mv.answer)" }
        $map.values = @($map.values | Where-Object { $_ -and $_.app -ne $k })
    }
    foreach ($v in @($map.resources | Where-Object { $_.kind -eq 'keyVault' -and $_.secrets })) {
        $gone = @($v.secrets | Where-Object { $_ -and $_.app -eq $k -and $_.by -eq 'hand' })
        # A secret another app reads too stays.
        $gone = @($gone | Where-Object { $n = $_.name; -not @($map.resources | Where-Object { $_.key -ne $k -and @($_.appSettings | Where-Object { $_ -and [string]$_.value -match "SecretName=$([regex]::Escape($n))\)" }).Count }).Count })
        foreach ($g in $gone) { Note "$($v.key): secret $($g.name) (put in by hand; Azure keeps it until you delete it)" }
        if ($gone.Count) { $v.secrets = @($v.secrets | Where-Object { $gone -notcontains $_ }) }
    }
    if (@($script:results | Where-Object { -not $_.Done }).Count) {
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @($script:results | Where-Object { -not $_.Done } | ForEach-Object { $_.Text }); code = 1 }) }
        return 1
    }
    if (-not (Confirm-Step "Write infra/infra.map.json without $k and generate main.bicep?" -DefaultNo)) {
        Note 'nothing was written'
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @(); code = 1; cancelled = $true }) }
        return 1
    }
    Save-Map

    # Azure: a deployment never deletes. Deleting is destructive and can't be undone, so it is never the
    # default: first a yes/no (no by default), then for each environment the resource's exact name typed,
    # and for production "delete prod" as well. Only what the setup made, never a shared resource.
    Head 'Azure'
    $envFiles = @(Get-ChildItem (Join-Path $infra 'environments') -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { (Read-Json $_.FullName).names.$k })
    $deleted = 0
    $wanted = $false
    if (-not $envFiles.Count) { Note "no environment has $k (none made it yet): nothing to delete in Azure" }
    else {
        Note "Azure still has $k where an environment made it: $((@($envFiles | ForEach-Object { "$($_.BaseName) ($((Read-Json $_.FullName).names.$k))" })) -join ', ')."
        Note 'Deleting it there is DESTRUCTIVE and can''t be undone (its data goes with it). Keeping it costs what it costs.'
        $wanted = Confirm-Step "Delete $k from Azure as well? (destructive, can't be undone)" -DefaultNo -Danger
        if (-not $wanted) { Note "kept in Azure; delete it later by hand (az resource delete) or run this for another resource" }
    }
    $signedIn = $wanted -and (Get-Command az -ErrorAction SilentlyContinue) -and (Try-Az @('account', 'show'))
    if ($wanted -and -not $signedIn) { Note 'The Azure CLI is not signed in (az login): nothing is deleted; by hand:' }
    foreach ($f in @($envFiles | Where-Object { $wanted })) {
        $envAbbr = $f.BaseName
        $saved = Read-Json $f.FullName
        # Its names by their rules first (this resource and its identity are out of the map by now: checked here).
        $nameProblems = @(Get-SavedNameProblems $saved)
        foreach ($d in @(@($def) + @($ownedDefs) | Where-Object { $_ -and $saved.names -and $saved.names.($_.key) })) {
            $pr = Test-Name ([string]$d.type) (([string]$saved.names.($d.key)).ToLowerInvariant())
            if ($pr) { $nameProblems += "names.$($d.key): $pr" }
        }
        $nameProblems = @($nameProblems | Select-Object -Unique)
        if ($nameProblems.Count) { Missing "${envAbbr}: infra/environments/$($f.Name) holds names that break the naming rules ($($nameProblems -join '; ')): nothing deleted there; fix the file"; continue }
        $name = [string]$saved.names.$k
        $group = [string]$saved.names.resourceGroup
        if ($saved.groups -and $saved.groups.$k) { Note "${envAbbr}: $name is shared from $($saved.groups.$k): kept (another environment or project uses it)"; continue }
        # The app's own identity, deleted after it (Azure deletes nothing with the app).
        $ownedNames = @($ownedDefs | Where-Object { $saved.names.($_.key) } | ForEach-Object { [pscustomobject]@{ Def = $_; Name = [string]$saved.names.($_.key) } })
        if (-not $signedIn) {
            Note "  ${envAbbr}: az resource delete -g $group -n $name --resource-type $($def.armType)   (check it first in the portal)"
            foreach ($o in $ownedNames) { Note "  ${envAbbr}: then az identity delete -g $group -n $($o.Name)   (its identity, after its role assignments: az role assignment list --assignee <its principal id> --all)" }
            if (Test-SignInOn $def) {
                $savedSignIn = [string]$saved.(Get-SignInClientIdAnswer $k)
                if (Test-Guid $savedSignIn) { Note "  ${envAbbr}: and its sign-in's app registration: az ad app delete --id $savedSignIn" }
                else { Note "  ${envAbbr}: and its sign-in's app registration $name, once you have checked it is this app's (owners, sign-in of the deleted app): az ad app delete --id <its client id>" }
            }
            continue
        }
        $script:subscription = $saved.subscriptionId
        $found = Find-MapResource $def $saved $hostKey
        if (-not $found) {
            Note "${envAbbr}: $name is not in Azure (any more)"
            foreach ($o in $ownedNames) {
                if (Find-MapResource $o.Def $saved '') { Note "${envAbbr}: its identity $($o.Name) is still there with its roles: kept (-Check reports it); delete it by hand once nothing uses it (az identity delete -g $group -n $($o.Name))" }
                Remove-SavedName $f.FullName $saved $o.Def
            }
            Remove-SavedName $f.FullName $saved $def
            continue
        }
        if (-not $found.Ours) { Note "${envAbbr}: $name was not made by the setup (no managed-by tag): kept; delete it in the portal if you are sure"; continue }
        Say ''
        Say "    DELETE FROM AZURE: $($found.Type) $name in $($found.Group) ($envAbbr, $($naming.environments.$envAbbr)). This can't be undone." 'Red'
        if ($envAbbr -eq 'prod') { Say '    THIS IS PRODUCTION: whatever uses it there stops working.' 'Red' }
        if ($def.identity -or $identityAppTypes -contains [string]$def.armType) { Note '  its managed identity''s role assignments go first' }
        if (Test-SignInOn $def) { Note "  then its sign-in's app registration $name (asked)" }
        foreach ($o in $ownedNames) { Note "  then its own identity $($o.Name), after the app" }
        if ($def.kind -eq 'keyVault') { Note '  a deleted vault stays recoverable for 30 days (asked: purge it)' }
        if (@('sqlDatabase', 'storage', 'storageQueue', 'serviceBus') -contains $def.kind) { Note '  ITS DATA GOES WITH IT (back it up first if you need it)' }
        $question = "To delete $name from $envAbbr, type its name exactly (anything else keeps it)"
        $typed = Read-Answer "  ${question}: " ([ordered]@{ kind = 'text'; question = $question; default = ''; danger = $true })
        if ($typed -cne $name) { Note "${envAbbr}: $name kept (the name didn't match)"; continue }
        if ($envAbbr -eq 'prod') {
            $question = 'Production: type "delete prod" to delete it (anything else keeps it)'
            $typed = Read-Answer "  ${question}: " ([ordered]@{ kind = 'text'; question = $question; default = ''; danger = $true })
            if ($typed -cne 'delete prod') { Note "${envAbbr}: $name kept"; continue }
        }
        Remove-MapResource $def $found $saved
        Ok "${envAbbr}: $name deleted"
        foreach ($o in $ownedNames) {
            $ofound = Find-MapResource $o.Def $saved ''
            if (-not $ofound) { Note "${envAbbr}: its identity $($o.Name) is not in Azure (any more)" }
            elseif (-not $ofound.Ours) { Note "${envAbbr}: its identity $($o.Name) was not made by the setup: kept (-Check reports it); delete it by hand once nothing uses it" }
            else {
                Remove-MapResource $o.Def $ofound $saved
                Ok "${envAbbr}: its identity $($o.Name) deleted"
            }
            Remove-SavedName $f.FullName $saved $o.Def
        }
        if (Test-SignInOn $def) { $idAnswer = Get-SignInClientIdAnswer $k; Remove-SignInRegistration $name ([string]$saved.$idAnswer) $idAnswer }
        Remove-SavedName $f.FullName $saved $def
        $deleted++
    }

    Head 'Next steps'
    Note 'Commit infra/ (the map, main.bicep, the environments'' saved answers).'
    if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @(); code = 0; removed = $true; key = $k; deleted = $deleted }) }
    else { Write-Host ''; Write-Host "$k removed from the map." -ForegroundColor Green }
    return 0
}

# --- a new project (an empty instance) ---------------------------------------------------------------

# The map of a project without resources yet: the resource group and GitHub Actions' app registration,
# which every project has.
function New-BaseMap([string]$Name, [string]$Description, [string]$Region, [string]$Deployment) {
    $rg = Get-Filled (Get-Blueprint 'resourceGroup').entry (New-Placeholders 'resourceGroup' 'Resource group') @{}
    $deploy = Get-Filled (Get-Blueprint 'entraDeployApp').entry (New-Placeholders 'deployApp' 'App registration (Entra)') @{}
    return [pscustomobject][ordered]@{
        '$comment'  = "The map of this infrastructure (infra/README.md, 'The map'): every resource of one environment, and how it is named, asked, deployed, sized, priced, connected, checked and removed. infra/azure-setup.ps1 runs from it (-AddResource / -RemoveResource change it), infra/lazybicep.ps1 shows it, infra/generate.ps1 makes infra/main.bicep from it (never edit that)."
        project     = [pscustomobject][ordered]@{ name = $Name; description = $Description; setup = 'azure-setup.ps1'; template = 'main.bicep'; managedByTag = 'infra/main.bicep'; deploymentName = $Deployment; subscriptionMatch = '' }
        regions     = [pscustomobject][ordered]@{ default = $Region; staticWebApp = @('westeurope', 'eastus2', 'centralus', 'westus2', 'eastasia') }
        providers   = @()
        costExtras  = @('Custom domains, certificates, managed identities, app registration')
        resources   = @($rg, $deploy)
        domains     = @()
        domainNotes = [pscustomobject]@{}
        github      = [pscustomobject][ordered]@{
            variables    = [pscustomobject][ordered]@{ AZURE_CLIENT_ID = '{deployApp.appId}'; AZURE_TENANT_ID = '{tenant}'; AZURE_SUBSCRIPTION_ID = '{subscription}' }
            tokenSecrets = @()
            deployRoles  = @()
            push         = ''
            workflows    = @()
        }
        live        = @()
        cleanup     = @()
        connections = @()
        steps       = [pscustomobject][ordered]@{
            setup  = @('Environment', 'Azure CLI', 'Prefix', 'Region', 'Names', 'GitHub', 'Estimated monthly cost', '1. Azure resources', 'Budget', '2. GitHub -> Azure trust', '3. GitHub environment', '4. Custom domains', '5. Live', 'Next steps')
            remove = @('Environment', 'Azure CLI', 'What would be removed', 'Removing', 'Next steps')
        }
        removeOrder = @('microsoft.alertsmanagement/smartDetectorAlertRules', 'Microsoft.Web/certificates', 'Microsoft.Web/serverFarms', 'Microsoft.OperationalInsights/workspaces')
    }
}

# The analysis of the solution (infra/analyze.ps1): once per run, shown every round ('<' starts the
# questions over). $null when it fails (then the resources are added by hand).
function Get-Analysis {
    if (-not $script:analysis) {
        Note "looking through $root"
        try { $script:analysis = & (Join-Path $infra 'analyze.ps1') -Path $root -PassThru }
        catch { Note "X the analysis failed: $($_.Exception.Message)"; return $null }
    }
    $a = $script:analysis
    Note "$($a.scanned.dotnet) .NET project(s), $($a.scanned.apps) app(s) to deploy"
    if (-not @($a.resources).Count) { Note 'nothing to suggest: add the resources by hand' }
    foreach ($r in @($a.resources)) {
        $line = '{0,-13} {1,-14} {2}' -f $r.kind, $r.key, $r.title
        if ($r.uses) { $line += "   uses $(@($r.uses) -join ', ')" }
        Note $line
    }
    foreach ($n in @($a.notes)) { Say "    ! $n" 'Yellow' }
    return $a
}
# The analysis's resources, each offered with what it was found from. Adding one asks the usual questions
# with the analysis's answers as the defaults; one left out (or given another key) is left out of (or
# renamed in) what the apps after it use.
function Add-Suggested($Analysis, [hashtable]$Known) {
    $keyOf = @{}
    # Already in the map (an import into a map: the same name in Azure): not offered, its key used instead.
    if ($Known) { foreach ($k in $Known.Keys) { $keyOf[$k] = $Known[$k] } }
    foreach ($r in @($Analysis.resources)) {
        if ($Known -and $Known.ContainsKey([string]$r.key)) { Note "$($r.azureName): in the map already as $($Known[[string]$r.key])"; continue }
        Head "Resources: suggested $($r.kind) $($r.title)"
        foreach ($e in @($r.evidence)) { Note "found: $e" }
        if (-not (Confirm-Step "Add $($r.title) ($($r.kind))?")) { $keyOf[[string]$r.key] = $null; Note 'left out'; continue }
        $spec = $r | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        if ((Get-MapKeys) -contains $spec.key) { $spec.PSObject.Properties.Remove('key') }
        if ($spec.answers -and $spec.answers.runtime) {
            $which = 'web'
            if ($r.kind -eq 'functionApp') { $which = 'function' }
            $newer = Get-NewerRuntime ([string]$spec.answers.runtime) $which ([string]$spec.answers.hosting)
            if ($newer) {
                Say "    ! the project targets $($spec.answers.runtime), which Azure doesn't offer any more: $newer suggested (move the project to it)" 'Yellow'
                $spec.answers.runtime = $newer
            }
        }
        if ($spec.uses) { $spec.uses = @(@($spec.uses) | ForEach-Object { if ($keyOf.ContainsKey($_)) { $keyOf[$_] } else { $_ } } | Where-Object { $_ }) }
        if ($spec.requires) {
            foreach ($q in @($spec.requires.PSObject.Properties)) {
                if (-not $keyOf.ContainsKey([string]$q.Value)) { continue }
                if ($keyOf[[string]$q.Value]) { $spec.requires.($q.Name) = $keyOf[[string]$q.Value] } else { $spec.requires.PSObject.Properties.Remove($q.Name) }
            }
        }
        if ($spec.roles) {
            $roles = [ordered]@{}
            foreach ($q in $spec.roles.PSObject.Properties) {
                $k = $q.Name
                if ($keyOf.ContainsKey($k)) { $k = $keyOf[$k] }
                if ($k) { $roles[$k] = @($q.Value) }
            }
            $spec.roles = [pscustomobject]$roles
        }
        $keyOf[[string]$r.key] = Add-FromBlueprint ([string]$r.kind) $null $spec
        if ($r.config) { Add-AppConfig $keyOf[[string]$r.key] $r.config $keyOf }
    }
    $script:keyOf = $keyOf
}

# An app's configuration from the analysis (infra/analyze.ps1): settings under its own names for the map's
# resources (identity-based: a trigger's Connection...), Key Vault secrets you put in (the app reads them
# through Key Vault references), values asked per environment; the code changes it needs are shown.
function Add-AppConfig([string]$AppKey, $Config, [hashtable]$KeyOf) {
    $app = Get-Def $AppKey
    if (-not $app) { return }
    $title = [string]$app.title
    Head "Configuration of $title"
    foreach ($w in @($Config.warnings | Where-Object { $_ })) { Say "    ! code: $w" 'Yellow' }
    $have = @(@($app.appSettings) | Where-Object { $_ } | ForEach-Object { [string]$_.name })
    # Settings: their {key.value}s follow the keys the resources got (left out: the setting too).
    $settings = @{}
    foreach ($x in @($Config.settings | Where-Object { $_ })) {
        if ($have -contains [string]$x.name) { continue }
        $v = [string]$x.value
        $ok = $true
        foreach ($m in [regex]::Matches($v, '\{(\w+)\.')) {
            $k = $m.Groups[1].Value
            if ($KeyOf.ContainsKey($k)) { if ($KeyOf[$k]) { $v = $v.Replace("{$k.", "{$($KeyOf[$k]).") } else { $ok = $false } }
            elseif (-not (Get-Def $k)) { $ok = $false }
        }
        if (-not $ok) { Note "$($x.name): its resource isn't in the map, left out"; continue }
        Note "setting $($x.name) = $v   ($($x.why))"
        $settings[[string]$x.name] = $v
    }
    if ($settings.Count) {
        $names = @($settings.Keys | Sort-Object)
        foreach ($n in @(Select-Many "Settings $title gets under its own names (identity-based)" $names $names)) {
            $app.appSettings = @(@($app.appSettings) | Where-Object { $_ }) + [pscustomobject][ordered]@{ name = $n; value = $settings[$n] }
            Note "${AppKey}: setting $n = $($settings[$n])"
        }
    }
    # Secrets: into the vault the app uses (or the map's first), read through Key Vault references.
    $secrets = @($Config.secrets | Where-Object { $_ -and $have -notcontains [string]$_.setting })
    if ($secrets.Count) {
        $vaultKey = [string](@($map.connections | Where-Object { $_.from -eq $AppKey -and (Get-Def $_.to).kind -eq 'keyVault' } | ForEach-Object { $_.to }) | Select-Object -First 1)
        if (-not $vaultKey) { $vaultKey = [string](@($map.resources | Where-Object { $_.kind -eq 'keyVault' } | ForEach-Object { $_.key }) | Select-Object -First 1) }
        if (-not $vaultKey) { Note "X $($secrets.Count) secret(s) of $title, but no Key Vault in the map: add one (a), then them by hand" }
        else {
            $vault = Get-Def $vaultKey
            foreach ($x in $secrets) { Note "secret $($x.setting) <- $vaultKey $($x.name)   ($($x.why))" }
            $names = @($secrets | ForEach-Object { [string]$_.setting })
            foreach ($n in @(Select-Many "Secrets of $title to keep in $($vault.title) (you put the values in)" $names $names)) {
                $x = $secrets | Where-Object { $_.setting -eq $n } | Select-Object -First 1
                if (-not @(@($vault.secrets) | Where-Object { $_ -and $_.name -eq $x.name }).Count) {
                    Set-Prop $vault 'secrets' (@(@($vault.secrets) | Where-Object { $_ }) + [pscustomobject][ordered]@{ name = [string]$x.name; by = 'hand'; label = [string]$x.path; what = "$($x.path) of $title"; setting = $n; app = $AppKey })
                }
                $app.appSettings = @(@($app.appSettings) | Where-Object { $_ }) + [pscustomobject][ordered]@{ name = $n; value = "@Microsoft.KeyVault(VaultName={$vaultKey.name};SecretName=$($x.name))"; about = 'a Key Vault secret you put in' }
                Note "${AppKey}: setting $n <- Key Vault secret $($x.name) (put in by hand)"
            }
            if (-not @($map.connections | Where-Object { $_.from -eq $AppKey -and $_.to -eq $vaultKey }).Count) {
                Add-Use $AppKey $vaultKey (Get-Blueprint 'keyVault').users (New-Placeholders $vaultKey $vault.title) $null
            }
        }
    }
    # Values per environment: main.bicep parameters, asked by every run.
    $values = @($Config.values | Where-Object { $_ -and $have -notcontains [string]$_.setting })
    if ($values.Count) {
        foreach ($x in $values) { Note "value $($x.setting): asked per environment   ($($x.why))" }
        $names = @($values | ForEach-Object { [string]$_.setting })
        if (-not $map.PSObject.Properties['values']) { Set-Prop $map 'values' @() }
        foreach ($n in @(Select-Many "Values of $title asked per environment" $names $names)) {
            $x = $values | Where-Object { $_.setting -eq $n } | Select-Object -First 1
            $answer = [string]$x.answer
            for ($i = 2; @(@($map.values) | Where-Object { $_ -and $_.answer -eq $answer }).Count; $i++) { $answer = "$($x.answer)$i" }
            $map.values = @(@($map.values) | Where-Object { $_ }) + [pscustomobject][ordered]@{ answer = $answer; param = $answer; label = [string]$x.label; setting = $n; app = $AppKey }
            $app.appSettings = @(@($app.appSettings) | Where-Object { $_ }) + [pscustomobject][ordered]@{ name = $n; value = "{$answer}" }
            Note "${AppKey}: setting $n = {$answer} (asked per environment)"
        }
    }
}

# Importing from Azure (infra/import.ps1): the subscription, the resource groups, the resources (every one
# the catalog has a kind for, by default), the environment they are and its own group. Read once per run
# for the same answers ('<' starts the questions over). $null when it can't (no Azure CLI, not signed in).
function Get-AzureImport {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Note 'X the Azure CLI is not installed (winget install Microsoft.AzureCLI)'; return $null }
    $account = Try-Az @('account', 'show')
    if (-not $account) { Note 'X the Azure CLI is not signed in: az login, then start again'; return $null }
    Note "signed in as $($account.user.name)"
    $subs = @(Invoke-Az @('account', 'list') | Where-Object { $_.state -eq 'Enabled' })
    $guess = 0
    for ($i = 0; $i -lt $subs.Count; $i++) {
        $mark = ''
        if ($subs[$i].isDefault) { $mark = '  <- CLI default'; $guess = $i }
        Note "$($i + 1). $($subs[$i].name) ($($subs[$i].id))$mark"
    }
    $n = 0
    while (-not [int]::TryParse((Ask 'Subscription (number)' ([string]($guess + 1))), [ref]$n) -or $n -lt 1 -or $n -gt $subs.Count) { Note "X 1 to $($subs.Count)" }
    $sub = $subs[$n - 1]
    $groups = @(Invoke-Az @('group', 'list', '--subscription', $sub.id) | Where-Object { $_ } | ForEach-Object { [string]$_.name } | Sort-Object)
    if (-not $groups.Count) { Note "X $($sub.name) has no resource groups"; return $null }
    $picked = @($ResourceGroup | ForEach-Object { $_.Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $groups -contains $_ })
    if (-not $picked.Count) {
        if ($groups.Count -le 40) { Note "resource groups: $($groups -join ', ')" }
        while (-not $picked.Count) {
            $picked = @(Select-Many 'Resource groups to import from' $groups @())
            if (-not $picked.Count) { Note 'X at least one' }
        }
    }
    $listKey = "$($sub.id)|$($picked -join ',')"
    if (-not $script:importList -or $script:importList.Key -ne $listKey) {
        Note "reading $($picked -join ', ')"
        $l = & (Join-Path $infra 'import.ps1') -Subscription $sub.id -ResourceGroup $picked -List -PassThru
        $script:importList = [pscustomobject]@{ Key = $listKey; List = $l }
    }
    $items = @($script:importList.List.resources | Where-Object { $_.state -ne 'with' })
    if (-not $items.Count) { Note 'X nothing to import there'; return $null }
    # Labels: the names (with their group when two groups have the same name).
    $label = @{}
    foreach ($it in $items) {
        $l = [string]$it.name
        if (@($items | Where-Object { $_.name -eq $it.name }).Count -gt 1) { $l = "$($it.group)/$($it.name)" }
        $label[$l] = $it
        $what = 'no kind in the catalog (reported, with a prompt to add it)'
        if ($it.state -eq 'kind') { $what = $it.kind }
        Note ('{0,-48} {1}' -f $l, $what)
    }
    $options = @($label.Keys | Sort-Object)
    $default = @($options | Where-Object { $label[$_].state -eq 'kind' })
    $chosen = @(Select-Many 'Resources to put into the map' $options $default)
    $ids = @($chosen | ForEach-Object { $label[$_].id })
    $envs = @($naming.environments.PSObject.Properties | ForEach-Object { $_.Name })
    $guessEnv = 'prod'
    foreach ($e in $envs) { if (@($picked | Where-Object { $_ -match "(^|[-_])$e($|[-_])" }).Count) { $guessEnv = $e } }
    $envName = Select-Option 'Which environment are they' $envs $guessEnv
    # Connect: the map manages these resources (their names become the environment's answers; a start adds
    # what is missing: managed identities, roles, the GitHub trust and deployments). New: the map's own,
    # made by its definitions (the naming rules, managed identities) next to them.
    Note "connect: the map takes these resources over; their names become the answers of $envName, and a start adds what is missing (managed identities, roles, the GitHub trust, environment and deploy workflows), each change asked first"
    Note 'new: the map gets the same resources, made new by its definitions (the naming rules, managed identities, no keys) next to these; move the data and remove the old ones by hand'
    $script:importMode = Select-Option "Connect to these resources, or create new ones by the map's definitions" @('connect', 'new') 'connect'
    $main = $picked[0]
    if ($picked.Count -gt 1) {
        $most = @($chosen | ForEach-Object { $label[$_].group } | Group-Object | Sort-Object Count -Descending | ForEach-Object { $_.Name }) | Select-Object -First 1
        if ($most) { $main = $most }
        $main = Select-Option "The resource group of $envName (the others' resources are shared from them)" $picked $main
    }
    $importKey = "$listKey|$($ids -join ',')|$envName|$main"
    if (-not $script:importData -or $script:importData.Key -ne $importKey) {
        Note 'reading the resources (their settings, queues, databases, role assignments)'
        $d = & (Join-Path $infra 'import.ps1') -Subscription $sub.id -ResourceGroup $picked -Ids $ids -Environment $envName -MainGroup $main -PassThru
        $script:importData = [pscustomobject]@{ Key = $importKey; Data = $d }
    }
    $a = $script:importData.Data
    foreach ($r in @($a.resources)) {
        $line = '{0,-15} {1,-16} {2}' -f $r.kind, $r.key, $r.azureName
        if ($r.uses) { $line += "   uses $(@($r.uses) -join ', ')" }
        Note $line
    }
    foreach ($m in @($a.missing)) { Say "    ! $($m.name) ($($m.type)): $(@($m.resources) -join ', '): no kind in the catalog" 'Yellow' }
    if ($a.prompts) { Say "    ! a prompt to add each is in $($a.prompts): paste it to Claude Code in the LazyBicep repository" 'Yellow' }
    foreach ($x in @($a.notes)) { Say "    ! $x" 'Yellow' }
    return $a
}

# After the map of an import: the real names as the environment's answers (marked imported, so its first
# run asks every question once with them as the defaults). The keys are the map's (renamed ones followed).
function Write-ImportedEnvironment($Import) {
    $envName = [string]$Import.environmentName
    $file = Join-Path $infra "environments\$envName.json"
    $old = Read-Json $file
    if ($old -and -not (Confirm-Step "Add the imported names to infra/environments/$envName.json (its other answers stay)?")) { return }
    $src = $Import.environment
    $names = [ordered]@{}
    $groups = [ordered]@{}
    foreach ($p in $src.names.PSObject.Properties) {
        $k = $p.Name
        if ($script:keyOf -and $script:keyOf.ContainsKey($k)) { $k = $script:keyOf[$k] }
        if ($k) { $names[$k] = [string]$p.Value }
    }
    foreach ($p in $src.groups.PSObject.Properties) {
        $k = $p.Name
        if ($script:keyOf -and $script:keyOf.ContainsKey($k)) { $k = $script:keyOf[$k] }
        if ($k -and $names.Contains($k)) { $groups[$k] = [string]$p.Value }
    }
    # A Function App's Flex Consumption plan: the map's resource it runs on.
    foreach ($x in @($Import.extraNames)) {
        $of = [string]$x.of
        if ($script:keyOf -and $script:keyOf.ContainsKey($of)) { $of = $script:keyOf[$of] }
        $c = @($map.connections | Where-Object { $_.from -eq $of -and $_.kind -eq $x.connection }) | Select-Object -First 1
        if ($c) { $names[$c.to] = [string]$x.name }
    }
    # The resource group's key is the map's.
    $rgDef = @($map.resources | Where-Object { $_.ask -eq 'group' }) | Select-Object -First 1
    if ($rgDef -and $names.Contains('resourceGroup') -and $rgDef.key -ne 'resourceGroup') { $names[$rgDef.key] = $names['resourceGroup']; $names.Remove('resourceGroup') }
    $subs = [ordered]@{}
    foreach ($d in @($map.resources | Where-Object { $_.target })) { $subs[[string]$d.target] = '' }
    # A connected container app's sign-in: the client id (and object id) it runs with, as <key>SignInClientId -
    # the setup uses it by its id (a registration found by name only when you alone own it).
    $ids = [ordered]@{}
    if ($src.signInIds) {
        foreach ($p in $src.signInIds.PSObject.Properties) {
            $k = $p.Name
            if ($script:keyOf -and $script:keyOf.ContainsKey($k)) { $k = $script:keyOf[$k] }
            $d = $null
            if ($k) { $d = Get-Def $k }
            if (-not ($d -and (Test-SignInOn $d) -and (Test-Guid ([string]$p.Value.clientId)))) { continue }
            $ids[(Get-SignInClientIdAnswer $k)] = [string]$p.Value.clientId
            if (Test-Guid ([string]$p.Value.objectId)) { $ids[(Get-SignInObjectIdAnswer $k)] = [string]$p.Value.objectId }
        }
    }
    if ($old) {
        foreach ($a in $ids.Keys) { if (-not $old.$a) { Set-Prop $old $a $ids[$a] } }
        # Into saved answers: the imported resources' names (and groups, sub names) only.
        $added = @()
        if (-not $old.names) { Set-Prop $old 'names' ([pscustomobject]@{}) }
        if (-not $old.groups) { Set-Prop $old 'groups' ([pscustomobject]@{}) }
        if (-not $old.subs) { Set-Prop $old 'subs' ([pscustomobject]@{}) }
        foreach ($k in $names.Keys) {
            if ($k -eq 'resourceGroup') { continue }
            if ([string]$old.names.$k -ne [string]$names[$k]) { Set-Prop $old.names $k $names[$k]; $added += $k }
            if ($groups.Contains($k)) { Set-Prop $old.groups $k $groups[$k] }
        }
        foreach ($t in $subs.Keys) { if ($null -eq $old.subs.$t) { Set-Prop $old.subs $t '' } }
        if ($names.Contains('resourceGroup') -and $old.names.resourceGroup -and $old.names.resourceGroup -ne $names['resourceGroup']) { Note "X $envName's resource group is $($old.names.resourceGroup), these are in $($names['resourceGroup']): the map makes its own resources in $($old.names.resourceGroup)" }
        [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $old -Depth 10) + "`n", (New-Object Text.UTF8Encoding $false))
        if ($added.Count) { Ok "infra/environments/$envName.json: the names of $($added -join ', ') (a dry run of $envName finds them)" }
        else { Ok "infra/environments/$envName.json has their names already" }
        return
    }
    $answers = [ordered]@{ imported = [string]$src.imported; subscriptionId = [string]$src.subscriptionId; location = [string]$src.location }
    if ($src.staticLocation) { $answers.staticLocation = [string]$src.staticLocation }
    $answers.prefix = [string]$naming.defaults.prefix
    $answers.subs = $subs
    $answers.names = $names
    $answers.groups = $groups
    foreach ($a in $ids.Keys) { $answers[$a] = $ids[$a] }
    New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
    [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $answers -Depth 10) + "`n", (New-Object Text.UTF8Encoding $false))
    Ok "infra/environments/$envName.json written: the real names of $envName (its first dry run asks every question once with them)"
}

# A new project: its name and prefix, then its resources: suggested by an analysis of the solution and
# offered one by one, or from the catalog by hand (or all of them from a spec file: -Init -SpecFile
# spec.json, see infra/LAZYBICEP.md), then the map and main.bicep.
function Invoke-Init {
    Say 'New project: asks its name and prefix, then its resources (suggested by an analysis of the solution, or from the catalog by hand); writes infra.map.json and generates main.bicep. Nothing in Azure changes yet.' 'Cyan'
    if ($map) { throw 'infra/infra.map.json exists already: -AddResource adds to it (or move it away to start over).' }
    $script:namingChanged = $true
    $p = $null
    if ($SpecFile) {
        if (-not (Test-Path $SpecFile)) { throw "No spec file $SpecFile." }
        $script:specData = Read-Json (Resolve-Path $SpecFile).Path
        $script:auto = $true
        $p = $script:specData.project
        Note "from $SpecFile"
    }
    $suggested = $null
    $script:imported = $null
    if (-not $SpecFile) {
        Head 'Analysis'
        $how = 'analyze'
        if ($Import) { $how = 'azure' }
        elseif (-not $Analyze) { $how = Select-Option 'Analyze the solution, import from Azure (resource groups), or add the resources by hand' @('analyze', 'azure', 'manual') 'analyze' }
        if ($how -eq 'analyze') { $suggested = Get-Analysis }
        elseif ($how -eq 'azure') { $suggested = Get-AzureImport; $script:imported = $suggested }
        else { Note 'by hand: the resources one by one from the catalog' }
        if ($suggested) { $p = $suggested.project }
    }
    Head 'Project'
    $default = Split-Path $root -Leaf
    if ($p -and $p.name) { $default = $p.name }
    $name = Ask 'Project name' $default
    $default = "$name on Azure"
    if ($p -and $p.description) { $default = $p.description }
    $description = Ask 'One line about it' $default
    while ($true) {
        $default = [string]$naming.defaults.prefix
        if ($p -and $p.prefix) { $default = $p.prefix }
        $prefix = (Ask 'Prefix of every name (client-project, one part when they are the same)' $default).ToLower()
        if ($prefix -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { break }
        Note 'X lowercase letters and digits, parts separated by single hyphens'
    }
    $default = 'westeurope'
    if ($p -and $p.region) { $default = $p.region }
    $region = Ask 'Region' $default
    $default = $prefix.Split('-')[-1] + '-{env}'
    if ($p -and $p.deploymentName) { $default = $p.deploymentName }
    $deployment = Ask "Name of the deployments in Azure ({env} = the environment)" $default
    $script:map = New-BaseMap $name $description $region $deployment
    $script:defs = @($script:map.resources)
    $naming.defaults.prefix = $prefix

    Head 'Resources'
    $addable = @(Get-Blueprints | Where-Object { $_.addable } | Sort-Object kind)
    foreach ($b in $addable) { Note ("{0,-16} {1}" -f $b.kind, $b.about) }
    if ($script:specData) {
        # A spec as it is, its apps' configuration too (settings, Key Vault secrets, values per environment), as
        # an analysis offers them.
        $specKeyOf = @{}
        foreach ($r in @($script:specData.resources)) {
            $added = Add-FromBlueprint ([string]$r.kind) $null $r
            $specKeyOf[[string]$r.key] = $added
            if ($r.config -and $added) { Add-AppConfig $added $r.config $specKeyOf }
        }
    }
    else {
        if ($suggested) { Add-Suggested $suggested }
        while ($true) {
            $default = 'done'
            if (@($map.resources).Count -le 2) { $default = 'appService' }
            Head 'Resources'
            Note ("in the map: " + ((@($map.resources | ForEach-Object { "$($_.key) ($($_.kind))" })) -join ', '))
            $k = Select-Option 'Add a resource (done = that is all)' (@($addable | ForEach-Object { $_.kind }) + 'done') $default
            if ($k -eq 'done') { break }
            [void](Add-FromBlueprint $k $null $null)
        }
    }
    $script:auto = $false

    Head 'Changes'
    foreach ($d in @($map.resources)) { Note ("{0,-16} {1} ({2})" -f $d.key, $d.title, $d.kind) }
    # A spec file is the answer to this too (it runs without questions).
    if (-not $script:specData -and -not (Confirm-Step 'Write infra/infra.map.json and naming.json and generate main.bicep?')) {
        Note 'nothing was written'
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @(); code = 1; cancelled = $true }) }
        return 1
    }
    Save-Map
    if ($script:imported -and $script:imported.environmentName) {
        if ($script:importMode -eq 'connect') { Write-ImportedEnvironment $script:imported }
        else { Note "new resources: $($script:imported.environmentName)'s first dry run plans them with the naming rules (the imported ones stay as they are)" }
    }
    Head 'Next steps'
    Note 'A dry run asks the names of every resource for an environment and shows what would be created:'
    Note '  .\infra\azure-setup.ps1 -DryRun     (or .\infra\lazybicep.ps1)'
    Note 'then a start creates it, the GitHub trust and the GitHub environment. Commit infra/.'
    $vars = @($map.github.variables.PSObject.Properties | Where-Object { $_.Name -notlike 'AZURE_*_ID' } | ForEach-Object { $_.Name })
    if ($vars.Count) { Note "The apps' deploy workflows use the GitHub environment's variables ($($vars -join ', '), AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID); add them to infra.map.json's github.workflows to have them named in the next steps." }
    $open = @($script:results | Where-Object { -not $_.Done } | ForEach-Object { $_.Text })
    if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = $open; code = [int][bool]$open.Count; added = $name }) }
    else { Write-Host ''; Write-Host "$name is set up in infra/infra.map.json." -ForegroundColor Green }
    return [int][bool]$open.Count
}

# --- the setup -------------------------------------------------------------------------------------

# The environment's monthly budget: Azure mails the people given at 80 % and 100 % of it and when the month's
# forecast passes it. An alert only: nothing is stopped. Asked after the cost estimate (its default: the
# estimate with room, in tens); '-' for none.
function Read-Budget($Saved, [string]$Env) {
    # Answers saved before there was a budget: a check has none; a dry run or start asks it (even when the
    # saved answers are kept).
    $hadAuto = $script:auto
    if ($Saved -and -not $Saved.PSObject.Properties['budget']) {
        if ($script:mode -eq 'check') { Note 'no budget in the saved answers yet (a dry run or start asks it)'; return [pscustomobject]@{ Amount = '-'; Emails = '' } }
        $script:auto = $false
    }
    try { return Read-BudgetAnswers $Saved $Env } finally { $script:auto = $hadAuto }
}
function Read-BudgetAnswers($Saved, [string]$Env) {
    $default = '-'
    if ($script:costTotal -gt 0) { $default = [string]([Math]::Max(10, [Math]::Ceiling($script:costTotal * 1.5 / 10) * 10)) }
    if ($Saved -and $Saved.budget) { $default = [string]$Saved.budget }
    while ($true) {
        $amount = Ask "Monthly budget of $Env, in the subscription's billing currency (mails at 80 % and 100 % of it and when the forecast passes it; nothing is stopped; '-' for none)" $default
        if ($amount -eq '-' -or ($amount -match '^\d+$' -and [int]$amount -gt 0)) { break }
        Note 'X a whole amount (e.g. 150), or -'
    }
    $emails = ''
    if ($amount -ne '-') {
        $default = [string]$script:vals['me']
        if ($Saved -and $Saved.budgetEmails) { $default = [string]$Saved.budgetEmails }
        while ($true) {
            $emails = Ask "Who gets the budget's mails (comma-separated)" $default
            $list = @($emails.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($list.Count -and -not @($list | Where-Object { $_ -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$' }).Count) { $emails = $list -join ', '; break }
            Note 'X e-mail addresses, comma-separated'
        }
    }
    return [pscustomobject]@{ Amount = $amount; Emails = $emails }
}
# The budget on the environment's resource group (Microsoft.Consumption/budgets, monthly-<environment>): set
# with the Azure CLI, apart from main.bicep, so a subscription that doesn't offer budgets doesn't stop the
# deployment. A dry run and a check show it and the month's spending; a start sets it, asked first.
function Get-BudgetUrl([string]$Subscription, [string]$Group, [string]$GhEnv) {
    return "https://management.azure.com/subscriptions/$Subscription/resourceGroups/$Group/providers/Microsoft.Consumption/budgets/monthly-$($GhEnv)?api-version=2023-11-01"
}
function Set-Budget($Budget, [string]$Subscription, [string]$Group, [string]$GhEnv) {
    $url = Get-BudgetUrl $Subscription $Group $GhEnv
    $have = Try-Az @('rest', '--method', 'get', '--url', $url)
    if ($have -and $have.properties.currentSpend) { Note ("spent this month: {0:0.00} {1}$(if ($have.properties.forecastSpend) { '; forecast {2:0.00}' })" -f [double]$have.properties.currentSpend.amount, $have.properties.currentSpend.unit, [double]$have.properties.forecastSpend.amount) }
    if ($Budget.Amount -eq '-') {
        if ($have) { Note "monthly-$GhEnv ($($have.properties.amount)) is there, but the answers have none: kept (delete it in the portal if it isn't wanted)" }
        else { Note 'no budget (the answers: -)' }
        return
    }
    $emails = @($Budget.Emails.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $haveEmails = @()
    if ($have -and $have.properties.notifications) { $haveEmails = @($have.properties.notifications.PSObject.Properties | ForEach-Object { @($_.Value.contactEmails) } | Select-Object -Unique) }
    $same = $have -and [double]$have.properties.amount -eq [double]$Budget.Amount -and -not (Compare-Object @($haveEmails | Sort-Object) @($emails | Sort-Object))
    if ($same) { Ok "budget monthly-$GhEnv`: $($Budget.Amount) a month, mails to $($emails -join ', ')"; return }
    $what = "monthly budget of $Group`: $($Budget.Amount)$(if ($have) { " (now $($have.properties.amount))" }), mails to $($emails -join ', ') at 80 % and 100 % and when the forecast passes it"
    if ($script:readOnly) { Missing $what; return }
    if (-not (Confirm-Step "Set the $($what)?")) { Missing $what; return }
    # The first month: an existing budget's (it can't move), else this one.
    $start = (Get-Date).ToUniversalTime().ToString('yyyy-MM-01T00:00:00Z')
    if ($have -and $have.properties.timePeriod.startDate) { $start = [string]$have.properties.timePeriod.startDate }
    $notify = [ordered]@{}
    foreach ($n in @(@('actual80', 80, 'Actual'), @('actual100', 100, 'Actual'), @('forecast100', 100, 'Forecasted'))) {
        $notify[$n[0]] = [ordered]@{ enabled = $true; operator = 'GreaterThanOrEqualTo'; threshold = $n[1]; thresholdType = $n[2]; contactEmails = @($emails) }
    }
    $body = [ordered]@{ properties = [ordered]@{ category = 'Cost'; amount = [int]$Budget.Amount; timeGrain = 'Monthly'; timePeriod = @{ startDate = $start }; notifications = $notify } }
    try {
        Invoke-Az @('rest', '--method', 'put', '--url', $url, '--body', "@$(Write-TempJson 'budget.json' $body)") | Out-Null
        Ok "budget monthly-$GhEnv`: $($Budget.Amount) a month, mails to $($emails -join ', ')"
    } catch { Missing "budget: Azure refused it (some subscriptions don't offer budgets): $(($_.Exception.Message -split "`n")[-1])" }
}

function Invoke-Setup {
    if (-not $script:replaying) {
        switch ($script:mode) {
            'dryrun' { Say 'Dry run: every question is asked, nothing is changed or saved.' 'Cyan' }
            'check' { Say 'Check: the saved answers, no questions, nothing is changed.' 'Cyan' }
            default { Say 'Start: every change is asked first.' 'Cyan' }
        }
        if ($script:mode -ne 'check') { Say "Enter accepts the value in brackets; '<' goes back to the previous question." 'Cyan' }
    }
    $script:res = [ordered]@{}
    $script:apps = @{}
    $script:choices = [ordered]@{}
    $script:vals = @{}
    $script:secrets = @{}
    $script:subs = [ordered]@{}
    $script:currentDef = $null
    $script:identities = @{}
    $script:oldIdentities = @()
    $script:oldSqlUsers.Clear()
    $script:lackingSecrets = @{} # container apps' missing Key Vault secrets (key -> @{ Vault; Secret; Ref })
    $imageUnknown = @()
    $signInPassed = @{}
    $paramsFile = $null

    Head 'Environment'
    $envs = @($naming.environments.PSObject.Properties | ForEach-Object { $_.Name })
    if ($script:mode -eq 'check') {
        # Only environments that are set up (have saved answers) can be checked.
        $envs = @($envs | Where-Object { Test-Path (Join-Path $infra "environments\$_.json") })
        if (-not $envs.Count) { throw 'No environment is set up yet (infra/environments/ is empty): run a dry run or start first.' }
    }
    foreach ($e in $envs) { Note ("{0,-5} {1}" -f $e, $naming.environments.$e) }
    if ($Environment -and $envs -contains $Environment) {
        $script:envAbbr = $Environment
        Note "environment: $Environment"
    } elseif ($script:mode -eq 'check' -and $envs.Count -eq 1) {
        $script:envAbbr = $envs[0]
        Note "environment: $($envs[0]) (the only one set up)"
    } else {
        $auto = $script:auto
        $script:auto = $false # the environment is asked in every mode (unless given)
        $script:envAbbr = Select-Option 'Environment' $envs $envs[0]
        $script:auto = $auto
    }
    $envAbbr = $script:envAbbr
    $ghEnv = [string]$naming.environments.$envAbbr # the GitHub environment (and the workflows' input)
    $script:vals['env'] = $envAbbr
    $script:vals['kvdns'] = '.vault.azure.net' # environment().suffixes.keyvaultDns in Azure's public cloud
    $script:vals['ghEnv'] = $ghEnv
    $script:vals['envName'] = $ghEnv.Substring(0, 1).ToUpper() + $ghEnv.Substring(1) # Production (main.bicep: the same)
    $envFile = Join-Path $infra "environments\$envAbbr.json"
    $script:saved = Read-Json $envFile
    $saved = $script:saved
    Assert-SavedNames $saved "infra/environments/$envAbbr.json"
    $script:fromCopy = $false # answers of another environment, not saved for this one yet
    $script:copyBranch = ''
    if ($script:ui) { Send ([ordered]@{ t = 'env'; env = $envAbbr; ghEnv = $ghEnv; saved = [bool]$saved }) }
    if ($saved) { Note "defaults from infra/environments/$envAbbr.json" } else { Note 'first run of this environment: defaults from infra/naming.json' }
    # A new environment can start from another one's answers (names moved to this environment), still
    # asking every question.
    if (-not $saved -and $script:mode -ne 'check') {
        $others = @($naming.environments.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { $_ -ne $envAbbr -and (Test-Path (Join-Path $infra "environments\$_.json")) })
        if ($others.Count) {
            $from = Select-Option 'Start from the answers of another environment (every question is still asked)' (@($others) + '-') $others[0]
            if ($from -ne '-') {
                $script:saved = Copy-Answers (Read-Json (Join-Path $infra "environments\$from.json")) $from $envAbbr
                $script:fromCopy = $true
                $saved = $script:saved
                Assert-SavedNames $saved "infra/environments/$from.json"
                Note "defaults from infra/environments/$from.json, moved to ${envAbbr}: names, custom domains and the deploy branch with $envAbbr instead of $from (each still asked); shared resources kept"
            }
        }
    }
    # Imported from Azure (infra/import.ps1): the real names, not answers yet: every question once.
    if ($saved -and $saved.imported -and $script:mode -ne 'check') {
        $script:fromCopy = $true
        Note "imported: $($saved.imported)"
    }
    # Saved answers: keep them all (the default; each is shown in grey) or go through the questions.
    if ($saved -and -not $script:fromCopy -and $script:mode -ne 'check') {
        $change = (Read-Answer "  The answers of $envAbbr are saved. Change anything? [y/N] " ([ordered]@{ kind = 'confirm'; question = "The answers of $envAbbr are saved. Change anything?"; default = 'n' })).ToLower()
        $script:auto = -not $change.StartsWith('y')
        if ($script:auto) { Note 'keeping the saved answers' }
    }

    Head 'Azure CLI'
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'The Azure CLI is not installed: winget install Microsoft.AzureCLI, then a new terminal.' }
    $account = Try-Az @('account', 'show')
    if (-not $account) { throw 'The Azure CLI is not signed in: run  az login  and start again.' }
    Note "signed in as $($account.user.name)"
    $script:vals['me'] = [string]$account.user.name
    $subs = @(Invoke-Az @('account', 'list') | Where-Object { $_.state -eq 'Enabled' })
    for ($i = 0; $i -lt $subs.Count; $i++) {
        $mark = ''
        if ($subs[$i].isDefault) { $mark = '  <- CLI default' }
        Note "$($i + 1). $($subs[$i].name) ($($subs[$i].id))$mark"
    }
    $guess = -1
    for ($i = 0; $i -lt $subs.Count; $i++) { if ($saved -and $subs[$i].id -eq $saved.subscriptionId) { $guess = $i } }
    if ($guess -lt 0 -and $map.project.subscriptionMatch) { for ($i = 0; $i -lt $subs.Count; $i++) { if ($guess -lt 0 -and $subs[$i].name -match $map.project.subscriptionMatch) { $guess = $i } } }
    if ($guess -lt 0) { for ($i = 0; $i -lt $subs.Count; $i++) { if ($subs[$i].isDefault) { $guess = $i } } }
    $n = 0
    if (-not [int]::TryParse((Ask 'Subscription (number)' ([string]($guess + 1))), [ref]$n) -or $n -lt 1 -or $n -gt $subs.Count) { throw 'No such subscription.' }
    $chosen = $subs[$n - 1]
    $script:subscription = $chosen.id
    $subscription = $chosen.id
    $tenant = $chosen.tenantId
    $script:vals['subscription'] = $subscription
    $script:vals['tenant'] = $tenant
    Ok "subscription $($chosen.name)"

    Head 'Prefix (infra/README.md, "Naming")'
    while ($true) {
        $default = [string]$naming.defaults.prefix
        if ($saved -and $saved.prefix) { $default = $saved.prefix }
        $script:prefix = (Ask 'Client-project prefix (one part when client and project are the same)' $default).ToLower()
        if ($script:prefix -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { break }
        Note 'X lowercase letters and digits, parts separated by single hyphens'
    }
    $script:samePrefix = $saved -and $saved.prefix -eq $script:prefix
    $project = $script:prefix

    Head 'Region'
    $rgDef = $defs | Where-Object { $_.ask -eq 'group' } | Select-Object -First 1
    $script:rgName = Read-Name $rgDef.label $rgDef.type (Get-Default $rgDef.key (Get-RuleName $rgDef.type))
    $rgName = $script:rgName
    $script:vals['rg'] = $rgName
    $rgExists = [bool](Invoke-Az @('group', 'exists', '-n', $rgName))
    if ($rgExists) {
        $location = (Invoke-Az @('group', 'show', '-n', $rgName)).location
    } else {
        $default = [string]$map.regions.default
        if ($saved -and $saved.location) { $default = $saved.location }
        $location = Ask 'Region' $default
    }
    $script:location = $location
    $state = 'new'
    if ($rgExists) { $state = 'exists' }
    Note "resource group ${rgName}: $state ($location)"
    Mark $rgDef.key $rgName $state ''
    $script:res[$rgDef.key] = [pscustomobject]@{ Name = $rgName; Group = ''; Found = $null }
    $hasStatic = [bool]@($defs | Where-Object { $_.armType -eq 'Microsoft.Web/staticSites' }).Count
    if (-not $hasStatic -or $staticLocations -contains $location) { $staticLocation = $location } else {
        $default = [string]$map.regions.default
        if ($saved -and $saved.staticLocation) { $default = $saved.staticLocation }
        $staticLocation = Select-Option 'Region of the Static Web App (offered in a few only)' $staticLocations $default
    }

    Head 'Names (Enter = the value in brackets)'
    foreach ($def in @($defs | Where-Object { $_.ask -ne 'group' })) { $script:res[$def.key] = Read-Resource $def }
    foreach ($dm in @($map.domains)) {
        $default = '-'
        if ($envAbbr -eq 'prod' -and $dm.prodDefault) { $default = $dm.prodDefault }
        if ($saved -and $saved.($dm.answer)) { $default = $saved.($dm.answer) }
        $script:choices[$dm.answer] = (Ask $dm.label $default).ToLower()
    }
    # The apps' values per environment (the map's "values": an external API's address...).
    foreach ($mv in @($map.values | Where-Object { $_ })) {
        $default = ''
        if ($mv.default) { $default = [string]$mv.default }
        if ($saved -and $null -ne $saved.($mv.answer)) { $default = [string]$saved.($mv.answer) }
        $script:choices[$mv.answer] = Ask "$($mv.label) (for $envAbbr)" $default
    }
    # The sign-in in front of container apps: who may sign in here, and its app registration's client id.
    foreach ($def in @(Get-SignInDefs)) { if ($script:res[$def.key] -and $script:res[$def.key].Name) { Read-SignIn $def } }
    # GitHub Actions' app registration by its saved client id (step 2 saves it), kept with the answers.
    $deployKeyDef = $defs | Where-Object { $_.ask -eq 'name' -and $_.type -eq 'deploy' } | Select-Object -First 1
    if ($deployKeyDef) {
        $deployIdAnswer = Get-DeployClientIdAnswer ([string]$deployKeyDef.key)
        if ($saved -and $saved.$deployIdAnswer) { $script:choices[$deployIdAnswer] = [string]$saved.$deployIdAnswer }
    }

    Head 'GitHub'
    $haveGh = $ghExe -and (Test-Gh @('auth', 'status'))
    $remote = $null
    $r = Invoke-Native 'git' @('-C', $root, 'remote', 'get-url', 'origin')
    if ($r.Code -eq 0 -and $r.Text -match 'github\.com[:/](.+?)(\.git)?$') { $remote = $Matches[1] }
    while ($true) {
        $default = $remote
        if ($saved -and $saved.repo) { $default = $saved.repo }
        $repo = Ask 'Repository (owner/name)' $default
        if ($repo -notmatch '^[\w.-]+/[\w.-]+$') { Note 'X owner/name' }
        elseif ($haveGh -and -not (Test-Gh @('api', "repos/$repo"))) { Note "X $repo not found (or no access with the GitHub CLI's account)" }
        else { break }
    }
    $script:vals['repo'] = $repo
    # The branch that deploys to this environment on every push (the workflows find it with
    # infra/route.ps1); the GitHub environment then only accepts deployments from it.
    while ($true) {
        $default = '-'
        if ($envAbbr -eq 'prod') { $default = 'production' }
        if ($saved -and $saved.branch) { $default = $saved.branch }
        $branch = Ask "Branch that deploys to $ghEnv ('-' = manual runs only)" $default
        # Production deploys from its branch only: with manual runs any branch could deploy there, and on GitHub
        # plans without required reviewers the branch (protected below) is the environment's only gate.
        if ($branch -eq '-' -and $envAbbr -eq 'prod') { Note "X $ghEnv deploys from a branch only (e.g. production), not by manual runs of any branch"; if ($script:readOnly) { break }; continue }
        if ($branch -eq '-' -or -not $haveGh -or (Test-Gh @('api', "repos/$repo/branches/$([uri]::EscapeDataString($branch))"))) { break }
        # Copied from another environment: a start can make the branch from that environment's (the same code).
        $base = ''
        if ($script:fromCopy -and $script:copyBranch -and $script:copyBranch -ne $branch -and (Test-Gh @('api', "repos/$repo/branches/$([uri]::EscapeDataString($script:copyBranch))"))) { $base = $script:copyBranch }
        if ($base -and -not $script:readOnly) {
            if (Confirm-Step "$repo has no branch ${branch}: create it from $base (the code $base deploys)?") {
                $sha = (Invoke-Gh @('api', "repos/$repo/branches/$([uri]::EscapeDataString($base))") -Json).commit.sha
                Invoke-Gh @('api', '-X', 'POST', "repos/$repo/git/refs", '-f', "ref=refs/heads/$branch", '-f', "sha=$sha") | Out-Null
                Ok "branch $branch created from $base"
                break
            }
        }
        if ($base) { Note "X $repo has no branch $branch yet (a start offers to create it from $base; or '-')" }
        else { Note "X $repo has no branch $branch (create it first, or '-')" }
        if ($script:readOnly) { break }
    }
    if ($branch -eq '-') { Note "GitHub environment $ghEnv, manual runs only" } else { Note "GitHub environment $ghEnv, deployed from $branch" }

    # The answers are the next run's defaults (compared as data, so another PowerShell's JSON layout
    # doesn't count as a change).
    $names = [ordered]@{}
    $groups = [ordered]@{}
    foreach ($def in $defs) {
        $res = $script:res[$def.key]
        if ($res.Name -or -not $def.optional) { $names[$def.key] = $res.Name }
        if ($def.groupParam) { $groups[$def.key] = $res.Group }
    }
    # The estimate first: the monthly budget's default comes from it.
    Write-CostEstimate $location $staticLocation
    $budget = Read-Budget $saved $envAbbr
    $answers = [ordered]@{
        subscriptionId = $subscription
        location       = $location
        staticLocation = $staticLocation
        prefix         = $script:prefix
        subs           = $script:subs
        repo           = $repo
        branch         = $branch
        budget         = $budget.Amount
        budgetEmails   = $budget.Emails
    }
    foreach ($k in $script:choices.Keys) { $answers[$k] = $script:choices[$k] }
    $answers.names = $names
    $answers.groups = $groups
    $answers = Get-OrderedLike $answers $saved

    $newJson = ConvertTo-Json -InputObject $answers -Depth 10 -Compress
    $oldJson = ''
    if ($saved -and -not $script:fromCopy) { $oldJson = ConvertTo-Json -InputObject $saved -Depth 10 -Compress } # a copy is not saved yet
    if ($newJson -ne $oldJson) {
        if (Confirm-Step "Save these answers in infra/environments/$envAbbr.json?") {
            New-Item -ItemType Directory -Force -Path (Split-Path $envFile) | Out-Null
            [IO.File]::WriteAllText($envFile, (ConvertTo-Json -InputObject $answers -Depth 10) + "`n", $utf8)
            Note 'saved (commit it: the next run starts from it)'
            # The deploy workflows are triggered by the environments' branches: a new or changed one goes in.
            & (Join-Path $infra 'generate.ps1') -Check -Quiet
            if ($LASTEXITCODE -ne 0) {
                & (Join-Path $infra 'generate.ps1') -Quiet
                Note "the deploy workflows (.github/workflows) follow the environments' branches: regenerated, commit them too"
            }
            if ($script:ui) { Send ([ordered]@{ t = 'saved'; env = $envAbbr }) }
        }
    }
    $script:canGoBack = $false # changes start here
    if ($script:mode -ne 'check') { $script:auto = $false } # questions from here on (DNS) are asked again

    Head '1. Azure resources'
    # The map's providers, and those the Container Apps kinds and the apps' identities need when the map has them.
    $providers = @($map.providers | Where-Object { $_ })
    foreach ($d in $defs) {
        $ns = ([string]$d.armType).Split('/')[0]
        if ($usedProviders -contains $ns -and $providers -notcontains $ns) { $providers += $ns }
    }
    foreach ($ns in $providers) {
        if ((Invoke-Az @('provider', 'show', '-n', $ns, '--query', 'registrationState')) -eq 'Registered') { continue }
        if (Confirm-Step "Register the resource provider $ns (once per subscription)?") {
            Invoke-Az @('provider', 'register', '-n', $ns, '--wait') | Out-Null
            Ok "$ns registered"
        } else { Missing "resource provider $ns not registered" }
    }

    $haveRg = $rgExists
    if ($haveRg) { Ok "resource group $rgName ($location)" }
    elseif (Confirm-Step "Create the resource group $rgName in $($location)?") {
        Invoke-Az @('group', 'create', '-n', $rgName, '-l', $location, '--tags', "project=$project", "environment=$ghEnv") | Out-Null
        $haveRg = $true
        Ok "resource group $rgName created ($location)"
        Mark $rgDef.key $rgName 'created' ''
    } else { Missing "resource group $rgName" }

    $templatePending = $false
    $appDefs = @($defs | Where-Object { $appTypes -contains $_.armType })
    if ($haveRg) {
        foreach ($def in $appDefs) { if ($script:res[$def.key].Found) { $script:apps[$def.key] = Get-App $def.key } }
        # An app that still signs in as its system-assigned identity (connected by an import, or made by an older
        # map) gets its own identity from the template, which switches the app to it; Azure then deletes the old
        # identity and leaves its role assignments behind as "unknown". What the old one has is read now (while
        # it is known) and listed in the next steps, to remove by hand once the app works with its own.
        $script:oldIdentities = @(foreach ($def in @($appDefs | Where-Object { $_.identity })) {
                $app = $script:apps[$def.key]
                if (-not ($app -and $app.identity -and [string]$app.identity.type -match 'SystemAssigned' -and $app.identity.principalId)) { continue }
                [pscustomobject]@{ App = [string]$app.name; Identity = [string]$script:res[[string]$def.identity].Name; PrincipalId = [string]$app.identity.principalId; Assignments = @(Get-RoleAssignments ([string]$app.identity.principalId)) }
            })
        $changes = @()
        $later = @()

        # The secrets the setup keeps (the map's "by": "setup", e.g. a secret two apps share) keep their value:
        # the app setting that mirrors it (readable with the management rights the setup needs anyway), else
        # the vault's; a new one only when neither has it. It is written to the vault only when missing there
        # or different, since every write is a new version.
        $secretParams = [ordered]@{}
        foreach ($vdef in @($defs | Where-Object { $_.secrets })) {
            $vres = $script:res[$vdef.key]
            $vaultGroup = $rgName
            if ($vres.Group) { $vaultGroup = $vres.Group }
            $vaultId = "/subscriptions/$subscription/resourceGroups/$vaultGroup/providers/$($vdef.armType)/$($vres.Name)"
            if ($vres.Found) { $vaultId = $vres.Found.id }
            foreach ($sec in @($vdef.secrets | Where-Object { $_.by -eq 'setup' })) {
                if (-not (Test-SecretName ([string]$sec.name))) { Missing "$($vdef.key): secret name $($sec.name) refused (letters, digits and -, up to 127)"; continue }
                $inVault = [bool](Try-Az @('resource', 'show', '--ids', "$vaultId/secrets/$($sec.name)"))
                $fromVault = $null
                if ($inVault) { $fromVault = Try-Az @('keyvault', 'secret', 'show', '--vault-name', $vres.Name, '--name', $sec.name, '--query', 'value') }
                $fromMirror = $null
                if ($sec.mirror -and $script:res[$sec.mirror.resource].Found) { $fromMirror = (Get-AppSettings $sec.mirror.resource)[$sec.mirror.setting] }
                if ($fromMirror -and $fromMirror.StartsWith($secretRefMark)) { $fromMirror = $null } # a container app's secret reference, not a value
                $kept = $fromMirror
                if (-not $kept) { $kept = $fromVault }
                $writeSecret = (-not $inVault) -or (-not $kept) -or ($fromVault -and $fromVault -ne $kept)
                $secret = $kept
                if (-not $secret) { $secret = New-Secret }
                $script:secrets[$sec.name] = $secret
                $secretParams[$sec.param] = $secret
                $secretParams[$sec.writeParam] = [bool]$writeSecret
                if ($writeSecret -and $inVault) { $later += [pscustomobject]@{ changeType = 'Modify'; resourceId = "/providers/$($vdef.armType)/$($vres.Name)/secrets/$($sec.name)" } }
            }
        }
        $me = Try-Az @('ad', 'signed-in-user', 'show')
        $ownerId = ''
        if ($me) { $ownerId = $me.id }

        # main.bicep's parameters: the map's param / groupParam / size, the domains, the secrets.
        $params = [ordered]@{
            location        = $location
            staticLocation  = $staticLocation
            environmentName = $ghEnv
            project         = $project
        }
        foreach ($def in $defs) {
            $res = $script:res[$def.key]
            if ($def.param) { $params[$def.param] = $res.Name }
            if ($def.groupParam) { $params[$def.groupParam] = $res.Group }
            if ($def.size) { $params[$def.size.param] = $script:choices[$def.size.answer] }
            if ($def.admin) {
                $admin = ([string]$script:choices[$def.admin.answer]).Split('|')
                $type = 'User'
                if ($admin[0]) { $type = $admin[0] }
                $params[$def.admin.typeParam] = $type
                $params[$def.admin.loginParam] = [string]($admin | Select-Object -Skip 1 -First 1)
                $params[$def.admin.sidParam] = [string]($admin | Select-Object -Skip 2 -First 1)
            }
        }
        foreach ($dm in @($map.domains | Where-Object { $_.param })) {
            $value = [string]$script:choices[$dm.answer]
            if ($value -eq '-') { $value = '' }
            $params[$dm.param] = $value
        }
        foreach ($mv in @($map.values | Where-Object { $_ -and $_.param })) { $params[$mv.param] = [string]$script:choices[$mv.answer] }
        # Container apps: the image Azure runs now ('' = the placeholder: a new app, or one still on it), so the template
        # never changes it; a first image comes in the step "First image" (after the sign-in and GitHub). The saved
        # sign-in client id, always ('' = no authConfigs and the placeholder stays: fail-closed; the step "Sign-in app
        # registrations" makes the app registration, then main.bicep runs again).
        $imageUnknown = @()
        $signInPassed = @{}
        foreach ($def in @($defs | Where-Object { $_.armType -eq $containerAppType })) {
            $cname = [string]$script:res[$def.key].Name
            if (-not $cname) { continue }
            $clientId = ''
            if (Test-SignInOn $def) {
                $clientId = [string]$script:choices[(Get-SignInClientIdAnswer $def.key)]
                $params["$($def.key)SignInClientId"] = $clientId
                $signInPassed[$def.key] = $clientId
                if (-not $clientId) { Note "${cname}: no sign-in yet (its app registration comes after step 1; then main.bicep runs again)" }
            }
            $image = Get-ImageParam $def.key
            # The sign-in's paths: never the whole app without sign-in (infra/generate.ps1 refuses it too).
            $pathProblem = ''
            if (Test-SignInOn $def) { $pathProblem = Get-SignInPathProblem $def }
            if ($pathProblem) {
                $imageUnknown += $cname
                Missing "${cname}: $pathProblem - the template isn't deployed"
            }
            if ($null -eq $image) {
                $imageUnknown += $cname
                Missing "${cname}: its image can't be read (az containerapp show): the template isn't deployed, it would put the placeholder back"
                $image = ''
            } elseif ($image -and (Test-SignInUnknown $def)) {
                # Its own image runs, but no sign-in registration is known (none saved, none in Azure's sign-in, none
                # yours alone by its name): the template would go out without the sign-in in front of it.
                $imageUnknown += $cname
                Missing "${cname}: the app runs its image but its sign-in registration is unknown - set $(Get-SignInClientIdAnswer $def.key) in infra/environments/$envAbbr.json (the template isn't deployed)"
            } elseif ($image) { Note "${cname}: image $image (kept; the app's workflow deploys a new one)" }
            else { Note "${cname}: image $placeholderImage (placeholder; its first image comes in the step First image)" }
            $params["$($def.key)Image"] = $image
        }
        # What waits for an app's code (an Event Grid subscription: Azure checks its function): made once the
        # function is there, so the first start (before the app's deploy) leaves it for the next one.
        foreach ($def in @($defs | Where-Object { $_.ready -and $_.ready.param })) {
            $appKey = [string]$def.ready.app
            $appName = ''
            if ($script:res[$appKey]) { $appName = [string]$script:res[$appKey].Name }
            $ready = $false
            if ($appName) { $ready = [bool](Try-Az @('functionapp', 'function', 'show', '-g', $rgName, '-n', $appName, '--function-name', [string]$def.ready.function)) }
            $params[[string]$def.ready.param] = $ready
            if (-not $ready -and -not $script:readyNoted[$def.key]) {
                $script:readyNoted[$def.key] = $true
                Missing "$($def.title): made once $appName has its function $($def.ready.function) (deploy the app's code, then run a start again)"
            }
        }
        $params.ownerObjectId = $ownerId
        foreach ($k in $secretParams.Keys) { $params[$k] = $secretParams[$k] }
        $parameters = [ordered]@{}
        # Only what main.bicep declares (a project without a Static Web App or a vault has no staticLocation or
        # ownerObjectId; Azure refuses parameters a template doesn't have).
        $declared = @([regex]::Matches((Get-Content (Join-Path $infra $map.project.template) -Raw), '(?m)^param\s+(\w+)') | ForEach-Object { $_.Groups[1].Value })
        foreach ($k in $params.Keys) { if ($declared -contains $k) { $parameters[$k] = @{ value = $params[$k] } } }
        $paramsFile = Write-TempJson 'parameters.json' ([ordered]@{
                '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
                contentVersion = '1.0.0.0'
                parameters     = $parameters
            })
        $deploymentName = ([string]$map.project.deploymentName).Replace('{env}', $envAbbr)
        $deployment = @('-g', $rgName, '-n', $deploymentName, '-f', (Join-Path $infra $map.project.template), '-p', "@$paramsFile")
        # main.bicep is made from the map (infra/generate.ps1): an older one would deploy something else.
        & (Join-Path $infra 'generate.ps1') -Check -Quiet
        if ($LASTEXITCODE -ne 0) { Missing "infra/$($map.project.template) or the deploy workflows aren't what infra.map.json makes: run .\infra\generate.ps1 first" }
        Note "comparing Azure with the template (what-if)..."
        $whatIf = Invoke-Az (@('deployment', 'group', 'what-if') + $deployment + @('--no-pretty-print'))
        $changes = @($whatIf.changes | Where-Object { Test-RealChange $_ })
        # The app settings what-if can't read: checked directly against the map's "appSettings" (every
        # setting there; the values the map expects where they are known here).
        foreach ($def in @($defs | Where-Object { $_.appSettings })) {
            if (-not $script:res[$def.key].Found) { continue }
            if (@('Microsoft.Web/sites', $containerAppType) -contains [string]$def.armType -and -not $script:apps[$def.key]) { continue }
            $have = Get-AppSettings $def.key
            $wrong = @()
            foreach ($s in @(Get-ExpectedSettings $def)) {
                $value = $have[$s.name]
                # A container app's Key Vault secret is a secret reference: there by name, its value never read.
                if ($def.armType -eq $containerAppType -and $value -and $value.StartsWith($secretRefMark)) { continue }
                # value: the whole setting; prefix: how it starts (never $s.equals: that is the object's method)
                $expect = [string]$s.value
                if (-not $expect) { $expect = [string]$s.prefix }
                if (-not $expect) { if (-not $value) { $wrong += $s.name }; continue }
                $expected = Expand $expect
                if ($null -eq $expected) { if ($s.unknown -eq 'wrong' -or -not $value) { $wrong += $s.name }; continue }
                if ($s.value -and $value -ne $expected) { $wrong += $s.name }
                elseif ($s.prefix -and (-not $value -or -not $value.StartsWith($expected, [StringComparison]::OrdinalIgnoreCase))) { $wrong += $s.name }
            }
            $wrong = @($wrong | Select-Object -Unique)
            if ($wrong.Count) { $changes += [pscustomobject]@{ changeType = 'Modify'; resourceId = "/providers/$($def.armType)/$($script:res[$def.key].Name)/config/appsettings ($($wrong -join ', '))" } }
        }
        $changes += $later
        if (-not $changes.Count) { Ok "resources match infra/$($map.project.template)" }
        else {
            foreach ($c in $changes) { Note ("{0,-8} {1}" -f $c.changeType, ($c.resourceId -split '/providers/')[-1]) }
            # The custom domains need DNS records pointing to what this creates: the instructions now, so
            # they can be added while it deploys (step 4 checks them and adds the domains).
            if (@($map.domains | Where-Object { $script:choices[$_.answer] -ne '-' -and -not $script:res[$_.resource].Found }).Count) {
                Write-DnsInstructions 'DNS for the custom domains (add it once these are created; the rest of the values follow after the deployment):' (Get-DnsRecords)
            }
            $plural = ''
            if ($changes.Count -gt 1) { $plural = 's' }
            if ($imageUnknown.Count) { Missing "infra/$($map.project.template) not deployed: $((@($imageUnknown | Select-Object -Unique)) -join ', ') (above: an image that can't be read, a sign-in registration that is unknown, or a sign-in path)"; $templatePending = $true }
            elseif (Confirm-Step "Deploy infra/$($map.project.template) ($($changes.Count) change$plural, a few minutes)?") {
                Invoke-Az (@('deployment', 'group', 'create') + $deployment) | Out-Null
                Ok "infra/$($map.project.template) deployed"
                foreach ($def in $defs) { $res = $script:res[$def.key]; if ($res.Name -and -not $res.Group -and -not $res.Found -and $def.ask -ne 'name' -and $def.ask -ne 'group') { Mark $def.key $res.Name 'created' '' } }
            } else { Missing "resources differ from the template ($($changes.Count) changes)"; $templatePending = $true }
        }
        foreach ($def in $appDefs) { $script:apps[$def.key] = Get-App $def.key }
        # The apps' identities: one owner each, no one else may attach them (reported only).
        Test-AppIdentities
        # Just created: now every value is known.
        if ($changes.Count -and @($map.domains | Where-Object { $script:choices[$_.answer] -ne '-' -and -not $script:res[$_.resource].Found -and $script:apps[$_.resource] }).Count) {
            Write-DnsInstructions 'DNS for the custom domains, all values (step 4 checks it and adds the domains):' (Get-DnsRecords)
        }
        # Container apps: the Key Vault secrets they reference (names only; the next steps say how to put them in).
        foreach ($def in @($appDefs | Where-Object { $_.armType -eq $containerAppType })) {
            $lack = @(Test-ContainerAppSecrets $def.key)
            if ($lack.Count) { $script:lackingSecrets[$def.key] = $lack }
        }
    }

    # The sign-in in front of container apps: the app registration once the app (and its address) exists, then
    # main.bicep again when its client id is new, so the sign-in (authConfigs) is there before the app's workflow
    # deploys its real image - all in this start.
    $signInDefs = @(Get-SignInDefs | Where-Object { $script:res[$_.key] -and $script:res[$_.key].Name })
    if ($signInDefs.Count) {
        Head 'Sign-in app registrations'
        $redeploy = @()
        foreach ($def in $signInDefs) {
            $idAnswer = Get-SignInClientIdAnswer $def.key
            $clientId = [string](@(Set-SignInApp $def) | Select-Object -Last 1)
            if ($clientId -and $clientId -ne [string]$script:choices[$idAnswer]) { $script:choices[$idAnswer] = $clientId }
            # Saved with its object id: the next run uses them, never a registration found by its name.
            if ($clientId) {
                Save-EnvAnswer $envFile $idAnswer $clientId
                $objAnswer = Get-SignInObjectIdAnswer $def.key
                if ($script:choices[$objAnswer]) { Save-EnvAnswer $envFile $objAnswer ([string]$script:choices[$objAnswer]) }
            }
            if ($clientId -and $signInPassed -and $signInPassed.ContainsKey($def.key) -and [string]$signInPassed[$def.key] -ne $clientId) { $redeploy += $def }
        }
        if ($redeploy.Count) {
            $signInNames = (@($redeploy | ForEach-Object { $script:res[$_.key].Name })) -join ', '
            if ($script:readOnly -or -not $paramsFile) { Missing "sign-in of ${signInNames}: main.bicep runs again with its client id (authConfigs; a start does it)" }
            else {
                $values = @{}
                foreach ($def in $redeploy) { $values["$($def.key)SignInClientId"] = [string]$script:choices[(Get-SignInClientIdAnswer $def.key)] }
                if ($imageUnknown.Count) { Missing "sign-in of ${signInNames}: not deployed (held back above: $((@($imageUnknown | Select-Object -Unique)) -join ', '))"; $templatePending = $true }
                elseif (Invoke-TemplateAgain $parameters $values $deployment $declared "Deploy infra/$($map.project.template) again so the sign-in is in front of $signInNames (a minute)?") {
                    Ok "infra/$($map.project.template) deployed: sign-in in front of $signInNames"
                    foreach ($def in $redeploy) { $script:apps[$def.key] = Get-App $def.key }
                } else { Missing "sign-in of ${signInNames}: not in front of the app yet (run a start again)"; $templatePending = $true }
            }
        }
        foreach ($def in $signInDefs) { Test-SignInLive $def ([string]$script:choices[(Get-SignInClientIdAnswer $def.key)]) }
    }

    # The apps' database users (the map's "sql" connections).
    $sqlLinks = @($map.connections | Where-Object { $_.kind -eq 'sql' })
    if ($sqlLinks.Count) {
        Head 'Database access'
        try { foreach ($c in $sqlLinks) { Grant-DatabaseUser $c } } finally { Close-SqlFirewall }
    }

    Head 'Budget'
    Set-Budget $budget $subscription $rgName $ghEnv

    Head '2. GitHub -> Azure trust (OIDC)'
    $deployDef = $defs | Where-Object { $_.ask -eq 'name' -and $_.type -eq 'deploy' } | Select-Object -First 1
    $deployApp = $script:res[$deployDef.key].Name
    # By its saved client id; by its name only when none is saved and you alone own it (Resolve-EntraApp): whoever
    # owns the registration GitHub Actions signs in as controls what it may change in Azure.
    $deployIdAnswer = Get-DeployClientIdAnswer ([string]$deployDef.key)
    $deployFound = Resolve-EntraApp $deployApp ([string]$script:choices[$deployIdAnswer]) $deployIdAnswer
    $entra = $deployFound.App
    if ($deployFound.Note) { Note $deployFound.Note }
    if ($deployFound.Problem) { Missing "app registration ${deployApp}: $($deployFound.Problem)"; Mark $deployDef.key $deployApp 'new' '' }
    elseif ($entra) {
        Ok "app registration $deployApp ($($entra.appId)$(if ($deployFound.Source -eq 'name') { ', by its name: you alone own it' }))"
        Mark $deployDef.key $deployApp 'ours' ''
        if ($deployFound.Source -eq 'id') {
            $owners = Get-EntraOwners 'app' ([string]$entra.appId)
            if (-not (Test-OwnedByOperator $owners)) { Missing "app registration ${deployApp}: owners $(Get-OwnersText $owners) (only you should own it)" }
        }
    } elseif (-not (Get-OperatorId)) { Missing "app registration ${deployApp}: made only by a signed-in user (az ad signed-in-user show), its owner"; Mark $deployDef.key $deployApp 'new' '' }
    elseif (Confirm-Step "Create the app registration $deployApp (GitHub Actions signs in as it; you its only owner)?") {
        $entra = Invoke-Az @('ad', 'app', 'create', '--display-name', $deployApp)
        if (-not (Test-OwnedByOperator (Get-EntraOwners 'app' ([string]$entra.appId)))) { Invoke-Az @('ad', 'app', 'owner', 'add', '--id', [string]$entra.appId, '--owner-object-id', (Get-OperatorId)) | Out-Null }
        Ok "app registration $deployApp created ($($entra.appId))"
        Mark $deployDef.key $deployApp 'created' ''
    } else { Missing "app registration $deployApp"; Mark $deployDef.key $deployApp 'new' '' }
    if ($entra) {
        $script:vals["$($deployDef.key).appId"] = $entra.appId
        $script:choices[$deployIdAnswer] = [string]$entra.appId
        Save-EnvAnswer $envFile $deployIdAnswer ([string]$entra.appId)
    }

    $principal = $null
    $deployRefused = $false
    if ($entra) {
        $gate = Get-DeployPrincipal $entra $deployApp
        $principal = $gate.Principal
        $deployRefused = $gate.Refused

        # The subject GitHub puts in its token: with immutable ids ('repo:owner@123/name@456:...') when the
        # repository uses them (seen on the first deploy: AADSTS700213 with the name-only one), else
        # 'repo:owner/name:...'. GitHub reports its prefix; both forms are trusted, so either works.
        $subjects = @("repo:${repo}:environment:$ghEnv")
        $oidc = $null
        if ($haveGh) {
            $oidc = Try-Gh @('api', "repos/$repo/actions/oidc/customization/sub") -Json
            if ($oidc -and $oidc.sub_claim_prefix -and "$($oidc.sub_claim_prefix):environment:$ghEnv" -ne $subjects[0]) { $subjects += "$($oidc.sub_claim_prefix):environment:$ghEnv" }
        } else { Note "without the GitHub CLI only the name-based subject is known; if the deploy's Azure login fails with AADSTS700213, add the subject it names here" }
        # Trust it has besides GitHub Actions of this repository's environments (the map's, both subject forms):
        # reported, never removed here; a client secret or certificate noted (the deploy signs in with OIDC).
        $ourSubjects = @(foreach ($e in @($naming.environments.PSObject.Properties | ForEach-Object { [string]$_.Value } | Where-Object { $_ })) {
                "repo:${repo}:environment:$e"
                if ($oidc -and $oidc.sub_claim_prefix) { "$($oidc.sub_claim_prefix):environment:$e" }
            })
        $foreign = Get-ForeignCredentials $entra $ourSubjects
        if ($null -eq $foreign) { Missing "${deployApp}: its federated credentials are not readable (az ad app federated-credential list --id $($entra.appId))" }
        foreach ($fc in @($foreign)) {
            if ($fc.Kind -eq 'federated') { Missing "${deployApp}: a $($fc.Text) - not GitHub Actions of $repo in this map's environments" }
            else { Note "${deployApp}: has a $($fc.Text) (the deploy signs in with OIDC: is it still needed?)" }
        }
        $existing = @(Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $entra.appId)) | Where-Object { $_ }
        for ($i = 0; $i -lt $subjects.Count; $i++) {
            $subject = $subjects[$i]
            $credentialName = "github-$ghEnv"
            if ($i -gt 0) { $credentialName = "github-$ghEnv-ids" }
            if (@($existing | Where-Object { $_.subject -eq $subject }).Count) { Ok "federated credential $subject" }
            elseif (Confirm-Step "Trust GitHub Actions of $repo, environment $ghEnv ($subject)?") {
                $credential = Write-TempJson 'credential.json' ([ordered]@{ name = $credentialName; issuer = 'https://token.actions.githubusercontent.com'; subject = $subject; audiences = @('api://AzureADTokenExchange') })
                Invoke-Az @('ad', 'app', 'federated-credential', 'create', '--id', $entra.appId, '--parameters', "@$credential") | Out-Null
                Ok "federated credential $subject created"
            } else { Missing "federated credential $subject" }
        }
    }

    # The role GitHub Actions' app registration needs on each app it deploys (the map's deployRoles).
    # An app (App Service, Container App: Website Contributor, Container Apps Contributor) or what it deploys into
    # (a container registry: AcrPush), each at its own scope only.
    foreach ($deployRole in @($map.github.deployRoles | Where-Object { $_ })) {
        $roleTargetId = Get-ResourceId ([string]$deployRole.resource)
        $roleTargetName = $script:res[$deployRole.resource].Name
        if (-not ($principal -and $roleTargetId)) { continue }
        $role = [string]$deployRole.role
        if (@(Invoke-Az @('role', 'assignment', 'list', '--assignee', $principal.id, '--scope', $roleTargetId, '--role', $role)) | Where-Object { $_ }) { Ok "$role on $roleTargetName" }
        elseif (Confirm-Step "Let $deployApp deploy to $roleTargetName ($role)?") {
            Invoke-Az @('role', 'assignment', 'create', '--assignee-object-id', $principal.id, '--assignee-principal-type', 'ServicePrincipal', '--role', $role, '--scope', $roleTargetId) | Out-Null
            Ok "$role on $roleTargetName assigned"
        } else { Missing "$role on $roleTargetName" }
    }

    # The deploys that run migrations: the app registration's database user (it changes the schema).
    $migrating = @(Get-MigratingDeploys)
    if ($migrating.Count -and $entra -and -not $deployRefused) {
        try { foreach ($dbKey in @($migrating | ForEach-Object { $_.Database } | Select-Object -Unique)) { Grant-DeployDatabaseUser $dbKey $deployApp $entra.appId } }
        finally { Close-SqlFirewall }
    }
    # The bundle runs on GitHub's runner (in Azure): a server shared from another group (or imported) doesn't
    # get main.bicep's AllowAllWindowsAzureIps rule, so it is checked here.
    foreach ($serverKey in @($migrating | ForEach-Object { $_.Server } | Select-Object -Unique)) {
        $sres = $script:res[$serverKey]
        if (-not $sres -or -not $sres.Name -or -not $sres.Group) { continue }
        $rule = Try-Az @('sql', 'server', 'firewall-rule', 'list', '-g', $sres.Group, '-s', $sres.Name)
        if (@($rule | Where-Object { $_ -and $_.startIpAddress -eq '0.0.0.0' -and $_.endIpAddress -eq '0.0.0.0' }).Count) { Ok "$($sres.Name) lets Azure services through (the migrations from GitHub's runners)" }
        else { Missing "$($sres.Name) (shared from $($sres.Group)) doesn't let Azure services through: the migrations from GitHub's runners can't reach it (az sql server firewall-rule create -g $($sres.Group) -s $($sres.Name) -n AllowAllWindowsAzureIps --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0)" }
    }

    Head "3. GitHub environment $ghEnv"
    $vars = [ordered]@{}
    foreach ($p in $map.github.variables.PSObject.Properties) { $vars[$p.Name] = Expand $p.Value }
    # The connection string each migrating deploy uses (an environment secret of the same name wins in the workflow).
    foreach ($md in $migrating) { $vars[$md.Variable] = Expand $md.Connection }
    # Each Static Web App's deployment token, as a secret of the GitHub environment (the map's tokenSecrets).
    $tokens = @(foreach ($t in @($map.github.tokenSecrets)) {
            $app = $script:res[$t.resource]
            $value = $null
            if ($script:apps[$t.resource]) {
                $secrets = Try-Az @('staticwebapp', 'secrets', 'list', '-g', $rgName, '-n', $app.Name)
                if ($secrets) { $value = $secrets.properties.apiKey }
            }
            [pscustomobject]@{ Name = [string]$t.name; App = $app.Name; Existed = [bool]$app.Found; Token = $value }
        })
    if ($haveGh) {
        $haveEnv = Test-Gh @('api', "repos/$repo/environments/$ghEnv")
        if ($haveEnv) { Ok "environment $ghEnv" }
        elseif (Confirm-Step "Create the GitHub environment ${ghEnv}?") {
            Invoke-Gh @('api', '-X', 'PUT', "repos/$repo/environments/$ghEnv") | Out-Null
            $haveEnv = $true
            Ok "environment $ghEnv created"
        } else { Missing "GitHub environment $ghEnv" }
        if ($haveEnv) {
            # Deployment branches: only the environment's branch, or any branch for manual-only environments.
            $envInfo = Try-Gh @('api', "repos/$repo/environments/$ghEnv") -Json
            $policyList = Try-Gh @('api', "repos/$repo/environments/$ghEnv/deployment-branch-policies") -Json
            $policies = @()
            if ($policyList) { $policies = @($policyList.branch_policies | Where-Object { $_ }) }
            $policyNames = @($policies | ForEach-Object { $_.name })
            $custom = $envInfo -and $envInfo.deployment_branch_policy -and $envInfo.deployment_branch_policy.custom_branch_policies
            if ($branch -eq '-') {
                if (-not ($envInfo -and $envInfo.deployment_branch_policy)) { Ok "${ghEnv}: any branch can deploy (manual runs)" }
                elseif (Confirm-Step "Let any branch deploy to $ghEnv (now: $($policyNames -join ', '))?") {
                    Invoke-Gh @('api', '-X', 'PUT', "repos/$repo/environments/$ghEnv", '--input', (Write-TempJson 'env.json' @{ deployment_branch_policy = $null })) | Out-Null
                    Ok "${ghEnv}: any branch can deploy"
                } else { Missing "${ghEnv}: deployment branches" }
            } elseif ($custom -and $policyNames.Count -eq 1 -and $policyNames[0] -eq $branch) { Ok "${ghEnv}: deployed only from $branch" }
            elseif (Confirm-Step "Allow only $branch to deploy to $ghEnv$(if ($policyNames.Count) { " (now: $($policyNames -join ', '))" })?") {
                Invoke-Gh @('api', '-X', 'PUT', "repos/$repo/environments/$ghEnv", '--input', (Write-TempJson 'env.json' @{ deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true } })) | Out-Null
                foreach ($p in $policies) { if ($p.name -ne $branch) { Invoke-Gh @('api', '-X', 'DELETE', "repos/$repo/environments/$ghEnv/deployment-branch-policies/$($p.id)") | Out-Null } }
                if ($policyNames -notcontains $branch) { Invoke-Gh @('api', '-X', 'POST', "repos/$repo/environments/$ghEnv/deployment-branch-policies", '-f', "name=$branch", '-f', 'type=branch') | Out-Null }
                Ok "${ghEnv}: deployed only from $branch"
            } else { Missing "${ghEnv}: deployment branch $branch" }

            # The deploy branch itself: changed only through a reviewed pull request, no force-push, no
            # deletion (a repository ruleset, or classic branch protection made by hand). Without it, anyone who
            # can push could push to it and deploy their code and migrations.
            if ($branch -ne '-') {
                $rules = @(Try-Gh @('api', "repos/$repo/rules/branches/$([uri]::EscapeDataString($branch))") -Json | Where-Object { $_ })
                $classic = Test-Gh @('api', "repos/$repo/branches/$([uri]::EscapeDataString($branch))/protection")
                if ($classic -or @($rules | Where-Object { $_.type -eq 'pull_request' }).Count) { Ok "${branch}: protected (changes through pull requests)" }
                elseif (Confirm-Step "Protect $branch with a ruleset (a reviewed pull request for every change, no force-push or deletion; the repository's admins may bypass it)?" -DefaultNo:($envAbbr -ne 'prod')) {
                    $ruleset = [ordered]@{
                        name        = "deploy branch $branch"
                        target      = 'branch'
                        enforcement = 'active'
                        conditions  = @{ ref_name = @{ include = @("refs/heads/$branch"); exclude = @() } }
                        # The admins (role 5) may bypass it: a team of one can still merge its own pull requests.
                        bypass_actors = @(@{ actor_id = 5; actor_type = 'RepositoryRole'; bypass_mode = 'always' })
                        rules       = @(
                            @{ type = 'deletion' },
                            @{ type = 'non_fast_forward' },
                            @{ type = 'pull_request'; parameters = [ordered]@{ required_approving_review_count = 1; dismiss_stale_reviews_on_push = $true; require_code_owner_review = $false; require_last_push_approval = $true; required_review_thread_resolution = $false } }
                        )
                    }
                    # GitHub may refuse it (rulesets of a private repository need a paid plan): reported, the run goes on.
                    try {
                        Invoke-Gh @('api', '-X', 'POST', "repos/$repo/rulesets", '--input', (Write-TempJson 'ruleset.json' $ruleset)) | Out-Null
                        Ok "${branch}: protected by the ruleset 'deploy branch $branch'"
                    } catch { Missing "${branch}: GitHub refused the ruleset ($($_.Exception.Message)); protect it by hand (Settings -> Rules)" }
                } else { Missing "${branch}: not protected (anyone who can push to it deploys to $ghEnv)" }
            }

            $have = @{}
            foreach ($v in @(Try-Gh @('variable', 'list', '--repo', $repo, '--env', $ghEnv, '--json', 'name,value') -Json)) { if ($v) { $have[$v.name] = $v.value } }
            foreach ($name in $vars.Keys) {
                $value = $vars[$name]
                if (-not $value) { Missing "${name}: no value yet" }
                elseif ($have[$name] -eq $value) { Ok "$name = $value" }
                elseif (Confirm-Step "Set $name = $value$(if ($have[$name]) { " (now $($have[$name]))" })?") {
                    Invoke-Gh @('variable', 'set', $name, '--repo', $repo, '--env', $ghEnv, '--body', $value) | Out-Null
                    Ok "$name = $value set"
                } else { Missing $name }
            }

            # A secret can't be read back: set when missing or when the web app is new (a new token), else
            # kept (-RefreshToken sets it again, e.g. after resetting the token in the portal).
            $envSecrets = @(Try-Gh @('secret', 'list', '--repo', $repo, '--env', $ghEnv, '--json', 'name') -Json)
            foreach ($t in $tokens) {
                $present = [bool](@($envSecrets | Where-Object { $_ -and $_.name -eq $t.Name }).Count)
                if (-not $t.Token) { Missing "$($t.Name): the static web app comes first" }
                elseif ($present -and $t.Existed -and -not $RefreshToken) { Ok "$($t.Name) (present)" }
                else {
                    $verb = 'Set'
                    if ($present) { $verb = 'Replace' }
                    $why = ''
                    if ($present -and -not $t.Existed) { $why = ' (the Static Web App is new)' }
                    if (Confirm-Step "$verb $($t.Name) from $($t.App)$($why)?") {
                        Invoke-Gh @('secret', 'set', $t.Name, '--repo', $repo, '--env', $ghEnv, '--body', $t.Token) | Out-Null
                        Ok "$($t.Name) set"
                    } else { Missing $t.Name }
                }
            }
        }
    } else {
        Note 'The GitHub CLI is not installed or not signed in (winget install GitHub.cli, gh auth login, then run'
        Note "this again to set and check them), so by hand: an environment named $ghEnv"
        Note "(https://github.com/$repo/settings/environments) with these variables:"
        foreach ($name in $vars.Keys) {
            $value = $vars[$name]
            if (-not $value) { $value = '(after step 2)' }
            Note ("  {0,-22} {1}" -f $name, $value)
        }
        if ($branch -ne '-') { Note "deployment branches: selected branches, only $branch" }
        foreach ($t in $tokens) {
            if ($t.Token) { Note "and the secret $($t.Name) = az staticwebapp secrets list -g $rgName -n $($t.App) --query properties.apiKey" }
            else { Note "and the secret $($t.Name) (after step 1)" }
        }
        Missing "GitHub environment $ghEnv not checked (no GitHub CLI)"
    }

    # A container app still on the placeholder gets its first image here, in this start: after its sign-in (step
    # "Sign-in app registrations") and GitHub (its workflow signs in with the trust and the environment's variables).
    # Its workflow runs with push-only, then main.bicep deploys the pushed image with the app's settings, secrets and
    # probes; every later run of the workflow changes the image by itself.
    $firstDefs = @($defs | Where-Object { $_.armType -eq $containerAppType -and $_.deploy -and $_.deploy.workflow -and $script:apps[$_.key] -and (Test-PlaceholderImage (Get-AppImage $script:apps[$_.key])) })
    if ($firstDefs.Count) {
        Head 'First image (container apps)'
        foreach ($def in $firstDefs) {
            $cname = [string]$script:res[$def.key].Name
            $wf = [string]$def.deploy.workflow
            $clientId = [string]$script:choices[(Get-SignInClientIdAnswer $def.key)]
            if ((Test-SignInOn $def) -and -not (Test-SignInReady $def $clientId)) { Missing "${cname}: its first image waits for the sign-in in front of it (above)"; continue }
            $lack = @(Get-MissingMapSecrets $def)
            if ($lack.Count) {
                $script:lackingSecrets[$def.key] = $lack
                Missing "${cname}: its first image waits for its Key Vault secrets ($((@($lack | ForEach-Object { "$($_.Vault)/$($_.Secret)" })) -join ', '); the next steps say how)"
                continue
            }
            if ($script:readOnly) { Missing "${cname}: still the placeholder (a start runs $wf with push-only and deploys its image)"; continue }
            if (-not $haveGh -or -not $paramsFile -or $imageUnknown.Count) { Missing "${cname}: still the placeholder (run $wf with push-only, then start again)"; continue }
            if (-not (Confirm-Step "Give $cname its first image: run $wf with push-only on $(if ($branch -ne '-') { $branch } else { 'the default branch' }) (a few minutes), then deploy it with main.bicep?")) { Missing "${cname}: still the placeholder"; continue }
            $image = Invoke-FirstImageBuild $def $repo $branch $ghEnv
            if (-not $image) { continue }
            # Checked again right before the deploy (the build took minutes): the real image brings its secret references.
            $lack = @(Get-MissingMapSecrets $def)
            if ($lack.Count) {
                $script:lackingSecrets[$def.key] = $lack
                Missing "${cname}: $image is pushed, not deployed: its Key Vault secrets are missing ($((@($lack | ForEach-Object { "$($_.Vault)/$($_.Secret)" })) -join ', ')); put them in, then start again"
                continue
            }
            if (Invoke-TemplateAgain $parameters @{ "$($def.key)Image" = $image } $deployment $declared "Deploy infra/$($map.project.template) with $image for $cname (its first image, with its settings)?") {
                Ok "${cname}: first image $image deployed"
                $script:apps[$def.key] = Get-App $def.key
            } else { Missing "${cname}: still the placeholder ($image is pushed: start again)"; $templatePending = $true }
        }
    }

    Head '4. Custom domains'
    $script:domainReady = @{}
    $script:domainsToAdd = $false # DNS is there, the domain not added yet (a dry run or check doesn't add it)
    foreach ($dm in @($map.domains)) {
        $domain = [string]$script:choices[$dm.answer]
        if ($domain -eq '-') { Note "$($dm.what): none"; continue }
        if ($dm.dns -eq 'staticWebApp') { Add-StaticDomain $dm $domain }
        elseif ($dm.dns -eq 'appService') { Add-AppServiceDomain $dm $domain }
    }

    Head '5. Live'
    $allLive = $true
    # Container apps start with the placeholder: their own image comes with their workflow.
    $placeholderApps = @()
    foreach ($def in @($defs | Where-Object { $_.armType -eq $containerAppType })) {
        $app = $script:apps[$def.key]
        if (-not $app) { continue }
        $cname = [string]$script:res[$def.key].Name
        $image = Get-AppImage $app
        $workflow = 'its deploy workflow'
        if ($def.deploy -and $def.deploy.workflow) { $workflow = ".github/workflows/$($def.deploy.workflow)" }
        if (Test-PlaceholderImage $image) {
            Missing "$cname still runs the placeholder image: a start gives it its first image (step First image), or run $workflow with push-only (environment $ghEnv), then start again"
            $placeholderApps += $def
        } else { Ok "$cname runs $image" }
    }
    foreach ($lv in @($map.live)) {
        $app = $script:apps[$lv.resource]
        $live = $false
        if (-not $app) { Missing "$($lv.what): not created yet"; $allLive = $false; continue }
        $bases = @("https://$(Get-AppHost $app)")
        if ($lv.domain -and $script:domainReady[$lv.domain]) { $bases += "https://$($script:choices[$lv.domain])" }
        foreach ($base in $bases) {
            if ($lv.kind -eq 'health') {
                $health = Get-Url "$base$($lv.path)"
                $version = ''
                if ($lv.version) {
                    $version = (Get-Url "$base$($lv.version)").Text
                    try { $v = ($version | ConvertFrom-Json).version; if ($v) { $version = $v } } catch { }
                }
                if ($health.Text.Trim() -eq $lv.expect) { Ok "${base}: $($lv.expect), $version"; $live = $true }
                else {
                    $text = $health.Text
                    if ($text.Length -gt 60) { $text = $text.Substring(0, 60) }
                    Missing "$base$($lv.path): $($health.Status) $text (not deployed yet? $($lv.workflow), environment $ghEnv)"
                }
            } else {
                $page = Get-Url "$base$($lv.path)"
                if ($page.Status -eq 200 -and $page.Text -match $lv.match) { Ok "${base}: the $($lv.what)"; $live = $true }
                elseif ($page.Status -eq 200) { Missing "${base}: the Azure placeholder (not deployed yet? $($lv.workflow))" }
                else { Missing "${base}: $($page.Status) $($page.Text)" }
            }
        }
        if (-not $live) { $allLive = $false }
    }

    # Everything still to do by hand, step by step: where, and what. Only the steps that apply now.
    $steps = New-Object System.Collections.ArrayList
    function Add-Step([string]$Title, [string]$Where, [string[]]$What) { [void]$steps.Add([ordered]@{ title = $Title; where = $Where; what = @($What) }) }
    $created = -not @($appDefs | Where-Object { -not $script:apps[$_.key] }).Count
    if (-not $created) {
        $how = 'Run this again and choose 3. Start'
        if ($script:mode -eq 'start') { $how = 'Run this again and say yes to the deployment' }
        Add-Step 'Create the resources' 'this PowerShell window (repository root)' @("$how`: .\infra\azure-setup.ps1 -Start -Environment $envAbbr; the steps below follow.")
    } elseif ($templatePending) {
        Add-Step 'Apply the template changes' 'this PowerShell window (repository root)' @(
            ".\infra\azure-setup.ps1 -Start -Environment $envAbbr, keep the saved answers, and say yes to the deployment",
            '(step 1 lists what changes).')
    }
    $answersChanged = (Invoke-Native 'git' @('-C', $root, 'status', '--porcelain', '--', "infra/environments/$envAbbr.json")).Text
    if ($answersChanged) {
        $pushTo = 'any; this environment deploys by manual runs'
        if ($branch -ne '-') { $pushTo = $branch }
        Add-Step 'Commit the saved answers' 'git, in the repository' @(
            "git add infra/environments/$envAbbr.json",
            "git commit -m `"Azure environment $envAbbr`"",
            "then push it to the branch that deploys ($pushTo): the workflows read it to find the environment.")
    }
    if (-not $haveGh) {
        $lines = @()
        if ($branch -ne '-') { $lines += "Deployment branches and tags: Selected branches -> Add rule: $branch" }
        $lines += 'Environment variables -> Add variable, for each:'
        foreach ($name in $vars.Keys) {
            $value = $vars[$name]
            if (-not $value) { $value = '(after step 2 of this script: run it again)' }
            $lines += ("  {0,-22} {1}" -f $name, $value)
        }
        foreach ($t in $tokens) {
            $lines += "Environment secrets -> Add secret: $($t.Name), the value of"
            $lines += "  az staticwebapp secrets list -g $rgName -n $($t.App) --query properties.apiKey -o tsv"
        }
        Add-Step "Set up the GitHub environment $ghEnv" "https://github.com/$repo/settings/environments (New environment: $ghEnv)" $lines
    }
    $records = @($script:dnsTodo)
    if (-not $records.Count -and @($map.domains | Where-Object { $script:choices[$_.answer] -ne '-' -and -not $script:apps[$_.resource] }).Count) { $records = @(Get-DnsRecords) }
    if ($records.Count) {
        $zones = (@($records | ForEach-Object { Get-Zone $_.Name }) | Select-Object -Unique) -join ', '
        $lines = @()
        foreach ($r in $records) {
            $how = 'pointing to'
            if ($r.Type -eq 'TXT') { $how = 'with the value' }
            $lines += ("{0,-5}  {1,-30} {2,-14} {3}" -f $r.Type, (Get-RelativeName $r.Name), $how, $r.Value)
        }
        $lines += 'Then run this again: step 4 checks the records and adds the domains with their certificates.'
        if ($map.domainNotes -and $map.domainNotes.$envAbbr) { $lines += @($map.domainNotes.$envAbbr) }
        Add-Step 'Add the DNS records of the custom domains' "the DNS host of $zones (where the domain's DNS is managed)" $lines
    }
    if ($script:domainsToAdd) {
        Add-Step 'Add the custom domains' 'this PowerShell window (repository root)' @(
            "The DNS records are there. Run .\infra\azure-setup.ps1 -Start -Environment $envAbbr and say yes in step 4:",
            'it adds the domains to the apps with their free certificates (a Static Web App''s takes a few minutes).')
    }
    if ($created -and -not $allLive) {
        $lines = @()
        $push = ''
        if ($map.github.push) { $push = " ($($map.github.push))" }
        if ($branch -ne '-') { $lines += "Push to $branch$push, or:" }
        $flows = @($map.github.workflows | Where-Object { $_ })
        if ($flows.Count) {
            $run = "Actions -> `"$($flows[0])`" -> Run workflow -> environment $ghEnv"
            foreach ($f in @($flows | Select-Object -Skip 1)) { $run += ", and the same for `"$f`"" }
            $lines += "$run."
        } else { $lines += "Actions -> run the workflow of each app with the environment $ghEnv (they sign in with AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)." }
        $both = 'every app'
        if ($flows.Count -eq 2) { $both = 'both' }
        $lines += "Then run this again with -Check: step 5 shows $both live."
        Add-Step 'Deploy the apps' "https://github.com/$repo/actions" $lines
    }
    foreach ($c in @($map.cleanup)) {
        if (-not $c -or $c.env -ne $envAbbr -or -not $haveGh -or -not $created -or -not $allLive) { continue }
        if (-not (Test-Gh @('secret', 'list', '--repo', $repo)) -or -not ((Invoke-Gh @('secret', 'list', '--repo', $repo)) -match $c.repoSecret)) { continue }
        Add-Step $c.title $c.where @($c.what | ForEach-Object { Expand $_ })
    }
    # The secrets put in by hand (e.g. API keys of other services): the app's settings already point at them
    # (main.bicep); until they are there the app treats them as not set.
    $listedSecrets = @{} # vault/secret already in a step
    foreach ($vdef in @($defs | Where-Object { $_.handSecrets })) {
        $hs = $vdef.handSecrets
        if (-not $script:apps[$hs.restart]) { continue }
        $vres = $script:res[$vdef.key]
        $vaultGroupName = $rgName
        if ($vres.Group) { $vaultGroupName = $vres.Group }
        $vaultResource = "/subscriptions/$subscription/resourceGroups/$vaultGroupName/providers/$($vdef.armType)/$($vres.Name)"
        $missingKeys = @($vdef.secrets | Where-Object { $_.by -eq 'hand' -and (Test-SecretName ([string]$_.name)) -and -not (Try-Az @('resource', 'show', '--ids', "$vaultResource/secrets/$($_.name)")) })
        if (-not $missingKeys.Count) { continue }
        $lines = @()
        foreach ($k in $missingKeys) {
            $lines += "az keyvault secret set --vault-name $($vres.Name) --name $($k.name) --file <a file only you can read, holding $($k.label)> --encoding utf-8"
            $lines += "  $($k.what); $($hs.reader) reads it as $($k.setting)"
        }
        foreach ($k in $missingKeys) { $listedSecrets["$($vres.Name)/$($k.name)".ToLower()] = $true }
        $lines += Get-RestartCommand ([string]$hs.restart)
        if ((Get-Def ([string]$hs.restart)).armType -eq $containerAppType) { $lines += "  $($hs.reader) reads its Key Vault secrets when its revision starts (a new version within about 30 minutes by itself)" }
        else { $lines += "  $($hs.reader) reads Key Vault references when it starts (portal: $($hs.reader) -> Environment variables -> Pull reference values)" }
        if ($hs.after) { $lines += $hs.after }
        Add-Step (Expand $hs.title) $hs.where $lines
    }
    # The same for the apps' secrets from an analysis (a vault without handSecrets): what to put in, then
    # the apps that read them restarted.
    foreach ($vdef in @($defs | Where-Object { -not $_.handSecrets -and @($_.secrets | Where-Object { $_ -and $_.by -eq 'hand' }).Count })) {
        $vres = $script:res[$vdef.key]
        if (-not $vres -or -not $vres.Name) { continue }
        $vaultGroupName = $rgName
        if ($vres.Group) { $vaultGroupName = $vres.Group }
        $vaultResource = "/subscriptions/$subscription/resourceGroups/$vaultGroupName/providers/$($vdef.armType)/$($vres.Name)"
        if (-not (Try-Az @('resource', 'show', '--ids', $vaultResource))) { continue }
        $missingKeys = @($vdef.secrets | Where-Object { $_ -and $_.by -eq 'hand' -and (Test-SecretName ([string]$_.name)) -and -not (Try-Az @('resource', 'show', '--ids', "$vaultResource/secrets/$($_.name)")) })
        if (-not $missingKeys.Count) { continue }
        $lines = @()
        foreach ($k in $missingKeys) {
            $lines += "az keyvault secret set --vault-name $($vres.Name) --name $($k.name) --file <a file only you can read, holding $($k.label)> --encoding utf-8"
            $lines += "  $($k.what): $($k.app) reads it as $($k.setting)"
        }
        foreach ($k in $missingKeys) { $listedSecrets["$($vres.Name)/$($k.name)".ToLower()] = $true }
        foreach ($a in @($missingKeys | ForEach-Object { [string]$_.app } | Where-Object { $_ } | Select-Object -Unique)) {
            $ad = Get-Def $a
            if (-not $ad -or -not $script:res[$a] -or -not $script:res[$a].Name) { continue }
            # A container app that doesn't exist yet reads them when it is created.
            if ($ad.armType -eq $containerAppType -and -not $script:apps[$a]) { continue }
            $lines += Get-RestartCommand $a
        }
        $lines += '  the apps read Key Vault references when they start (until then a missing secret is an empty setting; a container app''s revision does not start without it)'
        Add-Step "Put the apps' secrets into $($vres.Name)" "https://portal.azure.com/#@/resource$vaultResource/secrets" $lines
    }
    # Key Vault secrets a container app references that no step above lists (its secrets in Azure, by name).
    $containerLines = @()
    foreach ($appKey in @($script:lackingSecrets.Keys)) {
        $todo = @($script:lackingSecrets[$appKey] | Where-Object { -not $listedSecrets["$($_.Vault)/$($_.Secret)".ToLower()] })
        if (-not $todo.Count) { continue }
        foreach ($t in $todo) {
            $containerLines += "az keyvault secret set --vault-name $($t.Vault) --name $($t.Secret) --file <a file only you can read> --encoding utf-8"
            $containerLines += "  for $($script:res[$appKey].Name) ($($t.Ref)); delete the file afterwards (--value would show the secret in the process list and the shell history)"
        }
        $containerLines += Get-RestartCommand $appKey
    }
    if ($containerLines.Count) {
        $containerLines += '  a container app reads its Key Vault secrets when its revision starts: its first image waits for them.'
        $containerLines += "Then start again: .\infra\azure-setup.ps1 -Start -Environment $envAbbr (step First image deploys it)."
        Add-Step "Put the container apps' Key Vault secrets in" 'this PowerShell window (az), signed in with Key Vault Secrets Officer on the vault' $containerLines
    } elseif ($script:lackingSecrets.Count) {
        # Their secrets are listed in a step above: the first image follows with the next start.
        Add-Step 'Give the container apps their first image' 'this PowerShell window (repository root)' @(
            "Once the secrets above are in: .\infra\azure-setup.ps1 -Start -Environment $envAbbr (step First image deploys it).")
    }
    # The container apps still on the placeholder: their workflow builds and deploys their own image (after the sign-in
    # in front of them and their Key Vault secrets).
    if ($placeholderApps.Count) {
        $lines = @()
        foreach ($def in $placeholderApps) {
            $wf = 'its deploy workflow'
            if ($def.deploy -and $def.deploy.name) { $wf = "`"$($def.deploy.name)`"" }
            elseif ($def.deploy -and $def.deploy.workflow) { $wf = "`"$($def.deploy.workflow)`"" }
            $registryName = ''
            if ($def.registry -and $script:res[[string]$def.registry]) { $registryName = " to $($script:res[[string]$def.registry].Name)" }
            $lines += "Actions -> $wf -> Run workflow -> environment $ghEnv, push-only$(if ($branch -ne '-') { ", on $branch" })"
            $lines += "  builds the image of $($script:res[$def.key].Name) and pushes it$registryName"
        }
        if (@($placeholderApps | Where-Object { Test-SignInOn $_ }).Count) { $lines += 'An app with sign-in gets its image only once the sign-in is in front of it (a start makes it).' }
        $lines += "Then .\infra\azure-setup.ps1 -Start -Environment $envAbbr deploys the pushed image with the app's settings (step First image does both"
        $lines += 'when asked); every later run of the workflow deploys the new image by itself. -Check then shows each app on its own image.'
        Add-Step 'Deploy the container apps (they still run the placeholder)' "https://github.com/$repo/actions" $lines
    }
    # An app switched (or being switched) from its system-assigned identity to its own: what the old one was given,
    # removed by hand once the app works with its own identity (never by the setup: the app may still need it).
    $oldApps = @(@($script:oldIdentities | ForEach-Object { $_.App }) + @($script:oldSqlUsers | ForEach-Object { $_.App }) | Where-Object { $_ } | Select-Object -Unique)
    foreach ($a in $oldApps) {
        $o = @($script:oldIdentities | Where-Object { $_.App -eq $a }) | Select-Object -First 1
        $users = @($script:oldSqlUsers | Where-Object { $_.App -eq $a })
        $lines = @()
        if ($o) {
            $lines += "$a signs in as its system-assigned identity ($($o.PrincipalId)); the template switches it to its own identity $($o.Identity)."
            $lines += 'Once it works with that one, remove what the old identity was given (Azure deletes the old identity with the switch, not its roles):'
            foreach ($ra in @($o.Assignments)) {
                $lines += "az role assignment delete --ids $($ra.id)"
                $lines += "  $($ra.roleDefinitionName) on $($ra.scope)"
            }
            if (-not @($o.Assignments).Count) { $lines += '(it has no role assignments)' }
        } else { $lines += "$a signs in as its own identity now; once it works with it, drop the database users of its old system-assigned identity:" }
        foreach ($u in $users) { $lines += "DROP USER [$($u.User.Replace(']', ']]'))];   -- in $($u.Database) on $($u.Server), as its Entra admin" }
        Add-Step "Remove the old identity's access of $a" 'this PowerShell window (az), and the databases named (SSMS or the portal''s query editor)' $lines
    }
    if ($steps.Count) {
        Head 'Next steps (by hand)'
        if ($script:ui) { Send ([ordered]@{ t = 'steps'; items = @($steps) }) }
        else {
            for ($i = 0; $i -lt $steps.Count; $i++) {
                Write-Host ''
                Write-Host "  $($i + 1). $($steps[$i].title)" -ForegroundColor Cyan
                Write-Host "       Where: $($steps[$i].where)"
                Write-Host '       What:'
                foreach ($line in $steps[$i].what) { Write-Host "         $line" }
            }
        }
    }

    $open = @($script:results | Where-Object { -not $_.Done })
    $code = 0
    if ($open.Count) { $code = 1 }
    if ($script:ui) {
        Send ([ordered]@{ t = 'summary'; env = $envAbbr; ghEnv = $ghEnv; open = @($open | ForEach-Object { $_.Text }); code = $code })
        return $code
    }
    Write-Host ''
    if ($open.Count) {
        Write-Host "$envAbbr ($ghEnv): $($open.Count) open:" -ForegroundColor Yellow
        foreach ($o in $open) { Write-Host "  -- $($o.Text)" -ForegroundColor Yellow }
        return 1
    }
    Write-Host "$envAbbr ($ghEnv): everything is set up." -ForegroundColor Green
    return 0
}

# --- remove ------------------------------------------------------------------------------------------

# Removes what the setup created for one environment, from its saved answers: the resources the template
# made (tag managed-by) and the ones Azure or the setup added for them (an App Service's managed
# certificate, Application Insights' "Failure Anomalies" alert rule), the resource group when nothing else
# is in it, the app registration GitHub Actions deployed with, and the GitHub environment. Kept: shared
# resources from other resource groups, anything else in the group, the DNS records (listed for you).
# Everything is shown first and confirmed by typing the resource group's name.
function Invoke-Remove {
    Say 'Remove all: deletes everything the setup created for an environment; everything is shown first.' 'Cyan'

    Head 'Environment'
    $envs = @($naming.environments.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { Test-Path (Join-Path $infra "environments\$_.json") })
    if (-not $envs.Count) { throw 'No environment is set up (infra/environments/ is empty): nothing to remove.' }
    foreach ($e in $envs) { Note ("{0,-5} {1}" -f $e, $naming.environments.$e) }
    if ($Environment -and $envs -contains $Environment) { $envAbbr = $Environment; Note "environment: $Environment" }
    else { $envAbbr = Select-Option 'Environment to remove' $envs $envs[0] }
    $ghEnv = [string]$naming.environments.$envAbbr
    if ($script:ui) { Send ([ordered]@{ t = 'env'; env = $envAbbr; ghEnv = $ghEnv; saved = $true }) }
    $envFile = Join-Path $infra "environments\$envAbbr.json"
    $saved = Read-Json $envFile
    # Every name it deletes by: by its naming rule first (refused, nothing removed, when one breaks it).
    Assert-SavedNames $saved "infra/environments/$envAbbr.json"
    $rgDef = $defs | Where-Object { $_.ask -eq 'group' } | Select-Object -First 1
    $rgName = [string]$saved.names.($rgDef.key)

    Head 'Azure CLI'
    if (-not (Try-Az @('account', 'show'))) { throw 'The Azure CLI is not signed in: run  az login  and start again.' }
    $sub = @(Invoke-Az @('account', 'list') | Where-Object { $_ -and $_.id -eq $saved.subscriptionId })
    if (-not $sub.Count) { throw "This account can't see the environment's subscription $($saved.subscriptionId) (az login with the right account or tenant)." }
    $script:subscription = $saved.subscriptionId
    Ok "subscription $($sub[0].name)"

    # What is there, and what is ours.
    $certDomains = @($map.domains | Where-Object { $_.dns -eq 'appService' } | ForEach-Object { [string]$saved.($_.answer) } | Where-Object { $_ -and $_ -ne '-' })
    $insightsNames = @($defs | Where-Object { $_.armType -eq 'Microsoft.Insights/components' } | ForEach-Object { $saved.names.($_.key) } | Where-Object { $_ })
    $resources = @()
    if (Invoke-Az @('group', 'exists', '-n', $rgName)) { $resources = @(Invoke-Az @('resource', 'list', '-g', $rgName) | Where-Object { $_ }) }
    # A SQL server's system database goes with its server.
    $resources = @($resources | Where-Object { -not ($_.type -ieq 'Microsoft.Sql/servers/databases' -and $_.name -like '*/master') })
    $ours = @(); $others = @()
    foreach ($r in $resources) {
        $isOurs = $r.tags -and $r.tags.'managed-by' -eq $managedBy
        if (-not $isOurs -and $r.type -eq 'Microsoft.Web/certificates' -and @($certDomains | Where-Object { $r.name -ieq $_ }).Count) { $isOurs = $true }
        if (-not $isOurs -and $r.type -ieq 'microsoft.alertsmanagement/smartDetectorAlertRules' -and @($insightsNames | Where-Object { $r.name -eq "Failure Anomalies - $_" }).Count) { $isOurs = $true }
        if ($isOurs) { $ours += $r } else { $others += $r }
    }
    foreach ($def in $defs) {
        $name = [string]$saved.names.($def.key)
        if (-not $name) { continue }
        $state = 'gone'
        if ($saved.groups -and $saved.groups.($def.key)) { $state = 'shared' }
        elseif (@($ours | Where-Object { $_.name -eq $name }).Count) { $state = 'ours' }
        elseif ($def.ask -eq 'group' -and $resources.Count) { $state = 'ours' }
        $group = ''
        if ($saved.groups) { $group = [string]$saved.groups.($def.key) }
        Mark $def.key $name $state $group
    }
    # The identities of the apps that are deleted (their own, or the system-assigned one of an entry without
    # one): their role assignments go first, wherever they are (on a vault shared from another group they'd stay
    # as "unknown"); then the apps, then the apps' own identities (the map's removeOrder).
    $identities = @(foreach ($def in @($defs | Where-Object { ($_.identity -or $identityAppTypes -contains [string]$_.armType) -and $saved.names.($_.key) })) {
            $appName = [string]$saved.names.($def.key)
            if (-not @($ours | Where-Object { $_.name -eq $appName -and $_.type -ieq $def.armType }).Count) { continue }
            $app = $null
            $identityName = ''
            if ($def.identity) { $identityName = [string]$saved.names.([string]$def.identity) }
            else { $app = Show-App ([string]$def.armType) $rgName $appName }
            $ident = Get-AppIdentity $def $rgName $identityName $app
            if (-not $ident) { continue }
            [pscustomobject]@{ App = $appName; Name = $ident.Name; Assignments = @(Get-RoleAssignments $ident.PrincipalId) }
        })
    $deployDef = $defs | Where-Object { $_.ask -eq 'name' -and $_.type -eq 'deploy' } | Select-Object -First 1
    $deployApp = [string]$saved.names.($deployDef.key)
    # By the saved client ids; by name only what you alone own (Resolve-EntraApp): never someone else's.
    $deployIdAnswer = Get-DeployClientIdAnswer ([string]$deployDef.key)
    $deployFound = Resolve-EntraApp $deployApp ([string]$saved.$deployIdAnswer) $deployIdAnswer
    $entra = $deployFound.App
    if ($deployFound.Problem) { Note "Entra: app registration ${deployApp}: $($deployFound.Problem); not deleted" }
    if ($entra) { Mark $deployDef.key $deployApp 'ours' '' }
    # The sign-in app registrations of the container apps, deleted when asked.
    $signInRegs = @(foreach ($def in @(Get-SignInDefs | Where-Object { $saved.names.($_.key) })) {
            $appName = [string]$saved.names.($def.key)
            $idAnswer = Get-SignInClientIdAnswer ([string]$def.key)
            $found = Resolve-EntraApp $appName ([string]$saved.$idAnswer) $idAnswer '' -SignIn
            if ($found.Problem) { Note "Entra: sign-in of ${appName}: $($found.Problem); not deleted" }
            if ($found.App) { [pscustomobject]@{ App = $appName; AppId = [string]$found.App.appId; Answer = $idAnswer } }
        })
    $haveGh = $ghExe -and (Test-Gh @('auth', 'status'))
    $repo = [string]$saved.repo
    $haveEnv = $haveGh -and $repo -and (Test-Gh @('api', "repos/$repo/environments/$ghEnv"))
    $vaultOurs = @($ours | Where-Object { $_.type -eq 'Microsoft.KeyVault/vaults' }) | Select-Object -First 1
    $wholeGroup = $resources.Count -gt 0 -and $others.Count -eq 0

    Head "What would be removed ($envAbbr, $ghEnv)"
    if ($envAbbr -eq 'prod') { Say '    THIS IS PRODUCTION: its live apps stop.' 'Red' }
    if (-not $resources.Count) { Note "Azure: resource group $rgName is empty or gone" }
    elseif ($wholeGroup) { Note "Azure: resource group $rgName with everything in it:" }
    else { Note "Azure, in resource group ${rgName}:" }
    foreach ($r in $ours) { Note ("  delete  {0,-52} {1}" -f $r.name, $r.type) }
    foreach ($r in $others) { Note ("  keep    {0,-52} {1} (not made by the setup)" -f $r.name, $r.type) }
    foreach ($i in @($identities | Where-Object { @($_.Assignments).Count })) { Note ("  delete  {0,-52} first: {1} role assignment(s) of {2}" -f "roles of $($i.App)", @($i.Assignments).Count, $i.Name) }
    foreach ($def in @($defs | Where-Object { $_.groupParam -and $saved.groups -and $saved.groups.($_.key) })) {
        Note ("  keep    {0,-52} shared from {1}" -f $saved.names.($def.key), $saved.groups.($def.key))
    }
    if ($entra) { Note "Entra: app registration $deployApp (GitHub Actions' sign-in to Azure) and its service principal" }
    foreach ($s in $signInRegs) { Note "Entra: app registration $($s.App) ($($s.AppId)), the sign-in in front of $($s.App): asked (restorable for 30 days)" }
    if ($haveEnv) { Note "GitHub: environment $ghEnv of $repo (its variables, deployment token and branch rule)" }
    elseif (-not $haveGh) { Note "GitHub: not checked (no GitHub CLI); delete the environment $ghEnv by hand: https://github.com/$repo/settings/environments" }
    if ($vaultOurs) { Note "Key Vault $($vaultOurs.name): deleted vaults stay recoverable for 30 days and keep their name; you are asked whether to purge it" }
    Note 'Not touched: the DNS records (listed at the end), the code, the workflows.'

    if (-not $ours.Count -and -not $entra -and -not $haveEnv -and -not $signInRegs.Count) {
        Ok 'nothing of this environment is left'
    } else {
        Say ''
        $question = "To remove all of this, type the resource group's name ($rgName), anything else cancels"
        $typed = Read-Answer "  ${question}: " ([ordered]@{ kind = 'text'; question = $question; default = ''; danger = $true })
        if ($typed -cne $rgName) {
            Note 'cancelled, nothing was changed'
            if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = $envAbbr; ghEnv = $ghEnv; open = @(); code = 1; cancelled = $true }) }
            return 1
        }

        Head 'Removing'
        if ($haveEnv) {
            Invoke-Gh @('api', '-X', 'DELETE', "repos/$repo/environments/$ghEnv") | Out-Null
            Ok "GitHub environment $ghEnv deleted"
        }
        if ($entra) {
            Invoke-Az @('ad', 'app', 'delete', '--id', $entra.appId) | Out-Null # its service principal and federated credentials go with it
            Ok "app registration $deployApp deleted"
            Mark $deployDef.key $deployApp 'gone' ''
        }
        # The apps' role assignments first: one left on something kept (a vault shared from another group) would
        # stay as an "unknown" principal.
        foreach ($i in $identities) {
            foreach ($ra in @($i.Assignments)) { Try-Az @('role', 'assignment', 'delete', '--ids', $ra.id) | Out-Null }
            if (@($i.Assignments).Count) { Ok "$(@($i.Assignments).Count) role assignment(s) of $($i.Name) ($($i.App)) removed" }
        }
        if ($wholeGroup) {
            Note "deleting resource group $rgName (a few minutes)..."
            Invoke-Az @('group', 'delete', '-n', $rgName, '--yes') | Out-Null
            Ok "resource group $rgName deleted"
            if ($saved.budget -and $saved.budget -ne '-') {
                $r = Invoke-Native 'az' @('rest', '--method', 'delete', '--url', (Get-BudgetUrl $saved.subscriptionId $rgName $ghEnv), '--only-show-errors')
                if ($r.Code -eq 0) { Ok "budget monthly-$ghEnv deleted" }
            }
            foreach ($def in $defs) { if ($saved.names.($def.key) -and -not ($saved.groups -and $saved.groups.($def.key)) -and $def.ask -ne 'name') { Mark $def.key $saved.names.($def.key) 'gone' '' } }
        } elseif ($ours.Count) {
            # In the map's removeOrder: apps before their plan, the plan and the workspace last; the apps' own
            # identities after the apps (also in a map whose removeOrder doesn't say so).
            # (container apps before their environment and registry also in a map whose removeOrder doesn't say so)
            $order = @(Get-ContainerRemoveOrder @($map.removeOrder) | ForEach-Object { $_.ToLower() })
            $lastApp = -1
            foreach ($t in $identityAppTypes) { $at = [array]::IndexOf($order, $t.ToLower()); if ($at -gt $lastApp) { $lastApp = $at } }
            $sorted = @($ours | Sort-Object {
                    $i = [array]::IndexOf($order, $_.type.ToLower())
                    if ($_.type -ieq $identityType -and $i -le $lastApp) { if ($lastApp -lt 0) { 99.5 } else { $lastApp + 0.5 } }
                    elseif ($i -lt 0) { 99 } else { $i }
                })
            foreach ($r in $sorted) {
                Invoke-Az @('resource', 'delete', '--ids', $r.id) | Out-Null
                Ok "$($r.name) deleted"
                $def = $defs | Where-Object { $saved.names.($_.key) -eq $r.name } | Select-Object -First 1
                if ($def) { Mark $def.key $r.name 'gone' '' }
            }
        }
        # The container apps' sign-in app registrations, after their apps (each asked).
        foreach ($s in $signInRegs) { Remove-SignInRegistration $s.App $s.AppId $s.Answer }
        if ($vaultOurs) {
            $deleted = Try-Az @('keyvault', 'show-deleted', '--name', $vaultOurs.name)
            if ($deleted -and (Confirm-Step "Purge Key Vault $($vaultOurs.name) now (frees its name; its secrets can't be recovered then)?" -DefaultNo -Danger)) {
                Invoke-Az @('keyvault', 'purge', '--name', $vaultOurs.name) | Out-Null
                Ok "Key Vault $($vaultOurs.name) purged"
            } elseif ($deleted) { Note "Key Vault $($vaultOurs.name) stays recoverable until $(([string]$deleted.properties.scheduledPurgeDate).Split('T')[0]) (az keyvault recover --name $($vaultOurs.name))" }
        }
    }

    if (Confirm-Step "Delete infra/environments/$envAbbr.json as well (the workflows then stop deploying for $ghEnv)?" -DefaultNo) {
        Remove-Item $envFile
        Ok "infra/environments/$envAbbr.json deleted (commit it)"
    } else { Note "infra/environments/$envAbbr.json kept: Start recreates the environment with the same answers" }

    $records = @()
    foreach ($dm in @($map.domains)) {
        $domain = [string]$saved.($dm.answer)
        if (-not $domain -or $domain -eq '-') { continue }
        $records += New-DnsRecord 'CNAME' $domain "(the removed $($dm.what))"
        if ($dm.dns -eq 'appService') { $records += New-DnsRecord 'TXT' "asuid.$domain" '(its verification id)' }
    }
    if ($records.Count) {
        $zones = (@($records | ForEach-Object { Get-Zone $_.Name }) | Select-Object -Unique) -join ', '
        $lines = @($records | ForEach-Object { "delete {0,-5}  {1}" -f $_.Type, (Get-RelativeName $_.Name) })
        $lines += '(a CNAME left pointing at a deleted Azure address can be taken over by someone else''s app)'
        Head 'Next steps (by hand)'
        if ($script:ui) { Send ([ordered]@{ t = 'steps'; items = @([ordered]@{ title = 'Remove the DNS records of the custom domains'; where = "the DNS host of $zones"; what = $lines }) }) }
        else {
            Write-Host ''
            Write-Host '  1. Remove the DNS records of the custom domains' -ForegroundColor Cyan
            Write-Host "       Where: the DNS host of $zones"
            Write-Host '       What:'
            foreach ($line in $lines) { Write-Host "         $line" }
        }
    }
    if ($script:ui) {
        Send ([ordered]@{ t = 'summary'; env = $envAbbr; ghEnv = $ghEnv; open = @(); code = 0; removed = $true })
        return 0
    }
    Write-Host ''
    Write-Host "$envAbbr ($ghEnv): removed." -ForegroundColor Green
    return 0
}

# What to do: a switch, else the help and then the menu.
function Select-Mode {
    if ($DryRun) { return 'dryrun' }
    if ($Check) { return 'check' }
    if ($Start) { return 'start' }
    if ($Remove) { return 'remove' }
    if ($AddResource) { return 'addresource' }
    if ($RemoveResource) { return 'removeresource' }
    if ($Init -or -not $map) { return 'init' }
    if ($script:ui) { throw '-Ui needs -DryRun, -Check, -Start, -Remove, -AddResource or -RemoveResource.' }
    Show-Usage
    Write-Host 'What to do?' -ForegroundColor Cyan
    Write-Host '  1. Dry run - asks every question, shows what would be created or changed; changes nothing'
    Write-Host '  2. Check   - checks a set-up environment with its saved answers, no questions; changes nothing'
    Write-Host '  3. Start   - asks every question, then creates and updates what is missing (each change asked first)'
    Write-Host '  4. Remove all - deletes what the setup created for an environment (shown first, confirmed by typing its name)'
    Write-Host '  5. Add a resource to the map (from infra/catalog), then generate main.bicep'
    Write-Host '  6. Remove a resource from the map, then generate main.bicep'
    Write-Host '  q. Quit'
    while ($true) {
        $choice = (Read-Answer '  Choice [1]: ' ([ordered]@{ kind = 'menu'; question = 'What to do?'; default = '1' })).ToLower()
        if (@('', '1', 'd', 'dry run') -contains $choice) { return 'dryrun' }
        if (@('2', 'c', 'check') -contains $choice) { return 'check' }
        if (@('3', 's', 'start') -contains $choice) { return 'start' }
        if (@('4', 'r', 'remove') -contains $choice) { return 'remove' }
        if (@('5', 'a', 'add') -contains $choice) { return 'addresource' }
        if (@('6', 'x') -contains $choice) { return 'removeresource' }
        if (@('q', 'quit') -contains $choice) { return 'quit' }
        Note 'X 1 to 6 or q'
    }
}

$code = 1
try {
    if (-not $script:ui) { Show-Author }
    $script:mode = Select-Mode
    if (-not $map -and @('init', 'quit') -notcontains $script:mode) { throw 'There is no infra/infra.map.json yet: start the project with .\infra\azure-setup.ps1 -Init (or .\infra\lazybicep.ps1).' }
    if ($script:mode -eq 'quit') { $code = 0 }
    elseif ($script:mode -eq 'remove') { $code = Invoke-Remove }
    else {
        # The map's modes write files only at their end, so '<' works in them too until then.
        $mapMode = @('init', 'addresource', 'removeresource') -contains $script:mode
        $script:readOnly = $script:mode -ne 'start' -and -not $mapMode
        $script:auto = $script:mode -eq 'check'
        $script:typed.Clear() # the menu's answer isn't one of the questions
        while ($true) {
            $script:results.Clear()
            $script:dnsTodo.Clear()
            $script:canGoBack = $true
            $script:auto = $script:mode -eq 'check'
            $script:lastAuto = $null
            if ($mapMode) { Reset-MapState }
            try {
                switch ($script:mode) {
                    'init' { $code = Invoke-Init }
                    'addresource' { $code = Invoke-AddResource }
                    'removeresource' { $code = Invoke-RemoveResource }
                    default { $code = Invoke-Setup }
                }
                break
            } catch {
                if ($_.Exception.Message -ne $backSignal) { throw }
                # Everything typed except the last answer is answered again; the question before it comes up.
                $earlier = @($script:typed)
                $script:typed = New-Object System.Collections.ArrayList
                $script:replay = New-Object System.Collections.ArrayList
                for ($i = 0; $i -lt $earlier.Count - 1; $i++) { [void]$script:replay.Add($earlier[$i]) }
                # The question asked again shows what was answered before (to change it, or keep it).
                $script:previous = $null
                if ($earlier.Count) { $script:previous = $earlier[$earlier.Count - 1] }
                $script:replaying = $script:replay.Count -gt 0
                if ($script:ui) { Send ([ordered]@{ t = 'back' }) } else { Write-Host '    (back)' -ForegroundColor DarkGray }
            }
        }
    }
}
catch {
    if ($script:ui) { Send ([ordered]@{ t = 'error'; text = $_.Exception.Message }) }
    else { Write-Host ''; Write-Host $_.Exception.Message -ForegroundColor Red }
}
finally {
    if ($script:sqlRules.Count) { try { Close-SqlFirewall } catch { } }
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
exit $code
