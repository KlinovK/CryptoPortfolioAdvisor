import Foundation

struct AssetPositionDraftErrors: Equatable, Sendable {
    var symbol: String?
    var amount: String?

    var isEmpty: Bool {
        symbol == nil && amount == nil
    }
}

struct TradingConstraintsDraftErrors: Equatable, Sendable {
    var additionalMonthlyIncomeUSD: String?
    var minimumStableReserveUSD: String?

    var isEmpty: Bool {
        additionalMonthlyIncomeUSD == nil && minimumStableReserveUSD == nil
    }
}

struct LimitOrderDraftErrors: Equatable, Sendable {
    var symbol: String?
    var amountUSD: String?
    var targetPrice: String?

    var isEmpty: Bool {
        symbol == nil && amountUSD == nil && targetPrice == nil
    }
}

struct DashboardValidationErrors: Equatable, Sendable {
    var assetPositions: [UUID: AssetPositionDraftErrors] = [:]
    var constraints = TradingConstraintsDraftErrors()
    var limitOrders: [UUID: LimitOrderDraftErrors] = [:]
    var form: String?

    var hasErrors: Bool {
        !assetPositions.isEmpty
            || !constraints.isEmpty
            || !limitOrders.isEmpty
            || form != nil
    }
}

struct ValidatedDashboardInput: Equatable, Sendable {
    let portfolio: Portfolio
    let constraints: TradingConstraints
    let limitOrders: [LimitOrder]
}

struct DashboardValidationOutcome: Equatable, Sendable {
    let validatedInput: ValidatedDashboardInput?
    let errors: DashboardValidationErrors
}

enum DashboardDecimalParser {
    static func parse(_ rawValue: String, locale: Locale = .current) -> Decimal? {
        var normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        if let localeSeparator = locale.decimalSeparator, localeSeparator != "." {
            normalized = normalized.replacingOccurrences(of: localeSeparator, with: ".")
        }
        normalized = normalized.replacingOccurrences(of: ",", with: ".")

        var unsignedValue = normalized[...]
        if unsignedValue.first == "-" {
            unsignedValue.removeFirst()
        }

        guard !unsignedValue.isEmpty else {
            return nil
        }

        let components = unsignedValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count <= 2,
              components.contains(where: { !$0.isEmpty }),
              components.allSatisfy({ component in
                  component.allSatisfy { character in
                      guard let asciiValue = character.asciiValue else {
                          return false
                      }
                      return (48...57).contains(asciiValue)
                  }
              })
        else {
            return nil
        }

        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

extension DashboardFeature.State {
    func makeValidatedDraft(locale: Locale = .current) -> DashboardValidationOutcome {
        var errors = DashboardValidationErrors()
        var positions: [AssetPosition] = []
        var firstRowBySymbol: [AssetSymbol: UUID] = [:]

        for draft in assetPositions {
            var rowErrors = AssetPositionDraftErrors()
            let symbol: AssetSymbol?
            let amount: Decimal?

            do {
                symbol = try AssetSymbol(draft.symbol)
            } catch DomainValidationError.emptyAssetSymbol {
                symbol = nil
                rowErrors.symbol = "Asset symbol is required."
            } catch {
                symbol = nil
                rowErrors.symbol = "Use 1–20 letters, numbers, '.', '_' or '-'."
            }

            if let parsedAmount = DashboardDecimalParser.parse(draft.amount, locale: locale) {
                amount = parsedAmount
            } else {
                amount = nil
                rowErrors.amount = "Enter a valid amount."
            }

            if let symbol, let amount {
                do {
                    let position = try AssetPosition(symbol: symbol, amount: amount)

                    if let firstRowID = firstRowBySymbol[symbol] {
                        let duplicateMessage = "Duplicate asset symbol."
                        errors.assetPositions[
                            firstRowID,
                            default: AssetPositionDraftErrors()
                        ].symbol = duplicateMessage
                        rowErrors.symbol = duplicateMessage
                    } else {
                        firstRowBySymbol[symbol] = draft.id
                        positions.append(position)
                    }
                } catch DomainValidationError.negativeAssetAmount {
                    rowErrors.amount = "Amount must be zero or greater."
                } catch {
                    errors.form = "The portfolio contains invalid values."
                }
            }

            if !rowErrors.isEmpty {
                errors.assetPositions[draft.id] = rowErrors
            }
        }

        let portfolio: Portfolio?
        if errors.assetPositions.isEmpty {
            do {
                portfolio = try Portfolio(positions: positions)
            } catch {
                portfolio = nil
                errors.form = "The portfolio contains duplicate assets."
            }
        } else {
            portfolio = nil
        }

        let monthlyIncome = DashboardDecimalParser.parse(
            constraints.additionalMonthlyIncomeUSD,
            locale: locale
        )
        let stableReserve = DashboardDecimalParser.parse(
            constraints.minimumStableReserveUSD,
            locale: locale
        )

        if monthlyIncome == nil {
            errors.constraints.additionalMonthlyIncomeUSD = "Enter a valid monthly income."
        }
        if stableReserve == nil {
            errors.constraints.minimumStableReserveUSD = "Enter a valid stable reserve."
        }

        var validatedConstraints: TradingConstraints?
        if let monthlyIncome, let stableReserve {
            do {
                validatedConstraints = try TradingConstraints(
                    tradingStyle: constraints.tradingStyle,
                    riskTolerance: constraints.riskTolerance,
                    leverageAllowed: constraints.leverageAllowed,
                    additionalMonthlyIncomeUSD: monthlyIncome,
                    minimumStableReserveUSD: stableReserve
                )
            } catch DomainValidationError.negativeAdditionalMonthlyIncomeUSD {
                errors.constraints.additionalMonthlyIncomeUSD =
                    "Monthly income must be zero or greater."
            } catch DomainValidationError.negativeMinimumStableReserveUSD {
                errors.constraints.minimumStableReserveUSD =
                    "Stable reserve must be zero or greater."
            } catch {
                errors.form = "The trading constraints contain invalid values."
            }
        }

        var validatedOrders: [LimitOrder] = []
        for draft in limitOrders {
            var rowErrors = LimitOrderDraftErrors()
            let symbol: AssetSymbol?
            let amountUSD: Decimal?
            let targetPrice: Decimal?

            do {
                symbol = try AssetSymbol(draft.symbol)
            } catch DomainValidationError.emptyAssetSymbol {
                symbol = nil
                rowErrors.symbol = "Asset symbol is required."
            } catch {
                symbol = nil
                rowErrors.symbol = "Use 1–20 letters, numbers, '.', '_' or '-'."
            }

            if let parsedAmount = DashboardDecimalParser.parse(draft.amountUSD, locale: locale) {
                amountUSD = parsedAmount
            } else {
                amountUSD = nil
                rowErrors.amountUSD = "Enter a valid order amount."
            }

            if let parsedPrice = DashboardDecimalParser.parse(draft.targetPrice, locale: locale) {
                targetPrice = parsedPrice
            } else {
                targetPrice = nil
                rowErrors.targetPrice = "Enter a valid target price."
            }

            if let symbol, let amountUSD, let targetPrice {
                do {
                    validatedOrders.append(
                        try LimitOrder(
                            id: draft.id,
                            symbol: symbol,
                            side: draft.side,
                            amountUSD: amountUSD,
                            targetPrice: targetPrice,
                            status: draft.status,
                            createdAt: draft.createdAt,
                            resolvedAt: draft.status == .open ? nil : draft.resolvedAt
                        )
                    )
                } catch DomainValidationError.nonPositiveOrderAmountUSD {
                    rowErrors.amountUSD = "Order amount must be greater than zero."
                } catch DomainValidationError.nonPositiveOrderTargetPrice {
                    rowErrors.targetPrice = "Target price must be greater than zero."
                } catch {
                    errors.form = "A limit order contains invalid values."
                }
            }

            if !rowErrors.isEmpty {
                errors.limitOrders[draft.id] = rowErrors
            }
        }

        guard !errors.hasErrors,
              let portfolio,
              let validatedConstraints,
              validatedOrders.count == limitOrders.count
        else {
            return DashboardValidationOutcome(validatedInput: nil, errors: errors)
        }

        return DashboardValidationOutcome(
            validatedInput: ValidatedDashboardInput(
                portfolio: portfolio,
                constraints: validatedConstraints,
                limitOrders: validatedOrders
            ),
            errors: errors
        )
    }
}
