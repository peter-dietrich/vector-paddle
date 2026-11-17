# Vector Paddle — Fun City Arcade

Native macOS arcade paddle game, inspired by the early-1970s and 1980s two-paddle genre. **v0.1.0 (build 1)**. Both cabinets are original implementations, sharing the same physics and macOS app.

## Two cabinets

**Classic** is stark black-and-white paddle tennis: sharp-angle rebounds based on where the ball hits, a center dash line, no upgrades and a first-to-11 match by default.

**Modern** is a fully drawn neon-tech arena with bright solid paddles, illuminated rails, ball trails and arena pickups. Four modern-only pickups: **WIDE** grows the last hitter's paddle; **SPLIT** creates a second ball (maximum three); **SLOW** dilates ball speed temporarily; **BOOST** accelerates play temporarily. Both modes offer the same scoring and difficulty configuration.

## Standard Fun City features

- Classic and Modern cabinet choice, **Cadet / Veteran / Ace** CPU difficulty, local 1-player or 2-player mode.
- Version string in the banner; `MARKETING_VERSION=0.1.0`, `CURRENT_PROJECT_VERSION=1`.
- Custom Game: winning points (5/7/11/15/21), ball speed, paddle size, mouse steering, power-ups, sound effects, enhanced effects, reduced flashes.
- Save, recall and delete **five** independent game slots; resumed games reopen **paused**.
- Save and reload named **Custom Game** setups separately from matches.
- Arcade-point scoring (rallies, returns, points, match wins), independent Classic/Modern personal bests and **three-letter initials** after new records.
- Aggregate Fun City high-score keys (`VectorPaddle.HighScore.v1` and `VectorPaddle.Initials.v1`) saved in bundle `io.vectorpaddle.game`.
- App preferences and saves stored locally with UserDefaults. No cloud connection or external dependencies.

## Open in Xcode

Clone or extract this folder, then:

```bash
cd ~/Documents/GitHub/vector-paddle
open VectorPaddle.xcodeproj
```

Choose the **VectorPaddle** scheme, **My Mac**, then press **Command-R**.

Build from the macOS Terminal:

```bash
xcodebuild -project VectorPaddle.xcodeproj -scheme VectorPaddle -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
./scripts/test-engine.sh
```

Minimum macOS target: **14.0**. Project includes a shared Xcode scheme and GitHub Actions macOS build workflow.

## Controls

| Key | Function |
| --- | --- |
| W / S | Player 1 up / down |
| ↑ / ↓ | Player 2 up / down in Local 2 Player |
| Mouse movement in arena | Player 1 steering when enabled under Custom Game |
| Return / Space | Start match / start a rematch / resume |
| P | Pause / resume |
| R | Reset / new match |

## Fun City integration

Bundle ID: `io.vectorpaddle.game`. The launcher can locate and launch `VectorPaddle.app`. A new catalog entry and aggregate-high-score specification must be added to the `fun-city` project when this repository is published. Launcher distribution as an installable download also needs a signed release asset, not included here.

## Testing status

The gameplay engine has passed a real Swift compiler smoke test (initial serve, scoring, Classic and Modern, pause and Codable save/restore). **The macOS SwiftUI app has not yet been built in Xcode or play-tested on a Mac**; the bundled workflow will check this when the project is uploaded to GitHub. This is the first playable development candidate, not a signed release.

## Attribution

Original code and artwork are procedural/SwiftUI-drawn. No Pong trademark or licensed graphics are included in the in-game branding.