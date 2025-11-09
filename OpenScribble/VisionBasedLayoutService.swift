//
//  VisionBasedLayoutService.swift
//  OpenScribble
//
//  Created on 11/9/25.
//

import UIKit

class VisionBasedLayoutService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    /// Analyzes canvas and returns complete response with placement
    func analyzeCanvasAndRespond(
        canvasImage: UIImage,
        metadata: CanvasMetadata,
        completion: @escaping (Result<EnhancedAIResponse, Error>) -> Void
    ) {
        print("🚀 Starting GPT-4o-mini Vision analysis...")
        
        // Convert image to base64
        guard let imageData = canvasImage.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert image to data")
            completion(.failure(NSError(domain: "Image conversion failed", code: -1)))
            return
        }
        
        let base64Image = imageData.base64EncodedString()
        print("📸 Image prepared, size: \(imageData.count / 1024)KB")
        
        // Build the enhanced prompt
        let prompt = buildEnhancedPrompt(metadata: metadata)
        
        // Construct API request
        guard let url = URL(string: baseURL) else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",  // Fast vision model (gpt-5-nano doesn't work well for this)
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                                "detail": "high"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 600,  // Increased for tutoring responses with math notation
            "temperature": 0.8  // Slightly higher for more creative tutoring
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("❌ Failed to serialize JSON: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        print("📤 Sending request to GPT-4o-mini Vision API...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ API call failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                print("❌ No data received")
                completion(.failure(NSError(domain: "No data", code: -1)))
                return
            }
            
            // Debug: Print raw response
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("📥 Raw API response length: \(rawResponse.count) chars")
                print("📥 Full response:\n\(rawResponse)")
            }
            
            do {
                // Parse OpenAI response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Parsed JSON successfully")
                    print("   Keys in response: \(json.keys.joined(separator: ", "))")
                    
                    // Check for error first
                    if let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        print("❌ API Error: \(message)")
                        completion(.failure(NSError(domain: message, code: -1)))
                        return
                    }
                    
                    // Try to parse choices
                    if let choices = json["choices"] as? [[String: Any]] {
                        print("   Found \(choices.count) choices")
                        if let firstChoice = choices.first {
                            print("   Choice keys: \(firstChoice.keys.joined(separator: ", "))")
                            
                            if let message = firstChoice["message"] as? [String: Any] {
                                print("   Message keys: \(message.keys.joined(separator: ", "))")
                                
                                if let content = message["content"] as? String {
                                    print("✅ Received content from API")
                                    
                                    // Parse the JSON content from GPT
                                    let result = self.parseAIResponse(content, metadata: metadata)
                                    completion(result)
                                    return
                                } else {
                                    print("❌ No 'content' string in message")
                                }
                            } else {
                                print("❌ No 'message' dict in choice")
                            }
                        } else {
                            print("❌ No first choice found")
                        }
                    } else {
                        print("❌ No 'choices' array in response")
                    }
                    
                    print("❌ Failed to parse API response structure")
                    completion(.failure(NSError(domain: "Parse error", code: -1)))
                } else {
                    print("❌ Could not parse data as JSON dictionary")
                    completion(.failure(NSError(domain: "Invalid JSON", code: -1)))
                }
            } catch {
                print("❌ JSON parsing failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func buildEnhancedPrompt(metadata: CanvasMetadata) -> String {
        // Get top 5 largest empty spaces
        let topSpaces = metadata.largestEmptyRegions(count: 5)
        
        var spaceDescriptions = ""
        for (index, space) in topSpaces.enumerated() {
            spaceDescriptions += """
            \nOption \(index + 1): x=\(Int(space.minX)), y=\(Int(space.minY)), size=\(Int(space.width))×\(Int(space.height))pt
            """
        }
        
        return """
        You are a study tutor analyzing a handwriting canvas where you help students learn through guidance.
        
        📚 UNDERSTAND THE FULL CONTEXT:
        - ⚫️ Black handwritten text = Student's previous writing
        - 💗 Pink handwritten text = Your previous tutoring responses
        - 🟡 YELLOW HIGHLIGHT + ORANGE BOX "LATEST INPUT" = What student JUST wrote (what you respond to)
        
        🧠 READ EVERYTHING for context:
        - Understand spatial relationships (things written next to each other are related)
        - Track the full problem and all steps taken so far
        - Remember what was said before and what guidance you already gave
        - Mathematical notation matters: "| - 4x" next to an equation means "subtract 4x from both sides"
        
        🎓 YOUR TUTORING APPROACH:
        **GUIDE, DON'T SOLVE!** Help them learn by:
        - Asking guiding questions: "what if you...?", "try...", "what happens if...?"
        - Giving hints about next steps without doing the work
        - Confirming correct work: "good!", "correct, now...?"
        - Pointing out errors gently: "check that step" or "hmm, x should be..."
        - For math: use numbers and symbols (=, ≠, >, <, +, -, ×, ÷, √, ², ³, fractions)
        
        🎯 YOUR TASK:
        1. READ the entire canvas to understand context and progress
        2. FIND the yellow-highlighted text in the orange "LATEST INPUT" box
        3. EVALUATE: Is it correct? What's the next step? What do they need to learn?
        4. RESPOND briefly (3-12 words, casual, use math notation) to GUIDE them forward
        
        TUTORING EXAMPLES:
        - Problem "2x+5=13", Latest input "| -5" → You write: "good! now divide by 2"
        - Problem "x²-4=0", Latest input "how do i solve" → You write: "factor it! (x+?)(x-?)"
        - Latest input "3²" → You write: "what's 3×3?"
        - Latest input "is this 4x-2x?" → You write: "yes, simplify it"
        - Latest input "what is 5+3" → You write: "count it out! 5...6...7...?"
        - Latest input "derivative of x²" → You write: "power rule: bring down exp"
        - Latest input "stuck on integral" → You write: "reverse of derivative! what's d/dx of...?"
        
        NON-MATH EXAMPLES:
        - Latest input "mitochondria?" → You write: "powerhouse of the cell!"
        - Latest input "when was ww2" → You write: "1939-1945, what caused it?"
        - Latest input "explain photosynthesis" → You write: "plants: light + CO₂ + H₂O → sugar + O₂"
        
        CANVAS INFO:
        - Total size: \(Int(metadata.canvasSize.width)) × \(Int(metadata.canvasSize.height)) points
        - Occupied regions: \(metadata.occupiedRegions.count)
        
        RESPOND WITH THIS EXACT JSON FORMAT:
        {
          "userText": "what you read from the yellow highlight",
          "aiResponse": "your brief tutoring guidance"
        }
        
        CRITICAL: 
        - Respond ONLY with valid JSON, no markdown
        - Keep responses SHORT (3-12 words)
        - Casual tone (lowercase ok)
        - GUIDE don't solve! Make them think!
        - Use math notation: ×÷±≠≤≥²³√∫∑∞°
        - Understand full context from entire canvas!
        """
    }
    
    private func parseAIResponse(_ content: String, metadata: CanvasMetadata) -> Result<EnhancedAIResponse, Error> {
        // Clean up the content (remove markdown code blocks if present)
        var cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanContent.hasPrefix("```json") {
            cleanContent = cleanContent.replacingOccurrences(of: "```json", with: "")
            cleanContent = cleanContent.replacingOccurrences(of: "```", with: "")
            cleanContent = cleanContent.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleanContent.hasPrefix("```") {
            cleanContent = cleanContent.replacingOccurrences(of: "```", with: "")
            cleanContent = cleanContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let jsonData = cleanContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("❌ Failed to parse AI response as JSON")
            print("Raw content: \(cleanContent)")
            return .failure(NSError(domain: "Invalid JSON structure", code: -1))
        }
        
        guard let userText = json["userText"] as? String,
              let aiResponse = json["aiResponse"] as? String else {
            print("❌ Missing required fields in JSON")
            return .failure(NSError(domain: "Missing required fields", code: -1))
        }
        
        // We handle placement automatically now - no need for GPT-4 to figure it out!
        let autoPlacement = validatePlacement(
            ResponsePlacement(x: 0, y: 0, width: 500, height: 80),  // Dummy, will be recalculated
            metadata: metadata
        )
        
        let response = EnhancedAIResponse(
            userText: userText,
            aiResponse: aiResponse,
            placement: autoPlacement,
            reasoning: "Auto-placed using collision-free algorithm",
            chosenSpace: 0
        )
        
        print("✅ Parsed successfully:")
        print("   User wrote: \(userText)")
        print("   AI response: \(aiResponse)")
        print("   Auto-placement: (\(Int(autoPlacement.x)), \(Int(autoPlacement.y))) size: \(Int(autoPlacement.width))×\(Int(autoPlacement.height))")
        
        return .success(response)
    }
    
    private func validatePlacement(_ placement: ResponsePlacement, metadata: CanvasMetadata) -> ResponsePlacement {
        print("🎯 SMART PLACEMENT: Considering both user input and previous AI responses")
        
        guard let userBox = metadata.recentWritingRegion else {
            print("   ⚠️ No recent writing found, using default")
            return ResponsePlacement(x: 50, y: 50, width: 500, height: 80)
        }
        
        let responseSize = CGSize(width: 500, height: 80)  // Standard response size
        let padding: CGFloat = 40
        
        print("   📍 User's latest: x=\(Int(userBox.minX)), y=\(Int(userBox.minY)), w=\(Int(userBox.width)), h=\(Int(userBox.height))")
        
        // Find the last AI response (would be a recent occupied region that's not the user's input)
        var lastAIResponse: CGRect?
        if metadata.occupiedRegions.count > 1 {
            // Look for regions that might be previous AI responses
            // They would be relatively large (AI responses are typically 500x80) and recent
            for region in metadata.occupiedRegions.reversed() {
                // Skip if it overlaps significantly with user's recent writing (would be user's strokes)
                if !region.intersects(userBox) || region.intersection(userBox).width < region.width * 0.3 {
                    // This might be an AI response - it's separate from user's recent writing
                    if region.width > 200 {  // AI responses are wider
                        lastAIResponse = region
                        print("   🤖 Found previous AI response: x=\(Int(region.minX)), y=\(Int(region.minY)), w=\(Int(region.width)), h=\(Int(region.height))")
                        break
                    }
                }
            }
        }
        
        // Generate candidate anchor points: user's input AND last AI response
        var anchorBoxes: [(box: CGRect, name: String)] = [(userBox, "user input")]
        if let aiBox = lastAIResponse {
            anchorBoxes.append((aiBox, "previous AI response"))
        }
        
        // Try each anchor
        for (anchorBox, anchorName) in anchorBoxes {
            print("   🎯 Trying anchor: \(anchorName)")
            
            // Try 4 positions in order of preference: Below, Right, Above, Left
            let positions = [
                // 1. Below (most natural)
                CGPoint(x: anchorBox.minX, y: anchorBox.maxY + padding),
                // 2. Right
                CGPoint(x: anchorBox.maxX + padding, y: anchorBox.minY),
                // 3. Above
                CGPoint(x: anchorBox.minX, y: anchorBox.minY - responseSize.height - padding),
                // 4. Left
                CGPoint(x: anchorBox.minX - responseSize.width - padding, y: anchorBox.minY)
            ]
            
            let positionNames = ["BELOW", "RIGHT", "ABOVE", "LEFT"]

            
            for (index, position) in positions.enumerated() {
                let testBox = CGRect(origin: position, size: responseSize)
                
                // Check for significant collisions (allow minor overlaps)
                var hasSignificantCollision = false
                for occupied in metadata.occupiedRegions {
                    // Only expand by 10pt for breathing room (was 30, too aggressive)
                    let expandedOccupied = occupied.insetBy(dx: -10, dy: -10)
                    
                    // Check if there's a significant overlap (more than 20% of the response box)
                    if testBox.intersects(expandedOccupied) {
                        let intersection = testBox.intersection(expandedOccupied)
                        let intersectionArea = intersection.width * intersection.height
                        let testBoxArea = testBox.width * testBox.height
                        let overlapPercentage = intersectionArea / testBoxArea
                        
                        if overlapPercentage > 0.2 {  // More than 20% overlap = collision
                            hasSignificantCollision = true
                            print("      ❌ \(positionNames[index]): Collision (\(Int(overlapPercentage * 100))% overlap)")
                            break
                        }
                    }
                }
                
                if !hasSignificantCollision {
                    print("   ✅ \(positionNames[index]) of \(anchorName): Perfect! No collisions.")
                    return ResponsePlacement(
                        x: position.x,
                        y: position.y,
                        width: responseSize.width,
                        height: responseSize.height
                    )
                }
            }
        }
        
        // Last resort: place below user's text anyway (canvas will expand)
        print("   ⚠️ All positions have some collision, placing below anyway")
        return ResponsePlacement(
            x: userBox.minX,
            y: userBox.maxY + padding,
            width: responseSize.width,
            height: responseSize.height
        )
    }
    
    private func findFallbackPosition(size: CGSize, metadata: CanvasMetadata) -> CGPoint? {
        print("   🔍 Searching \(metadata.emptyRegions.count) empty regions...")
        
        // Try to find an empty region that fits
        for (index, emptyRegion) in metadata.emptyRegions.sorted(by: { $0.width * $0.height > $1.width * $1.height }).enumerated() {
            print("      Region \(index + 1): \(Int(emptyRegion.width))×\(Int(emptyRegion.height)) at (\(Int(emptyRegion.minX)), \(Int(emptyRegion.minY)))")
            if emptyRegion.width >= size.width && emptyRegion.height >= size.height {
                print("      ✅ Found suitable region!")
                return emptyRegion.origin
            }
        }
        
        // If no empty regions work, try to place below all existing content
        if let recentRegion = metadata.recentWritingRegion {
            let belowRecent = CGPoint(
                x: recentRegion.minX,
                y: recentRegion.maxY + 40
            )
            
            // Check if this fits on canvas
            if belowRecent.y + size.height < metadata.canvasSize.height - 20 {
                print("   📍 Placing below recent input at (\(Int(belowRecent.x)), \(Int(belowRecent.y)))")
                return belowRecent
            }
        }
        
        // Last resort: try right side of canvas
        let rightSide = CGPoint(
            x: metadata.canvasSize.width - size.width - 50,
            y: 50
        )
        
        if rightSide.x > 0 {
            print("   📍 Using right side fallback")
            return rightSide
        }
        
        // Ultimate fallback: top left
        print("   📍 Using top-left fallback (last resort)")
        return CGPoint(x: 50, y: 50)
    }
}

// MARK: - Response Models

struct EnhancedAIResponse {
    let userText: String
    let aiResponse: String
    let placement: ResponsePlacement
    let reasoning: String
    let chosenSpace: Int
}

struct ResponsePlacement {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    
    var origin: CGPoint {
        CGPoint(x: x, y: y)
    }
    
    var boundingBox: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

