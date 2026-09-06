#if os(iOS)
import SwiftUI
import PayCrossCore

/// The card entry form.
///
/// Holds no logic of its own: every keystroke goes through `CardFormReducer` in
/// Core, which is where formatting, brand limits, validation and the PCI-driven
/// CVV clearing live. That keeps this file a rendering concern and keeps the
/// behaviour testable on Linux.
struct CardFormView: View {
    @Environment(\.payCrossAppearance) private var style
    @Binding var state: CardFormState
    let amount: Amount
    let allowsSaving: Bool
    /// Whether the session invited the shopper to delete a stored card.
    var allowsCardRemoval: Bool = false
    let isLoading: Bool
    let fieldGroups: [FieldGroup]
    @Binding var fieldValues: [String: [String: String]]
    let fieldErrors: [FieldGroupError]
    let onPay: () -> Void
    var showsApplePayButton: Bool = false
    var onApplePay: () -> Void = {}
    /// Called when the shopper presses a row's trash. Nothing is deleted here:
    /// the sheet confirms first, then calls the server, and the row goes only
    /// once the server has taken the card.
    var onRemoveRequested: (SavedCard) -> Void = { _ in }

    private var canPay: Bool { state.canSubmit() && !isLoading }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AmountHeader(amount: amount)

                    // Directly under the total, not at the end of the column.
                    // Last meant below the fields, the field groups and the save
                    // toggle, which on a form with server-driven fields put it off
                    // the bottom of the screen: the shopper saw an unchanged form
                    // and a Pay button that had gone disabled, with no reason for
                    // either. Here it is on screen whatever the session asks for.
                    if let error = state.inlineError {
                        ErrorBanner(message: error)
                    }

                    if showsApplePayButton {
                        ApplePayButtonView(action: onApplePay, isEnabled: !isLoading)
                            .frame(height: 48)
                            .payCrossIdentifier(.walletButton)

                        // A separator rather than nothing: without it the card
                        // fields read as part of the Apple Pay button, and a
                        // shopper who has already decided reads "or" faster
                        // than they read a gap.
                        HStack {
                            VStack { Divider() }
                            Text(L("paycross_or_pay_with_card", "Or pay with card"))
                                .font(style.font(.footnote))
                                .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
                                // The rules give, not the caption. English sits
                                // two characters inside the width this row has,
                                // so "Ou payer par carte" wrapped mid-phrase
                                // between two lines that had room to spare.
                                // Priority rather than fixedSize: the dividers
                                // still shrink first, but once they are gone the
                                // caption wraps instead of running off a sheet
                                // it can no longer fit on at accessibility sizes.
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
                            errors: fieldErrors
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
            // Dragging the form is the gesture a shopper reaches for first when
            // something covers what they want to read.
            .scrollDismissesKeyboard(.interactively)

            // Pinned rather than trailing the fields. A Pay button that floats
            // mid-screen reads as unfinished, and on a taller device it drifts
            // further from the thumb the longer the form is.
            VStack(spacing: 0) {
                Divider()
                PayButton(amount: amount, isLoading: isLoading, isEnabled: canPay, action: onPay)
                    .padding(20)
            }
            .background(.ultraThinMaterial)
        }
        .background(style.color(\.surface) ?? Color(.systemGroupedBackground))
        .payCrossForeground(style.color(\.text))
        // A tap off the fields is the other habit. Buttons and the toggle still
        // win their own taps; this only claims the gaps between them.
        .contentShape(Rectangle())
        .onTapGesture { KeypadDismissal.resignFirstResponder() }
    }

    private var newCardFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledField(title: L("paycross_cardholder_name", "Cardholder Name")) {
                TextField(L("paycross_name_on_card", "NAME ON CARD"), text: binding(\.cardholderName, event: CardFormEvent.nameChanged))
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .payCrossIdentifier(.cardholderName)
            }

            LabeledField(title: L("paycross_card_number", "Card Number"), trailing: BrandBadge(brand: state.brand)) {
                // NOTE: Android uses KeyboardType.NumberPassword here, which
                // makes the framework withhold the field's contents from the
                // keyboard process. UIKeyboardType has no such variation, so
                // iOS has NO equivalent protection on this field today. Do not
                // record this as covered in a security review.
                NumericField(
                    placeholder: "1234 5678 9012 3456",
                    text: panBinding,
                    contentType: .creditCardNumber,
                    identifier: PayCrossTestIdentifiers.cardNumber.rawValue
                )
            }

            HStack(spacing: 12) {
                LabeledField(title: L("paycross_expiry_label", "MM/YY")) {
                    NumericField(
                        placeholder: "12/30",
                        text: expiryBinding,
                        identifier: PayCrossTestIdentifiers.expiry.rawValue
                    )
                }
                cvvField
            }
        }
    }

    private var cvvField: some View {
        LabeledField(title: L("paycross_cvv", "CVV")) {
            NumericField(
                placeholder: String(repeating: "•", count: state.cvvBrand.cvvLength),
                text: cvvBinding,
                isSecure: true,
                identifier: PayCrossTestIdentifiers.cvv.rawValue
            )
        }
    }

    // MARK: - Bindings

    /// Display-formatted text in, digits out. The reducer strips everything else,
    /// so a paste of "4111-1111-1111-1111" lands correctly.
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
    /// Set by the sheet from the language it resolved, so the amount and the
    /// words around it agree on where the comma goes.
    @Environment(\.locale) private var locale
    let amount: Amount

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("paycross_total", "Total"))
                .font(style.font(.footnote, weight: .medium))
                .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
                .textCase(.uppercase)
            Text(Amounts.formatted(amount, locale: locale))
                .font(style.font(.largeTitle, weight: .semibold))
                .monospacedDigit()
                .payCrossIdentifier(.amount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LabeledField<Content: View, Trailing: View>: View {
    @Environment(\.payCrossAppearance) private var style
    let title: String
    var trailing: Trailing
    @ViewBuilder let content: Content

    init(title: String, trailing: Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(style.font(.footnote, weight: .medium))
                .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
            HStack {
                content
                    .font(style.font(.body).monospacedDigit())
                trailing
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .payCrossComponentBackground(style)
        }
    }
}

extension LabeledField where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: EmptyView(), content: content)
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

private struct ErrorBanner: View {
    @Environment(\.payCrossAppearance) private var style
    let message: String

    private var errorColor: Color { style.color(\.error) ?? Color(.systemRed) }

    var body: some View {
        HStack(spacing: 8) {
            // Never colour alone: the icon carries the meaning too.
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
    }
}

private struct PayButton: View {
    @Environment(\.payCrossAppearance) private var style
    /// Same reason as `AmountHeader`: the button reads `Payer 12,00 €`.
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

    /// White is only right on a dark fill. The accent colour is the merchant
    /// app's to choose, and a light one left the amount and the spinner
    /// invisible on the one control the shopper has to press, so the label
    /// follows the fill's own luminance -- the rule Android has been applying
    /// since it started taking a brand colour. The disabled fill is the SDK's
    /// own grey and keeps the white it has always drawn.
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
            .frame(maxWidth: .infinity, minHeight: style.buttonHeight(or: 50))
        }
        .background(fill, in: RoundedRectangle(cornerRadius: style.buttonCornerRadius(or: 12)))
        .foregroundStyle(labelColor)
        .disabled(!isEnabled)
        .payCrossIdentifier(.payButton)
    }
}
#endif
