import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let senderMemberID: UUID
    let body: String
    let mentionedMemberIDs: [UUID]
    let createdAt: Date
}

enum ChatMentionParser {
    static func mentionedMemberIDs(in body: String, members: [Member]) -> [UUID] {
        let orderedMembers = members.sorted { $0.name.count > $1.name.count }
        var seen = Set<UUID>()
        var resolved: [UUID] = []

        for member in orderedMembers {
            let pattern = "(?<!\\S)@\(NSRegularExpression.escapedPattern(for: member.name))(?=\\s|$|[.,!?、。！？])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(body.startIndex..., in: body)
            guard regex.firstMatch(in: body, range: range) != nil else { continue }
            if seen.insert(member.id).inserted {
                resolved.append(member.id)
            }
        }

        return resolved
    }

    static func preview(for body: String, limit: Int = 48) -> String {
        let collapsed = body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard collapsed.count > limit else { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<index]) + "…"
    }
}
