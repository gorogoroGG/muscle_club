import Foundation

enum LocalTrainingPersistence {
    private static let defaults = UserDefaults.standard
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static let gymLocationKeyPrefix = "local.savedGymLocation."
    private static let legacyMemberProfilesKey = "local.memberMachineProfiles"
    private static let legacyMachineRequestsKey = "local.machineRequests"

    static func loadGymLocation(for memberID: UUID?) -> SavedGymLocation? {
        guard let memberID else { return nil }
        return load(SavedGymLocation.self, key: gymLocationKey(for: memberID))
    }

    static func saveGymLocation(_ gymLocation: SavedGymLocation, for memberID: UUID?) {
        guard let memberID else { return }
        save(gymLocation, key: gymLocationKey(for: memberID))
    }

    static func removeGymLocation(for memberID: UUID?) {
        guard let memberID else { return }
        defaults.removeObject(forKey: gymLocationKey(for: memberID))
    }

    static func clearInMemoryScope() {
        purgeLegacyStorage()
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func gymLocationKey(for memberID: UUID) -> String {
        gymLocationKeyPrefix + memberID.uuidString
    }

    private static func purgeLegacyStorage() {
        defaults.removeObject(forKey: legacyMemberProfilesKey)
        defaults.removeObject(forKey: legacyMachineRequestsKey)
    }
}
