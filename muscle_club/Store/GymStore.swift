import SwiftUI
import Combine
import CoreLocation

@MainActor
final class GymStore: ObservableObject {

    enum AppMode: Equatable {
        case signedOut
        case loading
        case signedIn
        case failed(String)
    }

    enum TodayGymStatus: Equatable {
        case checkedIn
        case checkedOut
        case goingNotArrived
    }

    struct PeriodStat: Identifiable {
        let id = UUID()
        let label: String
        let start: Date
        let count: Int
        let minutes: Int
    }

    // MARK: - State

    private var service: SupabaseGymService
    private let authService: SupabaseAuthService
    private let locationService: GymLocationService

    @Published var members: [Member] = []
    @Published var attendanceRecords: [AttendanceRecord] = []
    @Published var gymVisits: [GymVisit] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var notifications: [AppNotification] = []
    @Published var gymLocation: SavedGymLocation? = nil
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var appMode: AppMode = .signedOut
    @Published var lastErrorMessage: String? = nil
    @Published var lastMagicLinkRequestWasRateLimited: Bool = false

    private var pendingDisplayName: String? = nil
    private var pendingGymRegistrationName: String? = nil

    var isAuthenticated: Bool { appMode == .signedIn }
    var isSupabaseReady: Bool { service.isConfigured }
    var hasAuthSession: Bool { authService.isSignedIn }
    var isLocationAuthorized: Bool {
        switch locationAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }
    var isAutomaticCheckInEnabled: Bool {
        gymLocation != nil && isLocationAuthorized
    }
    var shouldShowOpenLocationSettings: Bool {
        switch locationAuthorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }
    var checkInModeTitle: String {
        isAutomaticCheckInEnabled ? "自動チェックイン" : "未設定"
    }
    var checkInModeDescription: String {
        if let gymLocation, isAutomaticCheckInEnabled {
            return "\(gymLocation.name) の半径\(Int(gymLocation.radiusMeters))mに3分以上滞在すると自動でチェックインします。"
        }
        if gymLocation == nil {
            return "ジムが未登録なので、自動チェックインはまだ使えません。"
        }
        switch locationAuthorizationStatus {
        case .notDetermined:
            return "位置情報を許可すると、自動チェックインが使えるようになります。"
        case .denied, .restricted:
            return "位置情報がオフなので、自動チェックインが使えません。"
        default:
            return "自動チェックインの準備ができています。"
        }
    }

    // MARK: - Current User

    var currentUser: Member {
        if let currentUserID = authService.currentUserID,
           let member = members.first(where: { $0.id == currentUserID }) {
            return member
        }
        if let currentUserID = authService.currentUserID {
            return Member(
                id: currentUserID,
                name: defaultDisplayName,
                initials: defaultInitials,
                avatarColorName: defaultAvatarColor
            )
        }
        return Member(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            name: "member",
            initials: "ME",
            avatarColorName: .blue
        )
    }

    var currentUserEmail: String? { authService.currentUserEmail }

    private var currentUserID: UUID { authService.currentUserID ?? currentUser.id }
    var allMembers: [Member] {
        members.isEmpty ? [currentUser] : members.sorted { $0.name < $1.name }
    }
    var unreadNotificationCount: Int {
        notifications.filter(\.isUnread).count
    }

    // MARK: - Init

    init(
        service: SupabaseGymService,
        authService: SupabaseAuthService
    ) {
        self.service = service
        self.authService = authService
        self.locationService = GymLocationService()
        self.locationAuthorizationStatus = locationService.authorizationStatus
        configureLocationService()

        if !service.isConfigured {
            lastErrorMessage = "Supabase の設定がまだ入っていません。"
            appMode = .failed(lastErrorMessage ?? "")
        } else if authService.isSignedIn {
            self.service.authToken = authService.sessionState?.accessToken
            loadGymLocation()
            refreshLocationAutomation()
            appMode = .loading
            Task { await loadRemoteDataIfNeeded() }
        } else {
            resetAuthBoundState(keepError: false)
            appMode = .signedOut
        }
    }

    convenience init() {
        self.init(service: SupabaseGymService(), authService: SupabaseAuthService())
    }

    // MARK: - Today

    var isCurrentUserGoing: Bool {
        attendanceRecords.contains {
            $0.memberID == currentUserID &&
            $0.type == .going &&
            Calendar.current.isDateInToday($0.date)
        }
    }

    var isCurrentUserNotGoing: Bool {
        attendanceRecords.contains {
            $0.memberID == currentUserID &&
            $0.type == .notGoing &&
            Calendar.current.isDateInToday($0.date)
        }
    }

    var isCurrentUserCheckedIn: Bool {
        openVisit(for: currentUserID) != nil
    }

    func todayStatus(for memberID: UUID) -> TodayGymStatus? {
        let calendar = Calendar.current
        if openVisit(for: memberID) != nil { return .checkedIn }
        let hasVisitToday = gymVisits.contains {
            $0.memberID == memberID && calendar.isDateInToday($0.checkInAt)
        }
        if hasVisitToday { return .checkedOut }
        let isGoingToday = attendanceRecords.contains {
            $0.memberID == memberID && $0.type == .going && calendar.isDateInToday($0.date)
        }
        if isGoingToday { return .goingNotArrived }
        return nil
    }

    var todayCheckedInMembers: [Member] {
        allMembers.filter { todayStatus(for: $0.id) == .checkedIn }
    }
    var todayCheckedOutMembers: [Member] {
        allMembers.filter { todayStatus(for: $0.id) == .checkedOut }
    }
    var todayGoingNotArrivedMembers: [Member] {
        allMembers.filter { todayStatus(for: $0.id) == .goingNotArrived }
    }

    private func openVisit(for memberID: UUID) -> GymVisit? {
        gymVisits.first { $0.memberID == memberID && $0.isOpen }
    }

    // MARK: - Streak

    var currentStreak: Int {
        let calendar = Calendar.current
        let days = Set(
            gymVisits
                .filter { $0.memberID == currentUserID }
                .map { calendar.startOfDay(for: $0.checkInAt) }
        ).sorted(by: >)

        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        for day in days {
            if day == cursor {
                streak += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
            } else {
                break
            }
        }
        return streak
    }

    // MARK: - Monthly Stats

    var currentUserMonthCount: Int {
        visitDays(for: currentUserID, equalTo: Date(), toGranularity: .month).count
    }

    var currentUserMonthMinutes: Int {
        gymVisits
            .filter { $0.memberID == currentUserID && Calendar.current.isDate($0.checkInAt, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.minutes() }
    }

    private func visitDays(for memberID: UUID, equalTo date: Date, toGranularity component: Calendar.Component) -> Set<Date> {
        let calendar = Calendar.current
        return Set(
            gymVisits
                .filter { $0.memberID == memberID && calendar.isDate($0.checkInAt, equalTo: date, toGranularity: component) }
                .map { calendar.startOfDay(for: $0.checkInAt) }
        )
    }

    // MARK: - Record Tab Stats

    func dailyStats(forWeekOf date: Date = Date(), memberID: UUID? = nil) -> [PeriodStat] {
        let calendar = Calendar.current
        let targetID = memberID ?? currentUserID
        let weekday = calendar.component(.weekday, from: date)
        let offset = weekday == 1 ? -6 : 2 - weekday
        let monday = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "E"

        return (0..<7).map { offsetDays in
            let day = calendar.date(byAdding: .day, value: offsetDays, to: monday) ?? monday
            let visits = gymVisits.filter { $0.memberID == targetID && calendar.isDate($0.checkInAt, inSameDayAs: day) }
            let minutes = visits.reduce(0) { $0 + $1.minutes() }
            return PeriodStat(label: formatter.string(from: day), start: day, count: visits.isEmpty ? 0 : 1, minutes: minutes)
        }
    }

    func monthlyStats(monthsBack: Int = 6, memberID: UUID? = nil) -> [PeriodStat] {
        let calendar = Calendar.current
        let targetID = memberID ?? currentUserID
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月"

        return stride(from: monthsBack - 1, through: 0, by: -1).map { offset in
            let monthDate = calendar.date(byAdding: .month, value: -offset, to: Date()) ?? Date()
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)) ?? monthDate
            let visits = gymVisits.filter { $0.memberID == targetID && calendar.isDate($0.checkInAt, equalTo: monthDate, toGranularity: .month) }
            let days = Set(visits.map { calendar.startOfDay(for: $0.checkInAt) }).count
            let minutes = visits.reduce(0) { $0 + $1.minutes() }
            return PeriodStat(label: formatter.string(from: monthStart), start: monthStart, count: days, minutes: minutes)
        }
    }

    func memberComparison(forWeekOf date: Date = Date()) -> [(member: Member, count: Int, minutes: Int)] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let offset = weekday == 1 ? -6 : 2 - weekday
        let monday = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: monday) else { return [] }

        return allMembers.map { member in
            let visits = gymVisits.filter {
                $0.memberID == member.id && $0.checkInAt >= monday && $0.checkInAt < weekEnd
            }
            let days = Set(visits.map { calendar.startOfDay(for: $0.checkInAt) }).count
            let minutes = visits.reduce(0) { $0 + $1.minutes() }
            return (member: member, count: days, minutes: minutes)
        }.sorted { $0.minutes > $1.minutes }
    }

    func memberComparison(forMonthOf date: Date = Date()) -> [(member: Member, count: Int, minutes: Int)] {
        let calendar = Calendar.current
        return allMembers.map { member in
            let visits = gymVisits.filter {
                $0.memberID == member.id && calendar.isDate($0.checkInAt, equalTo: date, toGranularity: .month)
            }
            let days = Set(visits.map { calendar.startOfDay(for: $0.checkInAt) }).count
            let minutes = visits.reduce(0) { $0 + $1.minutes() }
            return (member: member, count: days, minutes: minutes)
        }.sorted { $0.minutes > $1.minutes }
    }

    // MARK: - Calendar Helpers

    func checkedInDates(for memberID: UUID) -> Set<Date> {
        let calendar = Calendar.current
        return Set(
            gymVisits
                .filter { $0.memberID == memberID }
                .map { calendar.startOfDay(for: $0.checkInAt) }
        )
    }

    func goingDates(for memberID: UUID) -> Set<Date> {
        Set(
            attendanceRecords
                .filter { $0.memberID == memberID && $0.type == .going }
                .map { Calendar.current.startOfDay(for: $0.date) }
        )
    }

    // MARK: - Auth

    func sendMagicLink(email: String) async {
        guard let redirectURL = authService.signInRedirectURL() else {
            lastErrorMessage = "ログイン用の戻り先URLが作れませんでした。"
            lastMagicLinkRequestWasRateLimited = false
            appMode = .failed(lastErrorMessage ?? "")
            return
        }

        appMode = .loading
        lastMagicLinkRequestWasRateLimited = false
        do {
            try await authService.sendMagicLink(email: email, redirectTo: redirectURL)
            lastErrorMessage = nil
            appMode = .signedOut
        } catch {
            lastMagicLinkRequestWasRateLimited = isMagicLinkRateLimitError(error)
            lastErrorMessage = lastMagicLinkRequestWasRateLimited
                ? "メール送信が続いています。少し待ってから再送してください。"
                : error.localizedDescription
            appMode = .failed(error.localizedDescription)
        }
    }

    func signInWithApple(identityToken: String, nonce: String, displayName: String?) async {
        guard service.isConfigured else {
            lastErrorMessage = "Supabase の設定がまだ入っていません。"
            appMode = .failed(lastErrorMessage ?? "")
            return
        }

        appMode = .loading
        pendingDisplayName = displayName
        do {
            let session = try await authService.signInWithApple(identityToken: identityToken, nonce: nonce)
            service.authToken = session.accessToken
            try await ensureCurrentMemberExists()
            await loadRemoteDataIfNeeded()
            pendingDisplayName = nil
        } catch {
            pendingDisplayName = nil
            lastErrorMessage = error.localizedDescription
            appMode = .failed(error.localizedDescription)
        }
    }

    func handleOpenURL(_ url: URL) async {
        guard service.isConfigured else { return }

        appMode = .loading
        do {
            let session = try await authService.handleIncomingURL(url)
            service.authToken = session.accessToken
            try await ensureCurrentMemberExists()
            await loadRemoteDataIfNeeded()
        } catch {
            lastErrorMessage = error.localizedDescription
            appMode = .failed(error.localizedDescription)
        }
    }

    func signOut() async {
        let accessToken = authService.sessionState?.accessToken
        authService.clearSessionLocally()
        completeSignOut()
        if let accessToken {
            await authService.revokeCurrentSession(using: accessToken)
        }
    }

    func forceLocalSignOut() {
        authService.clearSessionLocally()
        completeSignOut()
    }

    private func completeSignOut() {
        service.authToken = nil
        resetAuthBoundState(keepError: false)
        lastErrorMessage = nil
        pendingDisplayName = nil
        appMode = .signedOut
    }

    func requestLocationPermission() {
        locationService.requestAuthorization()
    }

    func registerCurrentLocationAsGym(named rawName: String) {
        guard isAuthenticated else {
            lastErrorMessage = "ログイン後にジムを登録してください。"
            return
        }

        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingGymRegistrationName = trimmed.isEmpty ? "マイジム" : trimmed
        locationService.requestAuthorization()
        locationService.requestCurrentLocation()
    }

    func saveGymLocation(
        named rawName: String,
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Double = 120
    ) {
        guard isAuthenticated else {
            lastErrorMessage = "ログイン後にジムを登録してください。"
            return
        }

        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let gym = SavedGymLocation(
            name: trimmed.isEmpty ? "マイジム" : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: radiusMeters
        )
        gymLocation = gym
        LocalTrainingPersistence.saveGymLocation(gym, for: authService.currentUserID)
        pendingGymRegistrationName = nil
        refreshLocationAutomation()
        lastErrorMessage = "\(gym.name) を登録しました。"
    }

    func clearGymLocation() {
        gymLocation = nil
        LocalTrainingPersistence.removeGymLocation(for: authService.currentUserID)
        refreshLocationAutomation()
        lastErrorMessage = "登録済みジムを削除しました。"
    }

    // MARK: - Actions

    func toggleGoing() {
        guard isAuthenticated else {
            lastErrorMessage = "ログイン後に参加予定を登録してください。"
            return
        }
        if isCurrentUserCheckedIn { return }
        applyAttendanceIntent(isCurrentUserGoing ? nil : .going)
    }

    func toggleNotGoing() {
        guard isAuthenticated else {
            lastErrorMessage = "ログイン後に不参加を登録してください。"
            return
        }
        guard !isCurrentUserCheckedIn else {
            lastErrorMessage = "チェックインを取り消してから不参加に変更してください。"
            return
        }
        applyAttendanceIntent(isCurrentUserNotGoing ? nil : .notGoing)
    }

    func checkIn() {
        guard isAuthenticated, !isCurrentUserCheckedIn else { return }

        let visit = GymVisit(id: UUID(), memberID: currentUserID, checkInAt: Date(), checkOutAt: nil)
        gymVisits.append(visit)
        Task {
            do {
                try await performSupabaseRequest {
                    try await service.createGymVisit(visit)
                }
                await sendCheckInNotification()
            } catch {
                await MainActor.run {
                    gymVisits.removeAll { $0.id == visit.id }
                    lastErrorMessage = error.localizedDescription
                    appMode = .failed(error.localizedDescription)
                }
            }
        }
    }

    func checkOut() {
        guard let visit = openVisit(for: currentUserID) else { return }
        let checkOutAt = Date()
        updateVisitCheckOut(visitID: visit.id, checkOutAt: checkOutAt)
        Task {
            do {
                try await performSupabaseRequest {
                    try await service.closeGymVisit(id: visit.id, checkOutAt: checkOutAt)
                }
                await sendCheckOutNotification()
            } catch {
                await MainActor.run {
                    updateVisitCheckOut(visitID: visit.id, checkOutAt: nil)
                    lastErrorMessage = error.localizedDescription
                    appMode = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelCheckIn() {
        guard isAuthenticated, let visit = openVisit(for: currentUserID) else { return }

        gymVisits.removeAll { $0.id == visit.id }
        Task {
            do {
                try await performSupabaseRequest {
                    try await service.deleteGymVisit(id: visit.id)
                }
                await sendCheckInCancelledNotification()
            } catch {
                await MainActor.run {
                    gymVisits.append(visit)
                    lastErrorMessage = error.localizedDescription
                    appMode = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelCheckOut() {
        guard isAuthenticated else { return }

        let calendar = Calendar.current
        guard let visitIndex = gymVisits.lastIndex(where: {
            $0.memberID == currentUserID &&
            calendar.isDateInToday($0.checkInAt) &&
            !$0.isOpen
        }) else { return }

        let visit = gymVisits.remove(at: visitIndex)
        Task {
            do {
                try await performSupabaseRequest {
                    try await service.deleteGymVisit(id: visit.id)
                }
            } catch {
                await MainActor.run {
                    gymVisits.insert(visit, at: min(visitIndex, gymVisits.count))
                    lastErrorMessage = error.localizedDescription
                    appMode = .failed(error.localizedDescription)
                }
            }
        }
    }

    func sendChatMessage(_ rawBody: String) async -> Bool {
        guard isAuthenticated else {
            lastErrorMessage = "ログイン後にメッセージを送信してください。"
            return false
        }

        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }

        let message = ChatMessage(
            id: UUID(),
            senderMemberID: currentUserID,
            body: body,
            mentionedMemberIDs: ChatMentionParser.mentionedMemberIDs(in: body, members: allMembers),
            createdAt: Date()
        )

        chatMessages.append(message)
        do {
            try await performSupabaseRequest {
                try await service.createChatMessage(message)
            }
            await sendChatMessageNotifications(for: message)
            return true
        } catch {
            await MainActor.run {
                chatMessages.removeAll { $0.id == message.id }
                lastErrorMessage = error.localizedDescription
            }
            return false
        }
    }

    private func updateVisitCheckOut(visitID: UUID, checkOutAt: Date?) {
        guard let index = gymVisits.firstIndex(where: { $0.id == visitID }) else { return }
        gymVisits[index].checkOutAt = checkOutAt
    }

    func reload() {
        Task { await loadRemoteDataIfNeeded() }
    }

    // MARK: - Remote Load

    private func loadRemoteDataIfNeeded() async {
        guard service.isConfigured else {
            lastErrorMessage = "Supabase の設定がまだ入っていません。"
            appMode = .failed(lastErrorMessage ?? "")
            return
        }

        guard authService.isSignedIn else {
            resetAuthBoundState(keepError: false)
            appMode = .signedOut
            return
        }

        appMode = .loading

        do {
            service.authToken = authService.sessionState?.accessToken
            try await ensureCurrentMemberExists()
            loadGymLocation()
            refreshLocationAutomation()
            let snapshot = try await performSupabaseRequest {
                try await service.loadSnapshot()
            }
            members = snapshot.members
            attendanceRecords = snapshot.attendanceRecords
            gymVisits = snapshot.gymVisits
            chatMessages = snapshot.chatMessages
            await loadNotifications()

            if !members.contains(where: { $0.id == currentUserID }) {
                members.append(Member(id: currentUserID, name: defaultDisplayName, initials: defaultInitials, avatarColorName: defaultAvatarColor))
            }

            refreshLocationAutomation()
            lastErrorMessage = nil
            appMode = .signedIn
        } catch {
            lastErrorMessage = error.localizedDescription
            appMode = .failed(error.localizedDescription)
        }
    }

    private func ensureCurrentMemberExists() async throws {
        guard let userID = authService.currentUserID else { return }
        if let current = try await performSupabaseRequest({
            try await service.fetchCurrentMember(memberID: userID)
        }) {
            if !members.contains(where: { $0.id == current.id }) {
                members = members + [current]
            }
            return
        }

        let seed = Member(
            id: userID,
            name: defaultDisplayName,
            initials: defaultInitials,
            avatarColorName: defaultAvatarColor
        )
        try await performSupabaseRequest {
            try await service.upsertCurrentMember(seed)
        }
        if !members.contains(where: { $0.id == seed.id }) {
            members.append(seed)
        }
    }

    private var defaultDisplayName: String {
        if let pendingDisplayName {
            let trimmed = pendingDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        let email = authService.currentUserEmail ?? ""
        let localPart = email.split(separator: "@").first.map(String.init) ?? "member"
        return localPart.isEmpty ? "member" : localPart
    }

    private var defaultInitials: String {
        let name = defaultDisplayName
        let normalized = name
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        return String(normalized.prefix(2)).padding(toLength: 2, withPad: "M", startingAt: 0)
    }

    private var defaultAvatarColor: AvatarColor {
        let colors = AvatarColor.allCases
        guard !colors.isEmpty else { return .blue }
        let hash = abs(defaultDisplayName.hashValue)
        return colors[hash % colors.count]
    }

    private func isMagicLinkRateLimitError(_ error: Error) -> Bool {
        if let authError = error as? SupabaseAuthError {
            switch authError {
            case let .requestFailed(statusCode, message):
                if statusCode == 429 { return true }
                let lowercased = message.lowercased()
                return lowercased.contains("rate limit") || lowercased.contains("over_email_send_rate_limit")
            default:
                return false
            }
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("429")
            || message.contains("rate limit")
            || message.contains("over_email_send_rate_limit")
    }

    private func loadGymLocation() {
        gymLocation = LocalTrainingPersistence.loadGymLocation(for: authService.currentUserID)
    }

    private func resetAuthBoundState(keepError: Bool) {
        members = []
        attendanceRecords = []
        gymVisits = []
        chatMessages = []
        notifications = []
        gymLocation = nil
        pendingDisplayName = nil
        pendingGymRegistrationName = nil
        locationAuthorizationStatus = locationService.authorizationStatus
        lastMagicLinkRequestWasRateLimited = false
        if !keepError {
            lastErrorMessage = nil
        }
        locationService.updateMonitoredGym(nil, isCheckedIn: false)
        LocalTrainingPersistence.clearInMemoryScope()
    }

    private func configureLocationService() {
        locationService.onAuthorizationChange = { [weak self] status in
            guard let self else { return }
            Task { @MainActor in
                self.locationAuthorizationStatus = status
                self.refreshLocationAutomation()
                if self.pendingGymRegistrationName != nil, self.isLocationAuthorized {
                    self.locationService.requestCurrentLocation()
                }
            }
        }

        locationService.onLocationUpdate = { [weak self] location in
            guard let self else { return }
            Task { @MainActor in
                self.handleLocationUpdate(location)
            }
        }

        locationService.onCheckIn = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handleAutomaticCheckIn()
            }
        }

        locationService.onCheckOut = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handleAutomaticCheckOut()
            }
        }

        locationService.onError = { [weak self] message in
            guard let self else { return }
            Task { @MainActor in
                self.lastErrorMessage = message
            }
        }
    }

    private func refreshLocationAutomation() {
        locationAuthorizationStatus = locationService.authorizationStatus
        guard isAuthenticated else {
            locationService.updateMonitoredGym(nil, isCheckedIn: false)
            return
        }
        locationService.updateMonitoredGym(gymLocation, isCheckedIn: isCurrentUserCheckedIn)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        guard let pendingGymRegistrationName else { return }

        let gym = SavedGymLocation(
            name: pendingGymRegistrationName,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        gymLocation = gym
        LocalTrainingPersistence.saveGymLocation(gym, for: authService.currentUserID)
        self.pendingGymRegistrationName = nil
        refreshLocationAutomation()
        lastErrorMessage = "\(gym.name) を現在地で登録しました。"
    }

    private func handleAutomaticCheckIn() {
        guard isAuthenticated, isAutomaticCheckInEnabled, !isCurrentUserCheckedIn else { return }
        checkIn()
    }

    private func handleAutomaticCheckOut() {
        guard isAuthenticated, isCurrentUserCheckedIn else { return }
        checkOut()
    }

    private func applyAttendanceIntent(_ targetType: AttendanceType?) {
        let recordsToRemove = currentUserIntentRecords()
        let removedIDs = Set(recordsToRemove.map(\.id))
        let newRecord = targetType.map {
            AttendanceRecord(
                id: UUID(),
                memberID: currentUserID,
                date: Date(),
                type: $0
            )
        }

        attendanceRecords.removeAll { removedIDs.contains($0.id) }
        if let newRecord {
            attendanceRecords.append(newRecord)
        }

        Task {
            do {
                for removedRecord in recordsToRemove {
                    try await performSupabaseRequest {
                        try await service.deleteAttendanceRecord(id: removedRecord.id)
                    }
                }
                if let newRecord {
                    try await performSupabaseRequest {
                        try await service.createAttendanceRecord(newRecord)
                    }
                    await sendAttendanceNotification(type: newRecord.type)
                }
            } catch {
                await MainActor.run {
                    attendanceRecords.append(contentsOf: recordsToRemove)
                    if let newRecord {
                        attendanceRecords.removeAll { $0.id == newRecord.id }
                    }
                    lastErrorMessage = error.localizedDescription
                    appMode = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func currentUserIntentRecords() -> [AttendanceRecord] {
        attendanceRecords.filter {
            $0.memberID == currentUserID &&
            ($0.type == .going || $0.type == .notGoing) &&
            Calendar.current.isDateInToday($0.date)
        }
    }

    private func loadNotifications() async {
        do {
            notifications = try await performSupabaseRequest {
                try await service.fetchNotifications()
            }
        } catch {
            notifications = []
            lastErrorMessage = "通知の読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    func markNotificationsRead() {
        let unreadIDs = notifications.filter(\.isUnread).map(\.id)
        guard !unreadIDs.isEmpty else { return }

        let readAt = Date()
        notifications = notifications.map { notification in
            guard unreadIDs.contains(notification.id) else { return notification }
            return AppNotification(
                id: notification.id,
                recipientMemberID: notification.recipientMemberID,
                actorMemberID: notification.actorMemberID,
                type: notification.type,
                title: notification.title,
                message: notification.message,
                createdAt: notification.createdAt,
                readAt: readAt
            )
        }

        Task {
            do {
                try await performSupabaseRequest {
                    try await service.markNotificationsRead(ids: unreadIDs, readAt: readAt)
                }
            } catch {
                await MainActor.run {
                    lastErrorMessage = "通知の既読更新に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    private func performSupabaseRequest<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard shouldRefreshSession(for: error) else {
                throw error
            }

            let session = try await authService.refreshSession()
            service.authToken = session.accessToken
            return try await operation()
        }
    }

    private func shouldRefreshSession(for error: Error) -> Bool {
        let tokens = ["jwt", "token", "expired"]

        if let error = error as? SupabaseError {
            switch error {
            case let .requestFailed(statusCode, message):
                let lowercased = message.lowercased()
                return statusCode == 401 && tokens.contains(where: lowercased.contains)
            default:
                return false
            }
        }

        if let error = error as? SupabaseAuthError {
            switch error {
            case let .requestFailed(statusCode, message):
                let lowercased = message.lowercased()
                return statusCode == 401 && tokens.contains(where: lowercased.contains)
            default:
                return false
            }
        }

        return false
    }

    private func sendAttendanceNotification(type: AttendanceType) async {
        let title: String
        let message: String
        let notificationType: AppNotificationType

        switch type {
        case .going:
            title = "参加予定が更新されました"
            message = "\(currentUser.name) さんが「参加」を選びました。"
            notificationType = .going
        case .notGoing:
            title = "参加予定が更新されました"
            message = "\(currentUser.name) さんが「不参加」を選びました。"
            notificationType = .notGoing
        }

        await createNotifications(
            recipients: notificationRecipientIDs(),
            type: notificationType,
            title: title,
            message: message
        )
    }

    private func sendCheckInNotification() async {
        await createNotifications(
            recipients: notificationRecipientIDs(),
            type: .checkedIn,
            title: "チェックインがありました",
            message: "\(currentUser.name) さんがジムに到着しました。"
        )
    }

    private func sendCheckOutNotification() async {
        await createNotifications(
            recipients: notificationRecipientIDs(),
            type: .checkedOut,
            title: "チェックアウトがありました",
            message: "\(currentUser.name) さんがジムを退出しました。"
        )
    }

    private func sendCheckInCancelledNotification() async {
        await createNotifications(
            recipients: notificationRecipientIDs(),
            type: .checkInCancelled,
            title: "チェックインが取り消されました",
            message: "\(currentUser.name) さんがチェックインを取り消しました。"
        )
    }

    private func sendChatMessageNotifications(for message: ChatMessage) async {
        let recipients = notificationRecipientIDs()
        guard !recipients.isEmpty else { return }

        let mentionedRecipientIDs = Set(message.mentionedMemberIDs)
        let preview = ChatMentionParser.preview(for: message.body)

        let payload = recipients.map { recipientID in
            AppNotification(
                id: UUID(),
                recipientMemberID: recipientID,
                actorMemberID: currentUserID,
                type: .chatMessage,
                title: mentionedRecipientIDs.contains(recipientID)
                    ? "メンションされています"
                    : "新しいメッセージ",
                message: mentionedRecipientIDs.contains(recipientID)
                    ? "\(currentUser.name) さんがあなたをメンションしました: \(preview)"
                    : "\(currentUser.name) さん: \(preview)",
                createdAt: Date(),
                readAt: nil
            )
        }

        do {
            try await performSupabaseRequest {
                try await service.createNotifications(payload)
            }
        } catch {
            lastErrorMessage = "メッセージ通知の送信に失敗しました: \(error.localizedDescription)"
        }
    }

    private func createNotifications(
        recipients: [UUID],
        type: AppNotificationType,
        title: String,
        message: String
    ) async {
        let uniqueRecipients = Array(Set(recipients))
        guard !uniqueRecipients.isEmpty else { return }

        let payload = uniqueRecipients.map { recipientID in
            AppNotification(
                id: UUID(),
                recipientMemberID: recipientID,
                actorMemberID: currentUserID,
                type: type,
                title: title,
                message: message,
                createdAt: Date(),
                readAt: nil
            )
        }

        do {
            try await performSupabaseRequest {
                try await service.createNotifications(payload)
            }
            if uniqueRecipients.contains(currentUserID) {
                notifications = (payload + notifications).sorted { $0.createdAt > $1.createdAt }
            }
        } catch {
            lastErrorMessage = "通知の送信に失敗しました: \(error.localizedDescription)"
        }
    }

    private func notificationRecipientIDs() -> [UUID] {
        members.map(\.id).filter { $0 != currentUserID }
    }
}
