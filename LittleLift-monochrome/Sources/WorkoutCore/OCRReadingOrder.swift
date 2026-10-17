import Foundation

public struct OCRTextBox: Sendable {
    public let text: String
    public let x: Double
    public let y: Double
    public let height: Double
    public init(text: String, x: Double, y: Double, height: Double) { self.text = text; self.x = x; self.y = y; self.height = height }
}
public enum OCRReadingOrder {
    /// Vision's normalized coordinates start at the bottom. Keep cells on one
    /// visual row together; explicit table headers determine whether to use tabs.
    public static func text(from boxes: [OCRTextBox]) throws -> String {
        guard boxes.count <= 2000, boxes.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.height.isFinite && $0.height > 0 }),
              boxes.reduce(0, { $0 + $1.text.utf8.count }) <= 64_000 else {
            throw WorkoutError.invalidInput(L10n.s("This image contains too much text. Crop it to one workout."))
        }
        var rows: [[OCRTextBox]] = []
        for box in boxes.sorted(by: { $0.y > $1.y }) {
            if let i = rows.indices.last, let first = rows[i].first, abs(first.y - box.y) <= min(first.height, box.height) * 0.55 {
                rows[i].append(box)
            } else { rows.append([box]) }
        }
        let ordered = rows.map { $0.sorted { $0.x < $1.x } }
        let headerIndex = ordered.firstIndex { row in
            row.count >= 3 && TabularWorkoutImport.extract(row.map(\.text).joined(separator: "\t")) != nil
        }
        let text: String
        if let headerIndex {
            let header = ordered[headerIndex]
            text = ordered.enumerated().map { index, row in
                guard index > headerIndex else { return row.map(\.text).joined(separator: index == headerIndex ? "\t" : " ") }
                var cells = Array(repeating: "", count: header.count)
                for box in row {
                    guard let closest = header.indices.min(by: { abs(header[$0].x - box.x) < abs(header[$1].x - box.x) }) else { continue }
                    let spacing = header.indices.filter { $0 != closest }.map { abs(header[$0].x - header[closest].x) }.min() ?? 0
                    // Conservative alignment: uncertain or merged cells keep the
                    // whole row unresolved instead of shifting numeric columns.
                    guard abs(header[closest].x - box.x) < max(0.015, spacing * 0.4), cells[closest].isEmpty else {
                        return row.map(\.text).joined(separator: " ")
                    }
                    cells[closest] = box.text
                }
                return cells.joined(separator: "\t")
            }.joined(separator: "\n")
        } else { text = ordered.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n") }
        guard text.utf8.count <= 64_000 else { throw WorkoutError.invalidInput(L10n.s("This image contains too much text. Crop it to one workout.")) }
        return text
    }
}
