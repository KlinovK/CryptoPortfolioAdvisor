import Foundation

// Editable text only: wire decoding remains locale-independent and strict.
enum ATAEditableDecimalText {
    static func normalized(
        _ text: String, decimalSeparator: String = Locale.current.decimalSeparator ?? "."
    ) -> String {
        decimalSeparator == "," ? text.replacingOccurrences(of: ",", with: ".") : text
    }
}

// Text and row UUIDs exist only in transient UI state; account identity is the server UUID.
struct ATAHoldingDraft: Equatable, Identifiable, Sendable {
    let id: UUID
    var symbol: String
    var amount: String
}

struct ATAAccountEditor: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case create
        case rename(UUID)
        case holdings(UUID)
    }

    enum InputError: Equatable, Sendable {
        case name
        case symbol
        case amount
        case duplicateSymbol
        case accountMissing
    }

    let kind: Kind
    var name: String = ""
    var accountType: ATAAccountType = .manual
    var holdings: [ATAHoldingDraft] = []
    var inputError: InputError?
    var needsReview = false

    func validatedPositions() throws -> [ATAPosition] {
        var positions: [ATAPosition] = []
        var symbols: Set<AssetSymbol> = []
        for draft in holdings {
            let symbol: AssetSymbol
            do { symbol = try AssetSymbol(draft.symbol) } catch { throw InputError.symbol }
            let amount: Decimal
            do { amount = try ATADecimalCodec.decode(draft.amount) } catch {
                throw InputError.amount
            }
            guard amount >= 0 else { throw InputError.amount }
            // A zero row is omitted from the complete replacement, never transmitted.
            if amount == 0 { continue }
            guard symbols.insert(symbol).inserted else { throw InputError.duplicateSymbol }
            do { positions.append(try ATAPosition(symbol: symbol, amount: amount)) } catch {
                throw InputError.amount
            }
        }
        return positions
    }
}

extension ATAAccountEditor.InputError: Error {}
