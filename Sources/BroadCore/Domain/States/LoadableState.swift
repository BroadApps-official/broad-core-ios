public enum LoadableState<Value: Sendable>: Sendable {
    case idle
    case loading(previousValue: Value?)
    case loaded(Value)
    case empty
    case stale(value: Value, error: AppError?)
    case error(AppError, previousValue: Value?)

    public var value: Value? {
        switch self {
        case .idle, .empty:
            nil
        case let .loading(previousValue), let .error(_, previousValue):
            previousValue
        case let .loaded(value), let .stale(value, _):
            value
        }
    }

    public var error: AppError? {
        switch self {
        case let .stale(_, error):
            error
        case let .error(error, _):
            error
        case .idle, .loading, .loaded, .empty:
            nil
        }
    }

    public var isLoading: Bool {
        if case .loading = self {
            return true
        }

        return false
    }

    public var hasContent: Bool {
        switch self {
        case .loaded, .stale:
            return true
        case let .loading(previousValue), let .error(_, previousValue):
            if case .some = previousValue {
                return true
            }

            return false
        case .idle, .empty:
            return false
        }
    }

    public func beginLoading(preservingValue: Bool = true) -> LoadableState<Value> {
        .loading(previousValue: preservingValue ? value : nil)
    }

    public func fail(
        with error: AppError,
        preservingValue: Bool = true
    ) -> LoadableState<Value> {
        .error(
            error,
            previousValue: preservingValue ? value : nil
        )
    }
}

extension LoadableState: Equatable where Value: Equatable {}
