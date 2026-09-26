import AthkarCore
import SwiftUI

/// The أوقات الصلاة section of أخرى: the day's six times with the next prayer's countdown, the location that
/// produced them, and the calculation settings (NATIVE_APP_PLAN.md §7.3).
struct PrayerTimesView: View {
    let model: PrayerTimesModel

    @Environment(\.palette) private var palette
    @State private var showsSettings = false
    @State private var showsManualLocation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.location == nil {
                    noLocation
                } else {
                    dayNavigator
                    if model.dayOffset == 0 {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            countdown(now: context.date)
                        }
                    }
                    times
                    locationCard
                }
                Button {
                    showsSettings = true
                } label: {
                    Label("إعدادات الحساب", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("prayer.settings")
            }
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showsSettings) {
            PrayerSettingsView(model: model)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showsManualLocation) {
            ManualLocationView(location: model.location) { latitude, longitude in
                model.setManualLocation(latitude: latitude, longitude: longitude)
            }
            .environment(\.palette, palette)
        }
    }

    // MARK: No location

    private var noLocation: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.circle")
                .font(.largeTitle)
                .foregroundStyle(palette.accentStrong)
            Text("حدّد موقعك لعرض مواقيت الصلاة")
                .font(.headline.weight(.heavy))
                .foregroundStyle(palette.textPrimary)
            Text("يُطلب الموقع مرة واحدة، ويُحفظ على جهازك بدقة تقريبية (نحو كيلومتر) ولا يُرسل إلى أي جهة.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            locationButtons
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .card(palette)
    }

    private var locationButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await model.locate() }
                } label: {
                    HStack(spacing: 6) {
                        if model.isLocating { ProgressView() } else { Image(systemName: "location.fill") }
                        Text(model.location == nil ? "تحديد الموقع" : "تحديث الموقع")
                    }
                    .pill(palette, prominent: true)
                }
                .buttonStyle(.plain)
                .disabled(model.isLocating)
                .accessibilityIdentifier("prayer.locate")
                Button {
                    showsManualLocation = true
                } label: {
                    Text("إدخال يدوي").pill(palette, prominent: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("prayer.manual")
            }
            if let problem = model.locationProblem {
                Text(problem)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("prayer.locationProblem")
            }
        }
    }

    // MARK: Day

    private var dayNavigator: some View {
        let date = PrayerTimesModel.localDate(daysFromToday: model.dayOffset, now: Date(), in: model.zone)
        return HStack(spacing: 8) {
            dayButton("اليوم السابق", systemImage: "chevron.backward", offset: model.dayOffset - 1)
            VStack(spacing: 2) {
                Text(model.dayOffset == 0 ? "اليوم، " + PrayerDates.gregorian(date) : PrayerDates.gregorian(date))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityIdentifier("prayer.date")
                Text(PrayerDates.hijri(date, offset: model.settings.hijriOffset))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("prayer.hijri")
                if model.dayOffset != 0 {
                    Button("العودة إلى اليوم") { model.showDay(0) }
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(palette.accentStrong)
                        .accessibilityIdentifier("prayer.today")
                }
            }
            .frame(maxWidth: .infinity)
            dayButton("اليوم التالي", systemImage: "chevron.forward", offset: model.dayOffset + 1)
        }
        .padding(8)
        .card(palette)
    }

    private func dayButton(_ label: String, systemImage: String, offset: Int) -> some View {
        Button {
            model.showDay(offset)
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.textSecondary)
        .accessibilityLabel(label)
        .accessibilityIdentifier(offset > model.dayOffset ? "prayer.nextDay" : "prayer.previousDay")
    }

    // MARK: Countdown

    @ViewBuilder
    private func countdown(now: Date) -> some View {
        if let next = model.nextPrayer(now: now) {
            HStack {
                Text("الصلاة القادمة: \(PrayerNames.name(next.prayer))")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Text("بعد " + PrayerDates.remaining(from: now, to: next.at))
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(palette.accentStrong)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .card(palette)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("prayer.countdown")
        }
    }

    // MARK: Times

    private var times: some View {
        let schedule = model.shownSchedule
        let next = model.dayOffset == 0 ? model.nextPrayer() : nil
        return VStack(spacing: 0) {
            ForEach(Array(PrayerTime.allCases.enumerated()), id: \.element) { index, time in
                if index > 0 { Divider().overlay(palette.border) }
                let isNext = next?.prayer == time && next.map { SessionCalendar.localDate(of: $0.at, in: model.zone) }
                    == schedule?.localDate
                HStack {
                    Text(PrayerNames.name(time))
                        .font(.body.weight(isNext ? .heavy : .semibold))
                    Spacer(minLength: 8)
                    Text(value(time, in: schedule))
                        .font(.body.weight(isNext ? .heavy : .semibold).monospacedDigit())
                }
                .foregroundStyle(isNext ? palette.accentStrong : (time == .sunrise ? palette.textSecondary
                                                                                   : palette.textPrimary))
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(isNext ? palette.accentSoft.opacity(0.6) : .clear)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("prayer.time.\(time.rawValue)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14.4, style: .continuous))
        .card(palette)
    }

    private func value(_ time: PrayerTime, in schedule: PrayerSchedule?) -> String {
        guard let schedule else { return "—" }
        if time == .asr, schedule.asrClamped { return "غير محدد" }
        guard let instant = schedule[time] else { return "—" }
        return ArabicFormat.time(instant, in: schedule.zone)
    }

    // MARK: Location

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let location = model.location {
                Text("الموقع: \(PrayerDates.coordinates(location.latitude, location.longitude))"
                     + (location.source == .manual ? " (يدوي)" : ""))
                    .accessibilityIdentifier("prayer.location")
                if let updated = location.updatedAt {
                    Text("آخر تحديث: " + updated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
                                                                             locale: Locale(identifier: "ar-EG"))))
                }
                Text("المنطقة الزمنية: \(model.zone.identifier)")
                Text("طريقة الحساب: \(PrayerNames.method(model.settings.method))")
                    .accessibilityIdentifier("prayer.method")
            }
            locationButtons
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }
}

// MARK: - Settings

/// Method, Asr school, high-latitude rule, per-prayer minute adjustments and the Hijri offset.
struct PrayerSettingsView: View {
    let model: PrayerTimesModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("طريقة الحساب", selection: Binding(get: { model.settings.method }, set: model.setMethod)) {
                        ForEach(CalculationMethod.allCases, id: \.self) { method in
                            Text(PrayerNames.method(method)).tag(method)
                        }
                    }
                    .accessibilityIdentifier("prayer.settings.method")
                    Picker("مذهب العصر", selection: Binding(get: { model.settings.asrSchool }, set: model.setAsrSchool)) {
                        Text("الجمهور").tag(AsrSchool.standard)
                        Text("الحنفي").tag(AsrSchool.hanafi)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("prayer.settings.asrSchool")
                    Picker("خطوط العرض العالية",
                           selection: Binding(get: { model.settings.highLatitudeRule }, set: model.setHighLatitudeRule)) {
                        ForEach(HighLatitudeRule.allCases, id: \.self) { rule in
                            Text(PrayerNames.highLatitudeRule(rule)).tag(rule)
                        }
                    }
                } footer: {
                    Text("خطوط العرض العالية: كيف يُقدَّر الفجر والعشاء حيث لا يغيب الشفق.")
                }
                Section("تعديل الأوقات بالدقائق") {
                    ForEach(PrayerTime.allCases, id: \.self) { time in
                        Stepper(value: adjustment(time), in: -30...30) {
                            HStack {
                                Text(PrayerNames.name(time))
                                Spacer()
                                Text(Self.minutes(adjustment(time).wrappedValue))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("prayer.settings.adjust.\(time.rawValue)")
                    }
                }
                Section {
                    Stepper(value: Binding(get: { model.settings.hijriOffset }, set: model.setHijriOffset), in: -2...2) {
                        HStack {
                            Text("تعديل التاريخ الهجري")
                            Spacer()
                            Text(Self.days(model.settings.hijriOffset)).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("للعرض فقط، ولا يغيّر مواقيت الصلاة.")
                }
            }
            .navigationTitle("إعدادات الحساب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                        .accessibilityIdentifier("prayer.settings.done")
                }
            }
        }
    }

    private func adjustment(_ time: PrayerTime) -> Binding<Int> {
        Binding {
            model.settings.adjustments[time]
        } set: { value in
            var adjustments = model.settings.adjustments
            adjustments[time] = value
            model.setAdjustments(adjustments)
        }
    }

    private static func minutes(_ value: Int) -> String {
        value == 0 ? "بلا تعديل" : (value > 0 ? "+" : "−") + ArabicFormat.number(abs(value)) + " د"
    }

    private static func days(_ value: Int) -> String {
        value == 0 ? "بلا تعديل" : (value > 0 ? "+" : "−") + ArabicFormat.number(abs(value))
            + (abs(value) == 1 ? " يوم" : " يومان")
    }
}

extension PrayerAdjustments {
    subscript(time: PrayerTime) -> Int {
        get {
            switch time {
            case .fajr: fajr
            case .sunrise: sunrise
            case .dhuhr: dhuhr
            case .asr: asr
            case .maghrib: maghrib
            case .isha: isha
            }
        }
        set {
            switch time {
            case .fajr: fajr = newValue
            case .sunrise: sunrise = newValue
            case .dhuhr: dhuhr = newValue
            case .asr: asr = newValue
            case .maghrib: maghrib = newValue
            case .isha: isha = newValue
            }
        }
    }
}

// MARK: - Manual location

/// Latitude and longitude typed in, for users who deny location; Arabic-Indic or Western digits, «٫», «,» or «.».
struct ManualLocationView: View {
    let location: LocationProfile?
    let save: (Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var latitude = ""
    @State private var longitude = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("خط العرض (مثل ٢١٫٤٢)", text: $latitude)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("prayer.manual.latitude")
                    TextField("خط الطول (مثل ٣٩٫٨٢)", text: $longitude)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("prayer.manual.longitude")
                } footer: {
                    Text("خط العرض بين −٩٠ و٩٠، وخط الطول بين −١٨٠ و١٨٠. يُحفظ بمنزلتين عشريتين.")
                }
            }
            .navigationTitle("إدخال الموقع يدويًا")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        if let coordinates { save(coordinates.0, coordinates.1) }
                        dismiss()
                    }
                    .disabled(coordinates == nil)
                    .accessibilityIdentifier("prayer.manual.save")
                }
            }
            .onAppear {
                if let location, latitude.isEmpty, longitude.isEmpty {
                    latitude = String(location.latitude)
                    longitude = String(location.longitude)
                }
            }
        }
    }

    private var coordinates: (Double, Double)? {
        guard let lat = Self.parse(latitude), let lon = Self.parse(longitude),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }

    static func parse(_ text: String) -> Double? {
        var ascii = ""
        for scalar in text.trimmingCharacters(in: .whitespaces).unicodeScalars {
            switch scalar.value {
            case 0x0660...0x0669: ascii.append(Character(Unicode.Scalar(scalar.value - 0x0660 + 0x30)!))
            case 0x06F0...0x06F9: ascii.append(Character(Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!))
            case 0x066B, 0x2C: ascii.append(".") // «٫» and «,»
            case 0x2212: ascii.append("-") // «−»
            default: ascii.unicodeScalars.append(scalar)
            }
        }
        guard let value = Double(ascii), value.isFinite else { return nil }
        return value
    }
}

// MARK: - Wording

enum PrayerNames {
    static func name(_ time: PrayerTime) -> String {
        switch time {
        case .fajr: "الفجر"
        case .sunrise: "الشروق"
        case .dhuhr: "الظهر"
        case .asr: "العصر"
        case .maghrib: "المغرب"
        case .isha: "العشاء"
        }
    }

    /// The PWA's five labels first (its settings dialog), then the adhan-swift presets it does not offer.
    static func method(_ method: CalculationMethod) -> String {
        switch method {
        case .mwl: "رابطة العالم الإسلامي"
        case .ummAlQura: "أم القرى"
        case .egyptian: "الهيئة المصرية"
        case .karachi: "جامعة كراتشي"
        case .northAmerica: "أمريكا الشمالية"
        case .dubai: "دبي"
        case .moonsightingCommittee: "لجنة رؤية الهلال"
        case .kuwait: "الكويت"
        case .qatar: "قطر"
        case .singapore: "سنغافورة"
        case .tehran: "طهران"
        case .turkey: "تركيا"
        }
    }

    static func highLatitudeRule(_ rule: HighLatitudeRule) -> String {
        switch rule {
        case .twilightAngle: "زاوية الشفق"
        case .middleOfTheNight: "منتصف الليل"
        case .seventhOfTheNight: "سُبع الليل"
        }
    }
}

enum PrayerDates {
    /// Noon of `localDate`, a safe instant inside that civil day for formatting it.
    private static func noon(_ localDate: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// «السبت ٢٦ سبتمبر».
    static func gregorian(_ localDate: String) -> String {
        guard let date = noon(localDate) else { return localDate }
        var style = Date.FormatStyle(locale: Locale(identifier: "ar-EG")).weekday(.wide).day().month(.wide)
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }

    /// «١٤ ربيع الأول ١٤٤٨ هـ» (Umm al-Qura), shifted by the user's offset.
    static func hijri(_ localDate: String, offset: Int) -> String {
        guard let date = noon(localDate) else { return "" }
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let shifted = calendar.date(byAdding: .day, value: offset, to: date) ?? date
        var style = Date.FormatStyle(locale: Locale(identifier: "ar-EG"), calendar: calendar).day().month(.wide).year()
        style.timeZone = TimeZone(identifier: "UTC")!
        return shifted.formatted(style)
    }

    /// «١:٢٣:٠٥».
    static func remaining(from now: Date, to target: Date) -> String {
        let seconds = max(0, Int(target.timeIntervalSince(now).rounded(.up)))
        let text = String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        return text.map { $0.isASCII && $0.isNumber ? Character(ArabicFormat.number(Int(String($0))!)) : $0 }
            .reduce(into: "") { $0.append($1) }
    }

    /// «٢١٫٤٢، ٣٩٫٨٢».
    static func coordinates(_ latitude: Double, _ longitude: Double) -> String {
        func format(_ value: Double) -> String {
            String(format: "%.2f", value).map { character -> String in
                if character == "." { return "٫" }
                if character == "-" { return "−" }
                return character.isNumber ? ArabicFormat.number(Int(String(character))!) : String(character)
            }.joined()
        }
        return "\(format(latitude))، \(format(longitude))"
    }
}

private extension View {
    func card(_ palette: Palette) -> some View {
        background(RoundedRectangle(cornerRadius: 14.4, style: .continuous).fill(palette.surface.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 14.4, style: .continuous).strokeBorder(palette.border))
    }

    func pill(_ palette: Palette, prominent: Bool) -> some View {
        font(.subheadline.weight(.heavy))
            .foregroundStyle(prominent ? palette.accentStrong : palette.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(prominent ? palette.accentSoft : palette.surfaceRaised))
            .overlay(Capsule().strokeBorder(palette.border))
            .contentShape(Capsule())
    }
}
