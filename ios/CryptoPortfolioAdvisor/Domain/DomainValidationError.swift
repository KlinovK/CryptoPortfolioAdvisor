enum DomainValidationError: Error, Equatable, Sendable {
    case emptyAssetSymbol
    case negativeAssetAmount
    case duplicateAssetSymbol(AssetSymbol)
    case negativeAdditionalMonthlyIncomeUSD
    case negativeMinimumStableReserveUSD
    case nonPositiveOrderAmountUSD
    case nonPositiveOrderTargetPrice
    case openOrderCannotHaveResolvedAt
}
