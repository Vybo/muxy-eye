import MuxyEyeCore
import SwiftUI

/// The panel's root: the collapsed eye or the expanded panel, as the window controller lays it out.
struct EyeRootView: View {
    enum Content: Equatable {
        case collapsed(CollapsedLayout)
        case expanded(topInset: CGFloat)
    }

    let model: AppModel
    let content: Content?
    let onExpandedHeight: (CGFloat) -> Void

    var body: some View {
        Group {
            switch content {
            case .collapsed(let layout):
                CollapsedEyeView(model: model, layout: layout)
            case .expanded(let topInset):
                ExpandedPanelView(model: model, topInset: topInset, onHeightChange: onExpandedHeight)
            case nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}
