import Foundation

public enum UserFacingErrorMapper {
    public static func message(for error: AppError) -> String {
        switch error {
        case .persistence:
            return "Couldn't save your data locally. Please try again."
        case .sync:
            return "Sync failed. Check your connection and try again."
        case .configuration:
            return "App setup is incomplete. Please check Settings."
        case .bleSecurity:
            return "Device security check failed. Please re-pair your device."
        case .unsupportedProtocol:
            return "Your device firmware is out of date. Please update it."
        case .unknown(let message):
            return message.isEmpty ? "Something went wrong. Please try again." : message
        }
    }

    public static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            return message(for: appError)
        }
        return error.localizedDescription.isEmpty ? "Something went wrong. Please try again." : error.localizedDescription
    }
}
