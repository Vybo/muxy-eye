import MuxyEyeCore
import SwiftUI

/// The left rail: every agent session, waiting first, with a mini eye, the project and a subtitle.
struct SessionRailView: View {
    let model: AppModel
    let onContentHeight: (CGFloat) -> Void

    var body: some View {
        ScrollView(.vertical) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let state = model.state
                VStack(spacing: 2) {
                    ForEach(state.rail) { record in
                        Button {
                            model.selectedSession = record.id
                        } label: {
                            SessionRailRow(
                                name: SessionPresentation.displayName(for: record),
                                subtitle: SessionPresentation.railSubtitle(for: record, in: state, now: context.date),
                                mode: Self.mode(of: record, in: state),
                                isSelected: record.id == model.selectedSession
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onContentHeight($0) }
        }
        .scrollIndicators(.never)
    }

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

    var body: some View {
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
        .background(isSelected ? PanelTheme.card : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
