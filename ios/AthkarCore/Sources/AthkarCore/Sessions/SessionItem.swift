/// The fields of an adhkar item that the session rules read (`id`, `count`, `targetOptions`,
/// `defaultTarget`, `review` in `index.html`). Text and sources are irrelevant to the rules.
public struct SessionItem: Codable, Sendable, Hashable {
    public var id: String
    /// Fixed repetition count. Absent (or 0) means 1, as `item.count || 1`.
    public var count: Int?
    /// Targets the user may choose between. When present, `defaultTarget` must be one of them
    /// (`tools/content-validate.mjs` enforces this for shipped content).
    public var targetOptions: [Int]?
    public var defaultTarget: Int?
    /// Review items are shown but never counted towards completion.
    public var review: Bool

    public init(id: String, count: Int? = nil, targetOptions: [Int]? = nil, defaultTarget: Int? = nil, review: Bool = false) {
        self.id = id
        self.count = count
        self.targetOptions = targetOptions
        self.defaultTarget = defaultTarget
        self.review = review
    }

    private enum CodingKeys: String, CodingKey {
        case id, count, targetOptions, defaultTarget, review
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        targetOptions = try container.decodeIfPresent([Int].self, forKey: .targetOptions)
        defaultTarget = try container.decodeIfPresent(Int.self, forKey: .defaultTarget)
        review = try container.decodeIfPresent(Bool.self, forKey: .review) ?? false
    }

    /// Omits absent fields and `review: false`, matching the content's own shape.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(count, forKey: .count)
        try container.encodeIfPresent(targetOptions, forKey: .targetOptions)
        try container.encodeIfPresent(defaultTarget, forKey: .defaultTarget)
        if review { try container.encode(true, forKey: .review) }
    }
}
