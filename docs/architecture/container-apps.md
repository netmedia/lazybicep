# Container Apps

## Decision

A containerised app runs on Azure Container Apps as four kinds of resources with clear ownership:

| Resource | Belongs to | Tie in the map | Why |
|---|---|---|---|
| Container App | itself (a deployment target) | the app | One deployable app |
| Its identity | the app | `creates`: made and removed with it, never shared | Its roles must exist before its first revision ([identities.md](identities.md)) |
| Container Apps environment | the project's environment | `requires`: an existing one of the map or a new one | Hosts many apps, like an App Service plan; logs to a Log Analytics workspace (`requires`, existing or new) |
| Container registry | the project (one environment or shared) | `requires`: an existing one of the map or a new one | Serves many apps; apps pull with their identity (AcrPull), admin user and anonymous pull off |

Picking **Container App** in a new project therefore brings everything it needs in one go (answer "new" for the
environment and the registry); the second app picks the existing ones and gets only itself and its identity. Removing
an app removes its identity; the environment and the registry stay until no app uses them.

## Who owns the image

**The infrastructure never changes the image an app runs; the app's deploy workflow does.**

On App Service the code is deployed into an existing app, so the infrastructure template and the deploy never touch
the same thing. On Container Apps the image is part of the app's definition: a template that names an image would put
an old image back on every infrastructure run. So:

- a **new** app is created with the public placeholder `mcr.microsoft.com/k8se/quickstart`, **pinned by digest**
  (`@sha256:3a4d93c3…`, not `:latest`: it runs with the app's identity attached, so a changed image behind a tag must
  never start there) (port 80, no probes, no registry pull, no secrets needed);
- its **first** own image comes from the setup's step First image (asked): the app's workflow runs with `push-only`,
  then the template deploys that image with the app's port, probes and Key Vault secrets - the workflow alone refuses
  an app still on the placeholder;
- every **later** start reads the image Azure runs now and passes it back unchanged;
- the generated workflow builds the image on the runner, pushes it to the registry tagged with the commit SHA, updates
  only the app's image, and waits until the health path answers.

Infrastructure runs and app deploys never undo each other, and an infrastructure change never deploys code (the first
image is the one exception, asked for by the setup's step First image).

## Sign-in in front of an app

Container Apps' built-in sign-in (`authConfigs`, often called Easy Auth) with Microsoft Entra ID, made by the kit when
the app's map entry has `signIn`:

- the setup makes the **sign-in app registration** per environment (ID tokens, redirect
  `https://<fqdn>/.auth/login/aad/callback`, no client secret, token store off; optional identifier URI and app roles
  for APIs that accept tokens from other applications), with *Assignment required* and the group asked per
  environment;
- the sign-in is **for users**: its allowed audience is the client id only, never the identifier URI. With
  `api://<client id>` accepted too, an app-only token issued for that URI (client credentials of a daemon or another
  API sharing the registration) would pass on every signed-in route, where the app treats the caller as a signed-in
  user (CWE-863). This narrows the gap but does not close it: a client-credentials token requested for the client id
  itself (`<client id>/.default`) has the client id as its audience and passes, so an app that trusts the platform's
  principal must also refuse app-only principals (no user claim such as `name` / `preferred_username` / `upn`, or
  `idtyp=app`). An API that applications call lives on an excluded path and validates its own tokens (audience,
  issuer, roles);
- **excluded paths** pass without sign-in (health checks, endpoints with their own authentication); for each `/x/*`
  the kit also excludes `/x`, which the wildcard does not cover; the health path is always excluded, so it is never
  `/` or `/*` for an app with sign-in (the generator refuses it: the root must never be anonymous);
- the app is **created with the placeholder image**, so the real code never answers before its sign-in exists. (A
  Container App and its `authConfigs` in one deployment are created one after the other: an app created with its real
  image would serve requests without sign-in for that moment.)
- an app that trusts the platform's `X-MS-CLIENT-PRINCIPAL` header must only be reachable through the platform's
  sign-in - never disable sign-in to debug; take the app offline with `az containerapp ingress disable` instead.

## Deploying

The deploy app registration (OIDC, no stored secrets) gets **AcrPush** on the registry and **Container Apps
Contributor** on the app only - it can push an image and update the app, nothing else. Adding a container app always
(re)adds AcrPush on its registry to the map, so a registry kept from an earlier app or added by hand still gets it.
The image is built on the GitHub runner (`docker build`), not with `az acr build`, which needs a broader role on the registry.

## Platform limits the kit respects

- Probe limits: `initialDelaySeconds` 0-60, `periodSeconds` and `timeoutSeconds` 1-240, `failureThreshold` 1-10 - a
  longer startup window comes from the period, not the threshold.
- Container App names: 2-32 characters, lowercase letters, digits and hyphens.
- Registry names: 5-50 letters and digits, globally unique.

## Open

- Custom domains with managed certificates on a Container App.
- Private networking (VNet-integrated environment, private registry).
- Pinning base images by digest is the project's Dockerfile's concern, not the kit's.
