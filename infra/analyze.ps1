#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyBicep  -  analyze.ps1                                              ║
#  ║   Suggests a new project's resources from its solution                   ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyBicep  -  https://github.com/netmedia/lazybicep          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
.SYNOPSIS
LazyBicep by Netmedia: looks through a project's folders and suggests the resources of its map (a spec,
the same as -Init -SpecFile takes), each with what it was found from.

.AUTHOR
Netmedia  |  https://netmedia.agency  |  netmedia@netmedia.hr

.DESCRIPTION
Reads, without running anything:
  .NET projects (.csproj)   Web -> App Service, Functions -> Function App, Blazor WebAssembly -> Static
                            Web App; tests, libraries, workers and consoles are noted, not deployed
  package.json              React, Angular, Vue, Svelte, Next, Nuxt, Astro... -> Static Web App (with the
                            folder its build writes); Express, Nest, Fastify... -> App Service (Node);
                            @azure/functions -> Function App
  requirements.txt and      Django, Flask, FastAPI -> App Service (Python); azure-functions -> Function
  pyproject.toml            App
  appsettings*.json,        connection strings and settings: SQL Server, Service Bus, storage,
  local.settings.json, .env Application Insights, Key Vault (Redis, Cosmos DB, PostgreSQL... are noted)
  packages and code         EF Core / SqlClient, Azure SDKs, ServiceBusTrigger / QueueTrigger / senders
                            (the queues' names), GetConnectionString (the databases' names),
                            MapHealthChecks (the health check path); through project references too

A database's key comes from its connection string's name, so the setting the map gives the app
(ConnectionStrings__<Key>) is the one the app reads. infra/azure-setup.ps1 -Init (and lazybicep's New
project) runs this when asked to analyze, offers every suggestion with what it was found from, and asks
the usual questions with these answers as their defaults.

.PARAMETER Path
The folder to look through. Default: the project's root (the folder above infra).

.PARAMETER Out
Writes the suggestion as a spec file (for .\infra\azure-setup.ps1 -Init -SpecFile <file>).

.PARAMETER PassThru
Returns the suggestion as an object, without output (for infra/azure-setup.ps1).

.PARAMETER Help
Shows the usage guide and exits.

.EXAMPLE
.\infra\analyze.ps1

.EXAMPLE
.\infra\analyze.ps1 -Out spec.json

.NOTES
LazyBicep is a Netmedia product: https://netmedia.agency, netmedia@netmedia.hr,
https://github.com/netmedia/lazybicep.

.LINK
infra/LAZYBICEP.md
#>
[CmdletBinding()]
param(
    [string]$Path,
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
    $title = 'LazyBicep  -  analyze.ps1'
    Write-Host ''
    Write-Host "  $([char]0x256D)$hLine$([char]0x256E)" -ForegroundColor Cyan
    Row ''
    Row "$esc[1m$title$esc[0m" $title 'Cyan'
    Row 'Suggests a new project''s resources from its solution' -color 'White'
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
    & $g '  .\infra\analyze.ps1  [-Path <folder>]  [-Out <spec.json>]'
    & $d '  Looks through the project (the folder above infra) and suggests its resources:'
    & $d '  the apps from the .NET projects, package.json and Python projects; SQL databases,'
    & $d '  Service Bus and its queues, storage, queues, Key Vault and Application Insights'
    & $d '  from connection strings, packages and code. Runs nothing, changes nothing.'
    Write-Host ''
    & $b 'OPTIONS'
    & $y '  -Path <folder>'
    & $d '    The folder to look through (default: the project''s root).'
    & $y '  -Out <spec.json>'
    & $d '    Writes the suggestion as a spec file: .\infra\azure-setup.ps1 -Init -SpecFile'
    & $d '    takes it as it is (edit it first to change what it suggests).'
    & $y '  -Help  (-h)'
    & $d '    Shows this guide and exits.'
    Write-Host ''
    & $b 'USUALLY'
    & $g '  .\infra\azure-setup.ps1 -Init -Analyze      (or lazybicep: n, then analyze)'
    & $d '    runs this, offers every suggestion (with what it was found from) and asks the'
    & $d '    usual questions with its answers as the defaults.'
    Write-Host ''
    & $d '  More: infra\LAZYBICEP.md ("A new project")'
    Write-Host ''
}
if ($Help) { Show-Author; Show-Usage; exit 0 }

if (-not $Path) { $Path = Split-Path $infra -Parent }
$Path = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
if (-not (Test-Path $Path -PathType Container)) { throw "No folder $Path." }

# --- the files ----------------------------------------------------------------------------------------

# Build output, dependencies, tools' folders and the kit itself are not the project's code.
$skipDirs = @('node_modules', 'bin', 'obj', 'packages', 'dist', 'build', 'out', 'coverage', 'TestResults', 'artifacts', 'publish', 'wwwroot', '__pycache__', 'venv', 'site-packages')
function Get-AllFiles {
    $files = New-Object Collections.ArrayList
    $stack = New-Object Collections.Stack
    $stack.Push(@($Path, 0))
    while ($stack.Count) {
        $item = $stack.Pop()
        $dir = [string]$item[0]
        if ($dir -ieq $infra) { continue }
        try { foreach ($f in [IO.Directory]::GetFiles($dir)) { [void]$files.Add($f) } } catch { continue }
        if ($item[1] -ge 12) { continue }
        foreach ($d in [IO.Directory]::GetDirectories($dir)) {
            $n = Split-Path $d -Leaf
            if ($n.StartsWith('.') -or $skipDirs -contains $n) { continue }
            $stack.Push(@($d, ($item[1] + 1)))
        }
    }
    return , $files
}
function Get-Rel([string]$Full) {
    $r = $Full.Substring([Math]::Min($Full.Length, $Path.Length)).TrimStart('\', '/').Replace('\', '/')
    if (-not $r) { return '.' }
    return $r
}
# appsettings.json may have comments and trailing commas.
function Read-LooseJson([string]$File) {
    $t = ''
    try { $t = [IO.File]::ReadAllText($File) } catch { return $null }
    try { return ($t | ConvertFrom-Json) } catch { }
    $t = [regex]::Replace($t, '(?s)/\*.*?\*/', '')
    $t = [regex]::Replace($t, '(?m)^\s*//.*$', '')
    $t = [regex]::Replace($t, ',(\s*[}\]])', '$1')
    try { return ($t | ConvertFrom-Json) } catch { return $null }
}
# Every string of a JSON document with its path (ConnectionStrings:Erp, Values:AzureWebJobsStorage...).
function Get-Leaves($Node, [string]$Prefix, $Into) {
    if ($null -eq $Node) { return }
    if ($Node -is [string]) { [void]$Into.Add([pscustomobject]@{ Path = $Prefix; Value = $Node }); return }
    if ($Node -is [Management.Automation.PSCustomObject]) {
        foreach ($p in $Node.PSObject.Properties) {
            $sub = $p.Name
            if ($Prefix) { $sub = "${Prefix}:$($p.Name)" }
            Get-Leaves $p.Value $sub $Into
        }
    } elseif ($Node -is [array]) {
        for ($i = 0; $i -lt $Node.Count; $i++) { Get-Leaves $Node[$i] "${Prefix}:$i" $Into }
    }
}
# A map key from a name: letters and digits, starting with a small letter (ErpDb -> erpDb, orders-queue
# -> ordersQueue, ERP_DB -> erpDb).
function Get-KeyName([string]$Name) {
    $parts = @([regex]::Split($Name, '[^A-Za-z0-9]+') | Where-Object { $_ })
    if (-not $parts.Count) { return 'app' }
    $key = ''
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $p = $parts[$i]
        if ($p -cmatch '^[A-Z0-9]+$' -and $p.Length -gt 1) { $p = $p.Substring(0, 1) + $p.Substring(1).ToLower() }
        if ($i -eq 0) { $p = $p.Substring(0, 1).ToLower() + $p.Substring(1) } else { $p = $p.Substring(0, 1).ToUpper() + $p.Substring(1) }
        $key += $p
    }
    if ($key -notmatch '^[a-z]') { $key = 'x' + $key }
    return $key
}
$script:keys = New-Object Collections.Generic.HashSet[string]
function Get-FreeKey([string]$Want) {
    $k = $Want
    for ($i = 2; $script:keys.Contains($k); $i++) { $k = "$Want$i" }
    [void]$script:keys.Add($k)
    return $k
}

# --- what a package, a setting or a line of code says --------------------------------------------------

# Signals: sql, serviceBus, blob, queue, keyVault, appInsights (the catalog's); postgres, mysql, cosmos,
# mongo, redis, eventHubs, signalr (noted: no kind in the catalog).
$dotnetRules = [ordered]@{
    sql         = '^(microsoft\.entityframeworkcore\.sqlserver.*|microsoft\.data\.sqlclient|system\.data\.sqlclient|hangfire\.sqlserver|efcore\.bulkextensions\.sqlserver|linq2db\.sqlserver)$'
    serviceBus  = '^(azure\.messaging\.servicebus|microsoft\.azure\.servicebus|microsoft\.azure\.functions\.worker\.extensions\.servicebus|microsoft\.azure\.webjobs\.extensions\.servicebus|masstransit\.azure\.servicebus\.core|nservicebus\.transport\.azureservicebus|rebus\.azureservicebus)$'
    blob        = '^(azure\.storage\.blobs|azure\.data\.tables|azure\.storage\.files\..*|windowsazure\.storage|microsoft\.azure\.storage\..*|microsoft\.azure\.functions\.worker\.extensions\.storage\.blobs|microsoft\.azure\.functions\.worker\.extensions\.tables)$'
    queue       = '^(azure\.storage\.queues|microsoft\.azure\.functions\.worker\.extensions\.storage\.queues|microsoft\.azure\.webjobs\.extensions\.storage\.queues)$'
    keyVault    = '^(azure\.security\.keyvault\..*|azure\.extensions\.aspnetcore\.configuration\.secrets|microsoft\.extensions\.configuration\.azurekeyvault)$'
    appInsights = '^(microsoft\.applicationinsights.*|azure\.monitor\.opentelemetry\..*|microsoft\.azure\.functions\.worker\.applicationinsights)$'
    postgres    = '^(npgsql.*)$'
    mysql       = '^(pomelo\..*|mysql\..*|mysqlconnector)$'
    cosmos      = '^(microsoft\.azure\.cosmos|microsoft\.entityframeworkcore\.cosmos)$'
    mongo       = '^(mongodb\.driver)$'
    redis       = '^(stackexchange\.redis|microsoft\.extensions\.caching\.stackexchangeredis)$'
    eventHubs   = '^(azure\.messaging\.eventhubs.*|microsoft\.azure\.functions\.worker\.extensions\.eventhubs)$'
    signalr     = '^(microsoft\.azure\.signalr.*)$'
}
$nodeRules = [ordered]@{
    sql = '^(mssql|tedious)$'; serviceBus = '^@azure/service-bus$'; blob = '^(@azure/storage-blob|@azure/data-tables)$'; queue = '^@azure/storage-queue$'
    keyVault = '^@azure/keyvault-.*$'; appInsights = '^(applicationinsights|@azure/monitor-opentelemetry)$'; postgres = '^(pg|postgres)$'; mysql = '^(mysql|mysql2)$'
    cosmos = '^@azure/cosmos$'; mongo = '^(mongodb|mongoose)$'; redis = '^(redis|ioredis)$'; eventHubs = '^@azure/event-hubs$'
}
$pythonRules = [ordered]@{
    sql = '^(pyodbc|pymssql|mssql-django)$'; serviceBus = '^azure-servicebus$'; blob = '^(azure-storage-blob|azure-data-tables)$'; queue = '^azure-storage-queue$'
    keyVault = '^azure-keyvault-.*$'; appInsights = '^(azure-monitor-opentelemetry.*|opencensus-ext-azure|applicationinsights)$'; postgres = '^(psycopg|psycopg2|psycopg2-binary|asyncpg)$'
    mysql = '^(mysqlclient|pymysql)$'; cosmos = '^azure-cosmos$'; mongo = '^(pymongo|motor)$'; redis = '^redis$'; eventHubs = '^azure-eventhub$'
}
$signalNames = @{
    sql = 'SQL Server'; serviceBus = 'Service Bus'; blob = 'Blob/Table storage'; queue = 'Storage queues'; keyVault = 'Key Vault'; appInsights = 'Application Insights'
    postgres = 'PostgreSQL'; mysql = 'MySQL'; cosmos = 'Cosmos DB'; mongo = 'MongoDB'; redis = 'Redis'; eventHubs = 'Event Hubs'; signalr = 'Azure SignalR'
}
$catalogSignals = @('sql', 'serviceBus', 'blob', 'queue', 'keyVault', 'appInsights')

# What a setting is, from its value (or its name).
function Get-SettingKind([string]$Name, [string]$Value) {
    $v = $Value
    if ($v -match 'Endpoint=sb://|\.servicebus\.windows\.net') { return 'serviceBus' }
    if ($v -match 'AccountEndpoint=|\.documents\.azure\.com') { return 'cosmos' }
    if ($v -match 'DefaultEndpointsProtocol=|AccountName=|UseDevelopmentStorage=true|\.(blob|queue|table)\.core\.windows\.net') { return 'storage' }
    if ($v -match 'InstrumentationKey=') { return 'appInsights' }
    if ($v -match '\.vault\.azure\.net') { return 'keyVault' }
    if ($v -match '\.redis\.cache\.windows\.net|abortConnect=|:63(79|80)\b') { return 'redis' }
    if ($v -match '^mongodb(\+srv)?://') { return 'mongo' }
    if ($v -match '^postgres(ql)?://|(^|;)\s*Host\s*=') { return 'postgres' }
    if ($v -match '^mysql://') { return 'mysql' }
    if ($v -match '^(sqlserver|mssql)://') { return 'sql' }
    if ($v -match '(^|;)\s*(Server|Data Source|Address|Addr)\s*=' -and $v -match '(^|;)\s*(Database|Initial Catalog)\s*=') { return 'sql' }
    if ($v -match '(^|;)\s*(Server|Data Source)\s*=\s*(\(localdb\)|tcp:|\.\\|\.;|localhost)') { return 'sql' }
    if ($Name -match 'APPLICATIONINSIGHTS_CONNECTION_STRING|ApplicationInsights:(ConnectionString|InstrumentationKey)') { return 'appInsights' }
    if ($Name -match 'KeyVault|VaultUri|VaultUrl|VaultName') { return 'keyVault' }
    return $null
}

# --- the projects -------------------------------------------------------------------------------------

function New-Project([string]$File, [string]$Lang, [string]$Name) {
    $dir = Split-Path $File -Parent
    return [pscustomobject]@{
        File = $File; Dir = $dir; Rel = (Get-Rel $dir); Name = $Name; Lang = $Lang; Type = 'library'; Kind = $null
        Runtime = ''; Output = ''; Health = ''; Ver = ''; Packages = (New-Object Collections.ArrayList); Refs = (New-Object Collections.ArrayList)
        Signals = @{}; ConnNames = (New-Object Collections.ArrayList); Settings = (New-Object Collections.ArrayList); Values = @{}
        SbSend = (New-Object Collections.ArrayList); SbReceive = (New-Object Collections.ArrayList)
        SqSend = (New-Object Collections.ArrayList); SqReceive = (New-Object Collections.ArrayList)
        Code = (New-Object Collections.ArrayList); Notes = (New-Object Collections.ArrayList); Key = ''; Title = ''
    }
}
function Add-Signal($P, [string]$Signal, [string]$Evidence) {
    if (-not $P.Signals.ContainsKey($Signal)) { $P.Signals[$Signal] = New-Object Collections.ArrayList }
    if ($P.Signals[$Signal] -notcontains $Evidence) { [void]$P.Signals[$Signal].Add($Evidence) }
}
function Add-Unique($List, [string]$Value) { if ($Value -and $List -notcontains $Value) { [void]$List.Add($Value) } }
function Test-Rules($P, $Rules, [string[]]$Names) {
    foreach ($n in $Names) {
        foreach ($s in $Rules.Keys) { if ($n.ToLower() -match $Rules[$s]) { Add-Signal $P $s "$($P.Rel): $n" } }
    }
}
function Get-XmlValue([xml]$Xml, [string]$Name) {
    $n = $Xml.SelectSingleNode("//*[local-name()='$Name']")
    if ($n) { return $n.InnerText.Trim() }
    return ''
}

$all = Get-AllFiles
$notes = New-Object Collections.ArrayList
$projects = New-Object Collections.ArrayList

# .NET
$propsCache = @{}
foreach ($f in @($all | Where-Object { $_ -match '\.(cs|fs|vb)proj$' })) {
    $name = [IO.Path]::GetFileNameWithoutExtension($f)
    $p = New-Project $f 'dotnet' $name
    try { $proj = [xml][IO.File]::ReadAllText($f) } catch { Add-Unique $notes "$(Get-Rel $f): can't read it ($($_.Exception.Message))"; continue }
    $sdk = [string]$proj.DocumentElement.GetAttribute('Sdk')
    if (-not $sdk) { $s = $proj.SelectSingleNode("/*[local-name()='Project']/*[local-name()='Sdk']"); if ($s) { $sdk = [string]$s.GetAttribute('Name') } }
    $tfm = Get-XmlValue $proj 'TargetFramework'
    if (-not $tfm) { $tfm = ((Get-XmlValue $proj 'TargetFrameworks').Split(';') | Where-Object { $_ } | Sort-Object { if ($_ -match '(\d+)\.(\d+)') { [int]$Matches[1] * 100 + [int]$Matches[2] } else { 0 } } -Descending | Select-Object -First 1) }
    # The framework may come from a Directory.Build.props above it.
    for ($d = $p.Dir; -not $tfm -and $d -and $d.Length -ge $Path.Length; $d = Split-Path $d -Parent) {
        $props = Join-Path $d 'Directory.Build.props'
        if (-not $propsCache.ContainsKey($props)) {
            $propsCache[$props] = ''
            if (Test-Path $props) { try { $propsCache[$props] = Get-XmlValue ([xml][IO.File]::ReadAllText($props)) 'TargetFramework' } catch { } }
        }
        $tfm = $propsCache[$props]
    }
    if ($tfm -match '^net(coreapp)?(\d+\.\d+)') { $p.Ver = $Matches[2] }
    $netfx = (-not $sdk) -and ((Get-XmlValue $proj 'TargetFrameworkVersion') -match '^v4')
    foreach ($r in @($proj.SelectNodes("//*[local-name()='PackageReference']"))) {
        $id = [string]$r.GetAttribute('Include')
        if (-not $id) { $id = [string]$r.GetAttribute('Update') }
        Add-Unique $p.Packages $id
    }
    foreach ($r in @($proj.SelectNodes("//*[local-name()='ProjectReference']"))) {
        $inc = [string]$r.GetAttribute('Include')
        if ($inc) { Add-Unique $p.Refs ([IO.Path]::GetFullPath((Join-Path $p.Dir $inc))) }
    }
    $pk = @($p.Packages | ForEach-Object { $_.ToLower() })
    $isTest = (Get-XmlValue $proj 'IsTestProject') -eq 'true' -or @($pk | Where-Object { $_ -match '^(microsoft\.net\.test\.sdk|xunit.*|nunit.*|mstest.*)$' }).Count
    $isFunc = (Get-XmlValue $proj 'AzureFunctionsVersion') -or @($pk | Where-Object { $_ -match '^(microsoft\.azure\.functions\.worker.*|microsoft\.net\.sdk\.functions)$' }).Count
    $exe = (Get-XmlValue $proj 'OutputType') -match 'exe'
    if ($isTest) { $p.Type = 'test' }
    elseif ($netfx) { $p.Type = 'netfx' }
    elseif ($isFunc) {
        $p.Type = 'functions'; $p.Kind = 'functionApp'; $p.Runtime = "DOTNET-ISOLATED|$($p.Ver)"
        if ($pk -contains 'microsoft.net.sdk.functions') { [void]$p.Notes.Add('the in-process model (Microsoft.NET.Sdk.Functions): Flex Consumption runs only the isolated worker; migrate it, or choose hosting "plan"') }
    }
    elseif ($sdk -match 'BlazorWebAssembly') {
        $p.Type = 'wasm'; $p.Kind = 'staticWebApp'; $p.Output = 'wwwroot'
        [void]$p.Notes.Add('Blazor WebAssembly: the generated workflow builds with npm; change its build step to dotnet publish (the site is the publish folder''s wwwroot)')
    }
    elseif ($sdk -match 'Microsoft\.NET\.Sdk\.Web') { $p.Type = 'web'; $p.Kind = 'appService'; $p.Runtime = "DOTNETCORE|$($p.Ver)" }
    elseif ($sdk -match 'Microsoft\.NET\.Sdk\.Worker') { $p.Type = 'worker' }
    elseif ($exe) { $p.Type = 'console' }
    if ($p.Kind -and -not $p.Ver) { [void]$p.Notes.Add("no target framework found: the runtime is asked"); $p.Runtime = '' }
    Test-Rules $p $dotnetRules @($p.Packages)
    [void]$projects.Add($p)
}

# The code of each .NET project: the files in its folder that no deeper project owns.
$byDepth = @($projects | Sort-Object { $_.Dir.Length } -Descending)
foreach ($f in @($all | Where-Object { $_ -like '*.cs' })) {
    foreach ($p in $byDepth) { if ($f.StartsWith($p.Dir + '\', [StringComparison]::OrdinalIgnoreCase)) { [void]$p.Code.Add($f); break } }
}
foreach ($p in $projects) {
    foreach ($f in $p.Code) {
        $t = ''
        try { $t = [IO.File]::ReadAllText($f) } catch { continue }
        $rel = Get-Rel $f
        foreach ($m in [regex]::Matches($t, 'ServiceBusTrigger\(\s*"([^"]+)"\s*,\s*"([^"]+)"')) { Add-Unique $notes "${rel}: Service Bus topic $($m.Groups[1].Value) (subscription $($m.Groups[2].Value)): the catalog makes queues; add the topic by hand" }
        foreach ($m in [regex]::Matches($t, 'ServiceBusTrigger\(\s*"([^"]+)"\s*[,)](?!\s*")')) { Add-Unique $p.SbReceive $m.Groups[1].Value; Add-Signal $p 'serviceBus' "${rel}: ServiceBusTrigger(`"$($m.Groups[1].Value)`")" }
        foreach ($m in [regex]::Matches($t, '(CreateProcessor|CreateReceiver)\(\s*"([^"]+)"')) { Add-Unique $p.SbReceive $m.Groups[2].Value; Add-Signal $p 'serviceBus' "${rel}: $($m.Groups[1].Value)(`"$($m.Groups[2].Value)`")" }
        foreach ($m in [regex]::Matches($t, '(CreateSender\(|ServiceBusOutput\()\s*"([^"]+)"')) { Add-Unique $p.SbSend $m.Groups[2].Value; Add-Signal $p 'serviceBus' "${rel}: $($m.Groups[1].Value)`"$($m.Groups[2].Value)`")" }
        foreach ($m in [regex]::Matches($t, 'QueueTrigger\(\s*"([^"]+)"')) { Add-Unique $p.SqReceive $m.Groups[1].Value; Add-Signal $p 'queue' "${rel}: QueueTrigger(`"$($m.Groups[1].Value)`")" }
        foreach ($m in [regex]::Matches($t, '(QueueOutput\(|GetQueueClient\()\s*"([^"]+)"')) { Add-Unique $p.SqSend $m.Groups[2].Value; Add-Signal $p 'queue' "${rel}: $($m.Groups[1].Value)`"$($m.Groups[2].Value)`")" }
        foreach ($m in [regex]::Matches($t, '(GetConnectionString\(\s*"|ConnectionStrings:)([A-Za-z0-9_.\-]+)')) { Add-Unique $p.ConnNames $m.Groups[2].Value }
        foreach ($m in [regex]::Matches($t, '(MapHealthChecks|UseHealthChecks)\(\s*"([^"]+)"')) { if (-not $p.Health) { $p.Health = $m.Groups[2].Value } }
        if ($t -match 'UseSqlServer\(|UseAzureSql\(|new SqlConnection\(') { Add-Signal $p 'sql' "${rel}: $($Matches[0].TrimEnd([char]40))" }
        if ($t -match 'AddAzureKeyVault\(|new SecretClient\(') { Add-Signal $p 'keyVault' "${rel}: $($Matches[0].TrimEnd([char]40))" }
        if ($t -match 'AddApplicationInsightsTelemetry\w*\(|UseAzureMonitor\(|ConfigureFunctionsApplicationInsights\(') { Add-Signal $p 'appInsights' "${rel}: $($Matches[0].TrimEnd([char]40))" }
        if ($t -match 'new BlobServiceClient\(|BlobTrigger\(|new TableServiceClient\(') { Add-Signal $p 'blob' "${rel}: $($Matches[0].TrimEnd([char]40))" }
    }
}

# Node: front ends, servers, functions.
$frontEnds = [ordered]@{ 'next' = 'out'; 'nuxt' = '.output/public'; '@angular/core' = ''; 'react-scripts' = 'build'; '@sveltejs/kit' = 'build'; 'astro' = 'dist'; 'gatsby' = 'public'; 'vite' = 'dist'; '@vue/cli-service' = 'dist'; 'react' = 'dist'; 'vue' = 'dist'; 'svelte' = 'dist'; 'preact' = 'dist'; 'solid-js' = 'dist'; 'lit' = 'dist' }
$nodeServers = @('express', 'fastify', '@nestjs/core', 'koa', '@hapi/hapi', 'hono', 'restify')
foreach ($f in @($all | Where-Object { (Split-Path $_ -Leaf) -eq 'package.json' })) {
    $j = Read-LooseJson $f
    if (-not $j) { continue }
    $dir = Split-Path $f -Parent
    # A front end inside a .NET web project (an SPA template's ClientApp) is built and served by it.
    $owner = @($projects | Where-Object { $_.Lang -eq 'dotnet' -and $_.Kind -eq 'appService' -and ($dir -ieq $_.Dir -or $dir.StartsWith($_.Dir + '\', [StringComparison]::OrdinalIgnoreCase)) }) | Select-Object -First 1
    $deps = @()
    foreach ($section in @($j.dependencies, $j.devDependencies)) { if ($section) { $deps += @($section.PSObject.Properties | ForEach-Object { $_.Name }) } }
    if (-not $deps.Count) { continue }
    $name = [string]$j.name
    if (-not $name) { $name = Split-Path $dir -Leaf }
    $name = $name -replace '^@[^/]+/', ''
    if ($owner) { Add-Unique $notes "$(Get-Rel $dir): a front end built and served by $($owner.Name) (not a resource of its own)"; continue }
    $p = New-Project $f 'node' $name
    $major = ''
    if ($j.engines -and [string]$j.engines.node -match '(\d{2})') { $major = $Matches[1] }
    if ($deps -contains '@azure/functions' -and (Test-Path (Join-Path $dir 'host.json'))) {
        $p.Type = 'functions'; $p.Kind = 'functionApp'
        if (-not $major) { $major = '22' }
        $p.Runtime = "Node|$major"
    } else {
        $fe = @($frontEnds.Keys | Where-Object { $deps -contains $_ }) | Select-Object -First 1
        if ($fe) {
            $p.Type = 'frontend'; $p.Kind = 'staticWebApp'; $p.Output = $frontEnds[$fe]
            if ($fe -eq 'next') { [void]$p.Notes.Add('Next.js: Static Web Apps hosts a static export (output: ''export'' writes out/); a Next.js server needs an App Service (Node)') }
            if ($fe -eq 'nuxt') { [void]$p.Notes.Add('Nuxt: Static Web Apps hosts nuxt generate (.output/public); a Nuxt server needs an App Service (Node)') }
            if ($fe -eq '@angular/core') {
                $p.Output = "dist/$name"
                $aj = Read-LooseJson (Join-Path $dir 'angular.json')
                if ($aj -and $aj.projects) {
                    $first = @($aj.projects.PSObject.Properties)[0]
                    $build = $first.Value.architect.build
                    $op = $build.options.outputPath
                    if ($op -is [string]) { $p.Output = $op } elseif ($op -and $op.base) { $p.Output = [string]$op.base } else { $p.Output = "dist/$($first.Name)" }
                    # The application builder (Angular 17+) writes the site into browser/.
                    if ([string]$build.builder -match ':application$' -and -not ($op -and $op.browser -eq '')) { $p.Output += '/browser' }
                }
            }
            if ((Test-Path (Join-Path $dir 'yarn.lock')) -or (Test-Path (Join-Path $dir 'pnpm-lock.yaml'))) { [void]$p.Notes.Add('yarn/pnpm: the generated workflow runs npm ci and npm run build; change its build step') }
        } elseif (@($nodeServers | Where-Object { $deps -contains $_ }).Count) {
            $p.Type = 'server'; $p.Kind = 'appService'; $p.Health = '-'
            if (-not $major) { $major = '22' }
            $p.Runtime = "NODE|$major-lts"
        } else { continue }
    }
    $p.Title = $name
    Test-Rules $p $nodeRules $deps
    [void]$projects.Add($p)
}

# Python
foreach ($f in @($all | Where-Object { @('requirements.txt', 'pyproject.toml') -contains (Split-Path $_ -Leaf) })) {
    $dir = Split-Path $f -Parent
    if (@($projects | Where-Object { $_.Lang -eq 'python' -and $_.Dir -ieq $dir }).Count) { continue }
    $text = ''
    foreach ($n in @('requirements.txt', 'pyproject.toml')) { if (Test-Path (Join-Path $dir $n)) { $text += [IO.File]::ReadAllText((Join-Path $dir $n)) + "`n" } }
    $names = @([regex]::Matches($text.ToLower(), '[a-z0-9][a-z0-9_.\-]*') | ForEach-Object { $_.Value } | Select-Object -Unique)
    $p = New-Project $f 'python' (Split-Path $dir -Leaf)
    if ($names -contains 'azure-functions' -and ((Test-Path (Join-Path $dir 'function_app.py')) -or (Test-Path (Join-Path $dir 'host.json')))) { $p.Type = 'functions'; $p.Kind = 'functionApp'; $p.Runtime = 'Python|3.11' }
    elseif (@($names | Where-Object { @('django', 'flask', 'fastapi') -contains $_ }).Count) { $p.Type = 'server'; $p.Kind = 'appService'; $p.Runtime = 'PYTHON|3.12'; $p.Health = '-' }
    else { continue }
    Test-Rules $p $pythonRules $names
    [void]$projects.Add($p)
}

# Settings: appsettings*.json and local.settings.json of a .NET project, .env of the others.
foreach ($p in $projects) {
    $own = @($all | Where-Object { (Split-Path $_ -Parent) -ieq $p.Dir })
    foreach ($f in @($own | Where-Object { (Split-Path $_ -Leaf) -match '^(appsettings.*\.json|local\.settings\.json)$' })) {
        $j = Read-LooseJson $f
        if (-not $j) { continue }
        $rel = Get-Rel $f
        $leaves = New-Object Collections.ArrayList
        Get-Leaves $j '' $leaves
        foreach ($l in $leaves) {
            if ($l.Path -match '^Values:(.+)$') { $p.Values[$Matches[1]] = $l.Value }
            # A Function App's own storage: the catalog's functionApp needs a storage account anyway.
            if ($l.Path -match '^Values:(AzureWebJobsStorage|FUNCTIONS_.*|AzureWebJobsDashboard)$') { continue }
            $conn = ''
            if ($l.Path -match '^ConnectionStrings:([^:]+)$') { $conn = $Matches[1] }
            $kind = Get-SettingKind $l.Path $l.Value
            if (-not $kind -and -not $conn) { continue }
            $db = ''
            if ($kind -eq 'sql' -and $l.Value -match '(?:Database|Initial Catalog)\s*=\s*([^;]+)') { $db = $Matches[1].Trim() }
            [void]$p.Settings.Add([pscustomobject]@{ Kind = $kind; Name = $conn; Db = $db; Where = "${rel}: $($l.Path)" })
            if ($kind -eq 'storage') { $kind = 'blob' }
            if ($kind) { Add-Signal $p $kind "${rel}: $($l.Path)" }
        }
    }
    foreach ($f in @($own | Where-Object { (Split-Path $_ -Leaf) -match '^\.env' })) {
        $rel = Get-Rel $f
        foreach ($line in [IO.File]::ReadAllLines($f)) {
            if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { continue }
            $n = $Matches[1]; $v = $Matches[2].Trim().Trim('"', "'")
            $kind = Get-SettingKind $n $v
            if (-not $kind) { continue }
            $db = ''
            if ($kind -eq 'sql' -and $v -match '(?:Database|Initial Catalog)\s*=\s*([^;]+)') { $db = $Matches[1].Trim() }
            [void]$p.Settings.Add([pscustomobject]@{ Kind = $kind; Name = ''; Db = $db; Where = "${rel}: $n" })
            if ($kind -eq 'storage') { $kind = 'blob' }
            Add-Signal $p $kind "${rel}: $n"
        }
    }
}

# --- the apps, with what their references bring --------------------------------------------------------

$byFile = @{}
foreach ($p in $projects) { if ($p.Lang -eq 'dotnet') { $byFile[$p.File.ToLower()] = $p } }
function Get-Closure($P) {
    $seen = @{}
    $todo = New-Object Collections.Queue
    foreach ($r in $P.Refs) { $todo.Enqueue($r) }
    $out = New-Object Collections.ArrayList
    while ($todo.Count) {
        $r = ([string]$todo.Dequeue()).ToLower()
        if ($seen.ContainsKey($r) -or -not $byFile.ContainsKey($r)) { continue }
        $seen[$r] = $true
        $lib = $byFile[$r]
        [void]$out.Add($lib)
        foreach ($rr in $lib.Refs) { $todo.Enqueue($rr) }
    }
    return , $out
}

$apps = @($projects | Where-Object { $_.Kind })
# A Blazor WebAssembly app referenced by a web project is served by it (the hosted template).
foreach ($w in @($apps | Where-Object { $_.Type -eq 'wasm' })) {
    $host_ = @($apps | Where-Object { $_.Kind -eq 'appService' -and $_.Lang -eq 'dotnet' -and @($_.Refs | Where-Object { $_ -ieq $w.File }).Count }) | Select-Object -First 1
    if ($host_) { Add-Unique $notes "$($w.Rel): Blazor WebAssembly served by $($host_.Name) (not a resource of its own)"; $w.Kind = $null }
}
$apps = @($apps | Where-Object { $_.Kind })
foreach ($a in $apps) {
    foreach ($lib in (Get-Closure $a)) {
        foreach ($s in $lib.Signals.Keys) { foreach ($e in $lib.Signals[$s]) { Add-Signal $a $s "via $($lib.Name): $e" } }
        foreach ($n in $lib.ConnNames) { Add-Unique $a.ConnNames $n }
        foreach ($q in $lib.SbSend) { Add-Unique $a.SbSend $q }
        foreach ($q in $lib.SbReceive) { Add-Unique $a.SbReceive $q }
        foreach ($q in $lib.SqSend) { Add-Unique $a.SqSend $q }
        foreach ($q in $lib.SqReceive) { Add-Unique $a.SqReceive $q }
        if (-not $a.Health -and $lib.Health) { $a.Health = $lib.Health }
    }
    # %Setting% queue names of a Function: from its local.settings.json.
    foreach ($list in @($a.SbSend, $a.SbReceive, $a.SqSend, $a.SqReceive)) {
        for ($i = $list.Count - 1; $i -ge 0; $i--) {
            $q = [string]$list[$i]
            if ($q -notmatch '^%(.+)%$') { continue }
            $list.RemoveAt($i)
            if ($a.Values.ContainsKey($Matches[1]) -and $a.Values[$Matches[1]]) { Add-Unique $list ([string]$a.Values[$Matches[1]]) }
            else { Add-Unique $notes "$($a.Rel): queue $q is a setting with no value in local.settings.json: its queue is asked" }
        }
    }
}
foreach ($p in @($projects | Where-Object { -not $_.Kind })) {
    switch ($p.Type) {
        'worker' { Add-Unique $notes "$($p.Rel): a background worker ($($p.Name)): the catalog has no kind for it; a Function App, or a WebJob of an App Service, by hand" }
        'console' { Add-Unique $notes "$($p.Rel): a console app ($($p.Name)): not deployed by the catalog" }
        'netfx' { Add-Unique $notes "$($p.Rel): .NET Framework ($($p.Name)): needs a Windows App Service; the catalog's are Linux" }
    }
}
$tests = @($projects | Where-Object { $_.Type -eq 'test' }).Count
if ($tests) { Add-Unique $notes "$tests test project(s): not deployed" }

# Keys: the apps' names without what they all start with (Contoso.Erp.Api, Contoso.Erp.Admin.Api -> api,
# adminApi); a single app keeps its last part.
$dotted = New-Object Collections.ArrayList
foreach ($a in $apps) { if ($a.Lang -eq 'dotnet') { [void]$dotted.Add([string[]]$a.Name.Split('.')) } }
$common = 0
if ($dotted.Count) {
    $max = (@($dotted | ForEach-Object { $_.Count }) | Measure-Object -Minimum).Minimum - 1
    while ($common -lt $max) {
        $seg = $dotted[0][$common]
        if (@($dotted | Where-Object { $_[$common] -ne $seg }).Count) { break }
        $common++
    }
}
foreach ($a in @($apps | Sort-Object @{ e = { @('appService', 'functionApp', 'staticWebApp').IndexOf($_.Kind) } }, Name)) {
    $base = $a.Name
    if ($a.Lang -eq 'dotnet') { $base = (@($a.Name.Split('.') | Select-Object -Skip $common)) -join '.' }
    $a.Key = Get-FreeKey (Get-KeyName $base)
    if (-not $a.Title) { $a.Title = $a.Name }
}

# --- the resources they use --------------------------------------------------------------------------

function Get-Users([string]$Signal) { return @($apps | Where-Object { $_.Signals.ContainsKey($Signal) -and @('appService', 'functionApp') -contains $_.Kind }) }
function Get-Evidence($Users, [string]$Signal) {
    $e = New-Object Collections.ArrayList
    foreach ($u in $Users) { foreach ($x in @($u.Signals[$Signal] | Select-Object -First 3)) { Add-Unique $e $x } }
    return , $e
}
$resources = New-Object Collections.ArrayList
$uses = @{}   # app key -> resource keys
$roles = @{}  # app key -> @{ resource key -> roles }
foreach ($a in $apps) { $uses[$a.Key] = New-Object Collections.ArrayList; $roles[$a.Key] = [ordered]@{} }
function Add-Resource([string]$Kind, [string]$Key, [string]$Title, $Answers, $Users, $Evidence) {
    $r = [ordered]@{ kind = $Kind; key = $Key; title = $Title }
    if ($Answers -and $Answers.Count) { $r.answers = $Answers }
    $r.evidence = @($Evidence)
    if ($Users) { $r.usedBy = @($Users | ForEach-Object { $_.Key }) }
    foreach ($u in $Users) { Add-Unique $uses[$u.Key] $Key }
    [void]$resources.Add($r)
}

# Storage first: a Function App takes the first storage account of the map, a queue lives in one.
$blobUsers = @(Get-Users 'blob')
$queueUsers = @(Get-Users 'queue')
if ($blobUsers.Count -or $queueUsers.Count) {
    $ev = Get-Evidence $blobUsers 'blob'
    foreach ($x in (Get-Evidence $queueUsers 'queue')) { Add-Unique $ev $x }
    Add-Resource 'storage' (Get-FreeKey 'storage') 'Storage' $null $blobUsers $ev
}
if ($queueUsers.Count) {
    $names = New-Object Collections.ArrayList
    foreach ($u in $queueUsers) { foreach ($q in @($u.SqSend) + @($u.SqReceive)) { Add-Unique $names $q } }
    if (-not $names.Count) { [void]$names.Add('') }
    foreach ($q in $names) {
        $users = @($queueUsers | Where-Object { -not $q -or @($_.SqSend) -contains $q -or @($_.SqReceive) -contains $q -or -not (@($_.SqSend) + @($_.SqReceive)).Count })
        $title = $q
        $k = 'queue'
        if ($q) { $k = Get-KeyName $q } else { $title = 'Storage queue' }
        $k = Get-FreeKey $k
        $ev = New-Object Collections.ArrayList
        foreach ($u in $users) { foreach ($x in @($u.Signals['queue'] | Where-Object { -not $q -or $_ -match [regex]::Escape("`"$q`"") } | Select-Object -First 2)) { Add-Unique $ev $x } }
        # A name from a %setting%: what the app uses queues with.
        if (-not $ev.Count) { foreach ($x in (Get-Evidence $users 'queue')) { Add-Unique $ev $x } }
        Add-Resource 'storageQueue' $k $title $null $users $ev
        foreach ($u in $users) {
            $send = @($u.SqSend) -contains $q
            $recv = @($u.SqReceive) -contains $q
            if ($send -and -not $recv) { $roles[$u.Key][$k] = @('Storage Queue Data Message Sender') }
            elseif ($recv -and -not $send) { $roles[$u.Key][$k] = @('Storage Queue Data Message Processor') }
        }
    }
}

# SQL databases: one per connection string's name (the app reads ConnectionStrings:<name>).
$sqlUsers = @(Get-Users 'sql')
$dbs = [ordered]@{}
foreach ($u in $sqlUsers) {
    $found = New-Object Collections.ArrayList
    foreach ($s in @($u.Settings | Where-Object { $_.Kind -eq 'sql' })) {
        $n = $s.Name
        if (-not $n) { $n = $s.Db }
        if (-not $n) { continue }
        if (-not $dbs.Contains($n.ToLower())) { $dbs[$n.ToLower()] = @{ Name = $n; Db = $s.Db; Users = (New-Object Collections.ArrayList); Evidence = (New-Object Collections.ArrayList) } }
        if ($s.Db -and -not $dbs[$n.ToLower()].Db) { $dbs[$n.ToLower()].Db = $s.Db }
        Add-Unique $dbs[$n.ToLower()].Evidence "$($s.Where) (SQL Server$(if ($s.Db) { ", database $($s.Db)" }))"
        Add-Unique $found $n.ToLower()
    }
    # Names the code reads that no setting tells apart (empty in appsettings.json, or only in the code).
    if (-not $found.Count) {
        $other = @($u.Settings | Where-Object { $_.Kind -and $_.Name } | ForEach-Object { $_.Name.ToLower() })
        $named = @(@($u.ConnNames) + @($u.Settings | Where-Object { -not $_.Kind -and $_.Name } | ForEach-Object { $_.Name }) | Where-Object { $_ -and $other -notcontains $_.ToLower() -and $_ -notmatch '(?i)redis|bus|storage|blob|queue|cosmos|mongo|insights|vault|webjobs' } | Select-Object -Unique)
        foreach ($n in $named) {
            if (-not $dbs.Contains($n.ToLower())) { $dbs[$n.ToLower()] = @{ Name = $n; Db = ''; Users = (New-Object Collections.ArrayList); Evidence = (New-Object Collections.ArrayList) } }
            Add-Unique $dbs[$n.ToLower()].Evidence "$($u.Rel): reads the connection string $n"
            Add-Unique $found $n.ToLower()
        }
    }
    if (-not $found.Count) {
        if (-not $dbs.Contains('')) { $dbs[''] = @{ Name = ''; Db = ''; Users = (New-Object Collections.ArrayList); Evidence = (New-Object Collections.ArrayList) } }
        [void]$found.Add('')
    }
    foreach ($f in $found) { [void]$dbs[$f].Users.Add($u) }
}
foreach ($d in $dbs.Values) {
    $ev = $d.Evidence
    foreach ($x in (Get-Evidence $d.Users 'sql')) { if (-not @($ev | Where-Object { $_.StartsWith($x) }).Count) { Add-Unique $ev $x } }
    if ($d.Name) {
        $k = Get-FreeKey (Get-KeyName $d.Name)
        $title = $d.Name
        if ($d.Db -and $d.Db -ne $d.Name) { $title = "$($d.Db) ($($d.Name))" }
        $pascal = $k.Substring(0, 1).ToUpper() + $k.Substring(1)
        if ($pascal -ne $d.Name) { Add-Unique $ev "the map gives the apps ConnectionStrings__$pascal; they read $($d.Name): rename one of them" }
    } else {
        $k = Get-FreeKey 'db'
        $title = 'Database'
        Add-Unique $ev "no connection string's name found: the map gives the apps ConnectionStrings__Db"
    }
    Add-Resource 'sqlDatabase' $k $title $null $d.Users $ev
}

# Service Bus: one namespace with every queue found.
$busUsers = @(Get-Users 'serviceBus')
if ($busUsers.Count) {
    $queues = New-Object Collections.ArrayList
    foreach ($u in $busUsers) { foreach ($q in @($u.SbSend) + @($u.SbReceive)) { Add-Unique $queues $q } }
    $answers = [ordered]@{}
    $ev = Get-Evidence $busUsers 'serviceBus'
    if ($queues.Count) { $answers.queues = $queues -join ', ' } else { Add-Unique $ev 'no queue names found in the code: they are asked' }
    $k = Get-FreeKey 'bus'
    Add-Resource 'serviceBus' $k 'Service Bus' $answers $busUsers $ev
    foreach ($u in $busUsers) {
        $send = $u.SbSend.Count -gt 0
        $recv = $u.SbReceive.Count -gt 0
        if ($send -and -not $recv) { $roles[$u.Key][$k] = @('Azure Service Bus Data Sender') }
        elseif ($recv -and -not $send) { $roles[$u.Key][$k] = @('Azure Service Bus Data Receiver') }
    }
}

$vaultUsers = @(Get-Users 'keyVault')
if ($vaultUsers.Count) { Add-Resource 'keyVault' (Get-FreeKey 'vault') 'Key Vault' $null $vaultUsers (Get-Evidence $vaultUsers 'keyVault') }

# Application Insights: for the apps that send telemetry; every server app when none is found.
$aiUsers = @($apps | Where-Object { $_.Signals.ContainsKey('appInsights') })
$ev = Get-Evidence $aiUsers 'appInsights'
if (-not $aiUsers.Count) {
    $aiUsers = @($apps | Where-Object { @('appService', 'functionApp') -contains $_.Kind })
    if ($aiUsers.Count) { [void]$ev.Add('no telemetry found in the code: recommended for every app (logs, failures, performance)') }
}
if ($aiUsers.Count) { Add-Resource 'appInsights' (Get-FreeKey 'insights') 'Application Insights' $null $aiUsers $ev }

# What the catalog has no kind for.
foreach ($s in @($signalNames.Keys | Where-Object { $catalogSignals -notcontains $_ } | Sort-Object)) {
    $users = @($apps | Where-Object { $_.Signals.ContainsKey($s) })
    if ($users.Count) { Add-Unique $notes "$($signalNames[$s]) ($((@($users | ForEach-Object { $_.Key })) -join ', ')): the catalog has no kind for it; add it by hand" }
}

# The apps, after what they use (a new app is asked what of the map it uses).
foreach ($a in @($apps | Sort-Object @{ e = { @('appService', 'functionApp', 'staticWebApp').IndexOf($_.Kind) } }, Name)) {
    $answers = [ordered]@{}
    switch ($a.Kind) {
        'appService' {
            if ($a.Runtime) { $answers.runtime = $a.Runtime }
            $answers.source = $a.Rel
            if ($a.Health) { $answers.health = $a.Health }
            else { $answers.health = '-'; [void]$a.Notes.Add('no health check found (MapHealthChecks): none, so App Service doesn''t restart it for a missing path') }
        }
        'functionApp' {
            $answers.hosting = 'flex'
            if ($a.Runtime) { $answers.runtime = $a.Runtime }
            $answers.source = $a.Rel
        }
        'staticWebApp' { $answers.source = $a.Rel; $answers.output = $a.Output }
    }
    $what = switch ($a.Lang) { 'dotnet' { "$(Split-Path $a.File -Leaf) ($($a.Type)$(if ($a.Ver) { ", .NET $($a.Ver)" }))" } 'node' { "package.json ($($a.Type))" } default { "$(Split-Path $a.File -Leaf) ($($a.Type))" } }
    $r = [ordered]@{ kind = $a.Kind; key = $a.Key; title = $a.Title; answers = $answers }
    if ($uses[$a.Key].Count) { $r.uses = @($uses[$a.Key]) }
    if ($roles[$a.Key].Count) { $r.roles = $roles[$a.Key] }
    $r.evidence = @("$($a.Rel)/$what") + @($a.Notes)
    [void]$resources.Add($r)
}

# --- the project -----------------------------------------------------------------------------------------

$solution = @($all | Where-Object { $_ -match '\.slnx?$' } | Sort-Object { $_.Split('\').Count }) | Select-Object -First 1
$projectName = Split-Path $Path -Leaf
if ($solution) { $projectName = [IO.Path]::GetFileNameWithoutExtension($solution) }
$parts = @([regex]::Split($projectName.ToLower(), '[^a-z0-9]+') | Where-Object { $_ })
$prefix = ''
if ($parts.Count -ge 2) { $prefix = ($parts | Select-Object -First 2) -join '-' }
elseif ($parts.Count) {
    $first = 'nm'
    $nf = Join-Path $infra 'naming.json'
    if (Test-Path $nf) { $first = ([string](Get-Content $nf -Raw -Encoding UTF8 | ConvertFrom-Json).defaults.prefix).Split('-')[0] }
    $slug = $parts[0]
    if ($slug.Length -gt 12) { $slug = $slug.Substring(0, 12) }
    $prefix = "$first-$slug"
}
$kindsUsed = @($resources | Where-Object { @('appService', 'functionApp', 'staticWebApp') -notcontains $_.kind } | ForEach-Object { $_.kind } | Select-Object -Unique)
$description = "$projectName on Azure"
if ($apps.Count) { $description += ': ' + ((@($apps | ForEach-Object { $_.Key })) -join ', ') }
if ($kindsUsed.Count) { $description += ' with ' + ($kindsUsed -join ', ') }
$project = [ordered]@{ name = $projectName; description = $description }
if ($prefix -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $project.prefix = $prefix }

$spec = [ordered]@{
    '$comment' = "Suggested by infra/analyze.ps1 from $Path. A spec for .\infra\azure-setup.ps1 -Init -SpecFile (infra/LAZYBICEP.md, 'A new project'); 'evidence', 'usedBy' and 'notes' are only for reading."
    project = $project
    resources = @($resources)
    notes = @($notes)
    scanned = [ordered]@{ path = $Path; dotnet = @($projects | Where-Object { $_.Lang -eq 'dotnet' }).Count; apps = $apps.Count }
}
$json = $spec | ConvertTo-Json -Depth 12

if ($Out) {
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Out), $json, (New-Object Text.UTF8Encoding $false))
}
if ($PassThru) { return ($json | ConvertFrom-Json) }

# --- the report --------------------------------------------------------------------------------------------

Show-Author
Write-Host "  Looked through $Path" -ForegroundColor White
Write-Host "  $($spec.scanned.dotnet) .NET project(s), $($apps.Count) app(s) to deploy" -ForegroundColor DarkGray
Write-Host ''
Write-Host '  PROJECT' -ForegroundColor White
Write-Host "    $($project.name)   prefix $($project.prefix)" -ForegroundColor Green
Write-Host ''
Write-Host '  SUGGESTED RESOURCES' -ForegroundColor White
if (-not $resources.Count) { Write-Host '    none found: start the map by hand (.\infra\azure-setup.ps1 -Init)' -ForegroundColor DarkGray }
foreach ($r in $resources) {
    $extra = ''
    if ($r.answers) { $extra = (@($r.answers.Keys | ForEach-Object { "$_=$($r.answers[$_])" })) -join '  ' }
    Write-Host ("    {0,-13} {1,-14} {2}" -f $r.kind, $r.key, $r.title) -ForegroundColor Green
    if ($extra) { Write-Host "                  $extra" -ForegroundColor DarkGray }
    if ($r.uses) { Write-Host "                  uses $($r.uses -join ', ')" -ForegroundColor DarkGray }
    foreach ($e in $r.evidence) { Write-Host "                  - $e" -ForegroundColor DarkGray }
}
if ($notes.Count) {
    Write-Host ''
    Write-Host '  NOTES' -ForegroundColor White
    foreach ($n in $notes) { Write-Host "    ! $n" -ForegroundColor Yellow }
}
Write-Host ''
Write-Host '  NEXT' -ForegroundColor White
Write-Host '    .\infra\azure-setup.ps1 -Init -Analyze     offers each of these, then the usual questions' -ForegroundColor Green
if ($Out) { Write-Host "    .\infra\azure-setup.ps1 -Init -SpecFile $Out     takes them as they are (written: $Out)" -ForegroundColor Green }
Write-Host ''
