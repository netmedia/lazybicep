#Requires -Version 5.1
<#
.SYNOPSIS
Makes the developer guide's terminal UI screenshots (docs/images/tui-*.png) from the "Contoso Shop" demo.

.DESCRIPTION
Builds demo projects in a temp folder from this repository's kit (examples/spec.example.json, and a small
solution for the analysis), drives infra/lazybicep.ps1 with keys (-Keys, -Html: every snap as an HTML page
in the terminal's colours) and turns the chosen frames into PNGs with Microsoft Edge (headless).

The dry run is real and read-only: it signs in with the Azure CLI's default subscription (az login first),
looks names up and shows a what-if; nothing in Azure changes. It runs the test environment (production
needs a deploy branch, and the demo's repository has none).

.PARAMETER Out
Where the PNGs go. Default: docs/images.

.PARAMETER Environment
The environment of the dry run. Default: test.

.EXAMPLE
.\docs\tools\screenshots.ps1
#>
[CmdletBinding()]
param(
    [string]$Out = (Join-Path $PSScriptRoot '..\images'),
    [string]$Environment = 'test'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Out = [IO.Path]::GetFullPath($Out)
$edge = @('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe', 'C:\Program Files\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'Microsoft Edge is needed (it turns the HTML frames into PNGs).' }
$work = Join-Path ([IO.Path]::GetTempPath()) ('lazybicep-shots-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
Write-Host "work folder: $work"

# A project with the kit; with -Map, the demo's map from the example spec.
function New-Demo([string]$Name, [switch]$Map) {
    $dir = Join-Path $work $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'infra') | Out-Null
    Copy-Item -Path (Join-Path $repo 'infra\*') -Destination (Join-Path $dir 'infra') -Recurse -Force
    foreach ($f in @('infra.map.json', 'main.bicep')) { Remove-Item (Join-Path $dir "infra\$f") -ErrorAction SilentlyContinue }
    Remove-Item (Join-Path $dir 'infra\environments') -Recurse -ErrorAction SilentlyContinue
    # The setup asks the GitHub repository (the remote's is the default).
    & git -C $dir init -q 2>$null
    & git -C $dir remote add origin https://github.com/netmedia/lazybicep.git 2>$null
    if ($Map) {
        Push-Location $dir
        try { & powershell -NoProfile -ExecutionPolicy Bypass -File infra\azure-setup.ps1 -Init -SpecFile (Join-Path $repo 'examples\spec.example.json') | Out-Null } finally { Pop-Location }
        if (-not (Test-Path (Join-Path $dir 'infra\infra.map.json'))) { throw "the demo map wasn't made in $dir" }
    }
    return $dir
}
# The UI with keys; every snap an HTML page in $dir\frames.
function Invoke-Tui([string]$Dir, [string]$Keys) {
    # Each run its own folder: the frames' numbers start again with every run.
    $script:runNo++
    $frames = Join-Path $Dir "frames-$($script:runNo)"
    Push-Location $Dir
    try { & powershell -NoProfile -ExecutionPolicy Bypass -File infra\lazybicep.ps1 -Keys $Keys -Html $frames -Width 120 -Height 36 | Out-Null } finally { Pop-Location }
    return @(Get-ChildItem $frames -Filter '*.html' | Sort-Object Name)
}
function Get-Text($File) { return [Net.WebUtility]::HtmlDecode(([IO.File]::ReadAllText($File.FullName) -replace '<[^>]+>', '')) }
# The first (or last) frame whose screen has the text.
function Find-Frame($Files, [string]$Text, [switch]$Last) {
    $hits = @($Files | Where-Object { (Get-Text $_).Contains($Text) })
    if (-not $hits.Count) { throw "no frame shows '$Text'" }
    if ($Last) { return $hits[-1] }
    return $hits[0]
}
# What a screenshot mustn't show (the guide is public): the signed-in account and the subscriptions'
# names and ids, each replaced by a demo value of the same length (the screen's boxes stay aligned).
function Get-SameLength([string]$Text, [int]$Length) {
    if ($Text.Length -ge $Length) { return $Text.Substring(0, $Length) }
    return $Text + (' ' * ($Length - $Text.Length))
}
$redact = [ordered]@{}
$prevPref = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$me = (& az account show --query user.name -o tsv 2>$null)
# The JSON as one text (PowerShell 5.1 hands az's output over line by line).
$parsed = ((& az account list --query '[].{n:name,id:id}' -o json 2>$null) -join "`n") | ConvertFrom-Json
$subs = @($parsed | ForEach-Object { $_ }) # unrolled: 5.1 returns the whole array as one object
$ErrorActionPreference = $prevPref
if ($me) { $redact[[string]$me] = Get-SameLength 'dev@contoso.com' ([string]$me).Length }
for ($i = 0; $i -lt $subs.Count; $i++) {
    $name = [string]$subs[$i].n
    $demo = 'Contoso Demo'
    if ($i) { $demo = "Subscription $($i + 1)" }
    if ($demo.Length -gt $name.Length) { $demo = "Sub $($i + 1)" }
    if (-not $redact.Contains($name)) { $redact[$name] = Get-SameLength $demo $name.Length }
    $redact[[string]$subs[$i].id] = '00000000-0000-0000-0000-' + ('{0:000000000000}' -f ($i + 1))
}
function Protect-Frame($Frame) {
    $html = [IO.File]::ReadAllText($Frame.FullName)
    # The subscriptions' list ("3. <name> (<id>)"): the whole entry, numbered as on the screen; the spaces
    # that keep the line's length go at its end, where they don't show.
    $html = [regex]::Replace($html, '(?<n>\d+)\. (?<name>[^<(\r\n]+?) \((?<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\)', [Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $n = [int]$m.Groups['n'].Value
            $demo = 'Contoso Demo'
            if ($n -gt 1) { $demo = "Subscription $n" }
            $text = "$n. $demo (00000000-0000-0000-0000-$('{0:000000000000}' -f $n))"
            return $text + (' ' * [Math]::Max(0, $m.Value.Length - $text.Length))
        })
    foreach ($k in $redact.Keys) { if ($k) { $html = $html.Replace([Net.WebUtility]::HtmlEncode($k), [Net.WebUtility]::HtmlEncode($redact[$k])) } }
    $file = Join-Path $Frame.DirectoryName ($Frame.BaseName + '.public.html')
    [IO.File]::WriteAllText($file, $html, (New-Object Text.UTF8Encoding $false))
    return $file
}
function Save-Png($Frame, [string]$Name) {
    $png = Join-Path $Out "$Name.png"
    Remove-Item $png -ErrorAction SilentlyContinue
    # Its own profile, and stopped if it hangs (headless Edge sometimes doesn't exit).
    $edgeProfile = Join-Path $work ('edge-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $url = 'file:///' + (Protect-Frame $Frame).Replace('\', '/')
    $p = Start-Process $edge -ArgumentList @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', "--user-data-dir=`"$edgeProfile`"", '--window-size=1312,752', "--screenshot=`"$png`"", $url) -PassThru -WindowStyle Hidden
    for ($i = 0; $i -lt 60 -and -not (Test-Path $png); $i++) { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Milliseconds 500
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -like "*$edgeProfile*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (-not (Test-Path $png)) { throw "Edge made no $png" }
    Write-Host "  $Name.png  <- $($Frame.Name)" -ForegroundColor Green
}
$answers = (@('wait:ask', 'snap', 'stop:done', 'Enter') * 90) -join ','

# 1. The New project screen.
$new = New-Demo 'new'
$f = Invoke-Tui $new 'snap,q'
Save-Png (Find-Frame $f 'A NEW PROJECT') 'tui-new-project'

# 2. Home and Map of the demo.
$shop = New-Demo 'shop' -Map
$f = Invoke-Tui $shop 'snap,m,Down,snap,Down,snap,Down,snap,Down,snap,Esc,q'
Save-Png (Find-Frame $f 'ACTIONS') 'tui-home'
Save-Png (Find-Frame $f 'APP SETTINGS') 'tui-map'

# 3. A dry run: a question with choices, the cost with the budget question, the end.
$envs = @((Get-Content (Join-Path $shop 'infra\naming.json') -Raw | ConvertFrom-Json).environments.PSObject.Properties | ForEach-Object { $_.Name })
$downs = (@('Down') * [Math]::Max(0, [array]::IndexOf($envs, $Environment))) -join ','
$keys = (@($downs, 'd', ((@('wait:ask', 'snap', 'stop:done', 'Enter') * 120) -join ','), 'wait:done', 'snap') | Where-Object { $_ }) -join ','
$f = Invoke-Tui $shop $keys
Save-Png (Find-Frame $f '? Size of App Service plan') 'tui-run-question'
Save-Png (Find-Frame $f 'Monthly budget') 'tui-run-cost'
Save-Png ($f[-1]) 'tui-run-done'

# 4. The analysis of a small solution, at an app's configuration.
$sol = New-Demo 'solution'
$api = Join-Path $sol 'src\Shop.Api'
New-Item -ItemType Directory -Force -Path $api | Out-Null
Set-Content (Join-Path $sol 'Contoso.Shop.sln') ''
Set-Content (Join-Path $api 'Shop.Api.csproj') '<Project Sdk="Microsoft.NET.Sdk.Web"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup><ItemGroup><PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="10.0.0" /><PackageReference Include="Azure.Messaging.ServiceBus" Version="7.18.0" /></ItemGroup></Project>'
Set-Content (Join-Path $api 'Program.cs') @'
builder.Services.AddDbContext<ShopDb>(o => o.UseSqlServer(builder.Configuration.GetConnectionString("ShopDb")));
var bus = new ServiceBusClient(builder.Configuration["ServiceBus"]);
app.MapHealthChecks("/health");
'@
Set-Content (Join-Path $api 'appsettings.json') @'
{
  "ConnectionStrings": { "ShopDb": "Server=(localdb)\\mssqllocaldb;Database=Shop;Trusted_Connection=True;" },
  "ServiceBus": "Endpoint=sb://shop.servicebus.windows.net/;SharedAccessKeyName=app;SharedAccessKey=dev",
  "Smtp": { "Host": "smtp.office365.com", "Password": "" },
  "Payments": { "ApiKey": "" },
  "ExternalApi": { "BaseUrl": "http://localhost:5001" }
}
'@
$f = Invoke-Tui $sol ('n,' + $answers)
Save-Png (Find-Frame $f 'Secrets of') 'tui-new-analyze'

Write-Host "done: $Out (the work folder $work can go)"
