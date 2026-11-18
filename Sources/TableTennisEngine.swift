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

    mutating func movePlayer(to normalizedX: Double) {
        playerX = clampTable(normalizedX * 0.64, -0.70, 0.70)
    }
    mutating func aim(to normalizedX: Double) {
        aimX = clampTable(normalizedX * 0.65, -0.65, 0.65)
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
        ball = TableBall(x: x, y: 0.98, z: z,
                         vx: (side == .left ? -x : x) * 0.2,
                         vy: 0.83,
                         vz: direction * 2.25,
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
        let zReady = near ? b.z > 0.38 : b.z < -0.38
        let reachable = abs(b.x - x) <= (shot == .smash ? 0.32 : 0.28)
        guard zReady, reachable, b.y < 1.48 && b.y >= Self.tableHeight - 0.01 else {
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

    mutating func tick(_ delta: Double, nearAxis: Double = 0, farAxis: Double = 0) -> [PaddleEvent] {
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
                        awardPoint(to: receivingSide, reason: "DOUBLE BOUNCE / WRONG COURT")
                        events.append(.score)
                        continue
                    }
                    b.receiverBounceCount += 1
                    if b.isServe { b.isServe = false }
                    events.append(.wall)
                    banner = receivingSide == .left ? "RETURN THE BALL · CLICK" : "OPPONENT RETURNING"
                }
                b.y = Self.tableHeight + Self.ballRadius
                b.vy = abs(b.vy) * 0.77
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
            ball = b
            if rules.players == .solo && b.lastHit == .left &&
               b.receiverBounceCount == 1 && b.z < -0.48 && b.z > -1.35 {
                let skillReach: Double = rules.skill == .cadet ? 0.26 : (rules.skill == .veteran ? 0.33 : 0.40)
                let likelyHit = abs(b.x - opponentX) < skillReach && b.y < 1.34
                if likelyHit {
                    let intended: Double
                    switch aiStyle % 3 {
                    case 0: intended = -0.54
                    case 1: intended = 0.53
                    default: intended = 0.06
                    }
                    aiStyle += 1
                    let error = rules.skill == .cadet ? 0.22 : (rules.skill == .veteran ? 0.12 : 0.04)
                    strike(from: .right, shot: .drive,
                           targetX: clampTable(intended + Double.random(in: -error...error), -0.68, 0.68))
                    score.currentRally += 1
                    score.longestRally = max(score.currentRally, score.longestRally)
                    banner = "INCOMING · WAIT FOR BOUNCE"
                    events.append(.paddle)
                }
            }
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
        let destinationZ = side == .left ? -0.97 : 0.97
        let travel: Double
        switch shot {
        case .drive: travel = 0.59
        case .backspin: travel = 0.72
        case .smash: travel = 0.44
        }
        let safeFlight = max(0.36, travel / rules.ballFactor)
        let elevation = Self.tableHeight + Self.ballRadius + 0.025
        b.vx = (targetX - b.x) / safeFlight
        b.vz = (destinationZ - b.z) / safeFlight
        let physicsGravity = Self.gravity - (shot == .backspin ? 0.45 : shot == .smash ? -0.25 : 0)
        b.vy = (elevation - b.y + 0.5 * physicsGravity * safeFlight * safeFlight) / safeFlight
        b.verticalSpin = shot == .backspin ? 0.45 : (shot == .smash ? -0.25 : 0)
        b.sidewaysSpin = shot == .drive ? (targetX - b.x) * 0.12 : (targetX - b.x) * 0.2
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
