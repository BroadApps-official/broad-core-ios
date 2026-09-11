/// One typed event of the host app.
///
/// The platform never invents these. The app owns the code and the fields;
/// BroadCore only carries them to the loggers and to
/// ``BroadSupportLogRecorder``, so a support letter shows what the app was
/// doing next to what the platform was doing. Without this the log of an app
/// that talks to its own backend contains only platform steps, and the reason a
/// generation or a sync failed is missing from the very letter that reports it.
///
/// Codes and field names are declared as `StaticString`; symbolic field values
/// use the same type, while counters and flags accept `Int` and `Bool`.
/// The formatter normalizes punctuation and bounds the size of each entry.
public struct BroadLogHostEvent: Equatable, Sendable {
    /// Maximum length of a code; longer values are truncated.
    public static let maximumCodeLength = 64
    /// Maximum length of a field name or value; longer values are truncated.
    public static let maximumFieldLength = 64
    /// Maximum number of fields kept on one event.
    public static let maximumFieldCount = 8

    public let code: String
    public let category: BroadLogCategory
    public let level: BroadLogLevel
    public let fields: [BroadLogHostField]

    /// - Parameters:
    ///   - code: stable dotted identifier of the event, for example
    ///     `"musicfy.job.failed"`. Empty codes become `"host.event"`.
    ///   - category: which platform category the line is filed under.
    ///   - level: severity of the line.
    ///   - fields: ordered `name=value` pairs; see the type documentation for
    ///     what may go in them.
    public init(
        code: StaticString,
        category: BroadLogCategory = .backend,
        level: BroadLogLevel = .info,
        fields: [BroadLogHostField] = []
    ) {
        let sanitizedCode = BroadLogHostEvent.sanitize(
            code.description,
            limit: BroadLogHostEvent.maximumCodeLength
        )
        self.code = sanitizedCode.isEmpty ? "host.event" : sanitizedCode
        self.category = category
        self.level = level
        self.fields = Array(fields.prefix(BroadLogHostEvent.maximumFieldCount))
    }

    static func sanitize(_ value: String, limit: Int) -> String {
        let allowed = value.prefix(max(0, limit)).map { character -> Character in
            let isAllowed = character.isLetter && character.isASCII
                || character.isNumber && character.isASCII
                || character == "." || character == "_" || character == ":" || character == "-"
            return isAllowed ? character : "-"
        }
        return String(allowed)
    }
}

/// One `name=value` pair of a ``BroadLogHostEvent``. Names and symbolic values
/// are declared constants; numeric counters and boolean flags have typed overloads.
public struct BroadLogHostField: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(_ name: StaticString, _ value: StaticString) {
        self.init(name, formattedValue: value.description)
    }

    public init(_ name: StaticString, _ value: Int) {
        self.init(name, formattedValue: String(value))
    }

    public init(_ name: StaticString, _ value: Bool) {
        self.init(name, formattedValue: value ? "true" : "false")
    }

    private init(_ name: StaticString, formattedValue: String) {
        let sanitizedName = BroadLogHostEvent.sanitize(
            name.description,
            limit: BroadLogHostEvent.maximumFieldLength
        )
        self.name = sanitizedName.isEmpty ? "field" : sanitizedName
        value = BroadLogHostEvent.sanitize(
            formattedValue,
            limit: BroadLogHostEvent.maximumFieldLength
        )
    }
}
