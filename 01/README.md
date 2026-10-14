# UI Sci-Fi programs (Lazarus + BGRABitmap)

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
| **`SciFiHUDKit`** | **All UIs above on one canvas, laid out like the original design** |
| **`HUDSystemMonitor`** | **Live dashboard: CPU, memory, disk C:, network, processes, uptime, alerts** |
| **`HUDDesigner`** | **Layout editor: add / drag / tune widgets, save `.hud`, export a Pascal unit** |
| **`HUDRadarDefense`** | **Game: aim with the mouse, shoot the drones before they reach the core** |
| **`HUDChart`** | **Charts: KPI tiles, line, donut and column charts; CSV, live data, hover tooltips** |
| **`HUDClock`** | **Analog + digital clock, calendar, world clocks, day/week/month/year progress** |
| **`HUDFileBrowser`** | **Places, drives, folder listing, details and image/text preview; double-click opens** |
| **`HUDNote`** | **Notes: search, list, editor with autosave, word/character/line counters** |
| **`HUDMediaPlayer`** | **Audio player (MCI): playlist, transport, seek, volume, ID3 tags, drag & drop** |
| **`HUDCalculator`** | **Scientific calculator: parser with precedence, functions, memory, DEG/RAD, history** |
| **`HUDWeather`** | **Weather (Open-Meteo): current, wind, sun, next 24 h, 7 days; city search** |
| **`HUDTranslator`** | **Translator (MyMemory): language bar, source / translation panels, history** |

`SciFiHUDKit` (in the `SciFiHUDKit/` folder) contains no drawing code of its own:
it hosts the same widget classes as the single programs (`THUDComposite`), so a
change in a widget unit shows up in both. Click a UI in its view, or pick it in
the list above the tabs, to inspect and tune that UI; "Whole kit" shows the
canvas itself (layout table in its Anatomy tab).

`HUDSystemMonitor` drives the kit's widgets with live Windows data
(`HUDSystemMonitor/usysmonitor.pas`: GetSystemTimes, GlobalMemoryStatusEx,
DiskFree, GetIfTable, EnumProcesses). Its Anatomy tab lists which value drives
which gauge; sampling interval, smoothing and alert thresholds are parameters.

`HUDDesigner` edits a canvas of kit widgets: pick a widget in the toolbar and
click Add, click to select, drag to move (snaps to the grid), Del / Ctrl+D /
arrow keys, and tune the selected widget in the Parameters tab (loaders have a
"Label text" parameter). Layouts are saved as `.hud` (INI text) in
`HUDDesigner/layouts`. "Export Pascal" writes a `THUDComposite` unit that builds
the same screen; add it to `KITS` in `tools/make_projects.py` to make it a
program. `HUDDesigner.exe --selftest <dir>` checks save / load / export.

`HUDRadarDefense` is an arcade game on the same engine: left-click fires at the
crosshair (needs a LOCK on a drone), every shot costs energy, drones that reach
the core drain the shield. The side HUD (energy, shield, wave, combo, alerts,
score panel) is made of kit widgets driven by the game. Space pauses; the best
score is kept in `highscore.txt`. Parameters: Difficulty, Energy per shot,
Autopilot (a bot plays: demo mode).

`HUDChart` draws data in the HUD style: KPI tiles (value, change vs the previous
row, sparkline), a multi-series line chart, a donut of each series' share and a
column chart of the total per row. Hover any chart for a tooltip; the data
table is in the Live tab. Toolbar: Open CSV (samples in `HUDChart/samples`),
Sample data, Live data on/off; `HUDChart.exe --csv file.csv` starts with a CSV.
CSV = header row (x title, series names) + one row per category; `,` `;` or TAB;
more than 6 series fold into "Other". Series colours are a fixed, validated
categorical order (series i = slot i).

Application programs (`HUDClock`, `HUDFileBrowser`, `HUDNote`, `HUDMediaPlayer`)
use `shared/hudpanels.pas`: `TFrameWidget`, the HUD list `THUDListWidget`, and
`PlaceControl` / `StyleControl`, which put a real LCL control (the note editor,
the search box) exactly over a HUD frame at any window size.

- HUDNote keeps notes as UTF-8 `.txt` files in `HUDNote/notes` (autosave 1 s
  after typing). Ctrl+N new, Ctrl+S save, Ctrl+F search, Ctrl+Del delete.
- HUDMediaPlayer plays mp3 / wav / wma / m4a / aac through Windows MCI; the
  spectrum is a decorative animation (MCI exposes no audio samples). Space
  play/pause, arrows seek / volume, PgUp/PgDn tracks; `--play <files|folder>`.
- HUDFileBrowser opens files with their default program (double-click / Enter);
  `--path <folder>` starts in a folder.
- HUDCalculator: type or click; Enter evaluates, Backspace deletes, Del/Esc
  clears, Ctrl+C copies the result, D toggles DEG/RAD, P inserts pi. History
  rows reload their expression. `--eval "expr"` (repeatable) evaluates at start.
  The engine (`ucalcengine.pas`) handles precedence, right-associative `^`,
  implicit multiplication (2pi, 3(4+1)) and readable error messages.
- HUDWeather gets data from Open-Meteo (free, no API key, CC BY 4.0) over HTTPS
  with WinINet in a background thread; city lookup by name, refresh every 15
  minutes, last city in `weather.ini`. The city box and SEARCH / REFRESH buttons
  are a HUD location panel at the top (Enter searches, Esc cancels the edit). With no connection and no data yet it
  shows labelled DEMO values. `--city "Tokyo"` picks the city at start.
- HUDTranslator uses MyMemory (free, no key, about 5000 characters a day for
  anonymous use; text is sent to mymemory.translated.net). Text over 500 bytes
  is split at sentence boundaries. Ctrl+Enter translates, Ctrl+Shift+S swaps;
  history in `translator_history.txt`. `--text "..." --from en --to th`.
  `shared/hudnet.pas` holds the WinINet HTTP helper and a fix for FPC 3.2.2's
  fpjson, which corrupts runs of `\uXXXX` escapes (decoded before parsing).
- HUDClock world clocks list cities without daylight saving, so their fixed
  UTC offsets are always right.

## Layout

```
shared/hudcore.pas    render engine + THUDWidget base class (primitives, glow,
                      static cache, dirty rects, thread pool, parameters)
shared/hudhost.pas    window, HUD view and the info panel (all programs)
<Program>/            <Program>.lpi / .lpr + u<program>.pas (the UI itself)
SciFiHUDKit/          the composite kit (uscifihudkit.pas = layout only)
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

## Adding a UI to the kit

Add the widget's unit to the `uses` of `SciFiHUDKit/uscifihudkit.pas` and an
`AddChild(TMyWidget.Create, originX, originY)` line in its constructor
(the kit's search path covers every program folder; run `make_projects.py`
after adding a new program so the path includes it).

## Command line

```
<Program>.exe --shot out.png [W H]   render one frame (t = 2.5 s) and quit
<Program>.exe --info out.txt         export the info panel text and quit
<Program>.exe --set "Name=Value"     preset a parameter (repeatable), e.g.
                                     HUDRadarDefense.exe --set "Autopilot=1"
```
