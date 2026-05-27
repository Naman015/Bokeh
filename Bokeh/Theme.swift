import SwiftUI

// MARK: - Bokeh Theme (Colors, Typography, Glass Card)

extension Color {

    /// Centralized color palette for the Bokeh app.
    struct theme {
        // MARK: Core Brand
        static let bokehTeal = Color(red: 0.2, green: 0.65, blue: 0.65)
        static let bokehSand = Color(red: 0.96, green: 0.94, blue: 0.92)
        static let bokehDarkSurface = Color.black.opacity(0.2)
        /// Title / primary text on sand (WCAG contrast).
        static let bokehTitleColor = Color(red: 0.12, green: 0.10, blue: 0.08)
        /// Body and secondary text.
        static let bokehBodyColor = Color(red: 0.28, green: 0.26, blue: 0.24)

        // MARK: Success / Reward
        static let bokehMint = Color(red: 0.55, green: 0.82, blue: 0.72)
        static let bokehMintGlow = Color(red: 0.55, green: 0.82, blue: 0.72).opacity(0.15)

        // MARK: Warm Accent (milestones, streaks)
        static let bokehAmber = Color(red: 0.92, green: 0.75, blue: 0.42)
        static let bokehAmberSoft = Color(red: 0.95, green: 0.88, blue: 0.72)

        // MARK: Depth Layers
        static let bokehSandDeep = Color(red: 0.93, green: 0.90, blue: 0.86)
        static let bokehFog = Color(red: 0.97, green: 0.97, blue: 0.96)

        // MARK: Interactive States
        static let bokehTealPressed = Color(red: 0.15, green: 0.55, blue: 0.55)
        static let bokehTealSubtle = Color(red: 0.2, green: 0.65, blue: 0.65).opacity(0.08)

        // MARK: Caption Text
        static let bokehCaption = Color(red: 0.38, green: 0.36, blue: 0.33)
    }
}

// MARK: - Bokeh Elevation

enum BokehElevation {
    case resting
    case lifted
    case floating
}

struct BokehShadow: ViewModifier {
    let elevation: BokehElevation

    func body(content: Content) -> some View {
        switch elevation {
        case .resting:
            content.shadow(color: .black.opacity(0.03), radius: 6, y: 3)
        case .lifted:
            content.shadow(color: .black.opacity(0.06), radius: 12, y: 6)
        case .floating:
            content.shadow(color: .black.opacity(0.10), radius: 20, y: 10)
        }
    }
}

extension View {
    func bokehShadow(_ elevation: BokehElevation) -> some View {
        modifier(BokehShadow(elevation: elevation))
    }
}

// MARK: - Bokeh Spacing

enum BokehSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Bokeh Typography (SF Pro Rounded)

struct BokehTypography: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content
            .font(.system(style, design: .rounded))
            .fontWeight(weight)
    }
}

extension View {
    /// Applies Bokeh’s rounded system font with Dynamic Type support.
    func bokehFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(BokehTypography(style: style, weight: weight))
    }

    func bokehTitle() -> some View { bokehFont(.title2, weight: .bold) }
    func bokehHeadline() -> some View { bokehFont(.headline, weight: .semibold) }
    func bokehBody() -> some View { bokehFont(.body, weight: .regular) }
    func bokehCaptionStyle() -> some View { bokehFont(.caption, weight: .medium) }
}

// MARK: - Bokeh Pill

enum BokehPillStyle {
    case filled
    case outlined
    case tinted
}

struct BokehPill: ViewModifier {
    let style: BokehPillStyle

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 36)
            .background {
                Capsule().fill(pillFill)
            }
            .overlay {
                if style == .outlined {
                    Capsule().stroke(Color.theme.bokehTeal, lineWidth: 1.5)
                }
            }
    }

    private var pillFill: AnyShapeStyle {
        switch style {
        case .filled:
            AnyShapeStyle(Color.theme.bokehTeal)
        case .outlined:
            AnyShapeStyle(Color.clear)
        case .tinted:
            AnyShapeStyle(Color.theme.bokehTealSubtle)
        }
    }
}

extension View {
    func bokehPill(_ style: BokehPillStyle) -> some View {
        modifier(BokehPill(style: style))
    }
}

// MARK: - Bokeh Glass Card

struct BokehGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 15, y: 8)
    }
}

extension View {
    /// Applies the standard Bokeh glass card style (material, rounded, shadow).
    func bokehCardStyle() -> some View {
        modifier(BokehGlassCard())
    }
}

// MARK: - App Logo (matches App Icon)

/// Shows the app logo image when available, otherwise the camera.aperture symbol.
struct BokehLogoView: View {
    var size: CGFloat = 96
    var useTealTint: Bool = true

    var body: some View {
        ZStack {
            if UIImage(named: "AppLogo") != nil {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            } else {
                Circle()
                    .fill(Color.theme.bokehTeal.opacity(0.12))
                    .frame(width: size, height: size)
                Image(systemName: "camera.aperture")
                    .font(.system(size: size * 0.42, weight: .light, design: .rounded))
                    .foregroundStyle(useTealTint ? Color.theme.bokehTeal : .primary)
            }
        }
    }
}
