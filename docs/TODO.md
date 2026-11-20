# LazyBicep — TODO

What is built but not yet tried against Azure, and what was left out on purpose. Tick an item off (or
delete it) once it is done.

## To check (built, not run against Azure yet)

These need an Azure sign-in and a real terminal; they were tested offline only (stubs, generated
`main.bicep` compiled with `az bicep build`).

- [ ] **The full import against a real subscription.** Read-only; it reads the apps' settings (to see what
      they use), which is why it wasn't run while it was built:
      ```
      .\infra\import.ps1 -ResourceGroup dt-indamix-resgr-prod -List
      .\infra\import.ps1 -ResourceGroup dt-indamix-resgr-prod
      ```
      Check: the kinds, the apps' runtimes and plans, what each app uses (settings, role assignments),
      the queues, the Front Door's origin, and `infra/new-kinds.md` for anything missing.
- [ ] **The Azure import in lazybicep (TUI).** Only tried in the console. On the New project screen `n`, then
      `azure`; in a project with a map `a`, then `azure`. Check how the resource-group picker looks with
      many groups (the subscription has about 34).
- [ ] **A dry run of a map with `values`** (per-environment values from the analysis): they should be asked
      in "Names", saved in `infra/environments/<env>.json` and passed to `main.bicep`.
- [ ] **The next step for secrets put in by hand.** Appears after a start, once the vault exists in Azure:
      the `az keyvault secret set ...` lines for the missing secrets and the restart of the apps that read
      them.
- [ ] **An imported environment's first dry run (connect).** `environments/<env>.json` marked `imported`:
      every question asked once with the real names as defaults; the what-if should find the resources as
      existing and show only what the kit adds (identities, roles, settings, security).
- [ ] **The monthly budget.** A start sets `monthly-<environment>` on the environment's resource group; check
      that it appears (Cost Management -> Budgets) with the three alerts, that a second run reports it as set,
      and what a subscription without budgets says (the MPN one may be such).

### 0.2.0: identities and Container Apps (first run: PiiGateway's dev environment)

- [ ] **Container Apps what-if noise.** A second start with the same answers should change nothing; check
      whether the what-if of a container app (and its `authConfigs`, the environment's diagnostic setting)
      reports changes that aren't real (`Test-RealChange` may need more of them).
- [ ] **`az containerapp update --image` with Container Apps Contributor only.** The deploy app registration
      has that role on the app and nothing else: check the workflow's deploy step succeeds (the update may read
      the environment or the registry).
- [ ] **`az acr login` with AcrPush only.** The workflow's push step signs in to the registry with the deploy
      app registration's token (AcrPush on the registry, no reader role on the group).
- [ ] **`az containerapp auth show` output.** The workflow's sign-in guard queries
      `platform.enabled && identityProviders.azureActiveDirectory.enabled`; the setup also reads
      `properties.*`. Check the real output's shape and that the guard says `true`.
- [ ] **The Graph PATCH bodies of the sign-in step.** App roles (`PATCH /applications/<id>` with `appRoles`) and
      the group assignment (`POST /servicePrincipals/<id>/appRoleAssignedTo`, default role
      `00000000-...`): check both on a real tenant, and that a second run finds nothing to change.
- [ ] **`gh run` timing in First image.** The setup finds its `push-only` run by the time it started (30 s
      back, 20 tries of 3 s) and watches it; check with a slow queue and with another run of the same
      workflow at the same time.
- [ ] **`show-tags` rights of the person running the setup.** First image reads the pushed tag with
      `az acr repository show-tags` (a data-plane call): check which role the person needs on the registry
      (Owner of the subscription may not be enough without AcrPull or a reader data role).
- [ ] **The extra deployments in one start.** A start may deploy `main.bicep` three times (resources, the
      sign-in's client id, the first image): check the what-if shown each time, the time it takes, and that an
      answer of "no" in between leaves a state the next start finishes.
- [ ] **Flex Consumption accepting `keyVaultReferenceIdentity`.** The function app fragment sets it for every
      function app; check that a Flex Consumption app takes it (and reads Key Vault references with it).
- [ ] **Identity switch on an imported system-assigned app.** Connect an app with a system-assigned identity:
      the start should add its own identity, grant the roles, switch the app, and list the old identity's role
      assignments and SQL users in the next steps. Check the app keeps working during the switch.

## Left out on purpose (later)

- [ ] **Front Door: custom domain.** A custom domain on the endpoint with Front Door's managed certificate
      (and its DNS records in the setup's custom domains step).
- [ ] **Front Door: lock the app to it.** The app stays reachable directly; restrict it to the service tag
      `AzureFrontDoor.Backend` and the `X-Azure-FDID` header.
- [ ] **Front Door import: endpoint name.** An imported Front Door whose endpoint isn't named after the
      profile gets a second endpoint planned by a dry run; take the existing endpoint's name instead.
- [ ] **Configuration analysis for Node and Python.** Only `.env` files are read; also read `process.env.X`
      and `os.environ["X"]` / `os.getenv("X")` in the code.
- [ ] **Container Apps: custom domains.** A custom domain with a managed certificate on a container app (and
      its DNS records in the setup's custom domains step).
- [ ] **Container Apps: private networking.** A VNet-integrated environment and a private registry; today the
      environment, the registry and the apps' ingress are public (HTTPS only).
- [ ] **Container Apps: an environment or registry shared from another resource group.** Both must be in the
      app's resource group for now (`generate.ps1` stops otherwise).
- [ ] **Container Apps: a separate readiness path.** One health path serves the startup, liveness and readiness
      probes today (AZ 5.3 trade-off: a data-source outage must not restart the app); an optional readiness path
      (e.g. `/health/ready`) for the readiness probe only.
- [ ] **Pin GitHub Actions by commit SHA.** `catalog/workflows/actions.json` names the actions by version tag;
      pin each by its commit SHA (with the tag as a comment) and keep them updated (Dependabot).
- [ ] **`deploy.migrate` for container apps.** The migration bundle runs from an App Service or Function App
      deploy only; a container app's workflow stops on it.
- [ ] **Shared identities.** One identity per app per environment, on purpose; an imported shared identity is
      reported and each app gets its own.
- [ ] **The deploy identity as a user-assigned identity with federated credentials.** GitHub Actions still signs
      in as an Entra app registration (needs directory rights to make it); a user-assigned identity would not.
- [ ] **Kinds the catalog doesn't have yet**, reported by the import with a prompt each in
      `infra/new-kinds.md`: Service Bus topics and subscriptions, Redis, Cosmos DB, PostgreSQL / MySQL, Event
      Hubs, SignalR... Add them as projects need them (paste the prompt to Claude Code in this repository).
