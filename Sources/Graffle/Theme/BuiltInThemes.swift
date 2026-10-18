import Foundation

/// The themes that come with Graffle. They are written in the same JSON format users' theme files use,
/// so a built-in theme is also a worked example of the format.
enum BuiltInThemes {
    static let json: [String] = [
        #"""
        {"format":1,"id":"clean","name":"Clean","author":"Graffle","summary":"The plain default look."}
        """#,
        #"""
        {"format":1,"id":"soft-ui","name":"Soft UI","author":"Graffle","summary":"Pale cards with soft shadows.",
         "shape":{"fill":{"mode":"gradient","surface":"#FFFFFF","tint":0.22,"lighten":0.4,"darken":0.0},
                  "stroke":{"color":"#E1E6F0","width":1},
                  "shadow":{"color":"#6B7A9959","blur":14,"offset":6,"angle":90},
                  "cornerRadius":16,"text":{"color":"#3A4256"}},
         "connector":{"color":"#8A94AB","width":2,"cap":"round"}}
        """#,
        #"""
        {"format":1,"id":"frost","name":"Frost","author":"Graffle","summary":"Frosted glass panels with a light rim.",
         "shape":{"fill":{"surface":"#E6EEFF","tint":0.3,"alpha":0.75},
                  "stroke":{"color":"#A9BDF0","width":1.2},
                  "shadow":{"color":"#5A6A9A40","blur":16,"offset":6,"angle":90},
                  "effect":"glass","cornerRadius":18,"text":{"color":"#2F3A66"}},
         "connector":{"color":"#6F7FB0","width":2,"cap":"round"}}
        """#,
        #"""
        {"format":1,"id":"midnight","name":"Midnight","author":"Graffle","summary":"Dark navy cards with a blue-violet glow.",
         "shape":{"fill":{"mode":"gradient","surface":"#1B2A4A","tint":0.35,"lighten":0.1,"darken":0.12},
                  "stroke":{"lighten":0.3,"alpha":0.55,"width":1.2},
                  "shadow":{"color":"#00000088","blur":16,"offset":6,"angle":90},
                  "cornerRadius":18,"text":{"color":"#E8EEFF"}},
         "connector":{"color":"#6C7BFF","width":2,"cap":"round","glow":"#6A5CFF66"}}
        """#,
        #"""
        {"format":1,"id":"neumorphic-violet","name":"Neumorphic Violet","author":"Graffle","summary":"Soft, pressed-out shapes with violet accents.",
         "accent":"#9B3BF5","accentMix":0.55,
         "shape":{"fill":{"surface":"#E9ECF6","tint":0.3},
                  "stroke":{"visible":false},
                  "effect":"neumorphic","cornerRadius":18,"text":{"color":"#2D2F52"}},
         "connector":{"color":"#8B8FB5","width":2.5,"cap":"round"}}
        """#,
        #"""
        {"format":1,"id":"aurora-glass","name":"Aurora Glass","author":"Graffle","summary":"Violet glass panels with a glowing pink rim.",
         "accent":"#8B5CF6","accentMix":0.6,
         "shape":{"fill":{"mode":"gradient","surface":"#7C3AED","tint":0.5,"lighten":0.25,"darken":0.05,"alpha":0.9},
                  "stroke":{"color":"#FFFFFF","alpha":0.6,"width":1.2},
                  "shadow":{"color":"#5B21B680","blur":18,"offset":8,"angle":90},
                  "effect":"glass","cornerRadius":20,"text":{"color":"#FFFFFF"}},
         "connector":{"color":"#8B5CF6","width":2,"cap":"round","glow":"#EC489966"}}
        """#,
        #"""
        {"format":1,"id":"sky-wireframe","name":"Sky Wireframe","author":"Graffle","summary":"Flat pale-blue panels, light and airy.",
         "accent":"#6C9BE6","accentMix":0.7,
         "shape":{"fill":{"surface":"#D4E2F7","tint":0.4},
                  "stroke":{"visible":false},
                  "shadow":{"color":"#5B7CB840","blur":12,"offset":4,"angle":90},
                  "cornerRadius":6,"text":{"color":"#3F66B5"}},
         "connector":{"color":"#5B8BDD","width":1.5,"cap":"round"}}
        """#,
        #"""
        {"format":1,"id":"soft-blue","name":"Soft Blue","author":"Graffle","summary":"Blue gradient tiles with white lettering.",
         "accent":"#6F97EA","accentMix":0.85,
         "shape":{"fill":{"mode":"gradient","lighten":0.22,"darken":0.06},
                  "stroke":{"visible":false},
                  "shadow":{"color":"#0000002E","blur":10,"offset":4,"angle":90},
                  "cornerRadius":14,"text":{"color":"#FFFFFF"}},
         "connector":{"color":"#7E8AA6","width":2,"cap":"round"}}
        """#,
        #"""
        {"format":1,"id":"marker-doodle","name":"Marker Doodle","author":"Graffle","summary":"Bright marker scribbles; the grid turns into ruled-paper blue.",
         "gridColor":"#8FD3EA33",
         "shape":{"fill":{"lighten":0.1},
                  "stroke":{"lighten":0.0,"width":4.5,"rough":0.9,"cap":"round"},
                  "effect":"hatch","cornerRadius":12,
                  "text":{"color":"#2B2B3A","fonts":["Marker Felt","Noteworthy","Chalkboard SE"],"bold":true}},
         "connector":{"color":"#6B6F8A","width":3.5,"rough":0.8,"cap":"round"}}
        """#,
        #"""
        {"format":1,"id":"chalkboard","name":"Chalkboard","author":"Graffle","summary":"White chalk lines on dark board slabs.",
         "shape":{"fill":{"surface":"#3A3A3A","tint":0.0},
                  "stroke":{"color":"#F4F1E8","width":2.4,"rough":0.6,"cap":"round"},
                  "cornerRadius":8,
                  "text":{"color":"#F4F1E8","fonts":["Chalkboard SE","Chalkduster","Noteworthy"]}},
         "connector":{"color":"#3A3A3A","width":2.4,"rough":0.6,"cap":"round"}}
        """#,
        #"""
        {"format":1,"id":"green-chalk","name":"Green Chalk","author":"Graffle","summary":"Loose handwritten chalk on green slabs.",
         "gridColor":"#1E3F3422",
         "shape":{"fill":{"surface":"#1E3F34","tint":0.0},
                  "stroke":{"color":"#F2F2E6","width":2,"rough":1.0,"cap":"round"},
                  "cornerRadius":10,
                  "text":{"color":"#F2F2E6","fonts":["Bradley Hand","Noteworthy","Chalkboard SE"]}},
         "connector":{"color":"#1E3F34","width":2,"rough":0.9,"cap":"round"}}
        """#,
        #"""
        {"format":1,"id":"hud-neon","name":"HUD Neon","author":"Graffle","summary":"Glowing teal outlines on deep blue panels; teal grid.",
         "gridColor":"#0EA5A022","accent":"#3DD6D0","accentMix":0.35,
         "shape":{"fill":{"surface":"#0E3550","tint":0.25,"alpha":0.92},
                  "stroke":{"lighten":0.45,"width":1.6},
                  "shadow":{"color":"#3DD6D099","blur":12,"offset":0,"angle":90},
                  "cornerRadius":6,"text":{"color":"#BFF5F0","fonts":["Menlo","Courier New"]}},
         "connector":{"color":"#0EA5A0","width":1.6,"glow":"#0EA5A088"}}
        """#,
        #"""
        {"format":1,"id":"cyber-cyan","name":"Cyber Cyan","author":"Graffle","summary":"Cyan wireframes on black panels; teal grid.",
         "gridColor":"#19D3C533","accent":"#2FE6D5","accentMix":1.0,
         "shape":{"fill":{"surface":"#031A1C","tint":0.0,"alpha":0.94},
                  "stroke":{"color":"#2FE6D5","width":1.6},
                  "shadow":{"color":"#2FE6D58C","blur":10,"offset":0,"angle":90},
                  "cornerRadius":2,"text":{"color":"#7FF5EA","fonts":["Menlo","Courier New"]}},
         "connector":{"color":"#0E9F94","width":1.4,"glow":"#2FE6D580"}}
        """#,
        #"""
        {"format":1,"id":"clay","name":"Clay","author":"Graffle","summary":"Soft 3D tiles.",
         "shape":{"fill":{"mode":"gradient","surface":"#FFFFFF","tint":0.6,"lighten":0.1,"darken":0.08},
                  "stroke":{"visible":false},
                  "shadow":{"color":"#1E16264D","blur":16,"offset":8,"angle":90},
                  "effect":"clay","cornerRadius":22,"text":{"color":"#3B2A45"}},
         "connector":{"color":"#A78BBA","width":3,"cap":"round"}}
        """#,
    ]

    static let all: [ThemeDefinition] = json.compactMap { text in
        do { return try ThemeDefinition.decode(Data(text.utf8)) }
        catch { assertionFailure("Built-in theme is invalid: \(error.localizedDescription)\n\(text)"); return nil }
    }
}
