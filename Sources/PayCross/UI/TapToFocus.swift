#if os(iOS)
import SwiftUI

extension View {
    /// Makes the whole box focus the control drawn inside it.
    ///
    /// SwiftUI centres a one-line `TextField` inside whatever frame it is given
    /// rather than filling it, so a box tall enough to be a touch target still
    /// leaves a band above and below the control where a tap reaches nothing.
    /// This claims that band, and the horizontal padding with it.
    ///
    /// Nil is not the same as an empty closure, and is what the UIKit-backed
    /// fields and the option pickers pass: those fill or handle their own box,
    /// and a gesture that did nothing would eat the tap the sheet uses to put
    /// the keypad away.
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
