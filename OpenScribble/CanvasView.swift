//
//  CanvasView.swift
//  OpenScribble
//
//  Created on 11/9/25.
//

import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var toolPicker: PKToolPicker
    var onDrawingChanged: (() -> Void)?
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .white
        canvasView.drawingPolicy = .anyInput // Allow both pencil and finger
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 2)
        canvasView.isOpaque = true
        
        // Enable unlimited canvas with zoom and pan
        canvasView.minimumZoomScale = 0.25  // Can zoom out to 25%
        canvasView.maximumZoomScale = 4.0   // Can zoom in to 400%
        canvasView.zoomScale = 1.0
        
        // Set a very large content size for unlimited drawing
        canvasView.contentSize = CGSize(width: 10000, height: 10000)
        
        // Set up delegate for drawing changes
        canvasView.delegate = context.coordinator
        
        // Show tool picker
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Updates handled by bindings
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        
        init(_ parent: CanvasView) {
            self.parent = parent
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onDrawingChanged?()
        }
    }
}

