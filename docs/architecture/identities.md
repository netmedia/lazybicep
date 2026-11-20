# Managed identities

## Decision

Every app LazyBicep makes - App Service, Function App, Container App - signs in to Azure with **its own user-assigned
managed identity**:

- **owned by the app**: made together with the app (the blueprint's `creates`), named after it
  (`{prefix}-{sub}-{apptype}-ident-{env}`, `naming.json` `identityPattern`), removed with it;
- **never shared**: no other resource of the map can pick it; one identity per app **per environment** (dev, test and
  prod of one app are three identities);
- **its roles exist before the app starts**: role assignments target the identity, which exists before the app.

The app has no system-assigned identity. `-Check` guards the two ways a user-assigned identity can be misused (below).

This changes AZ 4.2 (system-assigned by default) for projects set up with LazyBicep.

## The two kinds of managed identity

Both are managed identities: Microsoft Entra issues their tokens, there is no secret to store, leak or rotate, and only
code running in the resource (or a resource the identity is attached to) can get a token for it.

| | System-assigned | User-assigned |
|---|---|---|
| What it is | Part of one resource | An Azure resource of its own (`Microsoft.ManagedIdentity/userAssignedIdentities`), attached to one or more resources |
| Lifetime | Created and deleted with its resource | Independent: lives until it is deleted |
| Exists before the resource | No: its principal id appears when the resource is created | Yes |
| Can be attached elsewhere | No | Yes, by anyone with the `.../assign/action` permission on it (Managed Identity Operator, Contributor, Owner) |
| Federated credentials (GitHub, Kubernetes, other clouds sign in as it) | No | Yes |
| What the code needs | Nothing: `DefaultAzureCredential` finds it | Its client id: `AZURE_CLIENT_ID` (and per-feature settings, below) |

## Options weighed

1. **System-assigned for every app** (AZ 4.2 as it stood). Safe by default when people work in the portal - nothing
   can borrow or orphan it. But roles can only be granted once the app exists, so the first start of an app that needs
   a role immediately fails or waits; a recreated app gets a new principal, and its role assignments and SQL database
   users dangle.
2. **User-assigned only where the start order requires it** (Container Apps), system-assigned elsewhere. Correct, but
   two identity models in the kit: two code paths for roles, Key Vault readers, SQL users and removal.
3. **Create a user-assigned identity first, switch to system-assigned, remove the user-assigned one.** Rejected: the
   switch itself creates the system identity and a new revision at the same moment, so the revision hits the same
   missing-role problem; avoiding that needs a third and fourth deployment and a temporary identity to clean up, for
   the same end state as option 4.
4. **User-assigned, owned by each app, for every app** - chosen.

## Why

**Start order.** Some platforms use the identity the moment the app is created:

- a Container App's revision pulls its image from the registry (AcrPull) and resolves its Key Vault secrets (Key Vault
  Secrets User) when it is created;
- a Flex Consumption function app's host reads its storage (identity-based `AzureWebJobsStorage`) and its deployment
  package storage as soon as it starts.

With a system-assigned identity those roles can only be granted after the app exists, and role assignments take a
while to take effect, so the first start fails. With a user-assigned identity the roles are granted to the identity
first, and the app starts with them in place - in one deployment.

**One model.** Every app has the same identity shape, so the generator and the setup have one rule for "the identity
of this app" (`<identity>.properties.principalId` / `.clientId`): role assignments, Key Vault readers, SQL database
users (made by the identity's client id), removal and checks all go through it.

**Stable principal.** Recreating an app (a changed plan, a kind change, a re-import) keeps its identity, so its roles
and its SQL database user stay valid; nothing dangles.

**Future direction.** Federated credentials (workload identity federation) work only with user-assigned identities, and
newer platforms - Container Apps with a registry, Flex Consumption, AKS workload identity - are built around them.

**Security is equal for the credential itself.** The difference lies in who can use, reuse or leave the identity
behind, and the kit closes those gaps by owning the lifecycle:

| Risk of a user-assigned identity | How LazyBicep closes it |
|---|---|
| Another resource borrows it (someone with the assign permission attaches it) | Never offered to another resource of the map; `-Check` reports Managed Identity Operator (and Managed Identity Contributor, Contributor, Owner, User Access Administrator) assignments on an app identity other than inherited ones |
| It outlives its app with its roles (the app deleted outside the kit) | Removed with the app (role assignments first, then the app, then the identity); `-Check` reports an `ident` identity no app of the map owns |
| Shared across environments, so a test app reaches production data | One per app per environment; the name carries the environment |

## What every app gets

| Setting or property | Why |
|---|---|
| `identity: { type: 'UserAssigned', userAssignedIdentities: { <identity>: {} } }` | The app signs in as its identity only |
| `AZURE_CLIENT_ID = <identity client id>` | `DefaultAzureCredential` / `ManagedIdentityCredential` in the app's code pick this identity |
| App Service: `keyVaultReferenceIdentity = <identity>` | `@Microsoft.KeyVault(...)` settings are resolved as the identity (the platform uses the system identity otherwise) |
| Function App: `AzureWebJobsStorage__credential = managedidentity`, `AzureWebJobsStorage__clientId` | The Functions host reads its state as the identity |
| Function App (Flex): deployment storage authentication `UserAssignedIdentity` | The platform reads the deployment package as the identity |
| Function App: every identity-based connection (`<Name>__fullyQualifiedNamespace`, `__queueServiceUri`, `__serviceUri`...): `<Name>__credential`, `<Name>__clientId` | Triggers and bindings sign in as the identity (App Service and Container Apps code uses `AZURE_CLIENT_ID`) |
| SQL connection strings without a password: `User Id=<identity client id>` | SqlClient's Entra authentication picks the identity |
| Container App: registry `identity` and Key Vault secrets' `identity` = the identity | The image pull and the secrets use it |

## Importing an app that has a system-assigned identity

A start of an imported ("connect") app adds its user-assigned identity, grants the identity the app's roles and
switches the app to it. The old identity's role assignments and SQL database users are listed in the run's next steps
to remove by hand once the app works with the new one.

## Open

- The GitHub deploy identity is still an Entra app registration with federated credentials per GitHub environment. A
  user-assigned identity with federated credentials would remove the need for directory rights to create app
  registrations; to be decided.
- Static Web Apps' managed functions cannot use managed identities (a platform limit); they keep settings.
