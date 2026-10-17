# Graffle

Editor de diagramas nativo para macOS (Swift + AppKit), inspirado en OmniGraffle.

## Compilar y ejecutar

```bash
./scripts/bundle.sh        # genera build/Graffle.app
open build/Graffle.app
```

Solo requiere las Command Line Tools (o Xcode) y macOS 13+. También: `swift run`.

### Instalador (.dmg)

```bash
./scripts/make-dmg.sh      # genera build/Graffle-<versión>.dmg y su .sha256
```

Al abrir el DMG aparece una ventana con la app, el acceso directo a *Applications* y un fondo que indica arrastrar una sobre la otra; el volumen lleva el ícono de Graffle. El script compila la app, arma la imagen, aplica el layout con Finder (si macOS no da permiso de Automatización a Finder, el DMG se genera igual pero sin la ventana personalizada), la comprime y **la monta para verificarla** (app firmada, enlace a Applications, fondo, ícono del volumen y layout). La app va firmada ad hoc y no notarizada: en otro Mac, la primera vez hay que abrirla con clic derecho → Abrir.

## Qué incluye

- **Multidocumento:** puedes tener abiertos todos los diagramas que quieras, cada uno en su propia ventana con su lienzo, inspector, paleta, deshacer y estado de "editado" independientes. File → New abre otro; Open… y Open Recent abren archivos `.graf` (también con doble clic en Finder o arrastrándolos al Dock; abrir uno que ya está abierto trae su ventana en vez de duplicarlo). Save, Save As y Revert to Saved, y al cerrar una ventana (o salir) con cambios sin guardar pregunta Save / Don’t Save / Cancel. Los `.svg` también se abren como un diagrama nuevo sin guardar, con el nombre del archivo. Las ventanas siguen la preferencia del sistema *Prefer tabs when opening documents*; en el menú Window hay Show Tab Bar, Merge All Windows y Move Tab to New Window.

- **Formas:** rectángulo, rectángulo redondeado, elipse, rombo, triángulo y texto libre.
- **Relleno:** ninguno, color sólido, gradiente lineal (con ángulo) y gradiente radial, con **cualquier número de paradas** de color. En el editor de gradiente: clic en la barra añade una parada, arrastrar un marcador la mueve (Shift = pasos de 5%), Supr la quita, y hay controles de color, posición e invertir.
- **Línea:** color, grosor, patrón (sólido, guiones, guiones largos, punteado, guion-punto), terminación (butt/round/square) y unión de esquinas (miter/round/bevel).
- **Sombra** con color, ángulo, desenfoque y distancia; **opacidad**; **radio de esquina**.
- **Texto:** fuente, tamaño, negrita, cursiva, subrayado, alineación horizontal y vertical, color (o automático según el contraste con el relleno).
- **Conectores** anclados a las formas: recto, curvo, ortogonal y ortogonal redondeado; 9 tipos de punta (flecha, flecha abierta, triángulo hueco, rombo, círculo, barra…) independientes en cada extremo, con tamaño ajustable y etiqueta.
- **Capas:** crear, borrar, reordenar, renombrar, mostrar/ocultar y bloquear; capa activa para objetos nuevos; mover la selección a otra capa. Las capas ocultas tampoco salen en la exportación.
- **Rotación** con el tirador circular sobre la forma (Shift = pasos de 15°) o con el dial Rotation del inspector. Los ángulos del inspector (rotación, sombra, gradiente lineal) son diales redondos: se arrastra la aguja (Shift = pasos de 15°) o se escribe el valor en el campo. Los conectores, la sombra y el redimensionado respetan el ángulo.
- **Grupos:** ⌘G agrupa la selección, ⇧⌘G la separa. Un clic selecciona todo el grupo y se mueve junto; copiar/pegar crea un grupo nuevo.
- Selección múltiple, mover, redimensionar con handles, flechas de teclado (Shift = 10 pt), rejilla con snap.
- Deshacer/rehacer (los cambios continuos de sliders y paneles de color se fusionan en un solo paso), cortar/copiar/pegar, duplicar, traer al frente / enviar al fondo, alinear.
- **Distribuir con espaciado igual** (Arrange → Distribute Horizontally / Vertically, o el menú contextual): con tres o más formas, las de los extremos se quedan donde están y las de en medio se reparten para que los huecos sean iguales. Las formas bloqueadas no se mueven.
- **Igualar tamaños** (Arrange → Same Width / Same Height / Same Size): todas las formas seleccionadas toman el ancho, el alto o ambos de la **primera que seleccionaste** (con una selección por área o Select All, la de más atrás). Cada una conserva su esquina superior izquierda; las bloqueadas no cambian.
- **Guías inteligentes** (al mover, al redimensionar y al crear formas): los bordes y el centro de lo que arrastras se imantan (a menos de 6 pt) a los de las demás formas, y aparece una línea guía magenta mientras estén alineados; también se imanta borde con borde.
  - *Al mover:* con varias formas seleccionadas se mueven como una caja.
  - *Al redimensionar:* el borde que arrastras se imanta (una forma, o varias a la vez como un grupo). Las formas giradas no se imantan, porque sus bordes no siguen los ejes.
  - *Al crear:* se imantan tanto la esquina donde empiezas como la que arrastras.
  - **Guías de espaciado igual (al mover):** si la forma queda a la misma distancia de sus dos vecinas, o a la misma distancia que ya hay entre otras dos formas de la misma fila o columna, se imanta y se dibujan corchetes con la medida del hueco (p. ej. "85") sobre todos los huecos iguales. Solo cuentan las formas de la misma fila (para el espaciado horizontal) o columna (vertical).
  Se apagan en View → Smart Guides (se recuerda) o manteniendo Opción mientras se arrastra.
- **Copiar y pegar estilo** (Edit → Copy Style ⌥⌘C / Paste Style ⌥⌘V, y en el menú contextual): lleva todo el aspecto (relleno, línea, sombra, opacidad, esquinas, formato de texto) de un objeto a otros, no su geometría ni su texto. Funciona con varios objetos a la vez, también sobre objetos bloqueados, y es un solo paso de deshacer. El relleno y las esquinas solo viajan entre formas: pegar el estilo de un conector no borra el relleno de una forma, y un conector nunca recibe relleno. Sin selección, "Paste Style" fija el aspecto de los objetos nuevos.
- **Paleta de estilos reutilizables** (sección *Styles* del inspector): miniaturas que muestran el aspecto real (degradado, sombra, línea punteada, o "Aa" en los estilos solo de texto). Un clic aplica el estilo a la selección (o a los objetos nuevos si no hay selección); el botón **+** guarda el estilo del objeto seleccionado con el nombre que elijas; clic derecho en una miniatura: Apply, Rename…, Update from Selection y Delete. La paleta se guarda en las preferencias de la app y sirve para cualquier documento; la primera vez trae siete estilos iniciales (si luego los borras todos, no vuelven).
- **Fuentes:** el selector de fuente lista todas las familias instaladas en el equipo (cada nombre en su propia tipografía). Si un documento usa una fuente que no está instalada, aparece marcada como "(not installed)" en vez de mostrar otra por error.
- **Menú contextual (clic derecho):** sobre un objeto lo selecciona (con todo su grupo si lo tiene) y ofrece Cut, Copy, Paste, Duplicate, Delete, **Group / Ungroup**, **Lock / Unlock** (y Unlock All), Bring to Front, Send to Back, Move to Layer ▸, Align ▸ y Edit Text / Edit Points / Edit Label según el objeto. Sobre el lienzo vacío ofrece Paste, Select All y Unlock All. Los mismos comandos están en el menú Edit y Arrange (Lock ⌘L, Unlock ⌥⌘L, Group ⌘G, Ungroup ⇧⌘G).
- **Bloqueo por objeto:** un objeto bloqueado sigue visible y se puede seleccionar (para poder desbloquearlo) y cambiar de estilo, pero no se puede mover, redimensionar, rotar, borrar, alinear ni editar su texto o puntos, y no muestra handles; se indica con un candado. Pegar o duplicar crea copias desbloqueadas. Es independiente del bloqueo de capas.
- **Colores predefinidos en Fill:** seis grises grandes y seis matices (2 × 2 tonos, del saturado al claro). Con relleno sólido aplican el color; con gradiente, a la parada seleccionada. El que coincide con el color actual se resalta.
- **Pluma (`P`) para curvas Bézier:** clic = punto de esquina; clic y arrastrar = punto suave con manijas simétricas. Se cierra haciendo clic en el primer punto (se agranda al acercarse) y se termina con Return, doble clic o Esc; Supr quita el último punto. Cambiar de herramienta conserva lo dibujado. El resultado es una forma de tipo *path* (se rota, redimensiona, exporta a SVG y se guarda como cualquier otra).
  **Edición de puntos:** doble clic sobre un trazo (o Return con el trazo seleccionado) muestra sus anclas. Arrastrar un ancla la mueve con sus manijas; arrastrar una manija reorienta la curva (en un punto suave la manija opuesta se alinea; Opción la suelta); doble clic en un ancla alterna suave/esquina; doble clic sobre la línea añade un punto sin cambiar la curva; Supr borra el punto seleccionado; Esc sale. Cada cambio es un paso de deshacer. Los trazos con varios subtrazos (de un SVG importado) no se pueden editar punto a punto.
- **Redimensionar varias formas como una unidad:** con dos o más formas seleccionadas (o un grupo) aparece una caja con 8 handles que escala todo junto. Shift en una esquina mantiene la proporción. Las formas giradas 90° intercambian el eje que escala su tamaño; con otros ángulos se escalan de forma pareja, porque una forma girada no se puede deformar.
- Zoom (pellizco, ⌘+ / ⌘-, ⌘0), **reglas** en puntos (View → Show Rulers, ⌘R, se recuerda entre sesiones), guardar/abrir (`.graf`, JSON legible) y exportar a PNG, PDF y **SVG** (⌥⌘E).
  El SVG conserva gradientes de varias paradas, patrones de línea, sombras, rotación, texto con saltos de línea, conectores con puntas y etiquetas, y cada capa visible como un `<g>`; las capas ocultas no se exportan.
- **Importar SVG:** *File → Open…* abre un `.svg` como documento nuevo, e *Import SVG…* (⇧⌘I) lo añade al documento actual como una capa nueva, agrupado, junto a la esquina visible del lienzo (un solo paso de deshacer).
  Lee `rect` (con esquinas redondeadas), `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path` (M L H V C S Q T A Z, absolutos y relativos), `text`/`tspan`, grupos anidados con transformaciones, `viewBox`, `fill`/`stroke` por atributo o `style=""`, gradientes lineales y radiales con cualquier número de paradas, patrones de guiones, opacidad y sombras (`feDropShadow`). Los rombos y triángulos se reconocen como formas nativas; rectángulos, elipses y texto conservan la rotación. Las líneas y curvas se vuelven formas de tipo *path*: se pueden seleccionar haciendo clic sobre el trazo, mover, rotar y redimensionar.
  Limitaciones: imágenes, `<use>`, patrones, `clipPath`, máscaras, bloques `<style>` (CSS) y filtros que no sean una sombra se omiten y se avisa de cuántos; los guiones usan el patrón predefinido más cercano; el texto entra como cajas de texto sueltas (no dentro de la forma); los conectores de un SVG exportado por la app vuelven como trazos sin conexión a las formas.

El inspector de la derecha es una sola columna de secciones colapsables (**Fill, Line, Shadow, Object, Text, Connector**) con el panel de **Layers** siempre visible al pie. Solo aparece lo que la selección necesita: **Text** con formas o conectores seleccionados (los conectores llevan etiqueta), **Connector** solo con conectores, y **Fill** no se muestra si solo hay conectores. Sin selección, los cambios definen cómo se crean los objetos nuevos. Los menús de patrón de línea, terminación, unión, tipo de conector, puntas de flecha, tipo de relleno y alineación de texto muestran dibujos en lugar de palabras (el nombre sale como tooltip) y la lista de fuentes muestra cada nombre en su propia tipografía. Los controles de **Shadow** solo aparecen mientras la sombra está activada. Cada slider lleva a su derecha un campo donde escribir el valor exacto (se ajusta al rango; la opacidad se escribe en %), y todos los desplegables miden lo mismo.

## Ícono y créditos

- El ícono de la app está en `Assets/AppIcon.icns`, generado a partir de `Assets/AppIcon-source.jpg` con `./scripts/make-icon.sh` (coloca la ilustración en una tarjeta redondeada con el margen y la sombra de los íconos de macOS, en los 10 tamaños que pide el sistema). `./scripts/bundle.sh` lo copia a la `.app` y lo declara en el `Info.plist`.
- *Graffle → About Graffle* muestra el ícono, la versión y los créditos: Graffle fue diseñada y desarrollada por **EVM** ([evm.mx](https://evm.mx), con enlace en el panel), y el copyright © 2026 EVM.

## Atajos de herramienta

`V` seleccionar · `R` rectángulo · `U` redondeado · `E` elipse · `D` rombo · `G` triángulo · `T` texto · `C` conector · `Esc` volver a seleccionar.
Doble clic en una forma o conector edita su texto.

## Pruebas de desarrollo

```bash
.build/debug/Graffle --selftest                    # simula ratón/teclado sobre el canvas
build/Graffle.app/Contents/MacOS/Graffle --selftest  # lo mismo, y además las pruebas de multidocumento (necesitan el Info.plist de la .app)
.build/debug/Graffle --render-sample salida.png    # renderiza un diagrama de muestra (también .svg, .selected.png, ...)
.build/debug/Graffle --svg-to-png in.svg out.png   # rasteriza un SVG con WebKit para compararlo con el canvas
.build/debug/Graffle --import-to-png in.svg out.png # importa un SVG al canvas y lo exporta a PNG
```

## Pendiente (ideas)

Páginas, curvas Bézier (herramienta pluma), snapping inteligente con guías,
ruteo ortogonal que esquive obstáculos, documentos con `NSDocument`.
