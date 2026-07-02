import Foundation

struct GymVisit: Identifiable, Codable, Equatable {
    let id: UUID
    let memberID: UUID
    let checkInAt: Date
    var checkOutAt: Date?

    var isOpen: Bool { checkOutAt == nil }

    func minutes(asOf now: Date = Date()) -> Int {
        max(0, Int((checkOutAt ?? now).timeIntervalSince(checkInAt) / 60))
    }
}
