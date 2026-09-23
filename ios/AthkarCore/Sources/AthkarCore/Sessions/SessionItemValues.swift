extension SessionState {
    /// One period's `progress` or `targets` container, in the shape it was stored.
    ///
    /// The PWA writes an object keyed by item id. `normalizeState` keeps any value that passes
    /// `value && typeof value === "object"`, so a stored JSON array stays an array. It is kept as one, and
    /// re-encoding writes what the PWA's `saveState` writes.
    public enum ItemValues: Sendable, Hashable {
        case object([String: StoredValue])
        case array([StoredValue])

        /// `container[key]` in JavaScript. For an object, this is the own member. For an array, it is the
        /// element at a canonical index (`"0"` is the first element, `"01"` is nothing) or `length`. Anything
        /// else is `nil` (`undefined`); so `"morning-01"` on an array is `nil`.
        ///
        /// Setting on an object stores the member, and `nil` removes it. Setting on an array only takes
        /// effect at an index: the array grows with `null` up to that index, and `nil` leaves `null` there.
        /// Those are the values `saveState` writes for JavaScript's holes and `delete`. Other keys are
        /// ignored on an array, because `saveState` drops them.
        public subscript(key: String) -> StoredValue? {
            get {
                switch self {
                case .object(let members): members[key]
                case .array(let elements): StoredValue.arrayProperty(elements, key)
                }
            }
            set {
                switch self {
                case .object(var members):
                    self = .object([:])  // Release the old storage so the update below stays in place.
                    members[key] = newValue
                    self = .object(members)
                case .array(var elements):
                    guard let index = StoredValue.arrayIndex(key) else { return }
                    self = .array([])
                    if index >= elements.count {
                        elements.append(contentsOf: repeatElement(.null, count: index - elements.count + 1))
                    }
                    elements[index] = newValue ?? .null
                    self = .array(elements)
                }
            }
        }

        /// The container `normalizeState` keeps for `value`: objects and arrays as they are, and nothing for
        /// any other value, which the PWA replaces with `{}`.
        init?(_ value: StoredValue) {
            switch value {
            case .object(let members): self = .object(members)
            case .array(let elements): self = .array(elements)
            default: return nil
            }
        }
    }
}

extension SessionState.ItemValues: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, SessionState.StoredValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}

extension SessionState.ItemValues: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let members = try? container.decode([String: SessionState.StoredValue].self) {
            self = .object(members)
        } else {
            self = .array(try container.decode([SessionState.StoredValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let members): try container.encode(members)
        case .array(let elements): try container.encode(elements)
        }
    }
}
