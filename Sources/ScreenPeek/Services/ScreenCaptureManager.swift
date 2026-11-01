import Foundation
import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import QuartzCore

@MainActor
final class ScreenCaptureManager: NSObject, ObservableObject {
    static let shared = ScreenCaptureManager()

    private var isInitialized: Bool = false

    @Published private(set) var availableDisplays: [DisplayInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID? {
        didSet {
            syncCachedDisplayProperties()
            guard isInitialized else { return }
            if oldValue != selectedDisplayID {
                onSelectedDisplayChanged?(selectedDisplay)
                ProjectorOverlayManager.shared.updateOverlayWindows(for: selectedDisplay)
                if !isStoppedByUser {
                    scheduleStreamRestart()
                }
            }
        }
    }

    @Published private(set) var isCapturing: Bool = false {
        didSet {
            guard isInitialized, oldValue != isCapturing else { return }
            CursorAndInputController.shared.refreshTrackingTimerState()
        }
    }
    @Published private(set) var isStoppedByUser: Bool = false {
        didSet {
            guard isInitialized, oldValue != isStoppedByUser else { return }
            CursorAndInputController.shared.refreshTrackingTimerState()
        }
    }
    @Published private(set) var hasScreenRecordingPermission: Bool = true
    @Published private(set) var statusMessage: String = "Đang khởi tạo..."
    @Published private(set) var currentFPS: Int = 0
    @Published private(set) var captureResolutionText: String = ""

    /// Callback invoked on main thread when a new frame arrives (receives IOSurface).
    var onFrameHandler: ((AnyObject?) -> Void)?
    /// Callback invoked when selected display changes (used by WindowController to update aspect ratio).
    var onSelectedDisplayChanged: ((DisplayInfo?) -> Void)?

    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var streamGeneration: UInt64 = 0
    private var activeRestartTask: Task<Void, Never>?
    private let videoSampleQueue = DispatchQueue(label: "com.hunglx.ScreenPeek.VideoSampleQueue", qos: .userInteractive)

    private var frameCounter: Int = 0
    private var lastFPSTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var screenChangeObserver: NSObjectProtocol?
    private var currentPreviewSize: CGSize = CGSize(width: 560, height: 315)
    private var resizeDebounceWorkItem: DispatchWorkItem?

    // O(1) cached display properties (eliminates 60Hz array scans)
    private(set) var selectedDisplay: DisplayInfo?
    private(set) var hasExternalDisplay: Bool = false

    private override init() {
        let initialDisplays = Self.scanConnectedDisplays()
        let initialSelectedID = initialDisplays.first(where: { !$0.isBuiltin })?.id ?? initialDisplays.first?.id
        self.availableDisplays = initialDisplays
        self.selectedDisplayID = initialSelectedID
        self.selectedDisplay = initialDisplays.first(where: { $0.id == initialSelectedID }) ?? initialDisplays.first
        self.hasExternalDisplay = initialDisplays.contains(where: { !$0.isBuiltin })
        super.init()
        observeScreenChanges()
        self.isInitialized = true
    }

    deinit {
        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func syncCachedDisplayProperties() {
        let resolved: DisplayInfo?
        if let id = selectedDisplayID {
            resolved = availableDisplays.first(where: { $0.id == id }) ?? availableDisplays.first
        } else {
            resolved = availableDisplays.first
        }
        selectedDisplay = resolved
        hasExternalDisplay = availableDisplays.contains(where: { !$0.isBuiltin })
    }

    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isInitialized else { return }
                let oldIDs = self.availableDisplays.map(\.id)
                let previousWasBuiltin = self.selectedDisplay?.isBuiltin ?? true
                self.refreshDisplays(autoSelectExternal: previousWasBuiltin)
                let newIDs = self.availableDisplays.map(\.id)

                ProjectorOverlayManager.shared.updateOverlayWindows(for: self.selectedDisplay)

                if oldIDs != newIDs && !self.isStoppedByUser && self.isCapturing {
                    await self.restartCaptureStream()
                }
            }
        }
    }

    private static func scanConnectedDisplays() -> [DisplayInfo] {
        let screens = NSScreen.screens
        var result: [DisplayInfo] = []

        for screen in screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            let isMain = CGDisplayIsMain(id) != 0
            let quartzBounds = CGDisplayBounds(id)
            let pixelW = CGDisplayPixelsWide(id)
            let pixelH = CGDisplayPixelsHigh(id)
            let name = screen.localizedName

            let info = DisplayInfo(
                id: id,
                name: name,
                frame: screen.frame,
                quartzBounds: quartzBounds,
                pixelWidth: pixelW,
                pixelHeight: pixelH,
                isBuiltin: isBuiltin,
                isMain: isMain
            )
            result.append(info)
        }

        result.sort { lhs, rhs in
            if lhs.isBuiltin != rhs.isBuiltin {
                return !lhs.isBuiltin
            }
            return lhs.id < rhs.id
        }
        return result
    }

    func refreshDisplays(autoSelectExternal: Bool = false) {
        let result = Self.scanConnectedDisplays()
        if self.availableDisplays != result {
            self.availableDisplays = result
        }

        if autoSelectExternal, let firstExternal = result.first(where: { !$0.isBuiltin }) {
            if selectedDisplayID != firstExternal.id {
                selectedDisplayID = firstExternal.id
            }
        } else if let currentID = selectedDisplayID, result.contains(where: { $0.id == currentID }) {
            syncCachedDisplayProperties()
        } else {
            selectedDisplayID = result.first?.id
        }
        syncCachedDisplayProperties()
    }

    // MARK: - Dynamic Stream Scaling (Battery & GPU Optimization)
    func notifyPreviewWindowResized(_ newSize: CGSize) {
        guard abs(newSize.width - currentPreviewSize.width) > 24 || abs(newSize.height - currentPreviewSize.height) > 24 else {
            return
        }
        currentPreviewSize = newSize
        scheduleDynamicConfigUpdate()
    }

    func scheduleDynamicConfigUpdate() {
        resizeDebounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                await self?.applyDynamicStreamConfiguration()
            }
        }
        resizeDebounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func buildOptimalStreamConfiguration(for targetDisplay: DisplayInfo) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let aspect = max(targetDisplay.aspectRatio, 0.5)
        let loupeEnabled = CursorAndInputController.shared.loupeMode != .off

        let desiredWidth: Int
        if loupeEnabled {
            // Higher resolution so 2.5x–3.5x Loupe magnification stays crisp
            desiredWidth = min(max(Int(targetDisplay.frame.width * 1.6), 1600), 2560)
        } else {
            // Dynamically match 2x Retina scale of actual preview window size to save GPU & battery!
            let retinaPreviewW = Int(max(currentPreviewSize.width, 380) * 2.0)
            desiredWidth = min(max(retinaPreviewW, 840), 2200)
        }
        // Align to even pixel dimensions
        let evenWidth = (desiredWidth / 2) * 2
        let evenHeight = max((Int(CGFloat(evenWidth) / aspect) / 2) * 2, 480)

        config.width = evenWidth
        config.height = evenHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.scalesToFit = true
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let resText = "\(evenWidth)×\(evenHeight)"
        if self.captureResolutionText != resText {
            self.captureResolutionText = resText
        }
        return config
    }

    func applyDynamicStreamConfiguration() async {
        guard isCapturing, !isStoppedByUser, let activeStream = stream, let targetDisplay = selectedDisplay else {
            return
        }
        let updatedConfig = buildOptimalStreamConfiguration(for: targetDisplay)
        try? await activeStream.updateConfiguration(updatedConfig)
    }

    // MARK: - Stream Lifecycle
    func start() {
        isStoppedByUser = false
        checkPermissionAndStart()
    }

    func pauseQuietlyOnLaunch() {
        isStoppedByUser = true
        isCapturing = false
        currentFPS = 0
        statusMessage = "Đang chạy nền trên thanh Menu Bar."
    }

    func resumeSharing() {
        isStoppedByUser = false
        checkPermissionAndStart()
    }

    func userStopSharing() {
        streamGeneration &+= 1
        activeRestartTask?.cancel()
        activeRestartTask = nil
        isStoppedByUser = true
        ProjectorOverlayManager.shared.disableAllOverlays()
        statusMessage = "Đã dừng chia sẻ màn hình."
        onFrameHandler?(nil)
        Task {
            await stopStream()
        }
    }

    func stopSynchronouslyForTermination() {
        streamGeneration &+= 1
        activeRestartTask?.cancel()
        activeRestartTask = nil
        resizeDebounceWorkItem?.cancel()
        isStoppedByUser = true
        if let existing = stream {
            stream = nil
            streamOutput = nil
            Task {
                try? await existing.stopCapture()
            }
        }
    }

    func handleStreamStoppedBySystem() {
        stream = nil
        streamOutput = nil
        if isCapturing { isCapturing = false }
        if !isStoppedByUser { isStoppedByUser = true }
        ProjectorOverlayManager.shared.disableAllOverlays()
        if currentFPS != 0 { currentFPS = 0 }
        statusMessage = "Đã dừng chia sẻ màn hình."
        onFrameHandler?(nil)
    }

    func checkPermissionAndStart() {
        isStoppedByUser = false
        let preflight = CGPreflightScreenCaptureAccess()
        if self.hasScreenRecordingPermission != preflight {
            self.hasScreenRecordingPermission = preflight
        }
        scheduleStreamRestart()
    }

    func scheduleStreamRestart() {
        activeRestartTask?.cancel()
        activeRestartTask = Task { @MainActor [weak self] in
            await self?.restartCaptureStream()
        }
    }

    func requestScreenCapturePermission() {
        _ = CGRequestScreenCaptureAccess()
        openScreenCaptureSettings()
    }

    func openScreenCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func restartCaptureStream() async {
        streamGeneration &+= 1
        let myGeneration = streamGeneration

        await stopStream()

        guard myGeneration == streamGeneration, !isStoppedByUser, !Task.isCancelled else { return }

        refreshDisplays(autoSelectExternal: false)
        guard let targetDisplay = selectedDisplay else {
            self.statusMessage = "Không tìm thấy màn hình nào."
            if self.isCapturing { self.isCapturing = false }
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            if !self.hasScreenRecordingPermission {
                self.hasScreenRecordingPermission = true
            }

            guard myGeneration == streamGeneration, !isStoppedByUser, !Task.isCancelled else { return }

            guard let scDisplay = content.displays.first(where: { $0.displayID == targetDisplay.id }) ?? content.displays.first else {
                self.statusMessage = "Không thể truy cập màn hình đã chọn."
                if self.isCapturing { self.isCapturing = false }
                return
            }

            // Exclude all windows of our own app (including Preview window, Laser overlay, and Blackout curtain!)
            let myPID = ProcessInfo.processInfo.processIdentifier
            let ownWindows = content.windows.filter { $0.owningApplication?.processID == myPID }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: ownWindows)
            let config = buildOptimalStreamConfiguration(for: targetDisplay)

            let output = CaptureStreamOutput(
                onFrame: { [weak self] surfaceObject in
                    guard let self else { return }
                    self.handleCapturedFrame(surfaceObject)
                },
                onStopped: { [weak self] in
                    guard let self else { return }
                    self.handleStreamStoppedBySystem()
                }
            )

            let newStream = SCStream(filter: filter, configuration: config, delegate: output)
            try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: videoSampleQueue)
            try await newStream.startCapture()

            // Verify no newer restart or stop occurred while awaiting startCapture()
            guard myGeneration == streamGeneration, !isStoppedByUser, !Task.isCancelled else {
                try? await newStream.stopCapture()
                return
            }

            self.streamOutput = output
            self.stream = newStream
            if !self.isCapturing { self.isCapturing = true }
            self.statusMessage = "Đang truyền hình trực tiếp: \(targetDisplay.name)"
        } catch {
            guard myGeneration == streamGeneration else { return }
            let preflight = CGPreflightScreenCaptureAccess()
            if self.hasScreenRecordingPermission != preflight {
                self.hasScreenRecordingPermission = preflight
            }
            if self.isCapturing { self.isCapturing = false }
            if !self.hasScreenRecordingPermission {
                self.statusMessage = "Cần cấp quyền Ghi màn hình (Screen Recording) để hiển thị màn hình kết nối."
            } else {
                self.statusMessage = "Lỗi kết nối màn hình: \(error.localizedDescription)"
            }
        }
    }

    func stopStream() async {
        if let existing = stream {
            stream = nil
            streamOutput = nil
            try? await existing.stopCapture()
        } else {
            streamOutput = nil
        }
        if isCapturing { isCapturing = false }
        if currentFPS != 0 { currentFPS = 0 }
    }

    private func handleCapturedFrame(_ surfaceObject: AnyObject) {
        guard !isStoppedByUser else { return }
        frameCounter += 1
        let now = CACurrentMediaTime()
        let elapsed = now - lastFPSTimestamp
        if elapsed >= 1.0 {
            let newFPS = Int(round(Double(frameCounter) / elapsed))
            if currentFPS != newFPS {
                currentFPS = newFPS
            }
            frameCounter = 0
            lastFPSTimestamp = now
        }
        onFrameHandler?(surfaceObject)
    }
}

private final class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let onFrame: @MainActor (AnyObject) -> Void
    private let onStopped: @MainActor () -> Void

    init(
        onFrame: @escaping @MainActor (AnyObject) -> Void,
        onStopped: @escaping @MainActor () -> Void
    ) {
        self.onFrame = onFrame
        self.onStopped = onStopped
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid else { return }

        // Skip idle/blank/suspended heartbeat sample buffers when screen pixels haven't changed
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let rawStatus = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: rawStatus),
           status != .complete {
            return
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let ioSurface = CVPixelBufferGetIOSurface(imageBuffer)?.takeUnretainedValue() else {
            return
        }

        let surfaceObj = ioSurface as AnyObject
        DispatchQueue.main.async { [onFrame] in
            onFrame(surfaceObj)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [onStopped] in
            onStopped()
        }
    }
}
