import Foundation
import ScreenCaptureKit
@preconcurrency import AVFoundation
import AppKit
import CoreGraphics

/// Controls the actual screen capture process using ScreenCaptureKit
/// Provides modular recording functionality with proper error handling
@available(macOS 12.3, *)
class CaptureController {
    
    private var currentDelegate: CaptureDelegate?
    private var currentStream: SCStream?
    private var isStreamStopped = false
    
    /// Error types for capture operations
    enum CaptureError: LocalizedError {
        case contentRetrievalFailed(Error)
        case streamCreationFailed(Error)
        case captureStartFailed(Error)
        case captureStopFailed(Error)
        case configurationError(String)
        
        var errorDescription: String? {
            switch self {
            case .contentRetrievalFailed(let error):
                return "Failed to retrieve shareable content: \(error.localizedDescription)"
            case .streamCreationFailed(let error):
                return "Failed to create capture stream: \(error.localizedDescription)"
            case .captureStartFailed(let error):
                return "Failed to start capture: \(error.localizedDescription)"
            case .captureStopFailed(let error):
                return "Failed to stop capture: \(error.localizedDescription)"
            case .configurationError(let message):
                return "Configuration error: \(message)"
            }
        }
    }
    
    /// Delegate for handling capture output
    private class CaptureDelegate: NSObject, SCStreamOutput {
        let videoInput: AVAssetWriterInput
        let audioInput: AVAssetWriterInput?
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let writer: AVAssetWriter
        private var startTime: CMTime?
        private var shouldStop = false
        private var frameCount = 0
        private var audioSampleCount = 0
        
        // 麦克风录制相关
        private var audioEngine: AVAudioEngine?
        private var microphoneInput: AVAssetWriterInput?
        private var audioMixer: AVAudioMixerNode?
        private let includeMicrophone: Bool
        
        init(videoInput: AVAssetWriterInput, 
             audioInput: AVAssetWriterInput?, 
             adaptor: AVAssetWriterInputPixelBufferAdaptor, 
             writer: AVAssetWriter,
             includeMicrophone: Bool = false) {
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.adaptor = adaptor
            self.writer = writer
            self.includeMicrophone = includeMicrophone
            
            super.init()
            
            // 如果需要麦克风，设置音频引擎
            if includeMicrophone {
                setupMicrophoneRecording()
            }
        }
        
        private func setupMicrophoneRecording() {
            do {
                audioEngine = AVAudioEngine()
                guard let audioEngine = audioEngine else { return }
                
                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                
                // 创建混音器节点
                audioMixer = AVAudioMixerNode()
                guard let audioMixer = audioMixer else { return }
                
                audioEngine.attach(audioMixer)
                audioEngine.connect(inputNode, to: audioMixer, format: recordingFormat)
                audioEngine.connect(audioMixer, to: audioEngine.outputNode, format: recordingFormat)
                
                // 安装音频处理回调
                audioMixer.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
                    self?.processMicrophoneAudio(buffer: buffer, time: time)
                }
                
                try audioEngine.start()
                print("🎤 Microphone audio engine started successfully")
                
            } catch {
                print("⚠️ Failed to setup microphone recording: \(error.localizedDescription)")
                audioEngine = nil
                audioMixer = nil
            }
        }
        
        private func processMicrophoneAudio(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
            // 暂时只记录麦克风音频处理，避免干扰系统音频录制
            // 实际的音频混合需要更复杂的实现
            if frameCount % 1000 == 0 { // 减少日志频率
                print("🎤 Microphone audio detected (not yet mixed)")
            }
        }
        
        func stopCapture() {
            shouldStop = true
            
            // 停止麦克风录制
            if let audioEngine = audioEngine {
                audioMixer?.removeTap(onBus: 0)
                audioEngine.stop()
                print("🎤 Microphone audio engine stopped")
            }
        }
        
        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
            // Stop processing if we've been told to stop
            if shouldStop {
                return
            }
            
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            // Initialize session timing on first frame
            if startTime == nil {
                startTime = timestamp
                writer.startSession(atSourceTime: startTime!)
            }
            
            // Don't check duration here - let the main recording loop handle timing
            
            switch outputType {
            case .screen:
                guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
                

                
                if videoInput.isReadyForMoreMediaData && !shouldStop {
                    let success = adaptor.append(pixelBuffer, withPresentationTime: timestamp)
                    frameCount += 1
                    if !success {
                        print("⚠️ Failed to append video frame at timestamp: \(CMTimeGetSeconds(timestamp))")
                        print("   Frame count: \(frameCount), Video input ready: \(videoInput.isReadyForMoreMediaData)")
                    } else if frameCount % 600 == 0 { // Log every 600 frames (20 seconds at 30fps)
                        print("📹 Video frames processed: \(frameCount) (timestamp: \(String(format: "%.2f", CMTimeGetSeconds(timestamp)))s)")
                    }
                }
            case .audio:
                if let audioInput = audioInput, audioInput.isReadyForMoreMediaData && !shouldStop {
                    let success = audioInput.append(sampleBuffer)
                    audioSampleCount += 1
                    if !success {
                        print("⚠️ Failed to append audio sample at timestamp: \(CMTimeGetSeconds(timestamp))")
                        print("   Audio samples: \(audioSampleCount), Audio input ready: \(audioInput.isReadyForMoreMediaData)")
                    } else if audioSampleCount % 1000 == 0 { // Log every 1000 audio samples
                        print("🎵 Audio samples processed: \(audioSampleCount) (timestamp: \(String(format: "%.2f", CMTimeGetSeconds(timestamp)))s)")
                    }
                }
            default:
                break
            }
        }
    }
    
    /// Start screen capture with the given configuration
    /// - Parameters:
    ///   - config: Recording configuration
    ///   - writer: AVAssetWriter for output
    ///   - videoInput: Video input for the writer
    ///   - audioInput: Optional audio input for the writer
    ///   - adaptor: Pixel buffer adaptor for video
    /// - Returns: SCStream instance for the capture
    /// - Throws: CaptureError if capture setup fails
    func startCapture(
        with config: RecordingConfiguration,
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        audioInput: AVAssetWriterInput?,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) async throws -> SCStream {
        
        // 🔧 修复：对于应用录制，先将应用置于前台
        // Exact-window mode (.window) never reaches this branch: --activation preserve means no raise, no focus.
        if config.recordingMode == .application, let targetApp = config.targetApplication {
            do {
                let appManager = ApplicationManager()
                try appManager.bringApplicationToFront(targetApp)
                
                // 给系统更多时间来完成窗口切换和桌面空间切换
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
                
                print("   Waiting for application to be fully visible...")
            } catch {
                print("⚠️ Warning: Could not bring application to front: \(error.localizedDescription)")
                print("   Recording will continue, but the application may be obscured")
            }
        }
        
        // Get shareable content
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.contentRetrievalFailed(error)
        }
        
        // Create stream configuration
        let streamConfig = try createStreamConfiguration(from: config, content: content)
        
        // Create content filter
        let filter = try createContentFilter(from: config, content: content)
        
        // Create capture delegate
        let delegate = CaptureDelegate(
            videoInput: videoInput,
            audioInput: audioInput,
            adaptor: adaptor,
            writer: writer,
            includeMicrophone: config.audioSettings.includeMicrophone
        )
        
        // Store delegate reference for later use
        self.currentDelegate = delegate
        
        // Create stream
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        
        // Store stream reference and reset stopped flag
        self.currentStream = stream
        self.isStreamStopped = false
        
        // Add stream outputs
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInitiated)
        let audioQueue = DispatchQueue(label: "audioQueue", qos: .userInitiated)
        
        do {
            try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: videoQueue)
        } catch {
            throw CaptureError.captureStartFailed(error)
        }
        
        // Add audio output if enabled
        if config.audioSettings.hasAudio {
            do {
                if #available(macOS 13.0, *) {
                    try stream.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: audioQueue)
                    if config.verbose {
                        print("✅ System audio stream added successfully")
                    }
                }
            } catch {
                print("⚠️ Warning: Failed to add system audio output: \(error.localizedDescription)")
                // Continue without system audio rather than failing completely
            }
        }
        
        // 🔧 新增：如果启用了麦克风，需要单独处理麦克风音频
        if config.audioSettings.includeMicrophone {
            print("🎤 Microphone recording enabled - will be mixed with system audio")
            // 注意：ScreenCaptureKit 主要处理系统音频，麦克风音频需要通过 AVAudioEngine 单独处理
            // 这需要在 OutputManager 中实现音频混合逻辑
        }
        
        // Start capture
        do {
            try await stream.startCapture()
        } catch {
            throw CaptureError.captureStartFailed(error)
        }
        
        return stream
    }
    
    /// Stop screen capture
    /// - Parameter stream: SCStream to stop
    /// - Throws: CaptureError if stop fails
    func stopCapture(_ stream: SCStream) async throws {
        // Check if this stream has already been stopped
        guard !isStreamStopped else {
            print("ℹ️ Stream stop already in progress or completed, skipping...")
            return
        }
        
        // Mark as stopped to prevent concurrent stop attempts
        isStreamStopped = true
        
        // First tell the delegate to stop processing new frames
        currentDelegate?.stopCapture()
        
        do {
            try await stream.stopCapture()
        } catch {
            // Check if the error is about stopping an already stopped stream
            let nsError = error as NSError
            if nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && nsError.code == -3808 {
                // Stream is already stopped, this is not an error in our context
                print("ℹ️ Stream was already stopped, continuing cleanup...")
            } else {
                throw CaptureError.captureStopFailed(error)
            }
        }
        
        // Clear references
        currentDelegate = nil
        currentStream = nil
    }
    
    /// Create ScreenCaptureKit stream configuration from recording configuration
    /// - Parameters:
    ///   - config: Recording configuration
    ///   - content: Shareable content for validation
    /// - Returns: Configured SCStreamConfiguration
    /// - Throws: CaptureError if configuration is invalid
    private func createStreamConfiguration(
        from config: RecordingConfiguration, 
        content: SCShareableContent
    ) throws -> SCStreamConfiguration {
        
        let streamConfig = SCStreamConfiguration()
        
        // Configure recording area and resolution
        let (sourceRect, outputSize) = try calculateRecordingDimensions(
            config: config, 
            content: content
        )
        
        if config.recordingMode != .window {
            streamConfig.sourceRect = sourceRect
        }
        streamConfig.width = Int(outputSize.width)
        streamConfig.height = Int(outputSize.height)
        
        // Configure video settings
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.minimumFrameInterval = config.videoSettings.frameInterval
        streamConfig.showsCursor = config.videoSettings.showCursor
        
        // 🔧 修复：对于应用录制的特殊配置
        if config.recordingMode == .application {
            // 应用录制时的关键设置
            streamConfig.scalesToFit = false  // 禁用自动缩放
            
            // 版本兼容的设置
            if #available(macOS 14.0, *) {
                streamConfig.preservesAspectRatio = true  // 保持宽高比
                streamConfig.captureResolution = .best
            }
            
            // 对于应用录制，不设置sourceRect，让系统自动处理
            if sourceRect == CGRect.null {
                // 不设置sourceRect，使用完整窗口
                print("   Using full window capture (no sourceRect)")
            }
        } else {
            // 屏幕录制时保持原有设置
            streamConfig.scalesToFit = false
        }
        
        if config.recordingMode == .window {
            streamConfig.scalesToFit = false
            if #available(macOS 14.0, *) {
                streamConfig.preservesAspectRatio = true
                streamConfig.captureResolution = .best
                streamConfig.ignoreShadowsSingleWindow = true // frame == window, no drop shadow padding
            }
        }
        
        // Configure color space and quality: Rec.709 frames (matches the Rec.709 tags written by the encoder)
        streamConfig.colorSpaceName = CGColorSpace.itur_709
        streamConfig.backgroundColor = CGColor.clear
        
        // Configure advanced settings for macOS 14+
        if #available(macOS 14.0, *) {
            streamConfig.queueDepth = 8
        }
        
        // Configure audio if enabled
        if config.audioSettings.hasAudio {
            if #available(macOS 13.0, *) {
                streamConfig.capturesAudio = true
            }
        }
        
        // Log capture configuration only in verbose mode
        if config.verbose {
            print("📹 Capture Configuration:")
            print("   Recording Mode: \(config.recordingMode)")
            if let screen = config.targetScreen {
                print("   Target Screen: \(screen.index) (\(screen.name))")
                print("   Screen Frame: \(screen.frame)")
                print("   Scale Factor: \(screen.scaleFactor)x")
            }
            print("   Source Rect: \(sourceRect)")
            print("   Output Size: \(Int(outputSize.width)) × \(Int(outputSize.height))")
            print("   Frame Rate: \(config.videoSettings.fps) fps")
            print("   Show Cursor: \(config.videoSettings.showCursor)")
            print("   Audio Enabled: \(config.audioSettings.hasAudio)")
        }
        return streamConfig
    }
    
    /// Create content filter based on recording configuration
    /// - Parameters:
    ///   - config: Recording configuration
    ///   - content: Shareable content
    /// - Returns: Configured SCContentFilter
    /// - Throws: CaptureError if filter creation fails
    private func createContentFilter(
        from config: RecordingConfiguration,
        content: SCShareableContent
    ) throws -> SCContentFilter {
        
        // 🔧 智能混合模式：当应用录制需要系统音频且不包含麦克风时，切换到屏幕录制模式
        // 如果同时需要麦克风，保持应用录制模式并尝试混合音频
        if config.recordingMode == .application && config.audioSettings.forceSystemAudio && !config.audioSettings.includeMicrophone {
            print("🔄 Smart Hybrid Mode: Switching to screen recording for system-wide audio")
            print("   Will record the screen area containing the application window")
            
            guard let targetApp = config.targetApplication else {
                throw CaptureError.configurationError("No target application specified")
            }
            
            // 找到应用窗口
            let appWindows = content.windows.filter { window in
                window.owningApplication?.bundleIdentifier == targetApp.bundleIdentifier
            }
            
            guard let appWindow = appWindows.first else {
                throw CaptureError.configurationError("No windows found for target application '\(targetApp.name)'")
            }
            
            // 找到包含应用窗口的显示器
            let windowCenter = CGPoint(
                x: appWindow.frame.origin.x + appWindow.frame.width / 2,
                y: appWindow.frame.origin.y + appWindow.frame.height / 2
            )
            
            var targetDisplay: SCDisplay?
            let screens = NSScreen.screens
            
            for screen in screens {
                if screen.frame.contains(windowCenter) {
                    let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                    targetDisplay = content.displays.first { $0.displayID == screenNumber }
                    break
                }
            }
            
            if targetDisplay == nil {
                targetDisplay = content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first!
            }
            
            print("   Target Display: ID \(targetDisplay!.displayID)")
            print("   Window Area: \(Int(appWindow.frame.origin.x)), \(Int(appWindow.frame.origin.y)), \(Int(appWindow.frame.width)) × \(Int(appWindow.frame.height))")
            
            return SCContentFilter(display: targetDisplay!, excludingWindows: [])
        }
        
        switch config.recordingMode {
        case .window:
            guard let target = config.windowTarget else {
                throw CaptureError.configurationError("No target window specified")
            }
            let window = try WindowResolver.resolve(target, in: content)
            return SCContentFilter(desktopIndependentWindow: window)
        case .screen:
            // Screen recording mode
            let targetDisplay: SCDisplay
            
            if let screenInfo = config.targetScreen {
                // Find the display matching the screen info
                guard let display = content.displays.first(where: { $0.displayID == screenInfo.displayID }) else {
                    throw CaptureError.configurationError("Target screen not found in available displays")
                }
                targetDisplay = display
            } else {
                // Use primary display
                guard let display = content.displays.first else {
                    throw CaptureError.configurationError("No displays available for recording")
                }
                targetDisplay = display
            }
            
            return SCContentFilter(display: targetDisplay, excludingWindows: [])
            
        case .application:
            // Application recording mode
            guard let targetApp = config.targetApplication else {
                throw CaptureError.configurationError("No target application specified for application recording")
            }
            
            // Find the application in shareable content
            guard content.applications.contains(where: { 
                $0.bundleIdentifier == targetApp.bundleIdentifier 
            }) else {
                throw CaptureError.configurationError("Target application not found in shareable content")
            }
            
            // Get windows for the application
            let appWindows = content.windows.filter { window in
                window.owningApplication?.bundleIdentifier == targetApp.bundleIdentifier
            }
            
            if appWindows.isEmpty {
                throw CaptureError.configurationError("No windows found for target application '\(targetApp.name)'")
            }
            
            // 🔧 修复：选择最佳窗口进行录制
            // 优先选择有标题且尺寸较大的窗口（通常是主窗口）
            let bestWindow = appWindows.max { lhs, rhs in
                // 首先比较是否有标题
                let lhsHasTitle = !(lhs.title?.isEmpty ?? true)
                let rhsHasTitle = !(rhs.title?.isEmpty ?? true)
                
                if lhsHasTitle != rhsHasTitle {
                    return rhsHasTitle // 有标题的窗口优先
                }
                
                // 如果都有标题或都没标题，比较窗口面积
                let lhsArea = lhs.frame.width * lhs.frame.height
                let rhsArea = rhs.frame.width * rhs.frame.height
                return lhsArea < rhsArea // 面积大的窗口优先
            } ?? appWindows.first!
            
            print("🎯 Selected window for recording:")
            print("   Title: '\((bestWindow.title?.isEmpty ?? true) ? "Untitled" : bestWindow.title!)'")
            print("   Size: \(Int(bestWindow.frame.width)) × \(Int(bestWindow.frame.height))")
            print("   Position: (\(Int(bestWindow.frame.origin.x)), \(Int(bestWindow.frame.origin.y)))")
            

            
            return SCContentFilter(desktopIndependentWindow: bestWindow)
        }
    }
    
    /// Calculate recording dimensions based on configuration
    /// - Parameters:
    ///   - config: Recording configuration
    ///   - content: Shareable content for screen information
    /// - Returns: Tuple of source rect and output size
    /// - Throws: CaptureError if calculation fails
    private func calculateRecordingDimensions(
        config: RecordingConfiguration,
        content: SCShareableContent
    ) throws -> (sourceRect: CGRect, outputSize: CGSize) {
        
        // 🔧 处理混合模式：应用录制 + 系统音频 = 屏幕录制模式但使用应用窗口区域
        if config.recordingMode == .application && config.audioSettings.forceSystemAudio {
            return try calculateHybridRecordingDimensions(config: config, content: content)
        }
        
        switch config.recordingMode {
        case .screen:
            return try calculateScreenRecordingDimensions(config: config, content: content)
        case .application:
            return try calculateApplicationRecordingDimensions(config: config, content: content)
        case .window:
            // Whole window; ScreenCaptureKit uses the full window area when sourceRect is left empty
            return (sourceRect: CGRect.zero, outputSize: config.videoSettings.resolution)
        }
    }
    
    /// Calculate dimensions for screen recording
    private func calculateScreenRecordingDimensions(
        config: RecordingConfiguration,
        content: SCShareableContent
    ) throws -> (sourceRect: CGRect, outputSize: CGSize) {
        
        let targetDisplay: SCDisplay
        
        if let screenInfo = config.targetScreen {
            guard let display = content.displays.first(where: { $0.displayID == screenInfo.displayID }) else {
                throw CaptureError.configurationError("Target screen not found")
            }
            targetDisplay = display
        } else {
            guard let display = content.displays.first else {
                throw CaptureError.configurationError("No displays available")
            }
            targetDisplay = display
        }
        
        // Get screen information from NSScreen for scale factor
        let screens = NSScreen.screens
        guard let nsScreen = screens.first(where: { 
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == targetDisplay.displayID 
        }) else {
            throw CaptureError.configurationError("Could not find NSScreen for display")
        }
        
        let scaleFactor = nsScreen.backingScaleFactor
        let logicalFrame = nsScreen.frame
        
        // 🔧 修复：使用屏幕本地坐标系计算录制区域
        let screenInfo = ScreenInfo(
            index: 1,
            displayID: targetDisplay.displayID,
            frame: logicalFrame,
            name: "Display",
            isPrimary: true,
            scaleFactor: scaleFactor
        )
        
        // 获取录制区域（像素坐标）
        let recordingRect = config.recordingArea.toCGRect(for: screenInfo)
        let actualWidth = Int(recordingRect.width)
        let actualHeight = Int(recordingRect.height)
        
        // 🔧 关键修复：对于ScreenCaptureKit，使用屏幕本地逻辑坐标
        // 不需要考虑屏幕在全局坐标系中的偏移
        let logicalSourceRect = config.recordingArea.toLogicalRect(for: screenInfo)
        
        return (
            sourceRect: logicalSourceRect,
            outputSize: CGSize(width: actualWidth, height: actualHeight)
        )
    }
    
    /// Calculate dimensions for application recording
    private func calculateApplicationRecordingDimensions(
        config: RecordingConfiguration,
        content: SCShareableContent
    ) throws -> (sourceRect: CGRect, outputSize: CGSize) {
        
        guard let targetApp = config.targetApplication else {
            throw CaptureError.configurationError("No target application specified")
        }
        
        // Find application windows in ScreenCaptureKit content
        let appWindows = content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == targetApp.bundleIdentifier
        }
        
        guard !appWindows.isEmpty else {
            throw CaptureError.configurationError("No windows found for target application '\(targetApp.name)'")
        }
        
        // 🔧 修复：使用与内容过滤器相同的窗口选择逻辑
        let scWindow = appWindows.max { lhs, rhs in
            // 首先比较是否有标题
            let lhsHasTitle = !(lhs.title?.isEmpty ?? true)
            let rhsHasTitle = !(rhs.title?.isEmpty ?? true)
            
            if lhsHasTitle != rhsHasTitle {
                return rhsHasTitle // 有标题的窗口优先
            }
            
            // 如果都有标题或都没标题，比较窗口面积
            let lhsArea = lhs.frame.width * lhs.frame.height
            let rhsArea = rhs.frame.width * rhs.frame.height
            return lhsArea < rhsArea // 面积大的窗口优先
        } ?? appWindows.first!
        
        // Get the ScreenCaptureKit window frame (this is already in the correct coordinate system)
        let scWindowFrame = scWindow.frame
        
        // Find the display that contains this window to get the correct scale factor
        let windowCenter = CGPoint(
            x: scWindowFrame.origin.x + scWindowFrame.width / 2,
            y: scWindowFrame.origin.y + scWindowFrame.height / 2
        )
        
        // Get the display containing the window center
        let screens = NSScreen.screens
        var scaleFactor: CGFloat = 1.0
        var containingScreen: NSScreen?
        
        for screen in screens {
            // Convert screen frame to match ScreenCaptureKit coordinate system
            let screenFrame = screen.frame
            let flippedScreenFrame = CGRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: screenFrame.width,
                height: screenFrame.height
            )
            
            if flippedScreenFrame.contains(windowCenter) {
                scaleFactor = screen.backingScaleFactor
                containingScreen = screen
                break
            }
        }
        
        // If no screen contains the window center, use the main screen's scale factor
        if scaleFactor == 1.0 {
            scaleFactor = NSScreen.main?.backingScaleFactor ?? 1.0
            containingScreen = NSScreen.main
        }
        
        // 🔧 修复：使用ScreenCaptureKit窗口的实际尺寸
        // ScreenCaptureKit已经提供了正确的窗口边界，不需要额外的坐标转换
        let actualWidth = scWindowFrame.width
        let actualHeight = scWindowFrame.height
        
        // 计算输出像素尺寸 - 使用实际窗口尺寸乘以缩放因子
        let outputWidth = Int(actualWidth * scaleFactor)
        let outputHeight = Int(actualHeight * scaleFactor)
        
        print("🔍 Application Recording Debug:")
        print("   Found \(appWindows.count) windows for '\(targetApp.name)'")
        for (index, window) in appWindows.enumerated() {
            let title = (window.title?.isEmpty ?? true) ? "Untitled" : window.title!
            print("     \(index + 1). '\(title)' - \(Int(window.frame.width))×\(Int(window.frame.height))")
        }
        print("   Selected Window: '\((scWindow.title?.isEmpty ?? true) ? "Untitled" : scWindow.title!)'")
        print("   SCWindow Frame: \(Int(scWindowFrame.origin.x)), \(Int(scWindowFrame.origin.y)), \(Int(actualWidth)) × \(Int(actualHeight))")
        print("   Scale Factor: \(scaleFactor)x")
        print("   Output Size (pixels): \(outputWidth) × \(outputHeight)")
        print("   Containing Screen: \(containingScreen?.localizedName ?? "Unknown")")
        
        // 🔧 关键修复：不使用sourceRect，让ScreenCaptureKit自动处理窗口边界
        // 对于应用窗口录制，sourceRect应该设置为CGRect.null或窗口的完整区域
        return (
            sourceRect: CGRect.null, // 让ScreenCaptureKit自动使用完整窗口区域
            outputSize: CGSize(width: outputWidth, height: outputHeight)
        )
    }
    
    /// Calculate dimensions for hybrid recording (app window area on screen for system audio)
    private func calculateHybridRecordingDimensions(
        config: RecordingConfiguration,
        content: SCShareableContent
    ) throws -> (sourceRect: CGRect, outputSize: CGSize) {
        
        guard let targetApp = config.targetApplication else {
            throw CaptureError.configurationError("No target application specified")
        }
        
        // 找到应用窗口
        let appWindows = content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == targetApp.bundleIdentifier
        }
        
        guard let appWindow = appWindows.first else {
            throw CaptureError.configurationError("No windows found for target application '\(targetApp.name)'")
        }
        
        // 获取窗口所在的屏幕信息
        let windowCenter = CGPoint(
            x: appWindow.frame.origin.x + appWindow.frame.width / 2,
            y: appWindow.frame.origin.y + appWindow.frame.height / 2
        )
        
        let screens = NSScreen.screens
        var scaleFactor: CGFloat = 1.0
        var containingScreen: NSScreen?
        
        for screen in screens {
            if screen.frame.contains(windowCenter) {
                scaleFactor = screen.backingScaleFactor
                containingScreen = screen
                break
            }
        }
        
        if scaleFactor == 1.0 {
            scaleFactor = NSScreen.main?.backingScaleFactor ?? 1.0
            containingScreen = NSScreen.main
        }
        
        // 🔧 混合模式：使用屏幕录制但限制在应用窗口区域
        let windowFrame = appWindow.frame
        let actualWidth = windowFrame.width
        let actualHeight = windowFrame.height
        
        // 计算输出像素尺寸
        let outputWidth = Int(actualWidth * scaleFactor)
        let outputHeight = Int(actualHeight * scaleFactor)
        
        // 🔧 关键：设置 sourceRect 为应用窗口在屏幕上的位置（逻辑坐标）
        // 这样屏幕录制模式只会录制窗口区域，同时获得系统音频
        let sourceRect = CGRect(
            x: windowFrame.origin.x,
            y: windowFrame.origin.y,
            width: actualWidth,
            height: actualHeight
        )
        
        print("🔍 Hybrid Recording Debug:")
        print("   Window Frame: \(Int(windowFrame.origin.x)), \(Int(windowFrame.origin.y)), \(Int(actualWidth)) × \(Int(actualHeight))")
        print("   Scale Factor: \(scaleFactor)x")
        print("   Source Rect (logical): \(Int(sourceRect.origin.x)), \(Int(sourceRect.origin.y)), \(Int(sourceRect.width)) × \(Int(sourceRect.height))")
        print("   Output Size (pixels): \(outputWidth) × \(outputHeight)")
        print("   Containing Screen: \(containingScreen?.localizedName ?? "Unknown")")
        
        return (
            sourceRect: sourceRect,
            outputSize: CGSize(width: outputWidth, height: outputHeight)
        )
    }
}