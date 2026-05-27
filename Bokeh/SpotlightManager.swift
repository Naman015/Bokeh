import Foundation
import UIKit
import CoreSpotlight
import MobileCoreServices

// MARK: - Spotlight Manager (Object Permanence)

enum SpotlightManager {

    private static let domainIdentifier = "com.bokeh.cleared"

    static func indexItem(_ item: ClearLog, image: UIImage?) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .image)
        attributeSet.title = item.label

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateString = formatter.string(from: item.timestamp)

        let location = item.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if location.isEmpty {
            attributeSet.contentDescription = "Cleared on \(dateString)"
        } else {
            attributeSet.contentDescription = "Cleared to: \(location) on \(dateString)"
        }

        if let image,
           let data = image.jpegData(compressionQuality: 0.5) {
            attributeSet.thumbnailData = data
        }

        let searchableItem = CSSearchableItem(
            uniqueIdentifier: item.id.uuidString,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributeSet
        )

        CSSearchableIndex.default().indexSearchableItems([searchableItem]) { _ in }
    }

    static func removeItem(_ item: ClearLog) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [item.id.uuidString]) { _ in }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { _ in }
    }
}

