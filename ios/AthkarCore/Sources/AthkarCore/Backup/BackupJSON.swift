import Foundation

/// Reading and writing backup files of every format: one UTF-8 JSON document, instants in `toISOString()` form.
enum BackupJSON {
    /// The parsed document, the same document re-encoded as plain JSON for `Codable`, and its `meta.format`.
    ///
    /// The file must be one UTF-8 JSON document; a leading UTF-8 BOM is ignored. The text is read by
    /// `StoredValue(parsingJSON:)`, JavaScript's `JSON.parse` grammar, rather than by `JSONDecoder` directly:
    /// duplicate keys keep the last value, numbers below the `Double` range read as 0, and a lone surrogate
    /// escape reads as U+FFFD (still a string, as in JavaScript). `JSONDecoder` would keep the first duplicate
    /// and reject the other two. The format is read before the shape, so a future format reports as such rather
    /// than as malformed.
    static func parse(_ data: Data) throws -> (root: SessionState.StoredValue, json: Data, format: Int) {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let bytes = data.starts(with: bom) ? data.dropFirst(bom.count) : data[...]
        let text = String(decoding: bytes, as: UTF8.self)
        // Decoding replaces invalid sequences with U+FFFD, so the bytes change exactly when they are not UTF-8.
        guard text.utf8.elementsEqual(bytes) else { throw BackupError.malformed("not UTF-8") }
        let root: SessionState.StoredValue
        do {
            root = try SessionState.StoredValue(parsingJSON: text)
        } catch {
            throw BackupError.malformed(error.description)
        }
        let json: Data
        do {
            json = try JSONEncoder().encode(root)
        } catch {
            throw BackupError.malformed(describe(error))
        }
        struct Probe: Decodable {
            struct Meta: Decodable { var format: Int }
            var meta: Meta
        }
        do {
            return (root, json, try decoder.decode(Probe.self, from: json).meta.format)
        } catch {
            throw BackupError.malformed(describe(error))
        }
    }

    /// Instants read only in the ISO-8601 UTC form.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ISOInstant.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "\(text) is not an ISO-8601 UTC instant")
            }
            return date
        }
        return decoder
    }

    /// Pretty-printed JSON with sorted keys and instants in `toISOString()` form.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISOInstant.format(date))
        }
        return encoder
    }

    static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return String(describing: error) }
        let (context, summary): (DecodingError.Context, String) = switch error {
        case let .typeMismatch(type, context): (context, "expected \(type)")
        case let .valueNotFound(type, context): (context, "missing \(type) value")
        case let .keyNotFound(key, context): (context, "missing key \(key.stringValue)")
        case let .dataCorrupted(context): (context, context.debugDescription)
        @unknown default: (DecodingError.Context(codingPath: [], debugDescription: ""), "\(error)")
        }
        let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        return path.isEmpty ? summary : "\(path): \(summary)"
    }
}

/// A backup file of either format: a PWA's envelope (format 1) or the native app's own export (format 2).
public enum BackupFile: Equatable, Sendable {
    case pwa(BackupEnvelope)
    case native(NativeBackup)

    /// Decodes and validates a file of either format. A later format is ``BackupError/unsupportedFormat(_:)``.
    public static func decode(_ data: Data) throws -> BackupFile {
        let (_, _, format) = try BackupJSON.parse(data)
        switch format {
        case BackupEnvelope.format: return .pwa(try BackupEnvelope.decode(data))
        case NativeBackup.format: return .native(try NativeBackup.decode(data))
        default: throw BackupError.unsupportedFormat(format)
        }
    }
}
