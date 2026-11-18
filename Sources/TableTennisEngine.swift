import Foundation

/// Deterministic 3D ball flight in metres. The visual scene never owns physics.
enum TableShot: String, CaseIterable, Codable { case drive, backspin, smash }
struct TableBall: Codable {
    var x: Double
    var y: Double
    var z: Double
    var vx: Double
    var vy: Double
    var vz: Double
    var sidewaysSpin: Double = 0
    var verticalSpin: Double = 0
    var lastHit: PaddleSide
    var isServe: Bool = false
    var ownServeBounce = false
    var receiverBounceCount = 0
}
struct TableRally: Codable {
    var player: Int = 0
    var opponent: Int = 0
    var playerGames: Int = 0
    var opponentGames: Int = 0
    var longestRally: Int = 0
    var currentRally: Int = 0
    var returns: Int = 0
    var pointsAwarded: Int = 0
}
struct TableMatch: Codable {
    static let tableWidth = 1.525
    static let tableHalfLength = 1.37
    static let tableHeight = 0.76
    static let ballRadius = 0.024
    static let netHeight = 0.1525
    static let gravity = 9.81
    // Move the smaller oval racket toward the back end line. Render and
    // physical contact use these shared coordinates; never resize collision
    // and visual geometry independently.
    static let paddleContactZ = 1.22
    static let paddleCenterY = 0.99
    static let paddleHalfWidth = 0.127
    static let paddleHalfHeight = 0.153

    var rules: PaddleRules
    var phase: PaddlePhase = .ready
    var ball: TableBall?
    var playerX = 0.0
    var opponentX = 0.0
    var aimX = 0.0
    var elapsed = 0.0
    var pointClock = 0.0
    var score = TableRally()
    var lastShot: TableShot = .drive
    var banner = "FIRST TO 11 · WIN BY TWO"
    var winner: PaddleSide?
    var awaitingServe = true
    var serveSide: PaddleSide = .left
    var serveTurn = 0
    var bestOfGames = 3
    var aiStyle = 0 // varies between targeting the wings, body, and safe middle
    var stageClock = 0.0

    init(rules: PaddleRules = PaddleRules()) { self.rules = rules }
    var playerPoints: Int { score.player }
    var opponentPoints: Int { score.opponent }
    var playerGames: Int { score.playerGames }
    var opponentGames: Int { score.opponentGames }
    var returns: Int { score.returns }
    var rally: Int { score.currentRally }
    var longestRally: Int { score.longestRally }
    var arcadeScore: Int { score.pointsAwarded }
    var isDeuce: Bool { score.player >= 10 && score.opponent >= 10 }
    var gamesRequired: Int { bestOfGames / 2 + 1 }
    var playerServing: Bool { serveSide == .left }
    var servesRemaining: Int { isDeuce ? 1 : 2 - (serveTurn % 2) }
    var gamePoint: Bool {
        let high = max(score.player, score.opponent)
        return high >= 10 && abs(score.player - score.opponent) >= 1
    }

    mutating func start() {
        guard phase == .ready else { return }
        phase = .playing
        awaitingServe = true
        serveSide = .left
        banner = "SPACE TO SERVE · LEFT CLICK TO RETURN"
        pointClock = 0
    }
    mutating func pauseOrResume() {
        switch phase {
        case .playing: phase = .paused
        case .paused: phase = .playing
        default: break
        }
    }
    mutating func reset(_ rules: PaddleRules) { self = TableMatch(rules: rules) }

    /// Inputs are world-space metres from the projected pointer, not a
    /// percentage of the entire window. This keeps the paddle directly below
    /// the pointer even when the table occupies only part of the viewport.
    mutating func movePlayer(to worldX: Double) {
        playerX = clampTable(worldX, -0.70, 0.70)
    }
    mutating func aim(to worldX: Double) {
        aimX = clampTable(worldX * 0.93, -0.65, 0.65)
    }

    mutating func serve() -> Bool {
        guard phase == .playing, awaitingServe, serveSide == .left else { return false }
        serveFrom(.left)
        return true
    }
    mutating func serveSecondPlayer() -> Bool {
        guard phase == .playing, awaitingServe, serveSide == .right, rules.players == .local else { return false }
        serveFrom(.right)
        return true
    }
    private mutating func serveFrom(_ side: PaddleSide) {
        // First landing on the server's half is mandatory. The next must be on
        // the receiving half. Flight is tuned for keyboard/mouse play.
        let direction = side == .left ? -1.0 : 1.0
        let x = side == .left ? playerX : opponentX
        let z = side == .left ? 1.18 : -1.18
        // A legal serve must land on this half, rebound ABOVE the net cord,
        // then land on the other half. The old 0.83 m/s toss and 0.77 bounce
        // lost too much vertical energy: virtually every serve hit the net.
        //
        // Release 30 cm above the table, near level; a lively first bounce
        // (0.90 restitution) creates a reliable second arc over the net.
        // Keep serve pace bounded so Custom speed settings remain legal.
        let speed = 2.50 + (rules.ballFactor - 1.0) * 0.30
        ball = TableBall(x: x, y: 1.08, z: z,
                         vx: (side == .left ? -x : x) * 0.16,
                         vy: 0.0,
                         vz: direction * speed,
                         lastHit: side,
                         isServe: true)
        awaitingServe = false
        banner = "SERVICE · TWO BOUNCES TO START"
        score.currentRally = 0
    }

    /// Human stroke: return only after the bounce on your own court.
    /// Early swings leave the ball alive so a novice can recover.
    @discardableResult
    mutating func swing(side: PaddleSide = .left, shot: TableShot = .drive) -> Bool {
        guard phase == .playing, !awaitingServe, let b = ball,
              b.lastHit != side, b.receiverBounceCount == 1 else {
            banner = "WAIT FOR THE TABLE BOUNCE"
            return false
        }
        let near = side == .left
        let x = near ? playerX : opponentX
        // A return is legal anywhere on the receiving half after its first
        // bounce. The old >0.38 m trigger blocked many genuine returns near
        // the net and made the rally feel unresponsive.
        let zReady = near ? b.z > 0.10 : b.z < -0.10
        let incoming = near ? b.vz > 0 : b.vz < 0
        let reach = shot == .smash ? 0.37 : 0.43
        let reachable = abs(b.x - x) <= reach
        guard zReady, incoming, reachable, b.y < 1.65 &&
              b.y >= Self.tableHeight - 0.01 else {
            banner = reachable ? "TIMING · TRACK THE BALL" : "TOO FAR FROM THE BALL"
            return false
        }
        if shot == .smash && b.y < 0.88 {
            banner = "SMASH REQUIRES A HIGHER BALL"
            return false
        }
        let placement: Double
        if side == .left {
            placement = clampTable(aimX + (b.x - playerX) * 1.2, -0.68, 0.68)
        } else {
            placement = clampTable(-aimX + (b.x - opponentX) * 1.2, -0.68, 0.68)
        }
        strike(from: side, shot: shot, targetX: placement)
        lastShot = shot
        score.currentRally += 1
        score.longestRally = max(score.currentRally, score.longestRally)
        score.returns += 1
        score.pointsAwarded += (shot == .smash ? 75 : 30) + min(120, score.currentRally * 8)
        banner = shot == .smash ? "SMASH!" : (shot == .backspin ? "BACKSPIN RETURN" : "CLEAN RETURN")
        return true
    }

    mutating func tick(_ delta: Double, nearAxis: Double = 0, farAxis: Double = 0,
                       selectedShot: TableShot = .drive) -> [PaddleEvent] {
        guard phase == .playing && delta.isFinite && delta > 0 else { return [] }
        let total = min(delta, 1.0/24.0)
        let steps = max(1, Int(ceil(total / (1.0/240.0))))
        var events: [PaddleEvent] = []
        for _ in 0..<steps {
            if phase != .playing { break }
            let dt = total / Double(steps)
            elapsed += dt
            pointClock += dt
            stageClock += dt
            if abs(nearAxis) > 0.05 {
                playerX = clampTable(playerX + nearAxis * dt * 1.45, -0.70, 0.70)
            }
            if rules.players == .local {
                opponentX = clampTable(opponentX + farAxis * dt * 1.45, -0.70, 0.70)
            } else { updateOpponent(dt) }
            if awaitingServe {
                if serveSide == .right && rules.players == .solo && pointClock >= 1.0 {
                    serveFrom(.right)
                }
                continue
            }
            guard var b = ball else { continue }
            let oldY = b.y
            let oldZ = b.z
            b.vx += b.sidewaysSpin * dt
            b.vy += (-Self.gravity + b.verticalSpin) * dt
            b.sidewaysSpin *= max(0, 1 - dt * 0.6)
            b.verticalSpin *= max(0, 1 - dt * 1.8)
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.z += b.vz * dt
            // Net collision only within the actual net span.
            if (oldZ * b.z <= 0), abs(b.x) < 0.83,
               b.y - Self.ballRadius < Self.tableHeight + Self.netHeight {
                ball = nil
                awardPoint(to: b.lastHit.opposite, reason: "NET FAULT")
                events.append(.score)
                continue
            }
            if oldY - Self.ballRadius >= Self.tableHeight &&
               b.y - Self.ballRadius <= Self.tableHeight && b.vy < 0 {
                let onTable = abs(b.x) <= Self.tableWidth/2 &&
                              abs(b.z) <= Self.tableHalfLength
                guard onTable else {
                    ball = nil
                    awardPoint(to: b.lastHit.opposite, reason: "OUT OF BOUNDS")
                    events.append(.score)
                    continue
                }
                let landedOnNear = b.z > 0
                let landedSide: PaddleSide = landedOnNear ? .left : .right
                let receivingSide = b.lastHit.opposite
                if b.isServe && !b.ownServeBounce {
                    if landedSide != b.lastHit {
                        ball = nil
                        awardPoint(to: receivingSide, reason: "SERVICE FAULT")
                        events.append(.score)
                        continue
                    }
                    b.ownServeBounce = true
                } else {
                    if landedSide != receivingSide || b.receiverBounceCount > 0 {
                        ball = nil
                        awardPoint(to: landedSide == receivingSide && b.receiverBounceCount > 0 ? b.lastHit : receivingSide, reason: "DOUBLE BOUNCE / WRONG COURT")
                        events.append(.score)
                        continue
                    }
                    b.receiverBounceCount += 1
                    if b.isServe { b.isServe = false }
                    events.append(.wall)
                    banner = receivingSide == .left ? "RETURN THE BALL · CLICK" : "OPPONENT RETURNING"
                }
                b.y = Self.tableHeight + Self.ballRadius
                // The first service bounce must preserve sufficient height
                // for the ball to cross the 15.25 cm net; normal rally
                // returns retain the lower restitution.
                b.vy = abs(b.vy) * (b.isServe && b.ownServeBounce ? 0.90 : 0.77)
                b.vx *= 0.95
                b.vz *= 0.93
            }
            // A ball travelling past the end of court is either a valid
            // unreturned winner (after bounce) or a long-shot fault.
            if abs(b.z) > Self.tableHalfLength + 0.35 ||
               b.y < -0.3 || abs(b.x) > 2.5 {
                ball = nil
                let receivingSide = b.lastHit.opposite
                let scorer = b.receiverBounceCount == 1 ? b.lastHit : receivingSide
                awardPoint(to: scorer, reason: b.receiverBounceCount == 1 ? "POINT WINNER" : "LONG / WIDE")
                events.append(.score)
                continue
            }
            // Detect a real crossing of the racket plane, not an arbitrary
            // click. A legal return may happen only AFTER one bounce on the
            // receiver's half and when the incoming ball overlaps the paddle.
            // Substeps prevent fast balls from tunnelling through the racket.
            if b.receiverBounceCount == 1 {
                let receiver = b.lastHit.opposite
                let plane = receiver == .left ? Self.paddleContactZ : -Self.paddleContactZ
                let crosses = receiver == .left
                    ? (b.vz > 0 && oldZ < plane && b.z >= plane)
                    : (b.vz < 0 && oldZ > plane && b.z <= plane)
                if crosses {
                    let paddleX = receiver == .left ? playerX : opponentX
                    // A slightly forgiving arcade contact envelope is much
                    // closer to the displayed racket than the old invisible
                    // click-anywhere behavior.
                    // An oval swept-sphere contact envelope, expanded
                    // slightly for the arcade camera and human reaction time.
                    // The small visible paddle is not a giant invisible box.
                    let contactX = Self.paddleHalfWidth + Self.ballRadius + 0.095
                    let contactY = Self.paddleHalfHeight + Self.ballRadius + 0.085
                    let nx = (b.x - paddleX) / contactX
                    let ny = (b.y - Self.paddleCenterY) / contactY
                    if nx * nx + ny * ny <= 1.0 {
                        ball = b
                        let chosen: TableShot
                        let target: Double
                        if receiver == .left {
                            chosen = selectedShot == .smash && b.y < 0.88
                                ? .drive : selectedShot
                            target = clampTable(aimX + (b.x - playerX) * 0.35, -0.68, 0.68)
                        } else {
                            chosen = .drive
                            if rules.players == .solo {
                                switch aiStyle % 3 {
                                case 0: target = -0.49
                                case 1: target = 0.48
                                default: target = 0.06
                                }
                                aiStyle += 1
                            } else {
                                target = clampTable(-aimX + (b.x - opponentX) * 0.35, -0.68, 0.68)
                            }
                        }
                        strike(from: receiver, shot: chosen, targetX: target)
                        score.currentRally += 1
                        score.longestRally = max(score.currentRally, score.longestRally)
                        if receiver == .left {
                            score.returns += 1
                            score.pointsAwarded += 30 + min(120, score.currentRally * 8)
                        }
                        banner = receiver == .left
                            ? "PADDLE CONTACT · \(chosen.rawValue.uppercased())"
                            : "CPU RETURN · TRACK THE BALL"
                        events.append(.paddle)
                        continue
                    }
                }
            }
            ball = b
        }
        return events
    }

    private mutating func updateOpponent(_ dt: Double) {
        var target = 0.02 * sin(elapsed * 0.8)
        if let b = ball, b.lastHit == .left {
            let timeToFarCourt = max(0, (-0.9 - b.z)/min(-0.2, b.vz))
            target = clampTable(b.x + b.vx * timeToFarCourt, -0.68, 0.68)
        }
        let speed: Double
        switch rules.skill {
        case .cadet: speed = 0.58
        case .veteran: speed = 1.15
        case .ace: speed = 1.72
        }
        opponentX += clampTable(target - opponentX, -speed * dt, speed * dt)
    }

    private mutating func strike(from side: PaddleSide, shot: TableShot, targetX: Double) {
        guard var b = ball else { return }
        let destinationZ = side == .left ? -0.94 : 0.94
        // Old 0.59-0.72 second arcs looked like floating balloons. Work from
        // a physically solved landing point and choose a shorter, readable
        // time of flight; the net clearance constraint is then enforced.
        let baseDuration: Double
        switch shot {
        case .drive: baseDuration = 0.43
        case .backspin: baseDuration = 0.52
        case .smash: baseDuration = 0.38
        }
        let pace = 0.85 + 0.15 * rules.ballFactor
        var duration = baseDuration / pace
        let verticalSpin: Double = shot == .backspin ? 0.35 : (shot == .smash ? -0.18 : 0)
        let effectiveGravity = Self.gravity - verticalSpin
        let landingY = Self.tableHeight + Self.ballRadius + 0.005
        // Because this is a ballistic arc, the vertical height at the net is
        // the interpolation between impact and landing plus an arc term.
        // Increase the flight duration until it clears the real net by 4 cm.
        // This prevents low, valid returns from faulting into the cord.
        let fractionAtNet = min(0.96, max(0.04,
            abs(b.z) / max(0.001, abs(b.z) + abs(destinationZ))))
        let minNetCenter = Self.tableHeight + Self.netHeight + Self.ballRadius + 0.04
        while duration < 0.75 {
            let atNet = b.y * (1 - fractionAtNet) + landingY * fractionAtNet
                + 0.5 * effectiveGravity * duration * duration
                  * fractionAtNet * (1 - fractionAtNet)
            if atNet >= minNetCenter { break }
            duration += 0.012
        }
        b.vx = (targetX - b.x) / duration
        b.vz = (destinationZ - b.z) / duration
        b.vy = (landingY - b.y + 0.5 * effectiveGravity * duration * duration) / duration
        b.verticalSpin = verticalSpin
        // Sidespin bends the flight gradually but shouldn't move it entirely
        // off the receiver's side after targeting a valid in-bounds landing.
        b.sidewaysSpin = (targetX - b.x) * (shot == .backspin ? 0.06 : 0.04)
        b.lastHit = side
        b.isServe = false
        b.ownServeBounce = false
        b.receiverBounceCount = 0
        ball = b
    }

    private mutating func awardPoint(to side: PaddleSide, reason: String) {
        if side == .left { score.player += 1; score.pointsAwarded += 180 }
        else { score.opponent += 1; score.pointsAwarded += rules.players == .local ? 100 : 0 }
        score.currentRally = 0
        pointClock = 0
        stageClock = 0
        banner = reason
        let high = max(score.player, score.opponent)
        if high >= 11 && abs(score.player - score.opponent) >= 2 {
            let gameWinner: PaddleSide = score.player > score.opponent ? .left : .right
            if gameWinner == .left { score.playerGames += 1; score.pointsAwarded += 900 }
            else { score.opponentGames += 1 }
            if max(score.playerGames, score.opponentGames) >= gamesRequired {
                winner = gameWinner
                phase = .finished
                awaitingServe = false
                banner = gameWinner == .left ? "MATCH WON · NEON CHAMPION" : "MATCH COMPLETE"
                if gameWinner == .left { score.pointsAwarded += 1_500 }
                return
            }
            score.player = 0
            score.opponent = 0
            serveTurn = 0
            banner = "GAME COMPLETE · NEXT GAME"
        } else { serveTurn += 1 }
        // Two serves each, alternating each point at deuce.
        if score.player >= 10 && score.opponent >= 10 {
            serveSide = (serveTurn % 2 == 0) ? .left : .right
        } else {
            serveSide = (serveTurn / 2) % 2 == 0 ? .left : .right
        }
        awaitingServe = true
    }
}
private func clampTable(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(hi, max(lo, v))
}


/// Camera geometry shared by the visual RealityKit renderer and mouse
/// projection. One source of truth avoids input drift after camera changes.
enum NeonRallyProjection {
    static let eyeY = 1.76
    static let eyeZ = 2.05
    static let lookY = 0.80
    static let lookZ = 0.50
    static let fieldOfViewDegrees = 60.0
    static let nearPaddleY = 1.01
    static let nearPaddleZ = 1.47

    /// Unprojects a horizontal viewport coordinate onto the player's paddle
    /// plane using the same perspective camera as the 3D renderer. No dead
    /// zone, damping, or multiplicative screen-width guesses.
    static func worldX(pointerX: Double, width: Double, height: Double) -> Double {
        guard pointerX.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { return 0 }
        let fy = lookY - eyeY
        let fz = lookZ - eyeZ
        let cameraDistance = hypot(fy, fz)
        let depth = ((nearPaddleY - eyeY) * fy +
                     (nearPaddleZ - eyeZ) * fz) / cameraDistance
        let halfWidthInMetres = depth * tan(fieldOfViewDegrees * .pi / 360.0) * (width / height)
        let horizontalNDC = (pointerX - width / 2) / (width / 2)
        return clampTable(horizontalNDC * halfWidthInMetres, -0.70, 0.70)
    }
}
