import Foundation
import Security

struct SupabaseGymSnapshot {
    let members: [Member]
    let attendanceRecords: [AttendanceRecord]
    let gymVisits: [GymVisit]
    let chatMessages: [ChatMessage]
}

enum SupabaseConfig {
    private static let placeholderURL = "https://YOUR_PROJECT.supabase.co"
    private static let placeholderAnonKey = "YOUR_SUPABASE_ANON_KEY"

    static var baseURL: URL? {
        let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
            ?? ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? ""
        guard !value.isEmpty, value != placeholderURL else { return nil }
        return URL(string: value)
    }

    static var anonKey: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ""
        guard !value.isEmpty, value != placeholderAnonKey else { return nil }
        return value
    }
}

struct SupabaseGymService {
    static let live = SupabaseGymService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    var authToken: String?

    init(session: URLSession = SupabaseGymService.makeSession()) {
        self.session = session
        self.decoder = .supabase
        self.encoder = .supabase
        self.authToken = nil
    }

    var isConfigured: Bool {
        SupabaseConfig.baseURL != nil && SupabaseConfig.anonKey != nil
    }

    func loadSnapshot() async throws -> SupabaseGymSnapshot {
        guard isConfigured else {
            throw SupabaseError.notConfigured
        }

        async let members: [Member] = fetchMembers()
        async let attendanceRecords: [AttendanceRecord] = fetchAttendanceRecords()
        async let gymVisits: [GymVisit] = fetchGymVisits()
        async let chatMessages: [ChatMessage] = fetchChatMessages()

        return try await SupabaseGymSnapshot(
            members: members,
            attendanceRecords: attendanceRecords,
            gymVisits: gymVisits,
            chatMessages: chatMessages
        )
    }

    func fetchCurrentMember(memberID: UUID) async throws -> Member? {
        let rows: [MemberRow] = try await fetch(
            path: "members",
            queryItems: [
                URLQueryItem(name: "select", value: "id,name,initials,avatar_color"),
                URLQueryItem(name: "id", value: "eq.\(memberID.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        return rows.first?.member
    }

    func upsertCurrentMember(_ member: Member) async throws {
        _ = try await execute(
            path: "members",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            body: MemberRow(member),
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func createAttendanceRecord(_ record: AttendanceRecord) async throws {
        _ = try await execute(
            path: "attendance_records",
            method: "POST",
            queryItems: [],
            body: AttendanceRecordRow(record),
            prefer: "return=minimal"
        )
    }

    func deleteAttendanceRecord(id: UUID) async throws {
        _ = try await request(
            path: "attendance_records",
            method: "DELETE",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            body: nil,
            prefer: nil
        )
    }

    func createGymVisit(_ visit: GymVisit) async throws {
        _ = try await execute(
            path: "gym_visits",
            method: "POST",
            queryItems: [],
            body: GymVisitRow(visit),
            prefer: "return=minimal"
        )
    }

    func closeGymVisit(id: UUID, checkOutAt: Date) async throws {
        _ = try await execute(
            path: "gym_visits",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            body: GymVisitCheckOutUpdateRow(checkOutAt: checkOutAt),
            prefer: "return=minimal"
        )
    }

    func deleteGymVisit(id: UUID) async throws {
        _ = try await request(
            path: "gym_visits",
            method: "DELETE",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            body: nil,
            prefer: nil
        )
    }

    func fetchChatMessages(limit: Int = 200) async throws -> [ChatMessage] {
        let rows: [ChatMessageRow] = try await fetch(
            path: "chat_messages",
            queryItems: [
                URLQueryItem(name: "select", value: "id,sender_member_id,body,mentioned_member_ids,created_at"),
                URLQueryItem(name: "order", value: "created_at.asc"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        return rows.map(\.message)
    }

    func createChatMessage(_ message: ChatMessage) async throws {
        _ = try await execute(
            path: "chat_messages",
            method: "POST",
            queryItems: [],
            body: ChatMessageRow(message),
            prefer: "return=minimal"
        )
    }

    func fetchNotifications() async throws -> [AppNotification] {
        let rows: [NotificationRow] = try await fetch(
            path: "notifications",
            queryItems: [
                URLQueryItem(
                    name: "select",
                    value: "id,recipient_member_id,actor_member_id,type,title,message,created_at,read_at"
                ),
                URLQueryItem(name: "order", value: "created_at.desc")
            ]
        )
        // 旧通知タイプが混ざっていても、表示可能なものだけ使う。
        return rows.compactMap(\.notification)
    }

    func createNotifications(_ notifications: [AppNotification]) async throws {
        guard !notifications.isEmpty else { return }
        _ = try await execute(
            path: "notifications",
            method: "POST",
            queryItems: [],
            body: notifications.map(NotificationRow.init),
            prefer: "return=minimal"
        )
    }

    func markNotificationsRead(ids: [UUID], readAt: Date = Date()) async throws {
        guard !ids.isEmpty else { return }

        let joinedIDs = ids.map(\.uuidString).joined(separator: ",")
        _ = try await execute(
            path: "notifications",
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "id", value: "in.(\(joinedIDs))"),
                URLQueryItem(name: "read_at", value: "is.null")
            ],
            body: NotificationReadUpdateRow(readAt: readAt),
            prefer: "return=minimal"
        )
    }

    // MARK: - Fetch

    private func fetchMembers() async throws -> [Member] {
        let rows: [MemberRow] = try await fetch(
            path: "members",
            queryItems: [
                URLQueryItem(name: "select", value: "id,name,initials,avatar_color"),
                URLQueryItem(name: "order", value: "name.asc")
            ]
        )
        return rows.map(\.member)
    }

    private func fetchAttendanceRecords() async throws -> [AttendanceRecord] {
        let rows: [AttendanceRecordRow] = try await fetch(
            path: "attendance_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,member_id,date,type"),
                URLQueryItem(name: "order", value: "date.desc")
            ]
        )
        // 古い type 値が残っていても、起動時の全体失敗にならないように除外する。
        return rows.compactMap(\.record)
    }

    private func fetchGymVisits() async throws -> [GymVisit] {
        let rows: [GymVisitRow] = try await fetch(
            path: "gym_visits",
            queryItems: [
                URLQueryItem(name: "select", value: "id,member_id,check_in_at,check_out_at"),
                URLQueryItem(name: "order", value: "check_in_at.desc")
            ]
        )
        return rows.map(\.visit)
    }

    // MARK: - HTTP

    private func fetch<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let data = try await request(
            path: path,
            method: "GET",
            queryItems: queryItems,
            body: nil,
            prefer: nil
        )
        return try decoder.decode(T.self, from: data)
    }

    private func execute<Row: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Row,
        prefer: String? = nil
    ) async throws -> Data {
        let encoded = try encoder.encode(body)
        return try await request(
            path: path,
            method: method,
            queryItems: queryItems,
            body: encoded,
            prefer: prefer
        )
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Data?,
        prefer: String? = nil
    ) async throws -> Data {
        guard let baseURL = SupabaseConfig.baseURL, let anonKey = SupabaseConfig.anonKey else {
            throw SupabaseError.notConfigured
        }

        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("rest")
                .appendingPathComponent("v1")
                .appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw SupabaseError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = SupabaseAPIErrorEnvelope.decode(from: data)?.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw SupabaseError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
        return data
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase の設定がまだ入っていません。"
        case .invalidURL:
            return "Supabase の URL が正しくありません。"
        case .invalidResponse:
            return "Supabase から不正な応答が返りました。"
        case let .requestFailed(statusCode, message):
            return "Supabase API error \(statusCode): \(message)"
        }
    }
}

private struct MemberRow: Codable {
    let id: UUID
    let name: String
    let initials: String
    let avatarColor: AvatarColor

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case initials
        case avatarColor = "avatar_color"
    }

    init(_ member: Member) {
        self.id = member.id
        self.name = member.name
        self.initials = member.initials
        self.avatarColor = member.avatarColorName
    }

    var member: Member {
        Member(id: id, name: name, initials: initials, avatarColorName: avatarColor)
    }
}

private struct AttendanceRecordRow: Codable {
    let id: UUID
    let memberID: UUID
    let date: Date
    let type: String

    init(_ record: AttendanceRecord) {
        self.id = record.id
        self.memberID = record.memberID
        self.date = record.date
        self.type = record.type.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case id
        case memberID = "member_id"
        case date
        case type
    }

    var record: AttendanceRecord? {
        guard let type = AttendanceType(rawValue: type) else { return nil }
        return AttendanceRecord(id: id, memberID: memberID, date: date, type: type)
    }
}

private struct GymVisitRow: Codable {
    let id: UUID
    let memberID: UUID
    let checkInAt: Date
    let checkOutAt: Date?

    init(_ visit: GymVisit) {
        self.id = visit.id
        self.memberID = visit.memberID
        self.checkInAt = visit.checkInAt
        self.checkOutAt = visit.checkOutAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case memberID = "member_id"
        case checkInAt = "check_in_at"
        case checkOutAt = "check_out_at"
    }

    var visit: GymVisit {
        GymVisit(id: id, memberID: memberID, checkInAt: checkInAt, checkOutAt: checkOutAt)
    }
}

private struct GymVisitCheckOutUpdateRow: Codable {
    let checkOutAt: Date

    enum CodingKeys: String, CodingKey {
        case checkOutAt = "check_out_at"
    }
}

private struct ChatMessageRow: Codable {
    let id: UUID
    let senderMemberID: UUID
    let body: String
    let mentionedMemberIDs: [UUID]
    let createdAt: Date

    init(_ message: ChatMessage) {
        self.id = message.id
        self.senderMemberID = message.senderMemberID
        self.body = message.body
        self.mentionedMemberIDs = message.mentionedMemberIDs
        self.createdAt = message.createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case senderMemberID = "sender_member_id"
        case body
        case mentionedMemberIDs = "mentioned_member_ids"
        case createdAt = "created_at"
    }

    var message: ChatMessage {
        ChatMessage(
            id: id,
            senderMemberID: senderMemberID,
            body: body,
            mentionedMemberIDs: mentionedMemberIDs,
            createdAt: createdAt
        )
    }
}

private struct NotificationRow: Codable {
    let id: UUID
    let recipientMemberID: UUID
    let actorMemberID: UUID?
    let type: String
    let title: String
    let message: String
    let createdAt: Date
    let readAt: Date?

    init(_ notification: AppNotification) {
        self.id = notification.id
        self.recipientMemberID = notification.recipientMemberID
        self.actorMemberID = notification.actorMemberID
        self.type = notification.type.rawValue
        self.title = notification.title
        self.message = notification.message
        self.createdAt = notification.createdAt
        self.readAt = notification.readAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case recipientMemberID = "recipient_member_id"
        case actorMemberID = "actor_member_id"
        case type
        case title
        case message
        case createdAt = "created_at"
        case readAt = "read_at"
    }

    var notification: AppNotification? {
        guard let type = AppNotificationType(rawValue: type) else { return nil }
        return AppNotification(
            id: id,
            recipientMemberID: recipientMemberID,
            actorMemberID: actorMemberID,
            type: type,
            title: title,
            message: message,
            createdAt: createdAt,
            readAt: readAt
        )
    }
}

private struct NotificationReadUpdateRow: Codable {
    let readAt: Date

    enum CodingKeys: String, CodingKey {
        case readAt = "read_at"
    }
}

private struct SupabaseAPIErrorEnvelope: Decodable {
    let message: String?

    static func decode(from data: Data) -> SupabaseAPIErrorEnvelope? {
        try? JSONDecoder.supabase.decode(SupabaseAPIErrorEnvelope.self, from: data)
    }
}

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = SupabaseDateFormatter.shared.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
        }
        return decoder
    }
}

private extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SupabaseDateFormatter.shared.string(from: date))
        }
        return encoder
    }
}

private final class SupabaseDateFormatter {
    static let shared = SupabaseDateFormatter()

    private let fractionalFormatter: ISO8601DateFormatter
    private let regularFormatter: ISO8601DateFormatter
    private let dateOnlyFormatter: DateFormatter

    private init() {
        fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        regularFormatter = ISO8601DateFormatter()
        regularFormatter.formatOptions = [.withInternetDateTime]

        dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.calendar = Calendar(identifier: .gregorian)
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
    }

    func date(from string: String) -> Date? {
        fractionalFormatter.date(from: string)
            ?? regularFormatter.date(from: string)
            ?? dateOnlyFormatter.date(from: string)
    }

    func string(from date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    func dateOnlyString(from date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }
}
