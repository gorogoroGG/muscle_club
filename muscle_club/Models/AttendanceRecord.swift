import Foundation

enum AttendanceType: String, Codable {
    case going
    case notGoing
}

struct AttendanceRecord: Identifiable, Codable {
    let id: UUID
    let memberID: UUID
    let date: Date
    let type: AttendanceType
}
