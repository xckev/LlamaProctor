//
//  ContentView.swift
//  LlamaProctor
//
//  Created by Kevin Xiao on 6/21/25.
//

import SwiftUI
import Combine
import Cocoa
@preconcurrency import ScreenCaptureKit

class StreamManager: NSObject, ObservableObject {
    private var stream: SCStream?
    private var output: ContentView.ScreenshotStreamOutput?
    private var isCapturing = false
    
    override init() {
        super.init()
        setupStream()
    }
    
    private func setupStream() {
        Task { @MainActor in
            do {
                let displays = try await SCShareableContent.current.displays
                guard let mainDisplay = displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                    print("Main display not found")
                    return
                }

                let config = SCStreamConfiguration()
                config.width = mainDisplay.width
                config.height = mainDisplay.height
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.capturesAudio = false
                config.sampleRate = 0
                config.channelCount = 0

                let stream = SCStream(filter: SCContentFilter(display: mainDisplay, excludingWindows: []), configuration: config, delegate: nil)
                
                let output = ContentView.ScreenshotStreamOutput()
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue.main)
                
                self.stream = stream
                self.output = output
                
                print("Stream setup completed")
            } catch {
                print("Stream setup failed: \(error)")
            }
        }
    }

    func captureScreenshot(completion: @escaping (NSImage?) -> Void) {
        guard let stream = stream, let output = output else {
            print("Stream not ready")
            completion(nil)
            return
        }
        
        guard !isCapturing else {
            print("Already capturing, skipping")
            return
        }
        
        isCapturing = true
        output.onCapture = { [weak self] (image: NSImage?) in
            // Only call completion if we actually got an image
            if let image = image {
                completion(image)
            } else {
                print("Failed to capture screenshot, keeping previous image")
            }
            self?.isCapturing = false
        }
        
        Task { [weak self] in
            do {
                try await stream.startCapture()
                
                // Stop after a short delay to capture one frame
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    Task {
                        do {
                            try await stream.stopCapture()
                        } catch {
                            print("Error stopping stream: \(error)")
                            self?.isCapturing = false
                        }
                    }
                }
            } catch {
                print("Error starting capture: \(error)")
                self?.isCapturing = false
                completion(nil)
            }
        }
    }
    
    deinit {
        // Don't use Task in deinit as it can cause issues
        // The stream will be cleaned up automatically
        print("StreamManager deinitialized")
    }
}

struct ContentView: View {
    @State private var screenshotTimerCancellable: AnyCancellable?
    @State private var windowTimerCancellable: AnyCancellable?
    @State private var windowsInfo: [String] = []
    @State private var latestScreenshot: NSImage? = nil
    @StateObject private var streamManager = StreamManager()

    var body: some View {
        VStack(alignment: .leading) {
            Text("LlamaProctor Running")
                .font(.headline)
            Divider()
            Text("Active Window:")
                .font(.subheadline)
            List(windowsInfo, id: \.self) { window in
                Text(window)
            }
            Divider()
            if let image = latestScreenshot {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 500)
            } else {
                Text("No screenshot available")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            startBackgroundTasks()
        }
        .onDisappear {
            screenshotTimerCancellable?.cancel()
            windowTimerCancellable?.cancel()
        }
    }

    func startBackgroundTasks() {
        // Give the stream manager a moment to set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Screenshot timer - every 7 seconds
            screenshotTimerCancellable = Timer.publish(every: 8, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    streamManager.captureScreenshot { image in
                        DispatchQueue.main.async {
                            // Only update if we got a new image
                            if let image = image {
                                latestScreenshot = image
                            }
                        }
                    }
                    print("Screenshot capture attempt")
                }
            
            // Window info timer - every 1 second
            windowTimerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    let windowTitles = getOpenWindowTitles()
                    windowsInfo = windowTitles
                    print("Captured windows: \(windowTitles)")
                }
        }
    }
    
    class ScreenshotStreamOutput: NSObject, SCStreamOutput {
        var onCapture: ((NSImage?) -> Void)?

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
            guard let pixelBuffer = sampleBuffer.imageBuffer else {
                print("No image buffer in sample - skipping this frame")
                DispatchQueue.main.async { [weak self] in
                    self?.onCapture?(nil)
                }
                return
            }
            
            // Additional validation
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            guard width > 0 && height > 0 else {
                print("Invalid pixel buffer dimensions: \(width)x\(height)")
                DispatchQueue.main.async { [weak self] in
                    self?.onCapture?(nil)
                }
                return
            }
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let rep = NSCIImageRep(ciImage: ciImage)
            let nsImage = NSImage(size: rep.size)
            nsImage.addRepresentation(rep)
            
            print("Successfully captured screenshot: \(width)x\(height)")
            DispatchQueue.main.async { [weak self] in
                self?.onCapture?(nsImage)
            }
        }
        
        func stream(_ stream: SCStream, didStopWithError error: Error) {
            print("Stream stopped with error: \(error)")
        }
    }

    func getOpenWindowTitles() -> [String] {
        guard let windowListInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        guard let frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return []
        }

        return windowListInfo.compactMap { dict in
            guard let pid = dict["kCGWindowOwnerPID"] as? pid_t,
                  pid == frontmostAppPID,
                  let ownerName = dict["kCGWindowOwnerName"] as? String,
                  let windowName = dict["kCGWindowName"] as? String else {
                return nil
            }
            return "\(ownerName): \(windowName)"
        }
    }
}

#Preview {
    ContentView()
}
