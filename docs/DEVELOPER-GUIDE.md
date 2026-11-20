# LazyBicep — Developer Guide

How to install LazyBicep, add it to a project, and use it there. Reference for every script: `-Help` on the script, `?` in the UI, and `infra/LAZYBICEP.md`.

## Overview

LazyBicep (v0.2.0) keeps a project's whole Azure infrastructure in **one map** (`infra/infra.map.json`) and sets it up, checks it, changes it and removes it environment by environment, from a terminal UI or plain PowerShell. Use it on every Netmedia project that runs on Azure.

What you get:

- **One source of truth** — the map lists the apps, databases, queues, vaults and telemetry, and how they connect (managed-identity roles, settings, deploy roles).
- **`main.bicep` is generated** from the map and the catalog. Never edit it by hand.
- **Safe runs** — every run does a what-if first and asks before each change; a second run with the same answers changes nothing.
- **No secrets** — every app signs in as its own managed identity, Entra-only SQL, keyless Service Bus and storage, Key Vault for what remains, GitHub → Azure trust over OIDC.
- **Generated GitHub Actions** — deploy workflows per app and build/CI workflows, all from the map.
- **Cost estimate** — every mode shows the estimated monthly cost from Azure list prices (EUR by default).

The pieces:

| Piece | Where | What it does |
| --- | --- | --- |
| `initintoproject.exe` / `.ps1` | LazyBicep repo | Copies the kit into a project, or updates it |
| `lazybicep.exe` / `lazybicep.ps1` | Project root and `infra\` | Terminal UI over everything below |
| `azure-setup.ps1` | `infra\` | The engine: dry run, check, start, remove, add/remove resource, new project |
| `generate.ps1` | `infra\` | Builds `main.bicep` and `.github/workflows` from the map |
| `analyze.ps1` | `infra\` | Reads the solution and suggests resources |
| `import.ps1` | `infra\` | Reads existing Azure resource groups and suggests a map (read-only) |
| `route.ps1` | `infra\` | Tells a workflow which environment a branch deploys to |

Every script explains itself: run it with `-Help` (or `-h`). In the UI, `?` shows the keys of the current screen. Full reference: `infra/LAZYBICEP.md` in any project.

![LazyBicep lifecycle: setup, map, environments, change loops](images/diagram-lifecycle.png)

Everything before Start only writes files in `infra\`. Later changes go back through dry run and Start; Check shows drift without changing anything.

## Install from scratch (once per PC)

You need Windows PowerShell 5.1 or PowerShell 7, the Azure CLI, the GitHub CLI and a clone of the LazyBicep repo. No PowerShell modules.

1. Install the CLIs:

   ```powershell
   winget install Microsoft.AzureCLI GitHub.cli
   ```
2. Sign in to GitHub with an account that is **admin of the project repository** (the setup creates GitHub environments, variables and secrets):

   ```powershell
   gh auth login
   ```
3. Sign in to Azure (add `--tenant <tenant>` if the subscription is in another tenant). The Azure CLI's default subscription is the one LazyBicep uses:

   ```powershell
   az login
   az account set --subscription <name-or-id>
   ```
4. Clone the kit somewhere stable, e.g. next to your projects:

   ```powershell
   git clone https://github.com/netmedia/lazybicep D:\Development\Netmedia\LazyBicep
   ```
5. Use Windows Terminal (or the Windows 10+ console) so the UI's colours and box characters render.

Notes:

- The `.exe` files are thin launchers for the `.ps1` of the same name, so there is no execution-policy prompt and double-click works. They are not code-signed; SmartScreen may ask once on a new PC.
- In PowerShell, start them as `.\lazybicep.exe` (PowerShell never runs a program from the current folder by name alone). In cmd, `lazybicep` is enough.
- Rebuild the launchers with `.\build-exe.ps1` only when `launcher\launcher.cs` or the version changes.

## Add LazyBicep to a project

Run `initintoproject` from the LazyBicep repo, pointing at the project's `infra` folder. It copies the kit; nothing in Azure changes.

```powershell
cd D:\Development\Netmedia\LazyBicep
.\initintoproject.exe D:\Development\Netmedia\MyProject\infra -DryRun   # preview what is copied
.\initintoproject.exe D:\Development\Netmedia\MyProject\infra
```

- The folder is created if missing. If the target is not named `infra`, `infrastructure`, `iac`, `azure`, `bicep` or `deploy`, it asks: create `<Target>\infra` (Yes, default) or put the kit directly into `<Target>` (No).
- `lazybicep.exe` is also placed in the project root, so the UI starts from either place.

What ends up in the project:

| Path | Owner | Commit? |
| --- | --- | --- |
| `infra/infra.map.json` | Project (created by New project) | Yes |
| `infra/naming.json` | Project (naming patterns, prefix, abbreviations) | Yes |
| `infra/environments/<env>.json` | Project (answers per environment) | Yes — workflows read them |
| `infra/main.bicep` | Generated from the map | Yes, never edit |
| `.github/workflows/*.yml` with `# GENERATED` | Generated from the map | Yes, never edit |
| `infra/new-kinds.md` | Written by an import | Optional |
| `infra/README.md` | Project notes | Yes |
| `azure-setup.ps1`, `lazybicep.*`, `generate.ps1`, `analyze.ps1`, `import.ps1`, `route.ps1`, `catalog/`, `modules/`, `LAZYBICEP.md`, `kit.json` | Kit (replaced on update) | Yes, don't edit in the project |

Put project-specific notes in `infra/README.md`, not `LAZYBICEP.md` — a kit update replaces the latter.

### Update the kit in a project

```powershell
.\initintoproject.ps1 D:\Development\Netmedia\MyProject\infra -Update
cd D:\Development\Netmedia\MyProject
.\infra\generate.ps1                                   # does main.bicep change?
.\infra\azure-setup.ps1 -DryRun -Environment test     # what that means in Azure
```

The update replaces only the files `kit.json` lists; the map, `naming.json`, `environments/`, `README.md` and any project-only catalog kinds stay. Old LazyAzure projects lose `lazyazure.*` and `LAZYAZURE.md`, replaced by `lazybicep.*`.

## The terminal UI

Start it from the project root with `.\lazybicep.exe` (or `.\infra\lazybicep.ps1 -Environment test` to preselect an environment). The UI does no work itself: it runs `azure-setup.ps1 -Ui`, so the UI and the scripts always behave the same.

| Screen | What you see | Keys |
| --- | --- | --- |
| **New** (no map yet) | Prompt to start a project | `n` new project, `?` help, `q` quit |
| **Home** | Environments, actions, the selected environment's resources and what each connects to | ↑↓ environment, `Tab` environments ↔ actions, `Enter` run action, `d` dry run, `c` check, `s` start, `r` remove all, `a` add resource, `x` remove resource, `m` map, `t` refresh token on/off, `?` help, `q` quit |
| **Map** | Every resource in detail: naming, kind, Azure type, Bicep params, cost, app settings, secrets, connections; then domains, GitHub, live checks, steps | ↑↓ resource, `PgUp`/`PgDn` scroll, `a` add, `x` remove selected, `Esc` back |
| **Run** | Step progress, resource states, log, and the current question at the bottom | `Enter` answer (empty = default shown), ←→ choose, `Space` toggle (multi-select), `y`/`n`, `<` previous question, `PgUp`/`PgDn`/`Home`/`End` scroll log, `Esc` stop (asked first); when done `Enter`/`Esc` back |

The `t` toggle is the same as `-RefreshToken`: it re-sets the Static Web App deployment token in GitHub, e.g. after you reset it in the portal.

### Screens

The screenshots come from a demo project (the example spec, "Contoso Shop") and a dry run of its `test` environment against a test subscription, so names, prices and open items are only examples. `docs/tools/screenshots.ps1` makes them again (the UI driven with keys; read-only in Azure).

**New project** — what you see in an `infra` folder that has no map yet. Press `n`.

![LazyBicep New project screen](images/tui-new-project.png)

**New project: analyzing the solution** — after the suggested app's usual questions, its configuration: the settings it gets under its own names, the secrets for Key Vault, the values asked per environment. `Space` toggles one, `Enter` takes the picked ones.

![LazyBicep New project offering an app's secrets for Key Vault](images/tui-new-analyze.png)

**Home** — environments and actions on the left; the selected environment's resources, their names and what each connects to on the right.

![LazyBicep Home screen](images/tui-home.png)

**Map** (`m`) — one resource in detail: naming, kind, Azure type, app settings, its generated deploy workflow and its connections.

![LazyBicep Map screen with Shop API selected](images/tui-map.png)

**Run: a question** — steps on the left, the log on the right, the question at the bottom. Here it's a choice, so you pick with ←→; text questions show the default, and `Enter` keeps it.

![LazyBicep dry run asking the App Service plan size](images/tui-run-question.png)

**Run: estimated monthly cost and the budget** — every dry run, check and start shows the cost before touching Azure; right after it comes the monthly budget question (its default from the estimate).

![LazyBicep dry run showing the estimated monthly cost and asking the monthly budget](images/tui-run-cost.png)

**Run: finished dry run** — `!` marks the steps that still have open items; the log lists them along with the next steps.

![LazyBicep finished dry run with open items](images/tui-run-done.png)

## Identities and roles

Every app (App Service, Function App, Container App) signs in to Azure as **its own user-assigned managed identity**. There is no password or key anywhere: Entra ID issues its tokens.

| Rule | What it means for you |
| --- | --- |
| One per app per environment | Adding an app adds its identity (`<key>Identity` in the map, `contoso-shop-apiapp-ident-prod` in Azure); test and production of one app are two identities |
| Made and removed with the app | Removing the app removes its role assignments, then the app, then the identity |
| Never shared | No other resource is offered it; `generate.ps1` stops on an identity that isn't its owner's |
| Roles before the first start | Roles, Key Vault access and SQL database users go to the identity, which exists before the app, so the app starts with them in place |

The app's code finds the identity through `AZURE_CLIENT_ID` (`DefaultAzureCredential`); Key Vault references, the Functions host's storage and triggers, and SQL connection strings (`User Id=<client id>`) name it too; the map writes all of these. `-Check` reports an identity in the resource group that no app owns, and any role on an app's identity that would let someone attach it elsewhere.

Maps made with 0.1.0 keep a system-assigned identity for their apps until an app is removed and added again; an imported app (connect) is switched to its own identity by the Start. Why the kit works this way: `docs/architecture/identities.md` in the LazyBicep repo.

## Workflows

Each scenario below gives the UI path and the equivalent script command. Nothing touches Azure until a **Start**; building the map, dry runs and checks are always safe.

### 1. Start the map of a new project

After `initintoproject`, open the UI (`.\lazybicep.exe`) and press `n`, or run `.\infra\azure-setup.ps1 -Init`. It first asks how to find the resources. All four routes then ask the project name, the name prefix (`client-project`, e.g. `contoso-shop`), the region and the deployment name, and finish by writing `infra.map.json` and `naming.json` and generating `main.bicep`.

**1a. Analyze the solution** — best for a codebase that is not yet in Azure.

```powershell
.\infra\azure-setup.ps1 -Init -Analyze       # skip the 'how' question
.\infra\analyze.ps1                         # just show what it would suggest
.\infra\analyze.ps1 -Out spec.json          # write it as an editable spec
```

It reads files only (runs nothing) and suggests: .NET Web → App Service (runtime, health check path from `MapHealthChecks`), or a Container App when a `Dockerfile` is in its folder (also for a Node or Python server; port from `EXPOSE`, one Container Apps environment and registry for all of them); .NET isolated Functions → Function App (Flex Consumption); Blazor WASM or React/Angular/Vue/Vite etc. → Static Web App; Node/Python servers → App Service; SQL connection strings / EF Core → SQL database per connection-string name; Service Bus queues found in code; storage and storage queues; Key Vault; Application Insights. Project references count. Each suggestion shows what it was found from (`Add Shop (ShopDb) (sqlDatabase)? [Y/n]`), then the usual questions with the findings as defaults. Workers, Redis, Cosmos DB, topics, PostgreSQL etc. are reported but not added.

It also sorts every setting each App Service and Function App reads (settings files, `Configuration["..."]`, environment variables, triggers' `Connection` names) and offers them after the app's questions:

| Found | Becomes |
| --- | --- |
| A trigger's `Connection = "Sb"`, a connection string with a key | An identity-based setting under the app's own name: `Sb__fullyQualifiedNamespace = {bus.host}` |
| A password, key, token, client secret | A Key Vault secret you put in; the setting is a Key Vault reference |
| An empty, placeholder or `localhost` value | A value asked per environment (the map's `values`, a `main.bicep` parameter) |
| Clients without `DefaultAzureCredential` | A warning with the code change |

Only setting names are read out of the files, never their values.

**1b. Import from Azure** — for a project whose resources already exist.

```powershell
.\infra\azure-setup.ps1 -Init -Import -ResourceGroup contoso-shop-resgr-prod
.\infra\import.ps1 -ResourceGroup contoso-shop-resgr-prod -List   # preview only
```

Read-only. Pick the subscription, one or more resource groups, the resources and which environment they are. It reads runtimes, health checks, plans, SWA build folders, SQL databases, Service Bus and storage queues, Front Door origins, container apps (environment, registry, ingress, size, probes, sign-in, Key Vault secret names), and each app's settings (matched by host name; values never shown or stored), identity and role assignments. A user-assigned identity of exactly one app becomes that app's; a shared one is reported. Then choose:

- **connect** — the map takes over the existing resources with their real names. The first dry run asks every question once with those names as defaults; a Start then adds only what is missing (the apps' own identities, roles, settings, security hardening, OIDC trust, GitHub environment, deploy workflows). An app on a system-assigned identity is switched to its own; the next steps list the old identity's role assignments and SQL users to remove by hand.
- **new** — the same resources are created fresh by the naming rules, keyless with managed identities. Move data and delete the old ones by hand.

Kinds the catalog lacks are listed in `infra/new-kinds.md` (see scenario 14).

**1c. By hand** — pick resources one by one from the catalog. For each it asks what it needs (a database: which SQL server, or a new one), which apps use it, and for an app what it uses.

**1d. From a spec file** — repeatable and reviewable; good for templates.

```powershell
.\infra\azure-setup.ps1 -Init -SpecFile spec.json
```

Start from `examples/spec.example.json` in the LazyBicep repo or from `analyze.ps1 -Out`. Per resource: `kind`, `key`, `title`, `answers`, `requires` (`{kind: key}` or `"new"`), `users`, `uses`, `roles`. Anything left out takes the default.

```json
{
  "project": { "name": "Contoso Shop", "prefix": "contoso-shop", "region": "westeurope", "deploymentName": "shop-{env}" },
  "resources": [
    { "kind": "appServicePlan", "key": "plan" },
    { "kind": "appService", "key": "api", "title": "Shop API", "answers": { "runtime": "DOTNETCORE|10.0" }, "requires": { "appServicePlan": "plan" } },
    { "kind": "sqlDatabase", "key": "shopDb", "requires": { "sqlServer": "new" }, "users": ["api"] }
  ]
}
```

Commit `infra\` once the map exists.

### 2. Create an environment in Azure

Environments: `prod`, `test`, `stag`, `dev`, `accp` (from `naming.json`).

1. **Dry run** — asks every question (names, sizes, SQL admin, deploy branch, domains…), shows what exists and what would be created, plus the monthly cost. Saves nothing.

   ```powershell
   .\infra\azure-setup.ps1 -DryRun -Environment test     # UI: select test, d
   ```
2. **Start** — same questions, then creates what is missing, asking before each change.

   ```powershell
   .\infra\azure-setup.ps1 -Start -Environment test      # UI: s
   ```
3. **Commit** `infra\` (map, `naming.json`, `main.bicep`, `environments\test.json`) and `.github\workflows`. The workflows read these files.

A Start runs these steps in order: save answers to `environments/<env>.json` → Azure resources (what-if, deploy only on a real change) → Sign-in app registrations (only for container apps with sign-in; scenario 10) → apps' SQL database users (by the client id of each app's identity, with `db_datareader`, `db_datawriter` and `EXECUTE` on `dbo`; your IP is let through the firewall for the step, asked first) → monthly budget → GitHub → Azure OIDC trust → GitHub environment (variables, deployment tokens, deploy only from its branch; the branch offered a ruleset) → First image (only for container apps still on the placeholder; scenario 10) → custom domains (DNS checked, free certificates) → live checks → a list of manual next steps.

**Monthly budget.** After the cost estimate the run asks a monthly budget for the environment (default: the estimate ×1.5, in tens; `-` for none) and who gets its mails. The Budget step sets `monthly-<environment>` on the environment's resource group: mails at 80 % and 100 % of the month's spending and when the forecast passes it. It only alerts, nothing is stopped. A subscription that doesn't offer budgets shows the step as open; the rest of the run goes on.

**Production.** Production deploys from a branch only (no manual-runs-only), and each deploy branch is offered a ruleset: changes through a reviewed pull request, no force-push or deletion (the repository's admins may bypass it). Production databases keep 35 days of point-in-time restore and long-term backups (weekly 4 weeks, monthly 12 months, yearly 5 years). The apps run as their environment: `ASPNETCORE_ENVIRONMENT` / `AZURE_FUNCTIONS_ENVIRONMENT` are `Production`, `Test`, `Staging`…, so `appsettings.Production.json` loads (an environment named `development` would turn on developer-only behaviour in Azure).

![The eight steps of a Start](images/diagram-start-steps.png)

The diagram shows the steps every project has; the two container-app steps run only when the map has container apps.

In a Run, `<` goes back to the previous question until the first change is made. Re-running with the same answers changes nothing.

### 3. Add another environment based on an existing one

Start a dry run or Start for the new environment (e.g. `test`); the first question offers to copy another environment's answers (e.g. `prod`). It translates them:

- Names: `-prod` → `-test` (or `-test` is appended).
- Domains: `dev.app.example.com` → `test.app.example.com`; `app.example.com` → `app-test.example.com`.
- Deploy branch: `production`/`prod` → `test`, `release/prod` → `release/test`; anything else becomes manual runs. A Start offers to create a missing branch from the source's.
- Shared resources stay shared. Every question is still asked; nothing is saved before the normal save.

When the answers are saved, every deploy workflow's triggers are regenerated to include the new branch. Commit them.

### 4. Check an environment for drift

```powershell
.\infra\azure-setup.ps1 -Check -Environment prod      # UI: c
```

Uses the saved answers, asks nothing, changes nothing. Reports what is in place and what is missing compared with the map. Run it after manual portal changes, before a release, or when something "stopped working". To fix what it finds, run a Start.

### 5. Remove an environment

```powershell
.\infra\azure-setup.ps1 -Remove -Environment test     # UI: r
```

Shows everything the setup created for that environment and deletes it only after you type the resource group's name. Shared resources are not removed.

### 6. Add a resource to the map

```powershell
.\infra\azure-setup.ps1 -AddResource                    # pick from the catalog
.\infra\azure-setup.ps1 -AddResource -Kind sqlDatabase   # UI: a on Home or Map
```

It asks what the resource needs (e.g. which SQL server, or a new one) and which apps use it. Each app gets its roles and settings on its own identity (see "Identities and roles" below): a database user plus a password-less connection string `ConnectionStrings__<Key>`, Service Bus Data Sender/Receiver, Key Vault Secrets User, storage data roles, and so on. Adding an app also adds its identity, asks its source folder and writes its deploy workflow. Then it updates the map and regenerates `main.bicep`.

To put it into Azure: dry run, then Start, per environment (scenario 2). Commit the map, `main.bicep` and workflows.

Available kinds:

| Kind | Use it for |
| --- | --- |
| `appService` | API or web app on App Service Linux (.NET, Node, Python, Java, PHP; default .NET 10) |
| `staticWebApp` | Front end on Static Web Apps (Free or Standard) |
| `functionApp` | Azure Functions, Flex Consumption or on a plan (default .NET 10 isolated) |
| `containerApp` | A containerised app from its Dockerfile on Azure Container Apps, optional Entra ID sign-in in front (scenario 10) |
| `containerAppsEnvironment` | Where container apps run (Consumption profile), logs to Log Analytics |
| `containerRegistry` | The container apps' images (Basic by default), no admin user or anonymous pull |
| `appServicePlan` | Linux plan, new or shared |
| `sqlServer`, `sqlDatabase` | Azure SQL, Entra sign-in only |
| `serviceBus` | Namespace with queues, keyless |
| `storage`, `storageQueue` | StorageV2 without keys; a single queue with a per-queue role |
| `keyVault` | RBAC vault |
| `appInsights`, `logAnalytics` | Telemetry |
| `frontDoor` | Front Door Standard/Premium in front of an app (custom domain and locking the app to Front Door are manual for now) |
| `appConfiguration` | App Configuration store (Developer by default), Entra sign-in only; you get Data Owner to write the keys |
| `blobContainer` | A private blob container (same name in every environment), roles scoped to the container |
| `eventGridSubscription` | A resource's events to a function: system topic + subscription; made by the start after the function's first deploy |

**Several of one kind** (two APIs, two databases) is fine: add it again with a different key; it gets its own sub-application name, e.g. `<prefix>-api2-apiapp-<env>`.

### 7. Import existing Azure resources into an existing map

```powershell
.\infra\azure-setup.ps1 -AddResource -Import -ResourceGroup <rg>   # UI: a, then azure
```

Same picking as scenario 1b. Resources already in the map for that environment are not offered again, and imported apps get connected to them. With **connect**, the real names are added to `environments/<env>.json`; other answers stay.

### 8. Remove a resource

```powershell
.\infra\azure-setup.ps1 -RemoveResource -Key shopDb     # UI: Map, select it, x
```

Takes it out of the map along with everything that refers to it (settings, roles, its workflow and its identity if it's an app) and regenerates `main.bicep`. It then offers to delete it from Azure: **no** by default; otherwise per environment you type its exact name (and `delete prod` for production). Only resources the setup made are deleted, never shared ones; an app's role assignments go first, then the app, then its identity (a container app's sign-in app registration is asked); a Container Apps environment or registry stays while a container app uses it; a Key Vault purge is asked separately.

### 9. Deploy code with the generated workflows

Each app's `deploy` block in the map says which folder, from which branch, is published where. `generate.ps1` turns it into `.github/workflows/<workflow>` (App Service .NET, Static Web App, Function App, Container App templates; a container app's workflow is in scenario 10).

- **Push to an environment's deploy branch** → the workflow runs, `route.ps1` maps the branch to the environment, it signs in with OIDC (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` from the GitHub environment) and deploys to `AZURE_<KEY>_NAME`.
- **Manual run** — pick the environment in the workflow's input.
- Triggers: changes under the app's `source` folder plus any extra `paths`. With `everyBranch`, tests run on every branch but deploys still only from environment branches.
- Hooks: `test` (run before publish), `beforeBuild` and `afterDeploy` steps (e.g. version stamping, smoke test).
- Generated files start with `# GENERATED`. Don't edit them; change the map and run `.\infra\generate.ps1`. A hand-written workflow with the same name is never overwritten.
- **Database migrations**: the app that owns the EF Core migrations has `deploy.migrate` (`{ "project": "Core", "database": "<sqlDatabase key>" }`). Its workflow builds a migrations bundle (with `dotnet-ef` pinned to the project's EF Core version) before the Azure login and runs it before the app is deployed; a failed migration stops the deploy. The setup gives GitHub's app registration a database user with `db_ddladmin` and sets `AZURE_<DATABASE>_CONNECTION`. A push that changes only the migrations' project deploys too. Make breaking schema changes in two steps (expand, then contract).
- After an App Service deploy the workflow waits for its health check (2xx; 401/403/302/307 pass with a warning, for apps behind Easy Auth or locked to Front Door).
- One deploy per app and environment at a time (`concurrency`); in a manual run production comes last and isn't preselected.

![How a push becomes a deploy](images/diagram-deploy.png)

### 10. A container app

A containerised app (any language, built from its Dockerfile) on Azure Container Apps. It runs in a **Container Apps environment** (like an App Service plan for many apps) and pulls its image from a **container registry**; both belong to the project, the app owns only itself and its identity. Example spec: `examples/spec.containerapp.json` in the LazyBicep repo.

**Add it** (UI: `a` → Container App):

```powershell
.\infra\azure-setup.ps1 -AddResource -Kind containerApp
```

It asks the source folder, Dockerfile and build context, port, vCPU and memory (2 GiB per vCPU), replicas (0 = scales to zero), revision mode, ingress (external or internal), health path (its probes), sticky sessions and sign-in (`none` or `entra`); then which environment and registry it uses: pick existing ones or answer **new** (a new environment also asks its Log Analytics workspace). Which apps' resources it uses (Key Vault, Service Bus, storage, SQL) is asked as for any app. Sign-in details (excluded paths, `401` instead of the redirect, identifier URI, app roles) go into the app's `signIn` in the map by hand; see `infra/LAZYBICEP.md`, "Container Apps".

**Dry run, then Start** (scenario 2). For a container app a Start does more than for an App Service:

| Step | What happens | Why |
| --- | --- | --- |
| Azure resources | The app is created with the public placeholder image (`mcr.microsoft.com/k8se/quickstart:latest`, port 80) | The infrastructure never deploys code; a later Start passes back the image Azure runs, so it never undoes a deploy |
| Sign-in app registrations | With `signIn`: the app registration named after the app (redirect, ID tokens, no client secret, Assignment required); you are asked the Entra group whose members may sign in in this environment. Then `main.bicep` runs again so the sign-in is in front of the app | The app's own code never answers before its sign-in exists |
| GitHub environment | Variables `AZURE_<KEY>_NAME`, `AZURE_<KEY>_GROUP`, `AZURE_<REGISTRY>_NAME`; deploy roles AcrPush on the registry and Container Apps Contributor on the app | The workflow can push an image and change the app's image, nothing more |
| First image | Runs the app's workflow with `push-only`, waits for it, then deploys the pushed image with `main.bicep` (its port, probes, settings and Key Vault secrets come with it) | Asked first; waits for the sign-in and for the app's Key Vault secrets |

The app's workflow must already be on the branch it runs from (commit and push `.github/workflows` after adding the app). Missing Key Vault secrets: the next steps show `az keyvault secret set ... --file <a file only you can read> --encoding utf-8` (never `--value`, which ends up in the shell history), then start again.

**Deploy by push.** From then on a push to the environment's branch (changes under the app's `source`) runs its workflow: the image is built on the GitHub runner, pushed to the registry tagged with the commit SHA, the app's image is updated (nothing else), and the run waits until the new revision is ready and its health path answers (up to 5 minutes). The workflow refuses an app that still runs the placeholder or, with sign-in, has no sign-in in front of it.

**Check** shows each container app's image (placeholder or its own), its sign-in compared with the map, and its Key Vault secrets (by name). Never turn the sign-in off to debug: take the app offline with `az containerapp ingress disable` instead.

Not yet: custom domains and private networking for container apps, an environment or registry from another resource group, `deploy.migrate` in a container app's workflow.

### 11. Add a CI / build workflow

Workflows that deploy no Azure resource (build, test, pack, publish a package) go into the map's `builds` array and are generated the same way.

```json
"builds": [{
  "workflow": "ci.yml", "name": "CI", "branches": ["main", "{environments}"], "paths": ["src/**"],
  "jobs": [{ "id": "test", "name": "Test", "runsOn": "ubuntu-latest", "steps": [
    { "uses": "checkout" },
    { "uses": "setup-dotnet", "with": { "dotnet-version": "10.0.x" } },
    { "name": "Test", "run": "dotnet test" } ] }]
}]
```

Then `.\infra\generate.ps1` and commit. `"{environments}"` expands to every environment's deploy branch; no `branches` means manual runs only. To move an existing hand-written workflow under LazyBicep: describe it in `builds`, delete the file, generate, compare.

### 12. Upgrade GitHub Actions versions everywhere

All generated workflows reference actions by short name from `infra/catalog/workflows/actions.json` (e.g. `"checkout": "actions/checkout@v7"`). Change the version there (kit-wide via a LazyBicep PR, then `-Update`), run `.\infra\generate.ps1`, commit. Every workflow follows.

### 13. Change naming conventions

Names follow `{prefix}-{sub}-{type}-{env}` (lowercase, empty parts dropped, storage accounts and container registries without hyphens; Application Insights adds `-insights`). An app's identity is `{prefix}-{sub}-{apptype}-ident-{env}` (`identityPattern`), e.g. `contoso-shop-apiapp-ident-prod`. Patterns, type and environment abbreviations, the default prefix and length limits live in the project's `infra/naming.json`. Edit it before the first Start of an environment; renaming existing resources means new resources in Azure.

A kit update never changes the project's `naming.json`: a project from 0.1.0 copies the types `contapp`, `contenv`, `contreg` and `ident` (with their `maxLength`), `contapp` in `targets` and `contreg` in `noHyphens` from the LazyBicep repo's `infra/naming.json` before adding a container app.

### 14. A resource type the catalog doesn't have

An import writes a ready-made prompt for each unsupported type (classic CDN, Redis, Cosmos DB, Service Bus topics…) into `infra/new-kinds.md`. To add the kind for everyone:

1. Open Claude Code in the **LazyBicep repo** and paste the prompt from `new-kinds.md`.
2. A kind = `catalog/<kind>.bicep` (fragment), `catalog/<kind>.json` (blueprint), and only for new behaviour a handler in `azure-setup.ps1` or `generate.ps1`.
3. Test with `.\infra\generate.ps1` and a dry run, then open a PR to LazyBicep.
4. In the project: `initintoproject.ps1 <project>\infra -Update`, then `-AddResource -Kind <kind>`.

### 15. Other options

- `-Currency USD` (or GBP…) — cost estimate currency; EUR by default.
- `-RefreshToken` (UI: `t`) — re-set the Static Web App deployment token in GitHub.
- Automation/tests of the UI: `lazybicep.ps1 -Keys "d,wait:ask,Enter,snap" -Frames out.txt`.

## Troubleshooting and FAQ

| Symptom / question | What to do |
| --- | --- |
| `lazybicep.exe` "not recognized" in PowerShell | Use `.\lazybicep.exe` — PowerShell won't run programs from the current folder by name |
| SmartScreen warns about the .exe | Expected on a new PC (unsigned launcher); allow once, or run the `.ps1` |
| UI shows garbled boxes/colours | Use Windows Terminal |
| Wrong subscription or tenant | `az login --tenant <tenant>`, then `az account set --subscription <id>` |
| GitHub step fails (environment, variables, secrets) | `gh auth login` with an account that is admin of the repo |
| Static Web App deploy fails with a token error | Run Start with `-RefreshToken` (UI: `t`), e.g. after resetting the token in the portal |
| SQL "Database access" step can't connect | Allow it to add your IP to the firewall when asked; your account must be the SQL Entra admin you chose |
| Runtime warning about end of support | Pick a newer runtime when asked; old ones Azure no longer offers (e.g. net8.0) are replaced by the closest newer one |
| A container app still shows the placeholder page | It has no image of its own yet: commit and push its workflow, then run a Start (step First image), or run the workflow with `push-only` and Start again |
| Container app workflow fails: "still runs the placeholder" or "no Entra ID sign-in yet" | Its first image and its sign-in come from a Start (steps First image and Sign-in app registrations); afterwards the workflow deploys by itself |
| A container app's new revision doesn't start | Usually a Key Vault secret it references is missing: `-Check` lists them; put them in with `az keyvault secret set ... --file`, then restart the revision (the next steps give the command) |
| Nobody can sign in to a container app | Its app registration requires an assignment: the Entra group asked in the Start must be assigned and the user a member of it (`-` means nobody yet) |
| `-Check` reports an identity no app owns, or a role on an app's identity | An identity outside the map keeps its roles: delete it (command shown) once nothing uses it. A role on an app's identity lets its holder attach it to other resources: delete that role assignment (command shown) |
| Someone changed things in the portal | `-Check` to see drift, `-Start` to restore what the map says |
| I edited `main.bicep` / a `# GENERATED` workflow | Changes will be overwritten; put them in the map and run `.\infra\generate.ps1` |
| Where do project notes go? | `infra/README.md`. `LAZYBICEP.md` is replaced on kit update |
| Is a second Start safe? | Yes — idempotent; same answers change nothing |
| Need more detail on a script | `-Help` on any script, `?` in the UI, `infra/LAZYBICEP.md` |

## Cheat sheet

| Task | Command (from project root) | UI |
| --- | --- | --- |
| Add kit to project | `<LazyBicep>\initintoproject.exe <project>\infra` | — |
| Update kit | `<LazyBicep>\initintoproject.ps1 <project>\infra -Update` | — |
| New project map | `.\infra\azure-setup.ps1 -Init [-Analyze \| -Import -ResourceGroup <rg> \| -SpecFile spec.json]` | `n` |
| Preview analysis | `.\infra\analyze.ps1 [-Out spec.json]` | — |
| Preview import | `.\infra\import.ps1 -ResourceGroup <rg> -List` | — |
| Dry run | `.\infra\azure-setup.ps1 -DryRun -Environment <env>` | `d` |
| Create / update env | `.\infra\azure-setup.ps1 -Start -Environment <env>` | `s` |
| Check drift | `.\infra\azure-setup.ps1 -Check -Environment <env>` | `c` |
| Remove env | `.\infra\azure-setup.ps1 -Remove -Environment <env>` | `r` |
| Add resource | `.\infra\azure-setup.ps1 -AddResource [-Kind <kind>]` | `a` |
| Import into map | `.\infra\azure-setup.ps1 -AddResource -Import [-ResourceGroup <rg>]` | `a` → azure |
| Remove resource | `.\infra\azure-setup.ps1 -RemoveResource -Key <key>` | Map → `x` |
| Add a container app | `.\infra\azure-setup.ps1 -AddResource -Kind containerApp`, then push its workflow and Start | `a` |
| Take a container app offline | `az containerapp ingress disable -g <rg> -n <app>` (never turn its sign-in off) | — |
| Regenerate bicep + workflows | `.\infra\generate.ps1` | automatic |
| Help | `<script> -Help` | `?` |

Golden rules: change the map, never `main.bicep` or `# GENERATED` workflows; always dry run before Start; commit `infra\` and `.github\workflows` after every change.

---

LazyBicep is developed by **Netmedia** · https://netmedia.agency · netmedia@netmedia.hr
