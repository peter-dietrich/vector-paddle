import AppKit
import SwiftUI

@main
struct VectorPaddleApp: App {
    var body: some Scene {
        WindowGroup("Vector Paddle") {
            PaddleWindow().frame(minWidth: 980, minHeight: 680).preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { CommandGroup(replacing: .newItem) {} GameHelpCommands() }
    }
}

struct PaddlePreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var rules: PaddleRules
}
struct PaddleSavedMatch: Codable {
    let savedOn: Date
    var engine: PaddleEngine
}
struct NeonRallySavedMatch: Codable {
    let savedOn: Date
    var match: TableMatch
}

@MainActor
final class PaddleSession: ObservableObject {
    @Published var engine = PaddleEngine()
    @Published var neon = TableMatch()
    @Published var selectedShot: TableShot = .drive
    @Published var showSettings = false
    @Published var showSaves = false
    @Published var showInitials = false
    @Published var initialsDraft = ""
    @Published var savedRevision = 0
    @Published var presets: [PaddlePreset] = []
    @Published var mouseY: Double? = nil
    @Published var bestClassic = 0
    @Published var bestModern = 0
    @Published var bestInitialsClassic = "---"
    @Published var bestInitialsModern = "---"

    private let audio = PaddleSound()
    private var keys: Set<UInt16> = []
    private var keyboardMonitor: Any?
    private var lastTick = Date()
    private var promptedThisMatch = false
    private let preferences = UserDefaults.standard

    init() {
        bestClassic = preferences.integer(forKey: "VectorPaddle.HighScore.Classic.v1")
        bestModern = preferences.integer(forKey: "VectorPaddle.HighScore.Modern.v1")
        bestInitialsClassic = preferences.string(forKey: "VectorPaddle.Initials.Classic.v1") ?? "---"
        bestInitialsModern = preferences.string(forKey: "VectorPaddle.Initials.Modern.v1") ?? "---"
        if let saved = preferences.data(forKey: "VectorPaddle.Presets.v1"),
           let entries = try? JSONDecoder().decode([PaddlePreset].self, from: saved) {
            presets = entries
        }
        if let saved = preferences.data(forKey: "VectorPaddle.Rules.v1"),
           let rules = try? JSONDecoder().decode(PaddleRules.self, from: saved) {
            engine = PaddleEngine(rules: rules)
        }
        neon = TableMatch(rules: engine.rules)
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, NSApp.isActive else { return event }
            return self.processKey(event) ? nil : event
        }
    }

    deinit {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    var isModern: Bool { engine.rules.style == .modern }
    var activePhase: PaddlePhase { isModern ? neon.phase : engine.phase }
    var activeScore: Int { isModern ? neon.arcadeScore : engine.arcadeScore }
    var activeLeft: Int { isModern ? neon.playerPoints : engine.leftScore }
    var activeRight: Int { isModern ? neon.opponentPoints : engine.rightScore }
    var activeRally: Int { isModern ? neon.rally : engine.rally }
    var activeLongest: Int { isModern ? neon.longestRally : engine.longestRally }
    var activeReturns: Int { isModern ? neon.returns : engine.bounceCount }
    var activeWinner: PaddleSide? { isModern ? neon.winner : engine.winner }
    func setPointer(_ x: Double) { if isModern { neon.movePlayer(to: x); neon.aim(to: x) } }
    func swing() {
        guard isModern else { return }
        let didHit = neon.swing(shot: selectedShot)
        if didHit { audio.play(.paddle, enabled: engine.rules.soundEnabled) }
    }
    func chooseShot(_ shot: TableShot) { selectedShot = shot }
    var bestScore: Int { engine.rules.style == .classic ? bestClassic : bestModern }
    var bestInitials: String { engine.rules.style == .classic ? bestInitialsClassic : bestInitialsModern }

    private func processKey(_ event: NSEvent) -> Bool {
        guard !showSettings && !showSaves && !showInitials else { return false }
        let code = event.keyCode
        let controlledKeys: Set<UInt16> = [13, 1, 126, 125, 123, 124, 35, 15, 36, 76, 49, 2, 0, 11, 18, 19, 20]
        guard controlledKeys.contains(code) else { return false }
        if event.type == .keyUp { keys.remove(code); return true }
        keys.insert(code)
        if event.isARepeat { return true }
        if isModern {
            switch code {
            case 35: pauseOrResume()
            case 15: newGame()
            case 18: selectedShot = .drive
            case 19: selectedShot = .backspin
            case 20: selectedShot = .smash
            case 11: swing() // B shoots; A/D only steer horizontally
            case 36, 76, 49:
                switch neon.phase {
                case .ready, .finished: startGame()
                case .paused: pauseOrResume()
                case .playing: if neon.awaitingServe {
                    if neon.serveSide == .left { _ = neon.serve() }
                    else if neon.rules.players == .local { _ = neon.serveSecondPlayer() }
                } else { swing() }
                }
            default: break
            }
        } else {
            switch code {
            case 35: pauseOrResume()
            case 15: newGame()
            case 36, 76, 49:
                switch engine.phase {
                case .ready, .finished: startGame()
                case .paused: pauseOrResume()
                case .playing: break
                }
            default: break
            }
        }
        return true
    }
    func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        if isModern {
            guard neon.phase == .playing else { return }
            let leftAxis = (keys.contains(2) ? 1.0 : 0) - (keys.contains(0) ? 1.0 : 0)
            let rightAxis = (keys.contains(124) ? 1.0 : 0) - (keys.contains(123) ? 1.0 : 0)
            let events = neon.tick(dt, nearAxis: leftAxis, farAxis: rightAxis, selectedShot: selectedShot)
            if let event = events.last { audio.play(event, enabled: engine.rules.soundEnabled) }
            if neon.phase == .finished && !promptedThisMatch {
                promptedThisMatch = true
                if neon.arcadeScore > bestScore { initialsDraft = ""; showInitials = true }
            }
            return
        }
        guard engine.phase == .playing else { return }
        let left = (keys.contains(1) ? 1.0 : 0) - (keys.contains(13) ? 1.0 : 0)
        let right = (keys.contains(125) ? 1.0 : 0) - (keys.contains(126) ? 1.0 : 0)
        let events = engine.step(dt, leftAxis: left, rightAxis: right, mouseY: mouseY)
        if let event = events.last { audio.play(event, enabled: engine.rules.soundEnabled) }
        if engine.phase == .finished && !promptedThisMatch {
            promptedThisMatch = true
            if engine.arcadeScore > bestScore {
                initialsDraft = ""
                showInitials = true
            }
        }
    }
    func startGame() {
        if isModern {
            if neon.phase == .finished { newGame() }
            neon.start()
        } else {
            if engine.phase == .finished { newGame() }
            engine.start()
        }
        lastTick = Date()
    }
    func newGame(with rules: PaddleRules? = nil) {
        keys.removeAll()
        engine.reset(using: rules ?? engine.rules)
        neon.reset(engine.rules)
        selectedShot = .drive
        promptedThisMatch = false
        lastTick = Date()
        mouseY = nil
        if let data = try? JSONEncoder().encode(engine.rules) {
            preferences.set(data, forKey: "VectorPaddle.Rules.v1")
        }
    }
    func pauseOrResume() { if isModern { neon.pauseOrResume() } else { engine.pauseOrResume() }; lastTick = Date() }
    func selectStyle(_ style: PaddleStyle) {
        guard engine.rules.style != style else { return }
        var changed = engine.rules; changed.style = style
        newGame(with: changed)
    }
    func selectSkill(_ skill: PaddleSkill) {
        guard engine.rules.skill != skill else { return }
        var changed = engine.rules; changed.skill = skill
        newGame(with: changed)
    }
    func recordInitials() {
        let initials = String(initialsDraft.uppercased().filter { $0.isLetter }.prefix(3))
        let value = initials.isEmpty ? "---" : initials
        let score = activeScore
        if engine.rules.style == .classic {
            bestClassic = max(bestClassic, score)
            bestInitialsClassic = value
            preferences.set(bestClassic, forKey: "VectorPaddle.HighScore.Classic.v1")
            preferences.set(value, forKey: "VectorPaddle.Initials.Classic.v1")
        } else {
            bestModern = max(bestModern, score)
            bestInitialsModern = value
            preferences.set(bestModern, forKey: "VectorPaddle.HighScore.Modern.v1")
            preferences.set(value, forKey: "VectorPaddle.Initials.Modern.v1")
        }
        if score >= preferences.integer(forKey: "VectorPaddle.HighScore.v1") {
            preferences.set(score, forKey: "VectorPaddle.HighScore.v1")
            preferences.set(value, forKey: "VectorPaddle.Initials.v1")
        }
        showInitials = false
    }
    func save(_ slot: Int) {
        guard (1...5).contains(slot), activePhase != .ready else { return }
        if isModern {
            guard let data = try? JSONEncoder().encode(NeonRallySavedMatch(savedOn: Date(), match: neon)) else { return }
            preferences.set(data, forKey: "VectorPaddle.NeonRally.Slot.\(slot).v1")
            savedRevision += 1
            return
        }
        let save = PaddleSavedMatch(savedOn: Date(), engine: engine)
        guard let encoded = try? JSONEncoder().encode(save) else { return }
        preferences.set(encoded, forKey: slotKey(slot))
        savedRevision += 1
    }
    func readSlot(_ slot: Int) -> PaddleSavedMatch? {
        guard (1...5).contains(slot), let data = preferences.data(forKey: slotKey(slot)) else { return nil }
        return try? JSONDecoder().decode(PaddleSavedMatch.self, from: data)
    }
    func readModernSlot(_ slot: Int) -> NeonRallySavedMatch? {
        guard (1...5).contains(slot),
            let data = preferences.data(forKey: "VectorPaddle.NeonRally.Slot.\(slot).v1") else { return nil }
        return try? JSONDecoder().decode(NeonRallySavedMatch.self, from: data)
    }
    func hasSlot(_ slot: Int) -> Bool { isModern ? readModernSlot(slot) != nil : readSlot(slot) != nil }
    func resume(_ slot: Int) {
        if isModern {
            guard var saved = readModernSlot(slot) else { return }
            saved.match.phase = .paused
            neon = saved.match
            engine.reset(using: neon.rules)
            promptedThisMatch = false
            showSaves = false
            keys.removeAll()
            lastTick = Date()
            return
        }
        guard var save = readSlot(slot) else { return }
        save.engine.phase = .paused
        engine = save.engine
        promptedThisMatch = false
        lastTick = Date()
        showSaves = false
        keys.removeAll()
    }
    func delete(_ slot: Int) {
        if isModern { preferences.removeObject(forKey: "VectorPaddle.NeonRally.Slot.\(slot).v1") }
        else { preferences.removeObject(forKey: slotKey(slot)) }
        savedRevision += 1
    }
    private func slotKey(_ slot: Int) -> String { "VectorPaddle.SaveSlot.\(slot).v1" }
    func storePreset(name: String, rules: PaddleRules) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !clean.isEmpty else { return }
        if let index = presets.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            presets[index].rules = rules
        } else { presets.append(PaddlePreset(name: clean, rules: rules)) }
        persistPresets()
    }
    func deletePreset(id: UUID) { presets.removeAll { $0.id == id }; persistPresets() }
    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            preferences.set(data, forKey: "VectorPaddle.Presets.v1")
        }
    }
}

struct PaddleWindow: View {
    @StateObject private var game = PaddleSession()
    private let heartbeat = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()
    private let blue = Color(red: 0.20, green: 0.91, blue: 1)
    private let pink = Color(red: 1, green: 0.30, blue: 0.63)
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(short) (\(build))"
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "gamecontroller.fill").foregroundStyle(blue).font(.title2)
                Text("VECTOR PADDLE").font(.system(size: 22, weight: .black, design: .monospaced)).tracking(2)
                Text(version).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Button("Custom Game") { game.showSettings = true }
                Button("Save / Resume") { game.showSaves = true }
                Button(game.activePhase == .paused ? "Resume" : "Pause") { game.pauseOrResume() }
                    .disabled(game.activePhase != .playing && game.activePhase != .paused)
                Button("New Game") { game.newGame() }.buttonStyle(.borderedProminent).tint(blue)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .padding(.horizontal, 20).frame(height: 66)
            .background(Color(red: 0.042, green: 0.057, blue: 0.091))

            HStack(spacing: 22) {
                Text("CABINET").foregroundStyle(.white.opacity(0.5))
                Picker("Display", selection: Binding(get: { game.engine.rules.style }, set: { game.selectStyle($0) })) {
                    ForEach(PaddleStyle.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 200)
                Text("SKILL").foregroundStyle(.white.opacity(0.5))
                Picker("Skill", selection: Binding(get: { game.engine.rules.skill }, set: { game.selectSkill($0) })) {
                    ForEach(PaddleSkill.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 115)
                Spacer(minLength: 12)
                Text(game.engine.rules.players.rawValue.uppercased()).foregroundStyle(blue)
                Text(game.isModern ? "BEST OF 3 · 11 PT GAMES" : "FIRST TO \(game.engine.rules.winningPoints)").foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 22).frame(height: 44)
            .background(Color(red: 0.055, green: 0.076, blue: 0.119))

            GeometryReader { geometry in
                HStack(spacing: 18) {
                    Group {
                        if game.isModern {
                            NeonRallyArena(match: game.neon, aimChanged: { game.setPointer($0) },
                                           stroke: { game.swing() })
                        } else {
                            PaddleArena(engine: game.engine) { normalizedY in game.mouseY = normalizedY }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(blue.opacity(game.isModern ? 0.5 : 0.2)))
                    .overlay { statusOverlay }
                    telemetry.frame(width: 220)
                }
                .padding(18).frame(width: geometry.size.width, height: geometry.size.height)
            }
            HStack(spacing: 16) {
                if game.isModern {
                    Text("POINTER / A-D  MOVE PADDLE")
                    Text("AUTO RETURN  ·  CLICK FOR EARLY SHOT")
                    Text("SPACE  SERVE")
                    Picker("Shot", selection: $game.selectedShot) {
                        Text("1 DRIVE").tag(TableShot.drive)
                        Text("2 BACKSPIN").tag(TableShot.backspin)
                        Text("3 SMASH").tag(TableShot.smash)
                    }.pickerStyle(.segmented).frame(width: 310)
                } else {
                    Text("W / S  LEFT PADDLE")
                    Text("↑ / ↓  RIGHT PADDLE (2P)")
                    Text("RETURN / SPACE  START")
                }
                Spacer()
                Text("P  PAUSE     R  RESET")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 20).frame(height: 44)
            .background(Color(red: 0.042, green: 0.057, blue: 0.091))
        }
        .background(Color(red: 0.024, green: 0.033, blue: 0.052))
        .onReceive(heartbeat) { _ in game.tick() }
        .sheet(isPresented: $game.showSettings) { PaddleSettingsSheet(game: game) }
        .sheet(isPresented: $game.showSaves) { PaddleSaveSheet(game: game) }
        .sheet(isPresented: $game.showInitials) {
            VStack(spacing: 17) {
                Text("NEW ARCADE RECORD").font(.system(size: 22, weight: .black, design: .monospaced))
                Text("\(game.activeScore) POINTS  ·  \(game.engine.rules.style.rawValue.uppercased())")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                TextField("THREE INITIALS", text: $game.initialsDraft).frame(width: 160).textFieldStyle(.roundedBorder)
                Button("Record Score") { game.recordInitials() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(32).frame(width: 400).preferredColorScheme(.dark)
        }
    }
    @ViewBuilder private var statusOverlay: some View {
        switch game.activePhase {
        case .ready: gameMessage("VECTOR PADDLE", sub: "TWO ERAS. ONE ARENA.", action: "RETURN TO START")
        case .paused: gameMessage("PAUSED", sub: "MATCH SUSPENDED", action: "P / RETURN TO RESUME")
        case .finished:
            gameMessage(game.activeWinner == .left ? "PLAYER ONE WINS" : (game.engine.rules.players == .solo ? "CPU WINS" : "PLAYER TWO WINS"),
                        sub: "ARCADE SCORE  \(game.activeScore)", action: "RETURN TO REMATCH")
        case .playing: EmptyView()
        }
    }
    private func gameMessage(_ title: String, sub: String, action: String) -> some View {
        VStack(spacing: 13) {
            Text(title).font(.system(size: 27, weight: .black, design: .monospaced)).tracking(2)
            Text(sub).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(blue)
            Text(action).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Button(game.activePhase == .paused ? "RESUME" : "PLAY") {
                if game.activePhase == .paused { game.pauseOrResume() } else { game.startGame() }
            }.buttonStyle(.borderedProminent).tint(blue)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 15).fill(Color(red: 0.025, green: 0.04, blue: 0.08).opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(blue.opacity(0.6)))
    }
    private var telemetry: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("MATCH TELEMETRY").font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(blue)
            Divider().overlay(blue.opacity(0.3))
            HStack {
                meter("PLAYER 1", value: "\(game.activeLeft)", tint: blue)
                Spacer()
                meter(game.engine.rules.players == .solo ? "CPU" : "PLAYER 2", value: "\(game.activeRight)", tint: pink)
            }
            Divider().overlay(blue.opacity(0.3))
            meter("ARCADE POINTS", value: game.activeScore.formatted(), tint: .white)
            meter("PERSONAL BEST", value: game.bestScore.formatted(), tint: .yellow)
            Text("\(game.bestInitials)   ·   \(game.engine.rules.style.rawValue.uppercased())")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            Divider().overlay(blue.opacity(0.3))
            meter("CURRENT RALLY", value: "\(game.activeRally)", tint: blue)
            meter("LONGEST RALLY", value: "\(game.activeLongest)", tint: blue)
            meter("PADDLE HITS", value: "\(game.activeReturns)", tint: blue)
            if game.engine.rules.style == .modern {
                Divider().overlay(blue.opacity(0.3))
                Text("NEON RALLY · TABLE TENNIS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(pink)
                meter("GAMES WON", value: "\(game.neon.playerGames)  :  \(game.neon.opponentGames)", tint: .white)
                Text(game.neon.isDeuce ? "DEUCE · ALTERNATE EVERY SERVE" : "TWO SERVES EACH")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(blue)
                Text(game.neon.playerServing ? "PLAYER 1 SERVES" : "OPPONENT SERVES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Text("SHOT: \(game.selectedShot.rawValue.uppercased())")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
            Text("FUN CITY ARCADE").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.38))
            Text("MATCH DATA SAVED LOCALLY").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.38))
        }
        .padding(17).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.055, green: 0.075, blue: 0.115)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(blue.opacity(0.15)))
    }
    private func meter(_ name: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.system(size: 25, weight: .black, design: .monospaced)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
    }
    private func status(_ title: String, active: Bool) -> some View {
        HStack {
            Circle().fill(active ? pink : Color.gray.opacity(0.3)).frame(width: 7, height: 7)
            Text(title).foregroundStyle(active ? .white : .white.opacity(0.4))
        }.font(.system(size: 10, weight: .semibold, design: .monospaced))
    }
}

struct PaddleSettingsSheet: View {
    @ObservedObject var game: PaddleSession
    @State private var draft: PaddleRules
    @State private var newPresetName = ""
    @State private var selectedPreset: UUID? = nil
    init(game: PaddleSession) {
        self.game = game
        _draft = State(initialValue: game.engine.rules)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("CUSTOM GAME").font(.system(size: 23, weight: .black, design: .monospaced))
            Text("Gameplay options take effect when you apply and start a new match.").foregroundStyle(.secondary)
            Form {
                Picker("Cabinet", selection: $draft.style) {
                    ForEach(PaddleStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Players", selection: $draft.players) {
                    ForEach(PaddlePlayers.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("CPU skill", selection: $draft.skill) {
                    ForEach(PaddleSkill.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(draft.players == .local)
                Picker("First to", selection: $draft.pointsToWin) {
                    ForEach([5, 7, 11, 15, 21], id: \.self) { Text("\($0) points").tag($0) }
                }
                HStack {
                    Text("Ball speed"); Spacer()
                    Slider(value: Binding(get: { Double(draft.ballSpeedPercent) }, set: { draft.ballSpeedPercent = Int($0) }),
                           in: 60...160, step: 5).frame(width: 190)
                    Text("\(draft.ballSpeedPercent)%").frame(width: 50)
                }
                HStack {
                    Text("Paddle size"); Spacer()
                    Slider(value: Binding(get: { Double(draft.paddleSizePercent) }, set: { draft.paddleSizePercent = Int($0) }),
                           in: 65...145, step: 5).frame(width: 190)
                    Text("\(draft.paddleSizePercent)%").frame(width: 50)
                }
                Toggle("Mouse control for Player 1", isOn: $draft.mousePaddle)
                Text("Modern uses table-tennis rules; arcade powers are disabled.")
                    .font(.caption).foregroundStyle(.secondary)
                    .opacity(draft.style == .modern ? 1 : 0)
                Toggle("Sound effects", isOn: $draft.soundEnabled)
                Toggle("Enhanced visual effects", isOn: $draft.effectsEnabled).disabled(draft.style == .classic)
                Toggle("Reduced flashes", isOn: $draft.reducedFlash)
            }.formStyle(.grouped)
            Divider()
            Text("NAMED SETUPS").font(.system(size: 12, weight: .bold, design: .monospaced))
            HStack {
                TextField("Setup name", text: $newPresetName)
                Button("Save Setup") { game.storePreset(name: newPresetName, rules: draft) }
                    .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !game.presets.isEmpty {
                HStack {
                    Picker("Load Setup", selection: $selectedPreset) {
                        Text("Select setup").tag(Optional<UUID>.none)
                        ForEach(game.presets) { preset in Text(preset.name).tag(Optional(preset.id)) }
                    }
                    Button("Load") {
                        if let id = selectedPreset, let preset = game.presets.first(where: { $0.id == id }) { draft = preset.rules }
                    }.disabled(selectedPreset == nil)
                    Button("Delete") {
                        if let id = selectedPreset { game.deletePreset(id: id); selectedPreset = nil }
                    }.disabled(selectedPreset == nil)
                }
            }
            HStack {
                Button("Restore Defaults") { draft = PaddleRules() }
                Spacer()
                Button("Cancel") { game.showSettings = false }
                Button("Apply & Start") {
                    game.newGame(with: draft); game.startGame(); game.showSettings = false
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(25).frame(width: 590, height: 710).preferredColorScheme(.dark)
    }
}

struct PaddleSaveSheet: View {
    @ObservedObject var game: PaddleSession
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("SAVE / RESUME MATCH").font(.system(size: 22, weight: .black, design: .monospaced))
            Text("Five slots per cabinet. Restored games always reopen paused.").foregroundStyle(.secondary)
            ForEach(1...5, id: \.self) { index in
                HStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SLOT \(index)").font(.system(size: 12, weight: .bold, design: .monospaced))
                        if game.isModern, let save = game.readModernSlot(index) {
                            Text("Neon Rally · \(save.match.playerPoints)–\(save.match.opponentPoints) · \(save.savedOn.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else if !game.isModern, let save = game.readSlot(index) {
                            Text("Classic · \(save.engine.leftScore)–\(save.engine.rightScore) · \(save.savedOn.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else { Text("EMPTY").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Save") { game.save(index) }.disabled(game.activePhase == .ready)
                    Button("Resume") { game.resume(index) }.disabled(!game.hasSlot(index))
                    Button(role: .destructive) { game.delete(index) } label: { Image(systemName: "trash") }
                        .disabled(!game.hasSlot(index))
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            }
            HStack { Spacer(); Button("Done") { game.showSaves = false } }
        }
        .padding(25).frame(width: 650).preferredColorScheme(.dark)
    }
}
