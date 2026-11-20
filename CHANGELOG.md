# Changelog

What changed in LazyBicep, newest first. The kit's version is in `infra/kit.json`; a project takes a new kit
with `.\initintoproject.ps1 <project>\infra -Update`. What is built but not yet run against Azure:
[docs/TODO.md](docs/TODO.md).

## 0.2.1 (on `develop`; not tagged yet)

- **A container app's own address**: `{<key>.host}` of a `containerApp` is made from its name and its
  environment's default domain (`<name>.<domain>`; internal ingress `<name>.internal.<domain>`), not from its
  `ingress.fqdn`, so the app may use it in its own settings without a cycle (`Mcp__PublicBaseUrl =
  https://{gateway.host}`). The output `<key>HostName` is unchanged; the setup reads the same value from Azure.
- **`{<key>.signInClientId}`**: a container app's sign-in client id (`<key>SignInClientId`), only for an app with
  `signIn`. Empty until the step Sign-in app registrations; the app runs the placeholder until then, so its own
  image never sees it empty (the setup's settings check expects it empty too). A container app's setting that
  uses it is set with its own image only (`<key>SignInSettings`, like the Key Vault secret settings), so the
  placeholder revision never gets an empty value.
- **`{envName}` of `development` is `Dev`** (AZ 12.5): the apps' `ASPNETCORE_ENVIRONMENT` /
  `AZURE_FUNCTIONS_ENVIRONMENT` in `dev` was `Development`, which made `IsDevelopment()` true in Azure. Every other
  environment keeps its full name capitalized (`Production`, `Test`...); the GitHub environment keeps the full
  name `development` (AZ 12.2). A `dev` app now loads `appsettings.Dev.json`.
- **`{tenantId}`** (`tenant().tenantId`) and **`{loginEndpoint}`** (`environment().authentication.loginEndpoint`,
  `https://login.microsoftonline.com/`); the setup fills them from the chosen subscription's tenant and
  `az cloud show`.
- **Project tags**: `project.tags` of the map (name -> value, AZ 2 `client`, `owner`...) on every resource after
  the kit's `project`, `environment` and `managed-by`, which they can't replace (refused, also by `-Init`).
  Asked in a new project ("Extra tags for every resource", `name=value, ...`; a spec file's `project.tags`); put
  on a resource group the setup creates; `-Check` reports an existing group without one (the what-if covers the
  template's resources). A name has 1-128 characters without `# : < > \ / ? & % " !` or control characters, a
  value up to 256 without `" % !`, control characters or a final `\` (the same check in `-Init` and
  `generate.ps1`); at most 47 (50 on a resource with the kit's 3). Names `true`, `false`, `null` are quoted in
  Bicep. Maps without `project.tags` make the same tags line as 0.2.0.
- `examples/spec.containerapp.json` uses all of them.
- **Health checks of the deploy workflows end after 5 minutes**: the container app's and the App Service's
  health step looped 30 times (`az` + `curl --max-time 20` + `sleep 10`), up to about 15 minutes. Now a deadline
  at start + 300 s (curl's `--max-time` and the sleep capped by the time left, `az containerapp show` under
  `timeout`) and `timeout-minutes: 6` on the step. Green still means the health path answered.
- **First image waits for the secrets put in by hand**: besides the Key Vault secrets the app's settings
  reference, the step (before the build and again before the deploy) checks every `by: hand` secret the map gives
  the app (a vault's `secrets[]` with `app` = the app, or without `app` in a vault whose `handSecrets` restart it),
  by name only; a missing one stops it before any deployment, and the next steps say how to put it in.
- **Sign-in accepts the client id only (security, CWE-863)**: with `signIn.identifierUri: true` the container
  app's `allowedAudiences` also held `api://<client id>`, so an app-only token issued for that URI (a daemon's
  client credentials, another API sharing the registration) passed on the signed-in routes as if a user had signed
  in. `identifierUri` now changes only the app registration (the setup's step); the sign-in is for users, and an API
  for applications lives on an excluded path and validates its own tokens. A map with `identifierUri` gets a
  shorter `allowedAudiences` in `main.bicep` (the what-if shows the change).
- **Allowed regions**: `project.regions` of the map (a list, e.g. EU only, AZ 2) puts `@allowed([...])` on
  `main.bicep`'s `location` (and limits `staticLocation` to those of them), so a deployment elsewhere fails; the
  setup offers only those regions for a new resource group (a choice) and stops on an existing group in another
  region. Asked by `-Init` ("Regions the resources may be in", `-` = any; a spec file's `project.regions`), then the
  default region is one of them. `regions.default` must be in the list. Maps without it: unchanged.
- **Actions pinned by commit SHA** (supply chain): every action in `catalog/workflows/actions.json` is
  `<owner>/<repo>@<40-character sha> # <release>`; the release stays readable as a YAML comment on the `uses:`
  line (Dependabot updates both). The SHAs are the current releases of the same major tags (checked
  2026-11-20); the `$comment` says how to upgrade. Generated workflows change only in their `uses:` lines.

## 0.2.0 (on `develop`, the default branch; not tagged yet)

Everything since 0.1.0. Why the identity model and the Container Apps kinds are built this way:
[docs/architecture/](docs/architecture/README.md).

### Every app has its own identity

- **App-owned user-assigned identities**: every App Service, Function App and Container App signs in to Azure as
  its own user-assigned managed identity (new kind `appIdentity`, naming type `ident`, named
  `{prefix}-{sub}-{apptype}-ident-{env}` by `naming.json`'s `identityPattern`), made with the app (`creates`),
  removed with it, never shared, one per app per environment. Its roles, Key Vault reads and SQL database user
  exist before the app starts. No system-assigned identity any more.
- Settings: `AZURE_CLIENT_ID` for every app; `keyVaultReferenceIdentity` (App Service, Function App);
  `AzureWebJobsStorage__credential` / `__clientId` and Flex deployment storage as `UserAssignedIdentity`
  (Function App); `<Name>__credential` / `__clientId` next to a function app's identity-based connections; SQL
  connection strings with `User Id=<client id>`. Brace values `{<key>Identity.clientId}`, `.principalId`, `.id`.
- `-Check` reports an `ident` identity no app of the map owns, and roles on an app identity's own scope that let
  someone attach it elsewhere (Managed Identity Operator, Managed Identity Contributor, Contributor, Owner, User
  Access Administrator). Reported only.
- Removal: an app's role assignments first, then the app, then its identity (`-RemoveResource` and `-Remove`).
- **Maps from 0.1.0**: none is in use, so nothing breaks; an app entry without `identity` keeps its
  system-assigned identity until it is removed and added again. An imported app (connect) on a system-assigned
  identity is switched to its own by the start; the next steps list the old identity's role assignments and SQL
  users to remove by hand.

### Container Apps

- **`containerApp`** (naming type `contapp`, a deployment target): a containerised app from its Dockerfile on
  Azure Container Apps, HTTPS only, external or internal ingress, port, vCPU / memory, replicas, revision mode,
  sticky sessions, startup / liveness / readiness probes on its health path (within the platform's limits), Key
  Vault secrets by reference (`keyVaultUrl` + its identity, `secretRef`; never a value in `main.bicep`).
- **`containerAppsEnvironment`** (`contenv`): workload profiles with the Consumption profile, logs to a Log
  Analytics workspace of the map through a diagnostic setting. **`containerRegistry`** (`contreg`): Basic by
  default, admin user and anonymous pull off, the name checked globally; the apps pull with AcrPull on their
  identity. A new project gets the app, its environment and registry from one pick.
- **The image belongs to the app's workflow**: a new app starts with the placeholder
  `mcr.microsoft.com/k8se/quickstart:latest`; every later start passes back the image Azure runs, so `main.bicep`
  never changes it.
- **Sign-in** (`signIn`): the platform's sign-in with Entra ID (ID token, no client secret, token store off;
  redirect or 401; excluded paths, `/x` with each `/x/*`, the health path always; optional identifier URI and app
  roles). The new step **Sign-in app registrations** makes or updates the app registration per environment, each
  change asked (redirect, ID tokens, Assignment required with the group asked per environment), and runs
  `main.bicep` again with its client id in the same start.
- The new step **First image**: runs the app's workflow with `push-only`, waits for it and deploys the pushed
  image with `main.bicep`, once the sign-in and the Key Vault secrets are there.
- **Deploy workflow** `catalog/workflows/containerApp.yml`: image built on the runner, pushed tagged with the
  commit SHA, only the image updated, then the health wait (2xx, up to 5 minutes); OIDC with AcrPush on the
  registry and Container Apps Contributor on the app; variables `AZURE_<KEY>_NAME`, `AZURE_<KEY>_GROUP`,
  `AZURE_<REGISTRY>_NAME`; `deploy.env` as BuildKit secrets. Refuses an app on the placeholder or without its
  sign-in.
- Cost estimate (registry by tier, apps at the Consumption price of their minimum replicas), `-Check` (image,
  sign-in, Key Vault secrets), removal order (app, then identity; environment and registry only when no app uses
  them). Roles AcrPull, AcrPush, Container Apps Contributor; Key Vault, Service Bus, storage and SQL take
  container apps as users.
- Not yet: custom domains and private networking (VNet) for container apps, an environment or registry shared
  from another resource group, `deploy.migrate` in a container app's workflow.

### Import and analysis

- The import reads Container Apps, their environments and registries (image only as information, sign-in
  settings, Key Vault secret names; never values) and user-assigned identities: the identity of exactly one
  imported app becomes that app's, a shared or unused one is reported.
- The analysis suggests a container app for a .NET web project, Node or Python server with a `Dockerfile` (or
  `Containerfile`) in its folder: port from `EXPOSE`, build context from what it copies, one environment and one
  registry for all.

### Other changes

- Hand-secret next steps write `az keyvault secret set ... --file <a file only you can read> --encoding utf-8`:
  the value never goes into the process list or the shell history.
- Service Bus API `2024-01-01` (the `minimumTlsVersion` lint warning on `2021-11-01`).
- `logAnalytics` also serves a Container Apps environment.
- **Entra app registrations are adopted by id, never by display name alone** (the sign-in registrations and the
  GitHub deploy registration): the saved client id first, then the live sign-in's client id; a registration found
  only by its name is taken only when you are its sole owner (else the run stops and says so). New registrations
  and service principals get you as their owner; `-Check` reports owner, redirect, ID-token and
  Assignment-required drift. An environment whose deploy registration has no owner: set `<deployKey>ClientId` in
  `infra/environments/<env>.json` or add yourself as its owner.
- Values from the environment's answers, Azure and Graph are checked before they reach `az` / `gh` (group ids as
  GUIDs, Key Vault secret names, redirect and identifier URIs), and arguments to `az.cmd` with `"`, `%` or line
  breaks are refused.
- `docs/tools/build-docx.ps1` takes Netmedia's document template from the `netmedia-document` plugin's theme.

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
