import Foundation

struct PortfolioFinancialFormatter: Sendable {
    private let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    func quantity(_ value: Decimal) -> String {
        let magnitude = magnitude(of: value)
        if magnitude.compare(NSDecimalNumber(value: 1)) != .orderedAscending {
            return format(
                value,
                style: .decimal,
                minimumFractionDigits: 0,
                maximumFractionDigits: 8
            )
        }

        return format(
            value,
            style: .decimal,
            minimumFractionDigits: 0,
            maximumFractionDigits: 38,
            maximumSignificantDigits: 8
        )
    }

    func usd(_ value: Decimal) -> String {
        let magnitude = magnitude(of: value)
        if magnitude.compare(NSDecimalNumber(value: 1)) != .orderedAscending {
            return format(
                value,
                style: .currency,
                minimumFractionDigits: 2,
                maximumFractionDigits: 2
            )
        }
        if magnitude.compare(NSDecimalNumber(string: "0.01")) != .orderedAscending {
            return format(
                value,
                style: .currency,
                minimumFractionDigits: 2,
                maximumFractionDigits: 4
            )
        }

        return format(
            value,
            style: .currency,
            minimumFractionDigits: 0,
            maximumFractionDigits: 38,
            maximumSignificantDigits: 6
        )
    }

    func percentage(_ value: Decimal) -> String {
        let magnitude = magnitude(of: value)
        let formatted: String
        if magnitude.compare(NSDecimalNumber(string: "0.01")) == .orderedAscending,
           value != 0 {
            formatted = format(
                value,
                style: .decimal,
                minimumFractionDigits: 0,
                maximumFractionDigits: 38,
                maximumSignificantDigits: 4
            )
        } else {
            formatted = format(
                value,
                style: .decimal,
                minimumFractionDigits: 0,
                maximumFractionDigits: 2
            )
        }
        return "\(formatted)%"
    }

    private func format(
        _ value: Decimal,
        style: NumberFormatter.Style,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int,
        maximumSignificantDigits: Int? = nil
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = style
        formatter.currencyCode = "USD"
        formatter.roundingMode = .halfUp
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        if let maximumSignificantDigits {
            formatter.usesSignificantDigits = true
            formatter.minimumSignificantDigits = 1
            formatter.maximumSignificantDigits = maximumSignificantDigits
        }
        formatter.usesGroupingSeparator = true

        if let formatted = formatter.string(from: NSDecimalNumber(decimal: value)) {
            return formatted
        }

        var value = value
        return NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))
    }

    private func magnitude(of value: Decimal) -> NSDecimalNumber {
        let number = NSDecimalNumber(decimal: value)
        if number.compare(NSDecimalNumber(value: 0)) == .orderedAscending {
            return number.multiplying(by: NSDecimalNumber(value: -1))
        }
        return number
    }
}

enum AnalysisModePresentation {
    static func title(for mode: AnalysisMode) -> String {
        switch mode {
        case .deterministic:
            "Deterministic analysis"
        case .aiAssisted:
            "AI-assisted analysis"
        case .aiFallback:
            "AI unavailable — deterministic analysis used"
        }
    }
}

enum RiskPresentation {
    static func title(for riskLevel: RiskLevel) -> String {
        switch riskLevel {
        case .low:
            "Low risk"
        case .moderate:
            "Moderate risk"
        case .high:
            "High risk"
        }
    }

    static func systemImage(for riskLevel: RiskLevel) -> String {
        switch riskLevel {
        case .low:
            "checkmark.shield"
        case .moderate:
            "exclamationmark.shield"
        case .high:
            "exclamationmark.triangle"
        }
    }
}
