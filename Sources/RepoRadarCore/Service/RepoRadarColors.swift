import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Design-system status and accent color tokens with WCAG AA (≥ 4.5:1) accessible text variants
/// in both light and dark modes (CHR-73, CHR-92).
public enum RepoRadarColors {
  public struct RGB: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
      self.red = red
      self.green = green
      self.blue = blue
    }

    public init(hex: UInt32) {
      self.red = Double((hex >> 16) & 0xFF) / 255.0
      self.green = Double((hex >> 8) & 0xFF) / 255.0
      self.blue = Double(hex & 0xFF) / 255.0
    }

    /// Relative luminance per WCAG 2.1.
    public var relativeLuminance: Double {
      func linearize(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    /// Contrast ratio against another RGB color per WCAG 2.1 (1.0 to 21.0).
    public func contrastRatio(against other: RGB) -> Double {
      let l1 = relativeLuminance
      let l2 = other.relativeLuminance
      let lighter = max(l1, l2)
      let darker = min(l1, l2)
      return (lighter + 0.05) / (darker + 0.05)
    }

    /// Alpha-composited color when drawn with `alpha` over `backdrop`.
    public func composited(alpha: Double, over backdrop: RGB) -> RGB {
      RGB(
        red: red * alpha + backdrop.red * (1.0 - alpha),
        green: green * alpha + backdrop.green * (1.0 - alpha),
        blue: blue * alpha + backdrop.blue * (1.0 - alpha)
      )
    }
  }

  // MARK: - Reference Surface RGBs (Light & Dark)

  public static let lightWindowBackground = RGB(hex: 0xFFFFFF)
  public static let lightPopoverBackground = RGB(hex: 0xF5F5F7)
  public static let darkWindowBackground = RGB(hex: 0x232325)
  public static let darkPopoverBackground = RGB(hex: 0x242426)

  // MARK: - Text Token RGBs (Light & Dark)

  /// Red status text (`#B40012` light / `#FF6961` dark).
  public static let statusFailTextLight = RGB(hex: 0xB40012)
  public static let statusFailTextDark = RGB(hex: 0xFF6961)

  /// Orange status text (`#AC2C00` light / `#FFB340` dark).
  public static let statusStaleTextLight = RGB(hex: 0xAC2C00)
  public static let statusStaleTextDark = RGB(hex: 0xFFB340)

  /// Green status text (`#146C2E` light / `#30DB5B` dark).
  public static let statusPassTextLight = RGB(hex: 0x146C2E)
  public static let statusPassTextDark = RGB(hex: 0x30DB5B)

  /// Purple status text (`#7A359C` light / `#DA8FFF` dark).
  public static let statusReviewTextLight = RGB(hex: 0x7A359C)
  public static let statusReviewTextDark = RGB(hex: 0xDA8FFF)

  /// Indigo accent / PR text (`#4338CA` light / `#A5B4FC` dark).
  public static let statusIndigoTextLight = RGB(hex: 0x4338CA)
  public static let statusIndigoTextDark = RGB(hex: 0xA5B4FC)

  // MARK: - Icon / Fill Token RGBs (Light & Dark)

  public static let statusFailIconLight = RGB(hex: 0xFF3B30)
  public static let statusFailIconDark = RGB(hex: 0xFF453A)

  public static let statusStaleIconLight = RGB(hex: 0xFF9500)
  public static let statusStaleIconDark = RGB(hex: 0xFF9F0A)

  public static let statusPassIconLight = RGB(hex: 0x34C759)
  public static let statusPassIconDark = RGB(hex: 0x30D158)

  public static let statusReviewIconLight = RGB(hex: 0xAF52DE)
  public static let statusReviewIconDark = RGB(hex: 0xBF5AF2)

  public static let statusIndigoIconLight = RGB(hex: 0x6366F1)
  public static let statusIndigoIconDark = RGB(hex: 0x818CF8)

  // MARK: - Dynamic SwiftUI Colors

  public static func dynamicColor(light: RGB, dark: RGB) -> Color {
    #if canImport(AppKit)
    let nsColor = NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      let rgb = isDark ? dark : light
      return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }
    return Color(nsColor: nsColor)
    #else
    return Color(red: light.red, green: light.green, blue: light.blue)
    #endif
  }

  /// Accessible red text (`#B40012` light / `#FF6961` dark).
  public static let statusFailText = dynamicColor(
    light: statusFailTextLight, dark: statusFailTextDark)

  /// Accessible orange text (`#AC2C00` light / `#FFB340` dark).
  public static let statusStaleText = dynamicColor(
    light: statusStaleTextLight, dark: statusStaleTextDark)

  /// Accessible green text (`#146C2E` light / `#30DB5B` dark).
  public static let statusPassText = dynamicColor(
    light: statusPassTextLight, dark: statusPassTextDark)

  /// Accessible purple text (`#7A359C` light / `#DA8FFF` dark).
  public static let statusReviewText = dynamicColor(
    light: statusReviewTextLight, dark: statusReviewTextDark)

  /// Accessible indigo accent text (`#4338CA` light / `#A5B4FC` dark).
  public static let statusIndigoText = dynamicColor(
    light: statusIndigoTextLight, dark: statusIndigoTextDark)

  /// Status red icon/tint base (`#FF3B30` light / `#FF453A` dark).
  public static let statusFail = dynamicColor(
    light: statusFailIconLight, dark: statusFailIconDark)

  /// Status orange icon/tint base (`#FF9500` light / `#FF9F0A` dark).
  public static let statusStale = dynamicColor(
    light: statusStaleIconLight, dark: statusStaleIconDark)

  /// Status green icon/tint base (`#34C759` light / `#30D158` dark).
  public static let statusPass = dynamicColor(
    light: statusPassIconLight, dark: statusPassIconDark)

  /// Status purple icon/tint base (`#AF52DE` light / `#BF5AF2` dark).
  public static let statusReview = dynamicColor(
    light: statusReviewIconLight, dark: statusReviewIconDark)

  /// Status indigo icon/tint base (`#6366F1` light / `#818CF8` dark).
  public static let statusIndigo = dynamicColor(
    light: statusIndigoIconLight, dark: statusIndigoIconDark)
}
