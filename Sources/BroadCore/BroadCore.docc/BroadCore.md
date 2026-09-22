# ``BroadCore``

Foundation contracts for reliable BroadApps iPhone application startup and state.

## Topics

### Bootstrap

- ``AppBootstrapCoordinator``
- ``BootstrapStep``
- ``AppBootstrapState``

### Policies and cache

- ``RetryPolicy``
- ``TimeoutPolicy``
- ``CachePolicy``
- ``CacheEnvelope``
- ``CacheReadResult``
- ``UserDefaultsKeyValueStore``
- ``FileSystemKeyValueStore``

### Errors and logging

- ``AppError``
- ``NetworkFailureClassifier``
- ``BroadLoggerProtocol``
- ``BroadLogEvent``
- ``BroadLogHostEvent``
- ``BroadLogHostField``
- ``OSLogBroadLogger``
- ``BroadSupportLogRecorder``
- ``CompositeBroadLogger``
- ``NoOpBroadLogger``

### Tracking

- ``TrackingAuthorizationUseCaseProtocol``
- ``SystemTrackingAuthorizationAdapter``

### Debug

- ``DebugFlag``
- ``DebugFlagStore``

### Server time

- ``ServerTimeReading``
- ``ServerTimeProviderProtocol``
- ``ServerSynchronizedClock``
- ``HTTPServerDate``

### Account identity

- ``AccountIdentifierProviderProtocol``
- ``AccountIdentifierResolution``
- ``AccountIdentifierSource``
- ``KeychainAccountIdentifierStore``
- ``KeychainAccountIdentifierConfiguration``

## Optional provider logging

Provider-specific diagnostics use ``BroadLogHostEvent`` and ``BroadLogHostField``. Billing implementations and their event vocabularies live in optional provider packages.
