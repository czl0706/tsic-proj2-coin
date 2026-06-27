# HDMI Coin

Tang Nano 4K HDMI coin-catching game implemented in Verilog.

Open this repository with `hdmi_coin` as the project root. The design keeps button input, game logic, render layers, and HDMI output separated so each part can be developed and explained independently.

## Pipeline

```text
top
  -> reset_sync
  -> ff_sync
  -> debounce
  -> game_core
       -> game_ctrl
       -> bg_layer
       -> obj_layer
       -> ui_layer
  -> svo_hdmi
       -> svo_enc
       -> svo_tmds
       -> OSER10 / ELVDS_OBUF
       -> HDMI
```

`game_core` produces one AXIS-like pixel stream. `svo_hdmi` only consumes that stream and drives the HDMI pins.

## Directory Structure

```text
hdmi_coin/
|-- README.md
|-- hdmi_coin.gprj
|-- skills/
|   |-- double_score.md
|   |-- gambler.md
|   |-- invincible_1.md
|   |-- invincible_2.md
|   |-- magnet.md
|   |-- fs/
|   |-- patches/
|   |-- run_all_patches.ps1
|   |-- speed_boost.md
|   `-- star_rain.md
|-- .vscode/
|   |-- launch.json
|   |-- tasks.json
|   |-- run.ps1
|   `-- png2mem.ps1
|-- png/
`-- src/
    |-- top.v
    |-- hdmi_coin.cst
    |-- hdmi_coin.sdc
    |-- common/
    |   |-- debounce.v
    |   |-- ff_sync.v
    |   |-- fifo.v
    |   |-- lfsr32.v
    |   |-- reset_sync.v
    |   `-- rom.v
    |-- game/
    |   |-- game_core.v
    |   |-- game_ctrl.v
    |   |-- skill_slot.v
    |   |-- spawn_postprocess.v
    |   `-- spawn_queue.v
    |-- overlay/
    |   |-- bg_layer.v
    |   |-- obj_layer.v
    |   `-- ui_layer.v
    |-- hdmi/
    |   |-- svo_defines.vh
    |   |-- svo_enc.v
    |   |-- svo_hdmi.v
    |   `-- svo_tmds.v
    |-- ip/
    |   |-- gowin_clkdiv.v
    |   `-- gowin_pllvr.v
    `-- assets/
        |-- background.mem
        |-- objects/
        `-- player/
```

## Video Spec

- Output mode: `640x480V`
- Resolution: 640 x 480
- Frame rate: 60 Hz
- Internal stream: AXIS-like valid/ready/data/user
- Stream pixel format: 24-bit BGR888
- ROM asset format: RGB565 `.mem`

The stream interface between `game_core` and `svo_hdmi` is:

```verilog
output        out_axis_tvalid;
input         out_axis_tready;
output [23:0] out_axis_tdata;
output [0:0]  out_axis_tuser;
```

`tuser[0]` marks the first pixel of a frame.

## Controls

Board buttons are active-low at the physical pin and become active-high pressed levels inside the game.

```text
btn_left   pin 13
btn_right  pin 17
btn_start  pin 18
btn_skill  pin 16
```

Input path:

```text
raw active-low button
  -> ff_sync
  -> debounce
  -> active-high stable level
  -> game_core / game_ctrl / ui_layer
```

`ff_sync` is a two-flop synchronizer. `debounce` is counter-based: the output changes only after the synchronized input stays different for `DEBOUNCE_CYCLES`.

## Game Spec

### States

Current game states in `game_ctrl`:

```text
1: playing
2: game over
```

Reset starts directly in `playing`. State value `0` is currently unused.
The state register stays inside `game_ctrl`; render layers only receive the simpler `game_over` signal.

`btn_start` restarts the game:

- player returns to the center
- timer resets
- score resets
- active objects are cleared
- state returns to playing

### Timer and Score

- `timer` starts from `TIMER_START`, currently 120 seconds.
- `timer` decreases once every 60 frame ticks.
- When `timer` reaches 0, the game enters game over.
- `score` is displayed as 4 digits.
- `high_score` updates only when the game enters game over.
- `+time` objects add `TIME_BONUS`, currently 3 seconds.
- `charge` objects add 1 skill charge, up to `SKILL_CHARGE_MAX`, currently 5.
- In the base branch, `btn_skill` is wired but does not trigger a gameplay effect.
- `skill_slot` owns the common skill lifecycle: button edge detect, charge check, timer countdown, `skill_on`, and `skill_start`.
- In the base branch, `SKILL_ENABLE = 0`, so `skill_slot` does not start or consume charge.
- Skill patches enable the slot and connect one gameplay effect through existing hook points.

Object effects:

```text
type 0: +1
type 1: +3
type 2: +5
type 3: -3
type 4: -5
type 5: +time
type 6: charge
```

Negative score clamps at 0.

### Player

- Display size: 64 x 64
- Source sprite size: 32 x 32
- Scaling: 2x pixel replication
- Initial x: 288
- Fixed y: 352
- Movement: left / right only
- Default speed: 8 px/frame
- Skill patches can change the movement block locally.
- Facing direction selects left or right sprite

Player assets:

```text
src/assets/player_left1_32.mem
src/assets/player_right1_32.mem
```

### Objects

- Maximum active objects: 16
- Display size: 32 x 32
- Source sprite size: 16 x 16
- Scaling: 2x pixel replication
- Default fall speed: 2 px/frame
- Default spawn period: 24 frames
- Skill patches can change the spawn counter reload locally.

Object type probability:

```text
+1      20%
+3      20%
+5      10%
-3      20%
-5      15%
+time    5%
charge  10%
```

`spawn_queue` creates raw spawn data. `spawn_postprocess` sits between `spawn_queue` and the object registers. The base version is pass-through, and skill branches can use it to remap object type or position without changing the raw queue.

Per-object state:

```text
obj_valid
obj_lane
obj_xoff
obj_ypos
obj_type
```

Coordinate formula:

```text
obj_x = 64 + obj_lane * 32 + obj_xoff
obj_ypos = stored object y pixel coordinate
```

The multi-object values are exported as packed buses:

```text
obj_valid_bus
obj_lane_bus
obj_xoff_bus
obj_ypos_bus
obj_type_bus
```

Object assets:

```text
src/assets/obj_plus1_16.mem
src/assets/obj_plus3_16.mem
src/assets/obj_plus5_16.mem
src/assets/obj_minus3_16.mem
src/assets/obj_minus5_16.mem
src/assets/obj_time_16.mem
src/assets/obj_charge_16.mem
```

## Render Layers

### `bg_layer`

Generates the base stream:

- reads `src/assets/background.mem`
- source tile is 32 x 32 RGB565
- display tile is 64 x 64 by 2x pixel replication
- repeats across the 640 x 480 screen

### `obj_layer`

Receives the background stream and overlays gameplay sprites.

Draw order:

```text
background
  -> falling objects
  -> player
```

Sprite ROM reads are synchronous, so hit flags and background pixels are delayed to match ROM latency.

### `ui_layer`

Receives the object stream and overlays the bottom 64-pixel UI.

Layout:

```text
left    timer, 3 digits
center  score, 4 digits
right   high score, 4 digits
```

Current UI behavior:

- no English labels
- left/right button indicators at screen edges
- center score blinks during game over
- skill charge bar at the bottom, 5 segments
- skill countdown timer near the charge bar, 2 small digits
- digits are logic-generated seven-segment shapes
- UI receives `game_over`; it does not depend on the internal state encoding

## Common Modules

- `reset_sync`: reset synchronizer used by `top`
- `ff_sync`: two-flop synchronizer for external asynchronous signals
- `debounce`: counter-based debounce for synchronized active-low buttons
- `rom`: synchronous ROM wrapper for RGB565 assets
- `fifo`: small synchronous FIFO used by `spawn_queue`
- `lfsr32`: pseudo-random generator for object spawn logic; `spawn_queue` uses one LFSR for position and one for type

## Skill Base

The base branch intentionally does not implement any skill. It only exposes clean hook points so each teaching branch can apply one skill patch without changing the video pipeline.

Base skill path:

```text
game_ctrl
  -> skill_slot          // common lifecycle, disabled by default
  -> spawn_queue
  -> spawn_postprocess   // pass-through shell
  -> object registers
```

`skill_slot` owns the common logic shared by every skill branch:

```text
btn_skill rising edge
charge full check
skill_timer countdown
skill_on
skill_start
charge clear trigger
```

`game_ctrl` exposes the common hack points:

```text
hit_player_l / hit_player_r / hit_player_t / hit_player_b
score_delta
player_speed
spawn_period
spawn_postprocess
```

The base branch uses these signals directly. Skill patches may introduce local effective signals such as `score_delta_eff`, `player_speed_eff`, or `spawn_period_eff` inside the patch itself.

Skill specs are stored in `skills/`, one file per skill. Apply-ready patch files are stored in `skills/patches/`.
Each patch only enables the common slot and changes the skill-specific effect.

Patch usage:

```powershell
git apply --ignore-whitespace .\skills\patches\magnet.patch
```

Each patch is intended to be applied on a fresh branch from this base. The patches are not designed to be stacked together.

```text
skills/magnet.md
skills/double_score.md
skills/speed_boost.md
skills/invincible_1.md
skills/invincible_2.md
skills/star_rain.md
skills/gambler.md

skills/patches/magnet.patch
skills/patches/double_score.patch
skills/patches/speed_boost.patch
skills/patches/invincible_1.patch
skills/patches/invincible_2.patch
skills/patches/star_rain.patch
skills/patches/gambler.patch
```

## Asset Format

All `.mem` sprite/tile assets are RGB565:

```text
one pixel token per pixel
4 hex digits per pixel
row-major order
transparent pixel = 0000
```

The render layers convert RGB565 ROM output to BGR888 for the SVO video stream.

## PNG to MEM

`.vscode/png2mem.ps1` converts all PNG files in an input folder to RGB565 `.mem` files.

Default behavior:

```text
input : png/
output: src/assets
```

Run from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.vscode\png2mem.ps1
```

Custom folders:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.vscode\png2mem.ps1 .\src\assets\objects .\src\assets\objects
```

The script only writes `.mem` files. It does not generate `assets.vh`, `assets.json`, or alpha map files.

## VS Code Tasks

Open VS Code with `hdmi_coin` as the workspace folder.

Available tasks:

```text
run      build and upload through Gowin
png2mem  convert PNG files under png/ to RGB565 MEM files in src/assets/
```

Use:

```text
Terminal -> Run Task... -> run
Terminal -> Run Task... -> png2mem
```

`run` is the default build task.

## Build and Upload

`.vscode/run.ps1` does:

1. Open `hdmi_coin.prj` if it exists, otherwise `hdmi_coin.gprj`.
2. Run Gowin build.
3. Find the generated `.fs` bitstream under `impl/pnr`.
4. Upload the bitstream with `programmer_cli`.

Expected Gowin install path in the current script:

```text
C:\Gowin\Gowin_V1.9.11.03_Education_x64
```

If your Gowin installation path is different, update `$GOWIN_HOME` in `.vscode/run.ps1`.

## Development Notes

- Keep `svo_hdmi` free of game logic.
- Add gameplay features inside `game_ctrl`.
- Add visual changes inside `bg_layer`, `obj_layer`, or `ui_layer`.
- Keep ROM assets small because Tang Nano 4K memory and LUT resources are limited.
- Prefer source sprites with power-of-two dimensions.
- Prefer pixel replication over linear interpolation for FPGA-friendly scaling.
- Treat each render layer as an independently testable stage.

## Current Implemented State

Implemented:

- 640 x 480 HDMI output
- separated `reset_sync` from `top`
- separated `game_core` and `svo_hdmi`
- background tile layer
- object layer with RGB565 object sprites
- player sprite rendering
- UI layer with timer, score, high score, and button indicators
- game controller with timer, movement, spawn queue, falling objects, collision, score, and high score update
- skill base hooks with common `skill_slot` lifecycle and pass-through `spawn_postprocess`
- button synchronization and debounce
- PNG to RGB565 MEM conversion script
- VS Code tasks for build/upload and asset conversion

Open items:

- tune spawn rate and fall speed
- tune sprite art
- decide whether to add an idle/start screen
- add more gameplay feedback if needed
- verify full Gowin synthesis/resource usage after each asset change
