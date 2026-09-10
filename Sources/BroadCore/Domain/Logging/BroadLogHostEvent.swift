/// One typed event of the host app.
///
/// The platform never invents these. The app owns the code and the fields;
/// BroadCore only carries them to the loggers and to
/// ``BroadSupportLogRecorder``, so a support letter shows what the app was
/// doing next to what the platform was doing. Without this the log of an app
/// that talks to its own backend contains only platform steps, and the reason a
/// generation or a sync failed is missing from the very letter that reports it.
///
/// It is deliberately not a free-text channel. A field carries a code, an enum
/// case or a count — never a URL, a receipt, a token, an identifier or a raw
/// error message. Values are sanitized on the way in: everything outside
/// `A-Za-z0-9._:-` becomes `-`, and both halves are capped, so a careless call
/// site cannot smuggle payment data or a stack trace into a file the user
/// e-mails to support.
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
        code: String,
        category: BroadLogCategory = .backend,
        level: BroadLogLevel = .info,
        fields: [BroadLogHostField] = []
    ) {
        let sanitizedCode = BroadLogHostEvent.sanitize(
            code,
            limit: BroadLogHostEvent.maximumCodeLength
        )
        self.code = sanitizedCode.isEmpty ? "host.event" : sanitizedCode
        self.category = category
        self.level = level
        self.fields = Array(fields.prefix(BroadLogHostEvent.maximumFieldCount))
    }

    static func sanitize(_ value: String, limit: Int) -> String {
        let allowed = value.map { character -> Character in
            let isAllowed = character.isLetter && character.isASCII
                || character.isNumber && character.isASCII
                || character == "." || character == "_" || character == ":" || character == "-"
            return isAllowed ? character : "-"
        }
        return String(allowed.prefix(max(0, limit)))
    }
}

/// One `name=value` pair of a ``BroadLogHostEvent``. Both halves are sanitized
/// the same way the code is.
public struct BroadLogHostField: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(_ name: String, _ value: String) {
        let sanitizedName = BroadLogHostEvent.sanitize(
            name,
            limit: BroadLogHostEvent.maximumFieldLength
        )
        self.name = sanitizedName.isEmpty ? "field" : sanitizedName
        self.value = BroadLogHostEvent.sanitize(
            value,
            limit: BroadLogHostEvent.maximumFieldLength
        )
    }

    public init(_ name: String, _ value: Int) {
        self.init(name, String(value))
    }

    public init(_ name: String, _ value: Bool) {
        self.init(name, value ? "true" : "false")
    }
}
