#if os(iOS)
import SwiftUI
import PayCrossCore

struct CardFormView: View {
    @Environment(\.payCrossAppearance) private var style
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var walletButtonHeight: CGFloat = 48
    @FocusState private var cardholderFocused: Bool
    @Binding var state: CardFormState
    let amount: Amount
    let allowsSaving: Bool
    var allowsCardRemoval: Bool = false
    let isLoading: Bool
    let fieldGroups: [FieldGroup]
    @Binding var fieldValues: [String: [String: String]]
    @Binding var optedInGroups: Set<String>
    let fieldErrors: [FieldGroupError]
    let language: String
    let onPay: () -> Void
    var showsApplePayButton: Bool = false
    var onApplePay: () -> Void = {}
    var onRemoveRequested: (SavedCard) -> Void = { _ in }

    private var canPay: Bool { state.canSubmit() && !isLoading }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AmountHeader(amount: amount)

                    if let error = state.inlineError {
                        ErrorBanner(message: error)
                    }

                    if showsApplePayButton {
                        ApplePayButtonView(action: onApplePay, isEnabled: !isLoading)
                            .frame(height: max(walletButtonHeight, style.buttonHeight(or: 0)))
                            .payCrossIdentifier(.walletButton)

                        HStack {
                            VStack { Divider() }
                            Text(L("paycross_or_pay_with_card", "Or pay with card"))
                                .font(style.font(.footnote))
                                .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
                                // WHY: layoutPriority rather than fixedSize, so the caption wraps at accessibility sizes instead of overflowing.
                                .layoutPriority(1)
                            VStack { Divider() }
                        }
                        .payCrossIdentifier(.walletDivider)
                    }

                    if !state.savedCards.isEmpty {
                        SavedCardPicker(
                            cards: state.savedCards,
                            selection: state.source,
                            allowsRemoval: allowsCardRemoval,
                            isPaying: isLoading,
                            onSelect: { send(.sourceSelected($0)) },
                            onRemoveRequested: onRemoveRequested
                        )
                    }

                    if state.source.isNewCard {
                        newCardFields
                    } else {
                        cvvField
                    }

                    if !fieldGroups.isEmpty {
                        FieldGroupsView(
                            groups: fieldGroups,
                            values: $fieldValues,
                            optedInGroups: $optedInGroups,
                            errors: fieldErrors,
                            language: language
                        )
                    }

                    if allowsSaving && state.source.isNewCard {
                        Toggle(L("paycross_save_this_card", "Save card for future use"), isOn: saveCardBinding)
                            .font(style.font(.subheadline))
                            .payCrossIdentifier(.saveCard)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 0) {
                Divider()
                PayButton(amount: amount, isLoading: isLoading, isEnabled: canPay, action: onPay)
                    .padding(20)
            }
            .background(.ultraThinMaterial)
        }
        .background(style.color(\.surface) ?? Color(.systemGroupedBackground))
        .payCrossForeground(style.color(\.text))
        .contentShape(Rectangle())
        .onTapGesture { KeypadDismissal.resignFirstResponder() }
    }

    private var newCardFields: some View {
        let cardholderTitle = L("paycross_cardholder_name", "Cardholder Name")
        let cardNumberTitle = L("paycross_card_number", "Card Number")

        return VStack(alignment: .leading, spacing: 14) {
            LabeledField(
                title: cardholderTitle,
                focus: { cardholderFocused = true }
            ) {
                TextField(L("paycross_name_on_card", "NAME ON CARD"), text: binding(\.cardholderName, event: CardFormEvent.nameChanged))
                    .accessibilityLabel(cardholderTitle)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .focused($cardholderFocused)
                    .payCrossIdentifier(.cardholderName)
            }

            LabeledField(title: cardNumberTitle, trailing: BrandBadge(brand: state.brand)) {
                // WHY: UIKeyboardType has no equivalent of Android's NumberPassword, so iOS gives this field no keyboard-side protection.
                NumericField(
                    placeholder: "1234 5678 9012 3456",
                    text: panBinding,
                    accessibleName: cardNumberTitle,
                    contentType: .creditCardNumber,
                    identifier: PayCrossTestIdentifiers.cardNumber.rawValue
                )
            }

            // WHY: ViewThatFits would always pick the side-by-side layout, because NumericField sets low hugging and compression resistance.
            if dynamicTypeSize.isAccessibilitySize {
                expiryField
                cvvField
            } else {
                HStack(spacing: 12) {
                    expiryField
                    cvvField
                }
            }
        }
    }

    private var expiryField: some View {
        let title = L("paycross_expiry_label", "MM/YY")
        return LabeledField(title: title) {
            NumericField(
                placeholder: "12/30",
                text: expiryBinding,
                accessibleName: title,
                identifier: PayCrossTestIdentifiers.expiry.rawValue
            )
        }
    }

    private var cvvField: some View {
        let title = L("paycross_cvv", "CVV")
        return LabeledField(title: title) {
            NumericField(
                placeholder: String(repeating: "•", count: state.cvvBrand.cvvLength),
                text: cvvBinding,
                accessibleName: title,
                isSecure: true,
                identifier: PayCrossTestIdentifiers.cvv.rawValue
            )
        }
    }

    // MARK: - Bindings

    private var panBinding: Binding<String> {
        Binding(
            get: { state.formattedPAN },
            set: { send(.panChanged($0)) }
        )
    }

    private var expiryBinding: Binding<String> {
        Binding(
            get: { state.formattedExpiry },
            set: { send(.expiryChanged($0)) }
        )
    }

    private var cvvBinding: Binding<String> {
        Binding(
            get: { state.cvvDigits },
            set: { send(.cvvChanged($0)) }
        )
    }

    private func binding(
        _ keyPath: KeyPath<CardFormState, String>,
        event: @escaping (String) -> CardFormEvent
    ) -> Binding<String> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: { send(event($0)) }
        )
    }

    private var saveCardBinding: Binding<Bool> {
        Binding(
            get: { state.saveCard },
            set: { send(.saveCardToggled($0)) }
        )
    }

    private func send(_ event: CardFormEvent) {
        CardFormReducer.reduce(state: &state, event: event)
    }
}

// MARK: - Pieces

private struct AmountHeader: View {
    @Environment(\.payCrossAppearance) private var style
    @Environment(\.locale) private var locale
    let amount: Amount

    var body: some View {
        let caption = L("paycross_total", "Total")
        let total = Amounts.formatted(amount, locale: locale)

        return VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(style.font(.footnote, weight: .medium))
                .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
                .textCase(.uppercase)
                // WHY: VoiceOver spells uppercase text letter by letter, and the amount label below already says the words.
                .accessibilityHidden(true)
            Text(total)
                .font(style.font(.largeTitle, weight: .semibold))
                .monospacedDigit()
                .accessibilityLabel("\(caption), \(total)")
                .payCrossIdentifier(.amount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LabeledField<Content: View, Trailing: View>: View {
    @Environment(\.payCrossAppearance) private var style
    let title: String
    var trailing: Trailing
    var focus: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        trailing: Trailing,
        focus: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.focus = focus
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(style.font(.footnote, weight: .medium))
                .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
                // WHY: each field's own accessibility label already says these words.
                .accessibilityHidden(true)
            HStack {
                content
                    // WHY: a UITextField is only one line tall, so the 44pt tap target is set on the field itself.
                    .frame(minHeight: 44)
                    .font(style.font(.body).monospacedDigit())
                trailing
            }
            .padding(.horizontal, 12)
            .payCrossComponentBackground(style)
            .tapToFocus(focus)
        }
    }
}

extension LabeledField where Trailing == EmptyView {
    init(
        title: String, focus: (() -> Void)? = nil, @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, trailing: EmptyView(), focus: focus, content: content)
    }
}

private struct BrandBadge: View {
    @Environment(\.payCrossAppearance) private var style
    let brand: CardBrand

    var body: some View {
        Text(brand == .unknown ? "" : brand.displayName)
            .font(style.font(.caption, weight: .semibold))
            .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
            .payCrossIdentifier(.brand)
    }
}

struct ErrorBanner: View {
    @Environment(\.payCrossAppearance) private var style
    let message: String
    var announce: (String) -> Void = { SheetAnnouncement.post($0) }

    private var errorColor: Color { style.color(\.error) ?? Color(.systemRed) }

    var body: some View {
        HStack(spacing: 8) {
            // WHY: the icon carries the meaning too, so colour is not the only cue.
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(style.font(.footnote))
        .foregroundStyle(errorColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            errorColor.opacity(0.1),
            in: RoundedRectangle(cornerRadius: style.cornerRadius(or: 10))
        )
        .payCrossIdentifier(.errorBanner)
        .onAppear { announce(message) }
        .onChange(of: message) { announce($0) }
    }
}

private struct PayButton: View {
    @Environment(\.payCrossAppearance) private var style
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 50
    @Environment(\.locale) private var locale
    let amount: Amount
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    private var fill: Color {
        if isEnabled {
            style.color(\.buttonBackground) ?? .accentColor
        } else {
            style.color(\.buttonDisabledBackground) ?? Color.gray.opacity(0.4)
        }
    }

    private var labelColor: Color {
        if isEnabled {
            style.color(\.buttonLabel) ?? .onBrand(of: .accentColor)
        } else {
            style.color(\.buttonDisabledLabel) ?? .white
        }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(labelColor)
                } else {
                    Text(L(
                        "paycross_pay_amount", "Pay %@",
                        Amounts.formatted(amount, locale: locale)
                    ))
                        .font(style.font(.headline))
                }
            }
            .frame(maxWidth: .infinity, minHeight: max(height, style.buttonHeight(or: 0)))
        }
        .background(fill, in: RoundedRectangle(cornerRadius: style.buttonCornerRadius(or: 12)))
        .foregroundStyle(labelColor)
        .disabled(!isEnabled)
        .payCrossIdentifier(.payButton)
    }
}
#endif
