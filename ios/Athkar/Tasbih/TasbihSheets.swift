import SwiftUI

/// «اختيار الذكر» (`tasbih-label-dialog`): the suggested phrases, the saved ones with «×», and «عبارة جديدة». Choosing
/// or adding a phrase closes the sheet; deleting one keeps it open.
struct TasbihPhraseSheet: View {
    let model: TasbihModel
    let apply: (TasbihModel.Change) -> Void

    /// Where VoiceOver goes: by position, since Swift equates canonically equivalent phrases.
    private enum Focus: Hashable {
        case preset(Int), custom(Int), input
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @AccessibilityFocusState private var focus: Focus?
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("أذكار مقترحة") {
                        ForEach(Array(model.presetOptions.enumerated()), id: \.element.id) { index, option in
                            optionButton(option, identifier: "tasbih.preset.\(option.key)")
                                .accessibilityFocused($focus, equals: .preset(index))
                        }
                    }
                    if !model.customOptions.isEmpty {
                        section("عباراتك") {
                            ForEach(Array(model.customOptions.enumerated()), id: \.element.id) { index, option in
                                HStack(spacing: 8) {
                                    optionButton(option, identifier: "tasbih.custom.\(index)")
                                        .accessibilityFocused($focus, equals: .custom(index))
                                    // The row's own phrase, not `model.custom[index]`: deleting the last phrase
                                    // updates this row before ForEach drops it, and the old index is out of range.
                                    deleteButton(TasbihText.savedText(of: option.key), index: index,
                                                 identifier: "tasbih.custom.\(index).delete")
                                }
                            }
                        }
                    }
                    section("عبارة جديدة") {
                        if model.canAddPhrase {
                            newPhrase
                        } else {
                            note("يمكن حفظ ٨ عبارات. احذف واحدة لإضافة غيرها.")
                                .accessibilityIdentifier("tasbih.custom.limit")
                        }
                    }
                }
                .padding()
            }
            .background(palette.background)
            .onAppear(perform: focusSelected)
            .navigationTitle("اختيار الذكر")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                        .accessibilityIdentifier("tasbih.phrases.close")
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// `tasbihOptionMarkup`: the phrase with its tashkeel and today's count; the one counted is pressed.
    private func optionButton(_ option: TasbihModel.Option, identifier: String) -> some View {
        let shape = Corner.box
        return Button {
            if let change = model.select(option.key) {
                dismiss()
                apply(change)
            }
        } label: {
            HStack(spacing: 12) {
                Text(option.label)
                    .font(ReadingFont.quran(16.8))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if option.count > 0 {
                    Text(ArabicFormat.number(option.count))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(option.isSelected ? palette.accentStrong : palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .background(shape.fill(option.isSelected ? palette.accentSoft : palette.surfaceRaised))
            .overlay(shape.strokeBorder(option.isSelected ? palette.accent.mixed(0.55, with: palette.border)
                                                          : palette.border))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityAddTraits(option.isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }

    /// `deleteTasbihPhrase`: the phrase leaves the list; its counts stay. VoiceOver moves to the saved phrase now
    /// in its place, or the one before it, or the typed phrase once none is left.
    private func deleteButton(_ phrase: String, index: Int, identifier: String) -> some View {
        Button {
            guard let change = model.deletePhrase(phrase) else { return }
            apply(change)
            let left = model.customOptions.count
            focus = left > 0 ? .custom(min(index, left - 1)) : .input
        } label: {
            Text("×")
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(palette.surfaceRaised))
                .overlay(Circle().strokeBorder(palette.border))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("حذف العبارة: \(TasbihText.stripTashkeel(phrase))")
        .accessibilityIdentifier(identifier)
    }

    private var newPhrase: some View {
        let canAdd = !TasbihText.cleanPhrase(text).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Text("اكتب الذكر")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 8) {
                TextField("مثل: سبحان الله وبحمده", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityLabel("اكتب الذكر")
                    .accessibilityHint("تُحفظ العبارة على هذا الجهاز لتختارها لاحقًا.")
                    .accessibilityIdentifier("tasbih.custom.input")
                    .accessibilityFocused($focus, equals: .input)
                    // `maxlength="60"`, in UTF-16 code units.
                    .onChange(of: text) { _, value in
                        var cut = value
                        while cut.utf16.count > TasbihText.maxPhraseLength { cut.removeLast() }
                        if cut.utf16.count != value.utf16.count { text = cut }
                    }
                Button("إضافة", action: add)
                    .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
                    .fixedSize()
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : 0.5)
                    .accessibilityIdentifier("tasbih.custom.add")
            }
            note("تُحفظ العبارة على هذا الجهاز لتختارها لاحقًا.")
                .accessibilityHidden(true)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(palette.textSecondary)
    }

    /// `openTasbihPhraseSheet`: VoiceOver starts on the phrase counted.
    private func focusSelected() {
        if let index = model.presetOptions.firstIndex(where: \.isSelected) {
            focus = .preset(index)
        } else if let index = model.customOptions.firstIndex(where: \.isSelected) {
            focus = .custom(index)
        }
    }

    /// `addTasbihPhrase`: a phrase already listed is chosen instead; a new one is saved and chosen.
    private func add() {
        guard let change = model.addPhrase(text) else {
            // With eight phrases saved the PWA empties the field too; the limit note replaces it.
            if !model.canAddPhrase { text = "" }
            return
        }
        text = ""
        dismiss()
        apply(change)
    }
}

/// «الهدف» (`tasbih-target-dialog`): «بلا هدف», ٣٣, ١٠٠ or «عدد آخر» typed in Arabic-Indic, Persian or Latin digits.
struct TasbihTargetSheet: View {
    let model: TasbihModel
    let apply: (TasbihModel.Change) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @FocusState private var inputFocused: Bool
    /// The option VoiceOver is on, by identifier.
    @AccessibilityFocusState private var focusedOption: String?
    @State private var showsInput: Bool
    @State private var input: String
    @State private var showsError = false

    init(model: TasbihModel, apply: @escaping (TasbihModel.Change) -> Void) {
        self.model = model
        self.apply = apply
        let custom = Self.isCustom(model.target)
        _showsInput = State(initialValue: custom)
        _input = State(initialValue: custom ? model.target.map(ArabicFormat.number) ?? "" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("الهدف")
                        .font(.title3.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("يتواصل العدّ بعد بلوغ الهدف.")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                    option("بلا هدف", detail: "عدّ مفتوح دون حدّ", identifier: "tasbih.target.none",
                           pressed: model.target == nil) { choose(nil) }
                    option(ArabicFormat.number(33), detail: "مثل التسبيح بعد الصلاة", identifier: "tasbih.target.33",
                           pressed: model.target == 33) { choose(33) }
                    option(ArabicFormat.number(100), detail: "مئة مرة", identifier: "tasbih.target.100",
                           pressed: model.target == 100) { choose(100) }
                    option("عدد آخر", detail: "من ١ إلى ٩٩٩٩", identifier: "tasbih.target.custom",
                           pressed: Self.isCustom(model.target)) {
                        showsInput = true
                        inputFocused = true
                    }
                    if showsInput { customForm }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear(perform: focusPressed)
            Button("إلغاء") { dismiss() }
                .buttonStyle(DialogButtonStyle(palette: palette))
                .accessibilityIdentifier("tasbih.target.cancel")
        }
        .padding(20)
        .fittedSheet(background: palette.background)
    }

    private func option(_ title: String, detail: String, identifier: String, pressed: Bool,
                        action: @escaping () -> Void) -> some View {
        let shape = Corner.box
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.bold))
                Text(detail).font(.footnote).foregroundStyle(palette.textSecondary)
            }
            .foregroundStyle(pressed ? palette.accentStrong : palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(shape.fill(pressed ? palette.accentSoft : palette.surfaceRaised))
            .overlay(shape.strokeBorder(pressed ? palette.accent.mixed(0.55, with: palette.border) : palette.border))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(pressed ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
        .accessibilityFocused($focusedOption, equals: identifier)
    }

    /// `openTasbihTargetDialog`: VoiceOver starts on the pressed option.
    private func focusPressed() {
        focusedOption = switch model.target {
        case nil: "tasbih.target.none"
        case 33: "tasbih.target.33"
        case 100: "tasbih.target.100"
        default: "tasbih.target.custom"
        }
    }

    private var customForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("مثل ٢٥٠", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .focused($inputFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityLabel("عدد آخر")
                    .accessibilityValue(showsError ? "\(input)، أدخل عددًا من ١ إلى ٩٩٩٩." : input)
                    .accessibilityIdentifier("tasbih.target.input")
                    .onChange(of: input) { _, value in
                        showsError = false
                        // `maxlength="5"`.
                        if value.utf16.count > 5 { input = String(value.prefix(5)) }
                    }
                Button("حفظ", action: save)
                    .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
                    .fixedSize()
                    .accessibilityIdentifier("tasbih.target.save")
            }
            if showsError {
                Text("أدخل عددًا من ١ إلى ٩٩٩٩.")
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
                    .accessibilityIdentifier("tasbih.target.error")
            }
        }
    }

    /// The target the input names, or the error under it.
    private func save() {
        guard let target = TasbihText.parseTarget(input) else {
            showsError = true
            inputFocused = true
            AccessibilityNotification.Announcement("أدخل عددًا من ١ إلى ٩٩٩٩.").post()
            return
        }
        choose(target)
    }

    private func choose(_ target: Int?) {
        guard let change = model.setTarget(target) else { return }
        dismiss()
        apply(change)
    }

    /// `isPresetTarget`, negated.
    private static func isCustom(_ target: Int?) -> Bool {
        target != nil && target != 33 && target != 100
    }
}
