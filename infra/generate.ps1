#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyBicep  -  generate.ps1                                             ║
#  ║   Makes main.bicep from the map and the catalog                          ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyBicep  -  https://github.com/netmedia/lazybicep          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
.SYNOPSIS
LazyBicep by Netmedia: makes infra/main.bicep from infra/infra.map.json and infra/catalog/.

.AUTHOR
Netmedia  |  https://netmedia.agency  |  netmedia@netmedia.hr

.DESCRIPTION
main.bicep is generated: one section per resource of the map, from its kind's fragment in
infra/catalog/<kind>.bicep (several resources of one kind each get their own, named by their key), the
apps' settings from their "appSettings" ({braces} become Bicep expressions), the role assignments from the
"role" connections, the Key Vault's readers and secrets. Change the map or the catalog, never main.bicep;
then run this, and a dry run shows what would change in Azure.

Values in {braces}: {<key>.name} (its name parameter), {<key>.host}, {<key>.id}, {<key>.connectionString}
(Application Insights), {<key>.tableEndpoint} / queueEndpoint / blobEndpoint (storage), {<key>.clientId} /
principalId (an app's identity), {<answer>} (a custom domain's parameter, e.g. {webDomain}),
{secret.<name>} (a secret the setup keeps), {kvdns} (.vault.azure.net), {env}; 'a|b' takes b when a is
empty (an unset domain, a resource that isn't used).

Every app signs in as its own user-assigned identity (an appIdentity of the map: the app's "identity", its
"owner"): its roles, Key Vault reads, AZURE_CLIENT_ID and identity-based connection settings use it.

A Container App (containerApp) runs the image main.bicep is given (<key>Image, the one Azure runs now; empty:
the public placeholder) and never changes it; its Key Vault references become Container Apps secrets
(keyVaultUrl + its identity) read through secretRef, and with "signIn" its platform sign-in (authConfigs) is
made once <key>SignInClientId is set.

.PARAMETER Check
Only compares: exits with 1 when main.bicep isn't what the map makes (infra/azure-setup.ps1 checks this).

.PARAMETER Quiet
No output (for -Check from the setup).

.PARAMETER Help
Shows the usage guide and exits.

.EXAMPLE
.\infra\generate.ps1

.NOTES
LazyBicep is a Netmedia product: https://netmedia.agency, netmedia@netmedia.hr,
https://github.com/netmedia/lazybicep.

.LINK
infra/LAZYBICEP.md
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Quiet,
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
    $title = 'LazyBicep  -  generate.ps1'
    Write-Host ''
    Write-Host "  $([char]0x256D)$hLine$([char]0x256E)" -ForegroundColor Cyan
    Row ''
    Row "$esc[1m$title$esc[0m" $title 'Cyan'
    Row 'Makes main.bicep from the map and the catalog' -color 'White'
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
    & $g '  .\infra\generate.ps1  [-Check]  [-Quiet]'
    & $d '  main.bicep is generated: never edit it. Change infra\infra.map.json (or add and'
    & $d '  remove resources with .\infra\azure-setup.ps1 -AddResource / -RemoveResource,'
    & $d '  which run this), then a dry run shows what changes in Azure.'
    Write-Host ''
    & $b 'OPTIONS'
    & $y '  -Check'
    & $d '    Only compares: exit 1 when main.bicep isn''t what the map makes.'
    & $y '  -Quiet'
    & $d '    No output (the setup checks with -Check -Quiet before every what-if).'
    & $y '  -Help  (-h)'
    & $d '    Shows this guide and exits.'
    Write-Host ''
    & $d '  More: infra\LAZYBICEP.md ("The catalog")'
    Write-Host ''
}
if ($Help) { Show-Author; Show-Usage; exit 0 }
if (-not $Quiet) { Show-Author }

$map = Get-Content (Join-Path $infra 'infra.map.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$roles = Get-Content (Join-Path $infra 'catalog\roles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$naming = Get-Content (Join-Path $infra 'naming.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$actions = Get-Content (Join-Path $infra 'catalog\workflows\actions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$defs = @($map.resources)
$noBicep = @('resourceGroup', 'entraDeployApp') # made by the setup itself
$target = Join-Path $infra ([string]$map.project.template)

function Get-Def([string]$Key) { return $defs | Where-Object { $_.key -eq $Key } | Select-Object -First 1 }
function Get-Links([string]$From, [string]$Kind) { return @($map.connections | Where-Object { $_.from -eq $From -and $_.kind -eq $Kind }) }
function Get-LinksTo([string]$To, [string]$Kind) { return @($map.connections | Where-Object { @($_.to.Split('|')) -contains $To -and $_.kind -eq $Kind }) }
function Test-Optional($Def) { return [bool]($Def.optional -or $Def.when) }
function Fail([string]$Text) { throw "infra.map.json: $Text" }

# --- {braces} to Bicep -------------------------------------------------------------------------------

function Get-TokenBicep([string]$Token) {
    if ($Token -eq 'kvdns') { return 'environment().suffixes.keyvaultDns' }
    if ($Token -eq 'env') { return 'environmentName' }
    # The environment's name capitalized (Production): appsettings.Production.json on Linux's case-sensitive disk.
    if ($Token -eq 'envName') { return "'`${toUpper(substring(environmentName, 0, 1))}`${substring(environmentName, 1)}'" }
    if ($Token.StartsWith('secret.')) {
        $name = $Token.Substring(7)
        foreach ($d in $defs) { foreach ($s in @($d.secrets)) { if ($s -and $s.name -eq $name -and $s.param) { return [string]$s.param } } }
        Fail "{$Token}: no secret $name that the setup keeps (secrets, by: setup)"
    }
    $domain = @($map.domains) | Where-Object { $_.answer -eq $Token } | Select-Object -First 1
    if ($domain) {
        if (-not $domain.param) { Fail "{$Token}: the domain has no main.bicep parameter (param)" }
        return [string]$domain.param
    }
    # A value asked per environment (the map's "values").
    $value = @($map.values) | Where-Object { $_ -and $_.answer -eq $Token } | Select-Object -First 1
    if ($value) { return [string]$value.param }
    $parts = $Token.Split('.')
    $d = Get-Def $parts[0]
    if (-not $d -or $parts.Count -ne 2) { Fail "{$Token}: no such resource or value" }
    $key = $d.key
    switch ($parts[1]) {
        'name' { return [string]$d.param }
        'id' { return "$key.id" }
        'host' {
            switch ([string]$d.kind) {
                'staticWebApp' { return "$key.properties.defaultHostname" }
                # Known from the name (the server may be shared from another group).
                'sqlServer' { return "'`${$($d.param)}`${environment().suffixes.sqlServerHostname}'" }
                'serviceBus' { return "'`${$($d.param)}.servicebus.windows.net'" }
                'appConfiguration' { return "'`${$($d.param)}.azconfig.io'" }
                'containerApp' { return "$key.properties.configuration.ingress.fqdn" }
                'containerRegistry' { return "$key.properties.loginServer" }
            }
            return "$key.properties.defaultHostName"
        }
        'connectionString' { return "${key}Connection" }
        'tableEndpoint' { return "$key.properties.primaryEndpoints.table" }
        'queueEndpoint' { return "$key.properties.primaryEndpoints.queue" }
        'blobEndpoint' { return "$key.properties.primaryEndpoints.blob" }
        # An app's identity: its client id (AZURE_CLIENT_ID, <Name>__clientId, SQL's User Id) and principal.
        'clientId' { if ($d.kind -eq 'appIdentity') { return "$key.properties.clientId" } }
        'principalId' { if ($d.kind -eq 'appIdentity') { return "$key.properties.principalId" } }
    }
    Fail "{$Token}: $($parts[1]) isn't a value of a resource"
}
# When a value can be empty (an unset domain, a resource only some answers use): the test for it.
function Get-TokenGuard([string]$Token) {
    $domain = @($map.domains) | Where-Object { $_.answer -eq $Token } | Select-Object -First 1
    if ($domain) { return "empty($($domain.param))" }
    $d = Get-Def ($Token.Split('.')[0])
    if ($d -and (Test-Optional $d)) { return "empty($($d.param))" }
    return $null
}
function Get-AltBicep([string]$Inner) {
    $alts = $Inner.Split('|')
    $expr = Get-TokenBicep $alts[-1]
    for ($i = $alts.Count - 2; $i -ge 0; $i--) {
        $guard = Get-TokenGuard $alts[$i]
        $token = Get-TokenBicep $alts[$i]
        if ($guard) { $expr = "$guard ? $expr : $token" } else { $expr = $token }
    }
    return $expr
}
function Get-ValueBicep([string]$Value) {
    $matches_ = @([regex]::Matches($Value, '\{([^{}]+)\}'))
    if ($matches_.Count -eq 1 -and $matches_[0].Value -eq $Value) { return Get-AltBicep $matches_[0].Groups[1].Value }
    $out = "'"
    $at = 0
    foreach ($m in $matches_) {
        $expr = Get-AltBicep $m.Groups[1].Value
        # A value that is itself an interpolated string ('${a}.b') goes in as it is.
        if ($expr -match "^'([^']*)'$") { $piece = $Matches[1] } else { $piece = '${' + $expr + '}' }
        $out += (Get-Literal $Value.Substring($at, $m.Index - $at)) + $piece
        $at = $m.Index + $m.Length
    }
    return $out + (Get-Literal $Value.Substring($at)) + "'"
}
function Get-Literal([string]$Text) { return $Text.Replace('\', '\\').Replace("'", "\'").Replace('${', '\${') }
function Get-Quoted([string]$Text) { return "'" + (Get-Literal $Text) + "'" }
function Get-PropName([string]$Name) { if ($Name -match '^[A-Za-z_][A-Za-z0-9_]*$') { return $Name } return (Get-Quoted $Name) }

function Get-SettingsArray($Def, [string]$Indent) {
    $lines = @('[')
    foreach ($s in @(Get-Settings $Def)) {
        if ($s.about) { $lines += "$Indent  // $($s.about)" }
        $lines += "$Indent  { name: $(Get-Quoted $s.name), value: $(Get-ValueBicep $s.value) }"
    }
    return ($lines + "$Indent]") -join "`n"
}
function Get-SettingsObject($Def, [string]$Indent) {
    $lines = @('{')
    foreach ($s in @(Get-Settings $Def)) {
        if ($s.about) { $lines += "$Indent  // $($s.about)" }
        $lines += "$Indent  $(Get-PropName $s.name): $(Get-ValueBicep $s.value)"
    }
    return ($lines + "$Indent}") -join "`n"
}

# --- the apps' identities ------------------------------------------------------------------------------

# An app's own user-assigned identity: the appIdentity its "identity" names, owned by it ("owner"), never
# another app's. $null for an app without one (a map from before LazyBicep 0.2.0: system-assigned).
function Get-Identity($Def) {
    if (-not $Def.identity) { return $null }
    $id = Get-Def ([string]$Def.identity)
    if (-not $id -or $id.kind -ne 'appIdentity') { Fail "$($Def.key): identity $($Def.identity) isn't an appIdentity of the map" }
    if ([string]$id.owner -ne [string]$Def.key) { Fail "$($Def.key): identity $($id.key) is the identity of $($id.owner) (an app's identity is never shared)" }
    return $id
}
# Who a role is given to: the principal of the app's identity, and the resource whose id names the assignment
# (the identity's, so the assignment doesn't wait for the app).
function Get-PrincipalExpr($Def) {
    $id = Get-Identity $Def
    if ($id) { return "$($id.key).properties.principalId" }
    return "$($Def.key).identity.principalId"
}
function Get-PrincipalKey($Def) {
    $id = Get-Identity $Def
    if ($id) { return [string]$id.key }
    return [string]$Def.key
}
# Identity-based connections: a setting <Name>__fullyQualifiedNamespace, __serviceUri, __accountName... whose
# value is a resource of the map. A Function App with its own identity signs in there as it: <Name>__credential
# = managedidentity and <Name>__clientId follow each (read by the Functions host, its triggers and bindings); a
# sibling the map sets itself is kept as it is. App Service and Container Apps code signs in through
# DefaultAzureCredential with AZURE_CLIENT_ID, so their apps get no siblings.
$identityConnections = @('accountName', 'fullyQualifiedNamespace', 'serviceUri', 'blobServiceUri', 'queueServiceUri', 'tableServiceUri', 'endpoint', 'uri')
function Get-Settings($Def) {
    $id = Get-Identity $Def
    if (-not $id) { return @($Def.appSettings) }
    $settings = @($Def.appSettings | Where-Object { $_ })
    if ($Def.kind -ne 'functionApp') { return $settings }
    $have = @($settings | ForEach-Object { [string]$_.name })
    $out = @()
    foreach ($s in $settings) {
        $out += $s
        $name = [string]$s.name
        $at = $name.LastIndexOf('__')
        if ($at -lt 1 -or $name -like 'ConnectionStrings__*' -or $identityConnections -notcontains $name.Substring($at + 2)) { continue }
        if (-not @([regex]::Matches([string]$s.value, '[{|](\w+)\.') | Where-Object { Get-Def $_.Groups[1].Value }).Count) { continue }
        $prefix = $name.Substring(0, $at)
        foreach ($p in @(@('credential', 'managedidentity'), @('clientId', "{$($id.key).clientId}"))) {
            $n = "${prefix}__$($p[0])"
            if ($have -contains $n) { continue }
            $have += $n
            $out += [pscustomobject]@{ name = $n; value = $p[1] }
        }
    }
    return $out
}
# An app's identity in its fragment: {{identity}} under //#if identity (//#if systemIdentity: an older map's
# system-assigned one), and {{dependsOn}}: what it waits for - $DependsOn, and with its own identity the
# identity's role assignments and Key Vault reads, so they exist when it first starts.
function Set-AppIdentity($Def, [hashtable]$V, [hashtable]$F, [string[]]$DependsOn) {
    $id = Get-Identity $Def
    $F.identity = [bool]$id
    $F.systemIdentity = -not $id
    $deps = @($DependsOn | Where-Object { $_ })
    $roleDeps = @()
    if ($id) {
        $V.identity = [string]$id.key
        $roleDeps += @($script:roleAssignments | Where-Object { $_.from.key -eq $Def.key } | ForEach-Object { $_.sym })
        $roleDeps += @(Get-Links $Def.key 'role' | Where-Object { (Get-Def $_.to).kind -eq 'keyVault' } | ForEach-Object { "$($_.to)Access" } | Select-Object -Unique)
    }
    $V.dependsOn = ''
    if ($roleDeps.Count) { $V.dependsOn = "  // Its identity's roles exist before it first starts.`n" }
    if (($deps + $roleDeps).Count) { $V.dependsOn += "  dependsOn: [$((@($deps + $roleDeps)) -join ', ')]" }
}

# --- Container Apps -----------------------------------------------------------------------------------------

# The public image a new Container App runs (port 80): main.bicep (catalog/containerApp.bicep) and the deploy
# workflow know it. Pinned by digest, not a tag: it runs with the app's identity attached (AcrPull, Key Vault Secrets
# User), so a changed image behind the same tag must never start there (digest looked up on MCR 2026-11-20).
$containerPlaceholder = 'mcr.microsoft.com/k8se/quickstart@sha256:3a4d93c34c6753f24765ab17a36f1754aee9b02082b7d9553d17697b9e8252c4'
# A key as a container name and image repository: lowercase, words joined with hyphens (adminApi -> admin-api).
function Get-ContainerName([string]$Key) { return ($Key -creplace '([a-z0-9])([A-Z])', '$1-$2').ToLowerInvariant() }
# A Container App's environment or registry: its field ("environment", "registry"), else its connection of that
# kind; in this resource group (one shared from another group isn't supported yet).
function Get-ContainerAppPart($Def, [string]$Field, [string]$Kind, [string]$LinkKind) {
    $k = [string]$Def.$Field
    if (-not $k) { $k = [string](@(Get-Links $Def.key $LinkKind | Where-Object { (Get-Def $_.to).kind -eq $Kind } | ForEach-Object { $_.to }) | Select-Object -First 1) }
    $part = $null
    if ($k) { $part = Get-Def $k }
    if (-not $part -or $part.kind -ne $Kind) { Fail "$($Def.key) needs its $Field (a $Kind of the map)" }
    if ($part.groupParam) { Fail "$($Def.key): a $Kind shared from another resource group isn't supported yet" }
    return $part
}
# With "signIn" (provider entra; "entra" alone takes the defaults) the platform's sign-in is in front of the app.
function Test-SignIn($Def) {
    if (-not $Def.signIn) { return $false }
    $provider = [string]$Def.signIn
    if ($Def.signIn -isnot [string]) { $provider = [string]$Def.signIn.provider }
    if (-not $provider -or $provider -eq 'none') { return $false }
    if ($provider -ne 'entra') { Fail "$($Def.key): signIn provider $provider (only entra, or none)" }
    return $true
}
# The paths a container app's sign-in leaves out (authConfigs excludedPaths), the one rule (import.ps1 and
# azure-setup.ps1 compare a running app with the same list):
#   1. its health path, when set and not '-' (the probes and the deploy reach it without sign-in);
#   2. then each of signIn.excludedPaths in map order, and for each '/x/*' first '/x' (the wildcard doesn't cover it);
#   3. de-duplicated (case-sensitive, the first one stays), order otherwise as above.
# The root is never anonymous: a health path or an excluded path of '/' or '/*' fails.
function Get-SignInExcludedPaths($Def) {
    $key = [string]$Def.key
    $paths = @()
    $health = [string]$Def.healthCheckPath
    if ($health -and $health -ne '-') {
        if ($health -eq '/' -or $health -eq '/*') { Fail "${key}: healthCheckPath $health with sign-in would leave the whole app without sign-in (the health path is excluded from it): use a path of its own, e.g. /health" }
        $paths += $health
    }
    if ($Def.signIn -isnot [string]) {
        foreach ($p in @($Def.signIn.excludedPaths | Where-Object { $_ })) {
            $p = [string]$p
            if (-not $p.StartsWith('/') -or $p -eq '/*' -or $p -eq '/') { Fail "${key}: signIn.excludedPaths $p (a path from /, not all of them)" }
            if ($p.EndsWith('/*')) { $paths += $p.Substring(0, $p.Length - 2) }
            $paths += $p
        }
    }
    $unique = @()
    foreach ($p in $paths) { if ($unique -cnotcontains $p) { $unique += $p } }
    # The caller wraps the result in @() (none or one path would otherwise not be a list).
    return $unique
}
# A setting that reads a Key Vault secret: @Microsoft.KeyVault(VaultName={<vault>.name};SecretName=<name>) (one you
# put in) or {secret.<name>} (one the setup keeps). A Container App gets it as a secret by reference (keyVaultUrl
# + its identity), never as a value; $null for any other setting.
function Get-ContainerSecret($Def, $Setting) {
    $value = [string]$Setting.value
    $vaultKey = ''
    $secret = ''
    if ($value -match '^@Microsoft\.KeyVault\(VaultName=\{(\w+)\.name\};SecretName=([A-Za-z0-9-]+)\)$') { $vaultKey = $Matches[1]; $secret = $Matches[2] }
    elseif ($value -match '^\{secret\.([A-Za-z0-9-]+)\}$') {
        $secret = $Matches[1]
        $vaultKey = [string](@($defs | Where-Object { $_.kind -eq 'keyVault' -and @($_.secrets | Where-Object { $_ -and $_.name -eq $secret }).Count } | ForEach-Object { $_.key }) | Select-Object -First 1)
        if (-not $vaultKey) { Fail "$($Def.key): setting $($Setting.name): no Key Vault of the map keeps the secret $secret" }
    }
    elseif ($value -match '@Microsoft\.KeyVault\(' -or $value -match '\{secret\.') {
        Fail "$($Def.key): setting $($Setting.name): a container app reads a Key Vault secret only as the whole value, @Microsoft.KeyVault(VaultName={<vault>.name};SecretName=<name>) or {secret.<name>} (never a value in main.bicep)"
    }
    else { return $null }
    $vault = Get-Def $vaultKey
    if (-not $vault -or $vault.kind -ne 'keyVault') { Fail "$($Def.key): setting $($Setting.name): $vaultKey isn't a Key Vault of the map" }
    if (-not @(Get-Links $Def.key 'role' | Where-Object { $_.to -eq $vaultKey -and @($_.roles) -contains 'Key Vault Secrets User' }).Count) {
        Fail "$($Def.key) reads the secret $secret of $vaultKey but has no Key Vault Secrets User there (a role connection)"
    }
    # Container Apps secret names: lowercase letters, digits, '-' and '.'.
    return [pscustomobject]@{ name = $secret.ToLowerInvariant(); url = "'https://`${$($vault.param)}`${environment().suffixes.keyvaultDns}/secrets/$secret'" }
}

# --- fragments -------------------------------------------------------------------------------------------

function Get-Fragment([string]$Kind, [hashtable]$Values, [hashtable]$Flags, [string]$File) {
    $file = $File
    if (-not $file) { $file = Join-Path $infra "catalog\$Kind.bicep" }
    if (-not (Test-Path $file)) { Fail "no $($file.Substring($infra.Length + 1)) for kind $Kind" }
    $text = (Get-Content $file -Raw -Encoding UTF8).Replace("`r`n", "`n")
    # A placeholder alone on its line with nothing to fill: the line goes (no empty lines in YAML steps).
    foreach ($k in $Values.Keys) { if (-not [string]$Values[$k]) { $text = [regex]::Replace($text, "(?m)^[ \t]*\{\{$k\}\}\n", '') } }
    $text = [regex]::Replace($text, '(?ms)^//#if (\w+)\n(.*?)^//#end\n', [Text.RegularExpressions.MatchEvaluator] {
            param($m)
            if ($Flags[$m.Groups[1].Value]) { return $m.Groups[2].Value }
            return ''
        })
    foreach ($k in $Values.Keys) { $text = $text.Replace("{{$k}}", [string]$Values[$k]) }
    # Actions by their short names (catalog/workflows/actions.json).
    $text = [regex]::Replace($text, '\{\{action:([\w-]+)\}\}', [Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $a = $actions.($m.Groups[1].Value)
            if (-not $a) { Fail "catalog/workflows/actions.json has no action $($m.Groups[1].Value)" }
            return [string]$a
        })
    $left = [regex]::Match($text, '\{\{(\w+)\}\}')
    if ($left.Success) { Fail "catalog/$Kind.bicep: nothing fills {{$($left.Groups[1].Value)}}" }
    return $text.TrimEnd()
}
function Get-SizeOptions($Def) { return '[' + ((@($Def.size.options) | ForEach-Object { Get-Quoted $_ }) -join ', ') + ']' }

# The values of one resource's fragment.
function Get-Section($Def) {
    $key = [string]$Def.key
    $v = @{ key = $key; name = [string]$Def.param; group = [string]$Def.groupParam; title = [string]$Def.title }
    # The production environment's name (naming.json), for what only production gets (backups...).
    $v.productionName = [string]$naming.environments.prod
    $f = @{}
    if ($Def.size) { $v.size = [string]$Def.size.param; $v.sizeOptions = Get-SizeOptions $Def; $v.sizeDefault = [string]$Def.size.default }
    switch ([string]$Def.kind) {
        'appService' {
            $host_ = @(Get-Links $key 'host') | Select-Object -First 1
            if (-not $host_) { Fail "$key needs a host connection (the App Service plan it runs on)" }
            $v.hostId = "$($host_.to)Id"
            $v.runtime = [string]$Def.runtime
            $v.healthCheckPath = [string]$Def.healthCheckPath
            $f.health = [bool]$Def.healthCheckPath
            $v.settingsArray = Get-SettingsArray $Def '      '
            Set-AppIdentity $Def $v $f @()
        }
        'staticWebApp' {
            $f.settings = [bool]@($Def.appSettings).Count
            if ($f.settings) { $v.settingsObject = Get-SettingsObject $Def '  ' }
        }
        'functionApp' {
            $host_ = @(Get-Links $key 'host') | Select-Object -First 1
            if (-not $host_) { Fail "$key needs a host connection (the plan it runs on)" }
            $v.hostId = "$($host_.to)Id"
            $f.flex = (Get-Def $host_.to).kind -eq 'flexPlan'
            $f.plan = -not $f.flex
            $v.runtime = [string]$Def.runtime
            $parts = ([string]$Def.runtime).Split('|')
            $v.runtimeName = $parts[0].ToLower()
            $v.runtimeVersion = $parts[-1]
            if ($f.flex) {
                $store = Get-Def ([string]$Def.stateStorage)
                if (-not $store) { Fail "$key (Flex Consumption) needs stateStorage: the storage account for its packages and state" }
                $v.storage = $store.key
                $v.storageTitle = $store.title
                $v.container = ($key.ToLower() + '-packages')
            }
            $v.settingsArray = Get-SettingsArray $Def '      '
            $packages = @()
            if ($f.flex) { $packages = @("$($key)Packages") }
            Set-AppIdentity $Def $v $f $packages
            # The platform reads the deployment package as the app's identity.
            $v.deploymentAuthentication = "{ type: 'SystemAssignedIdentity' }"
            if ($f.identity) { $v.deploymentAuthentication = "{ type: 'UserAssignedIdentity', userAssignedIdentityResourceId: $($v.identity).id }" }
        }
        'containerApp' {
            if (-not (Get-Identity $Def)) { Fail "$key (containerApp) needs its own identity (an appIdentity of the map, its ""identity"")" }
            $environment = Get-ContainerAppPart $Def 'environment' 'containerAppsEnvironment' 'host'
            $registry = Get-ContainerAppPart $Def 'registry' 'containerRegistry' 'role'
            if (-not @(Get-Links $key 'role' | Where-Object { $_.to -eq $registry.key -and @($_.roles) -contains 'AcrPull' }).Count) { Fail "$key needs AcrPull on $($registry.key) (a role connection: its identity pulls the image)" }
            $v.environment = $environment.key
            $v.registry = $registry.key
            $v.image = "$($key)Image"
            $v.signInClientId = "$($key)SignInClientId"
            $v.containerName = Get-ContainerName $key
            $inv = [Globalization.CultureInfo]::InvariantCulture
            $port = 0
            if (-not [int]::TryParse([string]$Def.port, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { Fail "${key}: port $($Def.port) (1-65535)" }
            $v.port = [string]$port
            # Consumption: 0.25 to 4 vCPU in steps of 0.25, with 2 GiB of memory per vCPU.
            $cpu = 0.0
            if (-not [double]::TryParse([string]$Def.cpu, [Globalization.NumberStyles]::Float, $inv, [ref]$cpu) -or $cpu -lt 0.25 -or $cpu -gt 4 -or ($cpu * 4) -ne [Math]::Floor($cpu * 4)) { Fail "${key}: cpu $($Def.cpu) (0.25 to 4 in steps of 0.25)" }
            $memory = 0.0
            if (-not ([string]$Def.memory -match '^([0-9.]+)Gi$') -or -not [double]::TryParse($Matches[1], [Globalization.NumberStyles]::Float, $inv, [ref]$memory) -or $memory -ne 2 * $cpu) {
                Fail "${key}: cpu $($Def.cpu) needs memory $((2 * $cpu).ToString($inv))Gi (2 GiB per vCPU), not $($Def.memory)"
            }
            $v.cpu = $cpu.ToString($inv)
            $v.memory = "$($memory.ToString($inv))Gi"
            $min = 0; $max = 0
            if (-not [int]::TryParse([string]$Def.minReplicas, [ref]$min) -or -not [int]::TryParse([string]$Def.maxReplicas, [ref]$max) -or $min -lt 0 -or $max -lt 1 -or $max -gt 1000 -or $min -gt $max) {
                Fail "${key}: replicas $($Def.minReplicas)-$($Def.maxReplicas) (min 0 or more, max 1-1000, min <= max)"
            }
            $v.minReplicas = [string]$min
            $v.maxReplicas = [string]$max
            switch ([string]$Def.revisionMode) { 'single' { $v.revisionMode = 'Single' } 'multiple' { $v.revisionMode = 'Multiple' } default { Fail "${key}: revisionMode $($Def.revisionMode) (single or multiple)" } }
            switch ([string]$Def.ingress) { 'external' { $v.external = 'true' } 'internal' { $v.external = 'false' } default { Fail "${key}: ingress $($Def.ingress) (external or internal)" } }
            $v.affinity = 'none'
            if (@('yes', 'true') -contains [string]$Def.sticky) {
                if ($v.revisionMode -ne 'Single') { Fail "${key}: sticky sessions work in single revision mode only" }
                $v.affinity = 'sticky'
            }
            $health = [string]$Def.healthCheckPath
            $f.health = [bool]$health -and $health -ne '-'
            if ($f.health -and -not $health.StartsWith('/')) { Fail "${key}: healthCheckPath $health (a path from /)" }
            $v.healthPath = Get-Quoted $health
            # Settings: values as they are; Key Vault secrets by reference (secretRef), in their own list - only the
            # app's own image gets them (the hand secrets go into a new vault after the first start).
            $envLines = @('[')
            $secretEnvLines = @('[')
            $secretRefs = [ordered]@{}
            foreach ($s in @(Get-Settings $Def)) {
                $ref = Get-ContainerSecret $Def $s
                if ($ref) {
                    if ($secretRefs.Contains($ref.name) -and $secretRefs[$ref.name].url -ne $ref.url) { Fail "${key}: two Key Vault secrets are both $($ref.name) in lowercase (a Container Apps secret's name)" }
                    $secretRefs[$ref.name] = $ref
                    if ($s.about) { $secretEnvLines += "  // $($s.about)" }
                    $secretEnvLines += "  { name: $(Get-Quoted $s.name), secretRef: $(Get-Quoted $ref.name) }"
                } else {
                    if ($s.about) { $envLines += "  // $($s.about)" }
                    $envLines += "  { name: $(Get-Quoted $s.name), value: $(Get-ValueBicep $s.value) }"
                }
            }
            $v.settingsArray = ($envLines + ']') -join "`n"
            $f.secrets = [bool]$secretRefs.Count
            $v.secretsArray = ''
            $v.secretSettingsArray = ''
            $v.envExpr = "$($key)Settings"
            if ($f.secrets) {
                $v.secretsArray = "[`n" + ((@($secretRefs.Values | ForEach-Object { "  { name: $(Get-Quoted $_.name), keyVaultUrl: $($_.url), identity: $($Def.identity).id }" })) -join "`n") + "`n]"
                $v.secretSettingsArray = ($secretEnvLines + ']') -join "`n"
                $v.envExpr = "$($key)Real ? concat($($key)Settings, $($key)SecretSettings) : $($key)Settings"
            }
            # Its own image only when it has one (not the placeholder) and, with sign-in, once the sign-in exists.
            $f.signIn = Test-SignIn $Def
            $v.realExpr = "!empty($($v.image)) && $($v.image) != $($key)Placeholder"
            $v.realComment = ''
            if ($f.signIn) {
                $v.realExpr += " && !empty($($v.signInClientId))"
                $v.realComment = '// Behind sign-in: its own image only once the sign-in exists (a client id), never before.'
                $v.redirectLine = ''
                switch ([string]$Def.signIn.unauthenticated) {
                    { @('', 'redirect') -contains $_ } { $v.unauthenticatedAction = 'RedirectToLoginPage'; $v.redirectLine = "      redirectToProvider: 'azureactivedirectory'" }
                    '401' { $v.unauthenticatedAction = 'Return401' }
                    '403' { $v.unauthenticatedAction = 'Return403' }
                    default { Fail "${key}: signIn.unauthenticated $($Def.signIn.unauthenticated) (redirect, 401 or 403)" }
                }
                # The health path always (the deploy waits for it), and for each /x/* also /x (Get-SignInExcludedPaths).
                $unique = @(Get-SignInExcludedPaths $Def)
                $v.excludedPaths = '[' + ((@($unique | ForEach-Object { Get-Quoted $_ })) -join ', ') + ']'
                $v.excludedNote = 'none'
                if ($unique.Count) { $v.excludedNote = $unique -join ', ' }
                $audiences = @($v.signInClientId)
                if (@('true', 'yes') -contains [string]$Def.signIn.identifierUri) { $audiences += "'api://`${$($v.signInClientId)}'" }
                $v.audiences = '[' + ($audiences -join ', ') + ']'
            }
            # Its logs from its first revision on; its identity's roles and Key Vault reads before it starts.
            Set-AppIdentity $Def $v $f @("$($environment.key)Logs")
        }
        'containerAppsEnvironment' {
            $ws = @(Get-Links $key 'logs') | Select-Object -First 1
            if (-not $ws -or (Get-Def $ws.to).kind -ne 'logAnalytics') { Fail "$key needs a logs connection (its Log Analytics workspace)" }
            $v.workspaceId = "$($ws.to)Id"
            $v.workspaceName = [string](Get-Def $ws.to).param
            $v.workspaceTitle = [string](Get-Def $ws.to).title
        }
        'appIdentity' { $v.owner = [string](Get-Def ([string]$Def.owner)).title }
        'sqlServer' {
            $v.adminLogin = [string]$Def.admin.loginParam
            $v.adminSid = [string]$Def.admin.sidParam
            $v.adminType = [string]$Def.admin.typeParam
        }
        'sqlDatabase' {
            $host_ = @(Get-Links $key 'host') | Select-Object -First 1
            $server = $null
            if ($host_) { $server = Get-Def $host_.to }
            if (-not $server -or $server.kind -ne 'sqlServer') { Fail "$key needs a host connection to its SQL server" }
            $v.server = $server.key
            $v.serverName = $server.param
            $v.serverTitle = $server.title
            $v.deployName = "'sql-database-`${$($Def.param)}'"
        }
        'serviceBus' {
            $lines = @()
            $i = 0
            foreach ($q in @($Def.queues | Where-Object { $_ })) {
                $i++
                $lines += ''
                $lines += "resource $($key)Queue$i 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {"
                $lines += "  parent: $key"
                $lines += "  name: $(Get-Quoted $q)"
                $lines += "  properties: { maxDeliveryCount: 10, lockDuration: 'PT1M', deadLetteringOnMessageExpiration: true }"
                $lines += '}'
            }
            $v.queues = $lines -join "`n"
        }
        { $_ -eq 'storageQueue' -or $_ -eq 'blobContainer' } {
            $host_ = @(Get-Links $key 'host') | Select-Object -First 1
            $parent = $null
            if ($host_) { $parent = Get-Def $host_.to }
            if (-not $parent -or $parent.kind -ne 'storage') { Fail "$key needs a host connection to its storage account" }
            $v.parent = $parent.key
            $v.parentTitle = $parent.title
        }
        'eventGridSubscription' {
            # The source's system topic (its type by the source's kind) and the function it delivers to.
            $src = $null; $dst = $null
            $l = @(Get-Links $key 'source') | Select-Object -First 1
            if ($l) { $src = Get-Def $l.to }
            $l = @(Get-Links $key 'deliver') | Select-Object -First 1
            if ($l) { $dst = Get-Def $l.to }
            $topicTypes = @{ appConfiguration = 'Microsoft.AppConfiguration.ConfigurationStores'; storage = 'Microsoft.Storage.StorageAccounts'; serviceBus = 'Microsoft.ServiceBus.Namespaces' }
            if (-not $src -or -not $topicTypes.ContainsKey([string]$src.kind)) { Fail "$key needs a source connection to an App Configuration, a storage account or a Service Bus" }
            if (-not $dst -or $dst.kind -ne 'functionApp') { Fail "$key needs a deliver connection to a Function App" }
            if (-not $Def.function) { Fail "$key has no function (the one that gets the events)" }
            $v.source = $src.key
            $v.sourceTitle = $src.title
            $v.topicType = $topicTypes[[string]$src.kind]
            $v.target = $dst.key
            $v.targetTitle = $dst.title
            $v.function = [string]$Def.function
            $v.ready = [string]$Def.ready.param
            $types = @(([string]$Def.eventTypes).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne '-' })
            $v.eventTypes = ''
            if ($types.Count) { $v.eventTypes = "      includedEventTypes: [$((@($types | ForEach-Object { Get-Quoted $_ })) -join ', ')]" }
            $v.filters = ''
            if ($Def.filterKey -and $Def.filterKey -ne '-' -and $Def.filterEndsWith -and $Def.filterEndsWith -ne '-') {
                $v.filters = "      advancedFilters: [{ operatorType: 'StringEndsWith', key: $(Get-Quoted $Def.filterKey), values: [$(Get-Quoted $Def.filterEndsWith)] }]"
            }
        }
        'frontDoor' {
            $o = @(Get-Links $key 'origin') | Select-Object -First 1
            $origin = $null
            if ($o) { $origin = Get-Def $o.to }
            if (-not $origin -or @('staticWebApp', 'appService', 'functionApp') -notcontains $origin.kind) { Fail "$key needs an origin connection to an app (a Static Web App, an App Service or a Function App)" }
            $v.origin = $origin.key
            $v.originTitle = $origin.title
            $v.originHost = Get-TokenBicep "$($origin.key).host"
            $v.probePath = '/'
            if ($origin.healthCheckPath) { $v.probePath = [string]$origin.healthCheckPath }
            $f.cache = $Def.cache -ne 'off'
        }
        'logAnalytics' {
            # Needed by a new Application Insights (its <key>New), always by a Container Apps environment.
            $users = @(Get-LinksTo $key 'logs' | ForEach-Object { if ((Get-Def $_.from).kind -eq 'appInsights') { "$($_.from)New" } else { 'true' } })
            $v.needed = 'false'
            if ($users -contains 'true') { $v.needed = 'true' }
            elseif ($users.Count) { $v.needed = $users -join ' || ' }
        }
        'appInsights' {
            $ws = @(Get-Links $key 'logs') | Select-Object -First 1
            if (-not $ws) { Fail "$key needs a logs connection (its Log Analytics workspace)" }
            $v.workspaceId = "$($ws.to)Id"
            $n = $v.name
            $g = $v.group
            if (Test-Optional $Def) {
                $v.nameDefault = " = ''"
                $v.optionalNote = ' Empty: none.'
                $v.newExpr = "!empty($n) && empty($g)"
                $v.existingExpr = "!empty($n) && !empty($g)"
                $v.nameExpr = "!empty($n) ? $n : 'none'"
            } else {
                $v.nameDefault = ''
                $v.optionalNote = ''
                $v.newExpr = "empty($g)"
                $v.existingExpr = "!empty($g)"
                $v.nameExpr = $n
            }
        }
        'keyVault' {
            $readers = @(Get-LinksTo $key 'role' | Where-Object { @($_.roles) -contains 'Key Vault Secrets User' } | ForEach-Object { $_.from })
            foreach ($c in @(Get-LinksTo $key 'role')) { foreach ($r in @($c.roles)) { if ($r -ne 'Key Vault Secrets User') { Fail "$($c.from) -> ${key}: role $r on a Key Vault isn't supported yet (only Key Vault Secrets User)" } } }
            $first = $v.name
            if ($readers.Count) { $first = (Get-Def $readers[0]).param }
            $v.accessName = "'vault-access-`${$first}'"
            if ($readers.Count) { $v.readers = "[`n" + ((@($readers | ForEach-Object { $r = Get-Def $_; "      { id: $(Get-PrincipalKey $r).id, principalId: $(Get-PrincipalExpr $r) }" })) -join "`n") + "`n    ]" } else { $v.readers = '[]' }
            $kept = @(@($Def.secrets) | Where-Object { $_ -and $_.by -eq 'setup' })
            if ($kept.Count) {
                $v.secretValues = "{`n" + ((@($kept | ForEach-Object { "      $(Get-Quoted $_.name): $($_.param)" })) -join "`n") + "`n    }"
                $writes = @($kept | ForEach-Object { "$($_.writeParam) ? [$(Get-Quoted $_.name)] : []" })
                if ($writes.Count -eq 1) { $v.writeSecrets = $writes[0] } else { $v.writeSecrets = "concat($($writes -join ', '))" }
            } else { $v.secretValues = '{}'; $v.writeSecrets = '[]' }
        }
    }
    return Get-Fragment ([string]$Def.kind) $v $f
}

# --- main.bicep --------------------------------------------------------------------------------------------

# The role assignments of the apps' identities (Key Vault roles: in its module), numbered as main.bicep names
# them: an app's section waits for its own.
function Get-RoleAssignments {
    $list = @()
    $n = 0
    foreach ($c in @($map.connections | Where-Object { $_.kind -eq 'role' })) {
        $to = Get-Def $c.to
        $from = Get-Def $c.from
        if (-not $to -or -not $from) { Fail "role connection $($c.from) -> $($c.to): no such resource" }
        if ($to.kind -eq 'keyVault') { continue }
        if ($to.groupParam) { Fail "role connection $($c.from) -> $($c.to): roles on a resource that may be shared from another group aren't supported yet" }
        foreach ($role in @($c.roles)) {
            $id = $roles.$role
            if (-not $id) { Fail "role '$role': not in catalog/roles.json" }
            $n++
            $list += [pscustomobject]@{ connection = $c; from = $from; to = $to; role = $role; id = $id; sym = "$($from.key)Role$n" }
        }
    }
    return $list
}

function Get-Bicep {
    foreach ($d in $defs) { if (-not $d.kind) { Fail "$($d.key) has no kind" } }
    # An app identity belongs to the one app that names it (and names it back as its owner).
    foreach ($d in @($defs | Where-Object { $_.kind -eq 'appIdentity' })) {
        $owner = Get-Def ([string]$d.owner)
        if (-not $owner -or [string]$owner.identity -ne [string]$d.key) { Fail "$($d.key): no app of the map owns this identity (its owner $($d.owner) must name it as its identity)" }
    }
    $script:roleAssignments = @(Get-RoleAssignments)
    $out = New-Object Collections.Generic.List[string]
    $out.Add('// GENERATED by infra/generate.ps1 from infra/infra.map.json and infra/catalog/: don''t edit it here.')
    $out.Add('// Change the map (infra/README.md, "The map") or the catalog, then run .\infra\generate.ps1.')
    $out.Add('//')
    $out.Add("// $($map.project.name): $($map.project.description).")
    $out.Add('// Every name comes from infra/azure-setup.ps1 (infra/naming.json rules, infra/environments/<env>.json); a')
    $out.Add('// shared resource with an empty <x>Group is created and managed here (tagged managed-by), otherwise it is an')
    $out.Add('// existing one of that group, used as it is.')
    $out.Add('')
    $out.Add("@description('Region of every new resource except the Static Web Apps.')")
    $out.Add('param location string = resourceGroup().location')
    if (@($defs | Where-Object { $_.kind -eq 'staticWebApp' }).Count) {
        $out.Add('')
        $out.Add("@description('Region of the Static Web Apps (offered in a few regions only).')")
        $out.Add("@allowed([$((@($map.regions.staticWebApp) | ForEach-Object { Get-Quoted $_ }) -join ', ')])")
        $out.Add("param staticLocation string = $(Get-Quoted $map.regions.default)")
    }
    $out.Add('')
    $out.Add("@description('Environment, full name (production, test, staging, development, acceptance): a tag.')")
    $out.Add('param environmentName string')
    $out.Add('')
    $out.Add("@description('Client-project and sub application prefix: a tag.')")
    $out.Add('param project string')
    foreach ($dm in @($map.domains | Where-Object { $_.param })) {
        $out.Add('')
        $out.Add("@description('The custom domain of the $($dm.what); empty = none yet.')")
        $out.Add("param $($dm.param) string = ''")
    }
    foreach ($mv in @($map.values | Where-Object { $_ -and $_.param })) {
        $out.Add('')
        $out.Add("@description($(Get-Quoted "$($mv.label): asked per environment."))")
        $out.Add("param $($mv.param) string = ''")
    }
    if (@($defs | Where-Object { @('keyVault', 'appConfiguration') -contains $_.kind }).Count) {
        $out.Add('')
        $out.Add("@description('Object id of the person running the setup: Key Vault Secrets Officer, App Configuration Data Owner (the secrets and keys put in by hand); empty = none.')")
        $out.Add("param ownerObjectId string = ''")
    }
    foreach ($d in $defs) {
        foreach ($s in @($d.secrets | Where-Object { $_ -and $_.by -eq 'setup' })) {
            $out.Add('')
            $out.Add("@description($(Get-Quoted "$($s.about); kept in the vault."))")
            $out.Add('@secure()')
            $out.Add("param $($s.param) string")
            $out.Add('')
            $out.Add("@description('Write $($s.param) to the vault (infra/azure-setup.ps1: only when it is missing there or differs).')")
            $out.Add("param $($s.writeParam) bool = true")
        }
    }
    $out.Add('')
    $out.Add("var tags = { project: project, environment: environmentName, 'managed-by': $(Get-Quoted $map.project.managedByTag) }")
    $out.Add('var here = resourceGroup().name')

    foreach ($d in $defs) {
        if ($noBicep -contains $d.kind) { continue }
        $out.Add('')
        $out.Add("// --- $($d.title) ($($d.key), $($d.kind)) $('-' * [Math]::Max(3, 90 - $d.title.Length - $d.key.Length - $d.kind.Length))")
        $out.Add('')
        $out.Add((Get-Section $d))
    }

    # Roles of the apps' managed identities (Key Vault roles: in its module above).
    $n = 0
    foreach ($r in $script:roleAssignments) {
        $n++
        if ($n -eq 1) { $out.Add(''); $out.Add('// --- Roles of the apps'' managed identities ' + ('-' * 60)) }
        $out.Add('')
        $out.Add("// $($r.from.title) -> $($r.to.title): $($r.role)$(if ($r.connection.what) { " ($($r.connection.what))" })")
        $out.Add("resource $($r.sym) 'Microsoft.Authorization/roleAssignments@2022-04-01' = {")
        $out.Add("  scope: $($r.to.key)")
        $out.Add("  name: guid($($r.to.key).id, $(Get-PrincipalKey $r.from).id, '$($r.id)')")
        $out.Add('  properties: {')
        $out.Add("    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '$($r.id)')")
        $out.Add("    principalId: $(Get-PrincipalExpr $r.from)")
        $out.Add("    principalType: 'ServicePrincipal'")
        $out.Add('  }')
        $out.Add('}')
    }

    $out.Add('')
    foreach ($d in $defs) {
        if ($d.kind -eq 'appService' -or $d.kind -eq 'functionApp') {
            $out.Add("output $($d.key)HostName string = $($d.key).properties.defaultHostName")
            $out.Add("output $($d.key)VerificationId string = $($d.key).properties.customDomainVerificationId")
        } elseif ($d.kind -eq 'staticWebApp') { $out.Add("output $($d.key)HostName string = $($d.key).properties.defaultHostname") }
        elseif ($d.kind -eq 'appIdentity') { $out.Add("output $($d.key)ClientId string = $($d.key).properties.clientId") }
        elseif ($d.kind -eq 'containerApp') { $out.Add("output $($d.key)HostName string = $($d.key).properties.configuration.ingress.fqdn") }
        elseif ($d.kind -eq 'containerRegistry') { $out.Add("output $($d.key)LoginServer string = $($d.key).properties.loginServer") }
        elseif ($d.kind -eq 'frontDoor') { $out.Add("output $($d.key)HostName string = $($d.key)Endpoint.properties.hostName") }
    }
    return (($out -join "`n") + "`n")
}

# --- the deploy workflows (.github/workflows) ---------------------------------------------------------------

# Each app with a "deploy" in the map gets its GitHub Actions workflow, from catalog/workflows/<kind>.yml:
# what it builds from which folder (its source and paths: the push trigger), how, and where it publishes
# (its app in the environment the branch belongs to: infra/route.ps1). The push trigger's branches are the
# environments' deploy branches (infra/environments/*.json), or every branch when the app tests on all.
$repoRoot = Split-Path $infra -Parent
$workflowDir = Join-Path $repoRoot '.github\workflows'
$generatedMark = '# GENERATED by infra/generate.ps1'

function Get-EnvBranches {
    return @(Get-ChildItem (Join-Path $infra 'environments') -Filter '*.json' -ErrorAction SilentlyContinue |
            ForEach-Object { [string](Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).branch } |
            Where-Object { $_ -and $_ -ne '-' } | Sort-Object -Unique)
}
function Get-YamlQuoted([string]$Text) { return "'" + $Text.Replace("'", "''") + "'" }
# A step of the map: { name, id, workingDirectory, run, comment }; $If on every step of a job that skips
# when the environment isn't set up.
# An action by its short name in catalog/workflows/actions.json (checkout -> actions/checkout@v7), or as given.
function Get-Action([string]$Name) {
    if ($actions.$Name) { return [string]$actions.$Name }
    return $Name
}
# A value of "with:" or an input: numbers and booleans as they are; text plain when YAML reads it as text,
# else quoted (a version like '8.7' stays text).
function Get-YamlValue($Value) {
    if ($Value -is [bool]) { if ($Value) { return 'true' } return 'false' }
    if ($Value -is [ValueType]) { return [string]$Value }
    $t = [string]$Value
    if ($t -match '^[0-9]' -or $t -match ': | #' -or $t -match '^[\[\]{}&*!|>''"%@`#,?:-]' -or @('true', 'false', 'null', 'yes', 'no', '~', '') -contains $t.ToLower()) { return Get-YamlQuoted $t }
    return $t
}
# A step of the map: { comment, name, if, id, uses, with, env, workingDirectory, run }; $If on every step of a
# job that skips when the environment isn't set up. env: the step's environment (e.g. a feed key from a secret).
function Get-StepYaml($Step, [string]$If) {
    $lines = @()
    foreach ($c in @($Step.comment | Where-Object { $_ })) { $lines += "      # $c" }
    $fields = @()
    if ($Step.name) { $fields += "name: $($Step.name)" }
    $condition = $If
    if ($Step.if) { $condition = [string]$Step.if }
    if ($condition) { $fields += "if: $condition" }
    if ($Step.id) { $fields += "id: $($Step.id)" }
    if ($Step.uses) { $fields += "uses: $(Get-Action ([string]$Step.uses))" }
    if ($Step.with) {
        $fields += 'with:'
        foreach ($p in $Step.with.PSObject.Properties) { $fields += "  $($p.Name): $(Get-YamlValue $p.Value)" }
    }
    if ($Step.env) {
        $fields += 'env:'
        foreach ($p in $Step.env.PSObject.Properties) { $fields += "  $($p.Name): $($p.Value)" }
    }
    if ($Step.workingDirectory) { $fields += "working-directory: $($Step.workingDirectory)" }
    if ($Step.shell) { $fields += "shell: $($Step.shell)" }
    if ($Step.run) {
        $run = ([string]$Step.run).Replace("`r", '')
        # One plain line when YAML reads it as it is, else a block.
        if ($run -notmatch "`n" -and $run -notmatch ': | #' -and $run -notmatch '^[\[\]{}&*!|>''"%@`#,?:-]') { $fields += "run: $run" }
        else {
            $fields += 'run: |'
            foreach ($l in $run.Split("`n")) { $fields += "  $l" }
        }
    }
    for ($i = 0; $i -lt $fields.Count; $i++) {
        if ($i -eq 0) { $lines += "      - $($fields[$i])" } else { $lines += "        $($fields[$i])" }
    }
    return ($lines -join "`n")
}

# A build of the map ("builds": a workflow of no Azure resource: build, test, pack...): its triggers,
# manual-run inputs and jobs, written out as they are.
function Get-BuildWorkflow($Build, [string[]]$EnvBranches, [string[]]$EnvNames) {
    $out = New-Object Collections.Generic.List[string]
    $out.Add("$generatedMark from infra/infra.map.json (the build $($Build.workflow)): don't edit it here.")
    $out.Add('# Change "builds" in the map, then run .\infra\generate.ps1.')
    $out.Add('#')
    foreach ($a in @($Build.about | Where-Object { $_ })) { $out.Add("# $a") }
    $out.Add("name: $($Build.name)")
    $out.Add('')
    $out.Add('on:')
    # Its branches: named ones, and "{environments}" for the environments' deploy branches.
    $branches = @()
    foreach ($b in @($Build.branches | Where-Object { $_ })) { if ($b -eq '{environments}') { $branches += $EnvBranches } else { $branches += [string]$b } }
    $branches = @($branches | Select-Object -Unique)
    if ($branches.Count) {
        $out.Add('  push:')
        $out.Add('    branches: [' + ((@($branches | ForEach-Object { Get-YamlQuoted $_ })) -join ', ') + ']')
        $paths = @($Build.paths | Where-Object { $_ }) + ".github/workflows/$($Build.workflow)"
        $out.Add('    paths:')
        foreach ($p in $paths) {
            if ($p -is [string]) { $out.Add("      - $(Get-YamlQuoted $p)") }
            else { foreach ($c in @($p.comment | Where-Object { $_ })) { $out.Add("      # $c") }; $out.Add("      - $(Get-YamlQuoted $p.path)") }
        }
    }
    $out.Add('  workflow_dispatch:')
    if ($Build.inputs) {
        $out.Add('    inputs:')
        foreach ($i in $Build.inputs.PSObject.Properties) {
            $out.Add("      $($i.Name):")
            if ($i.Value.description) { $out.Add("        description: $(Get-YamlQuoted ([string]$i.Value.description))") }
            if ($i.Value.type) { $out.Add("        type: $($i.Value.type)") }
            if ($i.Value.options) { $out.Add('        options: [' + ((@($i.Value.options) | ForEach-Object { [string]$_ }) -join ', ') + ']') }
            if ($null -ne $i.Value.default) { $out.Add("        default: $(Get-YamlValue $i.Value.default)") }
        }
    }
    if ($Build.permissions) {
        $out.Add('')
        $out.Add('permissions:')
        foreach ($p in $Build.permissions.PSObject.Properties) { $out.Add("  $($p.Name): $($p.Value)") }
    }
    $out.Add('')
    $out.Add('jobs:')
    $first = $true
    foreach ($j in @($Build.jobs | Where-Object { $_ })) {
        if (-not $first) { $out.Add('') }
        $first = $false
        $out.Add("  $($j.id):")
        if ($j.name) { $out.Add("    name: $($j.name)") }
        $needs = @($j.needs | Where-Object { $_ })
        if ($needs.Count -eq 1) { $out.Add("    needs: $($needs[0])") } elseif ($needs.Count) { $out.Add('    needs: [' + ($needs -join ', ') + ']') }
        if ($j.if) { $out.Add("    if: $($j.if)") }
        $out.Add("    runs-on: $($j.runsOn)")
        if ($j.permissions) {
            $out.Add('    permissions:')
            foreach ($p in $j.permissions.PSObject.Properties) { $out.Add("      $($p.Name): $($p.Value)") }
        }
        $out.Add('    steps:')
        $steps = Get-StepsYaml $j.steps ''
        if ($steps) { $out.Add($steps) }
    }
    return (($out -join "`n") + "`n")
}
function Get-StepsYaml($Steps, [string]$If) { return ((@($Steps | Where-Object { $_ }) | ForEach-Object { Get-StepYaml $_ $If }) -join "`n") }

# The dotnet-ef the bundle is built with: the project's EF Core version (its PackageReference, or central
# package management's Directory.Packages.props), else the app's .NET major (EF Core's majors follow .NET's);
# the latest could need a runtime the workflow doesn't install.
function Get-EfVersion([string]$Project, [string]$Dotnet) {
    $dir = Join-Path $repoRoot $Project
    $found = ''
    $proj = @(Get-ChildItem $dir -Filter '*.csproj' -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($proj) {
        $m = [regex]::Match((Get-Content $proj.FullName -Raw), '<PackageReference\s+Include="Microsoft\.EntityFrameworkCore(\.[\w.]+)?"\s+Version="([0-9][^"$]*)"')
        if ($m.Success) { $found = $m.Groups[2].Value }
    }
    for ($d = $dir; -not $found -and $d -and $d.Length -ge $repoRoot.Length; $d = Split-Path $d -Parent) {
        $props = Join-Path $d 'Directory.Packages.props'
        if (-not (Test-Path $props)) { continue }
        $m = [regex]::Match((Get-Content $props -Raw), '<PackageVersion\s+Include="Microsoft\.EntityFrameworkCore(\.[\w.]+)?"\s+Version="([0-9][^"$]*)"')
        if ($m.Success) { $found = $m.Groups[2].Value }
    }
    if ($found) { return $found }
    if ($Dotnet -match '^(\d+)') { return "$($Matches[1]).*" }
    return ''
}
# Database migrations (an app's deploy.migrate): the setting the apps read (ConnectionStrings__<Key>, as the
# sqlDatabase's "users" settings name it) and the GitHub environment's variable (or secret) with the connection
# string the workflow migrates with (azure-setup.ps1 sets the variable: the same name rule).
function Get-MigrationConnection([string]$DatabaseKey) { return $DatabaseKey.Substring(0, 1).ToUpper() + $DatabaseKey.Substring(1) }
function Get-MigrationVariable([string]$DatabaseKey) { return 'AZURE_' + ($DatabaseKey -creplace '([a-z0-9])([A-Z])', '$1_$2').ToUpper() + '_CONNECTION' }

# The GitHub environment's variable whose value is $Value ({<key>.name}, {<key>.group}): its name in a workflow.
function Get-WorkflowVariable([string]$Value, [string]$Key, [string]$What) {
    $var = @($map.github.variables.PSObject.Properties | Where-Object { [string]$_.Value -eq $Value }) | Select-Object -First 1
    if (-not $var) { Fail "${Key}: no github.variables entry with $Value ($What, for its workflow)" }
    return [string]$var.Name
}

function Get-Workflows {
    $out = [ordered]@{}
    # A manual run offers production last and never preselects it: deploying there is a choice, not a default.
    $prodName = [string]$naming.environments.prod
    $envNames = @(@($naming.environments.PSObject.Properties | ForEach-Object { [string]$_.Value } | Where-Object { $_ -ne $prodName }) + @($prodName | Where-Object { $_ }))
    $defaultEnv = $envNames[0]
    $envBranches = @(Get-EnvBranches)
    foreach ($d in @($defs | Where-Object { $_.deploy })) {
        $dep = $d.deploy
        $template = Join-Path $infra "catalog\workflows\$($d.kind).yml"
        if (-not (Test-Path $template)) { Fail "$($d.key): no catalog/workflows/$($d.kind).yml for its deploy" }
        if (-not $dep.workflow) { Fail "$($d.key): deploy has no workflow (its file name in .github/workflows)" }
        $v = @{ key = $d.key; name = [string]$dep.name }
        $f = @{}
        $v.about = ((@($dep.about | Where-Object { $_ }) | ForEach-Object { "# $_" }) -join "`n")
        if (-not $v.about) { $v.about = "# $($d.title): $($dep.source) -> $($d.kind) $($d.key)" }
        # The trigger: the source folder, the other paths, the workflow itself; the branches.
        $paths = @()
        if ($dep.source) { $paths += "$($dep.source)/**" }
        foreach ($p in @($dep.paths | Where-Object { $_ })) { $paths += $p }
        # The migrations' project too, when it isn't in the source folder (a new migration deploys).
        if ($dep.migrate -and $dep.migrate.project) {
            $mp = ([string]$dep.migrate.project).Trim('/', '\').Replace('\', '/')
            if (-not $dep.source -or -not ($mp -eq $dep.source -or $mp.StartsWith("$($dep.source)/"))) { $paths += "$mp/**" }
        }
        $paths += ".github/workflows/$($dep.workflow)"
        $v.paths = ((@($paths | ForEach-Object {
                        if ($_ -is [string]) { "      - $(Get-YamlQuoted $_)" }
                        else { @(@($_.comment | Where-Object { $_ }) | ForEach-Object { "      # $_" }) + "      - $(Get-YamlQuoted $_.path)" -join "`n" }
                    })) -join "`n")
        if ($dep.everyBranch) {
            $v.branches = "['**']"
            $v.branchesNote = ' # every branch (its tests); deploys only from an environment''s branch (route)'
            $f.push = $true
        } else {
            $v.branches = '[' + ((@($envBranches | ForEach-Object { Get-YamlQuoted $_ })) -join ', ') + ']'
            $v.branchesNote = ' # the environments'' deploy branches (infra/environments/*.json)'
            $f.push = [bool]$envBranches.Count
        }
        $v.environments = '[' + ($envNames -join ', ') + ']'
        $v.defaultEnvironment = $defaultEnv
        $v.beforeBuild = ''
        # The deploy's "env": step environment of the build steps only (publish, migration bundle), e.g. a
        # package feed's key from a secret - never the whole job's, so the deploy actions don't see it.
        $v.stepEnv = ''
        if ($dep.env) {
            $envLines = @('        env:') + @($dep.env.PSObject.Properties | ForEach-Object { "          $($_.Name): $($_.Value)" })
            $v.stepEnv = $envLines -join "`n"
        }
        $v.healthPath = ''
        $v.afterDeploy = ''
        if ($d.kind -eq 'staticWebApp') {
            $f.node = [bool]$dep.node
            $v.node = [string]$dep.node
            $v.source = [string]$dep.source
            $v.nodeComment = ((@($dep.nodeComment | Where-Object { $_ }) | ForEach-Object { "      # $_" }) -join "`n")
            $v.beforeBuild = Get-StepsYaml $dep.beforeBuild ''
            $v.buildStep = ''
            if ($dep.build) {
                $b = $dep.build
                if (-not $b.workingDirectory) { $b | Add-Member -NotePropertyName workingDirectory -NotePropertyValue ([string]$dep.source) -Force }
                $v.buildStep = Get-StepYaml $b ''
            }
            $token = @($map.github.tokenSecrets | Where-Object { $_ -and $_.resource -eq $d.key }) | Select-Object -First 1
            if (-not $token) { Fail "$($d.key): no github.tokenSecrets entry (its deployment token)" }
            $v.tokenExpr = "secrets.$($token.name)"
            if ($dep.tokenFallback) { $v.tokenExpr += " || secrets.$($dep.tokenFallback)" }
            $v.app = [string]$dep.app
            $v.api = [string]$dep.api
            $v.appComment = ''
            $v.apiComment = ''
            if ($dep.appComment) { $v.appComment = " # $($dep.appComment)" }
            if ($dep.apiComment) { $v.apiComment = " # $($dep.apiComment)" }
            $v.afterDeploy = Get-StepsYaml $dep.afterDeploy ''
        } elseif ($d.kind -eq 'containerApp') {
            # The image is built on the runner and pushed to the app's registry (AcrPush), then only the app's image
            # changes (Container Apps Contributor). The environment's variables: the app's name and resource group,
            # the registry's name.
            $v.appVar = Get-WorkflowVariable "{$($d.key).name}" $d.key 'the app''s name'
            $v.groupVar = Get-WorkflowVariable "{$($d.key).group}" $d.key 'the app''s resource group'
            $registry = Get-ContainerAppPart $d 'registry' 'containerRegistry' 'role'
            $v.registryVar = Get-WorkflowVariable "{$($registry.key).name}" $d.key "the name of its registry $($registry.key)"
            if ($dep.migrate) { Fail "$($d.key): deploy.migrate isn't supported for a container app yet (migrate from an App Service or Function App deploy)" }
            $v.repository = Get-ContainerName $d.key
            $v.containerName = $v.repository
            $v.placeholder = $containerPlaceholder
            $dockerfile = [string]$dep.dockerfile
            if (-not $dockerfile) { $dockerfile = (@([string]$dep.source, 'Dockerfile') | Where-Object { $_ }) -join '/' }
            $context = [string]$dep.context
            if (-not $context) { $context = '.' }
            $v.dockerfile = Get-YamlQuoted $dockerfile
            $v.context = Get-YamlQuoted $context
            # The deploy's "env" (e.g. a package feed's key from a secret): BuildKit secrets of the build step only,
            # never build arguments (those stay in the image's history).
            $v.buildEnv = ''
            $v.buildSecrets = ''
            if ($dep.env) {
                $names = @($dep.env.PSObject.Properties | ForEach-Object { $_.Name })
                foreach ($n in $names) { if ($n -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { Fail "$($d.key): deploy.env $n isn't an environment variable name" } }
                $v.buildEnv = (@($dep.env.PSObject.Properties | ForEach-Object { "          $($_.Name): $($_.Value)" })) -join "`n"
                $v.buildSecrets = (@($names | ForEach-Object { " --secret id=$_,env=$_" })) -join ''
            }
            $f.test = [bool]$dep.test
            $v.testStep = ''
            $v.testSetup = ''
            if ($dep.test) {
                $v.testStep = Get-StepYaml $dep.test ''
                if ($dep.dotnet) { $v.testSetup = "      - uses: $(Get-Action 'setup-dotnet')`n        with:`n          dotnet-version: $(Get-YamlQuoted ([string]$dep.dotnet))" }
            }
            $v.needs = 'route'
            if ($f.test) { $v.needs = 'test, route' }
            $v.beforeBuild = Get-StepsYaml $dep.beforeBuild 'steps.env.outputs.ready'
            # A push-only run (the setup's step First image) ends after the push.
            $v.afterDeploy = Get-StepsYaml $dep.afterDeploy 'steps.env.outputs.ready && !inputs.push-only'
            # Never its own image before its sign-in exists.
            $f.signIn = Test-SignIn $d
            # The health wait: the new revision ready, and its health path answering when the runner can reach it.
            $health = [string]$d.healthCheckPath
            $v.healthPath = "''"
            $v.healthNote = ''
            if ($health -and $health -ne '-' -and [string]$d.ingress -ne 'internal') { $v.healthPath = Get-YamlQuoted $health; $v.healthNote = " and $health answers 2xx" }
        } else {
            # The app's name in the GitHub environment: the variable whose value is {<key>.name}.
            $var = @($map.github.variables.PSObject.Properties | Where-Object { [string]$_.Value -eq "{$($d.key).name}" }) | Select-Object -First 1
            if (-not $var) { Fail "$($d.key): no github.variables entry with {$($d.key).name} (the app's name for its workflow)" }
            $v.appVar = $var.Name
            $dotnet = [string]$dep.dotnet
            if (-not $dotnet -and $d.runtime) { $dotnet = ([string]$d.runtime).Split('|')[-1] + '.x' }
            $v.dotnet = $dotnet
            $v.project = [string]$dep.project
            if (-not $v.project) { $v.project = [string]$dep.source }
            $v.publishArgs = ''
            if ($dep.publishArgs) { $v.publishArgs = " $($dep.publishArgs)" }
            $f.test = [bool]$dep.test
            $v.testStep = ''
            if ($dep.test) { $v.testStep = Get-StepYaml $dep.test '' }
            $v.needs = 'route'
            if ($f.test) { $v.needs = 'test, route' }
            $v.beforeBuild = Get-StepsYaml $dep.beforeBuild 'steps.env.outputs.ready'
            $v.afterDeploy = Get-StepsYaml $dep.afterDeploy 'steps.env.outputs.ready'
            # The app that owns the EF Core migrations runs them before it deploys (LAZYBICEP.md, "Database
            # migrations"): the bundle of migrate.project against migrate.database.
            # App Service: the deploy waits for the app's health check (its healthCheckPath).
            if ($d.kind -eq 'appService' -and $d.healthCheckPath -and [string]$d.healthCheckPath -ne '-') {
                $f.health = $true
                $v.healthPath = [string]$d.healthCheckPath
            }
            $f.migrate = [bool]$dep.migrate
            if ($dep.migrate) {
                $m = $dep.migrate
                $db = Get-Def ([string]$m.database)
                if (-not $db -or $db.kind -ne 'sqlDatabase') { Fail "$($d.key): deploy.migrate.database must be the key of a SQL database of the map" }
                if (-not $m.project) { Fail "$($d.key): deploy.migrate.project is the project with the migrations (e.g. Core)" }
                $v.migrateProject = [string]$m.project
                $v.migrateConnection = [string]$m.connection
                if (-not $v.migrateConnection) { $v.migrateConnection = Get-MigrationConnection $db.key }
                $v.migrateVar = Get-MigrationVariable $db.key
                $ef = Get-EfVersion ([string]$m.project) ([string]$dep.dotnet)
                $v.efVersion = ''
                if ($ef) { $v.efVersion = " --version '$ef'" }
            }
            if ($d.kind -eq 'functionApp') {
                $host_ = @(Get-Links $d.key 'host') | Select-Object -First 1
                $f.flex = $host_ -and (Get-Def $host_.to).kind -eq 'flexPlan'
            }
        }
        $out[[string]$dep.workflow] = (Get-Fragment $d.kind $v $f $template) + "`n"
    }
    # The builds (workflows of no Azure resource).
    foreach ($b in @($map.builds | Where-Object { $_ })) {
        if (-not $b.workflow) { Fail 'a build has no workflow (its file name in .github/workflows)' }
        if ($out.Contains([string]$b.workflow)) { Fail "two workflows named $($b.workflow)" }
        $out[[string]$b.workflow] = Get-BuildWorkflow $b $envBranches $envNames
    }
    return $out
}

$text = Get-Bicep
$workflows = Get-Workflows
$utf8 = New-Object Text.UTF8Encoding $false
$now = ''
if (Test-Path $target) { $now = (Get-Content $target -Raw -Encoding UTF8).Replace("`r`n", "`n") }
# What differs: main.bicep, a workflow, or a generated workflow of an app that isn't in the map any more.
$stale = @()
if ($now -ne $text) { $stale += $map.project.template }
foreach ($w in $workflows.Keys) {
    $file = Join-Path $workflowDir $w
    $have = ''
    if (Test-Path $file) { $have = (Get-Content $file -Raw -Encoding UTF8).Replace("`r`n", "`n") }
    # Never over a workflow written by hand (only a generated one is replaced).
    if ($have -and -not $have.StartsWith($generatedMark)) { Fail ".github/workflows/$w is a workflow written by hand: give the app's deploy another workflow name in the map (or move that file away)" }
    if ($have -ne $workflows[$w]) { $stale += ".github/workflows/$w" }
}
$orphans = @(Get-ChildItem $workflowDir -Filter '*.yml' -ErrorAction SilentlyContinue | Where-Object {
        -not $workflows.Contains($_.Name) -and (Get-Content $_.FullName -TotalCount 1) -like "$generatedMark*" })
foreach ($o in $orphans) { $stale += ".github/workflows/$($o.Name) (no app deploys with it any more)" }

if ($Check) {
    if (-not $stale.Count) { if (-not $Quiet) { Write-Host "$($map.project.template) and the workflows are what the map makes." -ForegroundColor Green }; exit 0 }
    if (-not $Quiet) { Write-Host "Not what the map makes: $($stale -join ', '). Run .\infra\generate.ps1" -ForegroundColor Yellow }
    exit 1
}
if (-not $stale.Count) { if (-not $Quiet) { Write-Host "$($map.project.template) and the workflows: no change." -ForegroundColor Green }; exit 0 }
if ($now -ne $text) {
    [IO.File]::WriteAllText($target, $text, $utf8)
    if (-not $Quiet) { Write-Host "$($map.project.template) written from the map. A dry run shows what changes in Azure: .\infra\azure-setup.ps1 -DryRun" -ForegroundColor Green }
}
if ($workflows.Count) { New-Item -ItemType Directory -Force -Path $workflowDir | Out-Null }
foreach ($w in $workflows.Keys) {
    $file = Join-Path $workflowDir $w
    $have = ''
    if (Test-Path $file) { $have = (Get-Content $file -Raw -Encoding UTF8).Replace("`r`n", "`n") }
    if ($have -eq $workflows[$w]) { continue }
    [IO.File]::WriteAllText($file, $workflows[$w], $utf8)
    if (-not $Quiet) { Write-Host ".github/workflows/$w written from the map (commit it: GitHub runs it from the branch)" -ForegroundColor Green }
}
foreach ($o in $orphans) {
    Remove-Item $o.FullName
    if (-not $Quiet) { Write-Host ".github/workflows/$($o.Name) deleted (no app deploys with it any more)" -ForegroundColor Green }
}
exit 0
