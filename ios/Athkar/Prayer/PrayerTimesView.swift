import AthkarCore
import SwiftUI

/// The أوقات الصلاة section of أخرى: the day in large Naskh with the Moon's phase, the prayer counted to with its
/// time left (the next adhan or, after an adhan, its iqama), the day's six times with their symbols, the iqamas,
/// the start of «الإشراق» and the night's last third; the location that produced them, and the calculation settings (NATIVE_APP_PLAN.md §7.3).
struct PrayerTimesView: View {
    let model: PrayerTimesModel
    let reminders: ReminderModel
    /// Opens «اليوم», where today's prayers are recorded.
    var openToday: () -> Void = {}

    @Environment(\.palette) private var palette
    @State private var showsSettings = false
    @State private var showsReminders = false
    private let cities = CityDirectory.shared
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
                    prohibitedNote
                    locationCard
                }
                Button(action: openToday) {
                    Label("تسجيل صلوات اليوم", systemImage: "checklist")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("prayer.tracker")
                Button {
                    showsReminders = true
                } label: {
                    Label("تنبيهات الصلاة", systemImage: "bell")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("prayer.reminders")
                Button {
                    showsSettings = true
                } label: {
                    Label("إعدادات الحساب", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("prayer.settings")
            }
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { await cities.load() }
        .sheet(isPresented: $showsReminders) {
            PrayerRemindersView(reminders: reminders, prayer: model)
                .environment(\.palette, palette)
        }
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
            Text("حدّد موقعك لعرض مواقيت الصلاة")
                .font(.headline.weight(.bold))
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

    /// The day on screen: its weekday and Hijri day in large Naskh, the Moon's phase beside the weekday, the
    /// Gregorian date and the Hijri year under them, and arrows to the days around it.
    private var dayNavigator: some View {
        let date = PrayerTimesModel.localDate(daysFromToday: model.dayOffset, now: Date(), in: model.zone)
        let hijri = PrayerDates.hijriDay(date, offset: model.settings.hijriOffset)
        let gregorian = PrayerDates.gregorianDate(date)
        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                dayButton("اليوم السابق", systemImage: "chevron.backward", offset: model.dayOffset - 1)
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: PrayerDates.moonPhase(hijriDay: hijri.number))
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(palette.textSecondary)
                                // The lit side is the sky's, not the reading direction's.
                                .environment(\.layoutDirection, .leftToRight)
                                .accessibilityHidden(true)
                            Text(PrayerDates.weekday(date))
                                .font(Self.dayFont)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        Text(model.dayOffset == 0 ? "اليوم، " + gregorian : gregorian)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .accessibilityIdentifier("prayer.date")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(hijri.dayMonth)
                            .font(Self.dayFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(hijri.year)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("prayer.hijri")
                }
                .foregroundStyle(palette.textPrimary)
                dayButton("اليوم التالي", systemImage: "chevron.forward", offset: model.dayOffset + 1)
            }
            if model.dayOffset != 0 {
                Button("العودة إلى اليوم") { model.showDay(0) }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.accentStrong)
                    .frame(minHeight: 32)
                    .accessibilityIdentifier("prayer.today")
            }
        }
        .padding(.vertical, 8)
        .card(palette)
    }

    /// The weekday and the Hijri day: Uthman Taha, as the ayah markers, scaled with the text size.
    private static let dayFont = Font.custom(ReadingFont.quranName, size: 28, relativeTo: .title)

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

    /// The prayer counted to, large: before its adhan «الصلاة القادمة» with the adhan's time, after it «الصلاة
    /// الحالية» with the iqama's, and the time left under it in the accent.
    @ViewBuilder
    private func countdown(now: Date) -> some View {
        if let next = model.countdown(now: now) {
            let at = ArabicFormat.time(next.at, in: model.zone)
            let target = next.event == .adhan ? at : "الإقامة " + at
            let remaining = PrayerDates.remaining(from: now, to: next.at)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.event == .adhan ? "الصلاة القادمة" : "الصلاة الحالية")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(palette.accentStrong)
                    Text(PrayerNames.name(next.prayer))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PrayerSymbol(time: next.prayer, size: 60, tint: palette.accentStrong)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(target)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(remaining)
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.accentStrong)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .card(palette)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(PrayerNames.counting(to: next))، \(at)، بعد \(remaining)")
            .accessibilityIdentifier("prayer.countdown")
        }
    }

    // MARK: Times

    private var times: some View {
        let schedule = model.shownSchedule
        // The prayer counted to: the next adhan's, or the one whose iqama is still ahead.
        let next = model.dayOffset == 0 ? model.countdown() : nil
        return VStack(spacing: 0) {
            ForEach(Array(PrayerTime.allCases.enumerated()), id: \.element) { index, time in
                if index > 0 { Rule() }
                let isNext = next?.prayer == time && next?.date == schedule?.localDate
                let ink = isNext ? palette.accentStrong
                    : (time == .sunrise ? palette.textSecondary : palette.textPrimary)
                HStack(spacing: 12) {
                    Text(PrayerNames.name(time))
                        .font(.title3.weight(isNext ? .bold : .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PrayerSymbol(time: time, size: 40, tint: isNext ? palette.accentStrong : palette.textSecondary)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(value(time, in: schedule))
                            .font(.title3.weight(isNext ? .bold : .semibold).monospacedDigit())
                        if let schedule, let detail = detail(time, in: schedule) {
                            Text(detail)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(isNext ? palette.accentStrong : palette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .frame(minHeight: 60)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("prayer.time.\(time.rawValue)")
            }
            Rule()
            TimelineView(.everyMinute) { context in
                lastThird(now: context.date)
            }
        }
        .card(palette)
    }

    /// «الثلث الأخير» of the night after the shown day's Maghrib; today, of the night under way until Fajr, marked
    /// «الآن» while it lasts (spec/night/night.md).
    private func lastThird(now: Date) -> some View {
        let third = model.dayOffset == 0
            ? LastThird.tonight(at: now, in: model.zone) { model.nightTimes(on: $0) }
            : model.shownSchedule.flatMap { LastThird.night(after: $0.localDate) { model.nightTimes(on: $0) } }
        let isNow = third?.contains(now) == true
        return HStack(spacing: 12) {
            Text("الثلث الأخير")
                .font(.title3.weight(isNow ? .bold : .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            PrayerSymbol(name: PrayerSymbol.lastThird, size: 40,
                         tint: isNow ? palette.accentStrong : palette.textSecondary)
            VStack(alignment: .trailing, spacing: 2) {
                Text(third.map { ArabicFormat.time($0.start, in: model.zone) } ?? "—")
                    .font(.title3.weight(isNow ? .bold : .semibold).monospacedDigit())
                if isNow {
                    Text("الآن")
                        .font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(isNow ? palette.accentStrong : palette.textSecondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer.time.lastThird")
    }

    /// The five times behind the home row's «وقت نهي» notice (``ProhibitedTime``), as Ibn Baz's fatwa lists
    /// them, with what may still be prayed in them.
    private var prohibitedNote: some View {
        let sunrise = ArabicFormat.minutesLeft(Int(ProhibitedTime.afterSunrise / 60))
        let zenith = ArabicFormat.minutesLeft(Int(ProhibitedTime.beforeDhuhr / 60))
        return Text("""
            أوقات النهي عن الصلاة خمسة، كما في فتوى الشيخ ابن باز، وينبّه إليها صف المواقيت في أعلى صفحة الأذكار:
            ١. من طلوع الفجر حتى طلوع الشمس.
            ٢. من طلوع الشمس حتى ترتفع قيد رمح، نحو \(sunrise).
            ٣. عند استواء الشمس قبيل الظهر حتى تزول، نحو \(zenith).
            ٤. من صلاة العصر حتى تصفرّ الشمس، قرب أن يصير ظل الشيء مثليه.
            ٥. من اصفرار الشمس حتى تغرب.
            ويُصلّى فيها ما فات من الفرائض، وذوات الأسباب كتحية المسجد وسنة الوضوء.
            """)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityIdentifier("prayer.prohibited")
    }

    private func value(_ time: PrayerTime, in schedule: PrayerSchedule?) -> String {
        guard let schedule else { return "—" }
        if time == .asr, schedule.asrClamped { return "غير محدد" }
        guard let instant = schedule[time] else { return "—" }
        return ArabicFormat.time(instant, in: schedule.zone)
    }

    /// The line under a time: when the sun has risen enough for «صلاة الإشراق» (the end of the sunrise
    /// ``ProhibitedTime``), each prayer's iqama, and on a Friday that Dhuhr's follows the khutbah.
    private func detail(_ time: PrayerTime, in schedule: PrayerSchedule) -> String? {
        if time == .sunrise {
            return schedule.sunrise.map { "بداية الإشراق " + ArabicFormat.time($0 + ProhibitedTime.afterSunrise,
                                                                              in: schedule.zone) }
        }
        if let prayer = ObligatoryPrayer(rawValue: time.rawValue), model.iqama[prayer] > 0,
           IqamaDelays.followsKhutbah(time, in: schedule) {
            return "الإقامة بعد الخطبة"
        }
        return model.iqama.iqama(of: time, in: schedule).map { "الإقامة " + ArabicFormat.time($0, in: schedule.zone) }
    }

    // MARK: Location

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let location = model.location {
                if let city = cities.nearestName(location) {
                    Text(city)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .accessibilityIdentifier("prayer.city")
                }
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
        .padding(.vertical, 12).padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }
}

/// A time's symbol in a ring: the sun rising, risen, high, lower, setting, then the night and its last third.
private struct PrayerSymbol: View {
    let name: String
    let size: CGFloat
    let tint: Color

    @Environment(\.palette) private var palette

    init(time: PrayerTime, size: CGFloat, tint: Color) {
        self.init(name: Self.name(time), size: size, tint: tint)
    }

    init(name: String, size: CGFloat, tint: Color) {
        self.name = name
        self.size = size
        self.tint = tint
    }

    /// «الثلث الأخير».
    static let lastThird = "moon.haze"

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.42, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .overlay { Circle().strokeBorder(palette.border) }
            .accessibilityHidden(true)
    }

    static func name(_ time: PrayerTime) -> String {
        switch time {
        case .fajr: "sunrise"
        case .sunrise: "sun.horizon"
        case .dhuhr: "sun.max"
        case .asr: "sun.min"
        case .maghrib: "sunset"
        case .isha: "moon.stars"
        }
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
                // Closures, not the model's methods: converting a method reference to Binding's
                // @isolated(any) setter crashes Xcode 26's Swift 6.3 compiler (DeckCardView's target picker).
                Section {
                    Picker("طريقة الحساب",
                           selection: Binding(get: { model.settings.method }, set: { model.setMethod($0) })) {
                        ForEach(CalculationMethod.allCases, id: \.self) { method in
                            Text(PrayerNames.method(method)).tag(method)
                        }
                    }
                    .accessibilityIdentifier("prayer.settings.method")
                    Picker("مذهب العصر",
                           selection: Binding(get: { model.settings.asrSchool }, set: { model.setAsrSchool($0) })) {
                        Text("الجمهور").tag(AsrSchool.standard)
                        Text("الحنفي").tag(AsrSchool.hanafi)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("prayer.settings.asrSchool")
                    Picker("خطوط العرض العالية",
                           selection: Binding(get: { model.settings.highLatitudeRule },
                                              set: { model.setHighLatitudeRule($0) })) {
                        ForEach(HighLatitudeRule.allCases, id: \.self) { rule in
                            Text(PrayerNames.highLatitudeRule(rule)).tag(rule)
                        }
                    }
                } footer: {
                    Text("يحدد خيار «خطوط العرض العالية» كيف يُقدَّر الفجر والعشاء حيث لا يغيب الشفق.")
                }
                Section {
                    ForEach(ObligatoryPrayer.allCases, id: \.self) { prayer in
                        Stepper(value: Binding(get: { model.iqama[prayer] }, set: { model.setIqama($0, for: prayer) }),
                                in: IqamaDelays.range) {
                            HStack {
                                Text(PrayerNames.name(prayer.time))
                                Spacer()
                                Text(Self.iqama(model.iqama[prayer]))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("prayer.settings.iqama.\(prayer.rawValue)")
                    }
                } header: {
                    Text("الإقامة بعد الأذان")
                } footer: {
                    Text("بعد كل أذان يعدّ التطبيق الوقت الباقي على الإقامة. القيم الافتراضية مُدد وزارة الشؤون الإسلامية: الفجر ٢٥ دقيقة، "
                         + "والمغرب ١٠، وسائر الصلوات ٢٠. واختر الصفر لإخفاء الإقامة.")
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
                    Stepper(value: Binding(get: { model.settings.hijriOffset }, set: { model.setHijriOffset($0) }),
                            in: -2...2) {
                        HStack {
                            Text("تعديل التاريخ الهجري")
                            Spacer()
                            Text(Self.days(model.settings.hijriOffset)).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("يغيّر التاريخ المعروض. ومع حساب أم القرى يحدّد أيضًا أيام رمضان، حين تكون العشاء بعد المغرب بساعتين.")
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

    private static func iqama(_ value: Int) -> String {
        value == 0 ? "بلا إقامة" : ArabicFormat.number(value) + " د"
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
    @State private var query = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var results: [City] = []
    private let cities = CityDirectory.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("اسم المدينة (مثل الرياض أو Riyadh)", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .accessibilityIdentifier("prayer.manual.city")
                    if cities.index == nil {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("تحميل قائمة المدن…").foregroundStyle(.secondary)
                        }
                    } else if !query.trimmingCharacters(in: .whitespaces).isEmpty, results.isEmpty {
                        Text("لم توجد مدينة بهذا الاسم. جرّب الاسم بالإنجليزية، أو أدخل الإحداثيات أدناه.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { city in
                        Button {
                            save(city.coordinates.latitude, city.coordinates.longitude)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CityDirectory.label(city))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if !city.arabicNames.isEmpty, let english = city.englishNames.last {
                                    Text(english).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("prayer.manual.result.\(city.id)")
                    }
                } header: {
                    Text("البحث عن مدينة")
                } footer: {
                    Text("يبحث التطبيق في قائمة مدن مضمّنة فيه، ولا يُرسل ما تكتبه إلى أي جهة. أسماء المدن من GeoNames (CC BY 4.0).")
                }
                Section {
                    TextField("خط العرض (مثل ٢١٫٤٢)", text: $latitude)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("prayer.manual.latitude")
                    TextField("خط الطول (مثل ٣٩٫٨٢)", text: $longitude)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("prayer.manual.longitude")
                } header: {
                    Text("أو الإحداثيات")
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
            .task { await cities.load() }
            .onChange(of: query) { search() }
            .onChange(of: cities.index == nil) { search() }
        }
    }

    private func search() {
        results = cities.index?.search(query, limit: 20) ?? []
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

    /// What a counter counts to: «الصلاة القادمة: الظهر» before the adhan, «إقامة الظهر» after it.
    static func counting(to countdown: PrayerCountdown) -> String {
        switch countdown.event {
        case .adhan: "الصلاة القادمة: \(name(countdown.prayer))"
        case .iqama: "إقامة \(name(countdown.prayer))"
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

    /// «الجمعة».
    static func weekday(_ localDate: String) -> String {
        guard let date = noon(localDate) else { return "" }
        var style = Date.FormatStyle(locale: Locale(identifier: "ar-EG")).weekday(.wide)
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }

    /// «١٣ نوفمبر ٢٠٢٦».
    static func gregorianDate(_ localDate: String) -> String {
        guard let date = noon(localDate) else { return localDate }
        var style = Date.FormatStyle(locale: Locale(identifier: "ar-EG")).day().month(.wide).year()
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }

    /// The Hijri day of `localDate` (Umm al-Qura), shifted by the user's offset: its number, «٣ جمادى الآخرة» and
    /// «١٤٤٨ هـ».
    static func hijriDay(_ localDate: String, offset: Int) -> (number: Int, dayMonth: String, year: String) {
        guard let date = noon(localDate) else { return (1, "", "") }
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let shifted = calendar.date(byAdding: .day, value: offset, to: date) ?? date
        var style = Date.FormatStyle(locale: Locale(identifier: "ar-EG"), calendar: calendar).day().month(.wide)
        style.timeZone = TimeZone(identifier: "UTC")!
        return (calendar.component(.day, from: shifted), shifted.formatted(style),
                ArabicFormat.number(calendar.component(.year, from: shifted)) + " هـ")
    }

    /// The SF Symbol of the Moon on Hijri day `day`: a crescent after the month is sighted, full in its middle,
    /// gone at its end.
    static func moonPhase(hijriDay day: Int) -> String {
        switch day {
        case ...6: "moonphase.waxing.crescent"
        case 7...8: "moonphase.first.quarter"
        case 9...13: "moonphase.waxing.gibbous"
        case 14...16: "moonphase.full.moon"
        case 17...21: "moonphase.waning.gibbous"
        case 22...23: "moonphase.last.quarter"
        case 24...28: "moonphase.waning.crescent"
        default: "moonphase.new.moon"
        }
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

/// The prayer screens' section and button styles, shared with the tracker's and the qibla's.
extension View {
    /// A section of the screen: on the page under a rule, not in a box.
    func card(_ palette: Palette) -> some View {
        overlay(alignment: .top) { Rule() }
    }

    /// A button: filled with the accent when `prominent`, outlined otherwise.
    func pill(_ palette: Palette, prominent: Bool) -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? palette.onAccent : palette.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Corner.box.fill(prominent ? palette.accent : .clear))
            .overlay {
                if !prominent { Corner.box.strokeBorder(palette.border) }
            }
            .contentShape(Corner.box)
    }
}
