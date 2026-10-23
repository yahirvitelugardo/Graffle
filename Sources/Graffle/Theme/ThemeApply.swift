#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Turns a theme into styles: how a shape, a connector or a whole drawing looks under it.
extension ThemeDefinition {
    // MARK: Base color

    /// The color a shape had before any theme touched it.
    static func originalColor(of style: Style) -> RGBA {
        if let b = style.themeBase, let f = style.themeFill, f == style.fill { return b }
        let fill: RGBA?
        switch style.fill.kind {
        case .none: fill = nil
        case .solid: fill = style.fill.color.with(alpha: 1)
        case .linear, .radial: fill = style.fill.color(at: 0.5).with(alpha: 1)
        }
        let line = style.stroke.visible ? style.stroke.color.with(alpha: 1) : nil
        // Many diagrams use a pale fill with a strong outline: the outline then carries the color.
        switch (fill, line) {
        case let (f?, l?): return l.saturation > f.saturation + 0.15 ? l : f
        case let (f?, nil): return f
        case let (nil, l?): return l
        default: return RGBA(0.45, 0.55, 0.75)
        }
    }

    /// The shape's color after the theme's accent has been mixed in.
    private func base(of style: Style) -> RGBA {
        let own = ThemeDefinition.originalColor(of: style)
        guard let a = accent.flatMap({ RGBA(hex: $0) }), let mix = accentMix, mix > 0 else { return own }
        return own.mixed(with: a, min(1, mix))
    }

    // MARK: Fonts and text color the library knows about (so leaving a theme can undo them)

    static func installedFont(from list: [String]?) -> String? {
        guard let list else { return nil }
        #if canImport(AppKit)
        let families = Set(NSFontManager.shared.availableFontFamilies)
        #else
        let families = Set(UIFont.familyNames)
        #endif
        return list.first { families.contains($0) }
    }

    private func applyText(_ t: inout TextFormat, onPage: Bool = false) {
        let spec = shape?.text
        if var c = spec?.color.flatMap({ RGBA(hex: $0) }) {
            // Free text sits on the white page, not on a shape, so light lettering (meant for dark shapes) would vanish.
            if onPage, c.luminance > 0.55 { c = RGBA(0.13, 0.14, 0.18) }
            t.color = c
        }
        else if let c = t.color, ThemeLibrary.themeTextColors.contains(c) { t.color = nil }     // one a theme set before
        if let f = ThemeDefinition.installedFont(from: spec?.fonts) { t.font = f }
        else if ThemeLibrary.themeFonts.contains(t.font) { t.font = "System" }
        if let b = spec?.bold { t.bold = b }
    }

    // MARK: Shapes

    /// `onShape` is for free text that sits on top of another shape (a caption inside a box), as opposed to text on the page.
    func apply(to style: inout Style, kind: ShapeKind, onShape: Bool = false) {
        if kind == .text {                                  // free text: only its type changes
            applyText(&style.text, onPage: !onShape)
            return
        }
        let original = ThemeDefinition.originalColor(of: style)
        let base = self.base(of: style)
        let hadFill = style.fill.kind != .none || (style.themeBase != nil && style.themeFill == style.fill)
        if !hadFill {
            // Lines, braces and outlines with no fill follow the theme's connector look (which reads on the white page), or keep
            // their own color when the theme has none.
            let ownColor = style.themeBase ?? style.stroke.color            // the color before any theme, kept so Clean can bring it back
            style.effect = nil
            style.shadow = Shadow()
            style.opacity = 1
            style.fill.kind = .none
            if let c = connector, let hex = c.color, let color = RGBA(hex: hex) {
                style.stroke.visible = true
                style.stroke.color = color
                style.stroke.width = c.width ?? style.stroke.width
                style.stroke.rough = (c.rough ?? 0) > 0 ? c.rough : nil
                style.stroke.cap = CapKind(rawValue: c.cap ?? "") ?? style.stroke.cap
                style.stroke.dash = DashKind(rawValue: c.dash ?? "") ?? style.stroke.dash
                if let g = c.glow.flatMap({ RGBA(hex: $0) }) { style.shadow = Shadow(enabled: true, color: g, blur: 8, offset: 0, angle: 90) }
            } else {
                style.stroke.color = ownColor
                style.stroke.rough = nil
            }
            applyText(&style.text)
            style.themeBase = ownColor
            style.themeFill = nil                                              // not "a filled shape the theme filled": it stays unfilled
            return
        }
        let spec = shape
        style.effect = nil
        style.stroke = Stroke()
        style.shadow = Shadow()
        style.opacity = 1

        // Fill
        let f = spec?.fill
        let surface = f?.surface.flatMap { RGBA(hex: $0) }
        var color = surface.map { $0.mixed(with: base, f?.tint ?? 1) } ?? base
        color = color.with(alpha: 1)
        switch f?.mode ?? "solid" {
        case "none":
            style.fill.kind = .none
        case "gradient":
            let top = color.lighter(f?.lighten ?? 0.3), bottom = color.darker(f?.darken ?? 0.1)
            style.fill.kind = .linear
            style.fill.angle = f?.angle ?? 90
            style.fill.color = color
            style.fill.stops = [GradientStop(color: top.with(alpha: f?.alpha ?? 1), position: 0),
                                GradientStop(color: bottom.with(alpha: f?.alpha ?? 1), position: 1)]
        default:
            style.fill.kind = .solid
            var c = color
            if let l = f?.lighten { c = c.lighter(l) }
            if let d = f?.darken { c = c.darker(d) }
            style.fill.color = c.with(alpha: f?.alpha ?? 1)
        }

        // Line
        let s = spec?.stroke
        style.stroke.visible = s?.visible ?? true
        var lineColor = s?.color.flatMap { RGBA(hex: $0) } ?? base
        if s?.color == nil {
            if let l = s?.lighten { lineColor = lineColor.lighter(l) }
            else { lineColor = lineColor.darker(s?.darken ?? 0.4) }
        }
        style.stroke.color = lineColor.with(alpha: s?.alpha ?? lineColor.a)
        style.stroke.width = s?.width ?? 1.5
        style.stroke.rough = (s?.rough ?? 0) > 0 ? s?.rough : nil
        style.stroke.cap = CapKind(rawValue: s?.cap ?? "") ?? .butt
        style.stroke.dash = DashKind(rawValue: s?.dash ?? "") ?? .solid

        // Shadow, effect, shape
        if let sh = spec?.shadow {
            style.shadow = Shadow(enabled: true, color: sh.color.flatMap { RGBA(hex: $0) } ?? RGBA(0, 0, 0, 0.3),
                                  blur: sh.blur ?? 8, offset: sh.offset ?? 4, angle: sh.angle ?? 90)
        }
        style.effect = spec?.effect.flatMap { Effect(rawValue: $0) }
        if let r = spec?.cornerRadius { style.cornerRadius = r }
        style.opacity = spec?.opacity ?? 1
        applyText(&style.text)

        style.themeBase = original
        style.themeFill = style.fill
    }

    // MARK: Connectors

    func applyToConnector(_ style: inout Style) {
        let c = connector
        let defaultLine = RGBA(0.25, 0.25, 0.3)
        style.effect = nil
        style.stroke = Stroke()
        style.shadow = Shadow()
        style.stroke.visible = true
        style.stroke.color = c?.color.flatMap { RGBA(hex: $0) } ?? defaultLine
        style.stroke.width = c?.width ?? 1.5
        style.stroke.rough = (c?.rough ?? 0) > 0 ? c?.rough : nil
        style.stroke.cap = CapKind(rawValue: c?.cap ?? "") ?? .butt
        style.stroke.dash = DashKind(rawValue: c?.dash ?? "") ?? .solid
        if let g = c?.glow.flatMap({ RGBA(hex: $0) }) { style.shadow = Shadow(enabled: true, color: g, blur: 8, offset: 0, angle: 90) }
        // Connector labels sit on the white page too.
        if let t = c?.textColor.flatMap({ RGBA(hex: $0) }) ?? shape?.text?.color.flatMap({ RGBA(hex: $0) }), t.luminance <= 0.55 { style.text.color = t }
        else if let t = style.text.color, ThemeLibrary.themeTextColors.contains(t) { style.text.color = nil }
        if let f = ThemeDefinition.installedFont(from: shape?.text?.fonts) { style.text.font = f }
        else if ThemeLibrary.themeFonts.contains(style.text.font) { style.text.font = "System" }
    }

    // MARK: Whole drawings

    /// Restyles everything in `drawing` and remembers the theme (the Clean theme is stored as "no theme").
    func apply(to drawing: inout Drawing) {
        drawing.theme = isClean ? nil : self
        let solids = drawing.shapes.filter { $0.kind != .text }
        for i in drawing.shapes.indices {
            let s = drawing.shapes[i]
            let onShape = s.kind == .text && solids.contains { $0.frame.contains(CGPoint(x: s.frame.midX, y: s.frame.midY)) }
            apply(to: &drawing.shapes[i].style, kind: s.kind, onShape: onShape)
        }
        for i in drawing.connectors.indices { applyToConnector(&drawing.connectors[i].style) }
    }
}
