# LazyBicep

**A Netmedia product**: made and maintained by [Netmedia](https://netmedia.agency)
(netmedia@netmedia.hr), https://github.com/netmedia/lazybicep.

The Azure infrastructure of a project, described by one map and set up, checked, changed and removed
environment by environment, with a terminal UI. Windows PowerShell 5.1 or PowerShell 7, the Azure CLI,
the GitHub CLI; no modules. This file belongs to the kit (`kit.json`); a kit update replaces it, so
project notes go into the project's own `README.md`.

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
missing in a vault (`az keyvault secret set ...`) and the apps to restart after them. Removing an app takes
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

What each app uses comes from its app settings and connection strings (matched by host names, Key Vault
references, Application Insights' key; the values are never shown or kept) and from its managed
identity's role assignments, which give its roles too.

Then it asks: **connect** to these resources, or create **new** ones by the map's definitions.

- **connect**: the map takes them over. After the map is written, `environments/<env>.json` gets their
  real names (marked imported), so the environment's first dry run asks every question once with them as
  the defaults and finds them; a start then adds what is missing, each change asked first: managed
  identities, roles, the apps' settings, the kit's security (no keys, no FTP or basic auth), the GitHub
  trust (OIDC), the GitHub environment and the deploy workflows.
- **new**: the map gets the same resources, made new next to them by the naming rules, with managed
  identities and without keys; move the data and remove the old ones by hand.

A type the catalog has no kind for (a classic CDN profile, Redis, Cosmos DB, Container Apps, Service Bus
topics...) is reported, and `infra/new-kinds.md` gets a prompt for each: what to build (the blueprint, the
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

A **spec file** answers all of it (examples/spec.example.json in the LazyBicep repository):

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
where a use offers roles). Anything left out takes the blueprint's default.

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
| Check | `-Check` | For an environment that is set up: its saved answers, no questions; reports what is in place and what is missing. Changes nothing |
| Start | `-Start` | Asks every question, then creates and updates what is missing, each change asked first |
| Remove all | `-Remove` (`-RemoveAll`) | Deletes everything the setup created for an environment, shown first and confirmed by typing the resource group's name |
| Add a resource | `-AddResource [-Kind <kind> \| -Import [-ResourceGroup <rg>]]` | Adds a resource of the catalog to the map with its connections, generates `main.bicep`; or imports resources from Azure into the map (asked first; see "Importing from Azure") |
| Remove a resource | `-RemoveResource [-Key <key>]` | Takes a resource out of the map with everything that refers to it, generates `main.bicep`; then offers to **delete it from Azure**: no by default, then per environment its exact name typed (and `delete prod` for production); only what the setup made, never a shared resource; an app's role assignments go first; a Key Vault's purge is asked |
| New project | `-Init [-SpecFile <file>]` | Makes the map of a new project |

More: `-Environment prod|test|stag|dev|accp`, `-RefreshToken`, `-Currency`, `-Help`. A run's steps:
answers (saved in `environments/<env>.json`), Azure resources (what-if first; deployed only on a real
change), the apps' database users (when there is SQL), GitHub -> Azure trust (OIDC), the GitHub
environment (variables, deployment tokens, deployments only from its branch), custom domains (DNS checked,
free certificates), live checks, and the next steps by hand. Every mode shows the estimated monthly cost
(Azure list prices).

A **new environment** can start from another one's answers (e.g. test from prod): the first question offers it. Names move to the new environment (`-prod` becomes `-test`, or `-test` is added); custom domains follow the same logic (`dev.app.example.com` -> `test.app.example.com`, `app.example.com` -> `app-test.example.com`); the deploy branch too (`production` -> `test`, `prod` -> `test`, `release/prod` -> `release/test`; anything else: manual runs), and a start offers to create a missing branch from the source's. Shared resources stay shared; every question is still asked, nothing is saved before the usual save.

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
| `free`, `check` | Checks for a new name (`nameAvailable`, `vaultSoftDelete`) and for an existing resource (`linuxPlanInRegion`, `sameRegion`, `rbacVault`) |
| `param`, `groupParam` | Its `main.bicep` parameters |
| `size`, `choice`, `variants`, `when`, `optional`, `admin` | Answers asked with it, fields that depend on a choice, asked only for some answers, saved only when used |
| `tag` | A short label shown with it in lazybicep and in the questions; without one it comes from the map: a choice per environment shows its options (`shared/separate`, or the environment's answer on Home), a `when` resource `only if separate` |
| `cost` | Its row in the cost estimate (`appServicePlan`, `staticWebApp`, `pennies`, `logs`, `table`) |
| `appSettings` | An app's settings: `main.bicep` sets them, the setup checks them. `{braces}` are values of other resources: `{storage.tableEndpoint}`, `{insights.connectionString}`, `{sqlServer.host}`, `{secret.<name>}`, `{webDomain}`... |
| `secrets`, `handSecrets` | Key Vault secrets the setup keeps (`by: setup`) or that are put in by hand (`by: hand`; `setting`, `app`: who reads it as what) |
| `deploy` | An app's deploy (below, "Deploy workflows"): which folder is built how, triggered by what, published where; `generate.ps1` makes its GitHub Actions workflow |

`values` (top level): values asked per environment for the apps' settings (`answer`, `param`, `label`,
`setting`, `app`): saved with the environment's answers, `main.bicep` parameters, `{answer}` in settings.

Then `connections` (`host`, `role`, `sql`, `logs`, `telemetry`, `settings`, `deploy`, `token`, `origin`),
`domains`, `github` (variables, deployment tokens, deploy roles, workflows), `live`, `cleanup`, `steps`,
`removeOrder`.

## The catalog

| Kind | What it is |
|---|---|
| `appService` | An API (or any web app) on App Service Linux; managed identity, health check, deployed with OIDC. Runtime: any Azure offers now (.NET, Node, Python, Java, PHP; default .NET 10), with a warning when its support ends within a year |
| `staticWebApp` | A front end on Static Web Apps (Free or Standard), deployed with its token |
| `functionApp` | Azure Functions: Flex Consumption (its own plan) or on an App Service plan; state in a storage account through its identity. Runtime: any Azure offers now (default .NET 10 isolated), with a warning when its support ends within a year |
| `appServicePlan` | A Linux plan (new or shared) |
| `sqlServer`, `sqlDatabase` | Azure SQL, Entra sign-in only (an admin you choose); the apps' database users are made by the step Database access (by client id, no directory rights needed; your address is let through the firewall for the step, asked first) |
| `serviceBus` | A namespace with queues, no keys; the apps get Data Sender and/or Receiver |
| `frontDoor` | Azure Front Door Standard or Premium (the CDN) in front of an app of the map (Static Web App, App Service or Function App): one endpoint, HTTPS only, health probes on the app's health check, caching and compression if wanted. A custom domain on it and locking the app to Front Door are by hand for now |
| `storageQueue` | A queue of a storage account; the apps get a queue role on that queue only |
| `storage` | StorageV2 without keys; the apps get the data roles you pick |
| `keyVault` | RBAC vault; the apps get Key Vault Secrets User |
| `appInsights`, `logAnalytics` | Telemetry for the apps that use it |

**Several of one kind** (two APIs, two databases): add it again; each gets its own key, parameters,
sections and sub application name (`<prefix>-api2-apiapp-<env>`); two resources of one Azure type can't
get the same name.

**A new kind**: a fragment (`catalog/<kind>.bicep`, filled per resource: `{{key}}`, `{{name}}`...), a
blueprint (`catalog/<kind>.json`: the map entry with `<placeholders>`, what it requires and creates, what
the apps that use it get) and, only for new behaviour, a handler in `azure-setup.ps1` (a name check, a
step) or `generate.ps1` (the fragment's values). Then `.\infra\generate.ps1`, a dry run, and a pull request
to LazyBicep so every project gets it.

## Naming

`{prefix}-{sub}-{type}-{env}`; Application Insights `{prefix}-{sub}-{type}-{env}-insights`, a shared one
`{prefix}-{sub}-{env}-insights`. All lowercase; the parts that are empty are left out; storage accounts
without hyphens. The sub application name belongs to a deployment target (an API, a web app, a function
app), asked for each. Types and environments are in `naming.json`.

## Deploy workflows

Each app's `deploy` in the map says **which folder, of which branch, is published where**, and
`generate.ps1` makes its workflow `.github/workflows/<workflow>` from `catalog/workflows/<kind>.yml`
(App Service .NET, Static Web App, Function app; generated files start with `# GENERATED`, never edit them,
and a workflow written by hand is never overwritten):

| Field | Meaning |
|---|---|
| `workflow`, `name`, `about` | Its file, its name in GitHub, the comment on top |
| `source` | The app's folder: a change in it triggers the deploy (`<source>/**`) |
| `paths` | More paths that trigger it (`"path"` or `{ "path", "comment" }`) |
| `everyBranch` | Triggered on every branch (its tests run everywhere); deploys still only from an environment's branch. Without it: **the environments' deploy branches** (`environments/*.json`), so a new environment's branch goes into every trigger when its answers are saved |
| `dotnet`, `project`, `publishArgs`, `test` | .NET: version, the project to publish, extra publish arguments, a test step run before |
| `node`, `build`, `app`, `api`, `tokenFallback` | Static Web App: Node version, the build step (in `source`), the built site and its functions folders, an extra token secret |
| `beforeBuild`, `afterDeploy` | The project's own steps (`{ name, id, run, workingDirectory, comment }`), e.g. a version step, a smoke test |

Where it publishes: the push's branch belongs to an environment (`route.ps1` reads `environments/*.json`), and
the workflow deploys to that environment's app: its name is the GitHub environment's variable
(`AZURE_WEBAPP_NAME`, `AZURE_<KEY>_NAME`), set by the setup. Adding an app asks its source folder and
writes its deploy; removing it deletes its workflow; saving an environment's answers regenerates the
triggers. Commit `.github/workflows` with the map.

A workflow finds the environment of a push with `route.ps1`:

```yaml
- id: route
  shell: pwsh
  run: ./infra/route.ps1 -Branch "${{ github.ref_name }}" -Chosen "${{ inputs.environment }}" >> $env:GITHUB_OUTPUT
```

and signs in to Azure with the GitHub environment's `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID` (OIDC, `azure/login`); each app's name is a variable `AZURE_<KEY>_NAME`, a Static
Web App's token the secret `AZURE_STATIC_WEB_APPS_API_TOKEN_<KEY>`.

### Actions

Every generated workflow takes its GitHub Actions from `catalog/workflows/actions.json` by a short name
(`"checkout": "actions/checkout@v7"`): templates write `{{action:checkout}}`, a build's step `"uses": "checkout"`.
Upgrading an action there (e.g. when GitHub deprecates a Node version) upgrades every workflow on the next
`.\infra\generate.ps1`.

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
`actions.json` or a full `owner/action@version`, `run` may have several lines.

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
means in Azure. A project from when the kit was LazyAzure loses `lazyazure.ps1`, `lazyazure.exe` and
`LAZYAZURE.md` (and the root's `lazyazure.exe`): `lazybicep.*` replaces them.

---

LazyBicep is developed by **Netmedia**  |  https://netmedia.agency  |  netmedia@netmedia.hr
