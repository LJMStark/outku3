import Foundation

/// 把裸 KRI 一次整块 POST 到设备 HTTP 收图端点的抽象。便于测试注入 mock。
public protocol AvatarHTTPUploading: Sendable {
    /// 上传裸 KRI 到 `endpoint`。`onProgress(sentBytes, totalBytes)` 在后台线程回调，
    /// 调用方负责 hop 到主线程更新 UI。非 2xx / 传输失败抛 `AvatarHTTPUploadError`。
    func upload(
        kriData: Data,
        to endpoint: URL,
        headers: [String: String],
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws
}

public enum AvatarHTTPUploadError: Error, Sendable, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case transportFailed(String)
}

/// 用 `URLSession.upload(for:from:)` 上传，进度经 `URLSessionTaskDelegate` 回调。
/// `allowsCellularAccess = false`：设备热点无互联网，强制走 WiFi 接口、不让请求漏到蜂窝。
public struct URLSessionAvatarUploader: AvatarHTTPUploading {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    public func upload(
        kriData: Data,
        to endpoint: URL,
        headers: [String: String],
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(WiFiAvatarHTTPContract.contentType, forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout

        let progressDelegate = UploadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: configuration, delegate: progressDelegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: kriData)
        } catch {
            throw AvatarHTTPUploadError.transportFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AvatarHTTPUploadError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw AvatarHTTPUploadError.httpStatus(http.statusCode)
        }
        // 响应体 {"status":"staging",...} 暂不解析：持久化成功由 BLE 0x22 staged 权威确认，
        // HTTP 200 仅表示"字节已收"（见 WiFi头像传输协议契约草案 §4）。
        _ = data
    }
}

/// URLSession 上传进度桥接。`didSendBodyData` 在 delegate 队列（后台）回调 onProgress。
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int, Int) -> Void

    init(onProgress: @escaping @Sendable (Int, Int) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(Int(totalBytesSent), Int(totalBytesExpectedToSend))
    }
}
