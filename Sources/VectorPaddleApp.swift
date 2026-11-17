import AppKit
import SwiftUI

@main
struct VectorPaddleApp: App {
    var body: some Scene {
        WindowGroup("Vector Paddle") {
            PaddleWindow().frame(minWidth: 980, minHeight: 680).preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { CommandGroup(replacing: .newItem) {} }
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

@MainActor
final class PaddleSession: ObservableObject {
    @Published var engine = PaddleEngine()
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
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, NSApp.isActive else { return event }
            return self.processKey(event) ? nil : event
        }
    }

    deinit {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    var bestScore: Int { engine.rules.style == .classic ? bestClassic : bestModern }
    var bestInitials: String { engine.rules.style == .classic ? bestInitialsClassic : bestInitialsModern }

    private func processKey(_ event: NSEvent) -> Bool {
        guard !showSettings && !showSaves && !showInitials else { return false }
        let code = event.keyCode
        let controlledKeys: Set<UInt16> = [13, 1, 126, 125, 35, 15, 36, 76, 49]
        guard controlledKeys.contains(code) else { return false }
        if event.type == .keyUp { keys.remove(code); return true }
        keys.insert(code)
        if event.isARepeat { return true }
        switch code {
        case 35: engine.pauseOrResume(); lastTick = Date()
        case 15: newGame()
        case 36, 76, 49:
            switch engine.phase {
            case .ready, .finished: startGame()
            case .paused: engine.pauseOrResume(); lastTick = Date()
            case .playing: break
            }
        default: break
        }
        return true
    }
    func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
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
        if engine.phase == .finished { newGame() }
        engine.start()
        lastTick = Date()
    }
    func newGame(with rules: PaddleRules? = nil) {
        keys.removeAll()
        engine.reset(using: rules ?? engine.rules)
        promptedThisMatch = false
        lastTick = Date()
        mouseY = nil
        if let data = try? JSONEncoder().encode(engine.rules) {
            preferences.set(data, forKey: "VectorPaddle.Rules.v1")
        }
    }
    func pauseOrResume() { engine.pauseOrResume(); lastTick = Date() }
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
        let score = engine.arcadeScore
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
        guard (1...5).contains(slot), engine.phase != .ready else { return }
        let save = PaddleSavedMatch(savedOn: Date(), engine: engine)
        guard let encoded = try? JSONEncoder().encode(save) else { return }
        preferences.set(encoded, forKey: slotKey(slot))
        savedRevision += 1
    }
    func readSlot(_ slot: Int) -> PaddleSavedMatch? {
        guard (1...5).contains(slot), let data = preferences.data(forKey: slotKey(slot)) else { return nil }
        return try? JSONDecoder().decode(PaddleSavedMatch.self, from: data)
    }
    func resume(_ slot: Int) {
        guard var save = readSlot(slot) else { return }
        save.engine.phase = .paused
        engine = save.engine
        promptedThisMatch = false
        lastTick = Date()
        showSaves = false
        keys.removeAll()
    }
    func delete(_ slot: Int) {
        preferences.removeObject(forKey: slotKey(slot))
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
                Button(game.engine.phase == .paused ? "Resume" : "Pause") { game.pauseOrResume() }
                    .disabled(game.engine.phase != .playing && game.engine.phase != .paused)
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
                Text("FIRST TO \(game.engine.rules.winningPoints)").foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 22).frame(height: 44)
            .background(Color(red: 0.055, green: 0.076, blue: 0.119))

            GeometryReader { geometry in
                HStack(spacing: 18) {
                    PaddleArena(engine: game.engine) { normalizedY in game.mouseY = normalizedY }
                        .aspectRatio(1.52, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(blue.opacity(game.engine.rules.style == .modern ? 0.5 : 0.2)))
                        .overlay { statusOverlay }
                    telemetry.frame(width: 220)
                }
                .padding(18).frame(width: geometry.size.width, height: geometry.size.height)
            }
            HStack(spacing: 22) {
                Text("W / S  LEFT PADDLE")
                Text("↑ / ↓  RIGHT PADDLE (2P)")
                Text("RETURN / SPACE  START")
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
                Text("\(game.engine.arcadeScore) POINTS  ·  \(game.engine.rules.style.rawValue.uppercased())")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                TextField("THREE INITIALS", text: $game.initialsDraft).frame(width: 160).textFieldStyle(.roundedBorder)
                Button("Record Score") { game.recordInitials() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(32).frame(width: 400).preferredColorScheme(.dark)
        }
    }
    @ViewBuilder private var statusOverlay: some View {
        switch game.engine.phase {
        case .ready: gameMessage("VECTOR PADDLE", sub: "TWO ERAS. ONE ARENA.", action: "RETURN TO START")
        case .paused: gameMessage("PAUSED", sub: "MATCH SUSPENDED", action: "P / RETURN TO RESUME")
        case .finished:
            gameMessage(game.engine.winner == .left ? "PLAYER ONE WINS" : (game.engine.rules.players == .solo ? "CPU WINS" : "PLAYER TWO WINS"),
                        sub: "ARCADE SCORE  \(game.engine.arcadeScore)", action: "RETURN TO REMATCH")
        case .playing: EmptyView()
        }
    }
    private func gameMessage(_ title: String, sub: String, action: String) -> some View {
        VStack(spacing: 13) {
            Text(title).font(.system(size: 27, weight: .black, design: .monospaced)).tracking(2)
            Text(sub).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(blue)
            Text(action).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Button(game.engine.phase == .paused ? "RESUME" : "PLAY") {
                if game.engine.phase == .paused { game.pauseOrResume() } else { game.startGame() }
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
                meter("PLAYER 1", value: "\(game.engine.leftScore)", tint: blue)
                Spacer()
                meter(game.engine.rules.players == .solo ? "CPU" : "PLAYER 2", value: "\(game.engine.rightScore)", tint: pink)
            }
            Divider().overlay(blue.opacity(0.3))
            meter("ARCADE POINTS", value: game.engine.arcadeScore.formatted(), tint: .white)
            meter("PERSONAL BEST", value: game.bestScore.formatted(), tint: .yellow)
            Text("\(game.bestInitials)   ·   \(game.engine.rules.style.rawValue.uppercased())")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            Divider().overlay(blue.opacity(0.3))
            meter("CURRENT RALLY", value: "\(game.engine.rally)", tint: blue)
            meter("LONGEST RALLY", value: "\(game.engine.longestRally)", tint: blue)
            meter("PADDLE HITS", value: "\(game.engine.bounceCount)", tint: blue)
            if game.engine.rules.style == .modern {
                Divider().overlay(blue.opacity(0.3))
                Text("ARENA SYSTEMS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(pink)
                status("WIDE PADDLE", active: max(game.engine.leftWideFor, game.engine.rightWideFor) > 0)
                status("TIME DILATION", active: game.engine.slowFor > 0)
                status("SPEED BOOST", active: game.engine.boostFor > 0)
                status("MULTIBALL", active: game.engine.balls.count > 1)
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
                Toggle("Modern power-ups", isOn: $draft.powerupsEnabled).disabled(draft.style == .classic)
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
            Text("Five local slots. Restored games always reopen paused.").foregroundStyle(.secondary)
            ForEach(1...5, id: \.self) { index in
                HStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SLOT \(index)").font(.system(size: 12, weight: .bold, design: .monospaced))
                        if let save = game.readSlot(index) {
                            Text("\(save.engine.rules.style.rawValue) · \(save.engine.leftScore)–\(save.engine.rightScore) · \(save.savedOn.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else { Text("EMPTY").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Save") { game.save(index) }.disabled(game.engine.phase == .ready)
                    Button("Resume") { game.resume(index) }.disabled(game.readSlot(index) == nil)
                    Button(role: .destructive) { game.delete(index) } label: { Image(systemName: "trash") }
                        .disabled(game.readSlot(index) == nil)
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            }
            HStack { Spacer(); Button("Done") { game.showSaves = false } }
        }
        .padding(25).frame(width: 650).preferredColorScheme(.dark)
    }
}
