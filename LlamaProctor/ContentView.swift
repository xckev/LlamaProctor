//
//  ContentView.swift
//  LlamaProctor
//
//  Created by Kevin Xiao on 6/21/25.
//

import SwiftUI
import Combine
import Cocoa
import ScreenCaptureKit

struct ContentView: View {
    @State private var timerCancellable: AnyCancellable?
    @State private var windowsInfo: [String] = []

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
        }
        .padding()
        .onAppear {
            startBackgroundTasks()
        }
    }

    func startBackgroundTasks() {
        timerCancellable = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                captureScreenshot()
                let windowTitles = getOpenWindowTitles()
                windowsInfo = windowTitles
                print("Captured windows: \(windowTitles)")
            }
    }
    
    class ScreenshotStreamOutput: NSObject, SCStreamOutput {
        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
            guard sampleBuffer.imageBuffer != nil else {
                print("No image buffer in sample")
                return
            }

            // Process the pixelBuffer here (e.g. convert to image)
            print("Received frame from screen stream")
        }
    }

    func captureScreenshot() {
        Task {
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

                let stream = SCStream(filter: SCContentFilter(display: mainDisplay, excludingWindows: []), configuration: config, delegate: nil)

                let output = ScreenshotStreamOutput()
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue.main)

                try await stream.startCapture()

                // Stop after short delay (e.g. 1 second) to simulate one-frame capture
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    stream.stopCapture()
                }
            } catch {
                print("Screen capture failed: \(error)")
            }
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
