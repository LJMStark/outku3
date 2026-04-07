import Foundation

public enum ExternalEditingError: LocalizedError, Sendable {
    case missingRemoteIdentifier(String)
    case integrationReadOnly(String)

    public var errorDescription: String? {
        switch self {
        case .missingRemoteIdentifier(let platform):
            return "\(platform) 数据缺少远端标识，请先刷新同步后再试。"
        case .integrationReadOnly(let platform):
            return "\(platform) 当前在 Kirole 中是只读连接，请在原平台中编辑。"
        }
    }
}
