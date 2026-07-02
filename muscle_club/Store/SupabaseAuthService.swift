import Foundation
import Security

struct SupabaseAuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String?
    let user: SupabaseAuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case user
    }
}

struct SupabaseAuthUser: Codable {
    let id: UUID
    let email: String?
}

final class SupabaseAuthService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let keychain: SupabaseSessionKeychain

    private(set) var sessionState: SupabaseAuthSession? {
        didSet {
            if let sessionState {
                keychain.save(sessionState)
            } else {
                keychain.clear()
            }
        }
    }

    init(
        session: URLSession = SupabaseAuthService.makeSession(),
        keychain: SupabaseSessionKeychain = .init(service: "muscle_club.supabase.auth")
    ) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.keychain = keychain
        self.sessionState = keychain.load()
    }

    var isSignedIn: Bool {
        sessionState != nil
    }

    var currentUserID: UUID? {
        sessionState?.user.id
    }

    var currentUserEmail: String? {
        sessionState?.user.email
    }

    func sendMagicLink(email: String, redirectTo: URL) async throws {
        let body = SupabaseMagicLinkRequest(
            email: email,
            createUser: true,
            options: SupabaseMagicLinkOptions(emailRedirectTo: redirectTo.absoluteString)
        )
        _ = try await requestAuthData(
            path: "otp",
            method: "POST",
            body: body
        )
    }

    func signInWithApple(identityToken: String, nonce: String) async throws -> SupabaseAuthSession {
        let body = SupabaseIDTokenRequest(
            provider: "apple",
            idToken: identityToken,
            token: identityToken,
            nonce: nonce
        )
        let session: SupabaseAuthSession = try await requestAuth(
            path: "token",
            queryItems: [URLQueryItem(name: "grant_type", value: "id_token")],
            method: "POST",
            body: body
        )
        sessionState = session
        return session
    }

    func refreshSession() async throws -> SupabaseAuthSession {
        guard let refreshToken = sessionState?.refreshToken else {
            throw SupabaseAuthError.missingRefreshToken
        }

        let session: SupabaseAuthSession = try await requestAuth(
            path: "token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: SupabaseRefreshTokenRequest(refreshToken: refreshToken)
        )
        sessionState = session
        return session
    }

    func handleIncomingURL(_ url: URL) async throws -> SupabaseAuthSession {
        if let session = extractDirectSession(from: url) {
            sessionState = session
            return session
        }

        let queryItems = SupabaseURLParts(url: url).items
        let tokenHash = queryItems["token_hash"]
        let code = queryItems["code"]
        let type = queryItems["type"] ?? "magiclink"

        if let token = tokenHash ?? code {
            let body = SupabaseVerifyRequest(type: type, tokenHash: tokenHash, token: token)
            let session: SupabaseAuthSession = try await requestAuth(
                path: "verify",
                method: "POST",
                body: body
            )
            sessionState = session
            return session
        }

        throw SupabaseAuthError.invalidCallbackURL
    }

    func revokeCurrentSession(using accessToken: String) async {
        guard
            let baseURL = SupabaseConfig.baseURL,
            let anonKey = SupabaseConfig.anonKey
        else {
            return
        }

        var request = URLRequest(
            url: baseURL
                .appendingPathComponent("auth")
                .appendingPathComponent("v1")
                .appendingPathComponent("logout")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        _ = try? await session.data(for: request)
    }

    func clearSessionLocally() {
        sessionState = nil
    }

    func signInRedirectURL() -> URL? {
        URL(string: "muscleclub://auth-callback")
    }

    private func extractDirectSession(from url: URL) -> SupabaseAuthSession? {
        let parts = SupabaseURLParts(url: url)
        guard
            let accessToken = parts.items["access_token"],
            let refreshToken = parts.items["refresh_token"],
            let tokenType = parts.items["token_type"],
            let userIDString = parts.items["user_id"],
            let userID = UUID(uuidString: userIDString)
        else { return nil }

        let email = parts.items["email"]
        return SupabaseAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            user: SupabaseAuthUser(id: userID, email: email)
        )
    }

    private func requestAuth<T: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Body
    ) async throws -> T {
        guard let baseURL = SupabaseConfig.baseURL, let anonKey = SupabaseConfig.anonKey else {
            throw SupabaseAuthError.notConfigured
        }

        let authURL = baseURL
            .appendingPathComponent("auth")
            .appendingPathComponent("v1")
            .appendingPathComponent(path)
        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw SupabaseAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(AnyEncodable(body))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = SupabaseAuthErrorEnvelope.decode(from: data)?.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw SupabaseAuthError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func requestAuthData<Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Body
    ) async throws {
        guard let baseURL = SupabaseConfig.baseURL, let anonKey = SupabaseConfig.anonKey else {
            throw SupabaseAuthError.notConfigured
        }

        let authURL = baseURL
            .appendingPathComponent("auth")
            .appendingPathComponent("v1")
            .appendingPathComponent(path)
        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw SupabaseAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(AnyEncodable(body))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = SupabaseAuthErrorEnvelope.decode(from: data)?.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw SupabaseAuthError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }
}

enum SupabaseAuthError: LocalizedError {
    case notConfigured
    case invalidResponse
    case invalidCallbackURL
    case missingRefreshToken
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase の設定がまだ入っていません。"
        case .invalidResponse:
            return "Supabase から不正な応答が返りました。"
        case .invalidCallbackURL:
            return "ログイン用の戻りURLを解釈できませんでした。"
        case .missingRefreshToken:
            return "ログイン情報の更新トークンが見つかりませんでした。"
        case let .requestFailed(statusCode, message):
            return "Supabase Auth error \(statusCode): \(message)"
        }
    }
}

private struct SupabaseMagicLinkRequest: Encodable {
    let email: String
    let createUser: Bool
    let options: SupabaseMagicLinkOptions

    enum CodingKeys: String, CodingKey {
        case email
        case createUser = "create_user"
        case options
    }
}

private struct SupabaseMagicLinkOptions: Encodable {
    let emailRedirectTo: String

    enum CodingKeys: String, CodingKey {
        case emailRedirectTo = "email_redirect_to"
    }
}

private struct SupabaseVerifyRequest: Encodable {
    let type: String
    let tokenHash: String?
    let token: String?

    enum CodingKeys: String, CodingKey {
        case type
        case tokenHash = "token_hash"
        case token
    }
}

private struct SupabaseIDTokenRequest: Encodable {
    let provider: String
    let idToken: String
    let token: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case token
        case nonce
    }
}

private struct SupabaseRefreshTokenRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct SupabaseAuthErrorEnvelope: Decodable {
    let message: String?

    static func decode(from data: Data) -> SupabaseAuthErrorEnvelope? {
        try? JSONDecoder().decode(SupabaseAuthErrorEnvelope.self, from: data)
    }
}

private struct SupabaseURLParts {
    let items: [String: String]

    init(url: URL) {
        var values: [String: String] = [:]

        func append(from componentString: String?) {
            guard let componentString else { return }
            let components = URLComponents(string: "?\(componentString)")
            for item in components?.queryItems ?? [] {
                if let value = item.value {
                    values[item.name] = value
                }
            }
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for item in components?.queryItems ?? [] {
            if let value = item.value {
                values[item.name] = value
            }
        }
        append(from: components?.fragment)
        items = values
    }
}

struct SupabaseSessionKeychain {
    let service: String
    private let account = "session"

    func save(_ session: SupabaseAuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> SupabaseAuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(SupabaseAuthSession.self, from: data)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        self.encodeClosure = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
