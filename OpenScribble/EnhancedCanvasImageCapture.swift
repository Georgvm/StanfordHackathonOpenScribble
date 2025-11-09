//
//  EnhancedCanvasImageCapture.swift
//  OpenScribble
//
//  Created on 11/9/25.
//

import UIKit
import PencilKit

class EnhancedCanvasImageCapture {
    
    /// Captures canvas with comprehensive annotations for GPT-4 Vision
    func captureWithDetailedAnnotations(
        canvasView: PKCanvasView,
        recentStrokeCount: Int = 10
    ) -> (image: UIImage, metadata: CanvasMetadata)? {
        
        print("📸 Capturing canvas with detailed annotations...")
        
        let drawing = canvasView.drawing
        
        // Calculate the bounding box that contains ALL strokes (not just visible viewport)
        let bounds = calculateDrawingBounds(drawing: drawing, viewBounds: canvasView.bounds)
        
        print("   📏 Capture bounds: \(Int(bounds.width)) × \(Int(bounds.height)) at (\(Int(bounds.minX)), \(Int(bounds.minY)))")
        
        // Calculate metadata about the canvas
        let metadata = calculateCanvasMetadata(drawing: drawing, bounds: bounds, recentStrokes: recentStrokeCount)
        
        // Create annotated image
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        
        let image = renderer.image { context in
            // Translate coordinate system so that bounds.origin appears at (0,0)
            let offset = CGPoint(x: -bounds.minX, y: -bounds.minY)
            context.cgContext.translateBy(x: offset.x, y: offset.y)
            
            // Layer 1: White background
            UIColor.white.setFill()
            context.fill(bounds)
            
            // Layer 2: Draw old strokes (not highlighted)
            drawOldStrokes(drawing: drawing, recentCount: recentStrokeCount, in: context, bounds: bounds)
            
            // Layer 3: Highlight recent strokes with yellow background
            highlightRecentStrokes(drawing: drawing, recentCount: recentStrokeCount, in: context)
            
            // Layer 4: Draw recent strokes on top
            drawRecentStrokes(drawing: drawing, recentCount: recentStrokeCount, in: context, bounds: bounds)
            
            // Layer 5: Draw bounding boxes around content
            drawBoundingBoxes(metadata: metadata, in: context.cgContext)
            
            // Layer 6: Draw occupancy heatmap overlay
            drawOccupancyHeatmap(metadata: metadata, in: context.cgContext)
            
            // Layer 7: Draw coordinate grid with labels
            drawAnnotatedGrid(in: context.cgContext, bounds: bounds)
            
            // Layer 8: Draw canvas dimensions
            drawDimensionLabels(in: context.cgContext, bounds: bounds)
            
            // Layer 9: Mark empty regions with green tint
            markEmptyRegions(metadata: metadata, in: context.cgContext)
        }
        
        print("✅ Canvas captured with comprehensive annotations")
        print("   \(metadata.description)")
        return (image, metadata)
    }
    
    /// Calculate the bounding box that encompasses ALL strokes in the drawing
    private func calculateDrawingBounds(drawing: PKDrawing, viewBounds: CGRect) -> CGRect {
        guard !drawing.strokes.isEmpty else {
            // No strokes yet, return a default size
            return CGRect(x: 0, y: 0, width: 1000, height: 1000)
        }
        
        // Find the union of all stroke bounds
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude
        
        for stroke in drawing.strokes {
            let bounds = stroke.renderBounds
            minX = min(minX, bounds.minX)
            maxX = max(maxX, bounds.maxX)
            minY = min(minY, bounds.minY)
            maxY = max(maxY, bounds.maxY)
        }
        
        // Add padding around the content (100pt on each side)
        let padding: CGFloat = 100
        minX -= padding
        minY -= padding
        maxX += padding
        maxY += padding
        
        // Ensure we don't have negative origin
        minX = max(0, minX)
        minY = max(0, minY)
        
        let width = maxX - minX
        let height = maxY - minY
        
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
    
    private func calculateCanvasMetadata(drawing: PKDrawing, bounds: CGRect, recentStrokes: Int) -> CanvasMetadata {
        var occupiedRegions: [CGRect] = []
        var recentRegion: CGRect?
        var actualRecentRegion: CGRect?  // For placement - tighter bounds
        
        let totalStrokes = drawing.strokes.count
        let oldCount = max(0, totalStrokes - recentStrokes)
        
        // Get the most recent strokes for calculating actual position
        let recentStrokesList = Array(drawing.strokes.suffix(recentStrokes))
        
        // Calculate bounding boxes for all strokes
        for (index, stroke) in drawing.strokes.enumerated() {
            let strokeBounds = stroke.renderBounds
            occupiedRegions.append(strokeBounds)
            
            // Track recent region (merged for highlighting)
            if index >= oldCount {
                if let existing = recentRegion {
                    recentRegion = existing.union(strokeBounds)
                } else {
                    recentRegion = strokeBounds
                }
            }
        }
        
        // Calculate the ACTUAL recent writing position (for placement)
        // Anchor to the LEFT edge (start) of the writing, not the center
        if !recentStrokesList.isEmpty {
            var minX: CGFloat = .greatestFiniteMagnitude
            var maxX: CGFloat = -.greatestFiniteMagnitude
            var minY: CGFloat = .greatestFiniteMagnitude
            var maxY: CGFloat = -.greatestFiniteMagnitude
            
            for stroke in recentStrokesList {
                let bounds = stroke.renderBounds
                minX = min(minX, bounds.minX)
                maxX = max(maxX, bounds.maxX)
                minY = min(minY, bounds.minY)
                maxY = max(maxY, bounds.maxY)
            }
            
            // Use the full width of the recent writing
            let width = maxX - minX
            let height = maxY - minY
            
            // Anchor to the LEFT edge (start) of the writing
            // This makes "2x=4x+11" anchor to the "2", not the "1" at the end
            actualRecentRegion = CGRect(
                x: minX,
                y: minY,
                width: width,
                height: height
            )
        }
        
        // Calculate empty regions using grid analysis
        let emptyRegions = calculateEmptyRegions(
            occupiedRegions: occupiedRegions,
            canvasBounds: bounds
        )
        
        return CanvasMetadata(
            canvasSize: bounds.size,
            occupiedRegions: occupiedRegions,
            recentWritingRegion: actualRecentRegion ?? recentRegion,  // Use compact box for placement
            emptyRegions: emptyRegions,
            gridSize: 50
        )
    }
    
    private func calculateEmptyRegions(occupiedRegions: [CGRect], canvasBounds: CGRect) -> [CGRect] {
        let gridSize: CGFloat = 100
        var grid: [[Bool]] = []
        
        let rows = Int(ceil(canvasBounds.height / gridSize))
        let cols = Int(ceil(canvasBounds.width / gridSize))
        
        // Initialize grid with all cells as empty (false = empty)
        for _ in 0..<rows {
            grid.append(Array(repeating: false, count: cols))
        }
        
        // Mark occupied cells (adjust for bounds offset)
        for y in 0..<rows {
            for x in 0..<cols {
                let testRect = CGRect(
                    x: canvasBounds.minX + CGFloat(x) * gridSize,
                    y: canvasBounds.minY + CGFloat(y) * gridSize,
                    width: gridSize,
                    height: gridSize
                )
                
                for occupied in occupiedRegions {
                    if testRect.intersects(occupied.insetBy(dx: -20, dy: -20)) {
                        grid[y][x] = true // Mark as occupied
                        break
                    }
                }
            }
        }
        
        // Find contiguous empty regions and merge them
        var emptyRegions: [CGRect] = []
        var visited: [[Bool]] = Array(repeating: Array(repeating: false, count: cols), count: rows)
        
        for startY in 0..<rows {
            for startX in 0..<cols {
                if !grid[startY][startX] && !visited[startY][startX] {
                    // Found an empty unvisited cell - expand it
                    var maxWidth = 0
                    var maxHeight = 0
                    
                    // Find maximum width at this starting position
                    var width = 0
                    while startX + width < cols && !grid[startY][startX + width] {
                        width += 1
                    }
                    
                    // Find maximum height for this width
                    var height = 0
                    var canExpand = true
                    while startY + height < rows && canExpand {
                        for x in startX..<(startX + width) {
                            if grid[startY + height][x] {
                                canExpand = false
                                break
                            }
                        }
                        if canExpand {
                            height += 1
                        }
                    }
                    
                    maxWidth = width
                    maxHeight = height
                    
                    // Mark these cells as visited
                    for y in startY..<(startY + maxHeight) {
                        for x in startX..<(startX + maxWidth) {
                            visited[y][x] = true
                        }
                    }
                    
                    // Create the empty region (adjust for bounds offset)
                    let region = CGRect(
                        x: canvasBounds.minX + CGFloat(startX) * gridSize,
                        y: canvasBounds.minY + CGFloat(startY) * gridSize,
                        width: CGFloat(maxWidth) * gridSize,
                        height: CGFloat(maxHeight) * gridSize
                    )
                    
                    // Only add regions that are reasonably sized
                    if region.width >= gridSize && region.height >= gridSize {
                        emptyRegions.append(region)
                    }
                }
            }
        }
        
        return emptyRegions
    }
    
    private func drawOldStrokes(drawing: PKDrawing, recentCount: Int, in context: UIGraphicsImageRendererContext, bounds: CGRect) {
        let totalStrokes = drawing.strokes.count
        let oldCount = max(0, totalStrokes - recentCount)
        
        if oldCount > 0 {
            var oldDrawing = PKDrawing()
            oldDrawing.strokes = Array(drawing.strokes.prefix(oldCount))
            oldDrawing.image(from: bounds, scale: 1.0).draw(in: bounds)
        }
    }
    
    private func highlightRecentStrokes(drawing: PKDrawing, recentCount: Int, in context: UIGraphicsImageRendererContext) {
        let recentStrokes = drawing.strokes.suffix(recentCount)
        
        // Calculate merged bounding box for all recent strokes
        guard let firstStroke = recentStrokes.first else { return }
        var mergedBounds = firstStroke.renderBounds
        
        for stroke in recentStrokes.dropFirst() {
            mergedBounds = mergedBounds.union(stroke.renderBounds)
        }
        
        // Add padding
        mergedBounds = mergedBounds.insetBy(dx: -15, dy: -15)
        
        // Draw ONE subtle highlight for all recent strokes
        context.cgContext.setFillColor(UIColor.yellow.withAlphaComponent(0.25).cgColor)
        context.cgContext.fill(mergedBounds)
    }
    
    private func drawRecentStrokes(drawing: PKDrawing, recentCount: Int, in context: UIGraphicsImageRendererContext, bounds: CGRect) {
        let recentStrokes = drawing.strokes.suffix(recentCount)
        var recentDrawing = PKDrawing()
        recentDrawing.strokes = Array(recentStrokes)
        recentDrawing.image(from: bounds, scale: 1.0).draw(in: bounds)
    }
    
    private func drawBoundingBoxes(metadata: CanvasMetadata, in context: CGContext) {
        // Draw a clean border around the merged recent writing region
        if let recent = metadata.recentWritingRegion {
            let boxRect = recent.insetBy(dx: -12, dy: -12)
            
            // Draw border
            context.setStrokeColor(UIColor.orange.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(3)
            context.stroke(boxRect)
            
            // Add subtle label
            let label = "LATEST INPUT"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.orange,
                .backgroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            (label as NSString).draw(
                at: CGPoint(x: recent.minX - 10, y: recent.minY - 22),
                withAttributes: attributes
            )
        }
    }
    
    private func drawOccupancyHeatmap(metadata: CanvasMetadata, in context: CGContext) {
        // Draw VERY LIGHT red overlay on occupied areas (don't obscure text!)
        context.setFillColor(UIColor.red.withAlphaComponent(0.03).cgColor)
        for region in metadata.occupiedRegions {
            context.fill(region.insetBy(dx: -30, dy: -30))
        }
    }
    
    private func drawAnnotatedGrid(in context: CGContext, bounds: CGRect) {
        let gridSize: CGFloat = 100
        
        context.setStrokeColor(UIColor.blue.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(0.5)
        
        // Vertical lines with labels
        for x in stride(from: 0, through: bounds.width, by: gridSize) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))
            
            // Add coordinate label
            let label = "\(Int(x))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.blue.withAlphaComponent(0.4)
            ]
            (label as NSString).draw(at: CGPoint(x: x + 2, y: 2), withAttributes: attributes)
        }
        
        // Horizontal lines with labels
        for y in stride(from: 0, through: bounds.height, by: gridSize) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
            
            // Add coordinate label
            let label = "\(Int(y))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.blue.withAlphaComponent(0.4)
            ]
            (label as NSString).draw(at: CGPoint(x: 2, y: y + 2), withAttributes: attributes)
        }
        
        context.strokePath()
    }
    
    private func drawDimensionLabels(in context: CGContext, bounds: CGRect) {
        let label = "Canvas: \(Int(bounds.width))×\(Int(bounds.height))pt"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.black,
            .backgroundColor: UIColor.white.withAlphaComponent(0.8)
        ]
        (label as NSString).draw(
            at: CGPoint(x: bounds.width - 180, y: 5),
            withAttributes: attributes
        )
    }
    
    private func markEmptyRegions(metadata: CanvasMetadata, in context: CGContext) {
        // Mark empty regions with VERY subtle green tint (barely visible)
        context.setFillColor(UIColor.green.withAlphaComponent(0.05).cgColor)
        for region in metadata.emptyRegions {
            context.fill(region)
        }
    }
}

// MARK: - Metadata Structure

struct CanvasMetadata {
    let canvasSize: CGSize
    let occupiedRegions: [CGRect]
    let recentWritingRegion: CGRect?
    let emptyRegions: [CGRect]
    let gridSize: CGFloat
    
    var description: String {
        """
        Canvas: \(Int(canvasSize.width))×\(Int(canvasSize.height)), \
        Occupied: \(occupiedRegions.count), \
        Empty spaces: \(emptyRegions.count)
        """
    }
    
    func largestEmptyRegions(count: Int) -> [CGRect] {
        return emptyRegions
            .sorted { $0.width * $0.height > $1.width * $1.height }
            .prefix(count)
            .map { $0 }
    }
}

