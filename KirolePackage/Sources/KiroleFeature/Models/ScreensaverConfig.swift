import Foundation

public struct ScreensaverConfig: Sendable, Codable, Equatable {
    public enum ScreensaverType: String, Sendable, Codable {
        case normal = "normal"
        case postcard = "postcard"
    }
    
    public var type: ScreensaverType
    public var quote: String
    public var author: String
    public var sceneId: String
    public var postcardDay: Int?
    
    public init(
        type: ScreensaverType = .normal,
        quote: String = "",
        author: String = "",
        sceneId: String = "harbor",
        postcardDay: Int? = nil
    ) {
        self.type = type
        self.quote = quote
        self.author = author
        self.sceneId = sceneId
        self.postcardDay = postcardDay
    }
}
