import AthkarCore
import SwiftUI

/// The five prayers of one day, as on «اليوم» and in a calendar day: tapping an unrecorded prayer's circle records it
/// at once (with «تراجع» in the undo bar), and the row opens its details for anything else. A future day is read-only.
struct TrackerPrayerList: View {
    let tracker: PrayerTrackerModel
    let date: String
    /// The day's calculated times, if there is a location.
    let schedule: PrayerSchedule?

    @Environment(\.palette) private var palette
    @State private var details: PrayerOccurrence?

    var body: some View {
        let editable = tracker.isEditable(date)
        let records = tracker.records(on: date)
        VStack(spacing: 0) {
            ForEach(Array(ObligatoryPrayer.allCases.enumerated()), id: \.element) { index, prayer in
                if index > 0 { Divider().overlay(palette.border) }
                let occurrence = PrayerOccurrence(date: date, prayer: prayer)
                row(occurrence, entry: records[prayer]?.entry ?? .unrecorded, editable: editable)
            }
        }
        .clipShape(Corner.box)
        .card(palette)
        .sheet(item: $details) { occurrence in
            PrayerRecordSheet(tracker: tracker, occurrence: occurrence)
                .environment(\.palette, palette)
        }
    }

    private func row(_ occurrence: PrayerOccurrence, entry: PrayerEntry, editable: Bool) -> some View {
        let name = TrackerText.slot(occurrence, entry: entry)
        let time = schedule.flatMap { schedule in
            schedule.scheduledTime(of: occurrence.prayer).map { ArabicFormat.time($0, in: schedule.zone) }
        }
        return HStack(spacing: 10) {
            Button {
                details = occurrence
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.body.weight(.heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text(TrackerText.summary(entry))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(entry.state == .prayed ? palette.completed : palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if let time {
                        Text(time)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .accessibilityLabel([name, time].compactMap { $0 }.joined(separator: "، "))
            .accessibilityValue(TrackerText.summary(entry))
            .accessibilityHint(editable ? "يفتح التفاصيل" : "")
            .accessibilityIdentifier("tracker.row.\(occurrence.prayer.rawValue)")
            logButton(occurrence, entry: entry, editable: editable)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
    }

    /// The circle: empty for unrecorded (tap to record), a tick for prayed, a dash for not applicable (both open the
    /// details, where the record can be changed).
    private func logButton(_ occurrence: PrayerOccurrence, entry: PrayerEntry, editable: Bool) -> some View {
        Button {
            if entry.state == .unrecorded {
                tracker.quickLog(occurrence)
            } else {
                details = occurrence
            }
        } label: {
            Group {
                switch entry.state {
                case .unrecorded:
                    Image(systemName: "circle")
                        .foregroundStyle(palette.textSecondary)
                case .prayed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.completed)
                case .notApplicable:
                    Image(systemName: "minus.circle")
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .font(.title2)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .opacity(editable ? 1 : 0.5)
        .accessibilityLabel((entry.state == .unrecorded ? "تسجيل صلاة " : "تعديل صلاة ")
                            + TrackerText.slot(occurrence, entry: entry))
        .accessibilityIdentifier("tracker.log.\(occurrence.prayer.rawValue)")
    }
}

/// A prayer's details: its state, the optional timing the user chooses, and on a Friday which noon prayer the Dhuhr
/// slot records. Each choice is saved at once.
struct PrayerRecordSheet: View {
    let tracker: PrayerTrackerModel
    let occurrence: PrayerOccurrence

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let record = tracker.record(occurrence)
        let entry = record?.entry ?? .unrecorded
        NavigationStack {
            List {
                Section {
                    ForEach(PrayerRecordState.allCases, id: \.self) { state in
                        option(TrackerText.state(state), selected: entry.state == state,
                               identifier: "tracker.state.\(state.rawValue)") {
                            switch state {
                            case .unrecorded: change(.unrecord)
                            case .prayed: change(.record(noon: nil))
                            case .notApplicable: change(.markNotApplicable)
                            }
                        }
                    }
                } footer: {
                    Text("«لا تنطبق» لا تُحتسب ضمن صلوات اليوم.")
                }
                if occurrence.isFridayDhuhr {
                    Section {
                        ForEach(NoonPrayer.allCases, id: \.self) { noon in
                            option(TrackerText.noon(noon), selected: entry.state == .prayed && entry.noon == noon,
                                   identifier: "tracker.noon.\(noon.rawValue)") {
                                change(.record(noon: noon))
                            }
                        }
                    } header: {
                        Text("صلاة الظهر يوم الجمعة")
                    } footer: {
                        Text("اختر ما صلّيته في هذا الوقت: الجمعة أو الظهر.")
                    }
                }
                Section {
                    ForEach([nil] + PrayerTiming.allCases.map(Optional.some), id: \.self) { timing in
                        option(TrackerText.timing(timing), selected: entry.state == .prayed && entry.timing == timing,
                               identifier: "tracker.timing.\(timing?.rawValue ?? "none")") {
                            change(.setTiming(timing))
                        }
                        .disabled(entry.state != .prayed)
                    }
                } header: {
                    Text("وقت الأداء (اختياري)")
                } footer: {
                    Text(entry.state == .prayed ? "تختاره أنت، ولا يحدده التطبيق من الساعة."
                                                : "يُختار بعد تسجيل الصلاة.")
                }
                if let record, let loggedAt = record.loggedAt {
                    Section {
                        Text("سُجّلت: " + ArabicFormat.shortDate(loggedAt, in: tracker.zone) + "، "
                             + ArabicFormat.time(loggedAt, in: tracker.zone))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .accessibilityIdentifier("tracker.loggedAt")
                    }
                }
            }
            .navigationTitle(TrackerText.slot(occurrence, entry: entry))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                        .accessibilityIdentifier("tracker.sheet.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func option(_ title: String, selected: Bool, identifier: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(palette.accentStrong)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// A deliberate choice in the sheet: saved at once, without the quick log's undo bar.
    private func change(_ command: PrayerCommand) {
        tracker.apply(command, to: occurrence)
        tracker.dismissUndo()
    }
}

/// «تراجع» after a quick log, until it is used, dismissed, or a few seconds pass.
struct TrackerUndoBar: View {
    let tracker: PrayerTrackerModel

    @Environment(\.palette) private var palette

    /// How long the bar stays.
    static let duration: Duration = .seconds(8)

    var body: some View {
        if let change = tracker.lastChange {
            HStack(spacing: 10) {
                Text(TrackerText.change(change.occurrence, entry: change.entry))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .accessibilityIdentifier("tracker.undoMessage")
                Spacer(minLength: 8)
                Button("تراجع") { tracker.undo() }
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(palette.accentStrong)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("tracker.undo")
            }
            .padding(.horizontal, 14)
            .background(Corner.box.fill(palette.surfaceRaised))
            .overlay(Corner.box.strokeBorder(palette.border))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: change.id) {
                AccessibilityNotification.Announcement(TrackerText.change(change.occurrence, entry: change.entry))
                    .post()
                try? await Task.sleep(for: Self.duration)
                if tracker.lastChange?.id == change.id { tracker.dismissUndo() }
            }
        }
    }
}
