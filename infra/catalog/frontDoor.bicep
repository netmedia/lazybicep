@description('{{title}}: the Front Door profile (Standard or Premium); its endpoint is named after it.')
param {{name}} string

@description('Tier of {{title}}: Standard_AzureFrontDoor or Premium_AzureFrontDoor (private links, the managed WAF rule sets).')
@allowed({{sizeOptions}})
param {{size}} string = '{{sizeDefault}}'

resource {{key}} 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: {{name}}
  location: 'global'
  tags: tags
  sku: { name: {{size}} }
  properties: { originResponseTimeoutSeconds: 60 }
}

// The endpoint: <name>-<hash>.z01.azurefd.net (an endpoint's name is at most 46 characters).
resource {{key}}Endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: {{key}}
  name: take({{name}}, 46)
  location: 'global'
  tags: tags
  properties: { enabledState: 'Enabled' }
}

// {{originTitle}}: the one origin, probed on {{probePath}}.
resource {{key}}Origins 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: {{key}}
  name: 'origins'
  properties: {
    loadBalancingSettings: { sampleSize: 4, successfulSamplesRequired: 3, additionalLatencyInMilliseconds: 50 }
    healthProbeSettings: { probePath: '{{probePath}}', probeRequestType: 'HEAD', probeProtocol: 'Https', probeIntervalInSeconds: 120 }
    sessionAffinityState: 'Disabled'
  }
}

resource {{key}}Origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: {{key}}Origins
  name: '{{origin}}'
  properties: {
    hostName: {{originHost}}
    originHostHeader: {{originHost}}
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

resource {{key}}Route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: {{key}}Endpoint
  name: 'default'
  dependsOn: [{{key}}Origin] // the group needs its origin first
  properties: {
    originGroup: { id: {{key}}Origins.id }
    supportedProtocols: ['Http', 'Https']
    patternsToMatch: ['/*']
    forwardingProtocol: 'HttpsOnly'
    httpsRedirect: 'Enabled'
    linkToDefaultDomain: 'Enabled'
//#if cache
    cacheConfiguration: {
      queryStringCachingBehavior: 'UseQueryString'
      compressionSettings: {
        isCompressionEnabled: true
        contentTypesToCompress: ['text/html', 'text/css', 'text/plain', 'text/xml', 'text/javascript', 'application/javascript', 'application/json', 'application/xml', 'image/svg+xml', 'font/ttf', 'font/otf']
      }
    }
//#end
  }
}
