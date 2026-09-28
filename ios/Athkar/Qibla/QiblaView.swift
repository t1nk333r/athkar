import AthkarCore
import SwiftUI

/// The القبلة section of أخرى: the Kaaba's direction from the stored location, on a live compass where the device has
/// one. The dial turns so its north follows the real north; the Kaaba mark sits at the Qibla bearing on it, and the fixed
/// pointer at the top is where the phone points. Without a compass (the simulator, some iPads) the dial stays north-up
/// and the bearing is given in degrees.
struct QiblaView: View {
    let prayer: PrayerTimesModel
    let openPrayerTimes: () -> Void

    @Environment(\.palette) private var palette
    @State private var heading = DeviceHeading()
    @State private var wasAligned = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let location = prayer.location {
                    let place = GeoCoordinates(latitude: location.latitude, longitude: location.longitude)
                    compass(bearing: Qibla.bearing(from: place))
                    details(place)
                } else {
                    noLocation
                }
            }
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { heading.start() }
        .onDisappear { heading.stop() }
    }

    // MARK: Compass

    private func compass(bearing: Double) -> some View {
        let deviceHeading = heading.degrees ?? 0
        let live = heading.isAvailable && heading.degrees != nil
        let aligned = live && Qibla.isAligned(bearing: bearing, heading: deviceHeading)
        return VStack(spacing: 14) {
            ZStack {
                dial(bearing: bearing, heading: deviceHeading, aligned: aligned)
                // Where the phone points.
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.title3)
                    .foregroundStyle(aligned ? palette.completed : palette.accentStrong)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: -18)
            }
            .frame(width: 260, height: 260)
            .padding(.top, 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spoken(bearing: bearing, heading: deviceHeading, live: live, aligned: aligned))
            .accessibilityIdentifier("qibla.compass")

            Text(status(bearing: bearing, live: live, aligned: aligned))
                .font(.headline.weight(.heavy))
                .foregroundStyle(aligned ? palette.completed : palette.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("qibla.status")
            if let note = note(live: live) {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .qiblaCard(palette)
        .onChange(of: aligned) { _, now in
            if now, !wasAligned { Haptics.shared.playCompletion() }
            wasAligned = now
        }
    }

    private func dial(bearing: Double, heading: Double, aligned: Bool) -> some View {
        ZStack {
            Circle().fill(palette.surfaceRaised)
            Circle().strokeBorder(aligned ? palette.completed : palette.border, lineWidth: aligned ? 3 : 1.5)
            ForEach(0..<72, id: \.self) { tick in
                Capsule()
                    .fill(tick % 18 == 0 ? palette.textPrimary : palette.textSecondary.opacity(tick % 2 == 0 ? 0.6 : 0.3))
                    .frame(width: tick % 18 == 0 ? 3 : 1.5, height: tick % 18 == 0 ? 14 : 8)
                    .offset(y: -118)
                    .rotationEffect(.degrees(Double(tick) * 5))
            }
            ForEach(Array(["ش", "ق", "ج", "غ"].enumerated()), id: \.offset) { index, letter in
                Text(letter)
                    .font(.subheadline.weight(.heavy))
                    .fixedSize()
                    .foregroundStyle(index == 0 ? palette.accentStrong : palette.textSecondary)
                    .rotationEffect(.degrees(-Double(index) * 90 + heading))
                    .offset(y: -94)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            // The Qibla line from the centre to the Kaaba mark.
            Capsule()
                .fill(aligned ? palette.completed : palette.accent)
                .frame(width: 3, height: 70)
                .offset(y: -35)
                .rotationEffect(.degrees(bearing))
            Image(systemName: "cube.fill")
                .font(.title2)
                .foregroundStyle(aligned ? palette.completed : palette.textPrimary)
                .rotationEffect(.degrees(-bearing + heading))
                .offset(y: -80)
                .rotationEffect(.degrees(bearing))
            Circle().fill(aligned ? palette.completed : palette.accent).frame(width: 10, height: 10)
        }
        // North on the dial follows the real north as the phone turns.
        .rotationEffect(.degrees(-heading))
        // A compass is not mirrored for right-to-left: east stays on the right.
        .environment(\.layoutDirection, .leftToRight)
        .animation(.easeOut(duration: 0.2), value: heading)
    }

    private func status(bearing: Double, live: Bool, aligned: Bool) -> String {
        guard live else { return "القبلة على \(Self.degrees(bearing)) من الشمال" }
        if aligned { return "أنت متجه إلى القبلة" }
        let offset = Qibla.offset(bearing: bearing, heading: heading.degrees ?? 0)
        return offset > 0 ? "استدر يمينًا \(Self.degrees(abs(offset)))" : "استدر يسارًا \(Self.degrees(abs(offset)))"
    }

    private func note(live: Bool) -> String? {
        if !heading.isAvailable {
            return "لا توجد بوصلة في هذا الجهاز. قِس الزاوية من الشمال باتجاه عقارب الساعة."
        }
        if !live { return "ضع الهاتف مستويًا وانتظر قليلًا حتى تعمل البوصلة." }
        if heading.needsCalibration { return "البوصلة تحتاج معايرة: حرّك الهاتف في الهواء على شكل رقم ٨." }
        if !heading.isTrueNorth {
            return "الاتجاه من الشمال المغناطيسي وقد يختلف بضع درجات. اسمح بالموقع للتطبيق ليُحسب من الشمال الحقيقي."
        }
        return "ضع الهاتف مستويًا وأبعده عن المعادن والمغناطيس."
    }

    // MARK: Details

    private func details(_ place: GeoCoordinates) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("اتجاه القبلة", "\(Self.degrees(Qibla.bearing(from: place))) من الشمال")
                .accessibilityIdentifier("qibla.bearing")
            Divider().overlay(palette.border)
            detailRow("المسافة إلى الكعبة", Self.kilometres(Qibla.distanceKilometres(from: place)))
            Divider().overlay(palette.border)
            detailRow("الموقع", PrayerDates.coordinates(place.latitude, place.longitude))
        }
        .padding(14)
        .qiblaCard(palette)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.textSecondary)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: No location

    private var noLocation: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.north.line")
                .font(.largeTitle)
                .foregroundStyle(palette.accentStrong)
            Text("حدّد موقعك لمعرفة اتجاه القبلة")
                .font(.headline.weight(.heavy))
                .foregroundStyle(palette.textPrimary)
            Text("يُستعمل الموقع نفسه الذي تُحسب منه مواقيت الصلاة، ولا يُرسل إلى أي جهة.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: openPrayerTimes) {
                Text("تحديد الموقع في أوقات الصلاة")
                    .font(.subheadline.weight(.heavy))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(palette.accentSoft))
                    .foregroundStyle(palette.accentStrong)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("qibla.setLocation")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .qiblaCard(palette)
    }

    // MARK: Formatting

    /// «٢٤٣°».
    static func degrees(_ value: Double) -> String {
        ArabicFormat.number(Int(value.rounded()) % 360) + "°"
    }

    /// «٧٩٣ كم».
    static func kilometres(_ value: Double) -> String {
        value < 1 ? "أقل من ١ كم" : ArabicFormat.number(Int(value.rounded())) + " كم"
    }

    private static func spoken(bearing: Double, heading: Double, live: Bool, aligned: Bool) -> String {
        guard live else { return "القبلة على \(degrees(bearing)) من الشمال باتجاه عقارب الساعة" }
        if aligned { return "أنت متجه إلى القبلة" }
        let offset = Qibla.offset(bearing: bearing, heading: heading)
        return "القبلة إلى \(offset > 0 ? "يمينك" : "يسارك") بـ\(degrees(abs(offset)))"
    }
}

private extension View {
    func qiblaCard(_ palette: Palette) -> some View {
        background(RoundedRectangle(cornerRadius: 14.4, style: .continuous).fill(palette.surface.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 14.4, style: .continuous).strokeBorder(palette.border))
    }
}
