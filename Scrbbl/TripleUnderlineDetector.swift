import CoreGraphics
import PencilKit

/// A Pencil gesture that asks a question, plus the strokes that make up the
/// gesture so they can be excluded from handwriting recognition.
struct GestureTrigger {
    enum Kind {
        case tripleUnderline
        case circle
    }

    let kind: Kind
    let bounds: CGRect
    let strokeIndices: Range<Int>

    var detail: AnswerDetail {
        switch kind {
        case .tripleUnderline: return .short
        case .circle: return .comprehensive
        }
    }
}

struct TripleUnderlineDetector {
    /// Looks only at the most recent strokes, so a gesture fires once when it is
    /// completed rather than on every stroke written afterwards.
    func trigger(in drawing: PKDrawing) -> GestureTrigger? {
        circle(in: drawing) ?? tripleUnderline(in: drawing)
    }

    // Forgiving geometry: the last three strokes only need to be roughly
    // horizontal marks stacked under the same words. Real underlines wobble,
    // slant, and vary in length.
    func tripleUnderline(in drawing: PKDrawing) -> GestureTrigger? {
        let strokes = drawing.strokes
        guard strokes.count >= 3 else { return nil }

        let indices = (strokes.count - 3)..<strokes.count
        let recent = indices.map { strokes[$0] }
        guard recent.allSatisfy(isHorizontalLine) else { return nil }

        let bounds = recent.dropFirst().reduce(recent[0].renderBounds) { $0.union($1.renderBounds) }
        guard bounds.height < 220 else { return nil }

        // The three lines must be stacked above one another, not side by side
        // the way consecutive words are: each pair overlaps horizontally.
        for (a, b) in [(0, 1), (1, 2), (0, 2)] {
            let first = recent[a].renderBounds, second = recent[b].renderBounds
            let overlap = min(first.maxX, second.maxX) - max(first.minX, second.minX)
            guard overlap > min(first.width, second.width) * 0.2 else { return nil }
        }

        return GestureTrigger(kind: .tripleUnderline, bounds: bounds, strokeIndices: indices)
    }

    func circle(in drawing: PKDrawing) -> GestureTrigger? {
        guard let stroke = drawing.strokes.last else { return nil }
        let bounds = stroke.renderBounds
        // A circled sentence is usually a long, flat oval, so allow wide shapes.
        guard bounds.width > 110, bounds.height > 45, bounds.width / bounds.height < 14,
              let first = stroke.path.first, let last = stroke.path.last else { return nil }
        // Hand-drawn circles rarely close exactly; allow a gap or an overshoot.
        let gapAllowance = max(70, min(bounds.width, bounds.height) * 0.5)
        let closes = hypot(last.location.x - first.location.x, last.location.y - first.location.y) < gapAllowance
        guard closes else { return nil }
        let index = drawing.strokes.count - 1
        return GestureTrigger(kind: .circle, bounds: bounds, strokeIndices: index..<(index + 1))
    }

    private func isHorizontalLine(_ stroke: PKStroke) -> Bool {
        let bounds = stroke.renderBounds
        guard bounds.width > 50, bounds.height < max(35, bounds.width * 0.4) else {
            return false
        }
        guard let angle = strokePathAngle(stroke) else { return false }
        let normalized = min(abs(angle), abs(abs(angle) - .pi))
        guard normalized < 0.5 else { return false }  // about 30 degrees of slant either way
        return isRoughlyStraight(stroke)
    }

    /// An underline can wobble and slant, but a cursive word zigzags up and down.
    /// Compare the drawn path's length with the straight distance between its
    /// ends, and check how far it strays from that straight line.
    private func isRoughlyStraight(_ stroke: PKStroke) -> Bool {
        let points = stroke.path.map(\.location)
        guard let first = points.first, let last = points.last else { return false }
        let chord = hypot(last.x - first.x, last.y - first.y)
        guard chord > 0 else { return false }

        var pathLength: CGFloat = 0
        var maxDeviation: CGFloat = 0
        let dx = last.x - first.x
        let dy = last.y - first.y
        for (index, point) in points.enumerated() {
            if index > 0 {
                let previous = points[index - 1]
                pathLength += hypot(point.x - previous.x, point.y - previous.y)
            }
            // Perpendicular distance from the straight line between the ends.
            let cross: CGFloat = dx * (first.y - point.y) - (first.x - point.x) * dy
            maxDeviation = max(maxDeviation, abs(cross) / chord)
        }

        return pathLength < chord * 1.3 && maxDeviation < max(18, chord * 0.12)
    }

    private func strokePathAngle(_ stroke: PKStroke) -> CGFloat? {
        guard let first = stroke.path.first,
              let last = stroke.path.last else { return nil }
        return atan2(last.location.y - first.location.y, last.location.x - first.location.x)
    }
}

/// Finds the handwriting a gesture points at. The gesture strokes themselves
/// are never included, so they are not read as part of the question.
enum QuestionLocator {
    /// About an inch on iPad: any underline within this distance below the
    /// writing counts.
    static let maxGapAboveLines: CGFloat = 150
    /// Room for a question that wraps onto two or three lines.
    static let maxQuestionHeight: CGFloat = 320
    /// Gap between wrapped lines of the same question.
    static let lineSpacingAllowance: CGFloat = 45

    static func strokes(for trigger: GestureTrigger, in drawing: PKDrawing) -> [PKStroke] {
        let candidates = drawing.strokes.enumerated()
            .filter { !trigger.strokeIndices.contains($0.offset) }
            .map(\.element)

        switch trigger.kind {
        case .circle:
            return candidates.filter { stroke in
                let bounds = stroke.renderBounds
                return trigger.bounds.contains(CGPoint(x: bounds.midX, y: bounds.midY))
            }
        case .tripleUnderline:
            return questionAbove(trigger.bounds, in: candidates)
        }
    }

    /// Starts from writing within about an inch above the lines, then grows to
    /// take in the whole sentence: the rest of that line, wherever it runs
    /// horizontally, and any lines it wraps onto just above.
    private static func questionAbove(_ lines: CGRect, in strokes: [PKStroke]) -> [PKStroke] {
        let above = strokes.filter { $0.renderBounds.midY < lines.midY }

        var picked = above.indices.filter { lines.minY - above[$0].renderBounds.maxY <= maxGapAboveLines }
        guard !picked.isEmpty else { return [] }

        var band = picked.map { above[$0].renderBounds }.reduce(CGRect.null) { $0.union($1) }
        let floor = band.maxY
        var grew = true
        while grew {
            grew = false
            for index in above.indices where !picked.contains(index) {
                let bounds = above[index].renderBounds
                let touchesBand = bounds.maxY >= band.minY - lineSpacingAllowance
                let withinQuestion = bounds.minY >= floor - maxQuestionHeight
                if touchesBand && withinQuestion {
                    picked.append(index)
                    band = band.union(bounds)
                    grew = true
                }
            }
        }
        return picked.map { above[$0] }
    }
}
