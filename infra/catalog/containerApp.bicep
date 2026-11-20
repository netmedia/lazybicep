@description('{{title}} (2-32 lowercase letters, digits and hyphens).')
@minLength(2)
@maxLength(32)
param {{name}} string

@description('The image {{title}} runs now (infra/azure-setup.ps1 reads it from Azure; its deploy workflow changes it, never this template). Empty: the public placeholder (a new app).')
param {{image}} string = ''
//#if signIn

@description('Client id of the sign-in app registration of {{title}} (infra/azure-setup.ps1, step Sign-in app registration). Empty: no sign-in yet, so {{title}} runs the placeholder.')
param {{signInClientId}} string = ''
//#end

// The infrastructure never changes the image (docs/architecture/container-apps.md). A new app runs the public
// placeholder until the setup's step First image deploys its first own image; later starts pass the image Azure
// runs now. The placeholder has port 80, no probes and no Key Vault secrets (the hand secrets go into a new vault
// after the first start); its registry and plain settings are the app's from the start (its identity's roles exist
// before it, dependsOn). Once it runs its own image, a deploy changes only the image.
// Pinned by digest, not a tag: the placeholder runs with the app's identity attached (AcrPull, Key Vault Secrets
// User), so a changed image behind the same tag must never start there (digest looked up on MCR 2026-11-20).
var {{key}}Placeholder = 'mcr.microsoft.com/k8se/quickstart@sha256:3a4d93c34c6753f24765ab17a36f1754aee9b02082b7d9553d17697b9e8252c4'
{{realComment}}
var {{key}}Real = {{realExpr}}

var {{key}}Settings = {{settingsArray}}
//#if secrets

// Key Vault secrets by reference, read with its identity when a revision starts: never a value here. Only with its
// own image, as are the settings that read them.
var {{key}}Secrets = {{secretsArray}}

var {{key}}SecretSettings = {{secretSettingsArray}}
//#end
//#if health

// Container Apps' probe limits: initialDelaySeconds 0-60, periodSeconds and timeoutSeconds 1-240, failureThreshold
// 1-10. The startup window comes from the period (5 + 10 x 10 = 105 s), not from the threshold.
var {{key}}Probes = [
  {
    type: 'Startup'
    httpGet: { path: {{healthPath}}, port: {{port}} }
    initialDelaySeconds: 5
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 10
  }
  {
    type: 'Liveness'
    httpGet: { path: {{healthPath}}, port: {{port}} }
    initialDelaySeconds: 5
    periodSeconds: 30
    timeoutSeconds: 5
    failureThreshold: 3
  }
  {
    type: 'Readiness'
    httpGet: { path: {{healthPath}}, port: {{port}} }
    initialDelaySeconds: 5
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3
  }
]
//#end

resource {{key}} 'Microsoft.App/containerApps@2025-07-01' = {
  name: {{name}}
  location: location
  tags: tags
  // Signs in to Azure as its own user-assigned identity only: the image pull and the Key Vault secrets too.
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${{{identity}}.id}': {} } }
  properties: {
    environmentId: {{environment}}.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: '{{revisionMode}}'
      ingress: {
        external: {{external}}
        targetPort: {{key}}Real ? {{port}} : 80
        transport: 'auto'
        allowInsecure: false // HTTPS only: plain HTTP is redirected
        stickySessions: { affinity: '{{affinity}}' }
        traffic: [
          { latestRevision: true, weight: 100 }
        ]
      }
      registries: [
        { server: {{registry}}.properties.loginServer, identity: {{identity}}.id }
      ]
//#if secrets
      secrets: {{key}}Real ? {{key}}Secrets : []
//#end
    }
    template: {
      containers: [
        {
          name: '{{containerName}}'
          image: {{key}}Real ? {{image}} : {{key}}Placeholder
          resources: { cpu: json('{{cpu}}'), memory: '{{memory}}' }
          env: {{envExpr}}
//#if health
          probes: {{key}}Real ? {{key}}Probes : []
//#end
        }
      ]
      scale: { minReplicas: {{minReplicas}}, maxReplicas: {{maxReplicas}} }
    }
  }
{{dependsOn}}
}
//#if signIn

// Sign-in by the platform with Entra ID (own tenant): the ID token, so no client secret; token store off. Made only
// with a client id - until then the app runs the placeholder, so its own code never answers without sign-in. An app
// that trusts X-MS-CLIENT-PRINCIPAL is only safe behind it: never turn it off to debug (take the app offline with
// az containerapp ingress disable). The excluded paths pass without sign-in: {{excludedNote}}.
resource {{key}}SignIn 'Microsoft.App/containerApps/authConfigs@2025-07-01' = if (!empty({{signInClientId}})) {
  parent: {{key}}
  name: 'current'
  properties: {
    platform: { enabled: true }
    globalValidation: {
      unauthenticatedClientAction: '{{unauthenticatedAction}}'
{{redirectLine}}
      excludedPaths: {{excludedPaths}}
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: {{signInClientId}}
          openIdIssuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: {{audiences}}
        }
      }
    }
    login: { tokenStore: { enabled: false } }
    httpSettings: { requireHttps: true }
  }
}
//#end
