import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: GymStore

    var body: some View {
        ZStack {
            AppBackground()

            switch store.appMode {
            case .signedIn:
                ContentView()
            case .signedOut:
                AuthView()
            case .loading:
                LoadingStateView()
            case let .failed(message):
                if store.hasAuthSession {
                    FailedStateView(
                        message: message,
                        onRetry: store.reload,
                        onSignOut: {
                            Task {
                                await store.signOut()
                            }
                        }
                    )
                } else {
                    AuthView()
                }
            }
        }
    }
}

private struct FailedStateView: View {
    let message: String
    let onRetry: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AppPalette.warning)

            Text("データを開けませんでした")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppPalette.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button("もう一度読み込む", action: onRetry)
                    .buttonStyle(PrimaryActionButtonStyle(tint: AppPalette.accentSecondary))

                Button("ログアウトする", action: onSignOut)
                    .buttonStyle(SecondaryActionButtonStyle(tint: AppPalette.danger))
            }
        }
        .padding(28)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AppPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(AppPalette.stroke, lineWidth: 1)
        )
        .padding(24)
    }
}

private struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(AppPalette.accentSecondary)
                .scaleEffect(1.2)

            Text("同期しています")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppPalette.textPrimary)

            Text("アカウントとトレーニング記録を読み込んでいます。")
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AppPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(AppPalette.stroke, lineWidth: 1)
        )
        .padding(24)
    }
}
