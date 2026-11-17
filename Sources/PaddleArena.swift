import SwiftUI

// Classic and Modern use identical normalized gameplay coordinates.
struct PaddleArena: View {
    let engine: PaddleEngine
    let onMouse: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                let screen = CGRect(origin: .zero, size: size)
                let w = size.width, h = size.height
                let modern = engine.rules.style == .modern
                if modern {
                    context.fill(Path(screen), with: .linearGradient(
                        Gradient(colors: [Color(red: 0.020, green: 0.07, blue: 0.14),
                                          Color(red: 0.025, green: 0.035, blue: 0.075),
                                          Color(red: 0.045, green: 0.025, blue: 0.09)]),
                        startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
                    modernBackground(&context, size: size)
                } else {
                    context.fill(Path(screen), with: .color(.black))
                    classicField(&context, size: size)
                }
                centerDivider(&context, size: size, modern: modern)
                drawScore(&context, size: size, modern: modern)
                if modern, let pickup = engine.pickup {
                    drawPickup(&context, pickup: pickup, size: size)
                }
                drawPaddle(&context, side: .left, size: size, modern: modern)
                drawPaddle(&context, side: .right, size: size, modern: modern)
                for ball in engine.balls {
                    drawBall(&context, ball: ball, size: size, modern: modern)
                }
            }
            .onContinuousHover { hover in
                switch hover {
                case .active(let point):
                    onMouse(min(1, max(0, Double(point.y / max(1, geometry.size.height)))))
                case .ended: break
                }
            }
        }
    }

    private func classicField(_ context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let edge = Path(CGRect(x: w * 0.015, y: h * 0.032, width: w * 0.97, height: h * 0.936))
        context.stroke(edge, with: .color(.white.opacity(0.35)), lineWidth: 1.3)
        for x in [0.028, 0.972] {
            let wall = Path(CGRect(x: w * x, y: h * 0.058, width: w * 0.003, height: h * 0.884))
            context.fill(wall, with: .color(.white.opacity(0.16)))
        }
    }

    private func modernBackground(_ context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let cyan = Color(red: 0.16, green: 0.85, blue: 1)
        let pink = Color(red: 1.0, green: 0.20, blue: 0.62)
        let plate = Path(roundedRect: CGRect(x: w * 0.014, y: h * 0.025,
                      width: w * 0.972, height: h * 0.95), cornerRadius: 16)
        context.fill(plate, with: .color(Color(red: 0.018, green: 0.045, blue: 0.084)))
        context.stroke(plate, with: .color(cyan.opacity(0.5)), lineWidth: 2)
        for i in 0..<22 {
            let x = CGFloat(i) / 21 * w
            var line = Path()
            line.move(to: CGPoint(x: x, y: h * 0.055))
            line.addLine(to: CGPoint(x: x, y: h * 0.945))
            context.stroke(line, with: .color(cyan.opacity(i % 3 == 0 ? 0.13 : 0.056)), lineWidth: 0.7)
        }
        for i in 0..<16 {
            let y = h * (0.055 + CGFloat(i) * 0.89 / 15)
            var line = Path()
            line.move(to: CGPoint(x: w * 0.035, y: y))
            line.addLine(to: CGPoint(x: w * 0.965, y: y))
            context.stroke(line, with: .color(cyan.opacity(i % 3 == 0 ? 0.11 : 0.05)), lineWidth: 0.7)
        }
        let leftZone = Path(CGRect(x: w * 0.02, y: h * 0.042, width: w * 0.20, height: h * 0.915))
        let rightZone = Path(CGRect(x: w * 0.78, y: h * 0.042, width: w * 0.20, height: h * 0.915))
        context.fill(leftZone, with: .linearGradient(Gradient(colors: [cyan.opacity(0.10), .clear]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w * 0.22, y: 0)))
        context.fill(rightZone, with: .linearGradient(Gradient(colors: [.clear, pink.opacity(0.10)]),
            startPoint: CGPoint(x: w * 0.78, y: 0), endPoint: CGPoint(x: w, y: 0)))
        let nearLeft = Path(CGRect(x: w * 0.034, y: h * 0.06, width: 3, height: h * 0.88))
        let nearRight = Path(CGRect(x: w * 0.966 - 3, y: h * 0.06, width: 3, height: h * 0.88))
        context.fill(nearLeft, with: .color(cyan.opacity(0.78)))
        context.fill(nearRight, with: .color(pink.opacity(0.78)))
        for y in [0.052, 0.948] {
            let rail = Path(CGRect(x: w * 0.035, y: h * y - 2, width: w * 0.93, height: 4))
            context.fill(rail, with: .linearGradient(
                Gradient(colors: [cyan, Color(red: 0.5, green: 0.4, blue: 1), pink]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: 0)))
            if engine.rules.effectsEnabled {
                context.drawLayer { glow in
                    glow.addFilter(.shadow(color: cyan.opacity(0.55), radius: 9))
                    glow.fill(rail, with: .color(cyan.opacity(0.35)))
                }
            }
        }
        let cornerLabel = Text("F U N  C I T Y  /  A R E N A   0 1")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(cyan.opacity(0.5))
        context.draw(cornerLabel, at: CGPoint(x: w * 0.5, y: h * 0.972), anchor: .center)
    }

    private func centerDivider(_ context: inout GraphicsContext, size: CGSize, modern: Bool) {
        let w = size.width, h = size.height
        for index in 0..<20 {
            let dash = Path(CGRect(x: w * 0.498, y: h * (0.06 + CGFloat(index) * 0.045),
                                   width: w * (modern ? 0.004 : 0.007), height: h * 0.023))
            context.fill(dash, with: .color(modern ? Color.cyan.opacity(0.25) : .white.opacity(0.75)))
        }
        if modern {
            let ring = Path(ellipseIn: CGRect(x: w * 0.44, y: h * 0.42, width: w * 0.12, height: h * 0.16))
            context.stroke(ring, with: .color(.cyan.opacity(0.15)), lineWidth: 1)
        }
    }

    private func drawScore(_ context: inout GraphicsContext, size: CGSize, modern: Bool) {
        let w = size.width, h = size.height
        let leftColor: Color = modern ? Color(red: 0.22, green: 0.9, blue: 1) : .white
        let rightColor: Color = modern ? Color(red: 1, green: 0.35, blue: 0.65) : .white
        let font = Font.system(size: min(w * 0.085, 66), weight: .black, design: .monospaced)
        context.draw(Text("\(engine.leftScore)").font(font).foregroundColor(leftColor.opacity(0.85)),
                     at: CGPoint(x: w * 0.40, y: h * 0.13), anchor: .center)
        context.draw(Text("\(engine.rightScore)").font(font).foregroundColor(rightColor.opacity(0.85)),
                     at: CGPoint(x: w * 0.60, y: h * 0.13), anchor: .center)
    }

    private func drawPaddle(_ context: inout GraphicsContext, side: PaddleSide,
                            size: CGSize, modern: Bool) {
        let w = size.width, h = size.height
        let x = w * (side == .left ? 0.064 : 0.936)
        let centerY = h * (side == .left ? engine.leftY : engine.rightY)
        let half = h * engine.halfHeight(for: side)
        let width = w * (modern ? 0.018 : 0.014)
        let body = Path(roundedRect: CGRect(x: x-width/2, y: centerY-half,
                                          width: width, height: half*2), cornerRadius: modern ? 5 : 0)
        if modern {
            let bright = side == .left ? Color(red: 0.25, green: 0.92, blue: 1) : Color(red: 1, green: 0.29, blue: 0.63)
            context.fill(body, with: .color(Color(red: 0.09, green: 0.15, blue: 0.23)))
            context.stroke(body, with: .color(bright), lineWidth: 2)
            let inset = Path(roundedRect: CGRect(x: x-width*0.19, y: centerY-half+7,
                           width: width*0.38, height: max(2,half*2-14)), cornerRadius: 2)
            context.fill(inset, with: .color(bright.opacity(0.85)))
            if engine.rules.effectsEnabled {
                context.drawLayer { glow in
                    glow.addFilter(.shadow(color: bright.opacity(0.75), radius: engine.rules.reducedFlash ? 3 : 12))
                    glow.stroke(body, with: .color(bright.opacity(0.48)), lineWidth: 3)
                }
            }
        } else {
            context.fill(body, with: .color(.white))
        }
    }

    private func drawBall(_ context: inout GraphicsContext, ball: PaddleBall,
                          size: CGSize, modern: Bool) {
        let w = size.width, h = size.height
        let point = CGPoint(x: w * ball.x, y: h * ball.y)
        let rad = min(w, h) * (modern ? 0.013 : 0.012)
        if modern {
            let glow = ball.vx > 0 ? Color(red: 0.24, green: 0.92, blue: 1) : Color(red: 1, green: 0.39, blue: 0.74)
            if engine.rules.effectsEnabled {
                for index in (1...8).reversed() {
                    let t = Double(index) * 0.014
                    let p = CGPoint(x: w * (ball.x - ball.vx * t), y: h * (ball.y - ball.vy * t))
                    let r = rad * CGFloat(1 - Double(index) / 12)
                    let trail = Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: 2*r, height: 2*r))
                    context.fill(trail, with: .color(glow.opacity((1 - Double(index)/9) * 0.45)))
                }
            }
            let halo = Path(ellipseIn: CGRect(x: point.x-rad*2.2, y: point.y-rad*2.2,
                                             width: rad*4.4, height: rad*4.4))
            context.fill(halo, with: .color(glow.opacity(engine.rules.reducedFlash ? 0.10 : 0.19)))
            let core = Path(ellipseIn: CGRect(x: point.x-rad, y: point.y-rad,
                                             width: rad*2, height: rad*2))
            context.fill(core, with: .color(.white))
            context.stroke(core, with: .color(glow), lineWidth: 2.5)
        } else {
            let ballPath = Path(CGRect(x: point.x-rad, y: point.y-rad,
                                      width: rad*2, height: rad*2))
            context.fill(ballPath, with: .color(.white))
        }
    }

    private func drawPickup(_ context: inout GraphicsContext, pickup: PaddlePickup, size: CGSize) {
        let w = size.width, h = size.height
        let center = CGPoint(x: w * pickup.x, y: h * pickup.y)
        let rad = min(w, h) * 0.035
        let pulse = engine.rules.reducedFlash ? 1.0 : 1.0 + 0.07 * sin(engine.elapsed * 5)
        let diameter = rad * 2 * pulse
        let box = CGRect(x: center.x - diameter/2, y: center.y - diameter/2,
                         width: diameter, height: diameter)
        let tint = Color(red: 1, green: 0.78, blue: 0.30)
        let circle = Path(ellipseIn: box)
        context.fill(circle, with: .color(Color(red: 0.20, green: 0.14, blue: 0.05)))
        context.stroke(circle, with: .color(tint), lineWidth: 3)
        let name = String(pickup.kind.rawValue.prefix(1))
        context.draw(Text(name).font(.system(size: max(10, rad*0.77), weight: .black, design: .monospaced))
            .foregroundColor(tint), at: center, anchor: .center)
    }
}
