#if os(iOS)
import SwiftUI
import PayCrossCore

struct SavedCardPicker: View {
    @Environment(\.payCrossAppearance) private var style
    let cards: [SavedCard]
    let selection: CardEntrySource
    let allowsRemoval: Bool
    let isPaying: Bool
    let onSelect: (CardEntrySource) -> Void
    let onRemoveRequested: (SavedCard) -> Void

    private var offersRemoval: Bool { allowsRemoval && !isPaying }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cards) { card in
                row(
                    label: card.rowTitle,
                    detail: card.expiryLabel,
                    identifier: PayCrossTestIdentifiers.savedCard(card.id),
                    isSelected: selection == .saved(card),
                    action: { onSelect(.saved(card)) },
                    remove: offersRemoval ? { onRemoveRequested(card) } : nil,
                    removeIdentifier: PayCrossTestIdentifiers.savedCardDelete(card.id)
                )
            }
            row(
                label: L("paycross_use_a_new_card", "Use a new card"),
                detail: nil,
                identifier: PayCrossTestIdentifiers.useNewCard.rawValue,
                isSelected: selection.isNewCard,
                action: { onSelect(.newCard) }
            )
        }
        .payCrossContainerIdentifier(.savedCards)
    }

    private func row(
        label: String,
        detail: String?,
        identifier: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        remove: (() -> Void)? = nil,
        removeIdentifier: String = ""
    ) -> some View {
        // WHY: Nested buttons share one tap area in SwiftUI, so the trash is a sibling of the selection button.
        HStack(spacing: 0) {
            Button(action: action) {
                HStack {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(
                            isSelected
                                ? style.foreground(\.brand, default: Color.accentColor)
                                : style.foreground(\.icon, default: .secondary)
                        )
                    Text(label)
                        .font(style.font(.body))
                    Spacer()
                    if let detail {
                        Text(detail)
                            .foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
                            .font(style.font(.footnote))
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityIdentifier(identifier)

            if let remove {
                Button(action: remove) {
                    Image(systemName: "trash")
                        .foregroundStyle(style.foreground(\.icon, default: .secondary))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    L("paycross_remove_card", "Remove card, %@", label)
                )
                .accessibilityIdentifier(removeIdentifier)
            }
        }
        .payCrossComponentBackground(style)
    }
}
#endif
