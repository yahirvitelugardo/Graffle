import Foundation

enum LengthUnit: String, Codable, CaseIterable {
    case millimeter, centimeter, meter, inch, foot

    var title: String {
        switch self {
        case .millimeter: return "Millimeters"
        case .centimeter: return "Centimeters"
        case .meter: return "Meters"
        case .inch: return "Inches"
        case .foot: return "Feet"
        }
    }

    var symbol: String {
        switch self {
        case .millimeter: return "mm"
        case .centimeter: return "cm"
        case .meter: return "m"
        case .inch: return "in"
        case .foot: return "ft"
        }
    }

    /// Millimeters in one unit.
    var millimeters: Double {
        switch self {
        case .millimeter: return 1
        case .centimeter: return 10
        case .meter: return 1000
        case .inch: return 25.4
        case .foot: return 304.8
        }
    }

    var defaultDecimals: Int {
        switch self {
        case .millimeter, .centimeter: return 0
        case .meter, .foot: return 2
        case .inch: return 1
        }
    }

    /// A sensible wall thickness in this unit (15 cm).
    var defaultWall: Double { 150 / millimeters }
}

/// What a canvas point stands for in the real world, so drawings can carry true measurements.
/// Without one a drawing counts one point as one centimeter.
struct DrawingScale: Codable, Equatable {
    var unit: LengthUnit = .centimeter
    /// How many `unit`s one canvas point stands for.
    var unitsPerPoint: Double = 1
    /// Decimals shown in measurements; nil = the unit's usual number.
    var decimals: Int? = nil
    /// Thickness of walls drawn with the Wall tool, in `unit`s; nil = 15 cm.
    var wallThickness: Double? = nil

    static let standard = DrawingScale()

    /// Points per printed inch: a PDF or a print puts 72 points on one inch of paper.
    static let pointsPerInch = 72.0

    var shownDecimals: Int { min(max(decimals ?? unit.defaultDecimals, 0), 4) }

    /// Real length of `points` canvas points, in `unit`s.
    func length(_ points: Double) -> Double { points * unitsPerPoint }
    func points(_ length: Double) -> Double { length / max(unitsPerPoint, 1e-9) }

    /// Canvas points in one centimeter (what real-size library items are multiplied by).
    var pointsPerCentimeter: Double { 10 / max(unitsPerPoint * unit.millimeters, 1e-9) }

    var wallThicknessPoints: Double { points(wallThickness ?? unit.defaultWall) }

    /// "3.20 m": a length in canvas points, in this scale.
    func format(points: Double) -> String {
        String(format: "%.\(shownDecimals)f", length(points)) + " " + unit.symbol
    }

    /// The N of a "1:N" printed scale (at 72 points per inch).
    var printRatio: Double { unitsPerPoint * unit.millimeters / (25.4 / Self.pointsPerInch) }

    /// A scale for "1:N" on paper, measuring in `unit`s.
    static func ratio(_ n: Double, unit: LengthUnit) -> DrawingScale {
        var s = DrawingScale()
        s.unit = unit
        s.unitsPerPoint = n * (25.4 / pointsPerInch) / unit.millimeters
        return s
    }
}
