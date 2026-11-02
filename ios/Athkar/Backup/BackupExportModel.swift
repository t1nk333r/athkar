import AthkarCore
import Foundation
import Observation

/// «تصدير نسخة احتياطية» (spec/backup/envelope-v2.md): the format 2 file of everything on this device, written to a
/// temporary file for the share sheet. Plaintext; the location is left out unless «تضمين الموقع» is switched on for this
/// export, and the switch starts off every time the screen opens.
@MainActor
@Observable
final class BackupExportModel: Identifiable {
    /// A written file, ready to share.
    struct File: Identifiable, Equatable {
        let url: URL
        var id: URL { url }
    }

    /// «تضمين الموقع».
    var includesLocation = false
    /// The file written for the share sheet, cleared when the sheet closes.
    var file: File?
    private(set) var error: String?

    @ObservationIgnored private let exporter: BackupExporter
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let directory: URL

    /// `directory` holds the exported file and nothing else; it is emptied before each export.
    init(exporter: BackupExporter, now: @escaping () -> Date, timeZone: TimeZone = .current,
         directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("BackupExport",
                                                                                      isDirectory: true)) {
        self.exporter = exporter
        self.now = now
        self.timeZone = timeZone
        self.directory = directory
    }

    /// `athkar-backup-YYYY-MM-DD.athkarbackup`, after the device's local date.
    static func fileName(at date: Date, in timeZone: TimeZone) -> String {
        "athkar-backup-\(SessionCalendar.localDate(of: date, in: timeZone)).athkarbackup"
    }

    /// «تصدير ومشاركة»: writes the file and offers it to the share sheet. Returns whether it was written; a failure
    /// is explained on the screen.
    @discardableResult
    func export() -> Bool {
        error = nil
        let date = now()
        do {
            let backup = try exporter.exportNative(timeZone: timeZone.identifier, exportedAt: date,
                                                   includeLocation: includesLocation)
            let data = try backup.encoded()
            clear()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(Self.fileName(at: date, in: timeZone))
            try data.write(to: url, options: .atomic)
            file = File(url: url)
            return true
        } catch {
            self.error = "تعذّر إنشاء النسخة الاحتياطية، ولم يتغيّر شيء على هذا الجهاز. (\(error.localizedDescription))"
            return false
        }
    }

    /// The share sheet closed, or the screen: the temporary file is removed.
    func clear() {
        file = nil
        try? FileManager.default.removeItem(at: directory)
    }
}
