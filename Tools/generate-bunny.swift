// generate-bunny.swift —— 產生「兔耳女孩」Q 版向量風格素材。
//
// 用法（在專案根目錄）：
//     swift Tools/generate-bunny.swift
//
// 會覆寫 Sources/SmallPet/Resources/ 底下的 body/、outfits/ 與 manifest.json。
// 想換回原本的小貓，跑 swift Tools/generate-sprites.swift 即可。
//
// 做法跟小貓版一樣：每個動作的每一格是一組「姿勢」(Pose)，本體和服裝用
// 同一組姿勢畫在同尺寸的透明畫布上，所以疊起來永遠對得齊。
// 角色特徵：棕色短髮 + 長兔耳、水藍大眼、ω 嘴、黑外套配水藍滾邊、
// 深藍上衣、藍色百褶裙、黑褲襪、白色圓手。
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

let outline = hex(0x2B2230)
let hair = hex(0x8A5A3C)
let hairDark = hex(0x6E452E)
let hairShine = hex(0xCDEBF7)
let earInner = hex(0xE9C6B4)
let skin = hex(0xFFEBDF)
let cheek = hex(0xF7A1A8, 0.6)
let eyeDark = hex(0x1F3F66)
let eyeIris = hex(0x46C1DE)
let jacket = hex(0x2A2A33)
let trim = hex(0x5CD0E0)
let top = hex(0x34304A)
let skirt = hex(0x3F7EC0)
let skirtLight = hex(0x6FA6DC)
let legging = hex(0x24242C)
let shoe = hex(0x17171D)
let white = hex(0xFFFFFF)

// MARK: - 姿勢

enum Eyes { case open, closed, happy, wide }

struct Pose {
    var bodyY: CGFloat = 0          // 上半身（身體+頭）整體上下位移
    var squashX: CGFloat = 1        // 水平伸縮（>1 變胖）
    var squashY: CGFloat = 1        // 垂直伸縮（<1 壓扁）
    var lean: CGFloat = 0           // 前傾角度（弧度），正值往臉的方向傾
    var headDX: CGFloat = 0
    var headDY: CGFloat = 0
    var headTilt: CGFloat = 0       // 點頭角度，正值往臉的方向低頭
    var frontFoot = CGPoint.zero    // 前腳位移
    var backFoot = CGPoint.zero     // 後腳位移
    var armFront: CGFloat = 0.15    // 手臂角度：0 垂下、π/2 往前平舉、π 舉高；負值往背後
    var armBack: CGFloat = 0.15
    var ears: CGFloat = 0           // 兔耳額外擺動，正值往後倒
    var eyes: Eyes = .open
    var mouthOpen = false
    var zzz = 0                     // 睡覺時頭上的 z 數量
    var back = false                // 轉過身，背對畫面（跳舞時扭屁股用）
    var tail: CGFloat = 0           // 背面時兔尾巴的左右擺動
    var straps = false              // 抓著降落傘的繩子（繩子一路畫到畫布頂端）
    var carrot = false              // 前手拿著胡蘿蔔，尖端朝嘴巴（吃東西用）
    var frame = 0                   // 這是動作的第幾格、一共幾格（會動的服裝用，例如 VIP 翅膀拍動、閃光）
    var frameCount = 1
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

func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

// 從 a 到 b 的葉片形（髮束用），w 是中段最寬處。
func petal(_ a: CGPoint, _ b: CGPoint, width w: CGFloat) -> CGPath {
    let dx = b.x - a.x, dy = b.y - a.y
    let len = max(hypot(dx, dy), 0.001)
    let nx = -dy / len * w * 0.66, ny = dx / len * w * 0.66
    let p = CGMutablePath()
    p.move(to: a)
    p.addCurve(to: b, control1: CGPoint(x: a.x + dx * 0.25 + nx, y: a.y + dy * 0.25 + ny),
               control2: CGPoint(x: a.x + dx * 0.75 + nx, y: a.y + dy * 0.75 + ny))
    p.addCurve(to: a, control1: CGPoint(x: a.x + dx * 0.75 - nx, y: a.y + dy * 0.75 - ny),
               control2: CGPoint(x: a.x + dx * 0.25 - nx, y: a.y + dy * 0.25 - ny))
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

func segment(_ a: CGPoint, _ b: CGPoint) -> CGPath {
    let p = CGMutablePath()
    p.move(to: a)
    p.addLine(to: b)
    return p
}

// 在一組座標變換內畫東西，畫完自動還原。
func withState(_ ctx: CGContext, _ transform: (CGContext) -> Void, _ draw: () -> Void) {
    ctx.saveGState()
    transform(ctx)
    draw()
    ctx.restoreGState()
}

// 上半身的座標變換：上下位移 → 以腳底為支點前傾、壓扁。
// 做成 CGAffineTransform，腳要接到上半身的髖部時才能算出位置。
func upperTransform(_ p: Pose) -> CGAffineTransform {
    CGAffineTransform.identity
        .translatedBy(x: 0, y: p.bodyY)
        .translatedBy(x: pivot.x, y: pivot.y)
        .rotated(by: -p.lean)
        .scaledBy(x: p.squashX, y: p.squashY)
        .translatedBy(x: -pivot.x, y: -pivot.y)
}

func upper(_ p: Pose) -> (CGContext) -> Void {
    { ctx in ctx.concatenate(upperTransform(p)) }
}

// 頭部的座標變換：在上半身之上再加頭的位移與點頭。服裝的帽子、眼鏡也用這個。
let neck = CGPoint(x: 52, y: 38)
func head(_ p: Pose) -> (CGContext) -> Void {
    { ctx in
        upper(p)(ctx)
        ctx.translateBy(x: p.headDX, y: p.headDY)
        ctx.translateBy(x: neck.x, y: neck.y)
        ctx.rotate(by: -p.headTilt)
        ctx.translateBy(x: -neck.x, y: -neck.y)
    }
}

// 各部位的基準座標（角色面向右，3/4 側臉）。
let eyeBack = CGPoint(x: 45, y: 50)
let eyeFront = CGPoint(x: 62, y: 50)
let shoulderBack = CGPoint(x: 39, y: 33)
let shoulderFront = CGPoint(x: 61, y: 33)
let hipBack = CGPoint(x: 45, y: 17)
let hipFront = CGPoint(x: 55, y: 17)
let footBack = CGPoint(x: 44, y: 8)
let footFront = CGPoint(x: 56, y: 8)

// MARK: - 本體

func drawBody(_ ctx: CGContext, _ p: Pose) {
    if p.back { return drawBodyBack(ctx, p) }
    let ut = upperTransform(p)

    // 降落傘的繩子：從兩手拉到畫布頂端，接上視窗上方那頂傘（最先畫，被頭擋住也沒關係）
    if p.straps {
        for (s, angle, top) in [(shoulderBack, p.armBack, strapTop[0]), (shoulderFront, p.armFront, strapTop[1])] {
            line(ctx, segment(hand(s, angle).applying(ut), top), outline, width: 1.3)
        }
    }

    // 後腳 + 後手（在身體後面）
    drawLeg(ctx, from: hipBack.applying(ut), to: CGPoint(x: footBack.x + p.backFoot.x, y: footBack.y + p.backFoot.y))
    if !raised(p.armBack) { withState(ctx, upper(p)) { drawArm(ctx, shoulderBack, p.armBack) } }
    drawLeg(ctx, from: hipFront.applying(ut), to: CGPoint(x: footFront.x + p.frontFoot.x, y: footFront.y + p.frontFoot.y))

    withState(ctx, upper(p)) {
        // 百褶裙
        let s = CGMutablePath()
        s.move(to: CGPoint(x: 39, y: 28))
        s.addLine(to: CGPoint(x: 61, y: 28))
        s.addLine(to: CGPoint(x: 67, y: 14))
        s.addQuadCurve(to: CGPoint(x: 50, y: 13), control: CGPoint(x: 58, y: 11))
        s.addQuadCurve(to: CGPoint(x: 33, y: 14), control: CGPoint(x: 42, y: 11))
        s.closeSubpath()
        shape(ctx, s, skirt)
        for (a, b) in [(CGPoint(x: 44, y: 27), CGPoint(x: 40, y: 14)),
                       (CGPoint(x: 50, y: 27), CGPoint(x: 50, y: 14)),
                       (CGPoint(x: 56, y: 27), CGPoint(x: 60, y: 14))] {
            line(ctx, segment(a, b), skirtLight, width: 1.6)
        }

        // 深藍上衣，下襬是一排小荷葉邊
        shape(ctx, rounded(44, 25, 14, 13, 3), top, lineWidth: 1.6)
        for x in stride(from: CGFloat(46.5), through: 56, by: 4.5) {
            shape(ctx, ellipse(x, 25, 5, 4), top, lineWidth: 1.2)
        }

        // 敞開的黑外套：左右兩片，內側水藍滾邊
        shape(ctx, rounded(33.5, 17, 13, 21, 5), jacket)
        shape(ctx, rounded(55.5, 17, 10, 21, 5), jacket)
        line(ctx, segment(CGPoint(x: 45.5, y: 18.5), CGPoint(x: 45.5, y: 36)), trim, width: 2)
        line(ctx, segment(CGPoint(x: 56.5, y: 18.5), CGPoint(x: 56.5, y: 36)), trim, width: 2)
        // 帽兜的水藍內裡，從脖子兩側露出來
        shape(ctx, ellipse(50, 37, 32, 7), trim, lineWidth: 1.6)

        if !raised(p.armFront) { drawArm(ctx, shoulderFront, p.armFront) }
    }

    withState(ctx, head(p)) { drawHead(ctx, p) }

    // 胡蘿蔔在臉前面、手的後面，看起來像握在手裡
    if p.carrot { withState(ctx, upper(p)) { drawCarrot(ctx, at: hand(shoulderFront, p.armFront)) } }

    // 舉高的手要畫在頭前面，不然會被大頭擋住
    withState(ctx, upper(p)) {
        if raised(p.armBack) { drawArm(ctx, shoulderBack, p.armBack) }
        if raised(p.armFront) { drawArm(ctx, shoulderFront, p.armFront) }
    }

    // 睡覺的 z
    for i in 0..<p.zzz {
        drawZ(ctx, at: CGPoint(x: 74 + CGFloat(i) * 8, y: 66 + CGFloat(i) * 10), size: 6 + CGFloat(i) * 2)
    }
}

// MARK: - 背面（轉身時用）

func drawBodyBack(_ ctx: CGContext, _ p: Pose) {
    let ut = upperTransform(p)

    drawLeg(ctx, from: hipBack.applying(ut), to: CGPoint(x: footBack.x + p.backFoot.x, y: footBack.y + p.backFoot.y))
    drawLeg(ctx, from: hipFront.applying(ut), to: CGPoint(x: footFront.x + p.frontFoot.x, y: footFront.y + p.frontFoot.y))

    withState(ctx, upper(p)) {
        // 背面看得到垂下的手臂在身體兩側
        if !raised(p.armBack) { drawArm(ctx, shoulderBack, p.armBack) }
        if !raised(p.armFront) { drawArm(ctx, shoulderFront, p.armFront) }

        // 百褶裙
        let s = CGMutablePath()
        s.move(to: CGPoint(x: 39, y: 28))
        s.addLine(to: CGPoint(x: 61, y: 28))
        s.addLine(to: CGPoint(x: 67, y: 14))
        s.addQuadCurve(to: CGPoint(x: 50, y: 13), control: CGPoint(x: 58, y: 11))
        s.addQuadCurve(to: CGPoint(x: 33, y: 14), control: CGPoint(x: 42, y: 11))
        s.closeSubpath()
        shape(ctx, s, skirt)
        for (a, b) in [(CGPoint(x: 44, y: 20), CGPoint(x: 41, y: 14)),
                       (CGPoint(x: 50, y: 20), CGPoint(x: 50, y: 14)),
                       (CGPoint(x: 56, y: 20), CGPoint(x: 59, y: 14))] {
            line(ctx, segment(a, b), skirtLight, width: 1.6)
        }

        // 外套背面一整片，上面披著帽兜
        shape(ctx, rounded(34, 19, 32, 19, 6), jacket)
        shape(ctx, ellipse(50, 33, 26, 11), jacket)
        let lining = CGMutablePath()
        lining.move(to: CGPoint(x: 40, y: 32))
        lining.addQuadCurve(to: CGPoint(x: 60, y: 32), control: CGPoint(x: 50, y: 26))
        line(ctx, lining, trim, width: 2)

        // 圓圓的兔尾巴
        shape(ctx, ellipse(50 + p.tail, 20, 10, 9), hair)
        shape(ctx, ellipse(48.5 + p.tail, 21.5, 3.5, 2.5), hairShine, stroke: false)
    }

    withState(ctx, head(p)) {
        // 兔耳背面：沒有粉色內側
        for (root, base, k) in [(CGPoint(x: 40, y: 72), CGFloat(0.3), CGFloat(1)),
                                (CGPoint(x: 60, y: 72), CGFloat(-0.3), CGFloat(1))] {
            withState(ctx, { c in
                c.translateBy(x: root.x, y: root.y)
                c.rotate(by: base + p.ears * k)
            }) {
                shape(ctx, ellipse(0, 13, 12, 28), hairDark)
            }
        }
        // 整顆後腦勺 + 兩側髮束
        shape(ctx, petal(CGPoint(x: 29, y: 60), CGPoint(x: 31, y: 36), width: 7), hair, lineWidth: 1.8)
        shape(ctx, petal(CGPoint(x: 71, y: 60), CGPoint(x: 69, y: 36), width: 7), hair, lineWidth: 1.8)
        shape(ctx, ellipse(50, 57, 52, 46), hair)
        // 髮流線條
        for (end, ctrl) in [(CGPoint(x: 38, y: 38), CGPoint(x: 38, y: 62)),
                            (CGPoint(x: 50, y: 35), CGPoint(x: 51, y: 60)),
                            (CGPoint(x: 62, y: 38), CGPoint(x: 63, y: 62))] {
            let strand = CGMutablePath()
            strand.move(to: CGPoint(x: 50, y: 78))
            strand.addQuadCurve(to: end, control: ctrl)
            line(ctx, strand, hairDark, width: 1.4)
        }
        withState(ctx, { c in
            c.translateBy(x: 41, y: 72)
            c.rotate(by: 0.35)
        }) {
            shape(ctx, ellipse(0, 0, 14, 5), hairShine, stroke: false)
        }
        shape(ctx, ellipse(58, 75, 6, 2.6), hairShine, stroke: false)
    }

    withState(ctx, upper(p)) {
        if raised(p.armBack) { drawArm(ctx, shoulderBack, p.armBack) }
        if raised(p.armFront) { drawArm(ctx, shoulderFront, p.armFront) }
    }
}

// 胡蘿蔔：粗的一端在手上，尖端往左上指向嘴巴，葉子從手的另一側露出來。
func drawCarrot(_ ctx: CGContext, at h: CGPoint) {
    let len: CGFloat = 19, rise: CGFloat = 5, half: CGFloat = 5   // 長度、往上的高度、粗端半寬
    let tip = CGPoint(x: h.x - len, y: h.y + rise)
    let d = CGPoint(x: 0.25, y: 0.97)   // 跟胡蘿蔔方向垂直的單位向量，用來決定粗細
    let base = CGPoint(x: h.x + 2, y: h.y - 0.5)
    for (dx, dy, rot) in [(CGFloat(4), CGFloat(1.5), CGFloat(0.5)), (CGFloat(5), CGFloat(-1.5), CGFloat(-0.25))] {
        withState(ctx, { c in
            c.translateBy(x: base.x + dx - 2, y: base.y + dy)
            c.rotate(by: rot)
        }) {
            shape(ctx, ellipse(3, 0, 8, 3.6), hex(0x5DB85A), lineWidth: 1.4)
        }
    }
    let body = CGMutablePath()
    body.move(to: CGPoint(x: base.x + d.x * half, y: base.y + d.y * half))
    body.addQuadCurve(to: tip, control: CGPoint(x: h.x - len * 0.5 + d.x * half * 0.8, y: h.y + rise * 0.5 + d.y * half * 0.8))
    body.addQuadCurve(to: CGPoint(x: base.x - d.x * half, y: base.y - d.y * half),
                      control: CGPoint(x: h.x - len * 0.5 - d.x * half * 0.8, y: h.y + rise * 0.5 - d.y * half * 0.8))
    body.closeSubpath()
    shape(ctx, body, hex(0xF39A3B), lineWidth: 1.6)
    // 胡蘿蔔上的短橫紋
    for k in [CGFloat(0.3), CGFloat(0.5), CGFloat(0.7)] {
        let c = CGPoint(x: h.x - len * k, y: h.y + rise * k)
        let w = half * (1 - k) * 0.9
        line(ctx, segment(CGPoint(x: c.x + d.x * w, y: c.y + d.y * w), CGPoint(x: c.x + d.x * w * 0.1, y: c.y + d.y * w * 0.1)),
             hex(0xC9712A), width: 1.1)
    }
}

func drawLeg(_ ctx: CGContext, from hip: CGPoint, to foot: CGPoint) {
    ctx.setLineCap(.round)
    line(ctx, segment(hip, foot), outline, width: 9)
    line(ctx, segment(hip, foot), legging, width: 6.2)
    shape(ctx, ellipse(foot.x + 1.5, foot.y - 0.5, 10, 6.5), shoe, lineWidth: 1.8)
}

func raised(_ angle: CGFloat) -> Bool { abs(angle) > 1.3 }

// 手（白色圓手的中心）在上半身座標裡的位置。
func hand(_ s: CGPoint, _ angle: CGFloat) -> CGPoint {
    CGPoint(x: s.x + sin(angle) * 12.5, y: s.y - cos(angle) * 12.5)
}

// 手臂：黑袖子 + 水藍袖口 + 白色圓手。角度 0 垂下，往前轉為正。
func drawArm(_ ctx: CGContext, _ s: CGPoint, _ angle: CGFloat) {
    let d = CGPoint(x: sin(angle), y: -cos(angle))
    func at(_ k: CGFloat) -> CGPoint { CGPoint(x: s.x + d.x * k, y: s.y + d.y * k) }
    ctx.setLineCap(.round)
    line(ctx, segment(s, at(9)), outline, width: 9)
    line(ctx, segment(s, at(9)), jacket, width: 6.6)
    ctx.setLineCap(.butt)
    line(ctx, segment(at(8), at(10)), outline, width: 9)
    line(ctx, segment(at(8.4), at(9.6)), trim, width: 6.6)
    ctx.setLineCap(.round)
    let h = hand(s, angle)
    shape(ctx, ellipse(h.x, h.y, 7.5, 7.5), white, lineWidth: 1.8)
}

func drawHead(_ ctx: CGContext, _ p: Pose) {
    // 兔耳（先畫，讓頭髮蓋住耳根）
    for (root, base, k) in [(CGPoint(x: 40, y: 72), CGFloat(0.3), CGFloat(1)),
                            (CGPoint(x: 60, y: 74), CGFloat(-0.18), CGFloat(0.8))] {
        withState(ctx, { c in
            c.translateBy(x: root.x, y: root.y)
            c.rotate(by: base + p.ears * k)
        }) {
            shape(ctx, ellipse(0, 13, 12, 28), hair)
            shape(ctx, ellipse(0.5, 14, 5.5, 19), earInner, stroke: false)
        }
    }

    // 後腦的頭髮
    shape(ctx, ellipse(50, 58, 54, 46), hairDark)

    // 臉
    shape(ctx, ellipse(54, 51, 40, 32), skin)

    // 兩側垂下的髮束
    shape(ctx, petal(CGPoint(x: 31, y: 62), CGPoint(x: 31, y: 37), width: 7), hair, lineWidth: 1.8)
    shape(ctx, petal(CGPoint(x: 76, y: 60), CGPoint(x: 74, y: 38), width: 6), hair, lineWidth: 1.8)

    // 瀏海：上緣是圓頂，下緣是一排尖尖的髮梢
    let bangs = CGMutablePath()
    bangs.move(to: CGPoint(x: 27, y: 54))
    bangs.addCurve(to: CGPoint(x: 78, y: 56), control1: CGPoint(x: 26, y: 86), control2: CGPoint(x: 78, y: 86))
    // 注意：addLines(between:) 會另起新的子路徑，所以這裡逐點 addLine 接在圓頂後面
    for pt in [CGPoint(x: 72, y: 61), CGPoint(x: 68, y: 56.5),
                             CGPoint(x: 63, y: 62), CGPoint(x: 57.5, y: 56), CGPoint(x: 52.5, y: 62.5),
                             CGPoint(x: 47, y: 56.5), CGPoint(x: 41.5, y: 62), CGPoint(x: 36, y: 55.5),
                             CGPoint(x: 32, y: 60)] {
        bangs.addLine(to: pt)
    }
    bangs.closeSubpath()
    shape(ctx, bangs, hair)

    // 頭髮上的水藍光澤
    withState(ctx, { c in
        c.translateBy(x: 41, y: 74)
        c.rotate(by: 0.35)
    }) {
        shape(ctx, ellipse(0, 0, 14, 5), hairShine, stroke: false)
    }
    shape(ctx, ellipse(57, 77.5, 6, 2.6), hairShine, stroke: false)

    // 臉頰
    shape(ctx, ellipse(40, 44, 7, 3.6), cheek, stroke: false)
    shape(ctx, ellipse(68, 44, 7, 3.6), cheek, stroke: false)

    drawEye(ctx, eyeBack, p.eyes)
    drawEye(ctx, eyeFront, p.eyes)

    // ω 嘴
    ctx.setLineCap(.round)
    if p.mouthOpen {
        shape(ctx, ellipse(54.5, 42, 5, 4.5), hex(0xC8504F), lineWidth: 1.5)
    } else {
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: 51.5, y: 43.5))
        mouth.addQuadCurve(to: CGPoint(x: 54.5, y: 43), control: CGPoint(x: 52.8, y: 41.2))
        mouth.addQuadCurve(to: CGPoint(x: 57.5, y: 43.5), control: CGPoint(x: 56.2, y: 41.2))
        line(ctx, mouth, outline, width: 1.5)
    }
}

func drawEye(_ ctx: CGContext, _ c: CGPoint, _ eyes: Eyes) {
    ctx.setLineCap(.round)
    switch eyes {
    case .open:
        let eye = ellipse(c.x, c.y, 8.5, 11)
        shape(ctx, eye, eyeDark, stroke: false)
        // 下半部的水藍虹膜，裁在眼睛形狀裡
        ctx.saveGState()
        ctx.addPath(eye)
        ctx.clip()
        shape(ctx, ellipse(c.x, c.y - 3, 9, 8), eyeIris, stroke: false)
        ctx.restoreGState()
        shape(ctx, ellipse(c.x - 1.4, c.y + 2.4, 3.4, 3.4), white, stroke: false)
        shape(ctx, ellipse(c.x + 1.8, c.y - 2.6, 1.6, 1.6), white, stroke: false)
        // 上睫毛
        let lash = CGMutablePath()
        lash.move(to: CGPoint(x: c.x - 5, y: c.y + 4))
        lash.addQuadCurve(to: CGPoint(x: c.x + 5, y: c.y + 4), control: CGPoint(x: c.x, y: c.y + 7.5))
        line(ctx, lash, outline, width: 2)
    case .wide:
        shape(ctx, ellipse(c.x, c.y, 10, 12), white, lineWidth: 1.6)
        shape(ctx, ellipse(c.x + 0.5, c.y, 4, 5), eyeIris, stroke: false)
        shape(ctx, ellipse(c.x + 0.5, c.y, 2, 2.5), eyeDark, stroke: false)
    case .closed:
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x - 4.5, y: c.y))
        path.addQuadCurve(to: CGPoint(x: c.x + 4.5, y: c.y), control: CGPoint(x: c.x, y: c.y - 4))
        line(ctx, path, outline, width: 2.2)
    case .happy:
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x - 4.5, y: c.y - 1.5))
        path.addQuadCurve(to: CGPoint(x: c.x + 4.5, y: c.y - 1.5), control: CGPoint(x: c.x, y: c.y + 5))
        line(ctx, path, outline, width: 2.2)
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


// MARK: - 背後的服裝用的小工具

// 把她身體的位置從服裝圖上挖掉：服裝圖疊在本體上面，挖掉後看起來就像在她身後。
// 背對畫面時翅膀、書包本來就該蓋在背上，不挖；fromBehind 為 true 時背對也挖（大到會蓋住頭的翅膀）。
func cutOutBody(_ ctx: CGContext, _ p: Pose, fromBehind: Bool = false) {
    guard !p.back || fromBehind else { return }
    ctx.saveGState()
    ctx.setBlendMode(.destinationOut)
    drawBody(ctx, p)
    ctx.restoreGState()
}

// 固定的亂數（同一個 n 永遠得到同一個 0..<1 的數），讓每格的閃光位置不同但每次產生都一樣。
func noise(_ n: Int) -> CGFloat {
    let x = sin(Double(n) * 12.9898) * 43758.5453
    return CGFloat(x - floor(x))
}

// 在 path 裡面填漸層（從 a 漸變到 b）。
func gradientFill(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], from a: CGPoint, to b: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// 四角星閃光。
func sparkle(_ ctx: CGContext, at c: CGPoint, size r: CGFloat, color: CGColor) {
    let star = CGMutablePath()
    star.move(to: CGPoint(x: c.x, y: c.y + r))
    star.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
    star.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
    star.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
    star.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 3, color: hex(0xFFE27A))
    ctx.addPath(star)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

// 翅膀根部的大鑽石。
func drawVIPGem(_ ctx: CGContext, _ p: Pose) {
    let root = CGPoint(x: 48, y: 36)
    withState(ctx, upper(p)) {
        let gem = polygon([CGPoint(x: root.x, y: root.y + 7), CGPoint(x: root.x + 5.5, y: root.y + 1),
                           CGPoint(x: root.x, y: root.y - 7), CGPoint(x: root.x - 5.5, y: root.y + 1)])
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 5, color: hex(0xB18CFF))
        shape(ctx, gem, hex(0xC9F3FF), lineWidth: 1.4)
        ctx.restoreGState()
        line(ctx, segment(CGPoint(x: root.x - 5.5, y: root.y + 1), CGPoint(x: root.x + 5.5, y: root.y + 1)), hex(0x7EE8FA), width: 0.9)
    }
}

// VIP 星耀之翼：網遊風的超大翅膀。
//   三層羽毛（金→粉→紫的長羽、白→金→水藍的主羽、金白的小覆羽），外圈發光，
//   上緣金色骨架鑲寶石，身後一圈光暈，每格飄不同位置的閃光。根部的鑽石另外畫（drawVIPGem）。
//   左右對稱、翅膀張滿整張畫布；每格輕輕拍一下，跳起來 / 被抓 / 往下掉時張得更開。
func drawVIPWings(_ ctx: CGContext, _ p: Pose) {
    let root = CGPoint(x: 48, y: 36)
    let phase = 2 * .pi * CGFloat(p.frame) / CGFloat(max(p.frameCount, 1))
    let excited = raised(p.armFront) || raised(p.armBack)
    // 再張開就會超出畫布頂端
    let flap = excited ? 0.1 + 0.02 * sin(phase) : 0.06 + 0.05 * sin(phase)

    let deep = hex(0x5B2A86)
    let tip = CGPoint(x: 31, y: 45)          // 骨架尖端（翅膀的「手腕」）
    let elbow = CGPoint(x: 5, y: 38)
    func arm(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: 2 * u * t * elbow.x + t * t * tip.x, y: 2 * u * t * elbow.y + t * t * tip.y)
    }

    withState(ctx, upper(p)) {
        // 身後的光暈
        let aura = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [hex(0xFFF1B8, 0.55), hex(0xFF9AD5, 0.25), hex(0xB18CFF, 0)] as CFArray,
                              locations: [0, 0.5, 1])!
        let auraCenter = CGPoint(x: root.x, y: root.y + 26)
        ctx.drawRadialGradient(aura, startCenter: auraCenter, startRadius: 0, endCenter: auraCenter, endRadius: 58 + 3 * sin(phase), options: [])

        for dir in [CGFloat(-1), CGFloat(1)] {
            withState(ctx, { c in
                c.translateBy(x: root.x, y: root.y)
                c.scaleBy(x: dir, y: 1)
                c.rotate(by: flap)
            }) {
                // 羽毛從骨架往下、往外排開；越靠尖端越往上翹
                func feather(_ t: CGFloat, length k: CGFloat, turn: CGFloat, width w: CGFloat) -> (CGPath, CGPoint, CGPoint) {
                    let a = arm(t)
                    let angle = -1.45 + 1.95 * t + turn
                    let len = (21 + 9 * sin(.pi * t)) * k
                    let b = CGPoint(x: a.x + cos(angle) * len, y: a.y + sin(angle) * len)
                    return (petal(a, b, width: w + 3 * t), a, b)
                }
                let ts = stride(from: CGFloat(0.12), through: 1.0, by: 0.11).map { $0 }

                // 第一層：長羽（發光）
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 7, color: hex(0xFFD86B, 0.95))
                for t in ts {
                    let (path, _, _) = feather(t, length: 1.18, turn: -0.12, width: 8)
                    ctx.addPath(path)
                }
                ctx.setFillColor(hex(0xFFD27A))
                ctx.fillPath()
                ctx.restoreGState()
                for t in ts {
                    let (path, a, b) = feather(t, length: 1.18, turn: -0.12, width: 8)
                    gradientFill(ctx, path, [hex(0xFFD27A), hex(0xFF5FA2), hex(0x8B5CF6)], from: a, to: b)
                    line(ctx, path, deep, width: 1.1)
                }
                // 第二層：主羽
                for t in ts.reversed() {
                    let (path, a, b) = feather(t, length: 0.86, turn: 0.05, width: 7)
                    gradientFill(ctx, path, [hex(0xFFFFFF), hex(0xFFE9A8), hex(0x7EE8FA)], from: a, to: b)
                    line(ctx, path, deep, width: 1.1)
                    line(ctx, segment(a, CGPoint(x: (a.x * 2 + b.x) / 3, y: (a.y * 2 + b.y) / 3)), hex(0xFFFFFF, 0.9), width: 0.9)
                }
                // 第三層：小覆羽
                for t in stride(from: CGFloat(0.08), through: 0.95, by: 0.145) {
                    let (path, a, b) = feather(t, length: 0.42, turn: 0.2, width: 6)
                    gradientFill(ctx, path, [hex(0xFFF8E1), hex(0xFFD27A)], from: a, to: b)
                    line(ctx, path, deep, width: 1)
                }

                // 金色骨架 + 寶石 + 尖端的星星
                let bone = CGMutablePath()
                bone.move(to: .zero)
                bone.addQuadCurve(to: tip, control: elbow)
                line(ctx, bone, deep, width: 5.2)
                line(ctx, bone, hex(0xF5C84C), width: 3.2)
                line(ctx, bone, hex(0xFFF3C4), width: 1)
                for (t, color) in [(CGFloat(0.4), hex(0xFF4F8B)), (CGFloat(0.72), hex(0x46C1DE))] {
                    let g = arm(t)
                    shape(ctx, ellipse(g.x, g.y, 5.2, 5.2), color, lineWidth: 1.2)
                    shape(ctx, ellipse(g.x - 0.9, g.y + 1, 1.8, 1.4), hex(0xFFFFFF, 0.9), stroke: false)
                }
                sparkle(ctx, at: CGPoint(x: tip.x + 1, y: tip.y + 1), size: 5.5, color: hex(0xFFF3C4))
            }
        }

    }

    // 飄在翅膀附近的閃光和光點，每格不一樣
    for k in 0..<7 {
        let n = p.frame * 31 + k * 7
        let side: CGFloat = k % 2 == 0 ? -1 : 1
        let c = CGPoint(x: 48 + side * (14 + 40 * noise(n)), y: 34 + 64 * noise(n + 1))
        sparkle(ctx, at: c, size: 2 + 3 * noise(n + 2), color: k % 3 == 0 ? hex(0xFFF3C4) : white)
    }
    for k in 0..<5 {
        let n = p.frame * 17 + k * 11 + 500
        let c = CGPoint(x: -4 + 104 * noise(n), y: 28 + 74 * noise(n + 1))
        shape(ctx, ellipse(c.x, c.y, 2.2, 2.2), [hex(0xFF9AD5, 0.8), hex(0x7EE8FA, 0.8), hex(0xFFE27A, 0.8)][k % 3], stroke: false)
    }
}

// MARK: - 服裝（每件都用跟本體相同的姿勢畫）

struct Outfit {
    let id: String
    let name: String
    let slot: String
    let draw: (CGContext, Pose) -> Void
}

// 每件服裝的戰鬥力加成。
let outfitPower: [String: Int] = [
    "cap": 3, "party_hat": 2, "glasses": 2, "sunglasses": 4, "scarf": 3, "bowtie": 2,
    "straw_hat": 5, "witch_hat": 9, "cape": 8, "crown": 14, "ribbon": 11,
    "flower_crown": 3, "headphones": 2, "goggles": 4, "heart_glasses": 2, "bell_collar": 2,
    "balloon": 1, "lollipop": 2, "backpack": 3, "wings": 6, "vip_wings": 20,
]
// 只能從地下城拿到的服裝（還沒拿到前不會出現在衣櫃）。
let dungeonOutfits: Set<String> = ["straw_hat", "witch_hat", "cape", "crown", "ribbon"]

let outfits: [Outfit] = [
    Outfit(id: "cap", name: "棒球帽", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            let red = hex(0xE8574F)
            // 帽沿（朝臉的方向；背對時被頭擋住）
            if !p.back { shape(ctx, ellipse(78, 66, 26, 7), hex(0xC9443D)) }
            // 帽頂：半個橢圓，兔耳從上面露出來
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: 25, y: 64))
            dome.addCurve(to: CGPoint(x: 78, y: 66), control1: CGPoint(x: 26, y: 92), control2: CGPoint(x: 77, y: 92))
            dome.closeSubpath()
            shape(ctx, dome, red)
            shape(ctx, ellipse(52, 86, 5, 4), hex(0xC9443D), lineWidth: 1.4)
        }
    },
    Outfit(id: "party_hat", name: "派對帽", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            let cone = polygon([CGPoint(x: 41, y: 77), CGPoint(x: 63, y: 79), CGPoint(x: 54, y: 103)])
            shape(ctx, cone, hex(0x7FC8E8))
            // 條紋：裁切在帽子形狀內
            ctx.saveGState()
            ctx.addPath(cone)
            ctx.clip()
            for y in stride(from: CGFloat(82), through: 102, by: 7) {
                line(ctx, segment(CGPoint(x: 30, y: y - 4), CGPoint(x: 80, y: y + 2)), hex(0xFFF27A), width: 3)
            }
            ctx.restoreGState()
            ctx.addPath(cone)
            ctx.setStrokeColor(outline)
            ctx.setLineWidth(2.2)
            ctx.strokePath()
            shape(ctx, ellipse(54, 104, 6.5, 6.5), hex(0xFF8FB1), lineWidth: 1.6)
        }
    },
    Outfit(id: "glasses", name: "圓框眼鏡", slot: "face") { ctx, p in
        guard !p.back else { return }
        withState(ctx, head(p)) {
            for c in [eyeBack, eyeFront] {
                shape(ctx, ellipse(c.x, c.y, 15, 15), hex(0xFFFFFF, 0.25), stroke: false)
                line(ctx, ellipse(c.x, c.y, 15, 15), hex(0x2F2F2F), width: 2)
            }
            let bridge = CGMutablePath()
            bridge.move(to: CGPoint(x: eyeBack.x + 7.5, y: eyeBack.y + 1))
            bridge.addQuadCurve(to: CGPoint(x: eyeFront.x - 7.5, y: eyeFront.y + 1),
                                control: CGPoint(x: (eyeBack.x + eyeFront.x) / 2, y: eyeBack.y + 4))
            line(ctx, bridge, hex(0x2F2F2F), width: 2)
        }
    },
    Outfit(id: "sunglasses", name: "墨鏡", slot: "face") { ctx, p in
        guard !p.back else { return }
        withState(ctx, head(p)) {
            for c in [eyeBack, eyeFront] {
                shape(ctx, rounded(c.x - 7.5, c.y - 5.5, 15, 11, 4), hex(0x26262E), lineWidth: 1.6)
                shape(ctx, ellipse(c.x + 3, c.y + 2, 3, 2), hex(0xFFFFFF, 0.6), stroke: false)
            }
            line(ctx, segment(CGPoint(x: eyeBack.x + 7.5, y: eyeBack.y + 2),
                              CGPoint(x: eyeFront.x - 7.5, y: eyeFront.y + 2)), hex(0x26262E), width: 2)
        }
    },
    Outfit(id: "scarf", name: "圍巾", slot: "neck") { ctx, p in
        withState(ctx, upper(p)) {
            // 垂在後肩的尾端
            shape(ctx, rounded(36, 18, 9, 17, 3), hex(0x3A78BC))
            // 繞脖子的一圈
            shape(ctx, rounded(35, 31, 32, 8.5, 4.2), hex(0x4A90D9))
        }
    },
    Outfit(id: "bowtie", name: "領結", slot: "neck") { ctx, p in
        guard !p.back else { return }
        withState(ctx, upper(p)) {
            let red = hex(0xD94A6A)
            let c = CGPoint(x: 51, y: 33)
            shape(ctx, polygon([c, CGPoint(x: c.x - 9, y: c.y + 5), CGPoint(x: c.x - 9, y: c.y - 5)]), red, lineWidth: 1.8)
            shape(ctx, polygon([c, CGPoint(x: c.x + 9, y: c.y + 5), CGPoint(x: c.x + 9, y: c.y - 5)]), red, lineWidth: 1.8)
            shape(ctx, ellipse(c.x, c.y, 5.5, 5.5), hex(0xB8395A), lineWidth: 1.8)
        }
    },

    // ── 以下是地下城的戰利品 ──

    Outfit(id: "straw_hat", name: "草帽", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            let straw = hex(0xF2D07A), strawDark = hex(0xD4A94E)
            // 寬帽沿
            shape(ctx, ellipse(52, 77, 66, 13), straw)
            line(ctx, ellipse(52, 77, 52, 8), strawDark, width: 1.2)
            // 帽頂，兔耳從後面冒出來
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: 35, y: 78))
            dome.addCurve(to: CGPoint(x: 69, y: 78), control1: CGPoint(x: 36, y: 96), control2: CGPoint(x: 68, y: 96))
            dome.closeSubpath()
            shape(ctx, dome, straw)
            // 紅色帽帶
            ctx.saveGState()
            ctx.addPath(dome)
            ctx.clip()
            ctx.fill(CGRect.zero)
            line(ctx, segment(CGPoint(x: 30, y: 81.5), CGPoint(x: 74, y: 81.5)), hex(0xD9483F), width: 4.5)
            ctx.restoreGState()
            line(ctx, dome, outline, width: 2.2)
        }
    },
    Outfit(id: "witch_hat", name: "魔法帽", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            let purple = hex(0x5B3F8C), band = hex(0x8E6CC8)
            shape(ctx, ellipse(52, 78, 60, 11), purple)
            // 尖帽：尖端往後彎
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: 38, y: 79))
            cone.addQuadCurve(to: CGPoint(x: 36, y: 103), control: CGPoint(x: 44, y: 92))
            cone.addQuadCurve(to: CGPoint(x: 66, y: 80), control: CGPoint(x: 60, y: 96))
            cone.closeSubpath()
            shape(ctx, cone, purple)
            ctx.saveGState()
            ctx.addPath(cone)
            ctx.clip()
            line(ctx, segment(CGPoint(x: 30, y: 83.5), CGPoint(x: 74, y: 84.5)), band, width: 4)
            ctx.restoreGState()
            line(ctx, cone, outline, width: 2.2)
            // 金色星星
            let star = CGMutablePath()
            let c = CGPoint(x: 55, y: 90)
            for k in 0..<10 {
                let r: CGFloat = k % 2 == 0 ? 4.2 : 1.8
                let a = CGFloat(k) * .pi / 5 + .pi / 2
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
            }
            star.closeSubpath()
            shape(ctx, star, hex(0xF5C84C), lineWidth: 1.2)
        }
    },
    Outfit(id: "cape", name: "披風", slot: "neck") { ctx, p in
        let red = hex(0xC8364A), lining = hex(0x8E2234)
        withState(ctx, upper(p)) {
            if p.back {
                // 背對時整片披風蓋住背，下襬留給兔尾巴
                let back = CGMutablePath()
                back.move(to: CGPoint(x: 37, y: 37))
                back.addLine(to: CGPoint(x: 65, y: 37))
                back.addQuadCurve(to: CGPoint(x: 70, y: 15), control: CGPoint(x: 70, y: 26))
                back.addQuadCurve(to: CGPoint(x: 51, y: 27), control: CGPoint(x: 60, y: 14))
                back.addQuadCurve(to: CGPoint(x: 32, y: 15), control: CGPoint(x: 42, y: 14))
                back.addQuadCurve(to: CGPoint(x: 37, y: 37), control: CGPoint(x: 32, y: 26))
                back.closeSubpath()
                shape(ctx, back, red)
                line(ctx, segment(CGPoint(x: 51, y: 34), CGPoint(x: 51, y: 28.5)), lining, width: 1.4)
                shape(ctx, rounded(36, 34, 30, 6, 3), red)
                return
            }
            // 面向前時：披風飄在背後（畫面左邊），露出紅色內裡
            let flap = CGMutablePath()
            flap.move(to: CGPoint(x: 41, y: 38))
            flap.addQuadCurve(to: CGPoint(x: 22, y: 11), control: CGPoint(x: 26, y: 30))
            flap.addQuadCurve(to: CGPoint(x: 30, y: 13), control: CGPoint(x: 26, y: 9))
            flap.addQuadCurve(to: CGPoint(x: 35, y: 11), control: CGPoint(x: 32, y: 10))
            flap.addQuadCurve(to: CGPoint(x: 37, y: 33), control: CGPoint(x: 34, y: 22))
            flap.closeSubpath()
            shape(ctx, flap, red)
            line(ctx, segment(CGPoint(x: 36.5, y: 31), CGPoint(x: 29, y: 13)), lining, width: 1.4)
            // 領子 + 金色扣環
            shape(ctx, rounded(36, 33.5, 30, 6.5, 3.2), red)
            shape(ctx, ellipse(58, 36.5, 5.5, 5.5), hex(0xF5C84C), lineWidth: 1.6)
        }
    },
    Outfit(id: "crown", name: "王冠", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            let gold = hex(0xF5C84C), goldDark = hex(0xD9A62E)
            withState(ctx, { c in
                c.translateBy(x: 53, y: 80)
                c.rotate(by: -0.12)   // 有點歪歪的戴著
            }) {
                let crown = polygon([
                    CGPoint(x: -12, y: 0), CGPoint(x: 12, y: 0), CGPoint(x: 13, y: 14), CGPoint(x: 6.5, y: 7),
                    CGPoint(x: 0, y: 16), CGPoint(x: -6.5, y: 7), CGPoint(x: -13, y: 14),
                ])
                shape(ctx, crown, gold)
                line(ctx, segment(CGPoint(x: -11.5, y: 3.5), CGPoint(x: 11.5, y: 3.5)), goldDark, width: 1.4)
                for (x, y) in [(CGFloat(-13), CGFloat(15)), (CGFloat(0), CGFloat(17)), (CGFloat(13), CGFloat(15))] {
                    shape(ctx, ellipse(x, y, 3.6, 3.6), gold, lineWidth: 1.3)
                }
                shape(ctx, ellipse(0, 7, 4.5, 4.5), hex(0xE0455A), lineWidth: 1.3)
                shape(ctx, ellipse(-7.5, 2, 3, 3), hex(0x46C1DE), lineWidth: 1)
                shape(ctx, ellipse(7.5, 2, 3, 3), hex(0x46C1DE), lineWidth: 1)
            }
        }
    },
    Outfit(id: "ribbon", name: "蝴蝶結", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            let pink = hex(0xFF8FB1), pinkDark = hex(0xE0668F)
            let c = CGPoint(x: 49, y: 84)
            // 兩條垂下來的緞帶
            shape(ctx, polygon([CGPoint(x: c.x - 1, y: c.y), CGPoint(x: c.x - 7, y: c.y - 10),
                                CGPoint(x: c.x - 3, y: c.y - 9), CGPoint(x: c.x + 1, y: c.y - 3)]), pinkDark, lineWidth: 1.6)
            shape(ctx, polygon([CGPoint(x: c.x + 1, y: c.y), CGPoint(x: c.x + 8, y: c.y - 9),
                                CGPoint(x: c.x + 4, y: c.y - 10), CGPoint(x: c.x - 1, y: c.y - 3)]), pinkDark, lineWidth: 1.6)
            // 左右兩個圈
            for dir in [CGFloat(-1), CGFloat(1)] {
                let loop = CGMutablePath()
                loop.move(to: c)
                loop.addCurve(to: CGPoint(x: c.x + 15 * dir, y: c.y - 3),
                              control1: CGPoint(x: c.x + 6 * dir, y: c.y + 12), control2: CGPoint(x: c.x + 16 * dir, y: c.y + 9))
                loop.addCurve(to: c, control1: CGPoint(x: c.x + 14 * dir, y: c.y - 8), control2: CGPoint(x: c.x + 5 * dir, y: c.y - 5))
                loop.closeSubpath()
                shape(ctx, loop, pink)
                line(ctx, segment(CGPoint(x: c.x + 4 * dir, y: c.y + 1), CGPoint(x: c.x + 10 * dir, y: c.y + 2)), pinkDark, width: 1.2)
            }
            shape(ctx, ellipse(c.x, c.y, 6.5, 6.5), pinkDark, lineWidth: 1.6)
        }
    },
    // ── 第二批：一般服裝和配件 ──

    Outfit(id: "flower_crown", name: "花冠", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            // 沿著頭頂排一圈小花，中間夾葉子
            let pts = (0...6).map { k -> CGPoint in
                let u = CGFloat(k) / 6
                return CGPoint(x: 29 + 46 * u, y: 72 + 11 * sin(.pi * u))
            }
            for (a, b) in zip(pts, pts.dropFirst()) {
                shape(ctx, ellipse((a.x + b.x) / 2, (a.y + b.y) / 2 - 1, 7, 4), hex(0x7CC46A), lineWidth: 1.2)
            }
            let colors = [hex(0xFF8FB1), hex(0xFFF27A), hex(0xFFFFFF), hex(0xB9A6F0)]
            for (k, c) in pts.enumerated() {
                for i in 0..<5 {
                    let a = CGFloat(i) * 2 * .pi / 5
                    shape(ctx, ellipse(c.x + cos(a) * 2.6, c.y + sin(a) * 2.6, 4, 4), colors[k % colors.count], lineWidth: 1)
                }
                shape(ctx, ellipse(c.x, c.y, 2.6, 2.6), hex(0xF5A623), stroke: false)
            }
        }
    },
    Outfit(id: "headphones", name: "耳機", slot: "head") { ctx, p in
        withState(ctx, head(p)) {
            let band = hex(0xF4F4F8), cup = hex(0xFF8FB1)
            let arc = CGMutablePath()
            arc.move(to: CGPoint(x: 31, y: 56))
            arc.addCurve(to: CGPoint(x: 73, y: 58), control1: CGPoint(x: 28, y: 94), control2: CGPoint(x: 76, y: 94))
            line(ctx, arc, outline, width: 6)
            line(ctx, arc, band, width: 3.6)
            if p.back {
                // 背對時兩邊耳罩都看得到
                shape(ctx, rounded(25, 48, 10, 16, 4), cup)
                shape(ctx, rounded(69, 50, 10, 16, 4), cup)
            } else {
                // 側臉：後面的耳罩整個露出來，前面的只露一小截
                shape(ctx, rounded(25, 47, 11, 17, 4.5), cup)
                shape(ctx, ellipse(30.5, 55.5, 4, 7), hex(0xFFFFFF, 0.6), stroke: false)
                shape(ctx, rounded(71, 50, 5, 13, 2.5), cup, lineWidth: 1.8)
            }
        }
    },
    Outfit(id: "goggles", name: "飛行護目鏡", slot: "face") { ctx, p in
        withState(ctx, head(p)) {
            let leather = hex(0x8B5E3C)
            if p.back {
                // 背對時只看到繞過後腦的皮帶
                shape(ctx, rounded(27, 47, 48, 6, 3), leather, lineWidth: 1.8)
                return
            }
            line(ctx, segment(CGPoint(x: 27, y: 52), CGPoint(x: eyeBack.x - 8, y: eyeBack.y + 1)), outline, width: 6)
            line(ctx, segment(CGPoint(x: 27, y: 52), CGPoint(x: eyeBack.x - 8, y: eyeBack.y + 1)), leather, width: 3.6)
            line(ctx, segment(CGPoint(x: eyeBack.x + 7, y: eyeBack.y + 1), CGPoint(x: eyeFront.x - 7, y: eyeFront.y + 1)), leather, width: 3)
            for c in [eyeBack, eyeFront] {
                shape(ctx, ellipse(c.x, c.y, 16.5, 15), hex(0xC9CED6), lineWidth: 2)
                shape(ctx, ellipse(c.x, c.y, 11.5, 10.5), hex(0xF5B04C, 0.55), lineWidth: 1.4)
                shape(ctx, ellipse(c.x + 2.5, c.y + 2.5, 3, 2), hex(0xFFFFFF, 0.8), stroke: false)
            }
        }
    },
    Outfit(id: "heart_glasses", name: "愛心眼鏡", slot: "face") { ctx, p in
        guard !p.back else { return }
        withState(ctx, head(p)) {
            for c in [eyeBack, eyeFront] {
                let heart = CGMutablePath()
                heart.move(to: CGPoint(x: c.x, y: c.y - 7))
                heart.addCurve(to: CGPoint(x: c.x, y: c.y + 3.5), control1: CGPoint(x: c.x - 13, y: c.y - 1), control2: CGPoint(x: c.x - 7, y: c.y + 10))
                heart.addCurve(to: CGPoint(x: c.x, y: c.y - 7), control1: CGPoint(x: c.x + 7, y: c.y + 10), control2: CGPoint(x: c.x + 13, y: c.y - 1))
                shape(ctx, heart, hex(0xFF5C8A, 0.75), lineWidth: 1.8)
                shape(ctx, ellipse(c.x - 3, c.y + 2, 2.5, 1.8), hex(0xFFFFFF, 0.7), stroke: false)
            }
            line(ctx, segment(CGPoint(x: eyeBack.x + 6, y: eyeBack.y + 2), CGPoint(x: eyeFront.x - 6, y: eyeFront.y + 2)), outline, width: 1.8)
        }
    },
    Outfit(id: "bell_collar", name: "鈴鐺項圈", slot: "neck") { ctx, p in
        withState(ctx, upper(p)) {
            shape(ctx, rounded(37, 32.5, 28, 5, 2.5), hex(0xE0455A), lineWidth: 1.8)
            guard !p.back else { return }
            let bell = CGPoint(x: 55, y: 30)
            shape(ctx, ellipse(bell.x, bell.y, 8, 8), hex(0xF5C84C), lineWidth: 1.6)
            line(ctx, segment(CGPoint(x: bell.x - 3.5, y: bell.y + 0.5), CGPoint(x: bell.x + 3.5, y: bell.y + 0.5)), hex(0xD9A62E), width: 1.2)
            shape(ctx, ellipse(bell.x, bell.y - 2, 2, 2), outline, stroke: false)
        }
    },

    // ── 手上（拿在前手，吃東西時手上是胡蘿蔔，就先收起來）──

    Outfit(id: "balloon", name: "氣球", slot: "hand") { ctx, p in
        guard !p.carrot else { return }
        withState(ctx, upper(p)) {
            let h = hand(shoulderFront, p.armFront)
            // 氣球一直飄在頭的右上方，線從手拉上去
            let b = CGPoint(x: 85, y: 87)
            let string = CGMutablePath()
            string.move(to: h)
            string.addQuadCurve(to: CGPoint(x: b.x - 1, y: b.y - 12), control: CGPoint(x: (h.x + b.x) / 2 + 6, y: (h.y + b.y) / 2 - 8))
            line(ctx, string, outline, width: 1.2)
            shape(ctx, polygon([CGPoint(x: b.x - 1, y: b.y - 11), CGPoint(x: b.x - 3.5, y: b.y - 14), CGPoint(x: b.x + 1.5, y: b.y - 14)]), hex(0xE0455A), lineWidth: 1.2)
            shape(ctx, ellipse(b.x, b.y, 17, 20), hex(0xFF5C6E))
            shape(ctx, ellipse(b.x - 4, b.y + 5, 4, 6), hex(0xFFFFFF, 0.6), stroke: false)
            // 手要蓋在線上面，看起來是握著
            shape(ctx, ellipse(h.x, h.y, 7.5, 7.5), white, lineWidth: 1.8)
        }
    },
    Outfit(id: "lollipop", name: "棒棒糖", slot: "hand") { ctx, p in
        guard !p.carrot else { return }
        withState(ctx, upper(p)) {
            let h = hand(shoulderFront, p.armFront)
            let top = CGPoint(x: h.x + 2, y: h.y + 13)
            line(ctx, segment(h, top), outline, width: 3.2)
            line(ctx, segment(h, top), white, width: 1.8)
            shape(ctx, ellipse(top.x, top.y + 3, 13, 13), hex(0xFF8FB1))
            // 螺旋
            let swirl = CGMutablePath()
            for k in 0...24 {
                let a = CGFloat(k) * 0.55
                let r = 0.22 * a + 0.4
                let pt = CGPoint(x: top.x + cos(a) * r, y: top.y + 3 + sin(a) * r)
                if k == 0 { swirl.move(to: pt) } else { swirl.addLine(to: pt) }
            }
            line(ctx, swirl, hex(0xFFFFFF), width: 1.6)
            shape(ctx, ellipse(h.x, h.y, 7.5, 7.5), white, lineWidth: 1.8)
        }
    },

    // ── 背後 ──

    Outfit(id: "backpack", name: "小書包", slot: "back") { ctx, p in
        let bag = hex(0xF7C66B), bagDark = hex(0xD9A62E)
        withState(ctx, upper(p)) {
            if p.back {
                shape(ctx, rounded(38, 13, 26, 23, 7), bag)
                shape(ctx, rounded(38, 25, 26, 11, 6), bagDark, lineWidth: 1.8)
                shape(ctx, rounded(44, 16, 14, 7, 3), bagDark, lineWidth: 1.4)
                shape(ctx, ellipse(51, 27, 4, 4), hex(0xE0455A), lineWidth: 1.2)
                return
            }
            // 側面：書包掛在背後，背帶從肩膀繞到前面
            shape(ctx, rounded(21, 14, 15, 22, 6), bag)
            shape(ctx, rounded(20, 25, 12, 10, 5), bagDark, lineWidth: 1.8)
            shape(ctx, ellipse(26, 29, 3.5, 3.5), hex(0xE0455A), lineWidth: 1.1)
            let strap = CGMutablePath()
            strap.move(to: CGPoint(x: 36, y: 34))
            strap.addQuadCurve(to: CGPoint(x: 44, y: 17), control: CGPoint(x: 44, y: 30))
            line(ctx, strap, outline, width: 4.4)
            line(ctx, strap, bagDark, width: 2.4)
        }
    },
    Outfit(id: "wings", name: "天使翅膀", slot: "back") { ctx, p in
        // 跳起來、被抓、往下掉時翅膀張開一點
        let spread: CGFloat = raised(p.armFront) || raised(p.armBack) ? 0.25 : 0
        func wing(_ root: CGPoint, _ dir: CGFloat, _ color: CGColor) {
            withState(ctx, { c in
                c.translateBy(x: root.x, y: root.y)
                c.rotate(by: (-0.25 - spread) * dir)   // 翼尖往上翹
                c.scaleBy(x: dir, y: 1)
            }) {
                let w = CGMutablePath()
                w.move(to: .zero)
                w.addQuadCurve(to: CGPoint(x: -26, y: 16), control: CGPoint(x: -12, y: 18))
                w.addQuadCurve(to: CGPoint(x: -22, y: 6), control: CGPoint(x: -28, y: 10))
                w.addQuadCurve(to: CGPoint(x: -24, y: -2), control: CGPoint(x: -18, y: 2))
                w.addQuadCurve(to: CGPoint(x: -17, y: -8), control: CGPoint(x: -22, y: -8))
                w.addQuadCurve(to: CGPoint(x: -4, y: -9), control: CGPoint(x: -10, y: -12))
                w.closeSubpath()
                shape(ctx, w, color)
                for (a, b) in [(CGPoint(x: -6, y: 4), CGPoint(x: -19, y: 9)), (CGPoint(x: -6, y: -2), CGPoint(x: -17, y: 0))] {
                    line(ctx, segment(a, b), hex(0xD7E3EA), width: 1.4)
                }
            }
        }
        withState(ctx, upper(p)) {
            if p.back {
                wing(CGPoint(x: 44, y: 31), 1, white)
                wing(CGPoint(x: 58, y: 31), -1, white)
            } else {
                wing(CGPoint(x: 39, y: 33), 1, hex(0xEDF3F7))   // 遠的那片，高一點
                wing(CGPoint(x: 37, y: 29), 1, white)
            }
        }
        cutOutBody(ctx, p)
    },
    Outfit(id: "vip_wings", name: "VIP 星耀之翼", slot: "back") { ctx, p in
        drawVIPWings(ctx, p)
        cutOutBody(ctx, p, fromBehind: true)
        if p.back { drawVIPGem(ctx, p) }   // 背對時鑽石鑲在背上
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
    ActionSpec(name: "dance", frames: 16, fps: 8, loop: true),
    ActionSpec(name: "parachute", frames: 4, fps: 4, loop: true),
    ActionSpec(name: "eat", frames: 4, fps: 5, loop: true),
    ActionSpec(name: "typing", frames: 4, fps: 6, loop: true),
    // 一格是擺盪的四分之一週期，要跟程式裡的 swingPeriod（2.4 秒）對上
    ActionSpec(name: "swing", frames: 4, fps: 4 / 2.4, loop: true),
    ActionSpec(name: "fly", frames: 2, fps: 4, loop: true),
]

func pose(_ action: String, _ i: Int, _ n: Int) -> Pose {
    var p = Pose()
    let t = CGFloat(i) / CGFloat(n) * 2 * .pi
    switch action {
    case "idle":
        p.squashY = 1 + 0.02 * sin(t)
        p.squashX = 1 - 0.012 * sin(t)
        p.armFront = 0.2 + 0.12 * sin(t)
        p.armBack = 0.2 - 0.12 * sin(t)
        p.ears = 0.08 * sin(t)
        if i == n - 1 { p.eyes = .closed }   // 最後一格眨眼
    case "walk":
        p.bodyY = abs(sin(t)) * 1.5
        p.frontFoot = CGPoint(x: 4 * sin(t), y: max(0, 3 * cos(t)))
        p.backFoot = CGPoint(x: -4 * sin(t), y: max(0, -3 * cos(t)))
        p.armFront = 0.15 - 0.5 * sin(t)       // 手跟同側腳反向擺
        p.armBack = 0.15 + 0.5 * sin(t)
        p.ears = 0.08 * sin(2 * t)
    case "run":
        p.lean = 0.12
        p.bodyY = 2 + abs(sin(t)) * 3
        p.frontFoot = CGPoint(x: 7 * sin(t), y: max(0, 5 * cos(t)))
        p.backFoot = CGPoint(x: -7 * sin(t), y: max(0, -5 * cos(t)))
        p.armFront = 0.4 - 1.0 * sin(t)
        p.armBack = 0.4 + 1.0 * sin(t)
        p.ears = 0.4 + 0.1 * sin(2 * t)        // 耳朵被風往後吹
        p.eyes = .happy
    case "jump":
        switch i {
        case 0:  // 蹲下蓄力，手往後
            p.squashX = 1.1; p.squashY = 0.86
            p.armFront = -0.5; p.armBack = -0.4; p.ears = 0.15
        case 1:  // 上升：雙手舉高（像 GIF 裡那樣歡呼）
            p.squashX = 0.95; p.squashY = 1.05; p.bodyY = 4
            p.frontFoot = CGPoint(x: -2, y: 3); p.backFoot = CGPoint(x: -3, y: 4)
            p.armFront = 2.3; p.armBack = -2.3
            p.ears = 0.45; p.eyes = .happy
        case 2:  // 下降：手張開，腳往前準備落地
            p.bodyY = 4
            p.frontFoot = CGPoint(x: 3, y: 3); p.backFoot = CGPoint(x: 1, y: 2)
            p.armFront = 1.7; p.armBack = -1.7
            p.ears = -0.2; p.mouthOpen = true
        default: // 落地緩衝
            p.squashX = 1.08; p.squashY = 0.9
            p.armFront = 0.9; p.armBack = -0.6
            p.ears = 0.25; p.eyes = .happy
        }
    case "sit":
        // 坐在地上，腳往前伸，手放在裙子上
        p.bodyY = -9
        p.lean = -0.05
        p.frontFoot = CGPoint(x: 13, y: -2)
        p.backFoot = CGPoint(x: 9, y: -2)
        p.armFront = 0.7; p.armBack = 0.6
        p.ears = i == 0 ? 0.05 : 0.2
        p.eyes = i == 0 ? .open : .happy
    case "sleep":
        // 坐著打瞌睡：低頭、耳朵垂下來
        p.bodyY = -9
        p.squashY = 0.98 + 0.02 * CGFloat(i)
        p.lean = 0.04
        p.headTilt = 0.22
        p.headDY = -1.5
        p.frontFoot = CGPoint(x: 13, y: -2)
        p.backFoot = CGPoint(x: 9, y: -2)
        p.armFront = 0.75; p.armBack = 0.65
        p.ears = 0.75 - 0.05 * CGFloat(i)
        p.eyes = .closed
        p.zzz = i + 1
    case "fall":
        p.bodyY = 6
        p.squashY = 1.03
        p.frontFoot = CGPoint(x: 4, y: i == 0 ? 8 : 5)
        p.backFoot = CGPoint(x: -3, y: i == 0 ? 5 : 8)
        p.armFront = i == 0 ? 2.1 : 2.6         // 手亂揮
        p.armBack = i == 0 ? -2.6 : -2.1
        p.ears = i == 0 ? -0.25 : 0.25
        p.eyes = .wide
        p.mouthOpen = true
    case "dragged":
        p.squashX = 0.96
        p.squashY = 1.04
        let swing: CGFloat = i == 0 ? 2 : -2
        p.frontFoot = CGPoint(x: swing, y: -1)
        p.backFoot = CGPoint(x: -swing, y: -1)
        p.armFront = 2.5; p.armBack = -2.5      // 被拎起來，手舉高
        p.ears = 0.55 + 0.15 * CGFloat(i)
        p.eyes = .wide
    case "dance":
        p = dancePose(i)
    case "eat":
        // 坐在餐桌旁的小凳子上啃胡蘿蔔（凳子畫在餐桌那張圖裡，墊在她屁股下面）。
        // 偶數格咬一口（張嘴、手往嘴邊送），奇數格嚼（閉眼笑、手稍微放下），腳懸空晃
        let bite = i % 2 == 0
        p.bodyY = bite ? 0 : -0.5
        p.frontFoot = CGPoint(x: 8, y: bite ? 4 : 3)
        p.backFoot = CGPoint(x: 5, y: bite ? 4.5 : 5.5)
        p.armBack = 0.6
        p.armFront = bite ? 2.0 : 1.85
        p.carrot = true
        p.mouthOpen = bite
        p.eyes = bite ? .open : .happy
        p.headTilt = bite ? 0.04 : 0
        p.ears = bite ? 0.05 : 0.18
    case "typing":
        // 坐在電腦桌前的小凳子上打字：前手在鍵盤上一上一下，眼睛盯著螢幕，偶爾眨眼
        p.frontFoot = CGPoint(x: 8, y: 4)
        p.backFoot = CGPoint(x: 5, y: 5)
        p.lean = 0.04
        p.armBack = 0.9
        p.armFront = i % 2 == 0 ? 1.72 : 1.88
        p.headTilt = 0.03
        p.ears = 0.06 * CGFloat(i % 2)
        if i == 3 { p.eyes = .closed }
    case "swing":
        // 坐在鞦韆上，前手抓繩子（繩子和座板由程式畫在鞦韆視窗裡）。
        // 0–1 往前盪：腳往前踢、身體往後仰；2–3 往後盪：腳收回來、身體往前
        let forward = i < 2
        p.lean = forward ? -0.07 : 0.06
        p.frontFoot = forward ? CGPoint(x: 13, y: 8) : CGPoint(x: 1, y: 2)
        p.backFoot = forward ? CGPoint(x: 10, y: 9) : CGPoint(x: -1, y: 3)
        p.armFront = 2.75
        p.armBack = 0.5
        p.ears = forward ? 0.35 : -0.15
        p.eyes = i == 1 ? .happy : .open
        p.mouthOpen = i == 1
    case "fly":
        // 坐在飛機駕駛座：腰以下被機身擋住（腳縮起來，別從機腹露出來），雙手握操縱桿，耳朵被風吹到後面
        p.frontFoot = CGPoint(x: 10, y: 8)
        p.backFoot = CGPoint(x: 7, y: 9)
        p.armFront = 1.15
        p.armBack = 1.0
        p.ears = i == 0 ? 0.55 : 0.68
        p.eyes = i == 0 ? .open : .happy
        p.mouthOpen = i == 1
    case "parachute":
        // 吊在傘下：雙手抓繩、腳懸空晃來晃去
        p.straps = true
        p.bodyY = 2
        p.lean = 0.05 * sin(t)
        p.armFront = 2.5; p.armBack = -2.5
        p.frontFoot = CGPoint(x: 2 * sin(t), y: 2)
        p.backFoot = CGPoint(x: -2 * sin(t), y: 3)
        p.ears = 0.12 * sin(t)
        p.eyes = i == 2 ? .happy : .open
    default:
        break
    }
    return p
}

// 跳舞：仿 w22wxui3joth1.gif 的舞步，16 格一輪。
//   0–7   面向前，左右搖擺、手輪流舉高，每兩拍往下一沉
//   8–13  轉身背對，左右扭屁股、兔尾巴跟著甩
//   14–15 跳一下轉回來，雙手舉高歡呼
func dancePose(_ i: Int) -> Pose {
    var p = Pose()
    let beat = i % 2 == 1                     // 奇數格是「沉下去」的那拍
    if beat {
        p.squashY = 0.93; p.squashX = 1.05
    }
    switch i {
    case 0:
        p.lean = -0.1; p.armFront = 1.9; p.armBack = -1.9; p.ears = 0.2
    case 1:
        p.armFront = 2.1; p.armBack = -2.1; p.eyes = .happy
    case 2:
        p.lean = 0.1; p.armFront = 2.15; p.armBack = -1.5; p.ears = -0.15
    case 3:
        p.armFront = 2.1; p.armBack = -2.1; p.eyes = .happy
    case 4:
        p.lean = -0.1; p.armFront = 1.5; p.armBack = -2.15; p.ears = 0.2
    case 5:
        p.armFront = 2.0; p.armBack = -2.0; p.eyes = .happy; p.mouthOpen = true
    case 6:
        p.lean = 0.1; p.bodyY = 3; p.armFront = 2.2; p.armBack = -2.2; p.ears = -0.15
        p.frontFoot = CGPoint(x: 0, y: 2); p.backFoot = CGPoint(x: 0, y: 2)
    case 7:
        p.armFront = 1.6; p.armBack = -1.6; p.eyes = .happy
    case 8...13:
        // 背對畫面扭屁股：身體往一邊倒，尾巴甩向另一邊
        p.back = true
        let side: CGFloat = (i / 2) % 2 == 0 ? 1 : -1
        p.lean = beat ? 0 : 0.18 * side
        p.tail = beat ? 0 : -4 * side
        p.armFront = beat ? 0.4 : 0.7
        p.armBack = beat ? -0.4 : -0.7
        p.ears = 0.15 * side
        p.frontFoot = CGPoint(x: 1, y: 0); p.backFoot = CGPoint(x: -1, y: 0)
    case 14:
        p.back = true; p.bodyY = 4
        p.armFront = 2.6; p.armBack = -2.6; p.ears = 0.3
        p.frontFoot = CGPoint(x: 0, y: 3); p.backFoot = CGPoint(x: 0, y: 3)
    default:
        p.armFront = 2.2; p.armBack = -2.2
        p.eyes = .happy; p.mouthOpen = true; p.ears = -0.1
    }
    return p
}

// MARK: - 降落傘（獨立道具圖）

// 繩子在寵物畫布頂端的接點（設計座標）。以畫布中線左右對稱，寵物轉向翻面時也對得上。
let canopyHeight: CGFloat = 80
let strapTop = [CGPoint(x: canvas / 2 - offsetX - 28, y: canvas), CGPoint(x: canvas / 2 - offsetX + 28, y: canvas)]

// 傘畫在 canvas × canopyHeight 的畫布上（不加 offsetX，直接用畫布座標）。
func drawCanopy(_ ctx: CGContext) {
    let cx = canvas / 2
    let rimY: CGFloat = 34
    let left: CGFloat = 5, right = canvas - 5
    let rim = (0...4).map { k in CGPoint(x: left + (right - left) * CGFloat(k) / 4, y: rimY + (k == 0 || k == 4 ? 0 : 3)) }
    let bottom = strapTop.map { CGPoint(x: $0.x + offsetX, y: 0) }

    // 繩子（傘緣 → 下方兩個接點）
    for (k, r) in rim.enumerated() {
        let b = k < 2 ? bottom[0] : (k > 2 ? bottom[1] : nil)
        if let b { line(ctx, segment(r, b), outline, width: 1.3) }
    }
    line(ctx, segment(rim[2], bottom[0]), outline, width: 1.3)
    line(ctx, segment(rim[2], bottom[1]), outline, width: 1.3)

    // 傘面：上緣半圓，下緣一段段往上拱的弧
    let dome = CGMutablePath()
    dome.move(to: rim[0])
    dome.addCurve(to: rim[4], control1: CGPoint(x: left, y: 82), control2: CGPoint(x: right, y: 82))
    for k in stride(from: 3, through: 0, by: -1) {
        let a = rim[k + 1], b = rim[k]
        dome.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: rimY + 9))
    }
    dome.closeSubpath()

    // 水藍 / 白相間的四片
    ctx.saveGState()
    ctx.addPath(dome)
    ctx.clip()
    for k in 0..<4 {
        let x0 = rim[k].x, x1 = rim[k + 1].x
        let panel = polygon([CGPoint(x: cx, y: 120), CGPoint(x: x0 + (x0 - cx) * 0.6, y: rimY - 4),
                             CGPoint(x: x1 + (x1 - cx) * 0.6, y: rimY - 4)])
        shape(ctx, panel, k % 2 == 0 ? trim : white, stroke: false)
    }
    ctx.restoreGState()
    for k in 1...3 {
        let seam = CGMutablePath()
        seam.move(to: rim[k])
        seam.addQuadCurve(to: CGPoint(x: cx, y: 74), control: CGPoint(x: rim[k].x + (rim[k].x - cx) * 0.15, y: 66))
        line(ctx, seam, outline, width: 1.4)
    }
    ctx.addPath(dome)
    ctx.setStrokeColor(outline)
    ctx.setLineWidth(2.2)
    ctx.strokePath()
    shape(ctx, ellipse(cx, 76, 6, 4), skirt, lineWidth: 1.6)
}

// MARK: - 餐桌佈景（獨立道具圖）

// 用跟寵物畫布一樣的座標（offsetX 8、地面 y=4），程式只要把寵物視窗的 x 對齊餐桌視窗的 x，
// 她就剛好坐在凳子上、面向右邊的桌子。
let diningWidth: CGFloat = 146
let diningHeight: CGFloat = 44
let wood = hex(0xC8935A)
let woodDark = hex(0x9C6B3C)

// meal：true 時盤子上放著胡蘿蔔（餵食中），false 是空盤子。
func drawDining(_ ctx: CGContext, meal: Bool) {
    // 小凳子：座面在她屁股下面（被裙子蓋住大半）
    for x in [CGFloat(40), CGFloat(57)] {
        shape(ctx, rounded(x, ground, 4, 10, 1.5), woodDark, lineWidth: 1.6)
    }
    shape(ctx, rounded(35, 12, 30, 4.5, 2), wood, lineWidth: 1.8)

    // 餐桌：兩隻腳、桌面、垂下來的格子桌巾
    for x in [CGFloat(80), CGFloat(124)] {
        shape(ctx, rounded(x, ground, 4.5, 24, 1.5), woodDark, lineWidth: 1.6)
    }
    shape(ctx, rounded(74, 27, 60, 5, 2), wood, lineWidth: 1.8)
    let cloth = polygon([CGPoint(x: 86, y: 30), CGPoint(x: 120, y: 30), CGPoint(x: 116, y: 20), CGPoint(x: 90, y: 20)])
    shape(ctx, cloth, hex(0xFFFFFF), lineWidth: 1.6)
    ctx.saveGState()
    ctx.addPath(cloth)
    ctx.clip()
    for x in stride(from: CGFloat(88), through: 120, by: 6) {
        line(ctx, segment(CGPoint(x: x, y: 31), CGPoint(x: x, y: 19)), hex(0xF08A8A, 0.7), width: 2.6)
    }
    for y in stride(from: CGFloat(22), through: 30, by: 5) {
        line(ctx, segment(CGPoint(x: 84, y: y), CGPoint(x: 122, y: y)), hex(0xF08A8A, 0.7), width: 2.6)
    }
    ctx.restoreGState()
    line(ctx, cloth, outline, width: 1.6)

    // 盤子（靠近她那一側）
    shape(ctx, ellipse(92, 33.5, 22, 5.5), hex(0xFFFFFF), lineWidth: 1.6)
    line(ctx, ellipse(92, 33.8, 14, 3), hex(0xD7E3EA), width: 1)
    if meal {
        // 兩根胡蘿蔔斜躺在盤子上
        for (c, rot) in [(CGPoint(x: 90, y: 36), CGFloat(0.25)), (CGPoint(x: 96, y: 35.5), CGFloat(-0.15))] {
            withState(ctx, { g in
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: rot)
            }) {
                shape(ctx, ellipse(6.5, 0.5, 5, 2.4), hex(0x5DB85A), lineWidth: 1.1)
                shape(ctx, polygon([CGPoint(x: -7, y: 0), CGPoint(x: 5, y: 2.6), CGPoint(x: 5, y: -2.4)]), hex(0xF39A3B), lineWidth: 1.3)
            }
        }
    }
    // 桌上的小杯子
    shape(ctx, rounded(112, 32, 7, 8, 2), hex(0x7FC8E8), lineWidth: 1.6)
}


// MARK: - 電腦桌佈景（獨立道具圖）

// 跟餐桌一樣：小凳子在左、桌子在右，寵物視窗 x 對齊電腦桌視窗 x 就坐在凳子上打電腦。
let computerWidth: CGFloat = 150
let computerHeight: CGFloat = 76

// on：true 時螢幕亮著（她在打電腦）。
func drawComputer(_ ctx: CGContext, on: Bool) {
    for x in [CGFloat(40), CGFloat(57)] {
        shape(ctx, rounded(x, ground, 4, 10, 1.5), woodDark, lineWidth: 1.6)
    }
    shape(ctx, rounded(35, 12, 30, 4.5, 2), wood, lineWidth: 1.8)

    // 書桌
    for x in [CGFloat(78), CGFloat(134)] {
        shape(ctx, rounded(x, ground, 4.5, 27, 1.5), woodDark, lineWidth: 1.6)
    }
    shape(ctx, rounded(72, 30, 70, 5, 2), wood, lineWidth: 1.8)

    // 鍵盤（她的手放在上面）
    shape(ctx, rounded(70, 35, 19, 3, 1), hex(0xE8E8EE), lineWidth: 1.4)

    // 桌上的馬克杯（在螢幕後面）
    shape(ctx, rounded(130, 35, 7, 8, 1.5), hex(0xF7C66B), lineWidth: 1.4)

    // 螢幕：腳架 + 斜斜朝向她的螢幕
    shape(ctx, rounded(103, 35, 12, 2.5, 1), hex(0x9AA0AA), lineWidth: 1.4)
    shape(ctx, rounded(107, 37, 4, 7, 1), hex(0x9AA0AA), lineWidth: 1.4)
    let body = polygon([CGPoint(x: 90, y: 42), CGPoint(x: 128, y: 44.5), CGPoint(x: 128, y: 72), CGPoint(x: 90, y: 69.5)])
    shape(ctx, body, hex(0x3A3D46), lineWidth: 1.8)
    let screen = polygon([CGPoint(x: 93, y: 45.2), CGPoint(x: 125, y: 47.3), CGPoint(x: 125, y: 69), CGPoint(x: 93, y: 66.8)])
    shape(ctx, screen, on ? hex(0x9FE3F5) : hex(0x23262E), stroke: false)
    if on {
        // 螢幕上的幾行字
        for (k, w) in [CGFloat(16), 24, 12, 20, 9].enumerated() {
            let y = 63 - CGFloat(k) * 3.8
            line(ctx, segment(CGPoint(x: 97, y: y), CGPoint(x: 97 + w, y: y + w * 0.066)), k == 2 ? hex(0xF7A1A8) : skirt, width: 1.6)
        }
    }
}

// MARK: - 鞦韆佈景（獨立道具圖）

// 一棵樹，樹枝往左伸，繩子從 swingPivot 垂下來。繩子和座板會跟著她擺，由程式畫，這張圖只有樹。
// 一樣用寵物畫布的座標：鞦韆靜止時，寵物視窗 x 對齊這張圖的 x，她就坐在座板上。
let swingWidth: CGFloat = 200
let swingHeight: CGFloat = 190
let swingPivot = CGPoint(x: 65.5, y: 130)   // 設計座標（輸出時再加 offsetX）；Scenery.swift 的 SwingRig 要跟著改

func drawSwingTree(_ ctx: CGContext) {
    let bark = hex(0x8B5E3C)
    let leaf = hex(0x7CC46A)
    let leafLight = hex(0xA6DB8C)

    // 樹幹（右邊）和往左伸的樹枝
    let trunk = CGMutablePath()
    trunk.move(to: CGPoint(x: 132, y: ground))
    trunk.addQuadCurve(to: CGPoint(x: 141, y: 150), control: CGPoint(x: 142, y: 60))
    trunk.addLine(to: CGPoint(x: 161, y: 150))
    trunk.addQuadCurve(to: CGPoint(x: 172, y: ground), control: CGPoint(x: 160, y: 60))
    trunk.closeSubpath()
    shape(ctx, trunk, bark)
    line(ctx, segment(CGPoint(x: 150, y: 28), CGPoint(x: 152, y: 52)), hex(0x6E452E), width: 1.6)
    line(ctx, segment(CGPoint(x: 156, y: 80), CGPoint(x: 155, y: 96)), hex(0x6E452E), width: 1.6)

    let branch = CGMutablePath()
    branch.move(to: CGPoint(x: 146, y: 124))
    branch.addQuadCurve(to: CGPoint(x: 55, y: 130), control: CGPoint(x: 100, y: 122))
    branch.addLine(to: CGPoint(x: 54, y: 137))
    branch.addQuadCurve(to: CGPoint(x: 146, y: 142), control: CGPoint(x: 100, y: 134))
    branch.closeSubpath()
    shape(ctx, branch, bark)

    // 樹葉：幾團圓圓的葉子，蓋住樹枝根部
    for (c, r) in [(CGPoint(x: 96, y: 150), CGFloat(17)), (CGPoint(x: 172, y: 146), CGFloat(17)),
                   (CGPoint(x: 152, y: 160), CGFloat(28)), (CGPoint(x: 122, y: 160), CGFloat(24)),
                   (CGPoint(x: 140, y: 176), CGFloat(20)), (CGPoint(x: 60, y: 146), CGFloat(13))] {
        shape(ctx, ellipse(c.x, c.y, r * 2, r * 1.6), leaf)
    }
    for c in [CGPoint(x: 144, y: 170), CGPoint(x: 116, y: 166), CGPoint(x: 172, y: 154), CGPoint(x: 92, y: 155), CGPoint(x: 56, y: 149)] {
        shape(ctx, ellipse(c.x, c.y, 10, 6), leafLight, stroke: false)
    }
    // 一朵小花和樹下的草
    shape(ctx, ellipse(108, 140, 7, 7), hex(0xF7A1A8), lineWidth: 1.2)
    for x in [CGFloat(126), 178, 186] {
        line(ctx, segment(CGPoint(x: x, y: ground), CGPoint(x: x - 3, y: ground + 7)), leaf, width: 2)
        line(ctx, segment(CGPoint(x: x, y: ground), CGPoint(x: x + 3, y: ground + 6)), leaf, width: 2)
    }
}

// MARK: - 飛機（獨立道具圖）

// 螺旋槳雙翼小飛機，機頭朝右。座標一樣跟寵物畫布對齊（offsetX 8），但上下各多留 planeMargin，
// 飛行時圖會小角度傾斜才不會被切掉；程式要把視窗往下放 planeMargin，地面才對得上。
// 分三張：
//   plane.png         停著的樣子（整台，螺旋槳靜止）
//   plane_back.png    她坐進去後，墊在她後面的部分（尾翼、上翼、椅背、機身）
//   plane_front_N.png 擋在她前面的部分（機身、擋風玻璃、下翼、輪子、轉動的螺旋槳）
// 駕駛座：她的屁股在設計座標 (50, 17)，跟坐凳子一樣。Scenery.swift 的 planeSeat 要跟著改。
let planeWidth: CGFloat = 180
let planeMargin: CGFloat = 16
let planeHeight: CGFloat = planeMargin * 2 + 60
let planeRed = hex(0xE8615A)
let planeYellow = hex(0xF7C66B)
let planeDark = hex(0x3A3D46)

enum PlanePart { case parked, back, front(Int) }

func drawPlane(_ ctx: CGContext, _ part: PlanePart) {
    ctx.translateBy(x: 0, y: planeMargin)
    var showBack = true, showFront = true
    var propFrame: Int? = nil   // nil：靜止的槳
    switch part {
    case .parked: break
    case .back: showFront = false
    case .front(let k): showBack = false; propFrame = k
    }

    if showBack {
        // 垂直尾翼
        shape(ctx, polygon([CGPoint(x: 1, y: 31), CGPoint(x: 4, y: 52), CGPoint(x: 14, y: 52), CGPoint(x: 26, y: 32)]), planeRed)
        line(ctx, segment(CGPoint(x: 6, y: 48), CGPoint(x: 13, y: 48)), white, width: 2)
        // 上翼和支柱（在她前方，不會擋到臉）
        line(ctx, segment(CGPoint(x: 92, y: 31), CGPoint(x: 96, y: 52)), planeDark, width: 2)
        line(ctx, segment(CGPoint(x: 104, y: 31), CGPoint(x: 106, y: 52)), planeDark, width: 2)
        shape(ctx, rounded(84, 51, 56, 6, 3), planeYellow)
        // 椅背
        shape(ctx, rounded(25, 26, 11, 16, 4), hex(0x8B5E3C))
    }

    // 機身：尾巴細、機頭圓。停著和前層都要畫（前層擋住她的下半身），後層也畫，飛起來時從縫隙看不到底
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 0, y: 32))
    body.addLine(to: CGPoint(x: 140, y: 33))
    body.addQuadCurve(to: CGPoint(x: 160, y: 22), control: CGPoint(x: 160, y: 33))
    body.addQuadCurve(to: CGPoint(x: 140, y: 11), control: CGPoint(x: 160, y: 11))
    body.addLine(to: CGPoint(x: 46, y: 11))
    body.addQuadCurve(to: CGPoint(x: 0, y: 25), control: CGPoint(x: 12, y: 13))
    body.closeSubpath()

    if showFront {
        // 尾輪
        line(ctx, segment(CGPoint(x: 14, y: 16), CGPoint(x: 13, y: 8)), planeDark, width: 2)
        shape(ctx, ellipse(13, 7, 6, 6), planeDark, lineWidth: 1.4)
        // 主輪
        line(ctx, segment(CGPoint(x: 104, y: 14), CGPoint(x: 110, y: 10)), planeDark, width: 2.4)
        line(ctx, segment(CGPoint(x: 120, y: 14), CGPoint(x: 112, y: 10)), planeDark, width: 2.4)
        shape(ctx, ellipse(111, 10, 12, 12), planeDark)
        shape(ctx, ellipse(111, 10, 4.5, 4.5), hex(0x9AA0AA), lineWidth: 1.2)
    }

    if showFront || showBack {
        shape(ctx, body, planeRed)
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        line(ctx, segment(CGPoint(x: 0, y: 21), CGPoint(x: 160, y: 21)), hex(0xFFF3E0), width: 3)
        shape(ctx, rounded(138, 0, 30, 40, 0), hex(0xC9CED6), stroke: false)   // 引擎罩
        ctx.restoreGState()
        ctx.addPath(body)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(2.2)
        ctx.strokePath()
        line(ctx, segment(CGPoint(x: 138, y: 13), CGPoint(x: 138, y: 32)), outline, width: 1.6)
    }

    if showFront {
        // 機身上的愛心
        let heart = CGMutablePath()
        heart.move(to: CGPoint(x: 120, y: 18))
        heart.addCurve(to: CGPoint(x: 120, y: 27), control1: CGPoint(x: 112, y: 22), control2: CGPoint(x: 115, y: 30))
        heart.addCurve(to: CGPoint(x: 120, y: 18), control1: CGPoint(x: 125, y: 30), control2: CGPoint(x: 128, y: 22))
        shape(ctx, heart, hex(0xF7A1A8), lineWidth: 1.4)
        // 駕駛艙邊緣和擋風玻璃
        shape(ctx, rounded(32, 30, 44, 4, 2), planeDark, lineWidth: 1.6)
        shape(ctx, polygon([CGPoint(x: 76, y: 33), CGPoint(x: 80, y: 46), CGPoint(x: 86, y: 46), CGPoint(x: 88, y: 33)]),
              hex(0xBFEAF7, 0.75), lineWidth: 1.6)
        // 水平尾翼、下翼
        shape(ctx, ellipse(13, 28, 28, 6), planeYellow, lineWidth: 1.8)
        shape(ctx, rounded(86, 13, 50, 6, 3), planeYellow)
        // 翼間支柱（前面那一對）
        line(ctx, segment(CGPoint(x: 92, y: 19), CGPoint(x: 92, y: 31)), planeDark, width: 2)
        line(ctx, segment(CGPoint(x: 130, y: 19), CGPoint(x: 133, y: 52)), planeDark, width: 2)
    }

    // 螺旋槳
    if case .back = part { return }
    if let k = propFrame {
        shape(ctx, ellipse(163, 22, 6, 38), hex(0xDDE3EA, 0.45), stroke: false)
        shape(ctx, ellipse(163, 22, 3.5, k == 0 ? 34 : 12), hex(0x8B5E3C, 0.75), lineWidth: 1.2)
    } else {
        shape(ctx, ellipse(163, 22, 4, 34), hex(0x8B5E3C), lineWidth: 1.6)
    }
    shape(ctx, ellipse(162, 22, 7, 9), planeDark, lineWidth: 1.6)
}

// MARK: - 輸出

func renderPNG(width: CGFloat = canvas, height: CGFloat = canvas, offset: CGFloat = offsetX, _ draw: (CGContext) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: offset, y: 0)
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
        var p = pose(spec.name, i, spec.frames)
        p.frame = i
        p.frameCount = spec.frames
        try write(renderPNG { drawBody($0, p) }, "body/\(spec.name)_\(i).png")
        count += 1
        for outfit in outfits {
            try write(renderPNG { outfit.draw($0, p) }, "outfits/\(outfit.id)/\(spec.name)_\(i).png")
            count += 1
        }
    }
}

try write(renderPNG(height: canopyHeight, offset: 0) { drawCanopy($0) }, "props/parachute.png")
try write(renderPNG(width: diningWidth, height: diningHeight) { drawDining($0, meal: false) }, "props/dining.png")
try write(renderPNG(width: diningWidth, height: diningHeight) { drawDining($0, meal: true) }, "props/dining_meal.png")
try write(renderPNG(width: computerWidth, height: computerHeight) { drawComputer($0, on: false) }, "props/computer.png")
try write(renderPNG(width: computerWidth, height: computerHeight) { drawComputer($0, on: true) }, "props/computer_on.png")
try write(renderPNG(width: swingWidth, height: swingHeight) { drawSwingTree($0) }, "props/swing.png")
for (part, name) in [(PlanePart.parked, "plane"), (.back, "plane_back"), (.front(0), "plane_front_0"), (.front(1), "plane_front_1")] {
    try write(renderPNG(width: planeWidth, height: planeHeight) { drawPlane($0, part) }, "props/\(name).png")
}
count += 10

// manifest.json：程式靠它知道有哪些動作、幾格、多快，以及有哪些服裝。
let manifest: [String: Any] = [
    "canvas": ["width": canvas, "height": canvas],
    "actions": Dictionary(uniqueKeysWithValues: actions.map {
        ($0.name, ["frames": $0.frames, "fps": $0.fps, "loop": $0.loop] as [String: Any])
    }),
    // 疊圖順序：前面的在下面。背後的東西最先畫，手上拿的最後畫
    "slots": [
        ["id": "back", "name": "背後"],
        ["id": "neck", "name": "脖子"],
        ["id": "face", "name": "臉"],
        ["id": "head", "name": "頭"],
        ["id": "hand", "name": "手上"],
    ],
    "outfits": outfits.map {
        ["id": $0.id, "name": $0.name, "slot": $0.slot,
         "power": outfitPower[$0.id] ?? 0, "dungeon": dungeonOutfits.contains($0.id)] as [String: Any]
    },
]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try write(json, "manifest.json")

print("已產生 \(count) 張圖到 \(outputRoot.path)")
