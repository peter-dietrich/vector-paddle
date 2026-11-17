import Foundation

enum PaddleStyle: String, CaseIterable, Codable, Identifiable {
    case classic = "Classic", modern = "Modern"
    var id: String { rawValue }
}
enum PaddleSkill: String, CaseIterable, Codable, Identifiable {
    case cadet = "Cadet", veteran = "Veteran", ace = "Ace"
    var id: String { rawValue }
}
enum PaddlePlayers: String, CaseIterable, Codable, Identifiable {
    case solo = "1 Player vs CPU", local = "Local 2 Player"
    var id: String { rawValue }
}
enum PaddlePhase: String, Codable { case ready, playing, paused, finished }
enum PaddleSide: String, Codable {
    case left, right
    var opposite: PaddleSide { self == .left ? .right : .left }
}
enum PaddlePickupKind: String, CaseIterable, Codable {
    case wide = "WIDE", split = "SPLIT", slow = "SLOW", boost = "BOOST"
}
struct PaddleRules: Codable, Equatable {
    var style: PaddleStyle = .classic
    var skill: PaddleSkill = .veteran
    var players: PaddlePlayers = .solo
    var pointsToWin = 11
    var ballSpeedPercent = 100
    var paddleSizePercent = 100
    var mousePaddle = false
    var powerupsEnabled = true
    var soundEnabled = true
    var reducedFlash = false
    var effectsEnabled = true
    var winningPoints: Int { max(3, min(pointsToWin, 21)) }
    var ballFactor: Double { Double(max(60, min(ballSpeedPercent, 160))) / 100 }
    var paddleFactor: Double { Double(max(65, min(paddleSizePercent, 145))) / 100 }
    var modernPowerups: Bool { style == .modern && powerupsEnabled }
}
struct PaddleBall: Codable, Identifiable {
    var id = UUID()
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var lastHit: PaddleSide = .left
}
struct PaddlePickup: Codable {
    var x: Double
    var y: Double
    var kind: PaddlePickupKind
}
enum PaddleEvent { case paddle, wall, score, pickup, win }

struct PaddleEngine: Codable {
    var rules: PaddleRules
    var phase: PaddlePhase = .ready
    var leftY = 0.5
    var rightY = 0.5
    var balls: [PaddleBall] = []
    var leftScore = 0
    var rightScore = 0
    var arcadeScore = 0
    var rally = 0
    var longestRally = 0
    var leftWideFor = 0.0
    var rightWideFor = 0.0
    var slowFor = 0.0
    var boostFor = 0.0
    var elapsed = 0.0
    var serveCountdown = 0.65
    var pendingServe: PaddleSide = .left
    var pickup: PaddlePickup? = nil
    var nextPickupAt = 7.0
    var winner: PaddleSide? = nil
    var bounceCount = 0

    init(rules: PaddleRules = PaddleRules()) { self.rules = rules }
    var paddleHalfHeight: Double { 0.083 * rules.paddleFactor }
    func halfHeight(for side: PaddleSide) -> Double {
        paddleHalfHeight * ((side == .left ? leftWideFor : rightWideFor) > 0 ? 1.52 : 1)
    }
    mutating func start() { phase = .playing; serveCountdown = 0.6 }
    mutating func pauseOrResume() {
        switch phase {
        case .playing: phase = .paused
        case .paused: phase = .playing
        default: break
        }
    }
    mutating func reset(using newRules: PaddleRules) { self = PaddleEngine(rules: newRules) }

    mutating func step(_ delta: Double, leftAxis: Double, rightAxis: Double, mouseY: Double?) -> [PaddleEvent] {
        guard phase == .playing, delta.isFinite, delta > 0 else { return [] }
        let dt = min(delta, 1.0 / 24.0)
        let n = Int(ceil(dt / (1.0 / 240.0)))
        var events: [PaddleEvent] = []
        for _ in 0..<n {
            guard phase == .playing else { break }
            let t = dt / Double(n)
            elapsed += t
            leftWideFor = max(0, leftWideFor - t); rightWideFor = max(0, rightWideFor - t)
            slowFor = max(0, slowFor - t); boostFor = max(0, boostFor - t)
            let leftMove = rules.mousePaddle && mouseY != nil
                ? (mouseY! - leftY) * min(1.0, t * 18.0)
                : clamp(leftAxis, -1, 1) * 0.92 * t
            leftY = clamp(leftY + leftMove, halfHeight(for: .left), 1 - halfHeight(for: .left))
            let rightMove = rules.players == .solo ? aiMove(seconds: t) : clamp(rightAxis, -1, 1) * 0.92 * t
            rightY = clamp(rightY + rightMove, halfHeight(for: .right), 1 - halfHeight(for: .right))
            if serveCountdown > 0 {
                serveCountdown -= t
                if serveCountdown <= 0 && balls.isEmpty { launchServe() }
            }
            if rules.modernPowerups && elapsed >= nextPickupAt && pickup == nil {
                pickup = PaddlePickup(x: Double.random(in: 0.36...0.64),
                    y: Double.random(in: 0.23...0.77), kind: PaddlePickupKind.allCases.randomElement() ?? .wide)
                nextPickupAt = elapsed + Double.random(in: 9...13)
            }
            for idx in balls.indices.reversed() {
                var ball = balls[idx]
                let factor = (slowFor > 0 ? 0.66 : 1) * (boostFor > 0 ? 1.28 : 1)
                let oldX = ball.x
                ball.x += ball.vx * t * factor
                ball.y += ball.vy * t * factor
                if ball.y < 0.052 {
                    ball.y = 0.104 - ball.y; ball.vy = abs(ball.vy)
                    if events.count < 6 { events.append(.wall) }
                } else if ball.y > 0.948 {
                    ball.y = 1.896 - ball.y; ball.vy = -abs(ball.vy)
                    if events.count < 6 { events.append(.wall) }
                }
                let hitLeft = ball.vx < 0 && oldX >= 0.076 && ball.x <= 0.076 && abs(ball.y - leftY) <= halfHeight(for: .left) + 0.014
                let hitRight = ball.vx > 0 && oldX <= 0.924 && ball.x >= 0.924 && abs(ball.y - rightY) <= halfHeight(for: .right) + 0.014
                if hitLeft || hitRight {
                    let side: PaddleSide = hitLeft ? .left : .right
                    let center = side == .left ? leftY : rightY
                    let angle = clamp((ball.y - center) / halfHeight(for: side), -1, 1) * 0.94
                    let speed = min(1.58 * rules.ballFactor, max(0.45, hypot(ball.vx, ball.vy)) * 1.035)
                    ball.vx = (side == .left ? 1 : -1) * max(0.22, speed * cos(angle))
                    ball.vy = speed * sin(angle)
                    ball.x = side == .left ? 0.078 : 0.922
                    ball.lastHit = side
                    rally += 1; longestRally = max(longestRally, rally); bounceCount += 1
                    arcadeScore += 10 + min(40, rally * 2)
                    if events.count < 6 { events.append(.paddle) }
                }
                if let prize = pickup, hypot(ball.x - prize.x, ball.y - prize.y) < 0.036 {
                    pickup = nil
                    applyPickup(prize.kind, for: ball.lastHit, ball: ball)
                    arcadeScore += 150
                    if events.count < 6 { events.append(.pickup) }
                }
                if ball.x < -0.026 || ball.x > 1.026 {
                    let scorer: PaddleSide = ball.x < 0 ? .right : .left
                    if scorer == .left { leftScore += 1 } else { rightScore += 1 }
                    pendingServe = scorer.opposite
                    arcadeScore += scorer == .left ? 250 : 70
                    rally = 0
                    balls.remove(at: idx)
                    if events.count < 6 { events.append(.score) }
                    if max(leftScore, rightScore) >= rules.winningPoints {
                        winner = leftScore > rightScore ? .left : .right
                        if winner == .left { arcadeScore += 1_000 }
                        else if rules.players == .local { arcadeScore += 750 }
                        phase = .finished
                        balls.removeAll()
                        events.append(.win)
                        break
                    } else if balls.isEmpty { serveCountdown = 0.95 }
                } else { balls[idx] = ball }
            }
        }
        return events
    }

    private mutating func launchServe() {
        let direction: Double = pendingServe == .left ? -1 : 1
        let speed = (rules.style == .classic ? 0.47 : 0.55) * rules.ballFactor
        balls.append(PaddleBall(x: 0.5, y: Double.random(in: 0.34...0.66),
            vx: direction * speed, vy: Double.random(in: -0.19...0.19), lastHit: pendingServe.opposite))
    }
    private mutating func applyPickup(_ kind: PaddlePickupKind, for side: PaddleSide, ball: PaddleBall) {
        switch kind {
        case .wide:
            if side == .left { leftWideFor = 8 } else { rightWideFor = 8 }
        case .split:
            if balls.count < 3 {
                var twin = ball; twin.id = UUID()
                twin.vy = (ball.vy > 0 ? -1 : 1) * (abs(ball.vy) + 0.28)
                twin.x = clamp(twin.x + (ball.vx > 0 ? 0.019 : -0.019), 0.15, 0.85)
                balls.append(twin)
            }
        case .slow: slowFor = 3.8
        case .boost: boostFor = 4.5
        }
    }
    private func aiMove(seconds: Double) -> Double {
        let target = balls.filter { $0.vx > 0 }.max(by: { $0.x < $1.x })
        let aim: Double
        if let b = target {
            let time = max(0, (0.924 - b.x) / max(0.01, b.vx))
            let y = (b.y + b.vy * time - 0.052).truncatingRemainder(dividingBy: 1.792)
            let folded = y < 0 ? y + 1.792 : y
            let predicted = 0.052 + (folded <= 0.896 ? folded : 1.792 - folded)
            let error: Double
            switch rules.skill {
            case .cadet: error = 0.085
            case .veteran: error = 0.037
            case .ace: error = 0.011
            }
            aim = clamp(predicted + sin(elapsed * 1.6) * error, 0.1, 0.9)
        } else { aim = 0.5 + 0.11 * sin(elapsed * 0.36) }
        let speed: Double
        switch rules.skill {
        case .cadet: speed = 0.46
        case .veteran: speed = 0.74
        case .ace: speed = 1.05
        }
        return clamp(aim - rightY, -speed * seconds, speed * seconds)
    }
}

private func clamp(_ n: Double, _ minValue: Double, _ maxValue: Double) -> Double {
    min(maxValue, max(minValue, n))
}
