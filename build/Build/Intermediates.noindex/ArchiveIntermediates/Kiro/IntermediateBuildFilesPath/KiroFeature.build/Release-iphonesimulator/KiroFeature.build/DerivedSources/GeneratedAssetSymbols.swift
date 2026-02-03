import Foundation
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "tiko_avatar" asset catalog image resource.
    static let tikoAvatar = DeveloperToolsSupport.ImageResource(name: "tiko_avatar", bundle: resourceBundle)

    /// The "tiko_mushroom" asset catalog image resource.
    static let tikoMushroom = DeveloperToolsSupport.ImageResource(name: "tiko_mushroom", bundle: resourceBundle)

    /// The "tiko_reading" asset catalog image resource.
    static let tikoReading = DeveloperToolsSupport.ImageResource(name: "tiko_reading", bundle: resourceBundle)

}

