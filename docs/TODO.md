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

## Left out on purpose (later)

- [ ] **Front Door: custom domain.** A custom domain on the endpoint with Front Door's managed certificate
      (and its DNS records in the setup's custom domains step).
- [ ] **Front Door: lock the app to it.** The app stays reachable directly; restrict it to the service tag
      `AzureFrontDoor.Backend` and the `X-Azure-FDID` header.
- [ ] **Front Door import: endpoint name.** An imported Front Door whose endpoint isn't named after the
      profile gets a second endpoint planned by a dry run; take the existing endpoint's name instead.
- [ ] **Configuration analysis for Node and Python.** Only `.env` files are read; also read `process.env.X`
      and `os.environ["X"]` / `os.getenv("X")` in the code.
- [ ] **Kinds the catalog doesn't have yet**, reported by the import with a prompt each in
      `infra/new-kinds.md`: Service Bus topics and subscriptions, Redis, Cosmos DB, Container Apps,
      PostgreSQL / MySQL, Event Hubs, SignalR, a user-assigned managed identity... Add them as projects need
      them (paste the prompt to Claude Code in this repository).
