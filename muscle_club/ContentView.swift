import SwiftUI

private enum AppTab: String, CaseIterable, Identifiable {
    case home
    case chat
    case record
    case myPage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "ホーム"
        case .chat: "チャット"
        case .record: "記録"
        case .myPage: "マイ"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .chat: "message.fill"
        case .record: "chart.bar.fill"
        case .myPage: "person.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        currentTab
        .safeAreaInset(edge: .bottom) {
            AppTabBar(selectedTab: $selectedTab)
        }
    }

    @ViewBuilder
    private var currentTab: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .chat:
            ChatView()
        case .record:
            RecordView()
        case .myPage:
            MyPageView()
        }
    }
}

private struct AppTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .bold))
                        Text(tab.title)
                        .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.black.opacity(0.84) : AppPalette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selectedTab == tab ? AppPalette.accentSecondary : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(Color.clear)
    }
}

#Preview {
    ContentView()
        .environmentObject(GymStore())
}
