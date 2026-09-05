#if os(iOS)
import SwiftUI
import PayCrossCore

/// The stored-card rows, plus the row that switches back to card entry.
///
/// Holds no state and no logic. Selecting a card and asking to delete one both
/// leave through a closure; what they mean is decided in Core and in the sheet.
/// The delete confirmation lives on the sheet beside the cancel confirmation,
/// because both are the sheet asking the shopper to stand behind something.
struct SavedCardPicker: View {
    let cards: [SavedCard]
    let selection: CardEntrySource
    let allowsRemoval: Bool
    /// A payment is in flight. The trash goes away rather than going dead: a
    /// control that is still there and does nothing reads as a broken sheet.
    let isPaying: Bool
    let onSelect: (CardEntrySource) -> Void
    /// Reports that the shopper pressed the trash. Nothing is deleted here: the
    /// sheet raises the confirmation and only then calls the server.
    let onRemoveRequested: (SavedCard) -> Void

    private var offersRemoval: Bool { allowsRemoval && !isPaying }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cards) { card in
                row(
                    label: "\(card.brand.displayName) •••• \(card.last4)",
                    detail: card.expiryLabel,
                    identifier: "paycross.savedCard.\(card.id)",
                    isSelected: selection == .saved(card),
                    action: { onSelect(.saved(card)) },
                    remove: offersRemoval ? { onRemoveRequested(card) } : nil,
                    removeIdentifier: "paycross.savedCard.\(card.id).delete"
                )
            }
            row(
                label: L("paycross_use_a_new_card", "Use a new card"),
                detail: nil,
                identifier: "paycross.savedCard.new",
                isSelected: selection.isNewCard,
                action: { onSelect(.newCard) }
            )
        }
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
        // Siblings rather than a delete button nested inside the selection
        // button: a tap landing on the wrong one of two overlapping controls
        // either charges a card the shopper meant to delete or deletes one they
        // meant to pay with.
        HStack(spacing: 0) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityIdentifier(identifier)

            if let remove {
                Button(action: remove) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        // The row is 44pt tall; the trash matches it, so the
                        // target is a target rather than a glyph.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Named after the row it belongs to. Every trash on the screen
                // is otherwise the same control to VoiceOver, on a screen whose
                // whole point is telling the cards apart.
                .accessibilityLabel(
                    String(format: L("paycross_remove_card", "Remove card, %@"), label)
                )
                .accessibilityIdentifier(removeIdentifier)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
