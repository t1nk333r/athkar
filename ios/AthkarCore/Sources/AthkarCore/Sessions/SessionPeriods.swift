/// One value per adhkar period, encoded as the PWA's `{ "morning": …, "evening": … }` pair.
public struct SessionPeriods<Value> {
    public var morning: Value
    public var evening: Value

    public init(morning: Value, evening: Value) {
        self.morning = morning
        self.evening = evening
    }

    public subscript(period: Period) -> Value {
        get {
            switch period {
            case .morning: morning
            case .evening: evening
            }
        }
        set {
            switch period {
            case .morning: morning = newValue
            case .evening: evening = newValue
            }
        }
    }
}

extension SessionPeriods: Sendable where Value: Sendable {}
extension SessionPeriods: Equatable where Value: Equatable {}
extension SessionPeriods: Hashable where Value: Hashable {}

private enum SessionPeriodsCodingKeys: String, CodingKey {
    case morning, evening
}

extension SessionPeriods: Decodable where Value: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SessionPeriodsCodingKeys.self)
        morning = try container.decode(Value.self, forKey: .morning)
        evening = try container.decode(Value.self, forKey: .evening)
    }
}

extension SessionPeriods: Encodable where Value: Encodable {
    /// Optional values are written as explicit `null`, as `JSON.stringify` does for the PWA state.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SessionPeriodsCodingKeys.self)
        try container.encode(morning, forKey: .morning)
        try container.encode(evening, forKey: .evening)
    }
}

/// The adhkar items of both periods, in content order (`collections` in `index.html`).
public typealias SessionCollections = SessionPeriods<[SessionItem]>
