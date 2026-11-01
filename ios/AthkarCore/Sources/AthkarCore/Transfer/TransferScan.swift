import Foundation

/// The PWA's `handleTransferScanText`: QR texts read by the camera, one at a time, collected into the frames of one
/// code. Other QR codes are ignored; a code that changes on the other device starts over; a frame that can never be
/// read here (another app, a newer version, a damaged frame) ends the scan.
public struct TransferScan: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Not a transfer frame (another QR code), or a frame already read: keep scanning.
        case ignored(foreign: Bool)
        /// A new frame: `read` of `count` frames, `restarted` when the code changed and reading began again.
        case progress(read: Int, count: Int, restarted: Bool)
        /// Every frame is read, or scanning cannot go on: the decoded container or the error.
        case finished(Result<TransferContainer, TransferError>)
    }

    private var msg: String?
    private var frames: [Int: String] = [:]
    public private(set) var count = 0

    public init() {}

    public var read: Int { frames.count }

    public mutating func scan(_ text: String) -> Outcome {
        // Longer than any whole code: never parsed or kept.
        guard text.utf16.count <= TransferCodec.maxTextLength else { return .ignored(foreign: true) }
        let clean = TransferCodec.trim(text)
        guard clean.hasPrefix("AQ") else { return .ignored(foreign: true) }
        let frame: TransferCodec.Frame
        switch TransferCodec.parseFrame(clean) {
        case let .success(parsed):
            frame = parsed
        case let .failure(error) where [.wrongApp, .newer, .corrupt].contains(error.kind):
            return .finished(.failure(error))
        case .failure:
            return .ignored(foreign: true)
        }
        var restarted = false
        if let msg, frame.msg != msg || frame.count != count {
            frames = [:]
            restarted = true
        }
        msg = frame.msg
        count = frame.count
        guard frames[frame.index] == nil else { return .ignored(foreign: false) }
        // Frames are kept only within the code limit (the parser keeps n ≤ 64; the text total is checked here).
        let kept = frames.values.reduce(0) { $0 + $1.utf16.count }
        guard kept + clean.utf16.count <= TransferCodec.maxTextLength else {
            return .finished(.failure(TransferError(.corrupt)))
        }
        frames[frame.index] = clean
        guard frames.count == count else { return .progress(read: frames.count, count: count, restarted: restarted) }
        return .finished(TransferCodec.decode(frames: frames.keys.sorted().compactMap { frames[$0] }))
    }
}
