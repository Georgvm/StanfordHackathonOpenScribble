//
//  ImprovedHandwritingRenderer.swift
//  OpenScribble
//
//  Created on 11/9/25.
//

import UIKit
import PencilKit
import CoreText

class ImprovedHandwritingRenderer {
    
    // Use a nice cursive/handwriting font
    private let handwritingFont = UIFont(name: "Bradley Hand", size: 30) ?? UIFont.systemFont(ofSize: 30)
    
    // MARK: - Animated Rendering
    
    /// Animates text rendering stroke-by-stroke to simulate handwriting
    func renderTextWithAnimation(
        _ text: String,
        at startPoint: CGPoint,
        maxWidth: CGFloat,
        in drawing: PKDrawing,
        onCanvas canvasView: PKCanvasView,
        completion: @escaping () -> Void
    ) {
        print("✍️ Starting animated handwriting: \(text)")
        print("📍 At position: (\(Int(startPoint.x)), \(Int(startPoint.y)))")
        print("📏 Max width: \(Int(maxWidth))")
        
        // Generate all strokes upfront
        let allStrokes = generateStrokesForText(text, at: startPoint, maxWidth: maxWidth)
        
        print("🎨 Generated \(allStrokes.count) strokes, animating them now...")
        
        // Animate strokes being added
        animateStrokes(allStrokes, on: canvasView, baseDrawing: drawing, completion: completion)
    }
    
    /// Generates all strokes for the text without adding them to the drawing
    /// Returns array of stroke groups (each group is one character)
    private func generateStrokesForText(
        _ text: String,
        at startPoint: CGPoint,
        maxWidth: CGFloat
    ) -> [[PKStroke]] {
        var allStrokeGroups: [[PKStroke]] = []
        var currentPoint = startPoint
        let lineHeight: CGFloat = 50
        let words = text.components(separatedBy: " ")
        
        var currentLineWords: [String] = []
        var currentLineWidth: CGFloat = 0
        
        for word in words {
            let wordWidth = estimateWordWidth(word)
            
            if currentLineWidth + wordWidth > maxWidth && !currentLineWords.isEmpty {
                let lineText = currentLineWords.joined(separator: " ")
                let lineStrokeGroups = generateStrokeGroupsForLine(lineText, at: currentPoint)
                allStrokeGroups.append(contentsOf: lineStrokeGroups)
                
                currentPoint.y += lineHeight
                currentLineWords = [word]
                currentLineWidth = wordWidth
            } else {
                currentLineWords.append(word)
                currentLineWidth += wordWidth + 20
            }
        }
        
        if !currentLineWords.isEmpty {
            let lineText = currentLineWords.joined(separator: " ")
            let lineStrokeGroups = generateStrokeGroupsForLine(lineText, at: currentPoint)
            allStrokeGroups.append(contentsOf: lineStrokeGroups)
        }
        
        return allStrokeGroups
    }
    
    /// Generates stroke groups for a single line (each group is one character)
    private func generateStrokeGroupsForLine(_ text: String, at point: CGPoint) -> [[PKStroke]] {
        var lineStrokeGroups: [[PKStroke]] = []
        var currentPoint = point
        
        for character in text {
            if character == " " {
                currentPoint.x += 20
                // Add empty group for space (for timing purposes)
                lineStrokeGroups.append([])
                continue
            }
            
            let charStrokes = createStrokesFromGlyph(
                character: character,
                at: currentPoint,
                font: handwritingFont
            )
            
            // Add character's strokes as a group
            if !charStrokes.isEmpty {
                lineStrokeGroups.append(charStrokes)
            }
            currentPoint.x += getCharacterWidth(character, font: handwritingFont)
        }
        
        return lineStrokeGroups
    }
    
    /// Animates stroke groups being added to the canvas
    /// Each group (character) appears together for more natural handwriting
    private func animateStrokes(
        _ strokeGroups: [[PKStroke]],
        on canvasView: PKCanvasView,
        baseDrawing: PKDrawing,
        completion: @escaping () -> Void
    ) {
        guard !strokeGroups.isEmpty else {
            completion()
            return
        }
        
        var currentDrawing = baseDrawing
        var groupIndex = 0
        
        // Timing: ~40ms per character for natural handwriting speed
        // Faster for spaces, slower for complex characters
        func getDelayForGroup(_ group: [PKStroke]) -> TimeInterval {
            if group.isEmpty {
                return 0.02  // Fast delay for spaces
            } else if group.count > 5 {
                return 0.06  // Slower for complex characters
            } else {
                return 0.04  // Normal speed for simple characters
            }
        }
        
        func addNextCharacter() {
            guard groupIndex < strokeGroups.count else {
                print("✅ Animation complete!")
                completion()
                return
            }
            
            // Add all strokes in the current group (one character)
            let group = strokeGroups[groupIndex]
            for stroke in group {
                currentDrawing.strokes.append(stroke)
            }
            canvasView.drawing = currentDrawing
            
            let delay = getDelayForGroup(group)
            groupIndex += 1
            
            // Schedule next character
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                addNextCharacter()
            }
        }
        
        // Start the animation
        addNextCharacter()
    }
    
    // MARK: - Non-Animated Rendering (Original)
    
    func renderTextWithLineWrapping(
        _ text: String,
        at startPoint: CGPoint,
        maxWidth: CGFloat,
        in drawing: PKDrawing
    ) -> PKDrawing {
        print("✍️ Rendering text as handwriting: \(text)")
        print("📍 At position: (\(Int(startPoint.x)), \(Int(startPoint.y)))")
        print("📏 Max width: \(Int(maxWidth))")
        
        var newDrawing = drawing
        var currentPoint = startPoint
        let lineHeight: CGFloat = 50
        let words = text.components(separatedBy: " ")
        
        var currentLineWords: [String] = []
        var currentLineWidth: CGFloat = 0
        
        for word in words {
            // Estimate word width
            let wordWidth = estimateWordWidth(word)
            
            // Check if adding this word would exceed maxWidth
            if currentLineWidth + wordWidth > maxWidth && !currentLineWords.isEmpty {
                // Render current line
                let lineText = currentLineWords.joined(separator: " ")
                newDrawing = renderLine(lineText, at: currentPoint, in: newDrawing)
                
                // Move to next line
                currentPoint.y += lineHeight
                currentLineWords = [word]
                currentLineWidth = wordWidth
            } else {
                currentLineWords.append(word)
                currentLineWidth += wordWidth + 20 // word + space
            }
        }
        
        // Render remaining words
        if !currentLineWords.isEmpty {
            let lineText = currentLineWords.joined(separator: " ")
            newDrawing = renderLine(lineText, at: currentPoint, in: newDrawing)
        }
        
        print("✅ Text rendered successfully")
        return newDrawing
    }
    
    private func renderLine(_ text: String, at point: CGPoint, in drawing: PKDrawing) -> PKDrawing {
        var newDrawing = drawing
        var currentPoint = point
        
        for character in text {
            if character == " " {
                currentPoint.x += 20
                continue
            }
            
            let charStrokes = createStrokesFromGlyph(
                character: character,
                at: currentPoint,
                font: handwritingFont
            )
            
            newDrawing.strokes.append(contentsOf: charStrokes)
            currentPoint.x += getCharacterWidth(character, font: handwritingFont)
        }
        
        return newDrawing
    }
    
    private func createStrokesFromGlyph(character: Character, at point: CGPoint, font: UIFont) -> [PKStroke] {
        var strokes: [PKStroke] = []
        
        // Get the character as a string
        let charString = String(character)
        
        // Create attributed string
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedString = NSAttributedString(string: charString, attributes: attributes)
        
        // Create a path from the text
        let line = CTLineCreateWithAttributedString(attributedString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        
        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            
            for index in 0..<glyphCount {
                var glyph = CGGlyph()
                CTRunGetGlyphs(run, CFRange(location: index, length: 1), &glyph)
                
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: index, length: 1), &position)
                
                // Get glyph path
                if let glyphPath = CTFontCreatePathForGlyph(font as CTFont, glyph, nil) {
                    // Create transform to flip Y-axis (CoreText has inverted Y compared to PencilKit)
                    var transform = CGAffineTransform(scaleX: 1.0, y: -1.0)
                    
                    // Apply the transform to flip the glyph
                    if let flippedPath = glyphPath.copy(using: &transform) {
                        // Convert path to strokes with corrected offset
                        let convertedStrokes = convertPathToStrokes(
                            flippedPath,
                            offset: CGPoint(x: point.x + position.x, y: point.y + position.y)
                        )
                        strokes.append(contentsOf: convertedStrokes)
                    }
                }
            }
        }
        
        return strokes
    }
    
    private func convertPathToStrokes(_ path: CGPath, offset: CGPoint) -> [PKStroke] {
        var strokes: [PKStroke] = []
        var currentStrokePoints: [CGPoint] = []
        
        // Define the ink (pink color for AI responses)
        let ink = PKInkingTool(.pen, color: .systemPink, width: 2.5).ink
        
        path.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            
            switch element.type {
            case .moveToPoint:
                // Start new stroke if we have points
                if !currentStrokePoints.isEmpty {
                    if let stroke = self.createStrokeFromPoints(currentStrokePoints, ink: ink, offset: offset) {
                        strokes.append(stroke)
                    }
                    currentStrokePoints.removeAll()
                }
                currentStrokePoints.append(element.points[0])
                
            case .addLineToPoint:
                currentStrokePoints.append(element.points[0])
                
            case .addQuadCurveToPoint:
                // Approximate curve with line segments
                let controlPoint = element.points[0]
                let endPoint = element.points[1]
                if let lastPoint = currentStrokePoints.last {
                    // Add intermediate points along the curve
                    for t in stride(from: 0.0, through: 1.0, by: 0.1) {
                        let tCGFloat = CGFloat(t)
                        let oneMinusT = CGFloat(1.0 - t)
                        
                        // Quadratic Bezier formula: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
                        let term1X = oneMinusT * oneMinusT * lastPoint.x
                        let term2X = 2.0 * oneMinusT * tCGFloat * controlPoint.x
                        let term3X = tCGFloat * tCGFloat * endPoint.x
                        let x = term1X + term2X + term3X
                        
                        let term1Y = oneMinusT * oneMinusT * lastPoint.y
                        let term2Y = 2.0 * oneMinusT * tCGFloat * controlPoint.y
                        let term3Y = tCGFloat * tCGFloat * endPoint.y
                        let y = term1Y + term2Y + term3Y
                        
                        currentStrokePoints.append(CGPoint(x: x, y: y))
                    }
                }
                
            case .addCurveToPoint:
                // Approximate cubic curve with line segments
                let cp1 = element.points[0]
                let cp2 = element.points[1]
                let endPoint = element.points[2]
                if let lastPoint = currentStrokePoints.last {
                    for t in stride(from: 0.0, through: 1.0, by: 0.1) {
                        let tCGFloat = CGFloat(t)
                        let oneMinusT = CGFloat(1.0 - t)
                        
                        // Cubic Bezier formula: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
                        let term1X = oneMinusT * oneMinusT * oneMinusT * lastPoint.x
                        let term2X = 3.0 * oneMinusT * oneMinusT * tCGFloat * cp1.x
                        let term3X = 3.0 * oneMinusT * tCGFloat * tCGFloat * cp2.x
                        let term4X = tCGFloat * tCGFloat * tCGFloat * endPoint.x
                        let x = term1X + term2X + term3X + term4X
                        
                        let term1Y = oneMinusT * oneMinusT * oneMinusT * lastPoint.y
                        let term2Y = 3.0 * oneMinusT * oneMinusT * tCGFloat * cp1.y
                        let term3Y = 3.0 * oneMinusT * tCGFloat * tCGFloat * cp2.y
                        let term4Y = tCGFloat * tCGFloat * tCGFloat * endPoint.y
                        let y = term1Y + term2Y + term3Y + term4Y
                        
                        currentStrokePoints.append(CGPoint(x: x, y: y))
                    }
                }
                
            case .closeSubpath:
                if !currentStrokePoints.isEmpty {
                    if let stroke = self.createStrokeFromPoints(currentStrokePoints, ink: ink, offset: offset) {
                        strokes.append(stroke)
                    }
                    currentStrokePoints.removeAll()
                }
                
            @unknown default:
                break
            }
        }
        
        // Add remaining points as a stroke
        if !currentStrokePoints.isEmpty {
            if let stroke = createStrokeFromPoints(currentStrokePoints, ink: ink, offset: offset) {
                strokes.append(stroke)
            }
        }
        
        return strokes
    }
    
    private func createStrokeFromPoints(_ points: [CGPoint], ink: PKInk, offset: CGPoint) -> PKStroke? {
        guard points.count > 1 else { return nil }
        
        // Convert points to PKStrokePoints with offset
        let strokePoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: CGPoint(x: point.x + offset.x, y: point.y + offset.y),
                timeOffset: TimeInterval(index) * 0.01,
                size: CGSize(width: 2.5, height: 2.5),
                opacity: 1.0,
                force: 1.0,
                azimuth: 0,
                altitude: 0
            )
        }
        
        let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date())
        return PKStroke(ink: ink, path: path)
    }
    
    private func estimateWordWidth(_ word: String) -> CGFloat {
        var width: CGFloat = 0
        for char in word {
            width += getCharacterWidth(char, font: handwritingFont)
        }
        return width
    }
    
    private func getCharacterWidth(_ character: Character, font: UIFont) -> CGFloat {
        let charString = String(character)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (charString as NSString).size(withAttributes: attributes)
        return size.width + 2 // Add small spacing
    }
}

