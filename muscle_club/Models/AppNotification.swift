import Foundation

enum AppNotificationType: String, Codable {
    case going
    case notGoing
    case checkedIn
    case checkedOut
    case checkInCancelled
    case chatMessage
}

struct AppNotification: Identifiable, Equatable, Codable {
    let id: UUID
    let recipientMemberID: UUID
    let actorMemberID: UUID?
    let type: AppNotificationType
    let title: String
    let message: String
    let createdAt: Date
    let readAt: Date?

    var isUnread: Bool {
        readAt == nil
    }
}
