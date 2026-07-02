import SwiftUI
import UIKit

private enum MyPageModal: String, Identifiable {
    case gymLocation

    var id: String { rawValue }
}

struct MyPageView: View {
    @EnvironmentObject private var store: GymStore
    @Environment(\.openURL) private var openURL

    @State private var activeModal: MyPageModal? = nil

    var body: some View {
        AppScrollContainer {
            ScreenTitleView(
                eyebrow: "PROFILE",
                title: store.currentUser.name,
                subtitle: store.currentUserEmail ?? "Apple ID でログイン中"
            )

            ProfileHeroCard(member: store.currentUser)
            CheckInAutomationCard(
                openMapPicker: { activeModal = .gymLocation },
                openSettings: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            )
            AccountCard(email: store.currentUserEmail, lastErrorMessage: store.lastErrorMessage) {
                Task {
                    await store.signOut()
                }
            }
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .gymLocation:
                GymLocationPickerSheet()
                    .environmentObject(store)
            }
        }
    }
}

private struct ProfileHeroCard: View {
    let member: Member

    var body: some View {
        CardView(title: "ACCOUNT") {
            HStack(spacing: 16) {
                AvatarView(member: member, size: 74)

                Text(member.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.textPrimary)

                Spacer()
            }
        }
    }
}

private struct CheckInAutomationCard: View {
    @EnvironmentObject private var store: GymStore

    let openMapPicker: () -> Void
    let openSettings: () -> Void

    var body: some View {
        CardView(title: "CHECK-IN") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("自動チェックイン")
                        .font(.headline)
                        .foregroundStyle(AppPalette.textPrimary)

                    Spacer()

                    AppBadgeView(
                        text: store.isAutomaticCheckInEnabled ? "AUTO" : "未設定",
                        tint: store.isAutomaticCheckInEnabled ? AppPalette.accentSecondary : AppPalette.warning
                    )
                }

                Text(store.checkInModeDescription)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)

                if let gymLocation = store.gymLocation {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("登録済みジム")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.textSecondary)
                        Text(gymLocation.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppPalette.textPrimary)
                        Text("半径 \(Int(gymLocation.radiusMeters))m で判定します")
                            .font(.caption)
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                } else {
                    Text("まだジムは登録されていません。マップで場所を選ぶと、自動チェックインの基準地点になります。")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                }

                Button("マップでジムを登録") {
                    openMapPicker()
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppPalette.accentSecondary))

                if store.shouldShowOpenLocationSettings {
                    Button("位置情報を設定で許可", action: openSettings)
                        .buttonStyle(SecondaryActionButtonStyle(tint: AppPalette.warning))
                } else if !store.isLocationAuthorized {
                    Button("位置情報を許可する") {
                        store.requestLocationPermission()
                    }
                    .buttonStyle(SecondaryActionButtonStyle(tint: AppPalette.accent))
                }

                if store.gymLocation != nil {
                    Button("登録済みジムを削除") {
                        store.clearGymLocation()
                    }
                    .buttonStyle(GhostActionButtonStyle())
                }
            }
        }
    }
}

private struct AccountCard: View {
    let email: String?
    let lastErrorMessage: String?
    let onLogout: () -> Void

    var body: some View {
        CardView(title: "SESSION") {
            VStack(alignment: .leading, spacing: 14) {
                Text("アカウント")
                    .font(.headline)
                    .foregroundStyle(AppPalette.textPrimary)

                Text(email ?? "Apple ID でログイン中")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)

                if let lastErrorMessage, !lastErrorMessage.isEmpty {
                    Text(lastErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(AppPalette.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppPalette.danger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button("ログアウト", action: onLogout)
                    .buttonStyle(SecondaryActionButtonStyle(tint: AppPalette.danger))
            }
        }
    }
}

#Preview {
    MyPageView()
        .environmentObject(GymStore())
}
