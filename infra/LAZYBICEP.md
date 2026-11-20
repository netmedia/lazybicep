# LazyBicep

**A Netmedia product**: made and maintained by [Netmedia](https://netmedia.agency)
(netmedia@netmedia.hr), https://github.com/netmedia/lazybicep.

The Azure infrastructure of a project, described by one map and set up, checked, changed and removed
environment by environment, with a terminal UI. Windows PowerShell 5.1 or PowerShell 7, the Azure CLI,
the GitHub CLI; no modules. This file belongs to the kit (`kit.json`); a kit update replaces it, so
project notes go into the project's own `README.md`.

**It carries out the Netmedia Azure Conventions** (the `netmedia` plugin's `conventions-azure`: naming AZ 1, resource
groups and tags AZ 2, infrastructure as code AZ 3, identity AZ 4, hosting AZ 5, SQL AZ 7, deployment AZ 12) and the
Backend Architecture's deploy-time migrations (BA 4.4). The two are kept in sync: a change to one is made in the other.

**Every script explains itself**: `-Help` (or `-h`) shows its guide, modes, options and examples;
in lazybicep, `?` shows the keys of every screen.

lazybicep also comes as `lazybicep.exe`, in `infra\` and in the project's root: it starts
`infra\lazybicep.ps1` with the same arguments, in the same console (the `.ps1` is the program). From the
project's root: `.\lazybicep.exe` in PowerShell (it never runs a program from the current folder by its
name alone), `lazybicep` in cmd, or a double-click in Explorer.

```
.\infra\lazybicep.ps1 -h          .\infra\azure-setup.ps1 -h          .\infra\generate.ps1 -h
```

| Path | What | Whose |
|---|---|---|
| `infra.map.json` | **The map**: every resource of an environment and how it is named, asked, deployed, sized, priced, connected, checked and removed | the project |
| `naming.json` | The naming rules: patterns, type and environment abbreviations, the prefix, length limits | the project |
| `environments/<env>.json` | The answers of each environment (commit them; the workflows read them) | the project |
| `main.bicep` | Every Azure resource of an environment: **generated** from the map, never edited | generated |
| `azure-setup.ps1` | The setup: asks, checks, creates, removes (every change asked first); adds and removes resources of the map; starts a new project | kit |
| `lazybicep.ps1` | The terminal UI of the setup | kit |
| `generate.ps1` | Makes `main.bicep` from the map and the catalog | kit |
| `analyze.ps1` | Looks through the solution and suggests a new project's resources (a spec) | kit |
| `import.ps1` | Reads resource groups in Azure and suggests a new project's map from their resources (a spec with the real names) | kit |
| `new-kinds.md` | Written by an import: a prompt per kind of resource the catalog doesn't have yet | the project |
| `catalog/` | The kinds of resources: `<kind>.bicep` (its part of `main.bicep`), `<kind>.json` (what adding it writes into the map), `roles.json` | kit |
| `modules/` | Bicep modules the catalog uses (a Key Vault's secrets and roles, a database in its server's group) | kit |
| `route.ps1` | Which environment a workflow run deploys to (from the pushed branch) | kit |
| `kit.json` | The kit's version and its files | kit |

## A new project

Drop the empty instance into the project (`initintoproject.ps1 <project>\infra` from the LazyBicep
repository), then:

```
.\infra\lazybicep.ps1                         # New project: n
.\infra\azure-setup.ps1 -Init                 # the same without the UI
.\infra\azure-setup.ps1 -Init -Analyze        # analyze the solution without asking first
.\infra\azure-setup.ps1 -Init -Import -ResourceGroup contoso-shop-resgr-prod   # import from Azure
.\infra\azure-setup.ps1 -Init -SpecFile spec.json
```

It asks first: **analyze** the solution, **import from Azure** (resource groups that exist already), or
add the resources **by hand**. The analysis
(`infra/analyze.ps1`; it reads files, runs nothing) looks through the project's folders, without build
output, `node_modules` and `infra`:

| Found | Suggests |
|---|---|
| A .NET Web project (`Microsoft.NET.Sdk.Web`) | An App Service: its runtime from the target framework, its folder as the source, the health check path from `MapHealthChecks` (none when there is none) |
| A .NET Functions project (isolated worker) | A Function App (Flex Consumption), its runtime from the target framework |
| A `Dockerfile` (or `Containerfile`) in the folder of a .NET Web project, a Node or a Python server | A Container App instead of an App Service: its Dockerfile, its build context (the repository root when the Dockerfile copies files from outside its folder or the project references projects outside it), its port (`EXPOSE`, default 8080); one Container Apps environment and one container registry for all of them. A Dockerfile anywhere else is noted |
| Blazor WebAssembly (not hosted by a web project) | A Static Web App (its workflow's build step to change to `dotnet publish`) |
| `package.json` with React, Angular, Vue, Svelte, Next, Nuxt, Astro, Vite... | A Static Web App with the folder its build writes (`dist`, `build`, Angular's `outputPath`...); a front end inside a .NET web project (`ClientApp`) is that project's |
| `package.json` with Express, Nest, Fastify, Koa...; `@azure/functions` | An App Service (Node); a Function App (Node) |
| Django, Flask, FastAPI; `azure-functions` | An App Service (Python); a Function App (Python) |
| SQL Server: a connection string, EF Core `SqlServer`, `SqlClient`, `UseSqlServer` | A SQL database per connection string's name (and a SQL server): its key comes from the name, so the setting the map gives the apps, `ConnectionStrings__<Key>`, is the one they read |
| Service Bus: a package, `ServiceBusTrigger`, `CreateSender`/`CreateProcessor` | A Service Bus with the queues named in the code (`%Setting%` names from `local.settings.json`); Sender or Receiver for an app that only sends or only receives |
| Storage: a connection string, Blob/Table packages; `QueueTrigger`, `GetQueueClient` | A storage account; a storage queue per name |
| Key Vault: a vault URL, `AddAzureKeyVault`, the Key Vault packages | A Key Vault for the apps that use it |
| Application Insights or Azure Monitor | Application Insights for the apps that send telemetry (every app when none does) |

What an app's project references bring counts for it (EF Core in a data library makes the API that
references it use SQL). Test projects are skipped; workers, consoles, .NET Framework, Service Bus topics,
Redis, Cosmos DB, PostgreSQL, MySQL, MongoDB, Event Hubs and SignalR are noted (no kind in the catalog).

Then every suggestion is offered with what it was found from (`Add Shop (ShopDb) (sqlDatabase)? [Y/n]`),
and adding one asks the usual questions with the analysis's answers as the defaults: change anything there.
One left out (or given another key) is left out of (or renamed in) what the apps after it use. A runtime
Azure doesn't offer any more (the project targets an old .NET) is suggested as the closest newer one, with
a warning. After the suggestions, more resources can be added from the catalog as usual.

**The apps' configuration.** For each App Service and Function App the analysis also lists every setting
it reads: its `appsettings*.json`, `local.settings.json` and `.env` (key names left empty count too),
`Configuration["..."]`, `GetValue`, environment variables and the triggers' `Connection = "..."` names
(through project references too). Each is sorted:

| Found | Becomes (offered after the app's questions, all picked by default) |
|---|---|
| What the map gives already (a SQL connection string by its name, Application Insights) | nothing to do |
| A trigger's `Connection` (`Sb`), a Service Bus or storage connection string with a key | an app setting under the app's own name, identity-based: `Sb__fullyQualifiedNamespace = {bus.host}`, `Jobs__queueServiceUri = {storage.queueEndpoint}` |
| A secret: a password, key, token, client secret...; a connection string of something the catalog has no kind for (Redis) | a Key Vault secret you put in (the vault's `secrets`, `by: hand`) and the setting as a Key Vault reference: `Smtp__Password = @Microsoft.KeyVault(VaultName={vault.name};SecretName=Smtp--Password)`; a Key Vault is suggested when there is none |
| A value that is empty, a placeholder or `localhost` in the files (or only read in the code) | a value asked per environment (the map's `values`): `ExternalApi__BaseUrl = {apiExternalApiBaseUrl}` |
| Clients made without a credential, a connection string with a key, `CloudStorageAccount` | a warning with the code change: `DefaultAzureCredential` (the map has no keys) |

Only the settings' names leave the files, never their values. A run's next steps list the secrets still
missing in a vault (`az keyvault secret set ... --file <a file only you can read> --encoding utf-8`: the value
never goes on the command line, where the process list and the shell history would keep it; delete the file
afterwards) and the apps to restart after them. Removing an app takes
its values and the secrets only it reads out of the map (Azure keeps the secrets until you delete them).
`.\infra\analyze.ps1` shows what it would suggest without starting; `-Out spec.json` writes it as a spec
file to edit and use with `-SpecFile`.

### Importing from Azure

The import (`infra/import.ps1`; Azure CLI, read only) asks the subscription, the resource groups (one or
more) and the resources to put into the map (by default every one the catalog has a kind for), which
environment they are, and with several groups the environment's own (the others' plans, SQL servers, Key
Vaults, Application Insights and workspaces are shared from theirs). From each resource it reads:

| Azure | Suggests |
|---|---|
| `Microsoft.Web/sites` | An App Service (runtime, health check, its plan) or a Function App (Flex Consumption or a plan, its runtime, its storage account) |
| `Microsoft.Web/serverFarms` | An App Service plan (a Flex Consumption plan goes with its app) |
| `Microsoft.Web/staticSites` | A Static Web App (its build's folders when GitHub made it) |
| `Microsoft.Sql/servers` | The SQL server and every database on it but master |
| `Microsoft.ServiceBus/namespaces` | A Service Bus with its queues (topics are reported: the catalog makes queues) |
| `Microsoft.Storage/storageAccounts` | A storage account and its queues (read with your sign-in, never the keys) |
| `Microsoft.KeyVault/vaults`, `Microsoft.Insights/components`, `Microsoft.OperationalInsights/workspaces` | Key Vault, Application Insights (with its workspace), Log Analytics |
| `Microsoft.Cdn/profiles` (Front Door) | A Front Door in front of the app its origin is |
| `Microsoft.App/containerApps` | A Container App: its environment and registry, ingress, port, size, replicas, revision mode, health path (from its probes), sign-in (on, unauthenticated action, excluded paths) and the names of its Key Vault secrets; the image only as information. Noted: more than one container, scale rules (a start drops them), plain HTTP allowed, secrets kept in the app instead of Key Vault, sign-in with another provider than Entra ID |
| `Microsoft.App/managedEnvironments` | A Container Apps environment with its Log Analytics workspace. Noted: a virtual network, a Consumption-only environment (the catalog's has workload profiles) |
| `Microsoft.ContainerRegistry/registries` | A container registry with its tier. Noted: admin user or anonymous pull on (a start turns them off), no public network access |
| `Microsoft.ManagedIdentity/userAssignedIdentities` | No suggestion of its own: the identity of exactly one imported app becomes that app's (connect keeps its real name). One that several apps share, or that no app uses, is reported, not imported |

What each app uses comes from its app settings and connection strings (matched by host names, Key Vault
references, Application Insights' key; the values are never shown or kept) and from its managed
identity's role assignments, which give its roles too. An app that signs in as a system-assigned identity
is noted: a start gives it its own identity (below, "Identity").

Then it asks: **connect** to these resources, or create **new** ones by the map's definitions.

- **connect**: the map takes them over. After the map is written, `environments/<env>.json` gets their
  real names (marked imported), so the environment's first dry run asks every question once with them as
  the defaults and finds them; a start then adds what is missing, each change asked first: the apps' own
  identities (an app on a system-assigned identity is switched to its own; the next steps list the old
  identity's role assignments and SQL users to remove by hand), roles, the apps' settings, the kit's security (no keys, no FTP or basic auth), the GitHub
  trust (OIDC), the GitHub environment and the deploy workflows.
- **new**: the map gets the same resources, made new next to them by the naming rules, with managed
  identities and without keys; move the data and remove the old ones by hand.

A type the catalog has no kind for (a classic CDN profile, Redis, Cosmos DB, Service Bus topics...) is
reported, and `infra/new-kinds.md` gets a prompt for each: what to build (the blueprint, the
fragment, naming, the import's mapping, the docs) and the resource's properties without secrets. Paste it
to Claude Code in the LazyBicep repository; once the kind is in the kit, `initintoproject.ps1 -Update`
brings it and `-AddResource` adds the resource. `.\infra\import.ps1 -ResourceGroup <rg> [-List]` shows
what an import would suggest without starting.

**Into a map that exists** (lazybicep: `a` on Home or the map, then azure; or `-AddResource -Import`): the
same picking and suggestions. What the map has already (the same name in that environment's answers) isn't
offered again, and the imported apps that use it are connected to it. With connect, the imported names are
added to `environments/<env>.json` (its other answers stay).

Either way it asks the project's name, the prefix of its names (`client-project`, e.g. `contoso-shop`), the
region and the name of the deployments. By hand, then its resources one by one from the catalog (after
the suggestions, the same for more): what each needs (a database:
which SQL server, or a new one first), which apps use it (each gets its roles and settings), and for an
app what it uses. Then it writes the map and `naming.json` and generates `main.bicep`. Nothing in Azure
changes yet: a dry run asks the names of an environment and shows what would be created, a start creates
it.

A **spec file** answers all of it (examples/spec.example.json in the LazyBicep repository;
examples/spec.containerapp.json for a container app with sign-in next to a function app):

```json
{
  "project": { "name": "Contoso Shop", "prefix": "contoso-shop", "region": "westeurope", "deploymentName": "shop-{env}" },
  "resources": [
    { "kind": "appServicePlan", "key": "plan" },
    { "kind": "appService", "key": "api", "title": "Shop API", "answers": { "runtime": "DOTNETCORE|10.0" }, "requires": { "appServicePlan": "plan" } },
    { "kind": "sqlDatabase", "key": "shopDb", "requires": { "sqlServer": "new" }, "users": ["api"] },
    { "kind": "serviceBus", "key": "bus", "answers": { "queues": "invoices, mail" }, "users": ["api"], "roles": { "api": ["Azure Service Bus Data Sender"] } }
  ]
}
```

Per resource: `kind`, `key`, `title`, `answers` (its blueprint's questions), `requires` (`{kind: key}` or
`"new"`), `users` (the apps that use it), `uses` (for an app: what it uses), `roles` (`{key: [roles]}`
where a use offers roles), `namingType` (another naming type of `naming.json`, e.g. `dfunc` for a function app
with Durable Functions; `analyze.ps1` suggests it). Anything left out takes the blueprint's default.

`project.tags` (asked in a new project: "Extra tags for every resource", `name=value, ...`, `-` for none) are
the project's own tags, e.g. `{ "client": "netmedia", "owner": "someone@netmedia.hr" }` (AZ 2): `main.bicep`
puts them on every resource after the kit's `project`, `environment` and `managed-by` (the AZ 2 `managedBy`),
which they can't replace (refused). The setup tags a resource group it creates with them; `-Check` reports an
existing group without one, and the what-if shows a resource of the template without them.

`project.regions` (asked in a new project: "Regions the resources may be in", comma separated, `-` for any) limits
where the resources may go, e.g. `["westeurope", "northeurope", "swedencentral"]` for EU only (AZ 2): `main.bicep`
gets `@allowed([...])` on `location` (and only those of them on a Static Web App's `staticLocation`), so a
deployment to another region fails before anything is made; the setup offers only these regions for a new
resource group and stops on an existing group elsewhere. `regions.default` must be one of them. Left out: any
region.

## Running it

Once per PC: the Azure CLI and the GitHub CLI, signed in with an account that is admin of the repository:

```
winget install Microsoft.AzureCLI GitHub.cli
gh auth login
az login                    # add --tenant <tenant> if the subscription is in another tenant
.\infra\lazybicep.ps1       # or .\infra\azure-setup.ps1 (the help, then a menu)
```

| Choice | Switch | What it does |
|---|---|---|
| Dry run | `-DryRun` | Asks every question, shows what exists and what would be created or changed. Changes and saves nothing |
| Check | `-Check` | For an environment that is set up: its saved answers, no questions; reports what is in place and what is missing (also the apps' identity guards, below "Identity", and the container apps' image, sign-in and Key Vault secrets). Changes nothing |
| Start | `-Start` | Asks every question, then creates and updates what is missing, each change asked first |
| Remove all | `-Remove` (`-RemoveAll`) | Deletes everything the setup created for an environment, shown first and confirmed by typing the resource group's name: the apps' role assignments first (also on a vault shared from elsewhere), the apps before their own identities; the container apps' sign-in app registrations are asked one by one (Entra keeps them restorable for 30 days) |
| Add a resource | `-AddResource [-Kind <kind> \| -Import [-ResourceGroup <rg>]]` | Adds a resource of the catalog to the map with its connections, generates `main.bicep`; or imports resources from Azure into the map (asked first; see "Importing from Azure") |
| Remove a resource | `-RemoveResource [-Key <key>]` | Takes a resource out of the map with everything that refers to it, generates `main.bicep`; then offers to **delete it from Azure**: no by default, then per environment its exact name typed (and `delete prod` for production); only what the setup made, never a shared resource; an app's role assignments go first, then the app, its sign-in app registration (asked) and its own identity; a Container Apps environment or registry stays while a container app uses it; a Key Vault's purge is asked |
| New project | `-Init [-SpecFile <file>]` | Makes the map of a new project |

More: `-Environment prod|test|stag|dev|accp`, `-RefreshToken`, `-Currency`, `-Help`. A run's steps:
answers (saved in `environments/<env>.json`), Azure resources (what-if first; deployed only on a real
change), Sign-in app registrations (container apps with `signIn`), the apps' database users (when there is
SQL), GitHub -> Azure trust (OIDC), the GitHub environment (variables, deployment tokens, deployments only
from its branch), First image (container apps still on the placeholder), custom domains (DNS checked, free
certificates), live checks, and the next steps by hand. Every mode shows the estimated monthly cost
(Azure list prices).

**A monthly budget** per environment: after the estimate a run asks the budget (default: the estimate with
room, x1.5 in tens; `-` for none) and who gets its mails (default: you), saved with the answers. The step
Budget sets `monthly-<environment>` on the environment's resource group (`Microsoft.Consumption/budgets`):
mails at 80 % and 100 % of the month's spending and when the month's forecast passes it. An alert only:
nothing is stopped. It is set with the Azure CLI apart from `main.bicep`, so a subscription that doesn't
offer budgets (some sponsorship and partner offers) only shows the step open; a dry run and a check show the
budget and what was spent this month; removing the environment deletes it. Answers saved before there was a
budget: a check says so, a dry run or start asks it. Container apps in the estimate: a registry by its tier;
an environment and an app that scales to zero per use (after the subscription's monthly free grant); an app
with minimum replicas at the Consumption active price of those replicas all month (an upper bound).

A **new environment** can start from another one's answers (e.g. test from prod): the first question offers it. Names move to the new environment (`-prod` becomes `-test`, or `-test` is added); custom domains follow the same logic (`dev.app.example.com` -> `test.app.example.com`, `app.example.com` -> `app-test.example.com`); the deploy branch too (`production` -> `test`, `prod` -> `test`, `release/prod` -> `release/test`; anything else: manual runs), and a start offers to create a missing branch from the source's. Shared resources stay shared; every question is still asked, nothing is saved before the usual save. A
container app's sign-in app registration belongs to its environment: its client id is not copied.

Idempotent: a second run with the same answers changes nothing. `<` goes back to the previous question
until the first change.

## lazybicep

The same setup in one screen. **Home**: the environments, the actions, the selected environment's
resources with where each connects. **Map**: every resource in detail (role, naming, kind, Azure type, how
it is asked, checks, Bicep parameters, cost, app settings, secrets, connections), then the connections,
domains, GitHub, live checks and steps; `a` adds a resource, `x` removes the selected one. **Run**: the
steps with their progress, the resources' states, the log, and the question at the bottom (chips for
choices, toggles for several, a text field with the default). **New project** when there is no map yet.

It does none of the work: it runs `azure-setup.ps1 -Ui` (events as JSON lines out, answers in), so both
always behave the same. `-Keys` and `-Frames` drive it without a console for tests.

## The map

Each resource (in the order asked and saved) has:

| Field | Meaning |
|---|---|
| `key` | Its name in the saved answers (`names.<key>`, `groups.<key>`), in `main.bicep` and in `{key.name}` values |
| `kind` | Its catalog kind |
| `title`, `label`, `role` | How it is shown; the question; what it is for |
| `type` | The naming type (`naming.json`); `target`: the deployment target whose sub application name it carries |
| `armType` | The Azure resource type |
| `ask` | `group`, `own` (in the environment's group), `shared` (may be an existing one elsewhere, used as it is), `workspace` (Log Analytics of the `neededBy` Application Insights), `child` (a name only: a database on its server, a queue in its storage account), `name` (a name only) |
| `free`, `check` | Checks for a new name (`nameAvailable`, `vaultSoftDelete`, `registryName`) and for an existing resource (`linuxPlanInRegion`, `sameRegion`, `rbacVault`) |
| `identity` | An app's own user-assigned identity: the key of its `appIdentity` (`<key>Identity`). An app without it (a map from 0.1.0) keeps a system-assigned identity (below, "Identity") |
| `owner` | An `appIdentity`'s app: the one app that names it as its `identity` |
| `param`, `groupParam` | Its `main.bicep` parameters |
| `size`, `choice`, `variants`, `when`, `optional`, `admin` | Answers asked with it, fields that depend on a choice, asked only for some answers, saved only when used |
| `tag` | A short label shown with it in lazybicep and in the questions; without one it comes from the map: a choice per environment shows its options (`shared/separate`, or the environment's answer on Home), a `when` resource `only if separate` |
| `cost` | Its row in the cost estimate (`appServicePlan`, `staticWebApp`, `pennies`, `logs`, `table`) |
| `appSettings` | An app's settings: `main.bicep` sets them, the setup checks them. `{braces}` are values of other resources: `{storage.tableEndpoint}`, `{insights.connectionString}`, `{sqlServer.host}`, `{apiIdentity.clientId}` (`.principalId`, `.id`), `{api.group}`, `{secret.<name>}`, `{webDomain}`, `{tenantId}` (`tenant().tenantId`), `{loginEndpoint}` (`environment().authentication.loginEndpoint`, `https://login.microsoftonline.com/`)... A container app's `{gateway.host}` comes from its name and its environment's domain (`<name>.<domain>`, internal ingress `<name>.internal.<domain>`), so the app may use its own address in its own settings (`Mcp__PublicBaseUrl = https://{gateway.host}`); `{gateway.signInClientId}` is its sign-in registration's client id, **empty until the step Sign-in app registrations** (the app runs the placeholder until then, so its own image never sees it empty) |
| `environment`, `registry` | A container app's Container Apps environment and container registry (their keys) |
| `port`, `cpu`, `memory` | A container app's target port; vCPU (0.25 to 4 in steps of 0.25) and memory (2 GiB per vCPU: `0.5` with `1Gi`) |
| `minReplicas`, `maxReplicas`, `revisionMode` | Its replicas (min 0 or more, 0 = scales to zero when idle; max 1-1000) and revisions (`single`: a deploy replaces the running one, or `multiple`) |
| `ingress`, `sticky` | `external` (from the internet) or `internal` (from the environment only), always HTTPS only; sticky sessions (`yes`/`no`, single revision mode only) |
| `healthCheckPath` | An App Service's health check; a container app's startup, liveness and readiness probes (`-` for none: no probes) |
| `signIn` | A container app's sign-in by the platform (below, "Container Apps"): `"entra"`, or `{ provider, unauthenticated, excludedPaths, identifierUri, appRoles }` |
| `secrets`, `handSecrets` | Key Vault secrets the setup keeps (`by: setup`) or that are put in by hand (`by: hand`; `setting`, `app`: who reads it as what) |
| `deploy` | An app's deploy (below, "Deploy workflows"): which folder is built how, triggered by what, published where; `generate.ps1` makes its GitHub Actions workflow |

`values` (top level): values asked per environment for the apps' settings (`answer`, `param`, `label`,
`setting`, `app`): saved with the environment's answers, `main.bicep` parameters, `{answer}` in settings.

Then `connections` (`host`, `role`, `sql`, `logs`, `telemetry`, `settings`, `deploy`, `token`, `origin`),
`domains`, `github` (variables, deployment tokens, deploy roles, workflows), `live`, `cleanup`, `steps`,
`removeOrder`. A deploy role is on an app (Website Contributor, Container Apps Contributor) or on what an app
deploys into (a container registry: AcrPush), each at that resource's scope only.

## The catalog

| Kind | What it is |
|---|---|
| `appService` | An API (or any web app) on App Service Linux; its own user-assigned identity, health check, deployed with OIDC. Runtime: any Azure offers now (.NET, Node, Python, Java, PHP; default .NET 10), with a warning when its support ends within a year |
| `staticWebApp` | A front end on Static Web Apps (Free or Standard), deployed with its token |
| `functionApp` | Azure Functions: Flex Consumption (its own plan) or on an App Service plan; its own user-assigned identity; state in a storage account through it. Runtime: any Azure offers now (default .NET 10 isolated), with a warning when its support ends within a year |
| `containerApp` | A containerised app (built from its Dockerfile, any language) on Azure Container Apps: its own user-assigned identity, HTTPS only, external or internal ingress, startup, liveness and readiness probes on its health path, optional Entra ID sign-in in front; deployed by its workflow (image built on the runner, tagged with the commit). The infrastructure never changes its image (below, "Container Apps"). Needs an environment and a registry: existing ones of the map or new ones |
| `containerAppsEnvironment` | Where container apps run, like an App Service plan for many apps: a workload-profiles environment with the Consumption profile (per use, scales to zero); its logs go to a Log Analytics workspace of the map (existing or new) through a diagnostic setting, no shared key |
| `containerRegistry` | An Azure Container Registry for the container apps' images (Basic by default; Standard, Premium): admin user and anonymous pull off; the apps pull with their identities (AcrPull), GitHub Actions pushes with OIDC (AcrPush). The name is global (`<name>.azurecr.io`) and checked |
| `appIdentity` | Not added by hand: the user-assigned identity every app makes for itself (below, "Identity") |
| `appServicePlan` | A Linux plan (new or shared) |
| `sqlServer`, `sqlDatabase` | Azure SQL, Entra sign-in only (an admin you choose); the apps' database users are made by the step Database access (by client id, no directory rights needed; your address is let through the firewall for the step, asked first), with `db_datareader`, `db_datawriter` and `EXECUTE` on `dbo` (the connection's `dbGrants`: the procedures and functions the migrations create). In production a database keeps 35 days of point-in-time restore (Basic: 7, its limit) and long-term backups (weekly 4 weeks, monthly 12 months, yearly 5 years) |
| `serviceBus` | A namespace with queues, no keys; the apps get Data Sender and/or Receiver |
| `frontDoor` | Azure Front Door Standard or Premium (the CDN) in front of an app of the map (Static Web App, App Service or Function App): one endpoint, HTTPS only, health probes on the app's health check, caching and compression if wanted. A custom domain on it and locking the app to Front Door are by hand for now |
| `appConfiguration` | An App Configuration store (`developer` by default: 3,000 requests a day included; `free`, `standard`), Entra sign-in only (`disableLocalAuth`); the apps that read it get App Configuration Data Reader and `AppConfiguration__<Key>__Endpoint`, you get App Configuration Data Owner to write the keys |
| `blobContainer` | A private blob container of a storage account, the same name in every environment (asked once, default its key); the apps that use it get a blob role on that container only (Reader by default) and `BlobContainers__<Key>__Uri` |
| `eventGridSubscription` | A resource's events (App Configuration, storage, Service Bus) to a function of a Function App: a system topic on the resource and the subscription (event types, an advanced filter StringEndsWith), Event Grid Basic. Azure checks the function when the subscription is made, so a run makes it only once the function is deployed: the first start leaves it open ("made once ... has its function"); after the app's first deploy the next start makes it |
| `storageQueue` | A queue of a storage account; the apps get a queue role on that queue only |
| `storage` | StorageV2 without keys; the apps get the data roles you pick |
| `keyVault` | RBAC vault; the apps get Key Vault Secrets User |
| `appInsights`, `logAnalytics` | Telemetry for the apps that use it; Log Analytics also keeps a Container Apps environment's logs |

**Several of one kind** (two APIs, two databases): add it again; each gets its own key, parameters,
sections and sub application name (`<prefix>-api2-apiapp-<env>`); two resources of one Azure type can't
get the same name.

**A new kind**: a fragment (`catalog/<kind>.bicep`, filled per resource: `{{key}}`, `{{name}}`...), a
blueprint (`catalog/<kind>.json`: the map entry with `<placeholders>`, what it requires and creates, what
the apps that use it get) and, only for new behaviour, a handler in `azure-setup.ps1` (a name check, a
step) or `generate.ps1` (the fragment's values). Then `.\infra\generate.ps1`, a dry run, and a pull request
to LazyBicep so every project gets it.

## Identity

Every app (App Service, Function App, Container App) signs in to Azure as **its own user-assigned managed
identity**, and only as it. Why: [Managed identities](https://github.com/netmedia/lazybicep/blob/develop/docs/architecture/identities.md)
in the LazyBicep repository.

- **Made and removed with its app.** Adding an app adds its identity (`creates`: an `appIdentity` with the key
  `<key>Identity`, its `owner` the app, the app's `identity` the identity), named after the app:
  `{prefix}-{sub}-{apptype}-ident-{env}` (`contoso-shop-apiapp-ident-prod`). Removing the app removes it: the
  app's role assignments first, then the app, then the identity.
- **Never shared.** No other resource is offered it, and `generate.ps1` stops on an identity that isn't its
  owner's. One per app per environment: test and production of one app are two identities.
- **Its roles exist before the app starts.** Role assignments, Key Vault readers and SQL database users (by
  the identity's client id) all go to the identity, which `main.bicep` makes before the app; the app waits for
  them (`dependsOn`).

What `main.bicep` gives every app:

| Setting or property | Why |
|---|---|
| `identity: UserAssigned` with its identity only (no system-assigned identity) | The app signs in as its identity |
| `AZURE_CLIENT_ID = {<key>Identity.clientId}` | `DefaultAzureCredential` in the app's code picks that identity |
| App Service and Function App: `keyVaultReferenceIdentity` | Key Vault references are read as the identity |
| Function App: `AzureWebJobsStorage__credential = managedidentity`, `AzureWebJobsStorage__clientId`; Flex Consumption: the deployment storage read as `UserAssignedIdentity` | The Functions host and the platform read the app's storage as the identity |
| Function App: `<Name>__credential` and `<Name>__clientId` next to each identity-based connection to a resource of the map (`<Name>__fullyQualifiedNamespace`, `__queueServiceUri`, `__serviceUri`, `__accountName`...), unless the map sets them | Triggers and bindings sign in as the identity |
| SQL connection strings: `User Id={<key>Identity.clientId}` (no password) | SqlClient's Entra authentication picks the identity |
| Container App: the registry and its Key Vault secrets with the identity | The image pull (AcrPull) and the secrets use it |

**`-Check` guards** (reported only, nothing changed): an `ident` identity in the environment's resource group
that no app of the map owns (it keeps its roles; the command to delete it is shown), and a role on an app
identity's own scope that lets someone attach it to another resource (Managed Identity Operator, Managed
Identity Contributor, Contributor, Owner, User Access Administrator; roles inherited from the resource group or
the subscription are not reported).

**Maps from 0.1.0**: an app entry without `identity` still gets a system-assigned identity, and everything goes
through that one as before. Remove the app and add it again to give it its own. **An imported app** (connect)
that signs in as a system-assigned identity: the start adds its own identity, grants it the app's roles and
switches the app to it; Azure deletes the old identity with the switch but not its role assignments, so the next
steps list them (and the old identity's SQL database users) to remove by hand once the app works.

## Container Apps

A container app runs on Azure Container Apps with the same guarantees as the App Service apps: its own
identity, no keys, Key Vault secrets, an optional Entra ID sign-in in front, and a generated workflow (OIDC)
that builds and deploys its image. Why it is built this way: [Container Apps](https://github.com/netmedia/lazybicep/blob/develop/docs/architecture/container-apps.md)
in the LazyBicep repository.

Adding a `containerApp` asks: its source folder, Dockerfile and build context, port, vCPU and memory, replicas,
revision mode, ingress, health path, sticky sessions and sign-in (`none` or `entra`); then which Container Apps
environment and registry it uses (an existing one of the map, or new: a new environment asks its Log Analytics
workspace the same way). In a new project one pick brings all of them. The app gets `AcrPull` on the
registry, its identity, and the settings every app gets (`ASPNETCORE_ENVIRONMENT = {envName}`,
`AZURE_CLIENT_ID`). GitHub Actions' app registration gets Container Apps Contributor on the app and `AcrPush`
on its registry - re-added with every container app, so a registry the map already had gets it too.

**The image belongs to the app's workflow, never to the infrastructure.** A new app is created with the
public placeholder `mcr.microsoft.com/k8se/quickstart`, pinned by digest (`@sha256:…` in
`catalog/containerApp.bicep`, never a tag: it runs with the app's identity attached) (port 80, no probes, no
Key Vault secrets, no registry pull). Every later start reads the image Azure runs now and passes it back (`<key>Image`), so
`main.bicep` and the app's deploys never undo each other. When the image can't be read, the template is not
deployed (it would put the placeholder back). The app's own port, probes and Key Vault secrets come with its
own image.

**Key Vault secrets**: a setting whose whole value is `@Microsoft.KeyVault(VaultName={vault.name};SecretName=<name>)`
or `{secret.<name>}` becomes a Container Apps secret by reference (`keyVaultUrl` and the app's identity) and
the setting a `secretRef`: never a value in `main.bicep`. The app needs Key Vault Secrets User on that vault.
A revision with a missing secret doesn't start, so the setup checks the secrets by name (never their values)
and the next steps say how to put them in.

**Sign-in** (`signIn`): Container Apps' built-in sign-in with Microsoft Entra ID, own tenant only, with the ID
token (no client secret), token store off, HTTPS required. Its fields (the questions ask only the provider;
the rest is set in the map):

| Field | Meaning |
|---|---|
| `provider` | `entra`, or `none` (off). `"signIn": "entra"` takes the defaults |
| `unauthenticated` | A request without sign-in: `redirect` (to the sign-in page, the default), `401` or `403` |
| `excludedPaths` | Paths that pass without sign-in (endpoints with their own authentication). The health path always does, so with sign-in it is never `/` or `/*` (refused: the root is never anonymous); for each `/x/*` also `/x`, which the wildcard doesn't cover |
| `identifierUri` | `true`: the app registration gets `api://<client id>` (the audience of tokens other applications request). The sign-in itself accepts only the client id: it is for users, so an app-only token for the identifier URI (a daemon's client-credential token) does not pass on the signed-in routes; one requested for the client id itself still does, so an app that trusts the platform's principal refuses app-only principals itself. An API for applications lives on an excluded path and validates its own tokens (audience, issuer, roles) |
| `appRoles` | App roles of the app registration: `{ value, allowed: ["Application" and/or "User"], displayName, description }`. Roles the map doesn't list are kept (removing one is by hand) |

The setup's step **Sign-in app registrations** (after Azure resources, once the app has its address) makes or
updates the app registration of each environment, each change asked: named after the app
(`contoso-shop-contapp-prod`), this tenant only, redirect `https://<fqdn>/.auth/login/aad/callback`, ID tokens
on, no client secret (one it finds is reported), the identifier URI and app roles from the map, its service
principal with Assignment required and the Entra group asked per environment (`-` for none: nobody signs in
until someone is assigned; guests in the group are reported). The client id and the group are saved with the
environment's answers (`<key>SignInClientId`, `<key>SignInGroup`). A new client id runs `main.bicep` again
in the same start (what-if first, asked), so the sign-in exists before the app's own image: with sign-in on,
`main.bicep` gives the app its own image only once the client id is set. `-Check` compares the sign-in in Azure
with the map; an app running its own image without sign-in is reported with how to take it offline
(`az containerapp ingress disable`, never by turning the sign-in off).

The step **First image** (after the GitHub environment) gives an app still on the placeholder its own image,
once its sign-in is in front of it and its Key Vault secrets are in - the ones its settings reference and every
`by: hand` secret the map gives it (a vault's `secrets[]` with `app` = the app, or without `app` in a vault whose
`handSecrets` restart it), checked by name before the build and again before the deploy: it runs the app's workflow with
`push-only` (on the environment's deploy branch, or the default branch for manual runs; the workflow must be
pushed there), waits for the run, finds the image of the run's commit in the registry and deploys it with
`main.bicep` (asked), so the app's settings, secrets and probes come with it. From then on the workflow
deploys every new image by itself. Not yet possible (no GitHub CLI, secrets missing): the next steps say what
to do, then start again.

Removing a container app removes its identity and asks whether to delete its sign-in app registration (Entra
keeps it restorable for 30 days); the environment and the registry stay until no container app of the map
uses them, and the deploy role on the registry goes with the last app that deploys into it.

**Limits for now**: the environment and the registry are in the app's resource group (not shared from
another one); no custom domains and no private networking (VNet) for container apps; `deploy.migrate` is not
supported in a container app's workflow (migrate from an App Service or Function App deploy).

## Naming

`{prefix}-{sub}-{type}-{env}`; Application Insights `{prefix}-{sub}-{type}-{env}-insights`, a shared one
`{prefix}-{sub}-{env}-insights`; an app's own identity `{prefix}-{sub}-{apptype}-ident-{env}` (`identityPattern`;
`{apptype}` is its app's naming type, so two apps without a sub application name never get the same one:
`contoso-shop-apiapp-ident-prod`, `contoso-shop-func-ident-prod`). All lowercase; the parts that are empty are
left out; storage accounts and container registries without hyphens. The sub application name belongs to a
deployment target (an API, a web app, a function app, a container app), asked for each. Types and environments
are in `naming.json`; the Container Apps types are `contapp` (2-32 characters), `contenv` (2-60) and `contreg`
(5-50 letters and digits, globally unique), and `ident` the apps' identities. A `naming.json` from before 0.2.0
without `identityPattern` gets the same pattern by default.

## Deploy workflows

Each app's `deploy` in the map says **which folder, of which branch, is published where**, and
`generate.ps1` makes its workflow `.github/workflows/<workflow>` from `catalog/workflows/<kind>.yml`
(App Service .NET, Static Web App, Function app, Container App; generated files start with `# GENERATED`,
never edit them, and a workflow written by hand is never overwritten):

| Field | Meaning |
|---|---|
| `workflow`, `name`, `about` | Its file, its name in GitHub, the comment on top |
| `source` | The app's folder: a change in it triggers the deploy (`<source>/**`) |
| `paths` | More paths that trigger it (`"path"` or `{ "path", "comment" }`) |
| `everyBranch` | Triggered on every branch (its tests run everywhere); deploys still only from an environment's branch. Without it: **the environments' deploy branches** (`environments/*.json`), so a new environment's branch goes into every trigger when its answers are saved |
| `dotnet`, `project`, `publishArgs`, `test` | .NET: version, the project to publish, extra publish arguments, a test step run before (a job the deploy needs: a failing test stops the deploy; the step may have `env`, e.g. a feed key) |
| `node`, `build`, `app`, `api`, `tokenFallback` | Static Web App: Node version, the build step (in `source`), the built site and its functions folders, an extra token secret |
| `dockerfile`, `context` | Container App: the Dockerfile (from the repository root; default `<source>/Dockerfile`) and the folder `docker build` gets (default `.`, the repository root) |
| `beforeBuild`, `afterDeploy` | The project's own steps (`{ name, id, env, run, workingDirectory, comment }`), e.g. a version step, a smoke test |
| `migrate` | The app that owns the EF Core migrations runs them before it deploys: `{ "project": "Core", "database": "<sqlDatabase key>", "connection": "ModelContext" }` (below, "Database migrations"). Every app that shares the EF Core model migrates too: the bundle applies only what is pending, so the order of the deploys doesn't matter. Not for a container app yet |
| `env` | Environment of the build steps only (publish, migration bundle): `{ "TELERIK_NUGET_KEY": "${{ secrets.TELERIK_NUGET_KEY }}" }` for a package feed's key. Never the job's: the deploy actions don't see it. A container app's build gets them as BuildKit secrets (`--secret id=<NAME>,env=<NAME>`), never as build arguments, which stay in the image's history |

Where it publishes: the push's branch belongs to an environment (`route.ps1` reads `environments/*.json`), and
the workflow deploys to that environment's app: its name is the GitHub environment's variable
(`AZURE_WEBAPP_NAME`, `AZURE_<KEY>_NAME`), set by the setup. Adding an app asks its source folder and
writes its deploy; removing it deletes its workflow; saving an environment's answers regenerates the
triggers. Commit `.github/workflows` with the map.

A workflow finds the environment of a push with `route.ps1` (the branch and the choice through `env`, never pasted
into the script: a branch name may hold quotes and semicolons):

```yaml
- id: route
  shell: pwsh
  env: { BRANCH: "${{ github.ref_name }}", CHOSEN: "${{ inputs.environment }}" }
  run: ./infra/route.ps1 -Branch $env:BRANCH -Chosen $env:CHOSEN >> $env:GITHUB_OUTPUT
```

A manual run offers production last and preselects the first other environment. One deploy of an app per
environment runs at a time (`concurrency`). An App Service with a health check path waits after its deploy until
the app answers it (200, a hard 5-minute deadline: every call gets only the time left, the step has
`timeout-minutes: 6`), or the run fails: a green deploy means the app started.

**A container app's workflow** (`catalog/workflows/containerApp.yml`): an optional test job (`test`, with
`dotnet` for its .NET setup), the route job, then the deploy: the image built on the runner from `dockerfile`
and `context`, pushed to the app's registry as `<key in lowercase words>:<commit SHA>` (`adminApi` ->
`admin-api`), and only the app's image changed (`az containerapp update --image`): its settings, secrets,
probes and sign-in stay as `main.bicep` made them. Then it waits until the new revision is ready and, with
external ingress and a health path, the path answers 2xx (a hard 5-minute deadline, step `timeout-minutes: 6`),
or the run fails.

- The GitHub environment's variables: `AZURE_<KEY>_NAME` and `AZURE_<KEY>_GROUP` (the app and its resource
  group) and `AZURE_<REGISTRY>_NAME` (its registry). Without them the deploy is skipped with a notice.
- Deploy roles of GitHub Actions' app registration: **AcrPush** on the registry and **Container Apps
  Contributor** on the app, nothing wider (the image is built with Docker on the runner, not with
  `az acr build`).
- A manual run's input `push-only` only builds and pushes the image: the setup's step First image uses it. A
  normal run refuses an app that still runs the placeholder (its first image goes in with `main.bicep`, which
  sets its port, probes and secrets) and, with `signIn`, an app without its sign-in in front
  (`az containerapp auth show`): the code never answers before the sign-in exists.

**Production deploys from its branch only**: the setup doesn't accept `-` (manual runs) for it. Every deploy
branch should be protected: the setup offers a repository ruleset (a reviewed pull request for every change, no
force-push or deletion) when the branch has neither a ruleset nor classic protection. On GitHub plans without
required reviewers for environments (private repositories below Enterprise) that branch is production's gate.

**The apps run as their environment**: `ASPNETCORE_ENVIRONMENT` (App Service, Container Apps) and
`AZURE_FUNCTIONS_ENVIRONMENT` (function apps) are the environment's name, capitalized (`{envName}`: `Production`, `Test`, `Staging`...; Linux's disk is
case-sensitive, so `appsettings.Production.json` loads), so environment-specific settings
files load and non-production behaviour (mail recipient overrides, no production alerts) applies. One exception:
`development` (the full name of `dev`) becomes `Dev`, never `Development`, which would make `IsDevelopment()` true
in Azure (developer-only switches, in Netmedia backends also migrations on startup; AZ 12.5) - such an app loads
`appsettings.Dev.json`. The GitHub environment keeps the full name `development` (AZ 12.2).

and signs in to Azure with the GitHub environment's `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID` (OIDC, `azure/login`); each app's name is a variable `AZURE_<KEY>_NAME` (a container
app's also `AZURE_<KEY>_GROUP` and `AZURE_<REGISTRY>_NAME`), a Static Web App's token the secret
`AZURE_STATIC_WEB_APPS_API_TOKEN_<KEY>`.

### Database migrations

The database changes before the code that needs it: the deploy of the app that owns the EF Core migrations
(its `deploy.migrate`) builds them into a bundle (`dotnet ef migrations bundle`, self-contained, linux-x64)
and runs it after the Azure login and before the app is deployed. A failed migration stops that deploy; the
bundle applies only pending migrations, so a re-run is safe. Apps never migrate on startup outside Development.

| Field | Meaning |
|---|---|
| `project` | The project with the migrations and its design-time factory (`--project` and `--startup-project`) |
| `database` | The key of the map's SQL database it migrates |
| `connection` | The connection string's name the factory reads (`ConnectionStrings__<connection>`); default: the database's key in Pascal case, the name the apps read too |

The setup does the rest, each step asked:

- **the GitHub environment's variable `AZURE_<DATABASE>_CONNECTION`**: the database's connection string with
  Entra ID (`Authentication=Active Directory Default`, no password); the workflow signs in as GitHub Actions'
  app registration through the Azure login. An environment **secret** of the same name wins: an older app whose
  database still has a SQL login keeps working with the same workflow.
- **the app registration's database user** (by its client id, like the apps' users) with `db_ddladmin`,
  `db_datareader` and `db_datawriter`: the migrations change the schema and the seed data.

The bundle reads the connection from the environment variable `ConnectionStrings__<connection>`, and runs on the
GitHub runner without the solution's files: the project's design-time factory must not require them (Netmedia's
`DesignTimeDbContextFactoryBase` treats `solutionsettings.json` as optional). GitHub's hosted runners run in
Azure: a SQL server the setup makes lets Azure services through (`AllowAllWindowsAzureIps`); one shared from
another resource group (or imported) keeps its own firewall, so a run checks it and shows the command when the
rule is missing. The `dotnet-ef` that builds the bundle is the project's EF Core version (its
`PackageReference` or `Directory.Packages.props`; else the app's .NET major), or the repository's tool
manifest (`.config/dotnet-tools.json`) when there is one. A push that changes only the migrations' project
deploys too (it is in the workflow's paths). Removing the database from the map takes the deploy's `migrate`
out. Other apps deploy on their own, possibly before the migration:
make breaking schema changes in two steps, expand then contract (Netmedia SQL Coding 10.4), so old and new code
both work with the database in between.

### Actions

Every generated workflow takes its GitHub Actions from `catalog/workflows/actions.json` by a short name
(`"checkout": "actions/checkout@<commit sha> # v7.0.1"`): templates write `{{action:checkout}}`, a build's step
`"uses": "checkout"`. Each is pinned by its full commit SHA, never a tag (a tag can be moved to other code), with
its release as a YAML comment on the `uses:` line. Upgrading an action there (e.g. when GitHub deprecates a Node
version) upgrades every workflow on the next `.\infra\generate.ps1`: the release's commit from
`gh api repos/<owner>/<repo>/git/ref/tags/<tag>` (an annotated tag, `"type": "tag"`, once more through
`git/tags/<sha>`), written as `<owner>/<repo>@<sha> # <tag>`.

## Builds

Workflows of no Azure resource (build, test, pack, publish a package) go into the map's `builds`, and
`generate.ps1` writes them like the deploys (`# GENERATED`, never over a hand-written file; to move a
hand-written one into the map, describe it in `builds`, delete the file, generate and compare):

| Field | Meaning |
|---|---|
| `workflow`, `name`, `about` | Its file, its name in GitHub, the comment on top |
| `branches` | Push branches: names, and `"{environments}"` for the environments' deploy branches; none: manual runs only |
| `paths` | Paths that trigger it (the workflow itself is added) |
| `inputs` | Manual run inputs: `{ "<name>": { description, type, options, default } }` |
| `permissions` | The workflow's token permissions |
| `jobs` | `{ id, name, needs, if, runsOn, permissions, steps }` |

A step is `{ comment, name, if, id, uses, with, workingDirectory, shell, run }`; `uses` is a name of
`actions.json` or a full `owner/action@<commit sha> # <tag>` (pin by SHA, like `actions.json`), `run` may have
several lines.

```json
"builds": [{
  "workflow": "ci.yml", "name": "CI", "branches": ["main", "{environments}"], "paths": ["src/**"],
  "jobs": [{ "id": "test", "name": "Test", "runsOn": "ubuntu-latest", "steps": [
    { "uses": "checkout" },
    { "uses": "setup-dotnet", "with": { "dotnet-version": "10.0.x" } },
    { "name": "Test", "run": "dotnet test" } ] }]
}]
```

## Updating the kit

From the LazyBicep repository: `.\initintoproject.ps1 <project>\infra -Update`. It replaces the kit's
files (`kit.json` lists them) and never touches the project's (`infra.map.json`, `naming.json`,
`environments/`); then `.\infra\generate.ps1` shows whether `main.bicep` changes, and a dry run what that
means in Azure. `naming.json` is the project's, so an update doesn't change it: from 0.1.0 to 0.2.0, copy
from the LazyBicep repository's `infra/naming.json` the types `contapp`, `contenv`, `contreg`, `ident` with their `maxLength`,
`contapp` into `targets` and `contreg` into `noHyphens` before adding a container app. A project from when the
kit was LazyAzure loses `lazyazure.ps1`, `lazyazure.exe` and
`LAZYAZURE.md` (and the root's `lazyazure.exe`): `lazybicep.*` replaces them.

---

LazyBicep is developed by **Netmedia**  |  https://netmedia.agency  |  netmedia@netmedia.hr
