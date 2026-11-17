import Foundation

@main struct EngineSmoke {
    static func main() throws {
        var classic = PaddleEngine()
        assert(classic.phase == .ready)
        classic.start()
        for _ in 0..<120 { _ = classic.step(1.0 / 60.0, leftAxis: 0, rightAxis: 0, mouseY: nil) }
        assert(!classic.balls.isEmpty || classic.leftScore + classic.rightScore > 0)
        classic.pauseOrResume()
        assert(classic.phase == .paused)
        let snapshot = try JSONEncoder().encode(classic)
        let restored = try JSONDecoder().decode(PaddleEngine.self, from: snapshot)
        assert(restored.phase == .paused && restored.rules.style == .classic)

        var rebound = PaddleEngine()
        rebound.start()
        rebound.serveCountdown = -1
        rebound.balls = [PaddleBall(x: 0.081, y: 0.50, vx: -0.7, vy: 0)]
        _ = rebound.step(1.0 / 60.0, leftAxis: 0, rightAxis: 0, mouseY: nil)
        assert(rebound.balls.first?.vx ?? 0 > 0, "left paddle must rebound")
        assert(rebound.rally == 1 && rebound.arcadeScore > 0)

        var finishRules = PaddleRules()
        finishRules.pointsToWin = 3
        var finish = PaddleEngine(rules: finishRules)
        finish.start()
        finish.serveCountdown = -1
        finish.leftScore = 2
        finish.balls = [PaddleBall(x: 1.025, y: 0.2, vx: 0.6, vy: 0)]
        _ = finish.step(1.0 / 60.0, leftAxis: 0, rightAxis: 0, mouseY: nil)
        assert(finish.phase == .finished && finish.winner == .left)
        assert(finish.arcadeScore >= 1_250)

        var rules = PaddleRules()
        rules.style = .modern
        rules.players = .local
        rules.pointsToWin = 3
        var modern = PaddleEngine(rules: rules)
        modern.start()
        modern.serveCountdown = -1
        modern.pickup = PaddlePickup(x: 0.5, y: 0.5, kind: .split)
        modern.balls = [PaddleBall(x: 0.5, y: 0.5, vx: 0.4, vy: 0)]
        _ = modern.step(1.0 / 60.0, leftAxis: 0, rightAxis: 0, mouseY: nil)
        assert(modern.balls.count == 2, "split powerup must add a ball")
        modern.pickup = PaddlePickup(x: 0.5, y: 0.5, kind: .wide)
        modern.balls = [PaddleBall(x: 0.5, y: 0.5, vx: 0.4, vy: 0, lastHit: .right)]
        _ = modern.step(1.0 / 60.0, leftAxis: 0, rightAxis: 0, mouseY: nil)
        assert(modern.rightWideFor > 0, "wide powerup must grow the correct paddle")
        print("PASS: serve, scoring, paddle rebound, match win, pickups, pause, save/restore")
    }
}
