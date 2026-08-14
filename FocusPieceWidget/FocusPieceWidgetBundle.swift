import WidgetKit
import SwiftUI

@main
struct FocusPieceWidgetBundle: WidgetBundle {
    var body: some Widget {
        FocusPieceWidget()
        FocusLiveActivity()
        // A second, iOS 18-only activity that declares the watch's `small`
        // family cannot go here: `WidgetBundleBuilder` has `buildOptional` but
        // no `buildEither`, so `if #available` works only without an `else` —
        // and registering both would leave two ActivityConfigurations for the
        // same attributes type. Declaring the family therefore needs this
        // extension's deployment target raised to iOS 18. See
        // FocusLiveActivitySmartStack.
    }
}
