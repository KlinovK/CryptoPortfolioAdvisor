import ComposableArchitecture

@Reducer
struct AnalysisDetailsFeature {
    @ObservableState
    struct State: Equatable {
        let analysis: PortfolioAnalysis
    }

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

enum AnalysisDetailsPresentation {
    static func orderedActions(_ actions: [PortfolioAction]) -> [PortfolioAction] {
        actions.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.priority == rhs.element.priority {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.priority < rhs.element.priority
            }
            .map(\.element)
    }

    static func actionTitle(_ action: PortfolioAction) -> String {
        let type: String
        switch action.type {
        case .buy:
            type = "BUY"
        case .sell:
            type = "SELL"
        case .hold:
            type = "HOLD"
        case .wait:
            type = "WAIT"
        case .placeLimit:
            type = "PLACE LIMIT"
        case .keepLimit:
            type = "KEEP LIMIT"
        case .cancelLimit:
            type = "CANCEL LIMIT"
        case .rebalance:
            type = "REBALANCE"
        case .monitor:
            type = "MONITOR"
        }

        guard let asset = action.asset else {
            return type
        }
        return "\(type) · \(asset.rawValue)"
    }

    static func priorityTitle(_ priority: Int) -> String {
        switch priority {
        case ...2:
            "High priority"
        case 3:
            "Medium priority"
        default:
            "Low priority"
        }
    }

    static func orderedWarnings(_ warnings: [PortfolioWarning]) -> [PortfolioWarning] {
        var seen = Set<WarningKey>()
        return warnings.enumerated()
            .sorted { lhs, rhs in
                let leftRank = warningRank(lhs.element.severity)
                let rightRank = warningRank(rhs.element.severity)
                if leftRank == rightRank {
                    return lhs.offset < rhs.offset
                }
                return leftRank < rightRank
            }
            .filter { seen.insert(WarningKey(warning: $0.element)).inserted }
            .map(\.element)
    }

    static func warningTitle(_ severity: WarningSeverity) -> String {
        switch severity {
        case .critical:
            "Critical warning"
        case .warning:
            "Warning"
        case .info:
            "Information"
        }
    }

    static func warningSystemImage(_ severity: WarningSeverity) -> String {
        switch severity {
        case .critical:
            "exclamationmark.octagon.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .info:
            "info.circle.fill"
        }
    }

    private static func warningRank(_ severity: WarningSeverity) -> Int {
        switch severity {
        case .critical:
            0
        case .warning:
            1
        case .info:
            2
        }
    }

    private struct WarningKey: Hashable {
        let code: String
        let asset: String?

        init(warning: PortfolioWarning) {
            code = warning.code
            asset = warning.asset?.rawValue
        }
    }
}
