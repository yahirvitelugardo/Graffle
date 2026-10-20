import Foundation
import CoreGraphics

/// Floor-plan parts at their real size in centimeters: the drawing scale turns them into points when they are placed.
/// Doors and windows are drawn for a 15 cm wall, with the wall centered on the part's top band.
enum ArchitectureCatalog {
    /// A path written in centimeters inside a `w` x `h` part.
    struct CMPen {
        var pen = ShapeCatalog.Pen()
        let w: Double, h: Double
        init(_ w: Double, _ h: Double) { self.w = w; self.h = h }
        mutating func m(_ x: Double, _ y: Double) { pen.m(x / w, y / h) }
        mutating func l(_ x: Double, _ y: Double) { pen.l(x / w, y / h) }
        mutating func z() { pen.z() }
        mutating func rect(_ x: Double, _ y: Double, _ rw: Double, _ rh: Double) {
            m(x, y); l(x + rw, y); l(x + rw, y + rh); l(x, y + rh); z()
        }
        mutating func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { m(x1, y1); l(x2, y2) }
        mutating func circle(_ cx: Double, _ cy: Double, _ r: Double) { pen.oval(cx / w, cy / h, r / w, r / h) }
        mutating func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) { pen.oval(cx / w, cy / h, rx / w, ry / h) }
        /// An arc of the circle at (cx, cy), from angle `a0` to `a1` in degrees (0 = right, 90 = down on the page), either direction.
        mutating func arc(_ cx: Double, _ cy: Double, _ r: Double, from a0: Double, to a1: Double) {
            let parts = max(1, Int(ceil(abs(a1 - a0) / 90)))
            let step = (a1 - a0) / Double(parts) * .pi / 180
            var a = a0 * .pi / 180
            m(cx + r * cos(a), cy + r * sin(a))
            for _ in 0..<parts {
                let k = 4 / 3 * tan(step / 4), b = a + step
                let p1 = (cx + r * (cos(a) - k * sin(a)), cy + r * (sin(a) + k * cos(a)))
                let p2 = (cx + r * (cos(b) + k * sin(b)), cy + r * (sin(b) - k * cos(b)))
                pen.c(p1.0 / w, p1.1 / h, p2.0 / w, p2.1 / h, (cx + r * cos(b)) / w, (cy + r * sin(b)) / h)
                a = b
            }
        }
        /// A tiny arrowhead at (x, y) pointing along `degrees`.
        mutating func arrowHead(_ x: Double, _ y: Double, degrees: Double, size: Double = 10) {
            let a = degrees * .pi / 180
            for side in [-1.0, 1.0] {
                let b = a + .pi + side * 0.45
                m(x, y); l(x + size * cos(b), y + size * sin(b))
            }
        }
    }

    private static let ink = RGBA(0.12, 0.13, 0.17)

    private enum Fill { case white, none, dark }

    private static func style(_ fill: Fill, width: Double = 1.5) -> Style {
        var st = Style()
        st.stroke.color = ink
        st.stroke.width = width
        st.stroke.cap = .round
        st.stroke.join = .round
        switch fill {
        case .white: st.fill.kind = .solid; st.fill.color = RGBA(1, 1, 1)
        case .none: st.fill.kind = .none
        case .dark: st.fill.kind = .solid; st.fill.color = RGBA(0.30, 0.31, 0.35)
        }
        return st
    }

    /// A part: optional white cut-out (to hide the wall behind a door or window), then the symbol itself.
    private static func part(_ id: String, _ name: String, _ w: Double, _ h: Double, fill: Fill = .white, cutout: CGSize? = nil, lineWidth: Double = 1.5,
                             extra: ((UUID) -> [Shape])? = nil, _ draw: @escaping (inout CMPen) -> Void) -> LibraryItem {
        var item = LibraryItem(id: "arch-" + id, name: name, category: ShapeCatalog.architecture, origin: .builtin, size: CGSize(width: w, height: h))
        item.realSize = CGSize(width: w, height: h)
        item.usesCurrentStyle = false
        item.compose = { layer in
            var shapes: [Shape] = []
            if let cut = cutout {
                var st = Style()
                st.fill.kind = .solid; st.fill.color = RGBA(1, 1, 1); st.stroke.visible = false
                shapes.append(Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 0, y: 0, width: cut.width, height: cut.height), style: st, name: name + " opening"))
            }
            var pen = CMPen(w, h)
            draw(&pen)
            shapes.append(Shape(layer: layer, kind: .path, frame: CGRect(x: 0, y: 0, width: w, height: h), style: style(fill, width: lineWidth),
                                outline: pen.pen.segs, name: name))
            shapes += extra?(layer) ?? []
            return shapes
        }
        return item
    }

    private static func label(_ text: String, at frame: CGRect, size: Double = 12) -> (UUID) -> [Shape] {
        { layer in
            var st = Style.textBox
            st.text.size = size; st.text.bold = true; st.text.color = ink
            return [Shape(layer: layer, kind: .text, frame: frame, style: st, text: text)]
        }
    }

    static let items: [LibraryItem] = [
        // Openings (wall 15 cm thick, centered on the top band)
        part("door-single", "Door (right hinge)", 90, 105, fill: .none, cutout: CGSize(width: 90, height: 15)) { p in
            p.line(0, 0, 0, 15); p.line(90, 0, 90, 15)
            p.rect(0, 15, 4, 90); p.arc(0, 15, 90, from: 0, to: 90)
        },
        part("door-single-left", "Door (left hinge)", 90, 105, fill: .none, cutout: CGSize(width: 90, height: 15)) { p in
            p.line(0, 0, 0, 15); p.line(90, 0, 90, 15)
            p.rect(86, 15, 4, 90); p.arc(90, 15, 90, from: 180, to: 90)
        },
        part("door-double", "Double Door", 160, 95, fill: .none, cutout: CGSize(width: 160, height: 15)) { p in
            p.line(0, 0, 0, 15); p.line(160, 0, 160, 15)
            p.rect(0, 15, 4, 80); p.arc(0, 15, 80, from: 0, to: 90)
            p.rect(156, 15, 4, 80); p.arc(160, 15, 80, from: 180, to: 90)
        },
        part("door-sliding", "Sliding Door", 150, 15, fill: .none, cutout: CGSize(width: 150, height: 15)) { p in
            p.line(0, 0, 0, 15); p.line(150, 0, 150, 15)
            p.rect(4, 2.5, 80, 4); p.rect(66, 8.5, 80, 4)
        },
        part("opening", "Opening", 100, 15, fill: .none, cutout: CGSize(width: 100, height: 15)) { p in
            p.line(0, 0, 0, 15); p.line(100, 0, 100, 15)
        },
        part("window", "Window", 120, 15, cutout: CGSize(width: 120, height: 15)) { p in
            p.rect(0, 0, 120, 15); p.line(0, 7.5, 120, 7.5)
        },
        part("window-double", "Double Window", 180, 15, cutout: CGSize(width: 180, height: 15)) { p in
            p.rect(0, 0, 180, 15); p.line(0, 7.5, 180, 7.5); p.line(90, 0, 90, 15)
        },

        // Structure
        part("stairs", "Stairs", 100, 280, fill: .none) { p in
            p.rect(0, 0, 100, 280)
            for i in 1..<10 { p.line(0, Double(i) * 28, 100, Double(i) * 28) }
            p.line(50, 262, 50, 30); p.arrowHead(50, 22, degrees: -90)
        },
        part("column-square", "Column", 40, 40, fill: .dark) { p in p.rect(0, 0, 40, 40) },
        part("column-round", "Round Column", 40, 40, fill: .dark) { p in p.circle(20, 20, 20) },

        // Furniture
        part("bed-double", "Double Bed", 160, 200) { p in
            p.rect(0, 0, 160, 200); p.rect(10, 10, 65, 38); p.rect(85, 10, 65, 38); p.line(0, 75, 160, 75)
        },
        part("bed-single", "Single Bed", 90, 200) { p in
            p.rect(0, 0, 90, 200); p.rect(10, 10, 70, 38); p.line(0, 75, 90, 75)
        },
        part("sofa-3", "Sofa (3 seats)", 210, 90) { p in
            p.rect(0, 0, 210, 90); p.rect(0, 0, 210, 22); p.rect(0, 22, 22, 68); p.rect(188, 22, 22, 68)
            p.line(77, 22, 77, 90); p.line(133, 22, 133, 90)
        },
        part("armchair", "Armchair", 80, 80) { p in
            p.rect(0, 0, 80, 80); p.rect(0, 0, 80, 18); p.rect(0, 18, 16, 62); p.rect(64, 18, 16, 62)
        },
        part("table-rect", "Table", 160, 90) { p in p.rect(0, 0, 160, 90) },
        part("table-round", "Round Table", 100, 100) { p in p.circle(50, 50, 50) },
        part("chair", "Chair", 45, 45) { p in p.rect(0, 0, 45, 45); p.rect(0, 0, 45, 9) },
        part("desk", "Desk", 140, 70) { p in p.rect(0, 0, 140, 70); p.rect(95, 4, 41, 62); p.line(95, 35, 136, 35) },
        part("wardrobe", "Wardrobe", 120, 60) { p in p.rect(0, 0, 120, 60); p.line(0, 0, 120, 60); p.line(0, 60, 120, 0) },

        // Kitchen and bathroom
        part("sink-double", "Kitchen Sink", 80, 50) { p in
            p.rect(0, 0, 80, 50); p.rect(7, 8, 30, 34); p.rect(43, 8, 30, 34); p.circle(40, 4, 2.5)
        },
        part("stove", "Stove", 60, 60) { p in
            p.rect(0, 0, 60, 60); p.circle(17, 17, 9); p.circle(43, 17, 9); p.circle(17, 43, 9); p.circle(43, 43, 9)
        },
        part("fridge", "Refrigerator", 60, 65) { p in p.rect(0, 0, 60, 65); p.line(0, 22, 60, 22); p.rect(50, 8, 4, 10); p.rect(50, 28, 4, 22) },
        part("washer", "Washing Machine", 60, 60) { p in p.rect(0, 0, 60, 60); p.circle(30, 33, 19); p.circle(30, 33, 11) },
        part("toilet", "Toilet", 40, 70) { p in p.rect(5, 0, 30, 20); p.oval(20, 46, 17, 24) },
        part("washbasin", "Washbasin", 55, 45) { p in p.rect(0, 0, 55, 45); p.oval(27.5, 24, 19, 14); p.circle(27.5, 6, 2.5) },
        part("bathtub", "Bathtub", 170, 75) { p in p.rect(0, 0, 170, 75); p.rect(6, 6, 158, 63); p.circle(154, 37.5, 3.5) },
        part("shower", "Shower", 90, 90) { p in p.rect(0, 0, 90, 90); p.line(0, 0, 90, 90); p.line(0, 90, 90, 0); p.circle(45, 45, 4) },

        // Symbols
        part("north", "North Arrow", 60, 90, fill: .none, extra: label("N", at: CGRect(x: 15, y: 0, width: 30, height: 20))) { p in
            p.circle(30, 60, 28)
            p.m(30, 36); p.l(40, 78); p.l(30, 69); p.l(20, 78); p.z()
        },
    ]
}
