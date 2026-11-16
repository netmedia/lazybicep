@description('{{title}}: the subscription (and the name of the system topic on {{sourceTitle}}, with -events).')
param {{name}} string

@description('Make {{title}}: the setup sets it once {{targetTitle}} has its function {{function}} (Azure checks the endpoint; the first start comes before the app is deployed).')
param {{ready}} bool = false

// {{sourceTitle}}'s events as an Event Grid system topic (one per resource).
resource {{key}}Topic 'Microsoft.EventGrid/systemTopics@2025-02-15' = {
  name: '${ {{name}} }-events'
  location: location
  tags: tags
  properties: {
    source: {{source}}.id
    topicType: '{{topicType}}'
  }
}

resource {{key}} 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2025-02-15' = if ({{ready}}) {
  parent: {{key}}Topic
  name: {{name}}
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${ {{target}}.id }/functions/{{function}}'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
{{eventTypes}}
{{filters}}
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: { maxDeliveryAttempts: 30, eventTimeToLiveInMinutes: 1440 }
  }
}
