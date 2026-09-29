import Foundation

// Drafts are presentation state only. The server's CurrentPortfolio remains authoritative.
struct ATAOrderEditor: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case create
        case externalFill(UUID)
    }

    enum InputError: Error, Equatable, Sendable {
        case accountMissing
        case orderNotOpen
        case unsupportedAsset
        case targetPrice
        case quantity
        case settlementAsset
        case holdings(ATAAccountEditor.InputError)
    }

    static let supportedAssets: [AssetSymbol] = [.btc, .eth, .sol, .usdt, .usdc]

    let kind: Kind
    var accountID: UUID?
    var asset: AssetSymbol = .btc
    var side: ATAOrderSide = .buy
    var targetPrice = ""
    var quantityAsset = ""
    var settlementAsset: AssetSymbol?
    var holdings: [ATAHoldingDraft] = []
    var inputError: InputError?
    var needsReview = false

    func validatedCreateRequest(portfolio: ATACurrentPortfolio) throws -> ATACreateOrderRequestDTO {
        guard let accountID,
            portfolio.accounts.contains(where: { $0.id == accountID })
        else { throw InputError.accountMissing }
        guard Self.supportedAssets.contains(asset) else { throw InputError.unsupportedAsset }
        let price: Decimal
        do { price = try ATADecimalCodec.decode(targetPrice) } catch {
            throw InputError.targetPrice
        }
        guard price > 0 else { throw InputError.targetPrice }
        let quantity: Decimal
        do { quantity = try ATADecimalCodec.decode(quantityAsset) } catch {
            throw InputError.quantity
        }
        guard quantity > 0 else { throw InputError.quantity }
        return try ATACreateOrderRequestDTO(
            expectedRevision: portfolio.revision, accountID: accountID, asset: asset, side: side,
            targetPrice: price, quantityAsset: quantity)
    }

    func validatedFillRequest(portfolio: ATACurrentPortfolio) throws
        -> ATAConfirmOrderFilledRequestDTO
    {
        guard case .externalFill(let id) = kind,
            let order = portfolio.limitOrders.first(where: { $0.id == id }),
            order.status == .open
        else { throw InputError.orderNotOpen }
        guard order.accountID == accountID,
            portfolio.accounts.contains(where: { $0.id == order.accountID })
        else { throw InputError.accountMissing }
        guard let settlementAsset, settlementAsset == .usdt || settlementAsset == .usdc else {
            throw InputError.settlementAsset
        }
        let positions: [ATAPosition]
        do {
            positions = try ATAAccountEditor(kind: .holdings(order.accountID), holdings: holdings)
                .validatedPositions()
        } catch let error as ATAAccountEditor.InputError {
            throw InputError.holdings(error)
        }
        return try ATAConfirmOrderFilledRequestDTO(
            expectedRevision: portfolio.revision, settlementAsset: settlementAsset,
            positions: positions)
    }
}

struct ATAOrderLifecycleDraft: Equatable, Sendable {
    enum Operation: Equatable, Sendable { case cancel, expire }
    let orderID: UUID
    let operation: Operation
    var needsReview = false
    var confirmationPresented = true
}
