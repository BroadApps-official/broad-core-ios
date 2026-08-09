import Swinject

public final class BroadCoreAssembly: Assembly {
    private let bootstrapSteps: [BootstrapStep]
    private let bootstrapErrorMessages: BootstrapErrorMessages
    private let cacheRepository: any CacheRepositoryProtocol
    private let stateStore: any KeyValueStoreProtocol
    private let logger: any BroadLoggerProtocol
    private let trackingAuthorizationRepository: any TrackingAuthorizationRepositoryProtocol

    public init(
        bootstrapSteps: [BootstrapStep] = [],
        bootstrapErrorMessages: BootstrapErrorMessages = .englishDefault,
        cacheRepository: (any CacheRepositoryProtocol)? = nil,
        stateStore: (any KeyValueStoreProtocol)? = nil,
        logger: any BroadLoggerProtocol = NoOpBroadLogger(),
        trackingAuthorizationRepository: any TrackingAuthorizationRepositoryProtocol =
            SystemTrackingAuthorizationAdapter()
    ) {
        self.bootstrapSteps = bootstrapSteps
        self.bootstrapErrorMessages = bootstrapErrorMessages
        self.logger = logger
        self.trackingAuthorizationRepository = trackingAuthorizationRepository

        if let stateStore {
            self.stateStore = stateStore
        } else {
            self.stateStore = UserDefaultsKeyValueStore(
                namespace: "com.broadapps.platform.state"
            )
        }

        if let cacheRepository {
            self.cacheRepository = cacheRepository
        } else {
            self.cacheRepository = VersionedJSONCacheRepository(
                keyValueStore: UserDefaultsKeyValueStore(
                    namespace: "com.broadapps.platform.cache"
                ),
                logger: logger
            )
        }
    }

    public func assemble(container: Container) {
        container
            .register(BroadCoreModule.self) { _ in
                BroadCoreModule()
            }
            .inObjectScope(.container)

        container
            .register(BroadLoggerProtocol.self) { [logger] _ in
                logger
            }
            .inObjectScope(.container)

        container
            .register(CacheRepositoryProtocol.self) { [cacheRepository] _ in
                cacheRepository
            }
            .inObjectScope(.container)

        container
            .register(KeyValueStoreProtocol.self) { [stateStore] _ in
                stateStore
            }
            .inObjectScope(.container)

        container
            .register(TrackingAuthorizationRepositoryProtocol.self) { [trackingAuthorizationRepository] _ in
                trackingAuthorizationRepository
            }
            .inObjectScope(.container)

        container
            .register(TrackingAuthorizationUseCaseProtocol.self) { [trackingAuthorizationRepository] _ in
                RequestTrackingAuthorizationUseCase(
                    repository: trackingAuthorizationRepository
                )
            }
            .inObjectScope(.container)

        container
            .register(RunAppBootstrapUseCaseProtocol.self) { [bootstrapErrorMessages, bootstrapSteps, logger] _ in
                AppBootstrapCoordinator(
                    steps: bootstrapSteps,
                    errorMessages: bootstrapErrorMessages,
                    logger: logger
                )
            }
            .inObjectScope(.container)
    }
}
