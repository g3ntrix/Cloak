import Foundation

struct AppUpdateRelease: Equatable, Identifiable, Sendable {
    var id: String { tagName }
    let tagName: String
    let version: String
    let name: String
    let body: String
    let htmlURL: URL
    let downloadURL: URL
    let assetName: String
    let assetSize: Int
    let publishedAt: Date?
}

enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(String)
    case available(AppUpdateRelease)
    case downloading(AppUpdateRelease, Double)
    case downloaded(URL)
    case failed(String)
}

enum AppUpdateError: LocalizedError {
    case noDMGAsset
    case invalidDownloadsDirectory

    var errorDescription: String? {
        switch self {
        case .noDMGAsset:
            return "The latest GitHub release does not include a DMG."
        case .invalidDownloadsDirectory:
            return "Could not find your Downloads folder."
        }
    }
}

final class AppUpdateService {
    static let shared = AppUpdateService()

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/g3ntrix/Cloak/releases/latest")!
    private let decoder: JSONDecoder
    private let activeDownloadLock = NSLock()
    private var activeDownload: AppUpdateDownloadDelegate?

    private init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func latestRelease() async throws -> AppUpdateRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("Cloak macOS updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        let release = try decoder.decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        }) else {
            throw AppUpdateError.noDMGAsset
        }

        return AppUpdateRelease(
            tagName: release.tagName,
            version: Self.normalizedVersion(release.tagName),
            name: release.name ?? release.tagName,
            body: release.body ?? "",
            htmlURL: release.htmlURL,
            downloadURL: asset.browserDownloadURL,
            assetName: asset.name,
            assetSize: asset.size,
            publishedAt: release.publishedAt
        )
    }

    func downloadDMG(
        for release: AppUpdateRelease,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: release.downloadURL)
        request.setValue("Cloak macOS updater", forHTTPHeaderField: "User-Agent")

        let downloads = try FileManager.default.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        guard downloads.isFileURL else { throw AppUpdateError.invalidDownloadsDirectory }

        let destination = uniqueDestination(for: release.assetName, in: downloads)
        let delegate = AppUpdateDownloadDelegate(
            destination: destination,
            expectedSize: Int64(release.assetSize),
            onProgress: onProgress
        )

        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            setActiveDownload(delegate)
            session.downloadTask(with: request).resume()
        }
    }

    func cancelDownload() {
        activeDownloadLock.lock()
        let download = activeDownload
        activeDownload = nil
        activeDownloadLock.unlock()
        download?.cancel()
    }

    func isNewer(_ latest: String, than current: String) -> Bool {
        Self.compareVersions(Self.normalizedVersion(latest), Self.normalizedVersion(current)) == .orderedDescending
    }

    static func normalizedVersion(_ raw: String) -> String {
        var version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("v") {
            version.removeFirst()
        }
        return version
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)
        for index in 0 ..< count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a > b { return .orderedDescending }
            if a < b { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version
            .split { !$0.isNumber }
            .map { Int($0) ?? 0 }
    }

    private func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }

    private func setActiveDownload(_ download: AppUpdateDownloadDelegate?) {
        activeDownloadLock.lock()
        activeDownload = download
        activeDownloadLock.unlock()
    }
}

private final class AppUpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let expectedSize: Int64
    let onProgress: @Sendable (Double) -> Void
    var continuation: CheckedContinuation<URL, Error>?
    var session: URLSession?
    private var downloadedURL: URL?
    private var didFinish = false

    init(destination: URL, expectedSize: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        guard expected > 0 else { return }
        let fraction = min(1, max(0, Double(totalBytesWritten) / Double(expected)))
        onProgress(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            downloadedURL = destination
            onProgress(1)
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else if let downloadedURL {
            finish(.success(downloadedURL))
        } else if !didFinish {
            finish(.failure(URLError(.unknown)))
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !didFinish else { return }
        didFinish = true
        session?.invalidateAndCancel()
        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let size: Int
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadURL = "browser_download_url"
    }
}
