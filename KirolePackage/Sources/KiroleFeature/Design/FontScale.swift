import CoreGraphics

// MARK: - Kirole Font Scale
//
// Canonical point sizes for the Kirole design system.
// Use these in all new code instead of raw numbers:
//
//   .font(.system(size: KiroleFontScale.body, weight: .semibold))
//
// Existing code still uses raw numbers and can be migrated incrementally.

public enum KiroleFontScale {
    /// 11 pt — tiny labels, monospaced debug text
    public static let micro: CGFloat = 11
    /// 12 pt — captions, secondary metadata
    public static let caption: CGFloat = 12
    /// 13 pt — footnotes, compact list rows
    public static let footnote: CGFloat = 13
    /// 14 pt — standard body text (most common)
    public static let body: CGFloat = 14
    /// 15 pt — callouts, slightly emphasized body
    public static let callout: CGFloat = 15
    /// 16 pt — subheadings, section labels
    public static let subheadline: CGFloat = 16
    /// 18 pt — card headings, small titles
    public static let headline: CGFloat = 18
    /// 20 pt — medium section titles
    public static let title3: CGFloat = 20
    /// 24 pt — page section titles
    public static let title2: CGFloat = 24
    /// 28 pt — large feature titles
    public static let title1: CGFloat = 28
    /// 32 pt — hero / page-level display text
    public static let largeTitle: CGFloat = 32
}
