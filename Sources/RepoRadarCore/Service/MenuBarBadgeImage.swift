import Foundation
#if canImport(AppKit)
import AppKit

/// Renders a crisp notification badge image for the menu bar item.
public enum MenuBarBadgeImage {
  /// Height of the menu bar badge pill in points.
  public static let badgeHeight: CGFloat = 14.0

  /// Minimum width of the badge pill (for single digit counts).
  public static let badgeMinWidth: CGFloat = 14.0

  /// Font point size for the count text.
  public static let fontSize: CGFloat = 9.5

  /// Generates a resolution-independent NSImage containing a red capsule badge with the count string.
  @MainActor
  public static func render(count: Int) -> NSImage {
    let text = count > 99 ? "99+" : "\(count)"
    let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.white
    ]
    let textSize = (text as NSString).size(withAttributes: attributes)
    let horizontalPadding: CGFloat = 4.0
    let width = max(badgeMinWidth, ceil(textSize.width) + (horizontalPadding * 2))

    let image = NSImage(size: NSSize(width: width, height: badgeHeight), flipped: false) { rect in
      let path = NSBezierPath(roundedRect: rect, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2)
      NSColor.systemRed.setFill()
      path.fill()

      let textPoint = NSPoint(
        x: (width - textSize.width) / 2,
        y: (badgeHeight - textSize.height) / 2
      )
      (text as NSString).draw(at: textPoint, withAttributes: attributes)
      return true
    }
    image.isTemplate = false
    return image
  }
}
#endif
