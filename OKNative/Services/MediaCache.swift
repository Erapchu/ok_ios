import Foundation
import CryptoKit

actor MediaCache {
    static let shared = MediaCache()
    private let directory: URL
    private var generation = UUID()
    private let session: URLSession
    private let maxDiskBytes = 150 * 1024 * 1024

    init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OKImages", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    func data(for url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw HTTPClient.Failure.insecureURL }
        let filename = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(filename)
        if let cached = try? Data(contentsOf: file) { return cached }
        let attempt = generation
        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.mimeType?.hasPrefix("image/") == true, data.count <= 20 * 1024 * 1024 else {
            throw OKAPIError.invalidResponse
        }
        if attempt == generation {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            trim()
        }
        return data
    }

    func clear() {
        generation = UUID()
        try? FileManager.default.removeItem(at: directory)
    }

    private func trim() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys)) else { return }
        let files = urls.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = files.reduce(0) { $0 + $1.1 }
        for file in files where size > maxDiskBytes {
            try? FileManager.default.removeItem(at: file.0)
            size -= file.1
        }
    }
}
