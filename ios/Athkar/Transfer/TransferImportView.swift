import AthkarCore
import SwiftUI
import UniformTypeIdentifiers

/// «استيراد من تطبيق الويب»: the athkar PWA's «استلام التقدّم» dialog as a sheet — paste, file or camera, then the
/// review, then the result (``TransferImportModel``).
struct TransferImportView: View {
    let model: TransferImportModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var choosesFile = false
    @State private var cameraProblem: QRScannerProblem?

    /// What «اختيار ملف» offers: a code saved as text, or an athkar backup.
    static let fileTypes: [UTType] = [.plainText, .json, UTType("local.dev.athkar.backup") ?? .data]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch model.screen {
                    case .receive: receive
                    case .scan: scan
                    case .review: review
                    case .result: result
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                        .accessibilityIdentifier("transfer.close")
                        .disabled(model.isWriting)
                }
            }
        }
        .tint(palette.accentStrong)
        .interactiveDismissDisabled(model.isWriting)
        .fileImporter(isPresented: $choosesFile, allowedContentTypes: Self.fileTypes) { picked in
            // Cancelling the picker reports no URL and changes nothing, as in the PWA.
            guard case let .success(url) = picked else {
                if case let .failure(error) = picked, (error as? CocoaError)?.code != .userCancelled {
                    model.importFile(nil)
                }
                return
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            model.importFile(TransferImportModel.read(url))
        }
        .onChange(of: model.screen) { _, screen in
            if screen != .scan { cameraProblem = nil }
            announce(screen)
        }
    }

    private var title: String {
        switch model.screen {
        case .receive: "استلام التقدّم"
        case .scan: "مسح رمز QR"
        case .review: "المراجعة"
        case .result: model.outcome?.succeeded == true ? "تمّ النقل" : "تعذّر النقل"
        }
    }

    // MARK: Receive

    private var receive: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("على الجهاز الآخر افتح تطبيق الويب «أذكار المسلم»، واذهب إلى الإعدادات ← «إرسال التقدّم»، ثم اختر الطريقة المتاحة هنا.")
                .font(.body)
                .foregroundStyle(palette.textPrimary)

            section("لصق الرمز") {
                Text("الصق رمز النقل هنا")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
                TextEditor(text: Binding(get: { model.code }, set: { model.code = $0 }))
                    .font(.system(.footnote, design: .monospaced))
                    .environment(\.layoutDirection, .leftToRight)
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 110)
                    .background(Corner.box.fill(palette.surfaceRaised))
                    .overlay(Corner.box.strokeBorder(model.pasteError == nil ? palette.border : palette.warning))
                    .accessibilityLabel("الصق رمز النقل هنا")
                    .accessibilityIdentifier("transfer.code")
                if let error = model.pasteError {
                    problem(error).accessibilityIdentifier("transfer.code.error")
                }
                HStack(spacing: 10) {
                    Button("لصق") {
                        if let text = UIPasteboard.general.string, !text.isEmpty {
                            model.code = text
                            model.continuePaste()
                        } else {
                            model.pasteUnavailable()
                        }
                    }
                    .buttonStyle(DialogButtonStyle(palette: palette))
                    .accessibilityIdentifier("transfer.paste")
                    Button("متابعة") { model.continuePaste() }
                        .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
                        .disabled(!model.canContinue)
                        .opacity(model.canContinue ? 1 : 0.5)
                        .accessibilityIdentifier("transfer.continue")
                }
            }

            section("ملف") {
                Button("اختيار ملف") { choosesFile = true }
                    .buttonStyle(DialogButtonStyle(palette: palette))
                    .accessibilityIdentifier("transfer.file")
                if let error = model.fileError {
                    problem(error).accessibilityIdentifier("transfer.file.error")
                }
                note("ملف رمز النقل (‎.txt) أو نسخة احتياطية (‎.athkarbackup).")
            }

            section("الكاميرا") {
                if QRScanner.isAvailable {
                    Button("مسح رمز QR") { model.startScan() }
                        .buttonStyle(DialogButtonStyle(palette: palette))
                        .accessibilityIdentifier("transfer.scan")
                    note("تُستخدم الكاميرا لقراءة الرمز فقط على هذا الجهاز؛ لا تُحفظ الصور ولا تُرسل.")
                } else {
                    note("لا تتوفر كاميرا على هذا الجهاز. الصق الرمز أو اختر ملفًا.")
                }
            }
        }
    }

    // MARK: Scan

    private var scan: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("وجّه الكاميرا إلى رمز QR الظاهر على الجهاز الآخر.")
                .foregroundStyle(palette.textPrimary)
            if let cameraProblem {
                problem(cameraProblem.message)
                Button("لصق الرمز أو اختيار ملف") { model.stopScan() }
                    .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
            } else {
                QRScanner(onCode: { model.scanned($0) }, onProblem: { cameraProblem = $0 })
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(Corner.box)
                    .overlay(Corner.box.strokeBorder(palette.border))
                    .accessibilityHidden(true)
                if model.scanCount > 0 { progress }
                Text(model.scanLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityIdentifier("transfer.scan.label")
                if let hint = model.scanHint { note(hint) }
                Button("إيقاف المسح") { model.stopScan() }
                    .buttonStyle(DialogButtonStyle(palette: palette))
                    .accessibilityIdentifier("transfer.scan.stop")
            }
        }
        // Nothing new for 15 s (8 s once a frame is read): the hint asks for brightness and distance.
        .task(id: model.scanRead) {
            try? await Task.sleep(for: .seconds(model.scanRead == 0 ? 15 : 8))
            if !Task.isCancelled { model.scanStalled() }
        }
    }

    private var progress: some View {
        HStack(spacing: 3) {
            ForEach(0..<model.scanCount, id: \.self) { index in
                Capsule()
                    .fill(index < model.scanRead ? palette.accent : palette.border)
                    .frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(model.scanLabel)
    }

    // MARK: Review

    @ViewBuilder private var review: some View {
        if let preview = model.preview {
            VStack(alignment: .leading, spacing: 14) {
                if model.refreshed { warning(TransferImportModel.refreshedNote) }
                Text(preview.lead)
                    .font(preview.isEmpty ? .title3.weight(.bold) : .headline)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let created = preview.created { note(created) }
                if preview.isEmpty {
                    note(preview.assurance)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(preview.rows.enumerated()), id: \.offset) { _, row in rowView(row) }
                    }
                    if preview.hasResets {
                        warning(preview.assurance)
                    } else {
                        Text(preview.assurance)
                            .font(.subheadline)
                            .foregroundStyle(palette.completed)
                    }
                    note(TransferImportModel.undoNote)
                }
                ForEach(preview.warnings, id: \.self) { warning($0) }
                if preview.isEmpty {
                    Button(preview.confirmTitle) { dismiss() }
                        .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
                        .accessibilityIdentifier("transfer.done")
                } else {
                    HStack(spacing: 10) {
                        Button("إلغاء") { model.back() }
                            .buttonStyle(DialogButtonStyle(palette: palette))
                            .accessibilityIdentifier("transfer.cancel")
                        Button(model.isWriting ? "يُحفظ…" : preview.confirmTitle) { model.confirm() }
                            .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
                            .accessibilityIdentifier("transfer.confirm")
                    }
                    .disabled(model.isWriting)
                }
            }
        }
    }

    private func rowView(_ row: TransferImportModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.textPrimary)
            Text(row.detail)
                .font(.footnote)
                .foregroundStyle(row.isComplete ? palette.completed : palette.textSecondary)
            ForEach(row.dates, id: \.self) { date in
                Text("• \(date)")
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Corner.box.fill(row.isReset ? palette.warningSoft : palette.surfaceRaised))
        .overlay(Corner.box.strokeBorder(row.isReset ? palette.warning : palette.border))
        .accessibilityElement(children: .combine)
    }

    // MARK: Result

    @ViewBuilder private var result: some View {
        if let outcome = model.outcome {
            VStack(spacing: 14) {
                Text(outcome.succeeded ? "✓" : "!")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(outcome.succeeded ? palette.completed : palette.warning)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(outcome.succeeded ? palette.completedSoft : palette.warningSoft))
                    .accessibilityHidden(true)
                Text(outcome.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityIdentifier("transfer.result.title")
                Text(outcome.message)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                if outcome.succeeded {
                    Button("تم") { dismiss() }
                        .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
                        .accessibilityIdentifier("transfer.done")
                } else {
                    Button("المحاولة مرة أخرى") { model.back() }
                        .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
                        .accessibilityIdentifier("transfer.retry")
                    Button("إغلاق") { dismiss() }
                        .buttonStyle(DialogButtonStyle(palette: palette))
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Parts

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func problem(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warning(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(palette.textPrimary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Corner.box.fill(palette.warningSoft))
    }

    private func announce(_ screen: TransferImportModel.Screen) {
        let text: String? = switch screen {
        case .result: model.outcome.map { "\($0.title). \($0.message)" }
        case .review: model.preview?.lead
        case .receive, .scan: nil
        }
        if let text { AccessibilityNotification.Announcement(text).post() }
    }
}
