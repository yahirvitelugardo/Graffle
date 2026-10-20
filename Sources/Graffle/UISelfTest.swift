import AppKit

/// Self-test steps for the interface's design tokens and the System / Light / Dark preference.
extension AppDelegate {
    func uiSteps() -> [(String, () -> Bool)] {
        var steps: [(String, () -> Bool)] = []
        func rgb(_ c: NSColor, _ appearance: NSAppearance.Name) -> (r: Int, g: Int, b: Int) {
            var out = (0, 0, 0)
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                let s = c.usingColorSpace(.sRGB)!
                out = (Int((s.redComponent * 255).rounded()), Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
            }
            return out
        }
        steps.append(("ui: tokens resolve to the light and dark values from the design", {
            func eq(_ c: NSColor, _ l: (Int, Int, Int), _ d: (Int, Int, Int)) -> Bool {
                let a = rgb(c, .aqua), b = rgb(c, .darkAqua)
                return (a.r, a.g, a.b) == l && (b.r, b.g, b.b) == d
            }
            return eq(Tok.windowBG, (0xEC, 0xEC, 0xEF), (0x14, 0x15, 0x18)) && eq(Tok.accent, (0x00, 0x71, 0xE3), (0x25, 0x63, 0xEB))
                && eq(Tok.textPrimary, (0x1D, 0x1D, 0x1F), (0xEC, 0xED, 0xEF)) && eq(Tok.textSecondary, (0x6E, 0x6E, 0x73), (0xA1, 0xA4, 0xAB))
                && eq(Tok.fieldBG, (0xF2, 0xF2, 0xF5), (0x2A, 0x2C, 0x31)) && eq(Tok.canvasBG, (0xFF, 0xFF, 0xFF), (0xF6, 0xF6, 0xF4))
                && eq(Tok.selectionRow, (0x00, 0x71, 0xE3), (0x1E, 0x3A, 0x7A)) && eq(Tok.switchOn, (0x34, 0xC7, 0x59), (0x25, 0x63, 0xEB))
        }))
        steps.append(("ui: text tokens keep 4.5:1 contrast on their panels in both themes", {
            func lum(_ c: (r: Int, g: Int, b: Int)) -> Double {
                func f(_ v: Int) -> Double { let x = Double(v) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
                return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
            }
            func ratio(_ a: NSColor, _ b: NSColor, _ m: NSAppearance.Name) -> Double {
                let la = lum(rgb(a, m)), lb = lum(rgb(b, m))
                return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
            }
            // Light panels are translucent white over the window color; measure against the card/window they sit on.
            return ratio(Tok.textPrimary, Tok.windowBG, .aqua) >= 4.5 && ratio(Tok.textSecondary, Tok.cardBG, .aqua) >= 4.5
                && ratio(Tok.textPrimary, Tok.cardBG, .darkAqua) >= 4.5 && ratio(Tok.textSecondary, Tok.cardBG, .darkAqua) >= 4.5
                && ratio(Tok.textSecondary, Tok.fieldBG, .darkAqua) >= 4.5 && ratio(Tok.textSecondary, Tok.cardBG, .aqua) >= 4.5
        }))
        steps.append(("ui: the appearance preference is saved and switches the app live", {
            let defaults = UserDefaults.standard
            let saved = defaults.object(forKey: UIAppearance.key)
            let savedAppearance = NSApp.appearance
            defer { if let saved { defaults.set(saved, forKey: UIAppearance.key) } else { defaults.removeObject(forKey: UIAppearance.key) }; NSApp.appearance = savedAppearance }
            var notified = 0
            let token = NotificationCenter.default.addObserver(forName: .uiAppearanceChanged, object: nil, queue: nil) { _ in notified += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            UIAppearance.current = .dark
            let dark = NSApp.appearance?.name == .darkAqua && defaults.string(forKey: UIAppearance.key) == "dark" && UIAppearance.current == .dark
            let surface = SurfaceView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            surface.fill = Tok.cardBG
            let window = NSWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
            window.contentView = surface
            surface.updateSurface()
            let darkFill = surface.layer?.backgroundColor?.components?.prefix(3).map { Int(($0 * 255).rounded()) }
            UIAppearance.current = .light
            surface.updateSurface()
            let lightFill = surface.layer?.backgroundColor?.components?.prefix(3).map { Int(($0 * 255).rounded()) }
            UIAppearance.current = .system
            let system = NSApp.appearance == nil
            let menu = self.makeMainMenu().items.first { $0.title == "View" }?.submenu?.items.first { $0.title == "Appearance" }?.submenu
            let listed = menu?.items.map(\.title) == ["System", "Light", "Dark"]
            return dark && darkFill == [0x26, 0x28, 0x2D] && lightFill == [255, 255, 255] && system && listed && notified == 3
        }))
        steps.append(("ui: the canvas stays light in dark mode, and exports are always white", {
            let defaults = UserDefaults.standard
            let saved = defaults.object(forKey: UIAppearance.key), savedAppearance = NSApp.appearance
            defer { if let saved { defaults.set(saved, forKey: UIAppearance.key) } else { defaults.removeObject(forKey: UIAppearance.key) }; NSApp.appearance = savedAppearance }
            UIAppearance.current = .dark
            var d = Drawing()
            d.shapes = [Shape(layer: d.layers[0].id, kind: .rectangle, frame: CGRect(x: 100, y: 100, width: 100, height: 60))]
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: CanvasView.canvasSize))
            canvas.load(d)
            guard let png = canvas.pngData(), let rep = NSBitmapImageRep(data: png), let c = rep.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB) else { return false }
            return c.redComponent > 0.99 && c.greenComponent > 0.99 && c.blueComponent > 0.99
        }))
        return steps
    }
}
