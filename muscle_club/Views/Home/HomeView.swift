import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var store: GymStore

    @State private var showNotifications = false
    @State private var showCancelCheckInPopup = false
    @State private var showCancelCheckOutPopup = false
    @State private var showGymLocationSheet = false
    @State private var showRippleEffect = false

    var body: some View {
        AppScrollContainer {
            HomeHeader(unreadCount: store.unreadNotificationCount) {
                showNotifications = true
            }

            if !store.isAutomaticCheckInEnabled {
                AutoCheckInSetupBanner {
                    handleBannerTap()
                }
            }

            TodayIntentToggle(
                isGoing: store.isCurrentUserGoing,
                isNotGoing: store.isCurrentUserNotGoing,
                isLocked: store.isCurrentUserCheckedIn,
                onToggleGoing: store.toggleGoing,
                onToggleNotGoing: store.toggleNotGoing
            )

            CheckInStatusCard(
                status: store.todayStatus(for: store.currentUser.id),
                onTapCheckedIn: { showCancelCheckInPopup = true },
                onTapCheckedOut: { showCancelCheckOutPopup = true }
            )

            GymPresenceMapCard(
                checkedInMembers: store.todayCheckedInMembers,
                checkedOutMembers: store.todayCheckedOutMembers,
                goingNotArrivedMembers: store.todayGoingNotArrivedMembers
            )

            SummaryCard(
                monthCount: store.currentUserMonthCount,
                streak: store.currentStreak,
                monthMinutes: store.currentUserMonthMinutes
            )
        }
        .overlay {
            if showRippleEffect {
                RippleEffectView()
            }
        }
        .appPopup(isPresented: $showCancelCheckInPopup) {
            PopupCard(
                title: "チェックインを取り消しますか?",
                message: "自動チェックインが誤って記録された場合に取り消せます。"
            ) {
                Button("チェックインを取り消す") {
                    store.cancelCheckIn()
                    showCancelCheckInPopup = false
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: AppPalette.danger))

                Button("閉じる") {
                    showCancelCheckInPopup = false
                }
                .buttonStyle(GhostActionButtonStyle())
            }
        }
        .appPopup(isPresented: $showCancelCheckOutPopup) {
            PopupCard(
                title: "チェックアウトを取り消しますか?",
                message: "今日のチェックアウト記録を削除して、元の状態に戻します。"
            ) {
                Button("チェックアウトを取り消す") {
                    store.cancelCheckOut()
                    showCancelCheckOutPopup = false
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: AppPalette.warning))

                Button("閉じる") {
                    showCancelCheckOutPopup = false
                }
                .buttonStyle(GhostActionButtonStyle())
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationCenterSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showGymLocationSheet) {
            GymLocationPickerSheet()
                .environmentObject(store)
        }
        .onChange(of: store.isCurrentUserCheckedIn) { _, isCheckedIn in
            guard isCheckedIn else { return }
            triggerRippleEffect()
        }
    }

    private func handleBannerTap() {
        if store.gymLocation == nil {
            showGymLocationSheet = true
        } else if store.shouldShowOpenLocationSettings {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            store.requestLocationPermission()
        }
    }

    private func triggerRippleEffect() {
        showRippleEffect = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            showRippleEffect = false
        }
    }
}

private struct HomeHeader: View {
    let unreadCount: Int
    let onNotificationsTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScreenTitleView(eyebrow: "TODAY", title: "今日のジム")

            Button(action: onNotificationsTap) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppPalette.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )

                    if unreadCount > 0 {
                        Text("\(min(unreadCount, 9))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(AppPalette.danger)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("通知")
        }
    }
}

private struct AutoCheckInSetupBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "location.slash.fill")
                    .font(.headline)
                    .foregroundStyle(AppPalette.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text("自動チェックイン設定をしてください")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)
                    Text("タップしてジムの場所や位置情報を設定します")
                        .font(.caption)
                        .foregroundStyle(AppPalette.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(AppPalette.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppPalette.warning.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppPalette.warning.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TodayIntentToggle: View {
    let isGoing: Bool
    let isNotGoing: Bool
    let isLocked: Bool
    let onToggleGoing: () -> Void
    let onToggleNotGoing: () -> Void

    var body: some View {
        CardView(title: "今日の予定") {
            HStack(spacing: 12) {
                if !isNotGoing {
                    IntentButton(
                        title: "参加",
                        systemImage: "figure.walk",
                        tint: AppPalette.danger,
                        isExpanded: isGoing,
                        isDisabled: isLocked,
                        action: onToggleGoing
                    )
                }
                if !isGoing {
                    IntentButton(
                        title: "不参加",
                        systemImage: "xmark",
                        tint: AppPalette.accent,
                        isExpanded: isNotGoing,
                        isDisabled: isLocked,
                        action: onToggleNotGoing
                    )
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isGoing)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isNotGoing)
        }
    }
}

private struct IntentButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isExpanded: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: isExpanded ? 34 : 18, weight: .bold))
                Text(title)
                    .font(isExpanded ? .system(size: 30, weight: .heavy, design: .rounded) : .headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: isExpanded ? 132 : 84)
            .foregroundStyle(isExpanded ? Color.white : tint)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isExpanded ? tint : tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(tint.opacity(isExpanded ? 0 : 0.4), lineWidth: 1.5)
            )
            .opacity(isDisabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct CheckInStatusCard: View {
    let status: GymStore.TodayGymStatus?
    let onTapCheckedIn: () -> Void
    let onTapCheckedOut: () -> Void

    var body: some View {
        CardView(title: "CHECK-IN") {
            VStack(spacing: 10) {
                switch status {
                case .checkedIn:
                    StatusCircle(size: 148, fill: AppPalette.danger, systemImage: "checkmark", label: "チェックイン済み")
                    StatusActionButton(
                        title: "チェックインを取り消す",
                        tint: AppPalette.danger,
                        action: onTapCheckedIn
                    )
                case .checkedOut:
                    StatusCircle(
                        size: 108,
                        fill: AppPalette.textSecondary.opacity(0.24),
                        systemImage: "arrow.uturn.backward",
                        label: "チェックアウト済み"
                    )
                    StatusActionButton(
                        title: "チェックアウトを取り消す",
                        tint: AppPalette.warning,
                        action: onTapCheckedOut
                    )
                default:
                    StatusCircle(size: 84, fill: Color.clear, strokeColor: AppPalette.stroke, systemImage: "location", label: "未チェックイン")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StatusCircle: View {
    var size: CGFloat
    var fill: Color
    var strokeColor: Color? = nil
    let systemImage: String
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: size, height: size)

                if let strokeColor {
                    Circle()
                        .strokeBorder(strokeColor, lineWidth: 2)
                        .frame(width: size, height: size)
                }

                Image(systemName: systemImage)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(strokeColor != nil ? AppPalette.textSecondary : Color.white)
            }

            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)
        }
    }
}

private struct StatusActionButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(SecondaryActionButtonStyle(tint: tint))
        .accessibilityLabel(title)
    }
}

private struct RippleEffectView: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(AppPalette.danger.opacity(0.6), lineWidth: 3)
                        .frame(width: 120, height: 120)
                        .scaleEffect(animate ? 3.2 : 0.2)
                        .opacity(animate ? 0 : 0.85)
                        .animation(
                            .easeOut(duration: 1.2).delay(Double(index) * 0.18),
                            value: animate
                        )
                }
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
        .onAppear { animate = true }
    }
}

private struct GymPresenceMapCard: View {
    let checkedInMembers: [Member]
    let checkedOutMembers: [Member]
    let goingNotArrivedMembers: [Member]

    private var isEmpty: Bool {
        checkedInMembers.isEmpty && checkedOutMembers.isEmpty && goingNotArrivedMembers.isEmpty
    }

    var body: some View {
        CardView(title: "TODAY") {
            VStack(alignment: .leading, spacing: 16) {
                Text("今日の様子")
                    .font(.headline)
                    .foregroundStyle(AppPalette.textPrimary)

                if isEmpty {
                    Text("今日はまだ参加予定の人がいません。")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                } else {
                    ZStack(alignment: .bottomTrailing) {
                        GymCircleView(members: checkedInMembers)

                        if !checkedOutMembers.isEmpty {
                            CheckedOutClusterView(members: checkedOutMembers)
                                .offset(x: 12, y: 12)
                        }
                    }

                    if !goingNotArrivedMembers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("まだ到着していません")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppPalette.textSecondary)

                            FlowLayout(spacing: 10) {
                                ForEach(goingNotArrivedMembers) { member in
                                    MemberChip(member: member)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct GymCircleView: View {
    let members: [Member]

    var body: some View {
        ZStack {
            Circle()
                .fill(AppPalette.accentSecondary.opacity(0.14))
                .overlay(
                    Circle().strokeBorder(AppPalette.accentSecondary.opacity(0.5), lineWidth: 2)
                )
                .frame(width: 220, height: 220)

            if members.isEmpty {
                Text("GYM")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(AppPalette.textSecondary)
            } else {
                FlowLayout(spacing: 10) {
                    ForEach(members) { member in
                        MemberChip(member: member)
                    }
                }
                .frame(width: 170)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct CheckedOutClusterView: View {
    let members: [Member]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: -10) {
                ForEach(members.prefix(4)) { member in
                    AvatarView(member: member, size: 32)
                        .overlay(Circle().strokeBorder(AppPalette.backgroundBottom, lineWidth: 2))
                }
            }
            Text("チェックアウト済み")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.textSecondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.surfaceStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppPalette.stroke, lineWidth: 1)
        )
    }
}

private struct MemberChip: View {
    let member: Member

    var body: some View {
        VStack(spacing: 4) {
            AvatarView(member: member, size: 40)
            Text(member.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)
                .lineLimit(1)
        }
        .frame(width: 52)
    }
}

private struct SummaryCard: View {
    let monthCount: Int
    let streak: Int
    let monthMinutes: Int

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var minutesLabel: String {
        let hours = monthMinutes / 60
        let minutes = monthMinutes % 60
        return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分"
    }

    var body: some View {
        CardView(title: "SUMMARY") {
            VStack(alignment: .leading, spacing: 12) {
                Text("今月のサマリー")
                    .font(.headline)
                    .foregroundStyle(AppPalette.textPrimary)

                LazyVGrid(columns: columns, spacing: 10) {
                    AppMetricTile(label: "今月", value: "\(monthCount)回", tint: AppPalette.accent, systemImage: "calendar")
                    AppMetricTile(label: "連続", value: "\(streak)日", tint: AppPalette.warning, systemImage: "flame.fill")
                    AppMetricTile(label: "滞在時間", value: minutesLabel, tint: AppPalette.accentSecondary, systemImage: "clock.fill")
                }
            }
        }
    }
}

private struct NotificationCenterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GymStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.notifications.isEmpty {
                        EmptyStateView(
                            title: "まだ通知はありません",
                            message: "参加予定やチェックイン、チャットがあると、ここに通知が届きます。",
                            systemImage: "bell.slash"
                        )
                    } else {
                        ForEach(store.notifications) { notification in
                            NotificationRow(notification: notification)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(AppBackground())
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .tint(AppPalette.textPrimary)
                }
            }
        }
        .onAppear {
            store.markNotificationsRead()
        }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 40, height: 40)

                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(notification.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    if notification.isUnread {
                        Circle()
                            .fill(AppPalette.danger)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(notification.message)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)

                Text(notification.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(AppPalette.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppPalette.stroke, lineWidth: 1)
        )
    }

    private var symbol: String {
        switch notification.type {
        case .going:
            return "figure.walk"
        case .notGoing:
            return "figure.wave"
        case .checkedIn:
            return "checkmark.circle.fill"
        case .checkedOut:
            return "rectangle.portrait.and.arrow.right.fill"
        case .checkInCancelled:
            return "xmark.circle.fill"
        case .chatMessage:
            return "message.fill"
        }
    }

    private var tint: Color {
        switch notification.type {
        case .going, .checkedIn:
            return AppPalette.danger
        case .notGoing:
            return AppPalette.accent
        case .checkedOut:
            return AppPalette.warning
        case .checkInCancelled:
            return AppPalette.warning
        case .chatMessage:
            return AppPalette.accentSecondary
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(GymStore())
}
