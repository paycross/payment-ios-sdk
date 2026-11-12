#if os(iOS)
import SwiftUI

extension View {
    // WHY: SwiftUI centres a one-line TextField in its frame, leaving a band above and below it where taps reach nothing.
    // WHY: An empty tap gesture would swallow the tap that dismisses the keypad, so nil must stay nil.
    @ViewBuilder
    func tapToFocus(_ focus: (() -> Void)?) -> some View {
        if let focus {
            contentShape(Rectangle()).onTapGesture(perform: focus)
        } else {
            self
        }
    }
}
#endif
