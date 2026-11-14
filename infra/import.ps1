#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyBicep  -  import.ps1                                               ║
#  ║   Suggests a new project's map from resources already in Azure           ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyBicep  -  https://github.com/netmedia/lazybicep          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
.SYNOPSIS
LazyBicep by Netmedia: reads resource groups of a subscription (Azure CLI, read only) and suggests the
map of a new project from their resources: a spec (what -Init -SpecFile takes) with the real names.

.AUTHOR
Netmedia  |  https://netmedia.agency  |  netmedia@netmedia.hr

.DESCRIPTION
Each resource of a kind the catalog has becomes a suggested resource, with what it was read from:
  Microsoft.Web/sites                      App Service (runtime, health check) or Function App (Flex
                                           Consumption or a plan; runtime; its storage account)
  Microsoft.Web/serverFarms                App Service plan (a Flex Consumption plan goes with its app)
  Microsoft.Web/staticSites                Static Web App (its build's folders, when GitHub made it)
  Microsoft.Sql/servers (+ databases)      SQL server and every database but master
  Microsoft.ServiceBus/namespaces          Service Bus with its queues (topics are noted)
  Microsoft.Storage/storageAccounts        Storage account and its queues
  Microsoft.KeyVault/vaults                Key Vault
  Microsoft.Insights/components            Application Insights (and its Log Analytics workspace)
  Microsoft.OperationalInsights/workspaces Log Analytics workspace
  Microsoft.Cdn/profiles (Front Door)      Front Door, in front of the app its origin is (a classic CDN
                                           profile is noted: it is retired)
What each app uses comes from its app settings and connection strings (matched by host names; values are
never shown or kept) and from its managed identity's role assignments (which give its roles too).

A type the catalog has no kind for is reported, and infra/new-kinds.md gets a prompt for each (what to
build, the resource's properties without secrets): paste it to Claude Code in the LazyBicep repository
to add the kind. Alert rules, action groups and certificates that come with other resources are left out.

infra/azure-setup.ps1 -Init (and lazybicep's New project) runs this when asked to import from Azure: it
asks the subscription, the resource groups and the resources, offers each suggestion, and writes the
real names as the environment's answers (infra/environments/<env>.json), so its first dry run finds them.

.PARAMETER ResourceGroup
The resource groups to read (comma-separated).

.PARAMETER Subscription
The subscription (name or id). Default: the Azure CLI's.

.PARAMETER List
Only lists the resources (for picking): each with its kind in the catalog, or none.

.PARAMETER Ids
Only these resources (their ids). Default: every resource the catalog has a kind for.

.PARAMETER Environment
The environment these resources are (prod, test...): the names are its answers.

.PARAMETER MainGroup
With several resource groups: the environment's own one (the others' resources are shared from them).

.PARAMETER Prompts
Where to write the prompts for the missing kinds. Default: infra/new-kinds.md.

.PARAMETER Out
Writes the suggestion as a spec file (for .\infra\azure-setup.ps1 -Init -SpecFile <file>).

.PARAMETER PassThru
Returns the result as an object, without output (for infra/azure-setup.ps1).

.PARAMETER Help
Shows the usage guide and exits.

.EXAMPLE
.\infra\import.ps1 -ResourceGroup contoso-shop-resgr-prod

.EXAMPLE
.\infra\import.ps1 -ResourceGroup contoso-shop-resgr-prod,contoso-shared-resgr -Out spec.json

.NOTES
LazyBicep is a Netmedia product: https://netmedia.agency, netmedia@netmedia.hr,
https://github.com/netmedia/lazybicep.

.LINK
infra/LAZYBICEP.md
#>
[CmdletBinding()]
param(
    [string[]]$ResourceGroup,
    [string]$Subscription,
    [switch]$List,
    [string[]]$Ids,
    [string]$Environment,
    [string]$MainGroup,
    [string]$Prompts,
    [string]$Out,
    [switch]$PassThru,
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$infra = $PSScriptRoot

# --- Netmedia: who made it, how to use it ---------------------------------------------------------------

function Show-Author {
    $width = 64
    $hLine = [string]::new([char]0x2500, $width)
    $v = [char]0x2502
    $esc = [char]27
    $version = ''
    if (Test-Path (Join-Path $infra 'kit.json')) { $version = (Get-Content (Join-Path $infra 'kit.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version }
    function Row([string]$display, [string]$measure = $display, [string]$color = 'White') {
        $pad = [Math]::Max(0, $width - $measure.Length)
        $left = [Math]::Floor($pad / 2)
        Write-Host "  $v" -NoNewline -ForegroundColor Cyan
        Write-Host "$(' ' * $left)$display$(' ' * ($pad - $left))" -NoNewline -ForegroundColor $color
        Write-Host $v -ForegroundColor Cyan
    }
    $title = 'LazyBicep  -  import.ps1'
    Write-Host ''
    Write-Host "  $([char]0x256D)$hLine$([char]0x256E)" -ForegroundColor Cyan
    Row ''
    Row "$esc[1m$title$esc[0m" $title 'Cyan'
    Row 'Suggests a new project''s map from resources in Azure' -color 'White'
    Row ''
    Row "by Netmedia$(if ($version) { "  |  LazyBicep $version" })" -color 'DarkGray'
    Row 'https://netmedia.agency  |  netmedia@netmedia.hr' -color 'DarkGray'
    Row ''
    Write-Host "  $([char]0x2570)$hLine$([char]0x256F)" -ForegroundColor Cyan
    Write-Host ''
}
function Show-Usage {
    $b = { param($t) Write-Host "  $t" -ForegroundColor White }
    $d = { param($t) Write-Host "  $t" -ForegroundColor DarkGray }
    $g = { param($t) Write-Host "  $t" -ForegroundColor Green }
    $y = { param($t) Write-Host "  $t" -ForegroundColor Yellow }
    & $b 'USAGE'
    & $g '  .\infra\import.ps1  -ResourceGroup <rg>[,<rg>...]  [-Subscription <sub>]  [-Out <spec.json>]'
    & $d '  Reads the resource groups (Azure CLI, read only) and suggests the map of a new project'
    & $d '  from their resources: apps with their runtimes, plans, SQL servers and databases,'
    & $d '  Service Bus and its queues, storage and its queues, Key Vault, Application Insights;'
    & $d '  what each app uses (its settings, its identity''s roles). Changes nothing.'
    Write-Host ''
    & $b 'OPTIONS'
    & $y '  -ResourceGroup <rg>[,<rg>...]'
    & $d '    The resource groups to read.'
    & $y '  -Subscription <name or id>'
    & $d '    Default: the Azure CLI''s.'
    & $y '  -List'
    & $d '    Only lists the resources, each with its kind in the catalog (or none).'
    & $y '  -Out <spec.json>'
    & $d '    Writes the suggestion as a spec file (.\infra\azure-setup.ps1 -Init -SpecFile).'
    & $y '  -Help  (-h)'
    & $d '    Shows this guide and exits.'
    Write-Host ''
    & $b 'USUALLY'
    & $g '  .\infra\azure-setup.ps1 -Init      (or lazybicep: n), then azure'
    & $d '    asks the subscription, the resource groups and the resources, offers every'
    & $d '    suggestion, then the usual questions; the real names become the environment''s'
    & $d '    answers, so its first dry run finds the resources.'
    Write-Host ''
    & $d '  A type the catalog has no kind for: infra\new-kinds.md gets a prompt to add it.'
    & $d '  More: infra\LAZYBICEP.md ("A new project")'
    Write-Host ''
}
if ($Help) { Show-Author; Show-Usage; exit 0 }
if (-not $ResourceGroup) { Show-Author; Show-Usage; Write-Host '  ERROR: -ResourceGroup is required.' -ForegroundColor Red; exit 1 }
$ResourceGroup = @($ResourceGroup | ForEach-Object { $_.Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# --- az ---------------------------------------------------------------------------------------------------

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'The Azure CLI is not installed: winget install Microsoft.AzureCLI, then a new terminal.' }
# JSON from az, or $null when it fails (no access, not found).
function Get-AzJson([string[]]$Arguments) {
    $all = @($Arguments) + @('-o', 'json', '--only-show-errors')
    if ($script:sub) { $all += @('--subscription', $script:sub) }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & az @all 2>$null } finally { $ErrorActionPreference = $prev }
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    try { return (($out -join "`n") | ConvertFrom-Json) } catch { return $null }
}
$script:sub = ''
$account = Get-AzJson @('account', 'show')
if (-not $account) { throw 'The Azure CLI is not signed in: run  az login  and start again.' }
if ($Subscription) {
    $s = Get-AzJson @('account', 'show', '--subscription', $Subscription)
    if (-not $s) { throw "No subscription $Subscription for $($account.user.name)." }
    $account = $s
}
$script:sub = [string]$account.id

# --- what the catalog has --------------------------------------------------------------------------------

# Azure types the catalog has a kind for (a web app's kind decides between App Service and Function App).
$kindOf = @{
    'microsoft.web/sites' = 'site'; 'microsoft.web/serverfarms' = 'appServicePlan'; 'microsoft.web/staticsites' = 'staticWebApp'
    'microsoft.sql/servers' = 'sqlServer'; 'microsoft.servicebus/namespaces' = 'serviceBus'; 'microsoft.storage/storageaccounts' = 'storage'
    'microsoft.keyvault/vaults' = 'keyVault'; 'microsoft.insights/components' = 'appInsights'; 'microsoft.operationalinsights/workspaces' = 'logAnalytics'
}
# What comes with other resources (Application Insights' smart detection, App Service's certificates...).
$withOthers = @('microsoft.cdn/profiles/afdendpoints', 'microsoft.cdn/profiles/endpoints', 'microsoft.insights/actiongroups', 'microsoft.alertsmanagement/smartdetectoralertrules', 'microsoft.web/certificates', 'microsoft.insights/metricalerts', 'microsoft.portal/dashboards', 'microsoft.web/connections')
# Missing kinds: a name for them and the usual abbreviation (Cloud Adoption Framework).
$missingHints = @{
    'microsoft.cdn/profiles' = @('classic CDN profile (retired: move it to Front Door, the catalog''s frontDoor)', 'cdnp'); 'microsoft.cdn/profiles/endpoints' = @('CDN endpoint', 'cdne'); 'microsoft.cdn/profiles/afdendpoints' = @('Front Door endpoint', 'fde')
    'microsoft.cache/redis' = @('Azure Cache for Redis', 'redis'); 'microsoft.documentdb/databaseaccounts' = @('Cosmos DB account', 'cosmos'); 'microsoft.managedidentity/userassignedidentities' = @('user-assigned managed identity', 'id')
    'microsoft.app/containerapps' = @('Container App', 'ca'); 'microsoft.app/managedenvironments' = @('Container Apps environment', 'cae'); 'microsoft.containerregistry/registries' = @('container registry', 'cr')
    'microsoft.eventgrid/topics' = @('Event Grid topic', 'evgt'); 'microsoft.eventgrid/systemtopics' = @('Event Grid system topic', 'egst'); 'microsoft.eventhub/namespaces' = @('Event Hubs namespace', 'evhns')
    'microsoft.signalrservice/signalr' = @('SignalR Service', 'sigr'); 'microsoft.signalrservice/webpubsub' = @('Web PubSub', 'wps'); 'microsoft.dbforpostgresql/flexibleservers' = @('PostgreSQL flexible server', 'psql')
    'microsoft.dbformysql/flexibleservers' = @('MySQL flexible server', 'mysql'); 'microsoft.apimanagement/service' = @('API Management', 'apim'); 'microsoft.network/dnszones' = @('DNS zone', 'dnsz')
    'microsoft.communication/communicationservices' = @('Communication Services', 'acs'); 'microsoft.communication/emailservices' = @('Email Communication Services', 'acse'); 'microsoft.search/searchservices' = @('Azure AI Search', 'srch')
    'microsoft.cognitiveservices/accounts' = @('Azure AI services account', 'ais'); 'microsoft.logic/workflows' = @('Logic App', 'logic'); 'microsoft.automation/automationaccounts' = @('Automation account', 'aa')
    'microsoft.servicebus/namespaces/topics' = @('Service Bus topic (and its subscriptions)', 'sbt')
}

# --- the resources of the groups ---------------------------------------------------------------------

function Get-Kind($R) {
    $t = ([string]$R.type).ToLower()
    $k = $kindOf[$t]
    if ($k -eq 'site') { if ([string]$R.kind -match 'functionapp') { return 'functionApp' } return 'appService' }
    # Front Door Standard/Premium; a classic CDN profile (retired) has no kind.
    if ($t -eq 'microsoft.cdn/profiles') { if ([string]$R.sku.name -match 'AzureFrontDoor') { return 'frontDoor' } return $null }
    # A Flex Consumption (or Consumption) plan goes with its Function App.
    if ($k -eq 'appServicePlan' -and ([string]$R.sku.tier -match 'FlexConsumption|Dynamic' -or [string]$R.sku.name -match '^(FC1|Y1)$')) { return 'functionPlan' }
    return $k
}
$items = New-Object Collections.ArrayList
foreach ($g in $ResourceGroup) {
    $rs = Get-AzJson @('resource', 'list', '-g', $g)
    if ($null -eq $rs -and -not (Get-AzJson @('group', 'exists', '-n', $g))) { throw "Resource group $g not found in $($account.name) (or no access)." }
    foreach ($r in @($rs)) {
        $t = ([string]$r.type).ToLower()
        $kind = Get-Kind $r
        $state = 'kind'
        if ($withOthers -contains $t) { $state = 'with' }
        elseif ($kind -eq 'functionPlan') { $state = 'with' }
        elseif (-not $kind) { $state = 'missing' }
        [void]$items.Add([pscustomobject]@{ id = [string]$r.id; name = [string]$r.name; type = [string]$r.type; group = $g; location = [string]$r.location; kind = $kind; state = $state; sku = [string]$r.sku.name })
    }
}

if ($List) {
    $result = [pscustomobject]@{ subscription = [string]$account.id; subscriptionName = [string]$account.name; resources = @($items) }
    if ($PassThru) { return $result }
    Show-Author
    Write-Host "  $($account.name): $($ResourceGroup -join ', ')" -ForegroundColor White
    foreach ($i in $items) {
        $what = switch ($i.state) { 'kind' { $i.kind } 'with' { 'comes with another resource' } default { 'no kind in the catalog' } }
        $color = switch ($i.state) { 'kind' { 'Green' } 'with' { 'DarkGray' } default { 'Yellow' } }
        Write-Host ("    {0,-28} {1,-48} {2}" -f $i.group, "$($i.name)", $what) -ForegroundColor $color
    }
    Write-Host ''
    exit 0
}

$picked = @($items | Where-Object { $_.state -eq 'kind' })
if ($Ids) {
    $want = @($Ids | ForEach-Object { $_.Split(',') } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    $picked = @($items | Where-Object { $_.state -ne 'with' -and $want -contains $_.id.ToLower() })
}
if (-not $MainGroup) {
    # The environment's group: the one with the most apps and resources picked.
    $MainGroup = @($picked | Group-Object group | Sort-Object Count -Descending | ForEach-Object { $_.Name }) | Select-Object -First 1
    if (-not $MainGroup) { $MainGroup = $ResourceGroup[0] }
}
$naming = $null
if (Test-Path (Join-Path $infra 'naming.json')) { $naming = Get-Content (Join-Path $infra 'naming.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
if (-not $Environment) {
    $Environment = 'prod'
    $envs = @()
    if ($naming) { $envs = @($naming.environments.PSObject.Properties | ForEach-Object { $_.Name }) }
    foreach ($e in $envs) { if ($MainGroup -match "(^|[-_])$e($|[-_])") { $Environment = $e } }
}

# --- keys from names ---------------------------------------------------------------------------------------

# A name without its prefix, type and environment parts (contoso-shop-api-apiapp-prod -> api); $null when only
# those are left (or a name without hyphens, like a storage account's).
$noise = New-Object Collections.Generic.HashSet[string]
foreach ($w in @('prod', 'production', 'test', 'stag', 'staging', 'dev', 'development', 'accp', 'acceptance', 'uat', 'qa', 'app', 'api', 'apiapp', 'webapp', 'web', 'func', 'fa', 'fn', 'functions', 'st', 'store', 'sql', 'sqldb', 'sqlserv', 'db', 'kv', 'vault', 'sb', 'sbns', 'sbus', 'bus', 'log', 'logs', 'law', 'appi', 'ai', 'insights', 'plan', 'asp', 'appplan', 'swa', 'stapp', 'statapp', 'rg', 'resgr', 'queue')) { [void]$noise.Add($w) }
if ($naming) { foreach ($p in $naming.types.PSObject.Properties) { [void]$noise.Add($p.Name.ToLower()) } }
$hyphenated = New-Object Collections.ArrayList
foreach ($p in $picked) { if ($p.name -match '-') { [void]$hyphenated.Add([string[]]$p.name.ToLower().Split('-')) } }
$prefixParts = @()
if ($hyphenated.Count -ge 2) {
    $max = (@($hyphenated | ForEach-Object { $_.Count }) | Measure-Object -Minimum).Minimum - 1
    for ($i = 0; $i -lt $max; $i++) {
        $seg = $hyphenated[0][$i]
        if (@($hyphenated | Where-Object { $_[$i] -ne $seg }).Count -or $noise.Contains($seg)) { break }
        $prefixParts += $seg
    }
}
if (-not $prefixParts.Count) {
    $rgParts = @($MainGroup.ToLower().Split('-') | Where-Object { $_ -and -not $noise.Contains($_) })
    $prefixParts = @($rgParts | Select-Object -First 2)
}
$script:keys = New-Object Collections.Generic.HashSet[string]
foreach ($k in @('resourceGroup', 'deployApp')) { [void]$script:keys.Add($k) }
function Get-KeyName([string]$Name) {
    $parts = @([regex]::Split($Name, '[^A-Za-z0-9]+') | Where-Object { $_ })
    if (-not $parts.Count) { return '' }
    $key = ''
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $p = $parts[$i].ToLower()
        if ($i -gt 0) { $p = $p.Substring(0, 1).ToUpper() + $p.Substring(1) }
        $key += $p
    }
    if ($key -notmatch '^[a-z]') { $key = 'x' + $key }
    return $key
}
function Get-FreeKey([string]$Want) {
    $k = $Want
    for ($i = 2; $script:keys.Contains($k); $i++) { $k = "$Want$i" }
    [void]$script:keys.Add($k)
    return $k
}
$keyDefaults = @{ frontDoor = 'cdn'; appService = 'api'; functionApp = 'func'; staticWebApp = 'web'; appServicePlan = 'plan'; sqlServer = 'sqlServer'; sqlDatabase = 'db'; serviceBus = 'bus'; storage = 'storage'; storageQueue = 'queue'; keyVault = 'vault'; appInsights = 'insights'; logAnalytics = 'workspace' }
function Get-KeyFor([string]$Kind, [string]$Name, [switch]$Child) {
    $base = ''
    if ($Child) { $base = Get-KeyName $Name }
    elseif ($Name -match '-') {
        $parts = @($Name.ToLower().Split('-'))
        $i = 0
        while ($i -lt $prefixParts.Count -and $i -lt $parts.Count -and $parts[$i] -eq $prefixParts[$i]) { $i++ }
        $left = @($parts | Select-Object -Skip $i | Where-Object { $_ -and -not $noise.Contains($_) })
        if ($left.Count) { $base = Get-KeyName ($left -join '-') }
    }
    # A kind's usual key reads better than a name's leftover for the shared ones (one of them, mostly).
    if (-not $base -or (@('appServicePlan', 'sqlServer', 'serviceBus', 'storage', 'keyVault', 'appInsights', 'logAnalytics') -contains $Kind -and -not @($picked | Where-Object { $_.kind -eq $Kind -and $_.name -ne $Name }).Count)) { $base = $keyDefaults[$Kind] }
    return Get-FreeKey $base
}

# --- each resource ---------------------------------------------------------------------------------------

$notes = New-Object Collections.ArrayList
function Add-Note([string]$Text) { if ($notes -notcontains $Text) { [void]$notes.Add($Text) } }
$entries = New-Object Collections.ArrayList   # @{ Kind; Key; Title; Item; Answers; Requires; Evidence; Hosts; Uses; Roles; Order }
$byId = @{}
function New-Entry([string]$Kind, [string]$Key, [string]$Title, $Item) {
    $e = [pscustomobject]@{ Kind = $Kind; Key = $Key; Title = $Title; Item = $Item; Answers = [ordered]@{}; Requires = [ordered]@{}; Evidence = (New-Object Collections.ArrayList); Hosts = (New-Object Collections.ArrayList); Uses = (New-Object Collections.ArrayList); Roles = [ordered]@{}; Name = ''; Group = ''; Extra = @{} }
    if ($Item) { $e.Name = $Item.name; $e.Group = $Item.group; $byId[$Item.id.ToLower()] = $e; [void]$e.Evidence.Add("$($Item.group)/$($Item.name) ($($Item.type)$(if ($Item.sku) { ", $($Item.sku)" }))") }
    [void]$entries.Add($e)
    return $e
}
function Find-ById([string]$Id) { if ($Id -and $byId.ContainsKey($Id.ToLower())) { return $byId[$Id.ToLower()] } return $null }

$order = @('logAnalytics', 'appInsights', 'storage', 'sqlServer', 'serviceBus', 'keyVault', 'appServicePlan', 'appService', 'functionApp', 'staticWebApp', 'frontDoor')
foreach ($it in @($picked | Where-Object { $_.state -eq 'kind' } | Sort-Object @{ e = { $order.IndexOf([string]$_.kind) } }, name)) {
    $e = New-Entry $it.kind (Get-KeyFor $it.kind $it.name) $it.name $it
    switch ($it.kind) {
        'logAnalytics' { }
        'appInsights' {
            $c = Get-AzJson @('resource', 'show', '--ids', $it.id)
            $ws = Find-ById ([string]$c.properties.WorkspaceResourceId)
            if ($ws) { $e.Requires['logAnalytics'] = $ws.Key }
            elseif ($c.properties.WorkspaceResourceId) { [void]$e.Evidence.Add("its workspace $(([string]$c.properties.WorkspaceResourceId).Split('/')[-1]) isn't picked: one is asked") }
            $e.Extra.ikey = [string]$c.properties.InstrumentationKey
        }
        'storage' {
            [void]$e.Hosts.Add("$($it.name).blob.core.windows.net"); [void]$e.Hosts.Add("$($it.name).queue.core.windows.net"); [void]$e.Hosts.Add("$($it.name).table.core.windows.net"); [void]$e.Hosts.Add("accountname=$($it.name);")
            # With your Entra sign-in only (never the account's keys).
            $queues = Get-AzJson @('storage', 'queue', 'list', '--account-name', $it.name, '--auth-mode', 'login')
            if ($null -eq $queues) { Add-Note "$($it.name): its queues can't be read with your sign-in (Storage Queue Data Reader on it): add them by hand" }
            foreach ($q in @($queues | Where-Object { $_ })) {
                $qe = New-Entry 'storageQueue' (Get-KeyFor 'storageQueue' $q.name -Child) $q.name $null
                $qe.Name = $q.name; $qe.Group = $it.group
                $qe.Requires['storage'] = $e.Key
                [void]$qe.Evidence.Add("a queue of $($it.name)")
                $qe.Extra.scope = "$($it.id)/queueServices/default/queues/$($q.name)".ToLower()
                [void]$qe.Hosts.Add("queues__$($q.name)")
            }
        }
        'sqlServer' {
            [void]$e.Hosts.Add("$($it.name).database.windows.net")
            $dbs = Get-AzJson @('sql', 'db', 'list', '-g', $it.group, '-s', $it.name)
            foreach ($d in @($dbs | Where-Object { $_ -and $_.name -ne 'master' })) {
                $de = New-Entry 'sqlDatabase' (Get-KeyFor 'sqlDatabase' $d.name -Child) $d.name $null
                $de.Name = $d.name; $de.Group = $it.group
                $de.Requires['sqlServer'] = $e.Key
                [void]$de.Evidence.Add("a database of $($it.name) ($($d.currentServiceObjectiveName))")
                $de.Extra.server = $it.name.ToLower()
            }
        }
        'serviceBus' {
            [void]$e.Hosts.Add("$($it.name).servicebus.windows.net")
            $queues = @(Get-AzJson @('servicebus', 'queue', 'list', '-g', $it.group, '--namespace-name', $it.name) | Where-Object { $_ } | ForEach-Object { $_.name })
            if ($queues.Count) { $e.Answers['queues'] = $queues -join ', '; [void]$e.Evidence.Add("queues: $($queues -join ', ')") }
            $topics = @(Get-AzJson @('servicebus', 'topic', 'list', '-g', $it.group, '--namespace-name', $it.name) | Where-Object { $_ })
            if ($topics.Count) {
                Add-Note "$($it.name): topics $((@($topics | ForEach-Object { $_.name })) -join ', '): the catalog's Service Bus makes queues only"
                $script:missingTopics = $topics
                $script:missingTopicsOf = $it
            }
        }
        'keyVault' { [void]$e.Hosts.Add("$($it.name).vault.azure.net"); [void]$e.Hosts.Add("vaultname=$($it.name)") }
        'frontDoor' {
            # Its origin: the app whose host name it points at (the apps are read before it).
            $hosts = @()
            foreach ($og in @(Get-AzJson @('afd', 'origin-group', 'list', '-g', $it.group, '--profile-name', $it.name) | Where-Object { $_ })) {
                $hosts += @(Get-AzJson @('afd', 'origin', 'list', '-g', $it.group, '--profile-name', $it.name, '--origin-group-name', $og.name) | Where-Object { $_ } | ForEach-Object { ([string]$_.hostName).ToLower() })
            }
            $app = @($entries | Where-Object { $_.Extra.host -and $hosts -contains $_.Extra.host }) | Select-Object -First 1
            if ($app) { $e.Requires['origin'] = $app.Key; [void]$e.Evidence.Add("in front of $($app.Name)") }
            elseif ($hosts.Count) { [void]$e.Evidence.Add("its origins ($($hosts -join ', ')) aren't apps picked here: its app is asked") }
            if ($hosts.Count -gt 1) { Add-Note "$($it.name): $($hosts.Count) origins; the catalog's Front Door has one (the first app found)" }
            $eps = @(Get-AzJson @('afd', 'endpoint', 'list', '-g', $it.group, '--profile-name', $it.name) | Where-Object { $_ } | ForEach-Object { $_.name })
            if ($eps.Count -and -not @($eps | Where-Object { $_ -eq $it.name.Substring(0, [Math]::Min(46, $it.name.Length)) }).Count) { Add-Note "$($it.name): its endpoint $($eps[0]) isn't named after the profile as the map's is: a dry run shows a new endpoint next to it" }
            $routes = 0
            foreach ($ep in $eps) { foreach ($rt in @(Get-AzJson @('afd', 'route', 'list', '-g', $it.group, '--profile-name', $it.name, '--endpoint-name', $ep) | Where-Object { $_ })) { $routes++; if ($rt.cacheConfiguration) { $e.Answers['cache'] = 'on' } } }
            if ($routes -and -not $e.Answers.Contains('cache')) { $e.Answers['cache'] = 'off' }
        }
        'appServicePlan' { }
        'staticWebApp' {
            $s = Get-AzJson @('staticwebapp', 'show', '-g', $it.group, '-n', $it.name)
            $bp = $s.buildProperties
            if (-not $bp -and $s.properties) { $bp = $s.properties.buildProperties }
            if ($bp -and $bp.appLocation) { $e.Answers['source'] = ([string]$bp.appLocation).Trim('/', ' ') }
            if ($bp -and $bp.outputLocation) { $e.Answers['output'] = ([string]$bp.outputLocation).Trim('/', ' ') }
            if ($s.repositoryUrl) { [void]$e.Evidence.Add("built from $($s.repositoryUrl)$(if ($s.branch) { " ($($s.branch))" })") }
            $e.Extra.location = [string]$it.location
            $e.Extra.host = ([string]$s.defaultHostname).ToLower()
        }
        { $_ -eq 'appService' -or $_ -eq 'functionApp' } {
            $site = Get-AzJson @('webapp', 'show', '-g', $it.group, '-n', $it.name)
            $e.Extra.host = ([string]$site.defaultHostName).ToLower()
            $cfg = Get-AzJson @('webapp', 'config', 'show', '-g', $it.group, '-n', $it.name)
            $plan = Find-ById ([string]$site.serverFarmId)
            $e.Extra.principal = [string]$site.identity.principalId
            if (-not $e.Extra.principal) { [void]$e.Evidence.Add('no managed identity: the catalog''s apps sign in with one') }
            if ([string]$site.kind -notmatch 'linux') { Add-Note "$($it.name): a Windows app; the catalog's apps run on Linux (its runtime is asked)" }
            if ($it.kind -eq 'appService') {
                if ($cfg.linuxFxVersion) { $e.Answers['runtime'] = [string]$cfg.linuxFxVersion }
                $e.Answers['health'] = '-'
                if ($cfg.healthCheckPath) { $e.Answers['health'] = [string]$cfg.healthCheckPath }
                if ($plan) { $e.Requires['appServicePlan'] = $plan.Key }
            } else {
                $f = Get-AzJson @('functionapp', 'show', '-g', $it.group, '-n', $it.name)
                $fc = $f.functionAppConfig
                if (-not $fc -and $f.properties) { $fc = $f.properties.functionAppConfig }
                if ($fc -and $fc.runtime) {
                    $e.Answers['hosting'] = 'flex'
                    $names = @{ 'dotnet-isolated' = 'DOTNET-ISOLATED'; 'node' = 'Node'; 'python' = 'Python'; 'java' = 'Java'; 'powershell' = 'PowerShell' }
                    $rn = [string]$fc.runtime.name
                    if ($names.ContainsKey($rn.ToLower())) { $rn = $names[$rn.ToLower()] }
                    $e.Answers['runtime'] = "$rn|$($fc.runtime.version)"
                    $fp = @($items | Where-Object { $_.id -ieq [string]$site.serverFarmId }) | Select-Object -First 1
                    if ($fp) { $e.Extra.flexPlan = $fp.name }
                } else {
                    $farm = @($items | Where-Object { $_.id -ieq [string]$site.serverFarmId }) | Select-Object -First 1
                    if ($farm -and $farm.kind -eq 'functionPlan') {
                        $e.Answers['hosting'] = 'flex'
                        Add-Note "$($it.name): on Consumption (Y1); the catalog makes Flex Consumption (the app moves to a new plan)"
                    } else {
                        $e.Answers['hosting'] = 'plan'
                        if ($plan) { $e.Requires['appServicePlan'] = $plan.Key }
                    }
                    if ($cfg.linuxFxVersion) { $e.Answers['runtime'] = [string]$cfg.linuxFxVersion }
                }
            }
            # What it uses: its settings and connection strings (by host name; the values stay here).
            $settings = @()
            $as = Get-AzJson @('webapp', 'config', 'appsettings', 'list', '-g', $it.group, '-n', $it.name)
            foreach ($x in @($as | Where-Object { $_ })) { $settings += [pscustomobject]@{ Name = [string]$x.name; Value = [string]$x.value } }
            $cs = Get-AzJson @('webapp', 'config', 'connection-string', 'list', '-g', $it.group, '-n', $it.name)
            foreach ($x in @($cs | Where-Object { $_ })) {
                $v = $x.value
                if ($v -and $v.PSObject.Properties['value']) { $v = $v.value }
                $settings += [pscustomobject]@{ Name = "ConnectionStrings:$($x.name)"; Value = [string]$v }
            }
            if ($null -eq $as) { [void]$e.Evidence.Add("its settings can't be read: what it uses is asked") }
            $e.Extra.settings = $settings
            # A Function App's own storage (AzureWebJobsStorage).
            if ($it.kind -eq 'functionApp') {
                $st = @($settings | Where-Object { $_.Name -match '^AzureWebJobsStorage(__accountName)?$' }) | Select-Object -First 1
                if ($st) {
                    $acc = ''
                    if ($st.Name -match '__accountName$') { $acc = $st.Value } elseif ($st.Value -match 'AccountName=([^;]+)') { $acc = $Matches[1] }
                    $se = @($entries | Where-Object { $_.Kind -eq 'storage' -and $_.Name -ieq $acc }) | Select-Object -First 1
                    if ($se) { $e.Requires['storage'] = $se.Key }
                }
            }
        }
    }
}

# Apps: the resources their settings name, and their identities' role assignments.
$apps = @($entries | Where-Object { @('appService', 'functionApp') -contains $_.Kind })
foreach ($a in $apps) {
    foreach ($s in @($a.Extra.settings)) {
        $v = ([string]$s.Value).ToLower()
        $n = ([string]$s.Name).ToLower()
        foreach ($r in @($entries | Where-Object { $_.Hosts.Count -and $_.Kind -ne 'storageQueue' })) {
            if (@($r.Hosts | Where-Object { $v.Contains($_.ToLower()) }).Count) {
                # A database by its name on the server.
                if ($r.Kind -eq 'sqlServer') {
                    foreach ($d in @($entries | Where-Object { $_.Kind -eq 'sqlDatabase' -and $_.Extra.server -eq $r.Name.ToLower() })) {
                        if ($v -match "(database|initial catalog)\s*=\s*$([regex]::Escape($d.Name.ToLower()))\s*(;|$)") { if ($a.Uses -notcontains $d.Key) { [void]$a.Uses.Add($d.Key); [void]$d.Evidence.Add("$($a.Name): setting $($s.Name)") } }
                    }
                } elseif ($a.Uses -notcontains $r.Key -and -not ($a.Kind -eq 'functionApp' -and $n -match '^azurewebjobsstorage')) { [void]$a.Uses.Add($r.Key); [void]$r.Evidence.Add("$($a.Name): setting $($s.Name)") }
            }
        }
        foreach ($q in @($entries | Where-Object { $_.Kind -eq 'storageQueue' })) {
            if ($v -eq $q.Name.ToLower() -and $n -match 'queue') { if ($a.Uses -notcontains $q.Key) { [void]$a.Uses.Add($q.Key); [void]$q.Evidence.Add("$($a.Name): setting $($s.Name)") } }
        }
        if ($n -match '^(applicationinsights_connection_string|appinsights_instrumentationkey)$') {
            foreach ($ai in @($entries | Where-Object { $_.Kind -eq 'appInsights' -and $_.Extra.ikey -and $v.Contains($_.Extra.ikey.ToLower()) })) { if ($a.Uses -notcontains $ai.Key) { [void]$a.Uses.Add($ai.Key); [void]$ai.Evidence.Add("$($a.Name): setting $($s.Name)") } }
        }
    }
}
$principals = @($apps | Where-Object { $_.Extra.principal })
if ($principals.Count) {
    $assignments = Get-AzJson @('role', 'assignment', 'list', '--all')
    if ($null -eq $assignments) { Add-Note 'the role assignments can''t be read: the apps'' roles are asked' }
    foreach ($ra in @($assignments | Where-Object { $_ })) {
        $a = @($principals | Where-Object { $_.Extra.principal -eq [string]$ra.principalId }) | Select-Object -First 1
        if (-not $a) { continue }
        $scope = ([string]$ra.scope).ToLower()
        $r = Find-ById $scope
        if (-not $r) { $r = @($entries | Where-Object { $_.Extra.scope -eq $scope }) | Select-Object -First 1 }
        if (-not $r -or $r.Key -eq $a.Key) { continue }
        # The Function App's own storage roles come with it.
        if ($a.Kind -eq 'functionApp' -and $r.Kind -eq 'storage' -and $a.Requires['storage'] -eq $r.Key) { continue }
        if ($a.Uses -notcontains $r.Key) { [void]$a.Uses.Add($r.Key) }
        if (-not $a.Roles.Contains($r.Key)) { $a.Roles[$r.Key] = New-Object Collections.ArrayList }
        if ($a.Roles[$r.Key] -notcontains [string]$ra.roleDefinitionName) { [void]$a.Roles[$r.Key].Add([string]$ra.roleDefinitionName) }
        [void]$r.Evidence.Add("$($a.Name): role $($ra.roleDefinitionName)")
    }
}
# Resources in another group than the environment's: shared from it when the kind allows it.
$shareable = @('appInsights', 'appServicePlan', 'keyVault', 'logAnalytics', 'sqlServer')
foreach ($e in @($entries | Where-Object { $_.Group -and $_.Group -ne $MainGroup })) {
    if ($shareable -contains $e.Kind) { [void]$e.Evidence.Add("in $($e.Group): shared from there (the environment's group is $MainGroup)") }
    elseif (@('sqlDatabase', 'storageQueue') -notcontains $e.Kind) { Add-Note "$($e.Name) is in $($e.Group): the map makes a $($e.Kind) in the environment's group ($MainGroup), so a dry run plans a new one there" }
}

# --- missing kinds: what to build, as a prompt -----------------------------------------------------------

$missing = @($picked | Where-Object { $_.state -eq 'missing' })
$missingTypes = New-Object Collections.ArrayList
$promptFile = $Prompts
if (-not $promptFile) { $promptFile = Join-Path $infra 'new-kinds.md' }
$sections = New-Object Collections.ArrayList
function Get-Clean($Node, [int]$Depth) {
    # Properties without anything secret, short enough to read.
    if ($null -eq $Node -or $Depth -gt 6) { return $null }
    if ($Node -is [array]) { return @($Node | Select-Object -First 5 | ForEach-Object { Get-Clean $_ ($Depth + 1) }) }
    if ($Node -is [Management.Automation.PSCustomObject]) {
        $o = [ordered]@{}
        foreach ($p in $Node.PSObject.Properties) {
            if ($p.Name -match '(?i)key|secret|password|connectionstring|token|sas|credential') { $o[$p.Name] = '(left out)'; continue }
            $o[$p.Name] = Get-Clean $p.Value ($Depth + 1)
        }
        return [pscustomobject]$o
    }
    return $Node
}
function Add-Prompt([string]$Type, [string]$Friendly, [string]$Abbr, $Examples, $Detail) {
    $kind = Get-KeyName (($Friendly -replace '\(.*\)', '') -replace '/', ' ')
    $json = ''
    if ($Detail) { $json = (Get-Clean $Detail 0) | ConvertTo-Json -Depth 8 }
    $text = @"
## $Friendly ($Type)

In this project: $((@($Examples | ForEach-Object { "$($_.group)/$($_.name)" })) -join ', ')

``````text
In the LazyBicep repository, add a new kind of resource to the catalog for $Type ($Friendly), made the
way the existing kinds are (read infra/LAZYBICEP.md, "The catalog", and infra/catalog/serviceBus.json,
serviceBus.bicep, keyVault.json and storage.json first):

1. infra/catalog/$kind.json: the blueprint: kind "$kind", title, about, addable, keyDefault, naming
   (type, about, maxLength; abbreviation "$Abbr"), questions (what differs per project), requires (what
   it needs in the map, with its connection), entry (key, title, label, type, armType "$Type", ask,
   param, kind, role, size with its options and default, cost with list prices in EUR), users (the app
   kinds that use it, their roles from infra/catalog/roles.json, the settings they get, without keys or
   connection strings: managed identities and Entra roles), providers, removeOrder.
2. infra/catalog/$kind.bicep: its part of main.bicep (the parameters the entry names; no keys or secrets
   in outputs; Entra / managed identity access), like serviceBus.bicep.
3. infra/naming.json's types (and maxLength) get its naming type; roles.json any role it needs.
4. infra/import.ps1: map $Type to the new kind in `$kindOf (and read what its questions need from the
   resource, as for serviceBus), and take it out of `$missingHints.
5. infra/LAZYBICEP.md: the catalog's table and the import's list; README.md if it is worth a line.
Then check: a test map with the new kind (.\infra\azure-setup.ps1 -AddResource -Kind $kind in a scratch
project), .\infra\generate.ps1, az bicep build --file infra\main.bicep, and a dry run.

What the project has now (Azure's properties, secrets left out):
$json
``````
"@
    [void]$sections.Add($text)
}
foreach ($grp in @($missing | Group-Object { $_.type.ToLower() })) {
    $hint = $missingHints[$grp.Name]
    $friendly = $grp.Group[0].type.Split('/')[-1]
    $abbr = ''
    if ($hint) { $friendly = $hint[0]; $abbr = $hint[1] }
    $detail = Get-AzJson @('resource', 'show', '--ids', $grp.Group[0].id)
    [void]$missingTypes.Add([pscustomobject]@{ type = $grp.Group[0].type; name = $friendly; count = $grp.Count; resources = @($grp.Group | ForEach-Object { $_.name }) })
    Add-Prompt $grp.Group[0].type $friendly $abbr $grp.Group $detail
}
if ($script:missingTopics) {
    [void]$missingTypes.Add([pscustomobject]@{ type = 'Microsoft.ServiceBus/namespaces/topics'; name = 'Service Bus topic (and its subscriptions)'; count = @($script:missingTopics).Count; resources = @($script:missingTopics | ForEach-Object { $_.name }) })
    $subsOf = @{}
    foreach ($t in @($script:missingTopics)) { $subsOf[$t.name] = @(Get-AzJson @('servicebus', 'topic', 'subscription', 'list', '-g', $script:missingTopicsOf.group, '--namespace-name', $script:missingTopicsOf.name, '--topic-name', $t.name) | Where-Object { $_ } | ForEach-Object { $_.name }) }
    Add-Prompt 'Microsoft.ServiceBus/namespaces/topics' 'Service Bus topic (and its subscriptions)' 'sbt' @($script:missingTopics | ForEach-Object { [pscustomobject]@{ group = $script:missingTopicsOf.group; name = "$($script:missingTopicsOf.name)/$($_.name)" } }) ([pscustomobject]@{ namespace = $script:missingTopicsOf.name; topics = $subsOf })
}
if ($sections.Count) {
    $head = @"
# Kinds of resources the catalog doesn't have yet

Found by infra/import.ps1 in $($account.name) ($($ResourceGroup -join ', ')) on $(Get-Date -Format 'yyyy-MM-dd').
Each section has a prompt: paste it to Claude Code in the LazyBicep repository to add the kind, then
update this project's kit (initintoproject.ps1 <project>\infra -Update) and add the resource
(.\infra\azure-setup.ps1 -AddResource, or lazybicep: a).

"@
    [IO.File]::WriteAllText($promptFile, $head + ($sections -join "`n"), (New-Object Text.UTF8Encoding $false))
}

# --- the result -----------------------------------------------------------------------------------------------

$resources = New-Object Collections.ArrayList
$names = [ordered]@{ resourceGroup = $MainGroup }
$groups = [ordered]@{}
$extraNames = New-Object Collections.ArrayList
$kindOrder = @('logAnalytics', 'appInsights', 'storage', 'storageQueue', 'sqlServer', 'sqlDatabase', 'serviceBus', 'keyVault', 'appServicePlan', 'appService', 'functionApp', 'staticWebApp', 'frontDoor')
foreach ($e in @($entries | Sort-Object @{ e = { $kindOrder.IndexOf($_.Kind) } })) {
    $r = [ordered]@{ kind = $e.Kind; key = $e.Key; title = $e.Title }
    if ($e.Answers.Count) { $r.answers = $e.Answers }
    if ($e.Requires.Count) { $r.requires = $e.Requires }
    if ($e.Uses.Count) { $r.uses = @($e.Uses) }
    if ($e.Roles.Count) { $ro = [ordered]@{}; foreach ($k in $e.Roles.Keys) { $ro[$k] = @($e.Roles[$k]) }; $r.roles = $ro }
    $r.evidence = @($e.Evidence)
    $r.azureName = $e.Name
    [void]$resources.Add($r)
    $names[$e.Key] = $e.Name
    if ($e.Group -and $e.Group -ne $MainGroup -and $shareable -contains $e.Kind) { $groups[$e.Key] = $e.Group }
    if ($e.Extra.flexPlan) { [void]$extraNames.Add([ordered]@{ of = $e.Key; connection = 'host'; name = $e.Extra.flexPlan }) }
}
$location = ''
$rgInfo = Get-AzJson @('group', 'show', '-n', $MainGroup)
if ($rgInfo) { $location = [string]$rgInfo.location }
$staticLocation = @($entries | Where-Object { $_.Kind -eq 'staticWebApp' -and $_.Extra.location } | ForEach-Object { ($_.Extra.location -replace '\s', '').ToLower() }) | Select-Object -First 1
$prefix = $prefixParts -join '-'
$projectName = (@($prefixParts | Select-Object -Last 1) | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ''
if (-not $projectName) { $projectName = $MainGroup }
$project = [ordered]@{ name = $projectName; description = "$projectName on Azure (imported from $($ResourceGroup -join ', '))" }
if ($prefix -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $project.prefix = $prefix }
if ($location) { $project.region = $location }
$environment = [ordered]@{
    imported = "$(Get-Date -Format 'yyyy-MM-dd') from $($ResourceGroup -join ', ') ($($account.name)): every question is asked once, with these as the defaults"
    subscriptionId = [string]$account.id
    location = $location
}
if ($staticLocation) { $environment.staticLocation = $staticLocation }
if ($prefix) { $environment.prefix = $prefix }
$environment.names = $names
$environment.groups = $groups

$result = [ordered]@{
    '$comment' = "Suggested by infra/import.ps1 from $($ResourceGroup -join ', ') in $($account.name). A spec for .\infra\azure-setup.ps1 -Init -SpecFile (infra/LAZYBICEP.md, 'A new project'); 'evidence', 'azureName', 'notes', 'missing' and 'environment' are only for reading (the setup writes the environment's answers from them)."
    project = $project
    resources = @($resources)
    notes = @($notes)
    missing = @($missingTypes)
    prompts = $(if ($sections.Count) { $promptFile } else { '' })
    environmentName = $Environment
    environment = $environment
    extraNames = @($extraNames)
    scanned = [ordered]@{ subscription = [string]$account.name; groups = @($ResourceGroup); resources = $items.Count; picked = $picked.Count }
}
$json = $result | ConvertTo-Json -Depth 12
if ($Out) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($Out), $json, (New-Object Text.UTF8Encoding $false)) }
if ($PassThru) { return ($json | ConvertFrom-Json) }

# --- the report ---------------------------------------------------------------------------------------------

Show-Author
Write-Host "  $($account.name): $($ResourceGroup -join ', ')   ($($items.Count) resources, environment $Environment, its group $MainGroup)" -ForegroundColor White
Write-Host ''
Write-Host '  PROJECT' -ForegroundColor White
Write-Host "    $($project.name)   prefix $($project.prefix)   $location" -ForegroundColor Green
Write-Host ''
Write-Host '  SUGGESTED RESOURCES' -ForegroundColor White
foreach ($r in $resources) {
    Write-Host ("    {0,-15} {1,-16} {2}" -f $r.kind, $r.key, $r.azureName) -ForegroundColor Green
    if ($r.answers) { Write-Host "                    $((@($r.answers.Keys | ForEach-Object { "$_=$($r.answers[$_])" })) -join '  ')" -ForegroundColor DarkGray }
    if ($r.uses) { Write-Host "                    uses $($r.uses -join ', ')" -ForegroundColor DarkGray }
    foreach ($x in $r.evidence) { Write-Host "                    - $x" -ForegroundColor DarkGray }
}
if ($missingTypes.Count) {
    Write-Host ''
    Write-Host '  NOT IN THE CATALOG' -ForegroundColor White
    foreach ($m in $missingTypes) { Write-Host "    ! $($m.name) ($($m.type)): $($m.resources -join ', ')" -ForegroundColor Yellow }
    Write-Host "    A prompt to add each: $promptFile (paste it to Claude Code in the LazyBicep repository)" -ForegroundColor Yellow
}
if ($notes.Count) {
    Write-Host ''
    Write-Host '  NOTES' -ForegroundColor White
    foreach ($n in $notes) { Write-Host "    ! $n" -ForegroundColor Yellow }
}
Write-Host ''
Write-Host '  NEXT' -ForegroundColor White
Write-Host '    .\infra\azure-setup.ps1 -Init     then azure: offers each of these, then the usual questions' -ForegroundColor Green
Write-Host ''
