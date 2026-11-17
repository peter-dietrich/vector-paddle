# Development notes

The core game engine is isolated in `Sources/PaddleEngine.swift` and uses Foundation only so smoke tests run without macOS. The SwiftUI app owns keyboard events, personal records, named presets, five snapshot slots and synthesized sounds. The playfield uses the same physics coordinates for Classic and Modern modes.

Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` together in Debug and Release in the Xcode project; the UI reads both. Do not introduce temporary Beta branding.

## Mac validation

- Build Debug and Release in Xcode.
- Test Classic against each CPU skill, score to 11.
- Test Modern pickups, split balls, paddle and wall collisions.
- Test W/S, arrows with two players, key release, optional mouse steering.
- Save mid-rally, close and reopen, restore paused and resume.
- Create/load/delete saved setups independently of save slots.
- Finish a record run, submit initials, reopen and verify persistence.
- Verify sound toggle and reduced flashes.
- Confirm bundle identifier `io.vectorpaddle.game`.

All art and synthesized audio is original. Do not import Pong trademarks or proprietary assets into the shipped game.
