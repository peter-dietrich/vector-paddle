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
        var tennis = TableMatch(rules: PaddleRules(style: .modern))
        assert(tennis.phase == .ready)
        tennis.start()
        assert(tennis.phase == .playing && tennis.awaitingServe)
        assert(tennis.serve())
        assert(tennis.ball != nil)
        for _ in 0..<240 {
            _ = tennis.tick(1.0 / 60.0)
            if tennis.awaitingServe { break }
        }
        assert(tennis.score.player + tennis.score.opponent > 0, "point must finish")
        assert(tennis.awaitingServe)
        tennis.pauseOrResume()
        assert(tennis.phase == .paused)
        let tennisData = try JSONEncoder().encode(tennis)
        let resumed = try JSONDecoder().decode(TableMatch.self, from: tennisData)
        assert(resumed.phase == .paused)
        var deuce = TableMatch(rules: PaddleRules(style: .modern))
        deuce.start()
        deuce.score.player = 10; deuce.score.opponent = 10
        assert(deuce.isDeuce)
        // Explicit regression for the original all-serves-hit-the-net bug.
        // Track both servers through the own-side bounce, net crossing and
        // receiving-side bounce, rather than merely checking a point resolves.
        for server in [PaddleSide.left, .right] {
            var serveRules = PaddleRules()
            serveRules.style = .modern
            serveRules.players = .local
            for speed in [60, 100, 160] {
                serveRules.ballSpeedPercent = speed
                var check = TableMatch(rules: serveRules)
                check.start()
                check.serveSide = server
                let launched = server == .left ? check.serve() : check.serveSecondPlayer()
                assert(launched, "service must launch")
                var ownBounce = false
                var clearedNet = false
                var oppositeBounce = false
                for _ in 0..<240 {
                    _ = check.tick(1.0 / 240.0)
                    if let flight = check.ball {
                        if flight.ownServeBounce { ownBounce = true }
                        if (server == .left ? flight.z < 0 : flight.z > 0) {
                            if flight.y - TableMatch.ballRadius >
                                TableMatch.tableHeight + TableMatch.netHeight {
                                clearedNet = true
                            }
                        }
                        if flight.receiverBounceCount == 1 { oppositeBounce = true; break }
                    } else { break }
                }
                assert(ownBounce, "serve must touch server half")
                assert(clearedNet, "serve must clear net at every speed")
                assert(oppositeBounce, "serve must bounce on receiver half")
            }
        }
        print("PASS: legal near/far serves clear net and bounce on both halves at 60/100/160%")
        print("PASS: 3D serves, ball physics, point resolution, deuce, save/restore")
        print("PASS: serve, scoring, paddle rebound, match win, pickups, pause, save/restore")
    }
}
