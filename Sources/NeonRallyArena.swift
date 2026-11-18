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
                        let worldX = NeonRallyProjection.worldX(
                            pointerX: Double(point.x),
                            width: Double(proxy.size.width),
                            height: Double(proxy.size.height)
                        )
                        aimChanged(worldX)
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
                        Text("MOVE PADDLE TO INTERCEPT  ·  CLICK FOR AN EARLY SHOT")
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
        // A lower courtside camera fills the arena with the table while keeping
        // its near edge and serving paddle visible at the bottom of the view.
        // These values also drive accurate cursor-to-paddle projection.
        camera.camera.fieldOfViewInDegrees = Float(NeonRallyProjection.fieldOfViewDegrees)
        let cameraPosition = SIMD3<Float>(
            0, Float(NeonRallyProjection.eyeY), Float(NeonRallyProjection.eyeZ)
        )
        camera.position = cameraPosition
        camera.look(at: SIMD3<Float>(
            0, Float(NeonRallyProjection.lookY), Float(NeonRallyProjection.lookZ)
        ), from: cameraPosition, relativeTo: root)
        root.addChild(camera)

        let floor = modelBox("floor", size: [9.0, 0.08, 10.0],
                             pos: [0, -0.17, -0.2],
                             material: UnlitMaterial(color: NSColor(red: 0.014, green: 0.025, blue: 0.052, alpha: 1)))
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
        near.position = [Float(match.playerX), Float(TableMatch.paddleCenterY), Float(TableMatch.paddleContactZ)]
        root.addChild(near)
        let far = makePaddle("far-paddle", color: brightPink)
        far.position = [Float(match.opponentX), Float(TableMatch.paddleCenterY), -Float(TableMatch.paddleContactZ)]
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

        // Solid stadium architecture on both flanks. Keep everything beyond
        // the court and outside the contact geometry: scenery is decorative,
        // never a hidden gameplay collider.
        let frameMetal = SimpleMaterial(
            color: NSColor(red: 0.065, green: 0.10, blue: 0.17, alpha: 1), isMetallic: true)
        let seatDark = SimpleMaterial(
            color: NSColor(red: 0.045, green: 0.07, blue: 0.13, alpha: 1), isMetallic: false)
        let seatMid = SimpleMaterial(
            color: NSColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1), isMetallic: false)
        for side: Float in [-1, 1] {
            let sideColor = side < 0 ? brightCyan : brightPink
            let wing = side * 2.6
            // Stepped spectator terraces and readable individual seat backs.
            for rowIndex in 0..<4 {
                let lateral = side * (1.50 + Float(rowIndex) * 0.36)
                let rise = Float(rowIndex) * 0.20
                root.addChild(modelBox("stand-terrace", size: [0.37, 0.18, 4.2],
                    pos: [lateral, 0.18 + rise, -0.32],
                    material: rowIndex.isMultiple(of: 2) ? seatDark : seatMid))
                for seatIndex in 0..<8 {
                    let z = -2.05 + Float(seatIndex) * 0.49
                    root.addChild(modelBox("spectator-seat", size: [0.23, 0.24, 0.07],
                        pos: [lateral, 0.39 + rise, z], material: frameMetal))
                }
                root.addChild(modelBox("stand-edge-light",
                    size: [0.025, 0.022, 4.25],
                    pos: [lateral - side * 0.17, 0.30 + rise, -0.32],
                    material: UnlitMaterial(color: sideColor.withAlphaComponent(0.43))))
            }
            // Upright illuminated framework breaks up the black void.
            for z: Float in [-2.4, -0.9, 0.7] {
                root.addChild(modelBox("arena-column", size: [0.075, 1.9, 0.075],
                    pos: [wing, 1.02, z], material: frameMetal))
                root.addChild(modelBox("column-light", size: [0.024, 1.58, 0.025],
                    pos: [wing - side * 0.045, 1.05, z],
                    material: UnlitMaterial(color: sideColor.withAlphaComponent(0.72))))
            }
            root.addChild(modelBox("wall-display", size: [0.085, 0.34, 2.5],
                pos: [wing + side * 0.15, 1.68, -0.55],
                material: UnlitMaterial(color: sideColor.withAlphaComponent(0.30))))
        }
        // A distant back-wall band gives the table a clear venue horizon.
        root.addChild(modelBox("rear-arena-wall", size: [7.0, 1.85, 0.11],
            pos: [0, 0.85, -3.05], material: seatDark))
        root.addChild(modelBox("rear-score-ribbon", size: [4.8, 0.065, 0.13],
            pos: [0, 1.56, -2.97], material: UnlitMaterial(color: brightCyan.withAlphaComponent(0.55))))
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
        let paddle = Entity()
        paddle.name = name

        // An upright, thin elliptical racket instead of the original
        // oversized rectangular board. Layered translucent shells produce
        // a glass-like center and a crisp lit silhouette.
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: color.withAlphaComponent(0.56))
        glass.roughness = .init(floatLiteral: 0.13)
        glass.metallic = .init(floatLiteral: 0.18)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.54))

        let face = ModelEntity(mesh: .generateSphere(radius: 1),
                               materials: [glass])
        face.name = "paddle-face"
        face.scale = [Float(TableMatch.paddleHalfWidth),
                      Float(TableMatch.paddleHalfHeight), 0.014]
        paddle.addChild(face)

        // A modest illuminated oval rim preserves the paddle shape against
        // the dark table without turning it back into an opaque paddle.
        let edge = ModelEntity(mesh: .generateSphere(radius: 1),
                               materials: [UnlitMaterial(
                                   color: color.withAlphaComponent(0.39))])
        edge.name = "glass-edge"
        edge.scale = [Float(TableMatch.paddleHalfWidth) * 1.08,
                      Float(TableMatch.paddleHalfHeight) * 1.07, 0.010]
        edge.position = [0, 0, -0.009]
        paddle.addChild(edge)

        // Narrow neck and short opaque handle follow actual racket proportions.
        paddle.addChild(modelBox("paddle-neck", size: [0.045, 0.065, 0.025],
            pos: [0, -Float(TableMatch.paddleHalfHeight) - 0.009, 0],
            material: SimpleMaterial(color: color.withAlphaComponent(0.80),
                                     isMetallic: true)))
        paddle.addChild(modelBox("handle", size: [0.047, 0.145, 0.034],
            pos: [0, -Float(TableMatch.paddleHalfHeight) - 0.108, 0],
            material: SimpleMaterial(
                color: NSColor(red: 0.11, green: 0.14, blue: 0.18, alpha: 1),
                isMetallic: false)))
        return paddle
    }

    private func modelBox(_ name: String, size: SIMD3<Float>, pos: SIMD3<Float>,
                          material: any RealityKit.Material) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        entity.name = name
        entity.position = pos
        return entity
    }
}
