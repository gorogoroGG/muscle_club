import Foundation
import CoreLocation

final class GymLocationService: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let regionIdentifier = "muscle_club.home_gym"
    private let dwellSeconds: TimeInterval = 180

    private var monitoredGym: SavedGymLocation?
    private var isCheckedIn = false
    private var insideSince: Date?
    private var outsideSince: Date?

    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    var onLocationUpdate: ((CLLocation) -> Void)?
    var onCheckIn: (() -> Void)?
    var onCheckOut: (() -> Void)?
    var onError: ((String) -> Void)?

    override init() {
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            onError?("位置情報が許可されていないため、自動チェックインが使えません。")
        @unknown default:
            break
        }
    }

    func requestCurrentLocation() {
        guard isLocationAvailable else { return }
        manager.requestLocation()
    }

    /// 監視するジムを更新する。同じジムであれば滞在タイマーは維持したまま位置更新の設定だけ揃える。
    func updateMonitoredGym(_ gym: SavedGymLocation?, isCheckedIn: Bool) {
        let isSameGym = monitoredGym == gym
        self.isCheckedIn = isCheckedIn

        if !isSameGym {
            insideSince = nil
            outsideSince = nil
            stopMonitoringCurrentRegion()
            manager.stopUpdatingLocation()
        }
        monitoredGym = gym

        guard let gym, isLocationAvailable else { return }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        if !isSameGym {
            let region = CLCircularRegion(
                center: gym.coordinate,
                radius: max(50, min(gym.radiusMeters, manager.maximumRegionMonitoringDistance)),
                identifier: regionIdentifier
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
            manager.requestState(for: region)
        }

        manager.allowsBackgroundLocationUpdates = manager.authorizationStatus == .authorizedAlways
        manager.startUpdatingLocation()
    }

    private var isLocationAvailable: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private func stopMonitoringCurrentRegion() {
        for region in manager.monitoredRegions where region.identifier == regionIdentifier {
            manager.stopMonitoring(for: region)
        }
    }

    /// 3分連続で範囲内/範囲外だったことを確認できたタイミングでチェックイン/チェックアウトを確定する。
    /// タイマーではなく位置更新のたびに経過時間を見るので、バックグラウンドで一時的に処理が止まっても
    /// 次の位置更新イベントで正しい状態に収束する。
    private func evaluateDwell(distance: CLLocationDistance) {
        guard let gym = monitoredGym else { return }
        let now = Date()
        let isInside = distance <= gym.radiusMeters

        if isInside {
            outsideSince = nil
            let since = insideSince ?? now
            insideSince = since
            if !isCheckedIn, now.timeIntervalSince(since) >= dwellSeconds {
                isCheckedIn = true
                onCheckIn?()
            }
        } else {
            insideSince = nil
            let since = outsideSince ?? now
            outsideSince = since
            if isCheckedIn, now.timeIntervalSince(since) >= dwellSeconds {
                isCheckedIn = false
                onCheckOut?()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(manager.authorizationStatus)
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            updateMonitoredGym(monitoredGym, isCheckedIn: isCheckedIn)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        manager.requestState(for: region)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        manager.requestState(for: region)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == regionIdentifier, let gym = monitoredGym else { return }
        switch state {
        case .inside:
            evaluateDwell(distance: 0)
        case .outside:
            evaluateDwell(distance: gym.radiusMeters + 1)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocationUpdate?(location)
        guard let gym = monitoredGym else { return }
        let gymLocation = CLLocation(latitude: gym.latitude, longitude: gym.longitude)
        evaluateDwell(distance: location.distance(from: gymLocation))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?(error.localizedDescription)
    }
}
