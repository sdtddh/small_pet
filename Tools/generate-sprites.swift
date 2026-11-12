// generate-sprites.swift —— 產生「佔位用」的向量風格寵物素材。
//
// 用法（在專案根目錄）：
//     swift Tools/generate-sprites.swift
//
// 會覆寫 Sources/SmallPet/Resources/ 底下的 body/、outfits/ 與 manifest.json。
// 之後若改用自己畫的圖，就不需要再跑這支程式，直接替換那些 PNG 即可。
//
// 做法：先定義一個「姿勢」(Pose)，描述身體壓扁程度、前傾角度、腳的位置、
// 眼睛表情…，每個動作的每一格都是一組不同的姿勢。本體和服裝用「同一組姿勢」
// 畫在同尺寸的透明畫布上，所以疊起來永遠對得齊。
import AppKit

// MARK: - 畫布設定

let canvas: CGFloat = 112        // 畫布大小（點），要跟 manifest 的 canvas 一致
let scale: CGFloat = 2           // 輸出 2 倍解析度，Retina 螢幕才清晰
let offsetX: CGFloat = 8         // 角色是以 96 寬設計的，往右移一點置中
let ground: CGFloat = 4          // 腳底的 y 座標
let pivot = CGPoint(x: 48, y: ground)   // 壓扁 / 前傾的支點（腳底中央）

let outputRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/SmallPet/Resources")

// MARK: - 顏色

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: a)
}

let outline = hex(0x5B3A29)
let fur = hex(0xF6B26B)
let furDark = hex(0xE39B4F)
let belly = hex(0xFFE6C7)
let pink = hex(0xF4A6A6)
let cheek = hex(0xF48A8A, 0.55)
let eyeColor = hex(0x3B2418)
let white = hex(0xFFFFFF)

// MARK: - 姿勢

enum Eyes { case open, closed, happy, wide }

struct Pose {
    var bodyY: CGFloat = 0          // 上半身（身體+頭+尾巴）整體上下位移
    var squashX: CGFloat = 1        // 水平伸縮（>1 變胖）
    var squashY: CGFloat = 1        // 垂直伸縮（<1 壓扁）
    var lean: CGFloat = 0           // 前傾角度（弧度），正值往臉的方向傾
    var headDX: CGFloat = 0
    var headDY: CGFloat = 0
    var frontFoot = CGPoint.zero    // 前腳位移
    var backFoot = CGPoint.zero     // 後腳位移
    var tail: CGFloat = 0           // 尾巴擺動角度
    var eyes: Eyes = .open
    var mouthOpen = false
    var zzz = 0                     // 睡覺時頭上的 z 數量
}

// MARK: - 繪圖小工具

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), transform: nil)
}

func polygon(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts)
    p.closeSubpath()
    return p
}

// 填色 + 描邊，向量風格的基本筆觸。
func shape(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, stroke: Bool = true, lineWidth: CGFloat = 2.2) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
    if stroke {
        ctx.addPath(path)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()
    }
}

func line(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, width: CGFloat) {
    ctx.addPath(path)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.strokePath()
}

// 在一組座標變換內畫東西，畫完自動還原。
func withState(_ ctx: CGContext, _ transform: (CGContext) -> Void, _ draw: () -> Void) {
    ctx.saveGState()
    transform(ctx)
    draw()
    ctx.restoreGState()
}

// 上半身的座標變換：上下位移 → 以腳底為支點前傾、壓扁。
func upper(_ p: Pose) -> (CGContext) -> Void {
    { ctx in
        ctx.translateBy(x: 0, y: p.bodyY)
        ctx.translateBy(x: pivot.x, y: pivot.y)
        ctx.rotate(by: -p.lean)
        ctx.scaleBy(x: p.squashX, y: p.squashY)
        ctx.translateBy(x: -pivot.x, y: -pivot.y)
    }
}

// 頭部的座標變換：在上半身之上再加頭的位移。服裝的帽子、眼鏡也用這個。
func head(_ p: Pose) -> (CGContext) -> Void {
    { ctx in
        upper(p)(ctx)
        ctx.translateBy(x: p.headDX, y: p.headDY)
    }
}

// 頭部各部位的基準座標（角色面向右）。
let headCenter = CGPoint(x: 52, y: 54)
let eyeBack = CGPoint(x: 47, y: 57)
let eyeFront = CGPoint(x: 62, y: 57)

// MARK: - 本體

func drawBody(_ ctx: CGContext, _ p: Pose) {
    // 尾巴（最後面）
    withState(ctx, { c in
        upper(p)(c)
        c.translateBy(x: 30, y: 24)
        c.rotate(by: p.tail)
    }) {
        let tail = CGMutablePath()
        tail.move(to: .zero)
        tail.addQuadCurve(to: CGPoint(x: -14, y: 24), control: CGPoint(x: -20, y: 2))
        ctx.setLineCap(.round)
        line(ctx, tail, outline, width: 9.5)
        line(ctx, tail, fur, width: 5.5)
    }

    // 後腳（在身體後面，腳不跟著上半身彈跳，才會黏在地上）
    shape(ctx, ellipse(40 + p.backFoot.x, 9 + p.backFoot.y, 15, 10), furDark)

    // 身體與肚子
    withState(ctx, upper(p)) {
        shape(ctx, ellipse(47, 28, 42, 32), fur)
        shape(ctx, ellipse(53, 25, 22, 18), belly, stroke: false)
    }

    // 前腳
    shape(ctx, ellipse(56 + p.frontFoot.x, 9 + p.frontFoot.y, 15, 10), fur)

    // 頭
    withState(ctx, head(p)) {
        // 耳朵（先畫，讓頭蓋住耳朵根部）
        let backEar = polygon([CGPoint(x: 33, y: 62), CGPoint(x: 36, y: 84), CGPoint(x: 50, y: 71)])
        let frontEar = polygon([CGPoint(x: 56, y: 71), CGPoint(x: 70, y: 84), CGPoint(x: 72, y: 62)])
        shape(ctx, backEar, fur)
        shape(ctx, frontEar, fur)
        shape(ctx, polygon([CGPoint(x: 37, y: 68), CGPoint(x: 38, y: 79), CGPoint(x: 46, y: 72)]), pink, stroke: false)
        shape(ctx, polygon([CGPoint(x: 60, y: 72), CGPoint(x: 68, y: 79), CGPoint(x: 69, y: 68)]), pink, stroke: false)

        shape(ctx, ellipse(headCenter.x, headCenter.y, 46, 40), fur)

        // 臉頰
        shape(ctx, ellipse(42, 49, 8, 5), cheek, stroke: false)
        shape(ctx, ellipse(68, 49, 8, 5), cheek, stroke: false)

        drawEye(ctx, eyeBack, p.eyes)
        drawEye(ctx, eyeFront, p.eyes)

        // 鼻子與嘴巴
        shape(ctx, polygon([CGPoint(x: 53, y: 52), CGPoint(x: 57, y: 52), CGPoint(x: 55, y: 50)]), pink, lineWidth: 1.2)
        ctx.setLineCap(.round)
        if p.mouthOpen {
            shape(ctx, ellipse(55, 46, 6, 5), hex(0xC8504F), lineWidth: 1.6)
        } else {
            let mouth = CGMutablePath()
            mouth.move(to: CGPoint(x: 51, y: 48))
            mouth.addQuadCurve(to: CGPoint(x: 55, y: 49), control: CGPoint(x: 53, y: 46))
            mouth.addQuadCurve(to: CGPoint(x: 59, y: 48), control: CGPoint(x: 57, y: 46))
            line(ctx, mouth, outline, width: 1.6)
        }
    }

    // 睡覺的 z
    for i in 0..<p.zzz {
        drawZ(ctx, at: CGPoint(x: 70 + CGFloat(i) * 9, y: 62 + CGFloat(i) * 11), size: 6 + CGFloat(i) * 2)
    }
}

func drawEye(_ ctx: CGContext, _ c: CGPoint, _ eyes: Eyes) {
    ctx.setLineCap(.round)
    switch eyes {
    case .open:
        shape(ctx, ellipse(c.x, c.y, 5.5, 7.5), eyeColor, stroke: false)
        shape(ctx, ellipse(c.x + 1, c.y + 1.8, 2, 2), white, stroke: false)
    case .wide:
        shape(ctx, ellipse(c.x, c.y, 9, 10), white, lineWidth: 1.6)
        shape(ctx, ellipse(c.x + 1, c.y, 3.5, 4), eyeColor, stroke: false)
    case .closed:
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x - 3.5, y: c.y))
        path.addQuadCurve(to: CGPoint(x: c.x + 3.5, y: c.y), control: CGPoint(x: c.x, y: c.y - 3.5))
        line(ctx, path, eyeColor, width: 2)
    case .happy:
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x - 3.5, y: c.y - 1))
        path.addQuadCurve(to: CGPoint(x: c.x + 3.5, y: c.y - 1), control: CGPoint(x: c.x, y: c.y + 4))
        line(ctx, path, eyeColor, width: 2)
    }
}

func drawZ(_ ctx: CGContext, at o: CGPoint, size s: CGFloat) {
    let z = CGMutablePath()
    z.addLines(between: [CGPoint(x: o.x, y: o.y + s), CGPoint(x: o.x + s, y: o.y + s),
                         CGPoint(x: o.x, y: o.y), CGPoint(x: o.x + s, y: o.y)])
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    line(ctx, z, hex(0x6C8EBF), width: 2)
}

// MARK: - 服裝（每件都用跟本體相同的姿勢畫）

struct Outfit {
    let id: String
    let name: String
    let slot: String
    let draw: (CGContext, Pose) -> Void
}

let outfits: [Outfit] = [
    Outfit(id: "cap", name: "棒球帽", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            let red = hex(0xE8574F)
            // 帽沿（朝臉的方向）
            shape(ctx, ellipse(70, 69, 24, 6), hex(0xC9443D))
            // 帽頂：半個橢圓
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: 33, y: 67))
            dome.addCurve(to: CGPoint(x: 73, y: 69), control1: CGPoint(x: 34, y: 92), control2: CGPoint(x: 72, y: 92))
            dome.closeSubpath()
            shape(ctx, dome, red)
            shape(ctx, ellipse(53, 85, 5, 4), hex(0xC9443D), lineWidth: 1.4)
        }
    },
    Outfit(id: "party_hat", name: "派對帽", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            let cone = polygon([CGPoint(x: 41, y: 71), CGPoint(x: 66, y: 73), CGPoint(x: 57, y: 99)])
            shape(ctx, cone, hex(0x7FC8E8))
            // 條紋：裁切在帽子形狀內
            ctx.saveGState()
            ctx.addPath(cone)
            ctx.clip()
            for y in stride(from: CGFloat(76), through: 96, by: 8) {
                let stripe = CGMutablePath()
                stripe.move(to: CGPoint(x: 30, y: y - 4))
                stripe.addLine(to: CGPoint(x: 80, y: y + 2))
                line(ctx, stripe, hex(0xFFF27A), width: 3)
            }
            ctx.restoreGState()
            ctx.addPath(cone)
            ctx.setStrokeColor(outline)
            ctx.setLineWidth(2.2)
            ctx.strokePath()
            shape(ctx, ellipse(57, 100, 7, 7), hex(0xFF8FB1), lineWidth: 1.6)
        }
    },
    Outfit(id: "glasses", name: "圓框眼鏡", slot: "face") { ctx, p in
        withState(ctx, head(p)) {
            for c in [eyeBack, eyeFront] {
                shape(ctx, ellipse(c.x, c.y, 13, 13), hex(0xFFFFFF, 0.25), stroke: false)
                line(ctx, ellipse(c.x, c.y, 13, 13), hex(0x2F2F2F), width: 2)
            }
            let bridge = CGMutablePath()
            bridge.move(to: CGPoint(x: eyeBack.x + 6.5, y: eyeBack.y + 1))
            bridge.addQuadCurve(to: CGPoint(x: eyeFront.x - 6.5, y: eyeFront.y + 1),
                                control: CGPoint(x: (eyeBack.x + eyeFront.x) / 2, y: eyeBack.y + 4))
            line(ctx, bridge, hex(0x2F2F2F), width: 2)
        }
    },
    Outfit(id: "sunglasses", name: "墨鏡", slot: "face") { ctx, p in
        withState(ctx, head(p)) {
            for c in [eyeBack, eyeFront] {
                let lens = CGPath(roundedRect: CGRect(x: c.x - 7, y: c.y - 5, width: 14, height: 10),
                                  cornerWidth: 4, cornerHeight: 4, transform: nil)
                shape(ctx, lens, hex(0x26262E), lineWidth: 1.6)
                shape(ctx, ellipse(c.x + 3, c.y + 2, 3, 2), hex(0xFFFFFF, 0.6), stroke: false)
            }
            let bridge = CGMutablePath()
            bridge.move(to: CGPoint(x: eyeBack.x + 7, y: eyeBack.y + 2))
            bridge.addLine(to: CGPoint(x: eyeFront.x - 7, y: eyeFront.y + 2))
            line(ctx, bridge, hex(0x26262E), width: 2)
        }
    },
    Outfit(id: "scarf", name: "圍巾", slot: "neck") { ctx, p in
        withState(ctx, upper(p)) {
            let blue = hex(0x4A90D9)
            // 垂在背後的尾端
            let end = CGPath(roundedRect: CGRect(x: 30, y: 20, width: 9, height: 18),
                             cornerWidth: 3, cornerHeight: 3, transform: nil)
            shape(ctx, end, hex(0x3A78BC))
            // 繞脖子的一圈
            let band = CGPath(roundedRect: CGRect(x: 31, y: 32, width: 40, height: 9),
                              cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)
            shape(ctx, band, blue)
        }
    },
    Outfit(id: "bowtie", name: "領結", slot: "neck") { ctx, p in
        withState(ctx, upper(p)) {
            let red = hex(0xD94A6A)
            shape(ctx, polygon([CGPoint(x: 56, y: 36), CGPoint(x: 46, y: 41), CGPoint(x: 46, y: 31)]), red, lineWidth: 1.8)
            shape(ctx, polygon([CGPoint(x: 56, y: 36), CGPoint(x: 66, y: 41), CGPoint(x: 66, y: 31)]), red, lineWidth: 1.8)
            shape(ctx, ellipse(56, 36, 6, 6), hex(0xB8395A), lineWidth: 1.8)
        }
    },
]

// MARK: - 每個動作的姿勢

struct ActionSpec {
    let name: String
    let frames: Int
    let fps: Double
    let loop: Bool
}

// jump 的 4 格有固定意義：0 蹲下、1 上升、2 下降、3 落地（由程式依物理狀態挑格）。
let actions: [ActionSpec] = [
    ActionSpec(name: "idle", frames: 4, fps: 3, loop: true),
    ActionSpec(name: "walk", frames: 6, fps: 10, loop: true),
    ActionSpec(name: "run", frames: 6, fps: 16, loop: true),
    ActionSpec(name: "jump", frames: 4, fps: 0, loop: false),
    ActionSpec(name: "sit", frames: 2, fps: 2, loop: true),
    ActionSpec(name: "sleep", frames: 2, fps: 1.2, loop: true),
    ActionSpec(name: "fall", frames: 2, fps: 8, loop: true),
    ActionSpec(name: "dragged", frames: 2, fps: 5, loop: true),
]

func pose(_ action: String, _ i: Int, _ n: Int) -> Pose {
    var p = Pose()
    let t = CGFloat(i) / CGFloat(n) * 2 * .pi
    switch action {
    case "idle":
        p.squashY = 1 + 0.025 * sin(t)
        p.squashX = 1 - 0.015 * sin(t)
        p.tail = 0.15 * sin(t)
        if i == n - 1 { p.eyes = .closed }   // 最後一格眨眼
    case "walk":
        p.bodyY = abs(sin(t)) * 2
        p.frontFoot = CGPoint(x: 5 * sin(t), y: max(0, 3 * cos(t)))
        p.backFoot = CGPoint(x: -5 * sin(t), y: max(0, -3 * cos(t)))
        p.tail = 0.2 * sin(t)
    case "run":
        p.lean = 0.14
        p.bodyY = 2 + abs(sin(t)) * 4
        p.frontFoot = CGPoint(x: 9 * sin(t), y: max(0, 6 * cos(t)))
        p.backFoot = CGPoint(x: -9 * sin(t), y: max(0, -6 * cos(t)))
        p.tail = -0.45 + 0.15 * sin(t)
        p.eyes = .happy
    case "jump":
        switch i {
        case 0:  // 蹲下蓄力
            p.squashX = 1.14; p.squashY = 0.8; p.tail = 0.3
        case 1:  // 上升：拉長
            p.squashX = 0.92; p.squashY = 1.1; p.bodyY = 4
            p.frontFoot = CGPoint(x: -2, y: 2); p.backFoot = CGPoint(x: -4, y: 3)
            p.tail = -0.5; p.eyes = .happy
        case 2:  // 下降：腳往前伸準備落地
            p.bodyY = 4
            p.frontFoot = CGPoint(x: 4, y: 3); p.backFoot = CGPoint(x: 2, y: 2)
            p.tail = 0.5; p.mouthOpen = true
        default: // 落地緩衝
            p.squashX = 1.1; p.squashY = 0.86; p.eyes = .happy
        }
    case "sit":
        p.squashY = 0.9
        p.lean = -0.08
        p.frontFoot = CGPoint(x: 3, y: 0)
        p.backFoot = CGPoint(x: -4, y: 0)
        p.tail = i == 0 ? 0.35 : -0.05
        p.eyes = i == 0 ? .open : .happy
    case "sleep":
        p.squashX = 1.18
        p.squashY = 0.72 + 0.03 * CGFloat(i)
        p.headDX = 4
        p.headDY = -10
        p.frontFoot = CGPoint(x: -4, y: 1)
        p.backFoot = CGPoint(x: 4, y: 1)
        p.tail = 0.6
        p.eyes = .closed
        p.zzz = i + 1
    case "fall":
        p.bodyY = 6
        p.squashY = 1.05
        p.frontFoot = CGPoint(x: 4, y: i == 0 ? 10 : 6)
        p.backFoot = CGPoint(x: -3, y: i == 0 ? 6 : 10)
        p.tail = 0.8 + 0.25 * CGFloat(i)
        p.eyes = .wide
        p.mouthOpen = true
    case "dragged":
        p.squashX = 0.95
        p.squashY = 1.08
        let swing: CGFloat = i == 0 ? 2 : -2
        p.frontFoot = CGPoint(x: swing, y: -1)
        p.backFoot = CGPoint(x: -swing, y: -1)
        p.tail = -0.6 + 0.2 * CGFloat(i)
        p.eyes = .wide
    default:
        break
    }
    return p
}

// MARK: - 輸出

func renderPNG(_ draw: (CGContext) -> Void) -> Data {
    let px = Int(canvas * scale)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: offsetX, y: 0)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
for dir in ["body", "outfits"] {
    try? fm.removeItem(at: outputRoot.appendingPathComponent(dir))
}

func write(_ data: Data, _ relative: String) throws {
    let url = outputRoot.appendingPathComponent(relative)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

var count = 0
for spec in actions {
    for i in 0..<spec.frames {
        let p = pose(spec.name, i, spec.frames)
        try write(renderPNG { drawBody($0, p) }, "body/\(spec.name)_\(i).png")
        count += 1
        for outfit in outfits {
            try write(renderPNG { outfit.draw($0, p) }, "outfits/\(outfit.id)/\(spec.name)_\(i).png")
            count += 1
        }
    }
}

// manifest.json：程式靠它知道有哪些動作、幾格、多快，以及有哪些服裝。
let manifest: [String: Any] = [
    "canvas": ["width": canvas, "height": canvas],
    "actions": Dictionary(uniqueKeysWithValues: actions.map {
        ($0.name, ["frames": $0.frames, "fps": $0.fps, "loop": $0.loop] as [String: Any])
    }),
    "slots": [
        ["id": "neck", "name": "脖子"],
        ["id": "face", "name": "臉"],
        ["id": "head", "name": "頭"],
    ],
    "outfits": outfits.map { ["id": $0.id, "name": $0.name, "slot": $0.slot] },
]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try write(json, "manifest.json")

print("已產生 \(count) 張圖到 \(outputRoot.path)")
