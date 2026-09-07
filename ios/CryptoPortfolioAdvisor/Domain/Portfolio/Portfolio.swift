struct Portfolio: Equatable, Codable, Sendable {
    let positions: [AssetPosition]

    init(positions: [AssetPosition]) throws {
        var symbols = Set<AssetSymbol>()

        for position in positions {
            guard symbols.insert(position.symbol).inserted else {
                throw DomainValidationError.duplicateAssetSymbol(position.symbol)
            }
        }

        self.positions = positions
    }

    private enum CodingKeys: CodingKey {
        case positions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(positions: container.decode([AssetPosition].self, forKey: .positions))
    }
}
