import MuxyEyeCore
import SwiftUI

/// The left rail: every agent session, waiting first, with a mini eye, the project and a subtitle.
/// Its rows cascade in while `revealed` turns true and fade out when it turns false. New rows slide
/// in, cleared ones fade and close up, and the selection highlight slides between rows.
struct SessionRailView: View {
    let model: AppModel
    let revealed: Bool
    let onContentHeight: (CGFloat) -> Void

    @Namespace private var selection

    var body: some View {
        let motion = PanelMotion()
        ScrollView(.vertical) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let state = model.state
                let rail = state.rail
                VStack(spacing: 2) {
                    ForEach(Array(rail.enumerated()), id: \.element.id) { index, record in
                        Button {
                            model.select(record.id)
                        } label: {
                            SessionRailRow(
                                name: SessionPresentation.displayName(for: record),
                                subtitle: SessionPresentation.railSubtitle(for: record, in: state, now: context.date),
                                mode: Self.mode(of: record, in: state),
                                isSelected: record.id == model.selectedSession,
                                selection: selection
                            )
                        }
                        .buttonStyle(.plain)
                        .reveal(revealed, show: motion.rowIn(index), hide: motion.contentOut, slide: motion.contentSlide)
                        .transition(Self.rowTransition)
                    }
                }
                .padding(6)
                .animation(motion.railChange.animation, value: rail.map(\.id))
                .animation(motion.selection.animation, value: model.selectedSession)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onContentHeight($0) }
        }
        .scrollIndicators(.never)
    }

    /// A new row slides in from the rail's edge; a cleared one fades and shrinks as the rows close up.
    private static let rowTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading))
    )

    static func mode(of record: SessionRecord, in state: EyeState) -> EyeMode {
        if state.isWaiting(record) { return .waiting }
        return record.muxyState == .working ? .working : .idle
    }
}

private struct SessionRailRow: View {
    let name: String
    let subtitle: String
    let mode: EyeMode
    let isSelected: Bool
    /// Where the selection highlight slides between rows.
    let selection: Namespace.ID

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 7) {
            MiniEyeView(mode: mode)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
                Text(verbatim: subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelTheme.secondaryText)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                shape
                    .fill(PanelTheme.card)
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(shape)
    }
}

/// A static, small eye: an orange ring when waiting, a line when working, a dim dot when idle.
struct MiniEyeView: View {
    private static let size: CGFloat = 16

    let mode: EyeMode

    var body: some View {
        ZStack {
            Circle()
                .fill(PanelTheme.eye)
                .overlay(Circle().strokeBorder(PanelTheme.divider, lineWidth: 1))
            switch mode {
            case .waiting:
                Circle()
                    .strokeBorder(PanelTheme.waiting, lineWidth: 1.8)
                    .padding(3)
            case .working:
                Capsule()
                    .fill(PanelTheme.line)
                    .frame(width: Self.size * 0.55, height: 1.6)
            case .idle:
                Circle()
                    .fill(PanelTheme.line.opacity(0.35))
                    .frame(width: 3, height: 3)
            }
        }
        .frame(width: Self.size, height: Self.size)
    }
}
