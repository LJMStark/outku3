import Foundation

public enum UserFacingErrorMapper {
    public static func message(for error: AppError) -> String {
        switch error {
        case .persistence:
            return "本地数据保存失败，请稍后重试。"
        case .sync:
            return "同步失败，请检查网络后重试。"
        case .configuration:
            return "应用配置不完整，请在设置中检查配置。"
        case .bleSecurity:
            return "设备安全校验失败，请重新配对设备。"
        case .unsupportedProtocol:
            return "设备协议版本过旧，请升级设备固件。"
        case .unknown(let message):
            return message.isEmpty ? "发生未知错误，请稍后重试。" : message
        }
    }

    public static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            return message(for: appError)
        }
        return error.localizedDescription.isEmpty ? "发生未知错误，请稍后重试。" : error.localizedDescription
    }
}
