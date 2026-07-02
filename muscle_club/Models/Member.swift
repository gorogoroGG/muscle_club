import SwiftUI

enum AvatarColor: String, Codable, CaseIterable {
    case blue
    case indigo
    case pink
    case green
    case orange
    case teal
    case purple
    case red
    case yellow

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .pink: .pink
        case .green: .green
        case .orange: .orange
        case .teal: .teal
        case .purple: .purple
        case .red: .red
        case .yellow: .yellow
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = AvatarColor(rawValue: rawValue) ?? .blue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct Member: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let initials: String
    let avatarColorName: AvatarColor

    var avatarColor: Color {
        avatarColorName.color
    }
}
