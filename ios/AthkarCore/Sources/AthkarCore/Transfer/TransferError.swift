import Foundation

/// Why a transfer code was refused (spec/transfer/transfer-v1.md §7). `kind` is the spec's error string. The PWA's
/// `unsupported` (a browser without CompressionStream) has no native counterpart: decoding here always works.
public struct TransferError: Error, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case notCode = "not-code"
        case tooLong = "too-long"
        case oneFrame = "one-frame"
        case incomplete
        case mixed
        case wrongApp = "wrong-app"
        case newer
        case corrupt
        case fileRead = "file-read"
        case clock
        case tooBig = "too-big"
        case write
        case changed
    }

    public var kind: Kind
    /// `corrupt`: `checksum`, `base45`, `inflate`, `inflate-cap`, `json` or `invalid`; `newer`: `version` or `format`;
    /// `wrong-app`: `app` when the code's JSON says so.
    public var reason: String?
    /// `invalid` (and the JSON-level `newer`/`wrong-app`): the JSON path, `/`-separated as the PWA writes it.
    public var path: String?

    public init(_ kind: Kind, reason: String? = nil, path: String? = nil) {
        self.kind = kind
        self.reason = reason
        self.path = path
    }

    static func corrupt(_ reason: String, path: String? = nil) -> TransferError {
        TransferError(.corrupt, reason: reason, path: path)
    }

    static func invalid(_ path: String) -> TransferError {
        TransferError(.corrupt, reason: "invalid", path: path)
    }
}
