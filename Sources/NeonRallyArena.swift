import SwiftUI
import RealityKit
import AppKit

/// Procedural native RealityKit arena. The physics engine remains independent
/// of rendering; entities are only visual representations of the match state.
struct NeonRallyArena: View {
    let match: TableMatch
    let aimChanged: (Double) -> Void
    let stroke: () -> Void

    private let cyan = Color(red: 0.20, green: 0.91, blue: 1.0)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RealityView { content in
                    let root = buildArena()
                    content.add(root)
                } update: { content in
                    guard let root = content.entities.first(where: { $0.name == "neon-rally" }) else { return }
                    if let nearPaddle = root.findEntity(named: "near-paddle") {
                        nearPaddle.position.x = Float(match.playerX)
                    }
                    if let farPaddle = root.findEntity(named: "far-paddle") {
                        farPaddle.position.x = Float(match.opponentX)
                    }
                    if let ball = root.findEntity(named: "ball") {
                        ball.isEnabled = match.ball != nil
                        if let value = match.ball {
                            ball.position = SIMD3(Float(value.x), Float(value.y), Float(value.z))
                        }
                    }
                    if let contact = root.findEntity(named: "ball-shadow") {
                        contact.isEnabled = match.ball != nil
                        if let value = match.ball {
                            contact.position = SIMD3(Float(value.x), 0.792, Float(value.z))
                            let shrink = Float(max(0.15, 1 - (value.y - TableMatch.tableHeight) * 0.35))
                            contact.scale = SIMD3(repeating: shrink)
                        }
                    }
                }
                .background(Color(red: 0.012, green: 0.022, blue: 0.050))
                .onContinuousHover { phase in
                    if case .active(let point) = phase {
                        let x = min(1, max(0, Double(point.x / max(1, proxy.size.width))))
                        aimChanged(x * 2 - 1)
                    }
                }
                .onTapGesture(perform: stroke)
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NEON RALLY  /  WORLD TOUR")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .tracking(1.2).foregroundStyle(cyan)
                            Text("3D TABLE TENNIS  ·  11 POINT GAMES")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.64))
                        }
                        Spacer()
                        Text(match.banner)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 270, alignment: .trailing)
                    }
                    .padding(17)
                    Spacer()
                    HStack(spacing: 14) {
                        Image(systemName: "hand.point.up.left.fill")
                        Text("MOVE POINTER TO POSITION PADDLE  ·  CLICK TO RETURN")
                        Spacer()
                        Text("SPACE TO SERVE")
                    }
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.black.opacity(0.36))
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func buildArena() -> Entity {
        let root = Entity()
        root.name = "neon-rally"

        let camera = PerspectiveCamera()
        camera.name = "arena-camera"
        camera.position = SIMD3<Float>(0, 2.65, 3.85)
        camera.look(at: SIMD3<Float>(0, 0.82, -0.10),
                    from: SIMD3<Float>(0, 2.65, 3.85), relativeTo: root)
        root.addChild(camera)

        let floor = modelBox("floor", size: [9.0, 0.08, 10.0],
                             pos: [0, -0.17, -0.2],
                             material: SimpleMaterial(color: NSColor(red: 0.025, green: 0.038, blue: 0.082, alpha: 1), isMetallic: false))
        root.addChild(floor)

        let platform = modelBox("platform", size: [2.24, 0.10, 3.34],
                                pos: [0, 0.14, 0],
                                material: SimpleMaterial(color: NSColor(red: 0.075, green: 0.08, blue: 0.14, alpha: 1), isMetallic: true))
        root.addChild(platform)

        let top = modelBox("table-surface", size: [1.525, 0.045, 2.74],
                           pos: [0, 0.755, 0],
                           material: SimpleMaterial(color: NSColor(red: 0.022, green: 0.18, blue: 0.22, alpha: 1), isMetallic: true))
        root.addChild(top)

        // Table legs and supports, deliberately opaque and solid.
        for x: Float in [-0.56, 0.56] {
            for z: Float in [-1.05, 1.05] {
                root.addChild(modelBox("leg", size: [0.075, 0.58, 0.075], pos: [x, 0.43, z],
                                       material: SimpleMaterial(color: NSColor.darkGray, isMetallic: true)))
            }
        }

        let brightCyan = NSColor(red: 0.20, green: 0.90, blue: 1, alpha: 1)
        let brightPink = NSColor(red: 1.0, green: 0.23, blue: 0.63, alpha: 1)
        let white = NSColor(white: 0.92, alpha: 1)

        // Regulation table markings and split halves.
        for x: Float in [-0.747, 0.747] {
            root.addChild(modelBox("sideline", size: [0.012, 0.006, 2.725],
                                   pos: [x, 0.782, 0],
                                   material: UnlitMaterial(color: white)))
        }
        for z: Float in [-1.356, 1.356] {
            root.addChild(modelBox("endline", size: [1.512, 0.006, 0.012],
                                   pos: [0, 0.782, z],
                                   material: UnlitMaterial(color: white)))
        }
        root.addChild(modelBox("centerline", size: [0.008, 0.006, 2.69],
                               pos: [0, 0.783, 0],
                               material: UnlitMaterial(color: white.withAlphaComponent(0.6))))

        // Distinct blue near court and magenta far court perimeter.
        root.addChild(modelBox("front-glow", size: [1.55, 0.016, 0.025],
                               pos: [0, 0.772, 1.385],
                               material: UnlitMaterial(color: brightCyan)))
        root.addChild(modelBox("back-glow", size: [1.55, 0.016, 0.025],
                               pos: [0, 0.772, -1.385],
                               material: UnlitMaterial(color: brightPink)))

        // Net is visibly solid, with a white cord and alternating vertical
        // posts. Thin opaque bars create a readable mesh from the camera.
        root.addChild(modelBox("net-top", size: [1.67, 0.018, 0.018],
                               pos: [0, 0.915, 0],
                               material: UnlitMaterial(color: white)))
        for index in 0...30 {
            let x = Float(index) / 30.0 * 1.6 - 0.8
            root.addChild(modelBox("net-thread", size: [0.004, 0.143, 0.005],
                                   pos: [x, 0.848, 0],
                                   material: UnlitMaterial(color: brightCyan.withAlphaComponent(0.7))))
        }
        for index in 0...7 {
            let y: Float = 0.782 + Float(index) * 0.019
            root.addChild(modelBox("net-thread", size: [1.61, 0.003, 0.004],
                                   pos: [0, y, 0],
                                   material: UnlitMaterial(color: brightCyan.withAlphaComponent(0.6))))
        }
        for x: Float in [-0.82, 0.82] {
            root.addChild(modelBox("net-post", size: [0.035, 0.20, 0.035],
                                   pos: [x, 0.858, 0],
                                   material: SimpleMaterial(color: NSColor.lightGray, isMetallic: true)))
        }

        let near = makePaddle("near-paddle", color: brightCyan)
        near.position = [Float(match.playerX), 1.01, 1.47]
        root.addChild(near)
        let far = makePaddle("far-paddle", color: brightPink)
        far.position = [Float(match.opponentX), 1.01, -1.47]
        root.addChild(far)

        let ball = ModelEntity(mesh: .generateSphere(radius: 0.024),
                               materials: [UnlitMaterial(color: NSColor.white)])
        ball.name = "ball"
        ball.position = [0, 0.95, 0]
        ball.isEnabled = match.ball != nil
        root.addChild(ball)

        let shadow = ModelEntity(mesh: .generateSphere(radius: 0.028),
                                 materials: [UnlitMaterial(color: NSColor(white: 0.02, alpha: 1))])
        shadow.name = "ball-shadow"
        shadow.position = [0, 0.792, 0]
        shadow.scale = [1.0, 0.04, 1.0]
        shadow.isEnabled = match.ball != nil
        root.addChild(shadow)

        for x: Float in [-1.8, 1.8] {
            let bar = modelBox("arena-lights", size: [0.08, 0.07, 3.6],
                                pos: [x, 0.24, 0],
                                material: UnlitMaterial(color: x < 0 ? brightCyan : brightPink))
            root.addChild(bar)
        }
        for z: Float in [-2.4, 2.4] {
            let bar = modelBox("arena-lights", size: [3.65, 0.07, 0.08],
                                pos: [0, 0.24, z],
                                material: UnlitMaterial(color: z < 0 ? brightPink : brightCyan))
            root.addChild(bar)
        }
        return root
    }

    private func makePaddle(_ name: String, color: NSColor) -> Entity {
        let base = Entity()
        base.name = name
        let head = ModelEntity(mesh: .generateBox(size: [0.27, 0.29, 0.025]),
                               materials: [SimpleMaterial(color: color, isMetallic: true)])
        head.name = "paddle-face"
        base.addChild(head)
        let handle = modelBox("handle", size: [0.058, 0.15, 0.052],
                              pos: [0, -0.21, 0],
                              material: SimpleMaterial(color: NSColor.black, isMetallic: false))
        base.addChild(handle)
        return base
    }

    private func modelBox(_ name: String, size: SIMD3<Float>, pos: SIMD3<Float>,
                          material: any Material) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        entity.name = name
        entity.position = pos
        return entity
    }
}
