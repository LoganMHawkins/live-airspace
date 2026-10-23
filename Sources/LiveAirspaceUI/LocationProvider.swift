import CoreLocation
import LiveAirspaceKit

/// One-shot approximate location, used to centre the radar on wherever the device is.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Fix: Equatable {
        var latitude: Double
        var longitude: Double
        var place: String?
    }

    @Published private(set) var fix: Fix?
    @Published private(set) var denied = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            #if os(macOS)
            manager.requestWhenInUseAuthorization()
            #else
            manager.requestWhenInUseAuthorization()
            #endif
        case .denied, .restricted: denied = true
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted: Task { @MainActor in self.denied = true }
        case .notDetermined: break
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.fix = Fix(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, place: nil)
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(loc)
            if let place = placemarks?.first?.locality {
                self.fix = Fix(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, place: place)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
