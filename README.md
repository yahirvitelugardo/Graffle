# Graffle

*Leer en [español](README.es.md).*

A native macOS diagramming and vector drawing app (Swift + AppKit), inspired by OmniGraffle.

## Build and run

```bash
./scripts/bundle.sh        # builds build/Graffle.app
open build/Graffle.app
```

Requires only the Command Line Tools (or Xcode) and macOS 13+. `swift run` also works.

### Installer (.dmg)

```bash
./scripts/make-dmg.sh      # builds build/Graffle-<version>.dmg and its .sha256
```

Opening the DMG shows a window with the app, a shortcut to *Applications* and a background telling you to drag one onto the other; the volume carries the Graffle icon. The script builds the app, assembles the image, applies the window layout through Finder (if macOS doesn't grant Finder Automation access, the DMG is still produced, just without the custom window), compresses it and **mounts it to verify it** (signed app, link to Applications, background, volume icon and layout). The app is ad-hoc signed and not notarized: on another Mac, the first time you have to open it with right-click → Open.

## What's included

- **Multiple documents:** open as many diagrams as you like, each in its own window with its own canvas, inspector, palette, undo history and "edited" state. File → New opens another; Open… and Open Recent open `.graf` files (also by double-clicking in Finder or dragging onto the Dock; opening a file that is already open brings its window forward instead of duplicating it). Save, Save As and Revert to Saved; closing a window (or quitting) with unsaved changes asks Save / Don’t Save / Cancel. `.svg` files also open as a new, unsaved diagram named after the file. Windows follow the system setting *Prefer tabs when opening documents*; the Window menu has Show Tab Bar, Merge All Windows and Move Tab to New Window.

- **Quick Look preview:** select a `.graf` file in Finder and press the space bar to see the diagram (a sharp, vector preview, sized to the diagram; an empty diagram shows a note). It is a Quick Look extension inside the app (`GraffleQuickLook.appex`), so it works in Finder, Spotlight and anywhere else macOS previews files. macOS registers it when the app is installed in `/Applications` (or opened from where it is); if the preview doesn't appear straight away, run `qlmanage -r` and check that *Graffle Quick Look* is on in System Settings → General → Login Items & Extensions → Quick Look.
- **Architecture diagrams from code:** *File → Import Project Architecture…* analyzes an Xcode workspace (`.xcworkspace`), project (`.xcodeproj`), Swift package (`Package.swift`), **.NET solution** (`.sln`, `.slnx`) or project (`.csproj`, `.fsproj`, `.vbproj`), **Android / Gradle build** (`settings.gradle(.kts)`), or a folder containing one, and opens a new, unsaved diagram of its modules. Every target is a node (apps, extensions, frameworks, libraries, tools, tests) with its platform, languages and file count; edges are target dependencies, links and embeds (dashed orange), and Swift package uses (purple, with the resolved version from `Package.resolved`). Local packages and referenced projects are followed. The layout is layered — dependents on top, what they depend on below — and dependency cycles are drawn as red dashed connectors labeled "cycle". Choose whether to include system frameworks, test targets and external packages in the open panel. Everything is a normal, editable Graffle drawing (layers: Dependencies, Targets, Packages, System, Legend). For .NET, every project is a node (web app, application, library or tests, with its target frameworks, language and file count); edges are `ProjectReference`s, NuGet packages (versions from the project or `Directory.Packages.props`) and shared frameworks (`FrameworkReference`); referenced projects outside the solution are followed. External packages and system frameworks get their own rows at the bottom. For Android and other Gradle builds every module from `settings.gradle(.kts)` is a node (Android app, library, dynamic feature, JVM library, multiplatform, with `minSdk`, Kotlin/Java and file count); edges are `project(":x")` and `projects.x` dependencies and external libraries (coordinates and versions from the build file or `gradle/libs.versions.toml`). Test configurations and commented-out lines are ignored, and Gradle itself is never run. Projects are read from `project.pbxproj` directly (no Xcode or build needed); packages use `swift package dump-package`, so the Command Line Tools must be installed.
- **Shapes:** rectangle, rounded rectangle, ellipse, diamond, triangle and free text.
- **Fill:** none, solid color, linear gradient (with an angle) and radial gradient, with **any number of color stops**. In the gradient editor: click the bar to add a stop, drag a marker to move it (Shift = 5% steps), Delete removes it, and there are controls for color, position and reverse.
- **Line:** color, width, pattern (solid, dashed, long dash, dotted, dash-dot), cap (butt/round/square) and corner join (miter/round/bevel).
- **Shadow** with color, angle, blur and distance; **opacity**; **corner radius**.
- **Text:** font, size, bold, italic, underline, horizontal and vertical alignment, color (or automatic, chosen for contrast with the fill).
- **Connectors** attached to shapes: straight, curved, orthogonal and rounded orthogonal; 9 arrowhead types (arrow, open arrow, hollow triangle, diamond, circle, bar…) independent at each end, with adjustable size and a label.
- **Layers:** create, delete, reorder, rename, show/hide and lock; an active layer for new objects; move the selection to another layer. Hidden layers are also left out of exports.
- **Rotation** with the round handle above a shape (Shift = 15° steps) or with the Rotation dial in the inspector. The inspector's angles (rotation, shadow, linear gradient) are round dials: drag the needle (Shift = 15° steps) or type the value in the field. Connectors, shadows and resizing respect the angle.
- **Groups:** ⌘G groups the selection, ⇧⌘G ungroups it. One click selects the whole group and it moves together; copy/paste creates a new group.
- Multiple selection, move, resize with handles, arrow keys (Shift = 10 pt), grid with snapping.
- Undo/redo (continuous changes from sliders and color panels are merged into a single step), cut/copy/paste, duplicate, bring to front / send to back, align.
- **Distribute with equal spacing** (Arrange → Distribute Horizontally / Vertically, or the context menu): with three or more shapes, the outermost stay where they are and the ones in between are spread so the gaps are equal. Locked shapes don't move.
- **Match sizes** (Arrange → Same Width / Same Height / Same Size): every selected shape takes the width, height or both of the **first one you selected** (with a marquee selection or Select All, the rearmost one). Each keeps its top-left corner; locked shapes are unchanged.
- **Smart guides** (when moving, resizing and creating shapes): the edges and center of what you drag snap (within 6 pt) to those of the other shapes, and a magenta guide line appears while they are aligned; edge-to-edge snapping works too.
  - *When moving:* with several shapes selected they move as one box.
  - *When resizing:* the edge you drag snaps (one shape, or several at once as a group). Rotated shapes don't snap, because their edges don't follow the axes.
  - *When creating:* both the corner where you start and the one you drag snap.
  - **Equal-spacing guides (when moving):** if the shape ends up at the same distance from its two neighbors, or at the same distance that already exists between two other shapes in the same row or column, it snaps and brackets showing the size of the gap (e.g. "85") are drawn over all the equal gaps. Only shapes in the same row (for horizontal spacing) or column (vertical) count.
  Turn them off in View → Smart Guides (remembered) or by holding Option while dragging.
- **Copy and paste style** (Edit → Copy Style ⌥⌘C / Paste Style ⌥⌘V, and in the context menu): carries the whole look (fill, line, shadow, opacity, corners, text format) from one object to others, but not its geometry or its text. It works on several objects at once, also on locked objects, and is a single undo step. Fill and corners only travel between shapes: pasting a connector's style doesn't erase a shape's fill, and a connector never receives a fill. With nothing selected, "Paste Style" sets the look of new objects.
- **Palette of reusable styles** (the *Styles* section of the inspector): thumbnails that show the real look (gradient, shadow, dashed line, or "Aa" for text-only styles). One click applies the style to the selection (or to new objects when nothing is selected); the **+** button saves the selected object's style under the name you choose; right-click a thumbnail: Apply, Rename…, Update from Selection and Delete. The palette is stored in the app's preferences and works for every document; the first time it comes with seven starter styles (if you later delete them all, they don't come back).
- **Fonts:** the font picker lists every font family installed on the computer (each name in its own typeface). If a document uses a font that isn't installed, it is marked "(not installed)" instead of silently showing another one.
- **Context menu (right-click):** on an object it selects it (with its whole group, if it has one) and offers Cut, Copy, Paste, Duplicate, Delete, **Group / Ungroup**, **Lock / Unlock** (and Unlock All), Bring to Front, Send to Back, Move to Layer ▸, Align ▸ and Edit Text / Edit Points / Edit Label depending on the object. On empty canvas it offers Paste, Select All and Unlock All. The same commands are in the Edit and Arrange menus (Lock ⌘L, Unlock ⌥⌘L, Group ⌘G, Ungroup ⇧⌘G).
- **Per-object locking:** a locked object stays visible and can be selected (so you can unlock it) and restyled, but it can't be moved, resized, rotated, deleted, aligned or have its text or points edited, and it shows no handles; a padlock marks it. Pasting or duplicating creates unlocked copies. It is independent of layer locking.
- **Color presets in Fill:** six large grays and six hues (2 × 2 shades, from saturated to pale). With a solid fill they apply the color; with a gradient, to the selected stop. The one that matches the current color is highlighted.
- **Pen (`P`) for Bézier curves:** click = corner point; click and drag = smooth point with symmetric handles. Close the path by clicking the first point (it grows as you approach) and finish with Return, double-click or Esc; Delete removes the last point. Switching tools keeps what you drew. The result is a *path* shape (it rotates, resizes, exports to SVG and is saved like any other).
  **Point editing:** double-click a path (or press Return with the path selected) to show its anchors. Dragging an anchor moves it along with its handles; dragging a handle reshapes the curve (on a smooth point the opposite handle stays aligned; Option releases it); double-clicking an anchor toggles smooth/corner; double-clicking the line adds a point without changing the curve; Delete removes the selected point; Esc exits. Every change is an undo step. Paths with several subpaths (from an imported SVG) can't be edited point by point.
- **Resize several shapes as one unit:** with two or more shapes selected (or a group), a box with 8 handles appears and scales everything together. Shift on a corner keeps the proportions. Shapes rotated by 90° swap the axis that scales their size; at other angles they scale evenly, because a rotated shape can't be skewed.
- Zoom (pinch, ⌘+ / ⌘-, ⌘0), **rulers** in points (View → Show Rulers, ⌘R, remembered between sessions), save/open (`.graf`, readable JSON) and export to PNG, PDF and **SVG** (⌥⌘E).
  The SVG keeps multi-stop gradients, line patterns, shadows, rotation, text with line breaks, connectors with arrowheads and labels, and every visible layer as a `<g>`; hidden layers are not exported.
- **SVG import:** *File → Open…* opens an `.svg` as a new document, and *Import SVG…* (⇧⌘I) adds it to the current document as a new layer, grouped, near the visible corner of the canvas (a single undo step).
  It reads `rect` (with rounded corners), `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path` (M L H V C S Q T A Z, absolute and relative), `text`/`tspan`, nested groups with transforms, `viewBox`, `fill`/`stroke` by attribute or `style=""`, linear and radial gradients with any number of stops, dash patterns, opacity and shadows (`feDropShadow`). Diamonds and triangles are recognized as native shapes; rectangles, ellipses and text keep their rotation. Lines and curves become *path* shapes: you can select them by clicking on the stroke, and move, rotate and resize them.
  Limitations: images, `<use>`, patterns, `clipPath`, masks, `<style>` blocks (CSS) and filters other than a shadow are skipped, and you are told how many; dashes use the closest preset pattern; text arrives as loose text boxes (not inside the shape); connectors from an SVG exported by the app come back as strokes not attached to the shapes.

The inspector on the right is a single column of collapsible sections (**Fill, Line, Shadow, Object, Text, Connector**) with the **Layers** panel always visible at the bottom. Only what the selection needs is shown: **Text** with shapes or connectors selected (connectors carry a label), **Connector** only with connectors, and **Fill** is hidden when only connectors are selected. With nothing selected, changes define how new objects are created. The menus for line pattern, cap, join, connector type, arrowheads, fill type and text alignment show drawings instead of words (the name appears as a tooltip), and the font list shows each name in its own typeface. The **Shadow** controls appear only while the shadow is on. Each slider has a field to its right where you can type the exact value (clamped to the range; opacity is typed as %), and all the drop-downs are the same width.

## Icon and credits

- The app icon is `Assets/AppIcon.icns`, generated from `Assets/AppIcon-source.jpg` with `./scripts/make-icon.sh` (it places the artwork on a rounded tile with the margin and shadow of macOS icons, at the 10 sizes the system asks for). `./scripts/bundle.sh` copies it into the `.app` and declares it in `Info.plist`.
- *Graffle → About Graffle* shows the icon, the version and the credits: Graffle was designed and developed by **EVM** ([evm.mx](https://evm.mx), linked in the panel), and the copyright © 2026 EVM, released under the MIT License (the `LICENSE` file has the full text).

## Tool shortcuts

`V` select · `R` rectangle · `U` rounded · `E` ellipse · `D` diamond · `G` triangle · `T` text · `C` connector · `P` pen · `Esc` back to select.
Double-click a shape or connector to edit its text.

## Development tests

To follow the Quick Look extension while previewing a file: `qlmanage -p some.graf`, then `/usr/bin/log show --last 2m --info --predicate 'subsystem == "mx.graffle.app.quicklook"'` (use `/usr/bin/log`: in zsh, plain `log` is a different command). `pluginkit -m -p com.apple.quicklook.preview -vv | grep -i graffle` shows whether macOS has registered it.

```bash
.build/debug/Graffle --selftest                    # simulates mouse/keyboard on the canvas
build/Graffle.app/Contents/MacOS/Graffle --selftest  # the same, plus the multi-document tests (they need the .app's Info.plist)
.build/debug/Graffle --render-sample out.png       # renders a sample diagram (also .svg, .selected.png, ...)
.build/debug/Graffle --svg-to-png in.svg out.png   # rasterizes an SVG with WebKit to compare it with the canvas
.build/debug/Graffle --import-to-png in.svg out.png # imports an SVG into the canvas and exports it to PNG
```

## Pending (ideas)

Pages, and orthogonal routing that avoids obstacles.
