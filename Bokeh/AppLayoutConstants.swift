import SwiftUI

// MARK: - iPad-focused layout
// https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados

enum AppLayoutConstants {
    // MARK: - Design system 
    static let teal = Color(red: 0.2, green: 0.65, blue: 0.65)
    static let sand = Color(red: 0.97, green: 0.95, blue: 0.93)
    static let titleColor = Color(red: 0.12, green: 0.10, blue: 0.08)
    static let bodyColor = Color(red: 0.35, green: 0.33, blue: 0.30)
    /// Minimum touch target size (pt). Apple HIG: 44×44 for all interactive elements.
    static let minTouchTarget: CGFloat = 44

    /// Standard horizontal padding. Larger on iPad (regular size class).
    static func horizontalPadding(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        horizontalSizeClass == .regular ? 24 : 16
    }

    /// Standard vertical padding.
    static func verticalPadding(verticalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        verticalSizeClass == .regular ? 20 : 16
    }

    /// Focus Log grid: minimum cell width. Larger on regular size class.
    static func focusLogCellMinWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        horizontalSizeClass == .regular ? 200 : 140
    }

    /// Focus Log grid: cell height. Taller on regular size class to fit image + name + location.
    static func focusLogCellHeight(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        horizontalSizeClass == .regular ? 220 : 180
    }

    /// Corner radius for cards. Slightly larger on iPad.
    static func cardCornerRadius(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        horizontalSizeClass == .regular ? 20 : 18
    }

    /// Sheet/content max width on iPad so content doesn’t overstretch.
    static let sheetMaxWidth: CGFloat = 520

    /// Default location tags shown in SuccessView and Focus Log filter. Custom locations are not persisted.
    static let defaultLocationTags = ["Trash", "Drawer", "Bag", "Shelf", "Closet", "Box"]
}
