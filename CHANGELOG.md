# Changelog

What changed in LazyBicep, newest first. The kit's version is in `infra/kit.json`; a project takes a new kit
with `.\initintoproject.ps1 <project>\infra -Update`. What is built but not yet run against Azure:
[docs/TODO.md](docs/TODO.md).

## Unreleased (on `develop`, the default branch)

### New project: from the solution or from Azure

- **Analyze the solution** (`infra/analyze.ps1`, `-Init -Analyze`): .NET, Node and Python projects become
  App Services, Function Apps and Static Web Apps; connection strings, packages and code suggest SQL
  databases (keyed by the connection string's name), Service Bus and its queues, storage and queues, Key Vault
  and Application Insights. Each suggestion is offered with what it was found from.
- **The apps' configuration**: every setting each app reads is sorted into identity-based settings under the
  app's own names (a trigger's `Connection`), Key Vault secrets you put in (read through Key Vault
  references), values asked per environment (the map's new `values`) and code changes for managed
  identities. Only names leave the files, never values.
- **Import from Azure** (`infra/import.ps1`, `-Init -Import`, and `a` then azure in an existing map): pick
  resource groups and resources; **connect** (their real names become the environment's answers, a start
  adds what is missing) or **new** (made fresh by the map's definitions). Kinds the catalog lacks get a prompt
  each in `infra/new-kinds.md`.
- A spec's apps can carry `config`; `namingType` (`dfunc` for Durable Functions).
- A runtime Azure no longer offers (net8.0 since 2026-11-10) is suggested as the closest newer one.

### Catalog

- **`frontDoor`**: Azure Front Door Standard/Premium in front of an app of the map (one endpoint, HTTPS only,
  health probes, optional caching). A blueprint's `requires` can name several kinds.
- **`appConfiguration`** (Developer by default, no access keys, you as Data Owner), **`blobContainer`** (private,
  one name in every environment, roles on the container) and **`eventGridSubscription`** (a resource's events
  to a function; made once the function is deployed, so the start after the app's first deploy). Roles:
  Storage Blob Data Reader, App Configuration Data Reader / Owner; naming types `appconf`, `blob`, `evgs`;
  the import and the analysis know App Configuration.
- **SQL**: the apps' database users get `EXECUTE` on `dbo` (`dbGrants`); production databases keep 35 days of
  point-in-time restore and long-term backups (weekly 4 weeks, monthly 12 months, yearly 5 years).
- Two Flex Consumption apps can share one storage account.

### Environments

- **Monthly budget** per environment: asked after the cost estimate; the step Budget sets
  `monthly-<environment>` on the environment's resource group with mails at 80 % and 100 % and at the
  forecast (set apart from `main.bicep`; deleted with the environment).
- **Production gate**: production deploys from a branch only; each deploy branch is offered a ruleset (reviewed
  pull requests, no force-push or deletion; admins may bypass it), by default for production.
- `ASPNETCORE_ENVIRONMENT` / `AZURE_FUNCTIONS_ENVIRONMENT` are the environment's name, capitalized
  (`{envName}`: `Production`, `Test`...), so `appsettings.<Environment>.json` loads.

### Deploy workflows

- **Database migrations** (`deploy.migrate`): an EF Core bundle built before the Azure login and run before the
  app is deployed; the GitHub app registration's database user (`db_ddladmin`); `dotnet-ef` pinned to the
  project's EF Core version; the migrations' project in the triggers.
- `concurrency` per app and environment; the branch and the manual choice through `env` (no script injection);
  `deploy.env` for build-step secrets; a map step may have `env`.
- An App Service's health check after the deploy (2xx; 401/403/302/307 pass with a warning).
- Production last in manual runs, and not preselected.
- Generated workflows take their actions from `catalog/workflows/actions.json` (Node 24 actions); the map's
  `builds` (CI workflows without an Azure resource).

### Kit

- **The developer guide in Word** (`docs/LazyBicep-Developer-Guide.docx`, Netmedia's document template) and
  its tools: `docs/tools/screenshots.ps1` makes the guide's UI screenshots from the Contoso Shop demo (the
  account and subscriptions replaced by demo values), `docs/tools/build-docx.ps1` the Word file (pandoc and
  Word). lazybicep's test mode: `-Html` (every snap as an HTML page in the terminal's colours), `stop:done`.
- The tool's files are `lazybicep.ps1` / `.exe` and `LAZYBICEP.md`; `initintoproject.ps1 -Update` removes a
  project's files under the tool's earlier name.
- `initintoproject.ps1`: a target that isn't an infra folder asks whether to create `<target>\infra`.
- Fixes: confirmations that lost their last value (`"$x?"` is a variable named `x?` in PowerShell); removing a
  database or an app cleans up what refers to it (migrations, values, secrets, a Front Door's origin).

## 0.1.0 (2026-10-22)

LazyBicep 0.1.0 by Netmedia: a project's Azure infrastructure from one map, with a terminal UI.
