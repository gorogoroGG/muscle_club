import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var store: GymStore

    @State private var isSigningIn = false
    @State private var message: String? = nil
    @State private var currentNonce: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 22) {
                authHero
                authCard
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 32)
        }
        .padding(.vertical, 28)
    }

    private var authHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppPalette.accent.opacity(0.18))
                    .frame(width: 104, height: 104)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(AppPalette.accentSecondary)
            }

            Text("筋肉クラブ")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.textPrimary)

            Text("仲間と予定を共有して、ジムの継続を続けやすくするアプリです。")
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var authCard: some View {
        CardView(title: "APPLE SIGN IN") {
            VStack(alignment: .leading, spacing: 18) {
                Text("Apple ID でログイン")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.textPrimary)

                Text("ログインすると、自分の記録を安全に管理しつつ、登録メンバー全員と予定とチェックインを共有できます。")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)

                SignInWithAppleButton(.signIn, onRequest: configureAppleRequest, onCompletion: handleAppleCompletion)
                    .frame(height: 54)
                    .signInWithAppleButtonStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .disabled(!store.isSupabaseReady || isSigningIn)
                    .opacity((!store.isSupabaseReady || isSigningIn) ? 0.6 : 1)

                if isSigningIn {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppPalette.accentSecondary)
                        Text("Apple ID を確認しています")
                            .font(.footnote)
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                }

                if let message {
                    messageBlock(text: message, tint: AppPalette.accentSecondary)
                }

                if let lastErrorMessage = store.lastErrorMessage {
                    messageBlock(text: lastErrorMessage, tint: AppPalette.danger)
                }

                if !store.isSupabaseReady {
                    messageBlock(text: "Supabase の URL / ANON KEY を設定すると Apple ID ログインを開始できます。", tint: AppPalette.warning)
                }

                VStack(alignment: .leading, spacing: 10) {
                    benefitRow(systemImage: "person.2.fill", text: "登録メンバー全員の情報を見られます")
                    benefitRow(systemImage: "calendar.badge.plus", text: "予定とチェックインをすばやく共有できます")
                    benefitRow(systemImage: "shield.fill", text: "Supabase Auth と RLS でデータを制限します")
                }
            }
        }
    }

    private func benefitRow(systemImage: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(AppPalette.accent)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
        }
    }

    private func messageBlock(text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        Task { await handleAppleResult(result) }
    }

    @MainActor
    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        message = nil
        store.lastErrorMessage = nil
        defer { isSigningIn = false }

        switch result {
        case let .failure(error):
            if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled {
                message = "Apple ID ログインをキャンセルしました。"
                return
            }
            store.lastErrorMessage = error.localizedDescription
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                store.lastErrorMessage = "Apple ID の認証結果を読み取れませんでした。"
                return
            }
            guard let nonce = currentNonce else {
                store.lastErrorMessage = "Apple ID ログインの nonce を作成できませんでした。"
                return
            }
            guard let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                store.lastErrorMessage = "Apple ID のトークンを読み取れませんでした。"
                return
            }

            let displayName = Self.displayName(from: credential.fullName)
            await store.signInWithApple(identityToken: identityToken, nonce: nonce, displayName: displayName)

            if store.lastErrorMessage == nil {
                currentNonce = nil
                message = "Apple ID でログインしました。"
            }
        }
    }

    private static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}
