enum ATAAccountType: String, CaseIterable, Sendable {
    case binance = "binance"
    case externalWallet = "external_wallet"
    case otherExchange = "other_exchange"
    case manual = "manual"
}

enum ATAOrderSide: String, CaseIterable, Sendable {
    case buy = "buy"
    case sell = "sell"
}

enum ATAOrderStatus: String, CaseIterable, Sendable {
    case open = "open"
    case filled = "filled"
    case cancelled = "cancelled"
    case expired = "expired"
}

enum ATAAnalysisRunStatus: String, CaseIterable, Sendable {
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
}

enum ATADailyTrend: String, CaseIterable, Sendable {
    case bullish = "bullish"
    case bearish = "bearish"
    case mixed = "mixed"
    case incomplete = "incomplete"
}

enum ATADataCompleteness: String, CaseIterable, Sendable {
    case unavailable = "unavailable"
    case priceOnly = "price_only"
    case partial = "partial"
    case complete = "complete"
}

enum ATAActionType: String, CaseIterable, Sendable {
    case buy = "buy"
    case sell = "sell"
    case hold = "hold"
    case wait = "wait"
    case placeLimitOrder = "place_limit_order"
    case keepLimitOrder = "keep_limit_order"
    case cancelLimitOrder = "cancel_limit_order"
    case replaceLimitOrder = "replace_limit_order"
    case rebalance = "rebalance"
    case rebalanceInformational = "rebalance_informational"
}

enum ATASetupStatus: String, CaseIterable, Sendable {
    case candidate = "candidate"
    case approachingZone = "approaching_zone"
    case zoneTouched = "zone_touched"
    case awaitingConfirmation = "awaiting_confirmation"
    case confirmed = "confirmed"
    case active = "active"
    case filledOrConfirmedManually = "filled_or_confirmed_manually"
    case invalidated = "invalidated"
    case expired = "expired"
    case completed = "completed"
    case cancelled = "cancelled"
}

enum ATATriggerTimeframe: String, CaseIterable, Sendable {
    case oneHour = "1h"
    case fourHour = "4h"
    case manual = "manual"
}

enum ATATriggerReason: String, CaseIterable, Sendable {
    case approachedZone = "approached_deterministic_zone"
    case touchedZone = "closed_1h_range_touched_zone"
    case awaitingClosedConfirmation = "awaiting_subsequent_closed_1h_confirmation"
    case resistanceRejection = "closed_1h_resistance_rejection_confirmed"
    case supportHold = "closed_1h_support_hold_confirmed"
    case resistanceBreakout = "closed_4h_breakout_invalidated_rejection"
    case supportBreakdown = "closed_4h_breakdown_invalidated_support"
    case confirmationWindowExpired = "confirmation_window_expired"
    case executionWindowExpired = "execution_window_expired"
    case executionMovedTooFar = "execution_price_moved_too_far_from_trigger"
    case manualFillConfirmed = "order_fill_confirmed_manually"
    case manualCancellationConfirmed = "order_cancellation_confirmed_manually"
}

enum ATASetupType: String, CaseIterable, Sendable {
    case pullbackBuy = "pullback_buy"
    case profitTakingSell = "profit_taking_sell"
    case supportHold = "support_hold"
    case resistanceRejection = "resistance_rejection"
}

enum ATAAssetDecisionType: String, CaseIterable, Sendable {
    case add = "add"
    case hold = "hold"
    case wait = "wait"
    case partialSell = "partial_sell"
    case sell = "sell"
    case rebalanceInformational = "rebalance_informational"
}

enum ATAAnalysisSeverity: String, CaseIterable, Sendable {
    case quiet = "quiet"
    case update = "update"
    case action = "action"
}

enum ATAMarketRegime: String, CaseIterable, Sendable {
    case riskOn = "risk_on"
    case constructive = "constructive"
    case neutral = "neutral"
    case elevatedRisk = "elevated_risk"
    case riskOff = "risk_off"
}

enum ATAReasoningMode: String, CaseIterable, Sendable {
    case deterministic = "DETERMINISTIC"
    case aiAssisted = "AI_ASSISTED"
    case aiFallback = "AI_FALLBACK"
}
