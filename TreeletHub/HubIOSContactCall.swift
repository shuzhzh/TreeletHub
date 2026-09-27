#if os(iOS)
import Contacts
import ContactsUI
import SwiftUI
import UIKit

enum HubIOSContactCall {
    static let phoneBundleId = "com.apple.mobilephone"
    static let idPrefix = "contact.tel."

    static func isSetupTile(_ bundleId: String) -> Bool {
        bundleId == phoneBundleId
    }

    static func isCallSlot(_ bundleId: String) -> Bool {
        bundleId.hasPrefix(idPrefix)
    }

    static func bundleId(forDialString dial: String) -> String {
        idPrefix + dial
    }

    static func telURL(from raw: String) -> URL? {
        guard let dial = dialString(from: raw), let url = URL(string: "tel:\(dial)") else { return nil }
        return url
    }

    static func dialString(from raw: String) -> String? {
        let allowed = CharacterSet(charactersIn: "+0123456789")
        let kept = String(raw.unicodeScalars.filter { allowed.contains($0) })
        let digits = kept.filter(\.isNumber)
        guard digits.count >= 3 else { return nil }
        return kept
    }

    static func preferredPhone(from contact: CNContact) -> String? {
        let labeled = contact.phoneNumbers
        let preferredLabels: [String] = [
            CNLabelPhoneNumberiPhone,
            CNLabelPhoneNumberMobile,
            CNLabelPhoneNumberMain,
        ]
        for label in preferredLabels {
            if let match = labeled.first(where: { $0.label == label }) {
                return match.value.stringValue
            }
        }
        return labeled.first?.value.stringValue
    }

    static func displayName(for contact: CNContact) -> String {
        let formatted = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !formatted.isEmpty { return formatted }
        let fallback = [contact.familyName, contact.givenName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "")
        return fallback.isEmpty ? preferredPhone(from: contact) ?? "Phone" : fallback
    }

    static func iconPNG(for contact: CNContact, name: String) -> Data? {
        if let data = contact.thumbnailImageData ?? contact.imageData,
           let image = UIImage(data: data),
           let png = image.hub_pngData(maxPixelSide: 256) {
            return png
        }
        return monogramPNG(name: name)
    }

    static func monogramPNG(name: String) -> Data? {
        let letter = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.pngData { _ in
            UIColor.systemBlue.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: side * 0.225).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: side * 0.42, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let text = letter.isEmpty ? "📞" : letter
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2),
                withAttributes: attrs
            )
        }
    }

    static func hydrated(_ contact: CNContact) -> CNContact {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]
        return (try? CNContactStore().unifiedContact(withIdentifier: contact.identifier, keysToFetch: keys)) ?? contact
    }

    static func picks(from contacts: [CNContact]) -> [HubIOSFamilyAppPick] {
        var seen = Set<String>()
        var result: [HubIOSFamilyAppPick] = []
        for rawContact in contacts {
            let contact = hydrated(rawContact)
            guard let raw = preferredPhone(from: contact) ?? preferredPhone(from: rawContact),
                  let dial = dialString(from: raw),
                  let url = telURL(from: dial),
                  seen.insert(dial).inserted
            else { continue }
            let name = displayName(for: contact)
            result.append(
                HubIOSFamilyAppPick(
                    bundleIdentifier: bundleId(forDialString: dial),
                    displayName: name,
                    tokenData: nil,
                    iconPNG: iconPNG(for: contact, name: name) ?? monogramPNG(name: name),
                    launchURLString: url.absoluteString
                )
            )
        }
        return result
    }

    static func requestAccessThen(_ work: @escaping () -> Void) {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .notDetermined else {
            work()
            return
        }
        store.requestAccess(for: .contacts) { _, _ in
            DispatchQueue.main.async(execute: work)
        }
    }
}

/// 系统通讯录多选。点电话时先要权限，再选要一键呼叫的联系人。
struct HubIOSContactCallPicker: UIViewControllerRepresentable {
    var onPick: ([CNContact]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactThumbnailImageDataKey,
            CNContactImageDataKey,
            CNContactIdentifierKey,
        ]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([CNContact]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([CNContact]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick([contact])
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
#endif
