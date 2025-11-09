//
//  ContentView.swift
//  OpenScribble
//
//  Created by Georg v. Manstein on 11/8/25.
//

import SwiftUI
import PencilKit

struct ContentView: View {
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var isProcessing = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showDebugImage = false
    @State private var debugImage: UIImage?
    @State private var lastAPICallStrokeCount = 0  // Track strokes at last API call
    @State private var autoSendEnabled = false  // Auto-send AI requests setting
    @State private var debounceTimer: Timer?  // Timer for auto-send debounce
    @State private var currentTask: Task<Void, Never>?  // Track current AI request task
    @State private var isRenderingAIResponse = false  // Flag to prevent auto-send during AI rendering
    @State private var lastUserStrokeCount = 0  // Track user strokes (not AI strokes)
    
    // OpenAI API Key
    private let apiKey = ""
    
    private let handwritingRenderer = ImprovedHandwritingRenderer()
    private let imageCapture = EnhancedCanvasImageCapture()
    
    var body: some View {
        ZStack {
            // Main Canvas
            CanvasView(canvasView: $canvasView, toolPicker: $toolPicker, onDrawingChanged: {
                handleDrawingChange()
            })
                .ignoresSafeArea()
            
            // Controls Overlay - Top Left Corner
            VStack {
                HStack(spacing: 12) {
                    // Debug Image Button
                    Button(action: captureDebugImage) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    
                    // Clear Canvas Button
                    Button(action: clearCanvas) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    
                    // Send to AI Button
                    Button(action: sendToAI) {
                        Image(systemName: isProcessing ? "hourglass" : "paperplane.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .disabled(isProcessing)
                    
                    // Settings Button with Menu
                    Menu {
                        Button(action: {
                            autoSendEnabled.toggle()
                        }) {
                            Label(
                                "Automatically send AI requests",
                                systemImage: autoSendEnabled ? "checkmark" : ""
                            )
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.gray)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.top, 16)
                
                Spacer()
            }
        }
        .alert("Message", isPresented: $showAlert) {
            Button("Copy") {
                UIPasteboard.general.string = alertMessage
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showDebugImage) {
            DebugImageView(image: debugImage)
        }
    }
    
    private func clearCanvas() {
        canvasView.drawing = PKDrawing()
        // Cancel any pending auto-send timer
        debounceTimer?.invalidate()
        debounceTimer = nil
        // Reset stroke counts
        lastUserStrokeCount = 0
        lastAPICallStrokeCount = 0
    }
    
    // Handle drawing changes for auto-send feature
    private func handleDrawingChange() {
        let currentStrokeCount = canvasView.drawing.strokes.count
        print("✏️ Drawing changed - stroke count: \(currentStrokeCount)")
        
        // Ignore if AI is currently rendering its response
        guard !isRenderingAIResponse else {
            print("   🤖 AI is rendering, ignoring this change")
            return
        }
        
        guard autoSendEnabled else {
            print("   ⏭️ Auto-send disabled, skipping")
            // Still track user strokes even when auto-send is off
            lastUserStrokeCount = currentStrokeCount
            return
        }
        
        guard !canvasView.drawing.strokes.isEmpty else {
            print("   ⏭️ Canvas empty, skipping")
            return
        }
        
        // Check if user actually added new strokes (not just AI rendering)
        guard currentStrokeCount > lastUserStrokeCount else {
            print("   ⏭️ No new user strokes detected, skipping")
            return
        }
        
        print("   ⏱️ New user strokes detected! Starting 1-second auto-send timer...")
        lastUserStrokeCount = currentStrokeCount
        
        // Cancel existing timer
        debounceTimer?.invalidate()
        
        // Cancel any ongoing AI request
        if isProcessing {
            print("   ⏸️ Cancelling ongoing AI request due to new strokes")
            currentTask?.cancel()
            isProcessing = false
        }
        
        // Start new 1-second timer
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [self] _ in
            print("⏰ Auto-send timer triggered - sending to AI...")
            sendToAI()
        }
    }
    
    private func captureDebugImage() {
        guard !canvasView.drawing.strokes.isEmpty else {
            alertMessage = "Canvas is empty! Write something first."
            showAlert = true
            return
        }
        
        print("🖼️ Capturing debug image...")
        
        // Calculate strokes since last API call
        let currentStrokeCount = canvasView.drawing.strokes.count
        let newStrokeCount = currentStrokeCount - lastAPICallStrokeCount
        
        if let captured = imageCapture.captureWithDetailedAnnotations(
            canvasView: canvasView,
            recentStrokeCount: max(1, newStrokeCount)
        ) {
            debugImage = captured.image
            showDebugImage = true
            print("✅ Debug image captured - showing preview")
        } else {
            alertMessage = "Failed to capture debug image"
            showAlert = true
        }
    }
    
    private func sendToAI() {
        guard !canvasView.drawing.strokes.isEmpty else {
            alertMessage = "Please write something first!"
            showAlert = true
            return
        }
        
        // Cancel any existing task
        currentTask?.cancel()
        
        // Cancel any pending auto-send timer since we're sending now
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        isProcessing = true
        
        print("🎨 Starting AI processing pipeline...")
        
        // Calculate how many strokes were added since last API call
        let currentStrokeCount = canvasView.drawing.strokes.count
        let newStrokeCount = currentStrokeCount - lastAPICallStrokeCount
        
        print("   📊 Total strokes: \(currentStrokeCount), New since last call: \(newStrokeCount)")
        
        // Step 1: Capture canvas with enhanced annotations
        // Highlight ALL strokes added since last API call
        guard let captured = imageCapture.captureWithDetailedAnnotations(
            canvasView: canvasView,
            recentStrokeCount: max(1, newStrokeCount)  // All new strokes since last call
        ) else {
            isProcessing = false
            alertMessage = "Failed to capture canvas. Please try again."
            showAlert = true
            return
        }
        
        let canvasImage = captured.image
        let metadata = captured.metadata
        
        // Save for debug viewing
        debugImage = canvasImage
        
        print("✅ Canvas captured successfully")
        
        // Step 2: Send to GPT-4o-mini Vision (handles OCR + response + placement)
        // Wrap in a Task for cancellation support
        currentTask = Task {
            let visionService = VisionBasedLayoutService(apiKey: apiKey)
            
            let result: Result<EnhancedAIResponse, Error> = await withCheckedContinuation { continuation in
                visionService.analyzeCanvasAndRespond(canvasImage: canvasImage, metadata: metadata) { result in
                    continuation.resume(returning: result)
                }
            }
            
            // Check if task was cancelled
            guard !Task.isCancelled else {
                print("⏸️ AI request was cancelled")
                DispatchQueue.main.async {
                    isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("🎉 AI Response received successfully!")
                    print("   📝 User wrote: '\(response.userText)'")
                    print("   💬 AI says: '\(response.aiResponse)'")
                    print("   📍 Placement: (\(Int(response.placement.x)), \(Int(response.placement.y)))")
                    print("   📏 Canvas size: \(Int(canvasView.bounds.width)) × \(Int(canvasView.bounds.height))")
                    print("   🎯 Reasoning: \(response.reasoning)")
                    
                    // Set flag to prevent auto-send during AI rendering
                    isRenderingAIResponse = true
                    
                    // Step 3: Render AI response as handwriting with animation at optimal position
                    handwritingRenderer.renderTextWithAnimation(
                        response.aiResponse,
                        at: response.placement.origin,
                        maxWidth: response.placement.width,
                        in: canvasView.drawing,
                        onCanvas: canvasView
                    ) {
                        // Animation complete callback
                        DispatchQueue.main.async {
                            // Update the stroke count AFTER AI responds
                            lastAPICallStrokeCount = canvasView.drawing.strokes.count
                            lastUserStrokeCount = canvasView.drawing.strokes.count  // Update user stroke count too
                            isRenderingAIResponse = false  // Clear flag after rendering is complete
                            print("✨ AI handwriting animated on canvas!")
                            print("   📊 Updated stroke count baseline: \(lastAPICallStrokeCount)")
                            print("   👤 Updated user stroke count: \(lastUserStrokeCount)")
                        }
                    }
                    
                case .failure(let error):
                    print("❌ Error: \(error.localizedDescription)")
                    alertMessage = "Error: \(error.localizedDescription)\n\nPlease make sure your API key is valid and you have internet connection."
                    showAlert = true
                }
                isProcessing = false
            }
        }
    }
}



// MARK: - Debug Image View

struct DebugImageView: View {
    @Environment(\.dismiss) var dismiss
    let image: UIImage?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Text("No image available")
                        .foregroundColor(.white)
                }
            }
            .navigationTitle("API Image Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if image != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: shareImage) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
    
    private func shareImage() {
        guard let image = image else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            
            // For iPad, set the popover presentation controller
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    ContentView()
}
