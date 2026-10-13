# Sci-Fi HUD programs (Lazarus + BGRABitmap)

One program per UI from the original HUD kit. Every program opens a window
with the live, animated UI on the left and a developer info panel on the right.

| Program | UI |
|---|---|
| `OpticScanner` | Large scanner with glowing lens shells, rotating arcs and band |
| `TargetLock` | Lock-on reticle with wings, tick ring, dotted ring |
| `ShieldCore` | Armoured ring with 4 rotating arc plates and a pulsing core |
| `HUDIconSet` | Corner brackets, frame shapes, warning triangles (optional blink) |
| `DataFrames` | 4 chamfered info panels (scan line, dot grid, target frame, status) |
| `RadarSweep` | Radar scope with sweep trail and contacts, 2 frame styles |
| `HexCore` | Hexagonal cube with corner chevrons and a pulsing core |
| `TargetCrosshair` | Aiming reticle with a rotating sector |
| `ChevronLoader` | Gauge + arrow bar of chevrons |
| `PillLoader` | Dotted gauge + rounded gradient bar |
| `BlockLoader` | Tick gauge + row of blocks |
| `SlantLoader` | Thick ring gauge + slanted wedge bar |

## Layout

```
shared/hudcore.pas    render engine + THUDWidget base class (primitives, glow,
                      static cache, dirty rects, thread pool, parameters)
shared/hudhost.pas    window, HUD view and the info panel (all programs)
<Program>/            <Program>.lpi / .lpr + u<program>.pas (the UI itself)
tools/make_projects.py  regenerates every .lpi/.lpr (add new programs here)
build_all.cmd         builds every program in Release mode
```

## Info panel

- **Overview**: names, files, design size, coordinate system, render pipeline,
  how to extend the UI, keys and command-line options.
- **Parameters**: live-editable values (speeds, styles, content, glow, zoom).
  Select a row to see its description and range; values marked "rebuilds the
  static cache" redraw the static part.
- **Anatomy**: every element with its geometry, color and whether it is
  static or animated.
- **Palette**: shared colors with hex values and usage.
- **Live**: fps, ms per render stage, scale, dirty rects and current animation
  state. Updates 4 times per second.

Buttons: Pause, Screenshot (PNG next to the exe), Export info (txt + clipboard),
Reset params, Show dirty rects, 60 fps cap.

## Adding a new UI

1. Copy a widget unit (e.g. `HexCore/uhexcore.pas`) to a new folder and rename
   the class.
2. Add a line to `PROGRAMS` in `tools/make_projects.py` and run it.
3. Implement `DrawStatic`, `DrawDynamic`, `DefineDirty` (must cover everything
   drawn in `DrawDynamic`), `DescribeAnatomy`, and register parameters in the
   constructor with `AddParam`.

## Command line

```
<Program>.exe --shot out.png [W H]   render one frame (t = 2.5 s) and quit
<Program>.exe --info out.txt         export the info panel text and quit
```
