import Combine
import CoreLocation
import Foundation
import WeatherKit

struct HubIslandWeatherSnapshot: Equatable {
    var temperatureLine: String
    var symbolName: String
    var conditionDescription: String
}

struct HubIslandDailyForecastItem: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let weekdayShort: String
    let symbolName: String
    let highLine: String
    let lowLine: String
}

/// Apple Weather（WeatherKit API）与粗略定位；沙盒需开启定位权限。
@MainActor
final class HubIslandWeatherStore: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var snapshot: HubIslandWeatherSnapshot?
    @Published private(set) var dailyItems: [HubIslandDailyForecastItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    /// 逆地理编码得到的城镇名（区/市），用于天气页展示。
    @Published private(set) var placeDisplayName: String?

    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    private let geocoder = CLGeocoder()
    private var lastGeocodedLocation: CLLocation?
    private static func weekdayString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = HubMacL10n.displayLocale
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocationIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        default:
            break
        }
    }

    func refreshIfAuthorized() {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        default:
            lastError = HubMacL10n.string("mac.weather.err.needs_location")
        }
    }

    deinit {
        geocoder.cancelGeocode()
    }

    private func updatePlaceDisplayName(for location: CLLocation) {
        if let prev = lastGeocodedLocation, prev.distance(from: location) < 1500, placeDisplayName != nil {
            return
        }
        lastGeocodedLocation = location
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] marks, _ in
            Task { @MainActor [weak self] in
                guard let self, let m = marks?.first else { return }
                self.placeDisplayName = Self.formatPlaceName(from: m)
            }
        }
    }

    private static func formatPlaceName(from placemark: CLPlacemark) -> String {
        let locality = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subLocal = placemark.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines)
        let admin = placemark.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let loc = locality, !loc.isEmpty {
            if let sub = subLocal, !sub.isEmpty, sub != loc {
                return "\(loc) · \(sub)"
            }
            return loc
        }
        if let sub = subLocal, !sub.isEmpty { return sub }
        if let a = admin, !a.isEmpty { return a }
        return placemark.name ?? ""
    }

    private func performWeatherFetch(at location: CLLocation) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let weather = try await weatherService.weather(for: location)
            let current = weather.currentWeather
            snapshot = HubIslandWeatherSnapshot(
                temperatureLine: Self.formatTemperature(current.temperature),
                symbolName: current.symbolName,
                conditionDescription: current.condition.description
            )
            let days = Array(weather.dailyForecast.forecast.prefix(7))
            dailyItems = days.map { day in
                HubIslandDailyForecastItem(
                    date: day.date,
                    weekdayShort: Self.weekdayString(for: day.date),
                    symbolName: day.symbolName,
                    highLine: Self.formatTemperature(day.highTemperature),
                    lowLine: Self.formatTemperature(day.lowTemperature)
                )
            }
        } catch {
            snapshot = nil
            dailyItems = []
            lastError = error.localizedDescription
        }
    }

    private func clearPlaceIfUnauthorized() {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            placeDisplayName = nil
            lastGeocodedLocation = nil
        }
    }

    private static func formatTemperature(_ measurement: Measurement<UnitTemperature>) -> String {
        let c = measurement.converted(to: .celsius)
        let v = Int(c.value.rounded())
        return "\(v)°"
    }
}

extension HubIslandWeatherStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            clearPlaceIfUnauthorized()
            switch authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            updatePlaceDisplayName(for: loc)
            await performWeatherFetch(at: loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            isLoading = false
        }
    }
}
