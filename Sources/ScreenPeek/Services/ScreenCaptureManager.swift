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
            guard isInitialized else { return }
            if oldValue != selectedDisplayID {
                onSelectedDisplayChanged?(selectedDisplay)
                ProjectorOverlayManager.shared.updateOverlayWindows(for: selectedDisplay)
                if !isStoppedByUser {
                    Task {
                        await restartCaptureStream()
                    }
                }
            }
        }
    }

    @Published private(set) var isCapturing: Bool = false {
        didSet {
            guard isInitialized else { return }
            CursorAndInputController.shared.refreshTrackingTimerState()
        }
    }
    @Published private(set) var isStoppedByUser: Bool = false {
        didSet {
            guard isInitialized else { return }
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
    private let videoSampleQueue = DispatchQueue(label: "com.hunglx.ScreenPeek.VideoSampleQueue", qos: .userInteractive)

    private var frameCounter: Int = 0
    private var lastFPSTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var screenChangeObserver: NSObjectProtocol?
    private var currentPreviewSize: CGSize = CGSize(width: 560, height: 315)
    private var resizeDebounceWorkItem: DispatchWorkItem?

    var selectedDisplay: DisplayInfo? {
        guard let id = selectedDisplayID else { return availableDisplays.first }
        return availableDisplays.first(where: { $0.id == id }) ?? availableDisplays.first
    }

    var hasExternalDisplay: Bool {
        availableDisplays.contains(where: { !$0.isBuiltin })
    }

    private override init() {
        let initialDisplays = Self.scanConnectedDisplays()
        self.availableDisplays = initialDisplays
        self.selectedDisplayID = initialDisplays.first(where: { !$0.isBuiltin })?.id ?? initialDisplays.first?.id
        super.init()
        observeScreenChanges()
        self.isInitialized = true
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
        self.availableDisplays = result

        if autoSelectExternal, let firstExternal = result.first(where: { !$0.isBuiltin }) {
            if selectedDisplayID != firstExternal.id {
                selectedDisplayID = firstExternal.id
            }
        } else if let currentID = selectedDisplayID, result.contains(where: { $0.id == currentID }) {
            // Keep current
        } else {
            selectedDisplayID = result.first?.id
        }
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
        config.queueDepth = 4
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        self.captureResolutionText = "\(evenWidth)×\(evenHeight)"
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

    func resumeSharing() {
        isStoppedByUser = false
        checkPermissionAndStart()
    }

    func userStopSharing() {
        isStoppedByUser = true
        ProjectorOverlayManager.shared.disableAllOverlays()
        statusMessage = "Đã dừng chia sẻ màn hình."
        onFrameHandler?(nil)
        Task {
            await stopStream()
        }
    }

    func handleStreamStoppedBySystem() {
        stream = nil
        streamOutput = nil
        isCapturing = false
        isStoppedByUser = true
        ProjectorOverlayManager.shared.disableAllOverlays()
        currentFPS = 0
        statusMessage = "Đã dừng chia sẻ màn hình."
        onFrameHandler?(nil)
    }

    func checkPermissionAndStart() {
        isStoppedByUser = false
        let preflight = CGPreflightScreenCaptureAccess()
        self.hasScreenRecordingPermission = preflight

        Task {
            await restartCaptureStream()
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
        await stopStream()

        guard !isStoppedByUser else { return }

        refreshDisplays(autoSelectExternal: false)
        guard let targetDisplay = selectedDisplay else {
            self.statusMessage = "Không tìm thấy màn hình nào."
            self.isCapturing = false
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            self.hasScreenRecordingPermission = true

            guard !isStoppedByUser else { return }

            guard let scDisplay = content.displays.first(where: { $0.displayID == targetDisplay.id }) ?? content.displays.first else {
                self.statusMessage = "Không thể truy cập màn hình đã chọn."
                self.isCapturing = false
                return
            }

            // Exclude all windows of our own app (including Preview window, Laser overlay, and Blackout curtain!)
            // This means even when Blackout hides the projector from the audience, ScreenPeek STILL shows the live desktop underneath to the presenter!
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
            self.streamOutput = output

            let newStream = SCStream(filter: filter, configuration: config, delegate: output)
            try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: videoSampleQueue)
            try await newStream.startCapture()

            self.stream = newStream
            self.isCapturing = true
            self.statusMessage = "Đang truyền hình trực tiếp: \(targetDisplay.name)"
        } catch {
            self.hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
            self.isCapturing = false
            if !self.hasScreenRecordingPermission {
                self.statusMessage = "Cần cấp quyền Ghi màn hình (Screen Recording) để hiển thị màn hình kết nối."
            } else {
                self.statusMessage = "Lỗi kết nối màn hình: \(error.localizedDescription)"
            }
        }
    }

    func stopStream() async {
        if let existing = stream {
            try? await existing.stopCapture()
        }
        stream = nil
        streamOutput = nil
        isCapturing = false
        currentFPS = 0
    }

    private func handleCapturedFrame(_ surfaceObject: AnyObject) {
        guard !isStoppedByUser else { return }
        frameCounter += 1
        let now = CACurrentMediaTime()
        let elapsed = now - lastFPSTimestamp
        if elapsed >= 1.0 {
            currentFPS = Int(round(Double(frameCounter) / elapsed))
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
        guard outputType == .screen,
              sampleBuffer.isValid,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
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
