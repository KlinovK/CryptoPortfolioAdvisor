import Foundation

// No raw input is carried in failures: financial text may be private.
enum ATAWireError: Error, Equatable, Sendable {
    case invalidDecimal
    case unrepresentableDecimal
    case invalidTimestamp
    case invalidIdentity
    case invalidSymbol
    case unknownEnum
    case invalidValue
    case inconsistentIdentity
}

enum ATADecimalCodec {
    // Matches backend parse_decimal after its explicit whitespace trimming.
    static func decode(_ text: String) throws -> Decimal {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            text.range(
                of: #"\A-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z"#,
                options: .regularExpression
            ) != nil
        else { throw ATAWireError.invalidDecimal }
        guard var value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
            !value.isNaN
        else { throw ATAWireError.unrepresentableDecimal }
        let rendered = NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))
        // Compare decimal digits, NOT Decimal(text) to Decimal(rendered): both could round.
        guard canonicalDigits(text) == canonicalDigits(rendered) else {
            throw ATAWireError.unrepresentableDecimal
        }
        return value
    }

    static func encode(_ value: Decimal) throws -> String {
        guard !value.isNaN else { throw ATAWireError.invalidDecimal }
        var copy = value
        let text = NSDecimalString(&copy, Locale(identifier: "en_US_POSIX"))
        guard try decode(text) == value else { throw ATAWireError.unrepresentableDecimal }
        return canonicalDigits(text)
    }

    private static func canonicalDigits(_ text: String) -> String {
        var result = text
        if result.contains(".") {
            while result.last == "0" { result.removeLast() }
            if result.last == "." { result.removeLast() }
        }
        return result == "-0" ? "0" : result
    }
}

enum ATATimestampCodec {
    // Frozen server output is six fractional digits + Z. Whole seconds are an
    // explicit compatibility fallback; offsets and other precision are not accepted.
    static func decode(_ text: String) throws -> Date {
        guard
            text.range(
                of: #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{6})?Z\z"#,
                options: .regularExpression
            ) != nil
        else { throw ATAWireError.invalidTimestamp }
        let bytes = Array(text.utf8)
        func number(_ start: Int, _ length: Int) -> Int {
            bytes[start..<(start + length)].reduce(0) { $0 * 10 + Int($1 - 48) }
        }
        let year = number(0, 4)
        let month = number(5, 2)
        let day = number(8, 2)
        let hour = number(11, 2)
        let minute = number(14, 2)
        let second = number(17, 2)
        guard year > 0, (1...12).contains(month), (1...31).contains(day),
            hour < 24, minute < 60, second < 60
        else {
            throw ATAWireError.invalidTimestamp
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )
        guard let base = calendar.date(from: parts) else { throw ATAWireError.invalidTimestamp }
        let actual = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: base)
        guard actual == parts else { throw ATAWireError.invalidTimestamp }
        // TimeInterval is only used for timestamps, never for financial values.
        let microseconds = bytes.count == 27 ? number(20, 6) : 0
        return base.addingTimeInterval(TimeInterval(microseconds) / 1_000_000)
    }
}

enum ATAResponseMapper {
    static func identity(_ text: String) throws -> UUID {
        guard let id = UUID(uuidString: text),
            id != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        else {
            throw ATAWireError.invalidIdentity
        }
        return id
    }

    static func symbol(_ text: String) throws -> AssetSymbol {
        guard let value = try? AssetSymbol(text), value.rawValue == text else {
            throw ATAWireError.invalidSymbol
        }
        return value
    }

    static func enumeration<T: RawRepresentable>(_ text: String, as type: T.Type) throws -> T
    where T.RawValue == String {
        guard let value = T(rawValue: text) else { throw ATAWireError.unknownEnum }
        return value
    }

    static func domain(from dto: ATAScoreComponentDTO) -> ATAScoreComponent {
        ATAScoreComponent(name: dto.name, points: dto.points, maximum: dto.maximum)
    }

    static func domain(from dto: ATAErrorEnvelopeDTO) -> ATAServiceError {
        ATAServiceError(
            code: dto.error.code, message: dto.error.message,
            reloadRequired: dto.error.reloadRequired
        )
    }
}
