# Infrastructure architecture

Why LazyBicep builds Azure infrastructure the way it does. These pages hold the decisions and the reasoning behind
them; they are the first chapters of Netmedia's future **Infrastructure Architecture Guide**, written while the
decisions are made so the guide can be assembled from them later.

How to use them:

- `LAZYBICEP.md` says **what** the kit does and how to use it; these pages say **why**.
- One page per topic. Each page states the decision first, then the options that were weighed, the reasoning, what
  the kit enforces, and what is left open.
- A decision that changes the Netmedia Azure Conventions (the `netmedia` plugin's `conventions-azure`, cited `AZ x.y`)
  names the rule; the conventions and the kit are kept in sync.

| Page | Topic | Decided |
|---|---|---|
| [identities.md](identities.md) | Managed identities: user-assigned, owned by each app, one per app per environment | 2026-11-19 |
| [container-apps.md](container-apps.md) | Container Apps: which resources belong together, who owns the image, sign-in in front of an app | 2026-11-19 |

## For the guide (later)

Topics the guide will need that are not decided here yet: networking (private endpoints, VNet integration),
custom domains for Container Apps, the GitHub deploy identity as a user-assigned identity with federated credentials
instead of an app registration, monitoring and alerts per environment, cost and budgets, disaster recovery.
