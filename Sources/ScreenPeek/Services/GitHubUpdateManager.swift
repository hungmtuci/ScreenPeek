import Foundation
import AppKit

struct GitHubReleaseInfo: Equatable {
    let tagName: String
    let versionString: String
    let title: String
    let releaseNotes: String
    let htmlURL: URL
    let publishedAt: Date?
    let zipDownloadURL: URL?
    let zipAssetName: String?
    let zipByteCount: Int64?

    var formattedZipSize: String? {
        guard let bytes = zipByteCount, bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(GitHubReleaseInfo)
    case downloading(progress: Double, downloadedMB: Double, totalMB: Double)
    case installing
    case downloadedToDownloadsFolder(URL)
    case error(String)
}

private struct GitHubReleaseAPIResponse: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
        let content_type: String?
    }

    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let draft: Bool?
    let prerelease: Bool?
    let published_at: String?
    let assets: [Asset]?
}

@MainActor
final class GitHubUpdateManager: NSObject, ObservableObject {
    static let shared = GitHubUpdateManager()

    static let repoOwner = "hungmtuci"
    static let repoName = "ScreenPeek"
    static let repositoryURL = URL(string: "https://github.com/hungmtuci/ScreenPeek")!
    static let releasesPageURL = URL(string: "https://github.com/hungmtuci/ScreenPeek/releases")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/hungmtuci/ScreenPeek/releases/latest")!

    private var isInitialized: Bool = false

    @Published var autoCheckUpdates: Bool {
        didSet {
            guard isInitialized else { return }
            UserDefaults.standard.set(autoCheckUpdates, forKey: "ScreenPeek.autoCheckUpdates")
            configurePeriodicTimer()
        }
    }

    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var availableRelease: GitHubReleaseInfo? = nil
    @Published private(set) var lastCheckedDate: Date? = nil

    private var periodicTimer: Timer?
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadSession: URLSession?
    private var downloadDelegate: ReleaseZipDownloadDelegate?

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.3.1"
    }

    var currentBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "6"
    }

    var hasUpdateAvailable: Bool {
        availableRelease != nil
    }

    private override init() {
        if UserDefaults.standard.object(forKey: "ScreenPeek.autoCheckUpdates") != nil {
            self.autoCheckUpdates = UserDefaults.standard.bool(forKey: "ScreenPeek.autoCheckUpdates")
        } else {
            self.autoCheckUpdates = true
        }
        if let savedTimestamp = UserDefaults.standard.object(forKey: "ScreenPeek.lastUpdateCheckTimestamp") as? Double, savedTimestamp > 0 {
            self.lastCheckedDate = Date(timeIntervalSince1970: savedTimestamp)
        }
        super.init()
        self.isInitialized = true
    }

    func startAutomaticChecksIfNeeded() {
        configurePeriodicTimer()
        guard autoCheckUpdates else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, self.autoCheckUpdates else { return }
            await self.checkForUpdates(userInitiated: false)
        }
    }

    private func configurePeriodicTimer() {
        periodicTimer?.invalidate()
        periodicTimer = nil
        guard autoCheckUpdates else { return }

        // Check silently every 12 hours while running
        let timer = Timer(timeInterval: 12 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates(userInitiated: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
    }

    // MARK: - Check for Updates via GitHub API
    func checkForUpdates(userInitiated: Bool = true) async {
        switch state {
        case .checking, .downloading, .installing:
            if userInitiated {
                ScreenPeekAppDelegate.shared?.openSettingsWindow(tab: .updates)
            }
            return
        default:
            break
        }

        state = .checking
        if userInitiated {
            ScreenPeekAppDelegate.shared?.openSettingsWindow(tab: .updates)
        }

        var request = URLRequest(
            url: Self.latestReleaseAPIURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ScreenPeek/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .error("Không nhận được phản hồi hợp lệ từ máy chủ GitHub.")
                return
            }

            if http.statusCode == 404 {
                let now = recordCheckTimestamp()
                availableRelease = nil
                state = .upToDate(checkedAt: now)
                return
            }

            if http.statusCode == 403 {
                state = .error("GitHub API tạm thời giới hạn lượt truy vấn (Rate Limit). Vui lòng thử lại sau ít phút hoặc mở trực tiếp trang GitHub.")
                return
            }

            guard (200...299).contains(http.statusCode) else {
                state = .error("Máy chủ GitHub trả về mã lỗi HTTP \(http.statusCode).")
                return
            }

            let decoded = try JSONDecoder().decode(GitHubReleaseAPIResponse.self, from: data)
            let remoteVersion = Self.cleanVersionString(decoded.tag_name)
            let now = recordCheckTimestamp()

            let isoFormatter = ISO8601DateFormatter()
            let publishedDate = decoded.published_at.flatMap { isoFormatter.date(from: $0) }

            let zipAsset = decoded.assets?.first(where: { $0.name.lowercased() == "screenpeek.zip" })
                ?? decoded.assets?.first(where: { $0.name.lowercased().hasSuffix(".zip") })

            let releaseInfo = GitHubReleaseInfo(
                tagName: decoded.tag_name,
                versionString: remoteVersion,
                title: (decoded.name?.isEmpty == false) ? decoded.name! : "ScreenPeek \(decoded.tag_name)",
                releaseNotes: (decoded.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? decoded.body!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : "Bản cập nhật cải thiện hiệu năng và trải nghiệm người dùng trên macOS.",
                htmlURL: URL(string: decoded.html_url) ?? Self.releasesPageURL,
                publishedAt: publishedDate,
                zipDownloadURL: zipAsset.flatMap { URL(string: $0.browser_download_url) },
                zipAssetName: zipAsset?.name,
                zipByteCount: zipAsset?.size
            )

            if Self.isVersion(remoteVersion, newerThan: currentVersion) {
                availableRelease = releaseInfo
                state = .updateAvailable(releaseInfo)
            } else {
                availableRelease = nil
                state = .upToDate(checkedAt: now)
            }
        } catch {
            if userInitiated {
                state = .error("Không thể kết nối tới GitHub: \(error.localizedDescription)")
            } else {
                state = .idle
            }
        }
    }

    private func recordCheckTimestamp() -> Date {
        let now = Date()
        lastCheckedDate = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "ScreenPeek.lastUpdateCheckTimestamp")
        return now
    }

    // MARK: - Download, Extract & Self-Replace Running App
    func downloadAndInstallUpdate() {
        guard let release = availableRelease else { return }
        guard let downloadURL = release.zipDownloadURL else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }

        cancelDownload(resetState: false)
        let totalExpectedMB = Double(release.zipByteCount ?? 0) / (1024.0 * 1024.0)
        state = .downloading(progress: 0.0, downloadedMB: 0.0, totalMB: max(totalExpectedMB, 0.1))

        let delegate = ReleaseZipDownloadDelegate(
            expectedBytes: release.zipByteCount ?? -1,
            onProgress: { [weak self] progress, downloadedMB, totalMB in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .downloading = self.state {
                        self.state = .downloading(progress: progress, downloadedMB: downloadedMB, totalMB: totalMB)
                    }
                }
            },
            onFinishedFile: { [weak self] tempZipURL in
                Task { @MainActor [weak self] in
                    await self?.processDownloadedArchive(at: tempZipURL, release: release)
                }
            },
            onError: { [weak self] errMsg in
                Task { @MainActor [weak self] in
                    self?.state = .error(errMsg)
                }
            }
        )

        self.downloadDelegate = delegate
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.activeDownloadSession = session

        var req = URLRequest(url: downloadURL)
        req.setValue("ScreenPeek/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: req)
        self.activeDownloadTask = task
        task.resume()
    }

    func cancelDownload(resetState: Bool = true) {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadSession?.invalidateAndCancel()
        activeDownloadSession = nil
        downloadDelegate = nil

        if resetState {
            if let rel = availableRelease {
                state = .updateAvailable(rel)
            } else {
                state = .idle
            }
        }
    }

    private func processDownloadedArchive(at downloadedTempFile: URL, release: GitHubReleaseInfo) async {
        activeDownloadTask = nil
        activeDownloadSession?.finishTasksAndInvalidate()
        activeDownloadSession = nil
        downloadDelegate = nil

        let currentBundleURL = Bundle.main.bundleURL
        let isRunningInsideAppBundle = currentBundleURL.pathExtension.lowercased() == "app"
        let parentDirPath = currentBundleURL.deletingLastPathComponent().path
        let canReplaceInPlace = isRunningInsideAppBundle && FileManager.default.isWritableFile(atPath: parentDirPath)

        // If running from a read-only mount (e.g. DMG) or raw binary, save cleanly to ~/Downloads and reveal in Finder
        if !canReplaceInPlace {
            do {
                let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let destZip = downloadsDir.appendingPathComponent("ScreenPeek-v\(release.versionString).zip")
                if FileManager.default.fileExists(atPath: destZip.path) {
                    try FileManager.default.removeItem(at: destZip)
                }
                try FileManager.default.moveItem(at: downloadedTempFile, to: destZip)
                NSWorkspace.shared.activateFileViewerSelecting([destZip])
                state = .downloadedToDownloadsFolder(destZip)
            } catch {
                try? FileManager.default.removeItem(at: downloadedTempFile)
                state = .error("Không thể lưu bản cập nhật vào thư mục Downloads: \(error.localizedDescription)")
            }
            return
        }

        state = .installing

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenPeekUpdater-\(UUID().uuidString)", isDirectory: true)
        let zipPath = stagingRoot.appendingPathComponent("ScreenPeek.zip")
        let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: downloadedTempFile, to: zipPath)

            // Extract with macOS native /usr/bin/ditto on background thread
            let extractedAppURL = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-x", "-k", zipPath.path, extractDir.path]
                try ditto.run()
                ditto.waitUntilExit()

                guard ditto.terminationStatus == 0 else {
                    throw NSError(domain: "ScreenPeekUpdater", code: Int(ditto.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: "Giải nén gói cập nhật thất bại (mã lỗi ditto \(ditto.terminationStatus))."
                    ])
                }

                // Locate ScreenPeek.app inside extractDir
                let fm = FileManager.default
                let directCandidate = extractDir.appendingPathComponent("ScreenPeek.app")
                var foundApp: URL? = nil

                if fm.fileExists(atPath: directCandidate.path) {
                    foundApp = directCandidate
                } else if let enumerator = fm.enumerator(at: extractDir, includingPropertiesForKeys: nil) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if fileURL.pathExtension.lowercased() == "app" && !fileURL.path.contains("__MACOSX") {
                            foundApp = fileURL
                            break
                        }
                    }
                }

                guard let appBundle = foundApp else {
                    throw NSError(domain: "ScreenPeekUpdater", code: 404, userInfo: [
                        NSLocalizedDescriptionKey: "Không tìm thấy ScreenPeek.app bên trong gói cập nhật tải từ GitHub."
                    ])
                }

                let execPath = appBundle.appendingPathComponent("Contents/MacOS/ScreenPeek").path
                guard fm.fileExists(atPath: execPath) else {
                    throw NSError(domain: "ScreenPeekUpdater", code: 422, userInfo: [
                        NSLocalizedDescriptionKey: "Gói cập nhật không hợp lệ (thiếu tệp thực thi ScreenPeek)."
                    ])
                }

                // Clear Gatekeeper quarantine attributes & ensure executable bit
                let xattr = Process()
                xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattr.arguments = ["-cr", appBundle.path]
                try? xattr.run()
                xattr.waitUntilExit()

                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["+x", execPath]
                try? chmod.run()
                chmod.waitUntilExit()

                return appBundle
            }.value

            // Write detached atomic replacement & relaunch helper script
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let scriptURL = stagingRoot.appendingPathComponent("apply_update.sh")
            let scriptContent = """
            #!/bin/bash
            APP_PID="$1"
            NEW_APP="$2"
            TARGET_APP="$3"
            STAGING_DIR="$4"

            for i in $(seq 1 60); do
                if ! kill -0 "$APP_PID" 2>/dev/null; then
                    break
                fi
                sleep 0.15
            done

            rm -rf "$TARGET_APP"
            /usr/bin/ditto "$NEW_APP" "$TARGET_APP"
            /usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true
            /usr/bin/open "$TARGET_APP"
            sleep 1
            rm -rf "$STAGING_DIR"
            """
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)

            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [
                scriptURL.path,
                "\(currentPID)",
                extractedAppURL.path,
                currentBundleURL.path,
                stagingRoot.path
            ]
            launcher.standardOutput = FileHandle.nullDevice
            launcher.standardError = FileHandle.nullDevice
            launcher.standardInput = FileHandle.nullDevice
            try launcher.run()

            // Gracefully terminate current process so the helper script swaps & relaunches immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                NSApp.terminate(nil)
            }
        } catch {
            try? FileManager.default.removeItem(at: stagingRoot)
            state = .error(error.localizedDescription)
        }
    }

    func openReleasePageInBrowser() {
        if let url = availableRelease?.htmlURL {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(Self.releasesPageURL)
        }
    }

    func openGitHubRepoInBrowser() {
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    // MARK: - Semantic Version Comparison
    static func cleanVersionString(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        if let dashIndex = trimmed.firstIndex(of: "-") {
            trimmed = String(trimmed[..<dashIndex])
        }
        return trimmed
    }

    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let rParts = cleanVersionString(remote).split(separator: ".").map { Int($0) ?? 0 }
        let lParts = cleanVersionString(local).split(separator: ".").map { Int($0) ?? 0 }
        let count = max(rParts.count, lParts.count)
        for i in 0..<count {
            let r = i < rParts.count ? rParts[i] : 0
            let l = i < lParts.count ? lParts[i] : 0
            if r != l {
                return r > l
            }
        }
        return false
    }
}

// MARK: - URLSessionDownloadDelegate Helper
private final class ReleaseZipDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let expectedBytes: Int64
    private let onProgress: (Double, Double, Double) -> Void
    private let onFinishedFile: (URL) -> Void
    private let onError: (String) -> Void
    private var lastUpdateTime: CFAbsoluteTime = 0
    private var didFinish: Bool = false

    init(
        expectedBytes: Int64,
        onProgress: @escaping (Double, Double, Double) -> Void,
        onFinishedFile: @escaping (URL) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
        self.onFinishedFile = onFinishedFile
        self.onError = onError
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        let fraction = total > 0 ? min(max(Double(totalBytesWritten) / Double(total), 0.0), 1.0) : 0.0

        if now - lastUpdateTime >= 0.06 || fraction >= 0.999 {
            lastUpdateTime = now
            let downMB = Double(totalBytesWritten) / (1024.0 * 1024.0)
            let totMB = total > 0 ? Double(total) / (1024.0 * 1024.0) : max(downMB, 0.1)
            onProgress(fraction, downMB, totMB)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        didFinish = true

        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            onError("Tải gói cập nhật thất bại (mã lỗi HTTP \(http.statusCode)).")
            return
        }

        // Move immediately out of URLSession's ephemeral location before this delegate method returns
        let safeTempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenPeekDownload-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: safeTempURL)
            onFinishedFile(safeTempURL)
        } catch {
            onError("Không thể lưu tệp cập nhật tạm thời: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            return
        }
        if !didFinish {
            onError("Tải gói cập nhật bị gián đoạn: \(error.localizedDescription)")
        }
    }
}
