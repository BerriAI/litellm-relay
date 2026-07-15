import SwiftUI

/// The top tab row of the dark-glass macOS menu bar popover.
/// One tab per coding agent: brand logo, name, and a mini usage meter.
/// The selected tab is a rounded translucent glass chip, and a small capsule
/// underline in the agent's accent color slides between tabs as you switch.
struct AgentTabBar: View {
    @ObservedObject var model: AppModel

    /// Namespace for the sliding accent underline.
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(model.agents) { agent in
                    tab(for: agent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Rectangle()
                .fill(GlassTheme.line)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func tab(for agent: AgentInfo) -> some View {
        let isActive = agent.id == model.selectedTag

        VStack(spacing: 4) {
            AgentIcon(
                resource: agent.iconResource,
                fallback: agent.fallbackText,
                size: 24
            )
            .opacity(isActive ? 1.0 : 0.6)
            .saturation(isActive ? 1.0 : 0.35)

            Text(agent.name)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : Color.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)

            meter(for: agent, isActive: isActive)

            // Sliding accent underline slot. The capsule uses
            // matchedGeometryEffect so it animates between tabs on selection.
            ZStack {
                if isActive {
                    Capsule(style: .continuous)
                        .fill(agent.accent)
                        .matchedGeometryEffect(id: "tabUnderline", in: ns)
                        .frame(width: 18, height: 2.5)
                }
            }
            .frame(height: 2.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(activeChip(isActive: isActive))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                model.selectedTag = agent.id
            }
        }
    }

    /// The active tab's translucent glass chip: a top-lit white gradient
    /// (`rgba(255,255,255,.16) → rgba(255,255,255,.06)`) with an inset white
    /// highlight along the top edge. Inactive tabs are transparent.
    @ViewBuilder
    private func activeChip(isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if isActive {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.06),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        } else {
            shape.fill(Color.clear)
        }
    }

    @ViewBuilder
    private func meter(for agent: AgentInfo, isActive: Bool) -> some View {
        // Meter is hidden on the active tab; a fixed-height slot keeps the
        // row visually aligned regardless of which tab is selected.
        GeometryReader { proxy in
            let fraction = min(max(agent.meter, 0), 1)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(GlassTheme.track)

                Capsule(style: .continuous)
                    .fill(agent.accent)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 2)
        .opacity(isActive ? 0 : 1)
    }
}
