import Combine
import Foundation

@MainActor
final class HubPairingStore: ObservableObject {
    private static let defaultsKey = "treelethub.pairing.pin.v1"
    @Published private(set) var pin: String

    init() {
        if let existing = UserDefaults.standard.string(forKey: Self.defaultsKey),
           existing.count == 6,
           existing.allSatisfy(\.isNumber)
        {
            pin = existing
        } else {
            pin = Self.makePIN()
            UserDefaults.standard.set(pin, forKey: Self.defaultsKey)
        }
    }

    func regenerate() {
        pin = Self.makePIN()
        UserDefaults.standard.set(pin, forKey: Self.defaultsKey)
    }

    private static func makePIN() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    func verify(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines) == pin
    }
}
