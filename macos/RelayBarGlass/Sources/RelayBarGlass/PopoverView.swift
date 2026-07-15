import SwiftUI

/// Dark-glass popover: agent tab row on top, one tab-driven per-tool card below.
struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            AgentTabBar(model: model)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    UsageCard(model: model)
                    footerBar
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: 560)
        }
        .frame(width: 400)
        .background(GlassBackground())
        .environment(\.colorScheme, .dark)
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            footerButton("Dashboard", "safari") { model.openDashboard() }
            Spacer()
            footerButton("Quit", "power") { model.quit() }
        }
        .padding(.top, 2)
    }

    private func footerButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(GlassTheme.caption.weight(.medium))
            }
            .foregroundStyle(GlassTheme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
