import Foundation
import os

public enum ErrorReporter {
    private static let logger = Logger(subsystem: "com.kirole.app", category: "AppError")

    public static func log(_ error: AppError, context: String? = nil) {
        let contextText = context.map { "[\($0)] " } ?? ""
        logger.error("\(contextText, privacy: .public)\(error.localizedDescription, privacy: .public)")
    }

    public static func log(_ error: Error, context: String? = nil) {
        let appError = AppError.unknown(error.localizedDescription)
        log(appError, context: context)
    }
}
