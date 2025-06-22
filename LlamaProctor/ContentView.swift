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
    @State private var teacherTaskDescription: String = ""
    @State private var latestAnalysis: [String: Any]? = nil
    @State private var isAnalyzing: Bool = false
    @StateObject private var streamManager = StreamManager()
    @StateObject private var mongoDBService = MongoDBService()

    var body: some View {
        VStack(alignment: .leading) {
            Text("LlamaProctor Running")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading) {
                Text("Teacher's Task Description:")
                    .font(.subheadline)
                TextField("Enter what the student should be working on...", text: $teacherTaskDescription, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...6)
            }
            
            Divider()
            
            Text("Active Window:")
                .font(.subheadline)
            List(windowsInfo, id: \.self) { window in
                Text(window)
            }
            
            Divider()
            
            if let analysis = latestAnalysis {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Student Activity Analysis:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Score:")
                            .fontWeight(.medium)
                        Text("\(analysis["score"] as? Int ?? 0)/5")
                            .foregroundColor(.blue)
                    }
                    
                    Text("Description:")
                        .fontWeight(.medium)
                    Text(analysis["description"] as? String ?? "No description available")
                        .foregroundColor(.secondary)
                    
                    Text("Suggestion:")
                        .fontWeight(.medium)
                    Text(analysis["suggestion"] as? String ?? "No suggestion available")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
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
            // Set app as active when it appears
            mongoDBService.setAppActiveStatus(active: true) { success, error in
                if let error = error {
                    print("Failed to set app as active: \(error)")
                } else {
                    print("App marked as active in MongoDB")
                }
            }
        }
        .onDisappear {
            screenshotTimerCancellable?.cancel()
            windowTimerCancellable?.cancel()
            // Set app as inactive when it disappears
            mongoDBService.setAppActiveStatus(active: false) { success, error in
                if let error = error {
                    print("Failed to set app as inactive: \(error)")
                } else {
                    print("App marked as inactive in MongoDB")
                }
            }
        }
    }

    func startBackgroundTasks() {
        // Give the stream manager a moment to set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Screenshot timer - every 8 seconds
            screenshotTimerCancellable = Timer.publish(every: 8, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    streamManager.captureScreenshot { image in
                        DispatchQueue.main.async {
                            // Only update if we got a new image
                            if let image = image {
                                latestScreenshot = image
                                // Analyze with Llama API if we have a task description and not already analyzing
                                if !teacherTaskDescription.isEmpty && !isAnalyzing {
                                    isAnalyzing = true
                                    analyzeStudentActivity(image: image, windows: windowsInfo, taskDescription: teacherTaskDescription)
                                }
                            }
                        }
                    }
                }
            
            // Window info timer - every 1 second
            windowTimerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    let windowTitles = getOpenWindowTitles()
                    windowsInfo = windowTitles
                }
        }
    }
    
    func analyzeStudentActivity(image: NSImage, windows: [String], taskDescription: String) {
        guard let imageData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: imageData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("Failed to convert image to PNG")
            return
        }
        
        // Convert image to base64
        let base64Image = pngData.base64EncodedString()
        
        // Prepare the request
        let requestBody: [String: Any] = [
            "model": "Llama-4-Scout-17B-16E-Instruct-FP8",
            "messages": [
                [
                    "role": "system",
                    "content": "You are an AI assistant helping teachers monitor student activity during class. Analyze the student's screen activity and compare it to the teacher's intended task. Consider all on-screen elements while putting the most weight on the active window. Provide a score out of 5 for how on-task the student is, a one-sentence brief description of what the student appears to be doing, and a short suggestion for the teacher. For the suggestion: if student is on-task, indicate 'on-task'. If not obviously on-task, indicate 'Sussy'. If truly off-task, indicate 'Needs reminder'."
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "Teacher's Task: \(taskDescription)\n\nActive Windows: \(windows.joined(separator: ", "))\n\nPlease analyze this student's activity and provide insights."
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "StudentActivityAnalysis",
                    "schema": [
                        "properties": [
                            "score": [
                                "type": "integer",
                                "description": "Score from 0 to 5 for how on-task the student's activity is to the teacher's task"
                            ],
                            "description": [
                                "type": "string",
                                "description": "A short 1 sentence summary of what the student seems to be doing. Mention all important on-screen elements."
                            ],
                            "suggestion": [
                                "type": "string",
                                "description": "A very short suggestion for the teacher. If student is on-task, indicate 'on-task'. If not obviously on-task, indicate 'Sussy'. If truly off-task, indicate 'Needs reminder'."
                            ]
                        ],
                        "required": ["score", "description", "suggestion"],
                        "type": "object"
                    ]
                ]
            ]
        ]
        
        // Make the API call
        var request = URLRequest(url: URL(string: "https://api.llama.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer LLM|4223328317906442|61bxxIJdYOjFW-jmlw5ea70FkBY", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Log the API request
            print("=== API REQUEST ===")
            print("Task: \(taskDescription)")
            print("Active Windows: \(windows.joined(separator: ", "))")
            print("Image Size: \(image.size.width) x \(image.size.height)")
            print("==================")
            
        } catch {
            print("Failed to serialize request: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("API call error: \(error)")
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                }
                return
            }
            
            guard let data = data else {
                print("No data received")
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Try the new completion_message format first
                    if let completionMessage = json["completion_message"] as? [String: Any],
                       let content = completionMessage["content"] as? [String: Any],
                       let text = content["text"] as? String {
                        
                        // Parse the structured JSON response from the text field
                        if let contentData = text.data(using: .utf8),
                           let analysisData = try JSONSerialization.jsonObject(with: contentData) as? [String: Any] {
                            
                            DispatchQueue.main.async {
                                self.latestAnalysis = analysisData
                                self.isAnalyzing = false
                            }
                            
                            // Store in MongoDB
                            self.storeAnalysisInMongoDB(analysisData, image: image, windows: windows, taskDescription: taskDescription)
                            
                            // Log the API response
                            print("=== API RESPONSE ===")
                            print("Score: \(analysisData["score"] ?? "N/A")/5")
                            print("Description: \(analysisData["description"] ?? "N/A")")
                            print("Suggestion: \(analysisData["suggestion"] ?? "N/A")")
                            print("===================")
                            
                        } else {
                            print("Failed to parse JSON from completion_message text")
                            DispatchQueue.main.async {
                                self.isAnalyzing = false
                            }
                        }
                    }
                    // Fallback to standard choices format
                    else if let choices = json["choices"] as? [[String: Any]],
                              let firstChoice = choices.first,
                              let message = firstChoice["message"] as? [String: Any],
                              let content = message["content"] as? String {
                        
                        // Parse the structured JSON response
                        if let contentData = content.data(using: .utf8),
                           let analysisData = try JSONSerialization.jsonObject(with: contentData) as? [String: Any] {
                            
                            DispatchQueue.main.async {
                                self.latestAnalysis = analysisData
                                self.isAnalyzing = false
                            }
                            
                            // Store in MongoDB
                            self.storeAnalysisInMongoDB(analysisData, image: image, windows: windows, taskDescription: taskDescription)
                            
                            // Log the API response
                            print("=== API RESPONSE ===")
                            print("Score: \(analysisData["score"] ?? "N/A")/5")
                            print("Description: \(analysisData["description"] ?? "N/A")")
                            print("Suggestion: \(analysisData["suggestion"] ?? "N/A")")
                            print("===================")
                            
                        } else {
                            DispatchQueue.main.async {
                                self.isAnalyzing = false
                            }
                        }
                    } else {
                        print("Failed to parse expected response structure")
                        DispatchQueue.main.async {
                            self.isAnalyzing = false
                        }
                    }
                }
            } catch {
                print("Failed to parse response: \(error)")
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                }
            }
        }.resume()
    }
    
    func storeAnalysisInMongoDB(_ analysis: [String: Any], image: NSImage, windows: [String], taskDescription: String) {
        guard let score = analysis["score"] as? Int,
              let description = analysis["description"] as? String,
              let suggestion = analysis["suggestion"] as? String else {
            print("Invalid analysis data for MongoDB storage")
            return
        }
        
        // Update the focus score in MongoDB based on Llama's score
        mongoDBService.updateFocusScore(
            id: "1",
            llamaScore: score,
            description: description,
            suggestion: suggestion
        ) { success, error in
            if let error = error {
                print("Failed to update MongoDB: \(error)")
            } else {
                print("Successfully updated MongoDB with new analysis")
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
