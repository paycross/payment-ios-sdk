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
    @Binding var state: CardFormState
    let amount: Amount
    let savedCards: [SavedCard]
    let allowsSaving: Bool
    let isLoading: Bool
    let fieldGroups: [FieldGroup]
    @Binding var fieldValues: [String: [String: String]]
    let fieldErrors: [FieldGroupError]
    let onPay: () -> Void
    var showsApplePayButton: Bool = false
    var onApplePay: () -> Void = {}

    private var canPay: Bool { state.canSubmit() && !isLoading }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AmountHeader(amount: amount)

                    if showsApplePayButton {
                        ApplePayButtonView(action: onApplePay)
                            .frame(height: 48)
                            .accessibilityIdentifier("applePayButton")

                        // A separator rather than nothing: without it the card
                        // fields read as part of the Apple Pay button, and a
                        // shopper who has already decided reads "or" faster
                        // than they read a gap.
                        HStack {
                            VStack { Divider() }
                            Text("or pay with card")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            VStack { Divider() }
                        }
                    }

                    if !savedCards.isEmpty {
                        SavedCardPicker(
                            cards: savedCards,
                            selection: state.source,
                            onSelect: { send(.sourceSelected($0)) }
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
                        Toggle("Save this card", isOn: saveCardBinding)
                            .font(.subheadline)
                    }

                    if let error = state.inlineError {
                        ErrorBanner(message: error)
                    }
                }
                .padding(20)
            }

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
        .background(Color(.systemGroupedBackground))
    }

    private var newCardFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledField(title: "Cardholder Name") {
                TextField("NAME ON CARD", text: binding(\.cardholderName, event: CardFormEvent.nameChanged))
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .accessibilityIdentifier("cardholderName")
            }

            LabeledField(title: "Card Number", trailing: BrandBadge(brand: state.brand)) {
                // NOTE: Android uses KeyboardType.NumberPassword here, which
                // makes the framework withhold the field's contents from the
                // keyboard process. UIKeyboardType has no such variation, so
                // iOS has NO equivalent protection on this field today. Do not
                // record this as covered in a security review.
                TextField("1234 5678 9012 3456", text: panBinding)
                    .keyboardType(.numberPad)
                    .textContentType(.creditCardNumber)
                    .accessibilityIdentifier("cardNumber")
            }

            HStack(spacing: 12) {
                LabeledField(title: "MM/YY") {
                    TextField("12/30", text: expiryBinding)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("expiry")
                }
                cvvField
            }
        }
    }

    private var cvvField: some View {
        LabeledField(title: "CVV") {
            SecureField(String(repeating: "•", count: state.cvvBrand.cvvLength), text: cvvBinding)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("cvv")
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
    let amount: Amount

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(Amounts.formatted(amount))
                .font(.largeTitle.weight(.semibold))
                .monospacedDigit()
                .accessibilityIdentifier("amount")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LabeledField<Content: View, Trailing: View>: View {
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
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                content
                    .font(.body.monospacedDigit())
                trailing
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

extension LabeledField where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: EmptyView(), content: content)
    }
}

private struct BrandBadge: View {
    let brand: CardBrand

    var body: some View {
        Text(brand == .unknown ? "" : brand.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("brand")
    }
}

private struct SavedCardPicker: View {
    let cards: [SavedCard]
    let selection: CardEntrySource
    let onSelect: (CardEntrySource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cards) { card in
                row(
                    label: "\(card.brand.displayName) •••• \(card.last4)",
                    detail: card.expiryLabel,
                    isSelected: selection == .saved(card),
                    action: { onSelect(.saved(card)) }
                )
            }
            row(
                label: "Use a new card",
                detail: nil,
                isSelected: selection.isNewCard,
                action: { onSelect(.newCard) }
            )
        }
    }

    private func row(
        label: String,
        detail: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(label)
                Spacer()
                if let detail {
                    Text(detail).foregroundStyle(.secondary).font(.footnote)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            // Never colour alone: the icon carries the meaning too.
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(.footnote)
        .foregroundStyle(Color(.systemRed))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemRed).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("errorBanner")
    }
}

private struct PayButton: View {
    let amount: Amount
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Pay \(Amounts.formatted(amount))")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .background(isEnabled ? Color.accentColor : Color.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.white)
        .disabled(!isEnabled)
        .accessibilityIdentifier("payButton")
    }
}
#endif
