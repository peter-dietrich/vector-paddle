# Vector Paddle — Fun City Arcade

Native macOS arcade game with two deliberately distinct cabinets. **v0.2.0 (build 2)**.

## Classic — original paddle tennis

Classic remains the v0.1.0 black-and-white Pong-style cabinet: two horizontal-moving-ball paddles, rallies, CPU skill settings and arcade scoring. Its original physics and original saved game slots are unchanged.

## Modern — NEON RALLY

Modern now runs its own physically simulated 3D table tennis match rendered with Apple's RealityKit. **This is a development candidate, not a finished professional table-tennis simulation.**

- Opaque table with net, sidelines, legs, illuminated perimeter and separate paddles, from a behind-the-player perspective
- 3D ball position/velocity with gravity, table bounce, net collision, spin effect and out-of-bounds detection
- A mandatory bounce on the server's half followed by a bounce on the receiver's half during service; returning after the bounce
- Move the paddle with your pointer or A/D, then click to return; select Drive, Backspin, or Smash using 1/2/3
- Space to serve and an automatic CPU serve for opponent turns
- CPU side-to-side anticipation tuned by Cadet, Veteran and Ace difficulty, with changing shot placement
- 11-point games, win by two, service alternating every two points and at deuce, best-of-three matches
- Modern-specific five match save slots that restore paused; Classic saves are kept independent
- Independent high score with three-character initials, plus current score, rallies and games in the right telemetry

**Controls in Modern:**

| Input | Function |
| --- | --- |
| Move pointer within arena | Position near-side paddle and choose cross-table aim |
| A / D | Move near-side paddle left / right |
| Click, Return | Hit the ball after it bounces on your half |
| 1 / 2 / 3 | Drive / Backspin / Smash shot |
| Space | Serve when it is your turn |
| P | Pause / resume |
| R | New game |
| Left / Right arrow | Move far-side paddle in local 2-player mode |
| Space | Second player serve during their turn |

Classic controls remain W/S and Up/Down paddles, Return/Space to start, P to pause and R to restart.

## Standard Fun City features

- Choice of Classic and Modern, Cadet/Veteran/Ace, solo or local 2-player
- Custom game presets, speed and other configuration, independent Classic and Modern save slots
- Personal best with 3-letter initials, version in game banner and Fun City bundle identifier
- Key/value preferences stored locally in UserDefaults (no backend, no imported licensed artwork)
- Bundle identifier: `io.vectorpaddle.game`
- Test script: `bash scripts/test-engine.sh`
- Xcode scheme: `VectorPaddle`

Modern defaults to table-tennis rules; the older Pong-style multiball and arena powerups are not part of Modern's default table-tennis physics. Those effects stay within the original engine, while Classic intentionally disables power-ups.

## Sync and run on your Mac

```bash
mkdir -p ~/Documents/GitHub
cd ~/Documents/GitHub
if [ -d vector-paddle/.git ]; then
  cd vector-paddle
  git switch main
  git pull --ff-only origin main
else
  git clone https://github.com/peter-dietrich/vector-paddle.git
  cd vector-paddle
fi
open VectorPaddle.xcodeproj
```

Select the VectorPaddle scheme, **My Mac**, press **Command-R**. macOS 14+.

Terminal build:

```bash
xcodebuild -project VectorPaddle.xcodeproj -scheme VectorPaddle -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
bash scripts/test-engine.sh
```

## Developer notes

- `Sources/PaddleEngine.swift` contains original Classic rules.
- `Sources/TableTennisEngine.swift` contains independent Foundation-only 3D table-tennis match rules.
- `Sources/NeonRallyArena.swift` owns RealityKit visual geometry and positioning.
- `Sources/VectorPaddleApp.swift` owns the native macOS app, scoreboards, input, persistence, presets and pause.
- `Tests/EngineSmoke.swift` includes headless engine tests, run through GitHub Actions with a native Xcode build.

GitHub is the source of truth. No local source patching or ZIP merge is needed.
