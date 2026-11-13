// generate-bunny.swift —— 產生角色的 Q 版向量風格素材。
//
// 用法（在專案根目錄）：
//     swift Tools/generate-bunny.swift            # 阿米婭（預設）
//     swift Tools/generate-bunny.swift rim        # 理芽
//
// 角色的本體、服裝、manifest.json 寫到 Sources/SmallPet/Resources/characters/<角色>/，
// 家具等道具圖寫到 Resources/props/（所有角色共用）。
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

// 第一個參數是角色 id，第二個（可省略）是 Resources 資料夾。
let characterNames = ["amiya": "阿米婭", "rim": "理芽"]
let character = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "amiya"
guard let characterName = characterNames[character] else {
    fatalError("不認識的角色 \(character)，可用：\(characterNames.keys.sorted())")
}
let rim = character == "rim"
let resourcesRoot = URL(fileURLWithPath: CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "Sources/SmallPet/Resources")
let outputRoot = resourcesRoot.appendingPathComponent("characters/\(character)")

// MARK: - 顏色

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: a)
}

let outline = hex(0x2B2230)
// 理芽：藍色鮑伯頭、橘色帽兜內裡、紅色線條、橘紅裙、藍鞋。
let hair = rim ? hex(0x2336D6) : hex(0x8A5A3C)
let hairDark = rim ? hex(0x1A259C) : hex(0x6E452E)
let hairShine = rim ? hex(0x9DB2FF) : hex(0xCDEBF7)
let earInner = hex(0xE9C6B4)
let skin = hex(0xFFEBDF)
let cheek = hex(0xF7A1A8, 0.6)
let eyeDark = rim ? hex(0x1B2268) : hex(0x1F3F66)
let eyeIris = rim ? hex(0x4C6BF0) : hex(0x46C1DE)
let jacket = hex(0x2A2A33)
let trim = rim ? hex(0xF29A2E) : hex(0x5CD0E0)        // 帽兜內裡
let jacketLine = rim ? hex(0xD8433A) : trim             // 外套線條、袖口
let top = rim ? hex(0x2B2348) : hex(0x34304A)
let skirt = rim ? hex(0xE8542A) : hex(0x3F7EC0)
let skirtLight = rim ? hex(0xF27A4A) : hex(0x6FA6DC)
let legging = hex(0x24242C)
let shoe = rim ? hex(0x3446C8) : hex(0x17171D)
let gemRed = hex(0xE0383A)
let gemGreen = hex(0x2FB36A)
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
    var parasol = false             // 撐著雨傘飄下來（拿雨傘時代替降落傘；傘柄一路畫到畫布頂端）
    var carrot = false              // 前手拿著胡蘿蔔，尖端朝嘴巴（吃東西用）
    var sword = false               // 前手握著劍（地下城打 boss 用）
    var slash: CGFloat = 0          // 揮劍的刀光：0 沒有，越大越亮
    var slashFrom: CGFloat = 0      // 刀光從哪個手臂角度劃到現在的角度
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
// 畫像素風格時（renderPixelPNG），一個像素是幾個設計單位；0 代表平常的向量畫法。
// 像素風格下線條至少一個像素粗，不然關掉反鋸齒後細線會斷掉。
var pixelCell: CGFloat = 0
func lineWidthFor(_ w: CGFloat) -> CGFloat { pixelCell > 0 ? max(w, pixelCell) : w }

// 發光（模糊陰影）。像素風格不要模糊，直接略過。
func setGlow(_ ctx: CGContext, blur: CGFloat, _ color: CGColor) {
    guard pixelCell == 0 else { return }
    ctx.setShadow(offset: .zero, blur: blur, color: color)
}

func shape(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, stroke: Bool = true, lineWidth: CGFloat = 2.2) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
    if stroke {
        ctx.addPath(path)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(lineWidthFor(lineWidth))
        ctx.strokePath()
    }
}

func line(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, width: CGFloat) {
    ctx.addPath(path)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidthFor(width))
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

// 本體拆成四層，好讓髮型和服裝可以自由搭配（見下方「外觀」）。由下往上：
//   hairBehind  垂在身體後面的長髮（雙馬尾、公主切的長髮…）
//   base        腳、垂下的手、衣服（還有降落傘的繩子）
//   head        頭：兔耳、臉、頭髮（背對時還有兔尾巴和蓋住背的長髮）
//   top         擋在頭前面的東西：舉高的手、胡蘿蔔、睡覺的 z
// 四層全畫 = 完整的她；App 會依目前選的髮型 / 服裝，各層挑對應的圖疊起來。
enum BodyPart { case hairBehind, base, head, top }
let allParts: Set<BodyPart> = [.hairBehind, .base, .head, .top]

func drawBody(_ ctx: CGContext, _ p: Pose, _ parts: Set<BodyPart> = allParts) {
    if p.back { return drawBodyBack(ctx, p, parts) }
    let ut = upperTransform(p)

    if parts.contains(.hairBehind) {
        withState(ctx, head(p)) { look.hair.behind(ctx, p) }
    }

    if parts.contains(.base) {
        // 降落傘的繩子：從兩手拉到畫布頂端，接上視窗上方那頂傘（最先畫，被頭擋住也沒關係）
        if p.straps {
            for (s, angle, top) in [(shoulderBack, p.armBack, strapTop[0]), (shoulderFront, p.armFront, strapTop[1])] {
                line(ctx, segment(hand(s, angle).applying(ut), top), outline, width: 1.3)
            }
        }

        // 她面向右邊、身體斜四分之三：畫面左邊那隻手（shoulderBack）是靠近我們的手，要擋在衣服前面；
        // 畫面右邊、臉那一側的手（shoulderFront，拿東西、打字、揮劍用的）是遠的那隻，從身體後面伸出來。
        drawLeg(ctx, from: hipBack.applying(ut), to: CGPoint(x: footBack.x + p.backFoot.x, y: footBack.y + p.backFoot.y))
        if !raised(p.armFront) { withState(ctx, upper(p)) { drawArm(ctx, shoulderFront, p.armFront) } }
        drawLeg(ctx, from: hipFront.applying(ut), to: CGPoint(x: footFront.x + p.frontFoot.x, y: footFront.y + p.frontFoot.y))

        withState(ctx, upper(p)) {
            look.clothes.torso(ctx, p)
            if !raised(p.armBack) { drawArm(ctx, shoulderBack, p.armBack) }
        }
    }

    if parts.contains(.head) {
        withState(ctx, head(p)) { drawHead(ctx, p) }
    }

    if parts.contains(.top) {
        // 胡蘿蔔在臉前面、手的後面，看起來像握在手裡
        if p.carrot { withState(ctx, upper(p)) { drawCarrot(ctx, at: hand(shoulderFront, p.armFront)) } }

        // 舉高的手要畫在頭前面，不然會被大頭擋住
        withState(ctx, upper(p)) {
            if raised(p.armBack) { drawArm(ctx, shoulderBack, p.armBack) }
            if raised(p.armFront) { drawArm(ctx, shoulderFront, p.armFront) }
        }

        // 劍（和刀光）永遠在最前面，看起來握在手裡
        if p.sword { withState(ctx, upper(p)) { drawSword(ctx, p) } }

        // 睡覺的 z
        for i in 0..<p.zzz {
            drawZ(ctx, at: CGPoint(x: 74 + CGFloat(i) * 8, y: 66 + CGFloat(i) * 10), size: 6 + CGFloat(i) * 2)
        }
    }
}

// MARK: - 背面（轉身時用）

func drawBodyBack(_ ctx: CGContext, _ p: Pose, _ parts: Set<BodyPart>) {
    let ut = upperTransform(p)

    // 背對時長髮蓋在背上，所以全部畫在 head 層，hairBehind 層是空的。
    if parts.contains(.base) {
        drawLeg(ctx, from: hipBack.applying(ut), to: CGPoint(x: footBack.x + p.backFoot.x, y: footBack.y + p.backFoot.y))
        drawLeg(ctx, from: hipFront.applying(ut), to: CGPoint(x: footFront.x + p.frontFoot.x, y: footFront.y + p.frontFoot.y))

        withState(ctx, upper(p)) {
            // 背面看得到垂下的手臂在身體兩側
            if !raised(p.armBack) { drawArm(ctx, shoulderBack, p.armBack) }
            if !raised(p.armFront) { drawArm(ctx, shoulderFront, p.armFront) }
            look.clothes.torsoBack(ctx, p)
        }
    }

    if parts.contains(.head) {
        // 圓圓的兔尾巴（跟頭髮同色；理芽沒有）
        if !rim { withState(ctx, upper(p)) {
            shape(ctx, ellipse(50 + p.tail, 20, 10, 9), look.hair.color)
            shape(ctx, ellipse(48.5 + p.tail, 21.5, 3.5, 2.5), look.hair.shine, stroke: false)
        } }

        withState(ctx, head(p)) {
            // 兔耳背面：沒有粉色內側
            for (root, base, k) in [(CGPoint(x: 40, y: 72), CGFloat(0.3), CGFloat(1)),
                                    (CGPoint(x: 60, y: 72), CGFloat(-0.3), CGFloat(1))] where !rim {
                withState(ctx, { c in
                    c.translateBy(x: root.x, y: root.y)
                    c.rotate(by: base + p.ears * k)
                }) {
                    shape(ctx, ellipse(0, 13, 12, 28), look.hair.dark)
                }
            }
            look.hair.backView(ctx, p)
        }
    }

    if parts.contains(.top) {
        withState(ctx, upper(p)) {
            if raised(p.armBack) { drawArm(ctx, shoulderBack, p.armBack) }
            if raised(p.armFront) { drawArm(ctx, shoulderFront, p.armFront) }
        }
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
    let c = look.clothes
    ctx.setLineCap(.round)
    line(ctx, segment(hip, foot), outline, width: 9)
    line(ctx, segment(hip, foot), c.legging, width: 6.2)
    // 短襪：腳踝上面一小段
    if let sock = c.sock {
        let len = max(hypot(hip.x - foot.x, hip.y - foot.y), 0.001)
        let top = CGPoint(x: foot.x + (hip.x - foot.x) / len * 3.5, y: foot.y + (hip.y - foot.y) / len * 3.5)
        line(ctx, segment(top, foot), sock, width: 6.2)
    }
    // 鞋底固定貼地，厚底鞋只往上長
    let h = c.shoeHeight
    shape(ctx, ellipse(foot.x + 1.5, foot.y - 0.5 + (h - 6.5) / 2, 10, h), c.shoe, lineWidth: 1.8)
}

func raised(_ angle: CGFloat) -> Bool { abs(angle) > 1.3 }

// 手（白色圓手的中心）在上半身座標裡的位置。
func hand(_ s: CGPoint, _ angle: CGFloat) -> CGPoint {
    CGPoint(x: s.x + sin(angle) * 12.5, y: s.y - cos(angle) * 12.5)
}

// 手臂：袖子 + 袖口 + 白色圓手（顏色、袖子粗細看目前的服裝）。角度 0 垂下，往前轉為正。
func drawArm(_ ctx: CGContext, _ s: CGPoint, _ angle: CGFloat) {
    let c = look.clothes
    let w = c.sleeveWidth
    let d = CGPoint(x: sin(angle), y: -cos(angle))
    func at(_ k: CGFloat) -> CGPoint { CGPoint(x: s.x + d.x * k, y: s.y + d.y * k) }
    ctx.setLineCap(.round)
    line(ctx, segment(s, at(9)), outline, width: w + 2.4)
    line(ctx, segment(s, at(9)), c.sleeve, width: w)
    ctx.setLineCap(.butt)
    line(ctx, segment(at(8), at(10)), outline, width: w + 2.4)
    line(ctx, segment(at(8.4), at(9.6)), c.cuff, width: w)
    ctx.setLineCap(.round)
    let h = hand(s, angle)
    shape(ctx, ellipse(h.x, h.y, 7.5, 7.5), white, lineWidth: 1.8)
}

func drawHead(_ ctx: CGContext, _ p: Pose) {
    // 兔耳（先畫，讓頭髮蓋住耳根）
    for (root, base, k) in [(CGPoint(x: 40, y: 72), CGFloat(0.3), CGFloat(1)),
                            (CGPoint(x: 60, y: 74), CGFloat(-0.18), CGFloat(0.8))] where !rim {
        withState(ctx, { c in
            c.translateBy(x: root.x, y: root.y)
            c.rotate(by: base + p.ears * k)
        }) {
            shape(ctx, ellipse(0, 13, 12, 28), look.hair.color)
            shape(ctx, ellipse(0.5, 14, 5.5, 19), earInner, stroke: false)
        }
    }

    // 後腦的頭髮（在臉後面）
    look.hair.backOfHead(ctx, p)

    // 臉
    shape(ctx, ellipse(54, 51, 40, 32), skin)

    // 臉前面的頭髮：兩側髮束、瀏海、光澤
    look.hair.front(ctx, p)

    // 臉頰
    shape(ctx, ellipse(40, 44, 7, 3.6), cheek, stroke: false)
    shape(ctx, ellipse(68, 44, 7, 3.6), cheek, stroke: false)

    drawEye(ctx, eyeBack, p.eyes)
    drawEye(ctx, eyeFront, p.eyes)

    // ω 嘴
    ctx.setLineCap(.round)
    if p.mouthOpen {
        shape(ctx, ellipse(54.5, 42, 5, 4.5), hex(0xC8504F), lineWidth: 1.5)
    } else if rim {
        // 理芽：小小的微笑
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: 52, y: 43.5))
        mouth.addQuadCurve(to: CGPoint(x: 57, y: 43.5), control: CGPoint(x: 54.5, y: 41))
        line(ctx, mouth, outline, width: 1.5)
    } else {
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: 51.5, y: 43.5))
        mouth.addQuadCurve(to: CGPoint(x: 54.5, y: 43), control: CGPoint(x: 52.8, y: 41.2))
        mouth.addQuadCurve(to: CGPoint(x: 57.5, y: 43.5), control: CGPoint(x: 56.2, y: 41.2))
        line(ctx, mouth, outline, width: 1.5)
    }
}

// 理芽的辮子：一節一節的小橢圓，尾端綁一小撮。sway 讓它跟著動作微微擺。
func drawBraid(_ ctx: CGContext, top: CGPoint, bottom: CGPoint, sway: CGFloat) {
    let n = 4
    let end = CGPoint(x: bottom.x - sway * 3, y: bottom.y)
    for i in 0..<n {
        let k = CGFloat(i) / CGFloat(n - 1)
        let c = CGPoint(x: top.x + (end.x - top.x) * k * k, y: top.y + (end.y - top.y) * k)
        shape(ctx, ellipse(c.x, c.y, 5 - k * 0.8, 5), i % 2 == 0 ? hair : hairDark, lineWidth: 1.2)
    }
    shape(ctx, ellipse(end.x, end.y - 2.5, 2.4, 2.4), hex(0x2B2348), lineWidth: 0.9)
    shape(ctx, petal(CGPoint(x: end.x, y: end.y - 3.4), CGPoint(x: end.x - sway * 2, y: end.y - 7.5), width: 2.4), hair, lineWidth: 1.2)
}

// 紅框綠心的菱形耳環。
func drawEarring(_ ctx: CGContext, at c: CGPoint) {
    shape(ctx, polygon([CGPoint(x: c.x, y: c.y + 4), CGPoint(x: c.x + 2.8, y: c.y), CGPoint(x: c.x, y: c.y - 4),
                        CGPoint(x: c.x - 2.8, y: c.y)]), gemRed, lineWidth: 1.1)
    shape(ctx, polygon([CGPoint(x: c.x, y: c.y + 1.8), CGPoint(x: c.x + 1.2, y: c.y), CGPoint(x: c.x, y: c.y - 1.8),
                        CGPoint(x: c.x - 1.2, y: c.y)]), gemGreen, stroke: false)
}

// 理芽的眼睛：深靛藍虹膜、裡面一圈紅色細環、黃色水滴形瞳孔光點，上眼線粗、眼尾往外勾。
func drawRimEye(_ ctx: CGContext, _ c: CGPoint, wide: Bool) {
    ctx.setLineCap(.round)
    let w: CGFloat = wide ? 9.5 : 8.5, h: CGFloat = wide ? 11.5 : 10
    let eye = ellipse(c.x, c.y - 0.5, w, h)
    if wide { shape(ctx, ellipse(c.x, c.y - 0.5, w + 1.5, h + 1), white, lineWidth: 1.4) }
    shape(ctx, eye, hex(0x1C1660), stroke: false)
    ctx.saveGState()
    ctx.addPath(eye)
    ctx.clip()
    shape(ctx, ellipse(c.x, c.y - 3, w, h * 0.7), hex(0x3B2FA6), stroke: false)   // 下半部亮一點的靛藍
    ctx.restoreGState()
    // 紅色細環（只畫下半圈多一點，像參考圖那樣）
    let ring = CGMutablePath()
    ring.addArc(center: CGPoint(x: c.x, y: c.y - 0.5), radius: w * 0.34, startAngle: .pi * 1.05, endAngle: .pi * 2.05, clockwise: false)
    line(ctx, ring, hex(0xE0383A, 0.85), width: 0.6)
    // 黃色水滴光點
    let drop = CGMutablePath()
    let d = CGPoint(x: c.x + 0.6, y: c.y - 0.3)
    drop.move(to: CGPoint(x: d.x + 0.4, y: d.y + 2.3))
    drop.addQuadCurve(to: CGPoint(x: d.x - 0.2, y: d.y - 1.6), control: CGPoint(x: d.x + 1.9, y: d.y - 0.3))
    drop.addQuadCurve(to: CGPoint(x: d.x + 0.4, y: d.y + 2.3), control: CGPoint(x: d.x - 1.6, y: d.y + 0.2))
    shape(ctx, drop, hex(0xFFE33A), stroke: false)
    // 粗上眼線 + 眼尾往外上勾
    let lid = CGMutablePath()
    lid.move(to: CGPoint(x: c.x - 5, y: c.y + 2.8))
    lid.addQuadCurve(to: CGPoint(x: c.x + 4.6, y: c.y + 3.4), control: CGPoint(x: c.x, y: c.y + 6.4))
    lid.addLine(to: CGPoint(x: c.x + 6.6, y: c.y + 5))
    line(ctx, lid, outline, width: 2.4)
    if !wide {   // 微微下垂的眼皮，讓眼神比較冷靜
        let shade = CGMutablePath()
        shade.move(to: CGPoint(x: c.x - 4.2, y: c.y + 3))
        shade.addQuadCurve(to: CGPoint(x: c.x + 4.2, y: c.y + 3), control: CGPoint(x: c.x, y: c.y + 1.6))
        line(ctx, shade, hex(0x1C1660, 0.6), width: 1)
    }
}

func drawEye(_ ctx: CGContext, _ c: CGPoint, _ eyes: Eyes) {
    ctx.setLineCap(.round)
    if rim && (eyes == .open || eyes == .wide) { return drawRimEye(ctx, c, wide: eyes == .wide) }
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
    setGlow(ctx, blur: 3, hex(0xFFE27A))
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
    "balloon": 1, "lollipop": 2, "umbrella": 4, "backpack": 3, "wings": 6, "vip_wings": 20,
]
// 只能從地下城拿到的服裝（還沒拿到前不會出現在衣櫃）。
let dungeonOutfits: Set<String> = [
    "straw_hat", "balloon", "bell_collar",          // 草原
    "witch_hat", "cape", "goggles", "backpack",     // 森林
    "crown", "ribbon", "wings",                     // 城堡
    "vip_wings",                                    // 星空神殿
]

// 哥德雨傘的顏色與撐開的傘面（降落時用的道具圖）。
let umbrellaBlack = hex(0x1E1A24), umbrellaShade = hex(0x3A2D4A), umbrellaWine = hex(0x9B2242)
let umbrellaLace = hex(0xF1ECF4), umbrellaShaft = hex(0x9A95A6)

// 撐開的傘（哥德蘿莉的鐘形洋傘）：c 是傘面下緣的中心，r 半徑、dome 高度。
// 黑 / 深紫相間的六片傘面，下緣一圈白蕾絲，傘骨尖端掛酒紅小珠，傘頂蝴蝶結 + 尖頂。
func drawOpenUmbrella(_ ctx: CGContext, rim c: CGPoint, radius r: CGFloat, dome: CGFloat) {
    let n = 6
    let tip = pt(c.x, c.y + dome)
    // 傘骨尖端：中間的比兩端低一點，看起來有弧度
    let ribs = (0...n).map { k -> CGPoint in
        let f = CGFloat(k) / CGFloat(n)
        return pt(c.x - r + r * 2 * f, c.y - 3 * sin(.pi * f))
    }
    func edge(_ k: Int, _ f: CGFloat) -> CGPoint {   // 第 k 片下緣上的點（兩根傘骨之間往上拱）
        let a = ribs[k], b = ribs[k + 1], m = pt((a.x + b.x) / 2, (a.y + b.y) / 2 + 4)
        return lerp(lerp(a, m, f), lerp(m, b, f), f)
    }
    // 白蕾絲：沿著下緣一顆顆小圓，傘面蓋住上半
    for k in 0..<n {
        for j in 0...4 {
            let q = edge(k, CGFloat(j) / 4)
            shape(ctx, ellipse(q.x, q.y - 0.6, 3.6, 3.6), umbrellaLace, lineWidth: 0.8)
        }
    }
    // 鐘形傘面：下襬外張、往上收成尖頂
    let canopy = CGMutablePath()
    canopy.move(to: ribs[0])
    canopy.addCurve(to: tip, control1: pt(c.x - r * 0.78, c.y + dome * 0.5), control2: pt(c.x - r * 0.2, c.y + dome * 0.62))
    canopy.addCurve(to: ribs[n], control1: pt(c.x + r * 0.2, c.y + dome * 0.62), control2: pt(c.x + r * 0.78, c.y + dome * 0.5))
    for k in stride(from: n - 1, through: 0, by: -1) {
        let a = ribs[k + 1], b = ribs[k]
        canopy.addQuadCurve(to: b, control: pt((a.x + b.x) / 2, (a.y + b.y) / 2 + 4))
    }
    canopy.closeSubpath()
    shape(ctx, canopy, umbrellaBlack, stroke: false)
    func rib(_ k: Int) -> CGPath {
        quad(tip, ribs[k], pt(c.x + (ribs[k].x - c.x) * 0.72, c.y + dome * 0.62))
    }
    // 隔一片塗深紫
    clipped(ctx, to: canopy) {
        for k in stride(from: 1, to: n, by: 2) {
            let panel = CGMutablePath()
            panel.addPath(rib(k))
            panel.addLine(to: pt(ribs[k].x, c.y - 8)); panel.addLine(to: pt(ribs[k + 1].x, c.y - 8)); panel.addLine(to: ribs[k + 1])
            panel.addQuadCurve(to: tip, control: pt(c.x + (ribs[k + 1].x - c.x) * 0.72, c.y + dome * 0.62))
            panel.closeSubpath()
            shape(ctx, panel, umbrellaShade, stroke: false)
        }
        shape(ctx, ellipse(c.x - r * 0.42, c.y + dome * 0.42, r * 0.34, 4), hex(0xFFFFFF, 0.16), stroke: false)   // 光澤
    }
    for k in 1..<n { line(ctx, rib(k), outline, width: 1) }
    ctx.addPath(canopy); ctx.setStrokeColor(outline); ctx.setLineWidth(2); ctx.strokePath()
    for q in ribs { shape(ctx, ellipse(q.x, q.y - 1, 3, 3), umbrellaWine, lineWidth: 0.9) }   // 傘骨尖端的小珠
    // 傘頂：尖頂 + 銀珠 + 酒紅蝴蝶結
    line(ctx, segment(tip, pt(tip.x, tip.y + 7)), outline, width: 2.2)
    line(ctx, segment(pt(tip.x, tip.y + 1), pt(tip.x, tip.y + 6.5)), umbrellaShaft, width: 0.9)
    shape(ctx, ellipse(tip.x, tip.y + 8, 3, 3), umbrellaShaft, lineWidth: 0.9)
    drawBow(ctx, at: pt(tip.x, tip.y + 0.5), size: 2.6, umbrellaWine)
}

// 撐傘飄下來時，傘柄在寵物畫布頂端的 x（設計座標，就是舉起的前手正上方）。
let parasolX: CGFloat = 70

// 道具圖：撐開的雨傘，傘柄從畫布底部往上接到傘面（跟寵物圖裡的傘柄接起來）。
// 道具圖不加 offsetX，所以這裡要自己加上。
func drawUmbrellaProp(_ ctx: CGContext) {
    let c = pt(parasolX + offsetX, 32)
    line(ctx, segment(pt(c.x, -2), pt(c.x, c.y + 6)), outline, width: 2.6)
    line(ctx, segment(pt(c.x, -2), pt(c.x, c.y + 6)), umbrellaShaft, width: 1.2)
    drawOpenUmbrella(ctx, rim: c, radius: 29, dome: 30)
}

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

    // 哥德雨傘：平常收起來拿在手上（順著手臂方向）；從高處掉下來時撐開代替降落傘，
    // 撐開的傘面是獨立道具圖 props/umbrella_open.png，這裡只畫從手伸到畫布頂端的傘柄。
    Outfit(id: "umbrella", name: "哥德雨傘", slot: "hand") { ctx, p in
        guard !p.carrot else { return }
        if p.parasol {
            // 傘柄從手直直往上，在 x = parasolX 跟道具圖的傘柄接起來（App 會讓道具圖跟著她轉向翻面）
            let h = hand(shoulderFront, p.armFront).applying(upperTransform(p))
            let top = pt(parasolX, canvas + 2)
            line(ctx, segment(h, top), outline, width: 2.6)
            line(ctx, segment(h, top), umbrellaShaft, width: 1.2)
            // 手下面的酒紅彎鉤握把
            let hook = quad(pt(h.x, h.y - 2), pt(h.x + 5, h.y - 5), pt(h.x + 1.5, h.y - 10))
            line(ctx, hook, outline, width: 3.2)
            line(ctx, hook, umbrellaWine, width: 1.7)
            cutOutBody(ctx, p, fromBehind: true)   // 傘柄在頭和身體後面，手（本體）蓋在上面像握著
            return
        }
        withState(ctx, upper(p)) {
            let h = hand(shoulderFront, p.armFront)
            let a = p.armFront + 0.6                             // 順著手臂再往前斜一點，傘尖才不會插進腳裡
            let d = pt(sin(a), -cos(a))
            func at(_ k: CGFloat, side: CGFloat = 0) -> CGPoint { pt(h.x + d.x * k - d.y * side, h.y + d.y * k + d.x * side) }
            // 酒紅彎鉤握把（在手的另一邊）
            let hook = CGMutablePath()
            hook.move(to: at(1)); hook.addLine(to: at(-5))
            hook.addQuadCurve(to: at(-5.5, side: 5.5), control: at(-10.5, side: 2.8))
            line(ctx, hook, outline, width: 3.4)
            line(ctx, hook, umbrellaWine, width: 1.8)
            // 傘尖（銀色）
            line(ctx, segment(at(23), at(29)), outline, width: 2.2)
            line(ctx, segment(at(24), at(28.5)), umbrellaShaft, width: 0.9)
            // 收攏的傘面開口那一圈白蕾絲，蓬在握把這頭
            for side in [CGFloat(-3.4), 0, 3.4] {
                let q = at(side == 0 ? 3.6 : 4.6, side: side)
                shape(ctx, ellipse(q.x, q.y, 4.6, 4.6), umbrellaLace, lineWidth: 0.9)
            }
            // 收起來的傘面：靠握把這頭比較蓬、往傘尖收細，上面兩道摺痕
            let furl = CGMutablePath()
            furl.move(to: at(4.5, side: 3.2))
            furl.addQuadCurve(to: at(25), control: at(14, side: 4.6))
            furl.addQuadCurve(to: at(4.5, side: -3.2), control: at(14, side: -4.6))
            furl.addQuadCurve(to: at(4.5, side: 3.2), control: at(6.5))
            furl.closeSubpath()
            shape(ctx, furl, umbrellaBlack, lineWidth: 1.5)
            clipped(ctx, to: furl) {
                shape(ctx, polygon([at(4, side: -0.2), at(4, side: -5), at(25, side: -0.2)]), umbrellaShade, stroke: false)
            }
            line(ctx, segment(at(6.5, side: 0.3), at(23)), outline, width: 0.8)
            // 酒紅綁帶 + 小蝴蝶結
            line(ctx, segment(at(13.5, side: 3.3), at(13.5, side: -3.3)), umbrellaWine, width: 1.8)
            drawBow(ctx, at: at(13.5), size: 1.9, umbrellaWine)
            shape(ctx, ellipse(h.x, h.y, 7.5, 7.5), white, lineWidth: 1.8)   // 手蓋在傘柄上
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

// MARK: - 外觀：髮型與服裝（純外觀，不加戰鬥力）
//
// 跟上面的「服裝」不同，這裡換的是她本人的頭髮和衣服，所以畫在本體的圖層裡（見 BodyPart）。
// 髮型只管 hairBehind / head 層，服裝只管 base / top 層，兩者可以任意搭配。

typealias Draw = (CGContext, Pose) -> Void

struct HairStyle {
    let id: String
    let name: String
    let color: CGColor      // 主色：兔耳、兔尾巴也用這個
    let dark: CGColor       // 暗色：後腦、兔耳背面
    let shine: CGColor      // 光澤
    var behind: Draw = { _, _ in }   // 垂在身體後面的長髮（頭的座標系）
    let backOfHead: Draw    // 臉後面的頭髮
    let front: Draw         // 臉前面的頭髮：兩側、瀏海、光澤、髮飾
    let backView: Draw      // 背對畫面時的後腦（兔耳已經先畫好了）
}

struct ClothesStyle {
    let id: String
    let name: String
    let sleeve: CGColor
    let cuff: CGColor
    var sleeveWidth: CGFloat = 6.6
    let legging: CGColor
    var sock: CGColor? = nil
    let shoe: CGColor
    var shoeHeight: CGFloat = 6.5    // 大於 6.5 是厚底鞋
    let torso: Draw         // 正面的衣服（上半身座標系）
    let torsoBack: Draw     // 背面的衣服
}

struct Look {
    var hair: HairStyle
    var clothes: ClothesStyle
}

// 瀏海：上緣是跟阿米婭一樣的圓頂（帽子才戴得上），下緣用 tips 決定髮梢形狀。
func bangsPath(_ tips: [CGPoint]) -> CGPath {
    let bangs = CGMutablePath()
    bangs.move(to: CGPoint(x: 27, y: 54))
    bangs.addCurve(to: CGPoint(x: 78, y: 56), control1: CGPoint(x: 26, y: 86), control2: CGPoint(x: 78, y: 86))
    // 注意：addLines(between:) 會另起新的子路徑，所以這裡逐點 addLine 接在圓頂後面
    for pt in tips { bangs.addLine(to: pt) }
    bangs.closeSubpath()
    return bangs
}

// 頭頂的兩道光澤。
// 正面在 y 74，背面（back: true）稍微低一點。
func hairGloss(_ ctx: CGContext, _ color: CGColor, back: Bool = false) {
    withState(ctx, { c in
        c.translateBy(x: 41, y: back ? 72 : 74)
        c.rotate(by: 0.35)
    }) {
        shape(ctx, ellipse(0, 0, 14, 5), color, stroke: false)
    }
    shape(ctx, back ? ellipse(58, 75, 6, 2.6) : ellipse(57, 77.5, 6, 2.6), color, stroke: false)
}

// 在 clip 形狀裡畫東西（例如瀏海裡的挑染）。
func clipped(_ ctx: CGContext, to path: CGPath, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    draw()
    ctx.restoreGState()
}

func quad(_ a: CGPoint, _ b: CGPoint, _ control: CGPoint) -> CGPath {
    let p = CGMutablePath()
    p.move(to: a)
    p.addQuadCurve(to: b, control: control)
    return p
}

func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

// 蝴蝶結：兩片三角形 + 中間的結。
func drawBow(_ ctx: CGContext, at c: CGPoint, size s: CGFloat, _ color: CGColor, knot: CGColor? = nil) {
    shape(ctx, polygon([c, pt(c.x - s * 1.6, c.y + s), pt(c.x - s * 1.6, c.y - s)]), color, lineWidth: 1.4)
    shape(ctx, polygon([c, pt(c.x + s * 1.6, c.y + s), pt(c.x + s * 1.6, c.y - s)]), color, lineWidth: 1.4)
    shape(ctx, ellipse(c.x, c.y, s * 0.95, s * 0.95), knot ?? color, lineWidth: 1.4)
}

// ── 髮型 ──

// 角色原本的髮型（阿米婭的棕髮；理芽的藍髮 + 小辮子、耳環）。
let amiyaHair = HairStyle(
    id: "original", name: characterName, color: hair, dark: hairDark, shine: hairShine,
    backOfHead: { ctx, _ in
        shape(ctx, ellipse(50, 58, 54, 46), hairDark)
    },
    front: { ctx, p in
        // 兩側垂下的髮束
        shape(ctx, petal(pt(31, 62), pt(31, 37), width: 7), hair, lineWidth: 1.8)
        if rim {
            // 臉旁邊的辮子 + 菱形耳環
            drawEarring(ctx, at: pt(34.5, 38))
            drawBraid(ctx, top: pt(75, 58), bottom: pt(76, 44), sway: p.ears)
            drawEarring(ctx, at: pt(70, 37))
        } else {
            shape(ctx, petal(pt(76, 60), pt(74, 38), width: 6), hair, lineWidth: 1.8)
        }
        // 瀏海：下緣是一排尖尖的髮梢
        shape(ctx, bangsPath([pt(72, 61), pt(68, 56.5), pt(63, 62), pt(57.5, 56), pt(52.5, 62.5),
                              pt(47, 56.5), pt(41.5, 62), pt(36, 55.5), pt(32, 60)]), hair)
        // 頭髮上的水藍光澤
        hairGloss(ctx, hairShine)
    },
    backView: { ctx, p in
        // 整顆後腦勺 + 兩側髮束
        shape(ctx, petal(pt(29, 60), pt(31, 36), width: 7), hair, lineWidth: 1.8)
        shape(ctx, petal(pt(71, 60), pt(69, 36), width: 7), hair, lineWidth: 1.8)
        shape(ctx, ellipse(50, 57, 52, 46), hair)
        // 髮流線條
        for (end, ctrl) in [(pt(38, 38), pt(38, 62)), (pt(50, 35), pt(51, 60)), (pt(62, 38), pt(63, 62))] {
            line(ctx, quad(pt(50, 78), end, ctrl), hairDark, width: 1.4)
        }
        hairGloss(ctx, hairShine, back: true)
        if rim {   // 背面：辮子在左側（背對時換邊）
            drawBraid(ctx, top: pt(30, 58), bottom: pt(31, 44), sway: p.ears)
        }
    }
)

// ── 髮型用的小工具 ──

// 一束頭髮：沿著三次貝茲曲線（p0 → p3）長出來，width(t) 決定每一段的寬度（t 從 0 到 1）。
// 用來畫雙馬尾、長髮、髮尾這種有 S 形弧度、慢慢收尖的髮束。
func hairStrand(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint,
                width: (CGFloat) -> CGFloat, samples: Int = 28) -> CGPath {
    func at(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                       y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y)
    }
    var left: [CGPoint] = [], right: [CGPoint] = []
    for i in 0...samples {
        let t = CGFloat(i) / CGFloat(samples)
        let a = at(max(0, t - 0.01)), b = at(min(1, t + 0.01)), c = at(t)
        let len = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
        let n = CGPoint(x: -(b.y - a.y) / len, y: (b.x - a.x) / len)
        let w = width(t) / 2
        left.append(CGPoint(x: c.x + n.x * w, y: c.y + n.y * w))
        right.append(CGPoint(x: c.x - n.x * w, y: c.y - n.y * w))
    }
    let path = CGMutablePath()
    path.move(to: left[0])
    for q in left.dropFirst() { path.addLine(to: q) }
    for q in right.reversed() { path.addLine(to: q) }
    path.closeSubpath()
    return path
}

// 常用的寬度變化：根部 w0，中段稍微鼓起來，尾端收到 tip。
func taper(_ w0: CGFloat, belly: CGFloat = 0.3, tip: CGFloat = 1.2) -> (CGFloat) -> CGFloat {
    { t in max(tip, w0 * (1 + belly * sin(.pi * t)) * (1 - 0.9 * pow(t, 1.6))) }
}

// 天使光環：黑髮頭頂那一圈亮亮的反光（畫在 clip 形狀裡，不會超出頭髮）。
func angelRing(_ ctx: CGContext, in shapePath: CGPath, _ color: CGColor, y: CGFloat = 70) {
    clipped(ctx, to: shapePath) {
        // 一段一段的短反光，中間斷開，才不會像髮箍
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [5.5, 2.6, 3.5, 2.6, 7, 2.6])
        line(ctx, quad(pt(31, y - 2), pt(74, y), pt(52, y + 8)), color.copy(alpha: 0.85)!, width: 2.2)
        ctx.restoreGState()
        shape(ctx, ellipse(41, y + 4.6, 4, 1.6), hex(0xFFFFFF, 0.8), stroke: false)
    }
}

// 兩圈圓圓的蝴蝶結 + 兩條垂下的緞帶，比三角形的可愛。
func loopBow(_ ctx: CGContext, at c: CGPoint, size s: CGFloat, _ color: CGColor, _ fold: CGColor, tails: Bool = true) {
    if tails {
        shape(ctx, petal(pt(c.x - 0.5, c.y - 0.5), pt(c.x - s * 0.7, c.y - s * 1.7), width: s * 0.55), color, lineWidth: 1.2)
        shape(ctx, petal(pt(c.x + 0.5, c.y - 0.5), pt(c.x + s * 0.8, c.y - s * 1.6), width: s * 0.55), color, lineWidth: 1.2)
    }
    for dir in [CGFloat(-1), 1] {
        withState(ctx, { g in
            g.translateBy(x: c.x + dir * s * 0.85, y: c.y + 0.3)
            g.rotate(by: dir * 0.25)
        }) {
            shape(ctx, ellipse(0, 0, s * 1.7, s * 1.25), color, lineWidth: 1.3)
            shape(ctx, ellipse(-dir * s * 0.35, 0, s * 0.6, s * 0.45), fold, stroke: false)
        }
    }
    shape(ctx, ellipse(c.x, c.y, s * 0.7, s * 0.8), fold, lineWidth: 1.2)
}

// 臉旁內彎的側髮（跟鮑伯同一種畫法）：從 top 往下到 bottom，尾端往臉內側收。
// side = -1 是後面那側（畫面左邊），1 是臉那側（畫面右邊）。
func sideLock(_ ctx: CGContext, side: CGFloat, top: CGFloat = 62, bottom: CGFloat, width w: CGFloat,
              _ color: CGColor, curl: CGFloat = 1) {
    let x0: CGFloat = side < 0 ? 27 : 79
    let inward: CGFloat = side < 0 ? 1 : -1
    let p = CGMutablePath()
    p.move(to: pt(x0, top))
    p.addQuadCurve(to: pt(x0 + inward * 1.5, bottom), control: pt(x0 - inward * 3, (top + bottom) / 2))
    p.addQuadCurve(to: pt(x0 + inward * (w + 1.5 * curl), bottom + 2.5 * curl), control: pt(x0 + inward * w * 0.6, bottom - 2.5 * curl))
    p.addQuadCurve(to: pt(x0 + inward * w, top - 2), control: pt(x0 + inward * (w - 1), (top + bottom) / 2))
    p.closeSubpath()
    shape(ctx, p, color, lineWidth: 1.7)
}

// 地雷系雙馬尾：黑髮、髮尾漸層成粉紅（裾カラー），S 形的軟軟長馬尾，綁粉紅緞帶蝴蝶結，頭頂有天使光環。
func jiraiTwinTails() -> HairStyle {
    let base = hex(0x2A2530), dark = hex(0x1A161F), shine = hex(0xD8C6F2)
    let pink = hex(0xFFB3D1), pinkMid = hex(0xE98AB5), ribbon = hex(0xF27AA6), ribbonFold = hex(0xD24F82)
    // 一條馬尾：side -1 左、1 右；rootX 是綁的位置
    func tail(_ ctx: CGContext, side: CGFloat, rootX: CGFloat, rootY: CGFloat) {
        let s = side
        let p0 = pt(rootX, rootY), p1 = pt(rootX + s * 14, rootY - 8)
        let p2 = pt(rootX + s * 2, rootY - 30), p3 = pt(rootX + s * 12, rootY - 47)
        let path = hairStrand(p0, p1, p2, p3, width: taper(12, belly: 0.35, tip: 1.6))
        shape(ctx, path, base)
        // 髮尾漸層成粉紅
        clipped(ctx, to: path) {
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [base, base, pinkMid, pink] as CFArray, locations: [0, 0.5, 0.72, 1])!
            ctx.drawLinearGradient(g, start: p0, end: p3, options: [.drawsAfterEndLocation])
        }
        ctx.addPath(path)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(2)
        ctx.strokePath()
        // 髮流
        let flow = CGMutablePath()
        flow.move(to: pt(rootX + s * 3, rootY - 4))
        flow.addCurve(to: pt(rootX + s * 9, rootY - 36), control1: pt(rootX + s * 12, rootY - 12), control2: pt(rootX - s * 1, rootY - 24))
        line(ctx, flow, hex(0xFFFFFF, 0.18), width: 1.4)
    }
    let bangs = bangsPath([pt(76, 57.5), pt(71, 59.3), pt(66, 57.6), pt(61, 59.6), pt(56, 57.7), pt(51, 59.8),
                           pt(46, 57.7), pt(41, 59.5), pt(36, 57.6), pt(31, 58.8), pt(28.5, 57)])
    return HairStyle(
        id: "jirai_twintails", name: "地雷系雙馬尾", color: base, dark: dark, shine: shine,
        behind: { ctx, _ in
            tail(ctx, side: -1, rootX: 25, rootY: 68)
            tail(ctx, side: 1, rootX: 80, rootY: 67)
        },
        backOfHead: { ctx, _ in shape(ctx, ellipse(51, 57, 56, 46), dark) },
        front: { ctx, _ in
            sideLock(ctx, side: -1, bottom: 37, width: 8, base)
            sideLock(ctx, side: 1, top: 60, bottom: 38, width: 7, base)
            shape(ctx, bangs, base)
            angelRing(ctx, in: bangs, shine)
            loopBow(ctx, at: pt(25, 69), size: 4.6, ribbon, ribbonFold)
            loopBow(ctx, at: pt(80, 68), size: 4.6, ribbon, ribbonFold)
        },
        backView: { ctx, _ in
            tail(ctx, side: -1, rootX: 29, rootY: 67)
            tail(ctx, side: 1, rootX: 71, rootY: 67)
            let head = ellipse(50, 57, 54, 46)
            shape(ctx, head, base)
            for (end, ctrl) in [(pt(40, 37), pt(39, 62)), (pt(60, 37), pt(61, 62))] {
                line(ctx, quad(pt(50, 78), end, ctrl), dark, width: 1.3)
            }
            angelRing(ctx, in: head, shine, y: 68)
            loopBow(ctx, at: pt(29, 68), size: 4.6, ribbon, ribbonFold)
            loopBow(ctx, at: pt(71, 68), size: 4.6, ribbon, ribbonFold)
        }
    )
}

// 日系鯔魚頭（狼尾）：頭頂圓圓的有層次、空氣感碎瀏海、臉旁的髮尾輕輕往外翹，
// 後頸留兩三束細長的髮尾垂到肩膀。accent 是後頸髮尾的顏色（跟主色不同就是內層挑染）。
func wolfMullet(id: String, name: String, base: CGColor, dark: CGColor, shine: CGColor, accent: CGColor,
                ring: Bool = false) -> HairStyle {
    // 臉旁往外翹的一片：從太陽穴往下，到臉頰往外撇
    func flick(_ ctx: CGContext, side: CGFloat, _ color: CGColor) {
        let x0: CGFloat = side < 0 ? 29 : 77
        let o = side   // 往外 = side 方向
        let p = CGMutablePath()
        p.move(to: pt(x0 - o * 1, 63))
        p.addQuadCurve(to: pt(x0 + o * 1, 44), control: pt(x0 + o * 4, 54))
        p.addQuadCurve(to: pt(x0 + o * 7, 37), control: pt(x0 + o * 2, 39))       // 髮尾往外撇
        p.addQuadCurve(to: pt(x0 - o * 5, 43), control: pt(x0 - o * 1, 39))
        p.addQuadCurve(to: pt(x0 - o * 6, 61), control: pt(x0 - o * 4, 52))
        p.closeSubpath()
        shape(ctx, p, color, lineWidth: 1.7)
    }
    func nape(_ ctx: CGContext, xs: [(CGFloat, CGFloat)], top: CGFloat) {
        // (根部 x, 往外的方向)
        for (x, o) in xs {
            let path = hairStrand(pt(x, top), pt(x + o * 2, top - 9), pt(x - o * 1, top - 17), pt(x + o * 7, top - 25),
                                  width: taper(8, belly: 0.15, tip: 1.4))
            shape(ctx, path, accent, lineWidth: 1.7)
        }
    }
    let bangs = bangsPath([pt(76, 59), pt(72.5, 56), pt(69, 61), pt(64.5, 56.5), pt(60.5, 62.5), pt(56, 56.8),
                           pt(51.5, 61.5), pt(47, 56.5), pt(42.5, 62), pt(38, 56.8), pt(34, 60.5), pt(30, 56.5)])
    return HairStyle(
        id: id, name: name, color: base, dark: dark, shine: shine,
        behind: { ctx, _ in nape(ctx, xs: [(35, -1), (41, -0.5), (63, 0.5), (69, 1)], top: 46) },
        backOfHead: { ctx, _ in shape(ctx, ellipse(51, 57, 56, 46), dark) },
        front: { ctx, _ in
            flick(ctx, side: -1, base)
            flick(ctx, side: 1, base)
            shape(ctx, bangs, base)
            clipped(ctx, to: bangs) {
                for (a, b, c) in [(pt(47, 82), pt(44.5, 57), pt(49, 68)), (pt(59, 82), pt(60, 58), pt(61.5, 70))] {
                    line(ctx, quad(a, b, c), dark, width: 1.1)
                }
            }
            if ring { angelRing(ctx, in: bangs, shine) } else { hairGloss(ctx, shine) }
        },
        backView: { ctx, _ in
            nape(ctx, xs: [(38, -1), (45, -0.4), (55, 0.4), (62, 1)], top: 46)
            let head = ellipse(50, 58, 54, 44)
            shape(ctx, head, base)
            for (end, ctrl) in [(pt(39, 40), pt(38, 62)), (pt(50, 37), pt(51, 60)), (pt(61, 40), pt(63, 62))] {
                line(ctx, quad(pt(50, 78), end, ctrl), dark, width: 1.2)
            }
            if ring { angelRing(ctx, in: head, shine, y: 68) } else { hairGloss(ctx, shine, back: true) }
        }
    )
}

// 日系公主切：黑長直，頭頂天使光環，齊瀏海的轉角是圓的，臉旁的姬髮到下巴剪齊、微微內彎，
// 後面的長髮垂到腰、髮尾圓圓的。
func himeCut() -> HairStyle {
    let base = hex(0x25212C), dark = hex(0x16131B), shine = hex(0xC9D4F0)
    let bangs = bangsPath([pt(77, 58), pt(70.5, 57.3), pt(69, 58.3), pt(60.5, 57.3), pt(59, 58.3), pt(49.5, 57.3),
                           pt(48, 58.3), pt(39.5, 57.3), pt(38, 58.3), pt(29, 58)])
    // 姬髮：直直往下，到下巴剪齊，轉角圓圓的
    func himeLock(_ ctx: CGContext, x0: CGFloat, x1: CGFloat, top: CGFloat, bottom: CGFloat) {
        let p = CGMutablePath()
        p.move(to: pt(x0, top))
        p.addQuadCurve(to: pt(x0 + 0.5, bottom + 2), control: pt(x0 - 1.5, (top + bottom) / 2))
        p.addQuadCurve(to: pt(x0 + 2.5, bottom), control: pt(x0 + 0.5, bottom))
        p.addLine(to: pt(x1 - 2, bottom + 0.6))
        p.addQuadCurve(to: pt(x1, bottom + 2.5), control: pt(x1, bottom + 0.6))
        p.addQuadCurve(to: pt(x1, top - 1), control: pt(x1 + 0.5, (top + bottom) / 2))
        p.closeSubpath()
        shape(ctx, p, base, lineWidth: 1.7)
    }
    // 垂到腰的長髮：一大片，髮尾微彎、圓角
    func longHair(_ ctx: CGContext, left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let p = CGMutablePath()
        p.move(to: pt(left + 3, top))
        p.addQuadCurve(to: pt(left, bottom + 4), control: pt(left - 3, (top + bottom) / 2))
        p.addQuadCurve(to: pt(left + 5, bottom), control: pt(left, bottom))
        p.addQuadCurve(to: pt(right - 5, bottom), control: pt((left + right) / 2, bottom - 2.5))
        p.addQuadCurve(to: pt(right, bottom + 4), control: pt(right, bottom))
        p.addQuadCurve(to: pt(right - 3, top), control: pt(right + 3, (top + bottom) / 2))
        p.closeSubpath()
        shape(ctx, p, base)
        clipped(ctx, to: p) {
            for k in stride(from: left + 9, through: right - 8, by: 10) {
                line(ctx, quad(pt(k, top - 2), pt(k + (k < (left + right) / 2 ? -1.5 : 1.5), bottom + 1), pt(k + 1, (top + bottom) / 2)),
                     dark, width: 1.1)
            }
        }
    }
    return HairStyle(
        id: "hime_cut", name: "日系公主切", color: base, dark: dark, shine: shine,
        behind: { ctx, _ in longHair(ctx, left: 22, right: 81, top: 62, bottom: 16) },
        backOfHead: { ctx, _ in shape(ctx, ellipse(51, 57, 56, 46), dark) },
        front: { ctx, _ in
            himeLock(ctx, x0: 26.5, x1: 35, top: 62, bottom: 38)
            himeLock(ctx, x0: 71.5, x1: 78.5, top: 60, bottom: 39)
            shape(ctx, bangs, base)
            angelRing(ctx, in: bangs, shine)
        },
        backView: { ctx, _ in
            longHair(ctx, left: 30, right: 70, top: 66, bottom: 21)
            let head = ellipse(50, 57, 54, 46)
            shape(ctx, head, base)
            angelRing(ctx, in: head, shine, y: 68)
        }
    )
}

// 日系短鮑伯：粉霧棕、透明感的空氣瀏海，髮尾在下巴內彎。
func shortBob() -> HairStyle {
    let base = hex(0xB98A86), dark = hex(0x94655F), shine = hex(0xF7D9D6)
    return HairStyle(
        id: "short_bob", name: "日系短鮑伯", color: base, dark: dark, shine: shine,
        backOfHead: { ctx, _ in shape(ctx, ellipse(51, 54, 58, 48), dark) },
        front: { ctx, _ in
            // 兩側內彎的鮑伯
            let back = CGMutablePath()
            back.move(to: pt(26, 60))
            back.addQuadCurve(to: pt(30, 34), control: pt(21, 45))
            back.addQuadCurve(to: pt(39, 37), control: pt(34, 31))
            back.addQuadCurve(to: pt(36, 60), control: pt(33, 47))
            back.closeSubpath()
            shape(ctx, back, base, lineWidth: 1.8)
            let front = CGMutablePath()
            front.move(to: pt(80, 58))
            front.addQuadCurve(to: pt(76, 35), control: pt(84, 45))
            front.addQuadCurve(to: pt(69, 37), control: pt(73, 32))
            front.addQuadCurve(to: pt(72, 58), control: pt(73, 47))
            front.closeSubpath()
            shape(ctx, front, base, lineWidth: 1.8)
            // 空氣瀏海：細細的髮梢，看得到額頭
            shape(ctx, bangsPath([pt(76, 59), pt(72, 60), pt(69, 57), pt(65, 62), pt(61, 58), pt(57, 63),
                                  pt(53, 58), pt(49, 62.5), pt(45, 58), pt(41, 62), pt(37, 57.5), pt(33, 60.5), pt(30, 57)]), base)
            hairGloss(ctx, shine)
        },
        backView: { ctx, _ in
            shape(ctx, ellipse(50, 55, 56, 48), base)
            line(ctx, quad(pt(27, 40), pt(73, 40), pt(50, 29)), dark, width: 1.6)
            for (end, ctrl) in [(pt(40, 36), pt(39, 60)), (pt(60, 36), pt(61, 60))] {
                line(ctx, quad(pt(50, 78), end, ctrl), dark, width: 1.3)
            }
            hairGloss(ctx, shine, back: true)
        }
    )
}

let hairStyles: [HairStyle] = [
    amiyaHair,
    jiraiTwinTails(),
    wolfMullet(id: "wolf_milktea", name: "日系鯔魚頭・奶茶", base: hex(0xC9A07E), dark: hex(0xA57D5E),
               shine: hex(0xF5E2C8), accent: hex(0xC9A07E)),
    wolfMullet(id: "wolf_silver", name: "日系鯔魚頭・黑銀挑染", base: hex(0x2E2A33), dark: hex(0x1D1A21),
               shine: hex(0xD9DEE8), accent: hex(0xC4CBD8), ring: true),
    himeCut(),
    shortBob(),
]

// ── 服裝 ──

// 阿米婭原本的百褶裙（正面、背面的褶線位置不同）。
func pleatedSkirt(_ ctx: CGContext, _ color: CGColor, _ pleat: CGColor, back: Bool) {
    let s = CGMutablePath()
    s.move(to: pt(39, 28))
    s.addLine(to: pt(61, 28))
    s.addLine(to: pt(67, 14))
    s.addQuadCurve(to: pt(50, 13), control: pt(58, 11))
    s.addQuadCurve(to: pt(33, 14), control: pt(42, 11))
    s.closeSubpath()
    shape(ctx, s, color)
    let pleats = back
        ? [(pt(44, 20), pt(41, 14)), (pt(50, 20), pt(50, 14)), (pt(56, 20), pt(59, 14))]
        : [(pt(44, 27), pt(40, 14)), (pt(50, 27), pt(50, 14)), (pt(56, 27), pt(60, 14))]
    for (a, b) in pleats { line(ctx, segment(a, b), pleat, width: 1.6) }
}

// 角色原本的衣服（阿米婭的黑外套 + 藍裙；理芽的紅線外套 + 胸前菱形 + 橘紅裙）。
let amiyaClothes = ClothesStyle(
    id: "original", name: characterName, sleeve: jacket, cuff: jacketLine, legging: legging, shoe: shoe,
    torso: { ctx, _ in
        pleatedSkirt(ctx, skirt, skirtLight, back: false)
        if rim {
            // 深紫內搭，胸前紅白菱形
            shape(ctx, rounded(44, 24, 14, 14, 3), top, lineWidth: 1.6)
            shape(ctx, polygon([pt(51, 35), pt(54.5, 30), pt(51, 25), pt(47.5, 30)]), gemRed, lineWidth: 1.2)
            shape(ctx, polygon([pt(51, 32.5), pt(52.7, 30), pt(51, 27.5), pt(49.3, 30)]), white, stroke: false)
        } else {
            // 深藍上衣，下襬是一排小荷葉邊
            shape(ctx, rounded(44, 25, 14, 13, 3), top, lineWidth: 1.6)
            for x in stride(from: CGFloat(46.5), through: 56, by: 4.5) {
                shape(ctx, ellipse(x, 25, 5, 4), top, lineWidth: 1.2)
            }
        }
        // 敞開的黑外套：左右兩片，內側滾邊
        shape(ctx, rounded(33.5, 17, 13, 21, 5), jacket)
        shape(ctx, rounded(55.5, 17, 10, 21, 5), jacket)
        line(ctx, segment(pt(45.5, 18.5), pt(45.5, 36)), jacketLine, width: 2)
        line(ctx, segment(pt(56.5, 18.5), pt(56.5, 36)), jacketLine, width: 2)
        if rim {   // 外套上的紅色折線
            for (a, b, c) in [(pt(36, 30), pt(40, 26), pt(43, 29)), (pt(58, 29), pt(61, 26), pt(64, 30))] {
                let z = CGMutablePath(); z.move(to: a); z.addLine(to: b); z.addLine(to: c)
                line(ctx, z, jacketLine, width: 1.3)
            }
        }
        // 帽兜的水藍內裡，從脖子兩側露出來
        shape(ctx, ellipse(50, 37, 32, 7), trim, lineWidth: 1.6)
    },
    torsoBack: { ctx, _ in
        pleatedSkirt(ctx, skirt, skirtLight, back: true)
        // 外套背面一整片，上面披著帽兜
        shape(ctx, rounded(34, 19, 32, 19, 6), jacket)
        shape(ctx, ellipse(50, 33, 26, 11), jacket)
        line(ctx, quad(pt(40, 32), pt(60, 32), pt(50, 26)), trim, width: 2)
    }
)

// 荷葉邊裙 + 大圓領 + 胸前蝴蝶結：地雷系、量產型共用，只換顏色。
func frillyDress(id: String, name: String, blouse: CGColor, skirt: CGColor, lace: CGColor, collar: CGColor,
                 ribbon: CGColor, sleeve: CGColor, cuff: CGColor, legging: CGColor, sock: CGColor?, shoe: CGColor) -> ClothesStyle {
    func skirtShape(_ ctx: CGContext) {
        // 裙襬下露出一圈蕾絲
        for x in stride(from: CGFloat(33.5), through: 67, by: 4.1) {
            shape(ctx, ellipse(x, 13, 5, 4), lace, lineWidth: 1.1)
        }
        let s = CGMutablePath()
        s.move(to: pt(38, 27))
        s.addLine(to: pt(62, 27))
        s.addLine(to: pt(68, 14.5))
        s.addQuadCurve(to: pt(50, 13), control: pt(58, 12))
        s.addQuadCurve(to: pt(32, 14.5), control: pt(42, 12))
        s.closeSubpath()
        shape(ctx, s, skirt)
        let trimLine = CGMutablePath()
        trimLine.move(to: pt(33.5, 16))
        trimLine.addQuadCurve(to: pt(50, 14.6), control: pt(42, 13.6))
        trimLine.addQuadCurve(to: pt(66.5, 16), control: pt(58, 13.6))
        line(ctx, trimLine, ribbon, width: 1.3)
    }
    return ClothesStyle(
        id: id, name: name, sleeve: sleeve, cuff: cuff, legging: legging, sock: sock, shoe: shoe, shoeHeight: 8.5,
        torso: { ctx, _ in
            skirtShape(ctx)
            shape(ctx, rounded(36, 24, 28, 15, 5), blouse)
            line(ctx, segment(pt(37.5, 26), pt(62.5, 26)), ribbon, width: 2)   // 腰帶
            // 大圓領 + 胸前蝴蝶結（緞帶垂下來）
            shape(ctx, ellipse(43.5, 36, 15, 7), collar, lineWidth: 1.4)
            shape(ctx, ellipse(58, 36, 15, 7), collar, lineWidth: 1.4)
            shape(ctx, petal(pt(49.5, 32), pt(46.5, 24.5), width: 3), ribbon, lineWidth: 1.2)
            shape(ctx, petal(pt(52.5, 32), pt(55.5, 24.5), width: 3), ribbon, lineWidth: 1.2)
            drawBow(ctx, at: pt(51, 33), size: 4.2, ribbon)
        },
        torsoBack: { ctx, _ in
            skirtShape(ctx)
            shape(ctx, rounded(34, 19, 32, 20, 6), blouse)
            shape(ctx, ellipse(50, 36, 28, 8), collar, lineWidth: 1.4)
            drawBow(ctx, at: pt(50, 24), size: 5.5, ribbon)   // 背後腰上的大蝴蝶結
        }
    )
}

let jiraiClothes = frillyDress(
    id: "jirai", name: "地雷系", blouse: hex(0x231E27), skirt: hex(0x231E27), lace: white, collar: white,
    ribbon: hex(0xF26B9C), sleeve: hex(0x231E27), cuff: white, legging: hex(0x1E1A22), sock: white, shoe: hex(0x18151C))

let ryousanClothes = frillyDress(
    id: "ryousan", name: "量產型", blouse: hex(0xFFF4F7), skirt: hex(0xF4B6CB), lace: white, collar: white,
    ribbon: hex(0xE0607E), sleeve: hex(0xFFF4F7), cuff: hex(0xF4B6CB), legging: hex(0xFBF3F6), sock: nil, shoe: hex(0xE68AA8))

// 日系水手服：白上衣、深藍水手領、紅領巾、深藍百褶裙、樂福鞋。
let sailorClothes: ClothesStyle = {
    let navy = hex(0x22305E), navyLight = hex(0x3B4C86), shirt = hex(0xF8F9FC), red = hex(0xD8343F)
    return ClothesStyle(
        id: "sailor", name: "日系水手服", sleeve: shirt, cuff: navy, legging: hex(0x23243A), shoe: hex(0x5A3A2A),
        torso: { ctx, _ in
            pleatedSkirt(ctx, navy, navyLight, back: false)
            shape(ctx, rounded(36, 22, 28, 17, 5), shirt)
            // V 字水手領 + 白色滾線
            shape(ctx, polygon([pt(35, 39.5), pt(66, 39.5), pt(64, 33), pt(51, 25.5), pt(37.5, 33)]), navy, lineWidth: 1.6)
            let stripe = CGMutablePath()
            stripe.addLines(between: [pt(39.5, 34), pt(51, 28), pt(62, 34)])
            line(ctx, stripe, shirt, width: 1.2)
            shape(ctx, polygon([pt(44, 39.5), pt(58, 39.5), pt(51, 30)]), shirt, lineWidth: 1.2)
            // 紅領巾
            shape(ctx, petal(pt(50, 29), pt(47.5, 21), width: 3.5), red, lineWidth: 1.2)
            shape(ctx, petal(pt(52, 29), pt(54.5, 21), width: 3.5), red, lineWidth: 1.2)
            drawBow(ctx, at: pt(51, 30), size: 3.8, red)
        },
        torsoBack: { ctx, _ in
            pleatedSkirt(ctx, navy, navyLight, back: true)
            shape(ctx, rounded(34, 19, 32, 20, 6), shirt)
            // 背後方方的水手領
            shape(ctx, rounded(36, 27, 28, 13, 2), navy, lineWidth: 1.6)
            line(ctx, rounded(38.5, 29.5, 23, 8.5, 1.5), shirt, width: 1.2)
        }
    )
}()

// 日系街頭：oversize 霧紫帽 T 蓋到大腿，白色厚底球鞋。
let streetClothes: ClothesStyle = {
    let hoodie = hex(0xB7A6C9), hoodieDark = hex(0x9483AA)
    return ClothesStyle(
        id: "street_hoodie", name: "日系街頭帽T", sleeve: hoodie, cuff: hoodieDark, sleeveWidth: 7.6,
        legging: skin, sock: white, shoe: hex(0xF4F4F4), shoeHeight: 8.5,
        torso: { ctx, _ in
            shape(ctx, rounded(32, 10, 36, 29, 9), hoodie)
            line(ctx, segment(pt(34.5, 13), pt(65.5, 13)), hoodieDark, width: 1.4)   // 下襬羅紋
            shape(ctx, rounded(41, 15, 18, 8, 3.5), hoodieDark, lineWidth: 1.4)       // 大口袋
            shape(ctx, ellipse(50, 37.5, 34, 8), hoodieDark, lineWidth: 1.6)          // 帽子圍在脖子
            // 帽繩
            for (a, b) in [(pt(47, 35), pt(46, 27)), (pt(55, 35), pt(56, 27.5))] {
                line(ctx, segment(a, b), white, width: 1.5)
                shape(ctx, ellipse(b.x, b.y, 2.4, 2.4), white, lineWidth: 1)
            }
        },
        torsoBack: { ctx, _ in
            shape(ctx, rounded(32, 10, 36, 29, 9), hoodie)
            line(ctx, segment(pt(34.5, 13), pt(65.5, 13)), hoodieDark, width: 1.4)
            // 帽子垂在背上
            shape(ctx, rounded(38, 23, 24, 16, 8), hoodieDark, lineWidth: 1.6)
            line(ctx, quad(pt(41, 36), pt(59, 36), pt(50, 30)), hoodie, width: 1.4)
        }
    )
}()

// 日系浴衣：深藍底櫻花紋的短版浴衣、粉紅腰帶、木屐。
let yukataClothes: ClothesStyle = {
    let navy = hex(0x2D3A6E), sakura = hex(0xF6A9C2), obi = hex(0xE85C7A), cord = hex(0xFFE27A)
    func robe(_ ctx: CGContext) {
        let r = CGMutablePath()
        r.move(to: pt(36, 38.5))
        r.addLine(to: pt(64, 38.5))
        r.addLine(to: pt(67, 12))
        r.addQuadCurve(to: pt(50, 11), control: pt(58, 10.5))
        r.addQuadCurve(to: pt(33, 12), control: pt(42, 10.5))
        r.closeSubpath()
        shape(ctx, r, navy)
        for c in [pt(39, 15), pt(55, 15.5), pt(62.5, 31), pt(38.5, 32), pt(47, 16.5), pt(60.5, 18)] {
            shape(ctx, ellipse(c.x, c.y, 3.8, 3.8), sakura, lineWidth: 0.9)
            shape(ctx, ellipse(c.x, c.y, 1.2, 1.2), white, stroke: false)
        }
    }
    return ClothesStyle(
        id: "yukata", name: "日系浴衣", sleeve: navy, cuff: navy, sleeveWidth: 9,
        legging: skin, sock: white, shoe: hex(0xC8935A), shoeHeight: 5.5,
        torso: { ctx, _ in
            robe(ctx)
            // 交領
            line(ctx, segment(pt(45, 38.5), pt(53, 27)), white, width: 2.2)
            line(ctx, segment(pt(57, 38.5), pt(50.5, 31)), white, width: 2.2)
            shape(ctx, rounded(35, 21, 30, 6.5, 1.5), obi, lineWidth: 1.6)
            line(ctx, segment(pt(35.5, 24.2), pt(64.5, 24.2)), cord, width: 1)
        },
        torsoBack: { ctx, _ in
            robe(ctx)
            shape(ctx, rounded(34, 21, 32, 6.5, 1.5), obi, lineWidth: 1.6)
            drawBow(ctx, at: pt(50, 24.5), size: 7, obi)   // 背後的文庫結
        }
    )
}()

// 哥德蘿莉：黑色馬甲連身裙、酒紅綁帶、兩層蕾絲裙襬、立領 + 銀十字、黑褲襪厚底鞋。
let gothicClothes: ClothesStyle = {
    let black = hex(0x1E1A24), shade = hex(0x34293F), wine = hex(0x7A1E34), lace = hex(0xE9E4EC), silver = hex(0xC9CCD6)
    func skirt(_ ctx: CGContext) {
        // 最下面一圈白蕾絲，上面兩層黑裙
        for x in stride(from: CGFloat(32), through: 68, by: 4) {
            shape(ctx, ellipse(x, 11, 4.6, 4), lace, lineWidth: 1.1)
        }
        let lower = CGMutablePath()
        lower.move(to: pt(37, 22)); lower.addLine(to: pt(63, 22)); lower.addLine(to: pt(69, 12.5))
        lower.addQuadCurve(to: pt(50, 11), control: pt(59, 10)); lower.addQuadCurve(to: pt(31, 12.5), control: pt(41, 10))
        lower.closeSubpath()
        shape(ctx, lower, black)
        line(ctx, quad(pt(32.5, 14), pt(67.5, 14), pt(50, 11.2)), wine, width: 1.3)
        let upper = CGMutablePath()
        upper.move(to: pt(38.5, 28)); upper.addLine(to: pt(61.5, 28)); upper.addLine(to: pt(66, 18.5))
        upper.addQuadCurve(to: pt(50, 17), control: pt(58, 16)); upper.addQuadCurve(to: pt(34, 18.5), control: pt(42, 16))
        upper.closeSubpath()
        shape(ctx, upper, shade)
        for x in stride(from: CGFloat(36), through: 64, by: 4) {
            shape(ctx, ellipse(x, 17.6, 4, 2.6), black, lineWidth: 1)   // 上層裙襬的荷葉邊
        }
    }
    return ClothesStyle(
        id: "gothic", name: "哥德蘿莉", sleeve: black, cuff: lace, sleeveWidth: 7.4,
        legging: hex(0x15121A), shoe: hex(0x120F16), shoeHeight: 9,
        torso: { ctx, _ in
            skirt(ctx)
            shape(ctx, rounded(37, 24, 26, 15, 4), black)                    // 馬甲
            // 胸前酒紅交叉綁帶
            for y in stride(from: CGFloat(26.5), through: 33, by: 3.2) {
                line(ctx, segment(pt(47.5, y), pt(54.5, y + 2.6)), wine, width: 1.1)
                line(ctx, segment(pt(54.5, y), pt(47.5, y + 2.6)), wine, width: 1.1)
            }
            // 白蕾絲立領 + 酒紅領結 + 銀十字
            shape(ctx, rounded(42, 35.5, 18, 4.5, 2), lace, lineWidth: 1.3)
            drawBow(ctx, at: pt(51, 35.5), size: 3, wine)
            line(ctx, segment(pt(51, 33), pt(51, 27.5)), silver, width: 1.4)
            line(ctx, segment(pt(49, 31.2), pt(53, 31.2)), silver, width: 1.4)
        },
        torsoBack: { ctx, _ in
            skirt(ctx)
            shape(ctx, rounded(34, 20, 32, 19, 6), black)
            for y in stride(from: CGFloat(23), through: 33, by: 3.2) {   // 背後的綁帶
                line(ctx, segment(pt(46.5, y), pt(53.5, y + 2.6)), wine, width: 1.1)
                line(ctx, segment(pt(53.5, y), pt(46.5, y + 2.6)), wine, width: 1.1)
            }
            shape(ctx, rounded(40, 35.5, 20, 4.5, 2), lace, lineWidth: 1.3)
            drawBow(ctx, at: pt(50, 21), size: 6, wine)                  // 腰後大蝴蝶結
        }
    )
}()

let clothesStyles: [ClothesStyle] = [amiyaClothes, jiraiClothes, ryousanClothes, sailorClothes, streetClothes, yukataClothes, gothicClothes]

// 目前畫的是哪一套。產生本體與一般服裝時是阿米婭原本的樣子；產生外觀圖層時才會換。
let defaultLook = Look(hair: amiyaHair, clothes: amiyaClothes)
var look = defaultLook

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
    // 拿著雨傘時代替降落傘：單手撐傘飄下來（格數、速度要跟 parachute 一樣）
    ActionSpec(name: "parasol", frames: 4, fps: 4, loop: true),
    ActionSpec(name: "eat", frames: 4, fps: 5, loop: true),
    ActionSpec(name: "typing", frames: 4, fps: 6, loop: true),
    // 一格是擺盪的四分之一週期，要跟程式裡的 swingPeriod（2.4 秒）對上
    ActionSpec(name: "swing", frames: 4, fps: 4 / 2.4, loop: true),
    ActionSpec(name: "fly", frames: 2, fps: 4, loop: true),
    // 在地下城拿劍砍 boss：一刀 6 格，第 3 格砍中（程式在這格讓 boss 閃一下）
    ActionSpec(name: "attack", frames: 6, fps: 9, loop: true),
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
    case "attack":
        // 0 準備、1 舉劍、2 揮下、3 砍中、4 收勢、5 站穩
        p.sword = true
        p.armBack = 0.55
        p.eyes = .open
        switch i {
        case 0:
            p.armFront = 1.25; p.lean = 0.04; p.frontFoot = CGPoint(x: 3, y: 0); p.ears = 0.1
        case 1:
            p.armFront = 2.85; p.lean = -0.08; p.squashY = 1.02; p.armBack = 0.9
            p.frontFoot = CGPoint(x: 2, y: 1); p.ears = 0.25
        case 2:
            p.armFront = 1.9; p.lean = 0.1; p.frontFoot = CGPoint(x: 6, y: 0); p.backFoot = CGPoint(x: -3, y: 0)
            p.slash = 0.6; p.slashFrom = 2.5; p.mouthOpen = true; p.ears = 0.35
        case 3:
            p.armFront = 0.95; p.lean = 0.17; p.squashY = 0.97; p.squashX = 1.03
            p.frontFoot = CGPoint(x: 7, y: 0); p.backFoot = CGPoint(x: -4, y: 0)
            p.slash = 1; p.slashFrom = 2.3; p.mouthOpen = true; p.ears = 0.45
        case 4:
            p.armFront = 0.6; p.lean = 0.12; p.frontFoot = CGPoint(x: 6, y: 0); p.backFoot = CGPoint(x: -3, y: 0)
            p.slash = 0.35; p.slashFrom = 1.5; p.ears = 0.3
        default:
            p.armFront = 0.95; p.lean = 0.06; p.frontFoot = CGPoint(x: 4, y: 0); p.ears = 0.15
        }
    case "parasol":
        // 單手撐傘飄下來：前手舉高握傘柄，後手跟腳輕輕晃
        p.parasol = true
        p.bodyY = 2
        p.lean = 0.05 * sin(t)
        p.armFront = 2.35; p.armBack = -0.5 + 0.25 * sin(t)
        p.frontFoot = CGPoint(x: 2 * sin(t), y: 2)
        p.backFoot = CGPoint(x: -2 * sin(t), y: 3)
        p.ears = 0.12 * sin(t)
        p.eyes = i == 2 ? .happy : .open
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

// MARK: - 劍（地下城打 boss）

// 劍的方向：順著手臂再往上翹一點，舉劍時指向後上方、砍下去時指向前方。
func swordAngle(_ armAngle: CGFloat) -> CGFloat { armAngle + 0.5 }

func drawSword(_ ctx: CGContext, _ p: Pose) {
    let h = hand(shoulderFront, p.armFront)
    // 刀光：從舉劍的角度劃到現在的角度，一道彎彎的光
    if p.slash > 0 {
        let s = shoulderFront
        let r: CGFloat = 38
        let a0 = swordAngle(p.slashFrom), a1 = swordAngle(p.armFront)
        let arc = CGMutablePath()
        // 角度 0 往下、往前轉為正；換成 CG 的角度（從 +x 逆時針）是 a - π/2 的相反
        func pt(_ a: CGFloat, _ rr: CGFloat) -> CGPoint { CGPoint(x: s.x + sin(a) * rr, y: s.y - cos(a) * rr) }
        let steps = 14
        for k in 0...steps {
            let a = a0 + (a1 - a0) * CGFloat(k) / CGFloat(steps)
            let q = pt(a, r)
            if k == 0 { arc.move(to: q) } else { arc.addLine(to: q) }
        }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setShadow(offset: .zero, blur: 6, color: hex(0x9FE8FF, 0.9 * p.slash))
        line(ctx, arc, hex(0xBFF1FF, 0.55 * p.slash), width: 9)
        line(ctx, arc, hex(0xFFFFFF, 0.9 * p.slash), width: 3)
        ctx.restoreGState()
    }
    let a = swordAngle(p.armFront)
    let d = CGPoint(x: sin(a), y: -cos(a))
    let n = CGPoint(x: -d.y, y: d.x)
    func at(_ k: CGFloat, _ side: CGFloat = 0) -> CGPoint {
        CGPoint(x: h.x + d.x * k + n.x * side, y: h.y + d.y * k + n.y * side)
    }
    // 劍柄、護手、劍身
    ctx.setLineCap(.round)
    line(ctx, segment(at(-4), at(3)), outline, width: 4.4)
    line(ctx, segment(at(-4), at(3)), hex(0x8B5A3C), width: 2.4)
    shape(ctx, ellipse(at(-4.5).x, at(-4.5).y, 3.6, 3.6), hex(0xF2C94C), lineWidth: 1.1)
    let blade = polygon([at(4, -2.2), at(22, -1.8), at(27, 0), at(22, 1.8), at(4, 2.2)])
    shape(ctx, blade, hex(0xE6EEF5), lineWidth: 1.5)
    line(ctx, segment(at(5), at(23)), hex(0xAFC4D6), width: 1)
    line(ctx, segment(at(3, -5), at(3, 5)), outline, width: 4)
    line(ctx, segment(at(3, -5), at(3, 5)), hex(0xF2C94C), width: 2.2)
    // 手蓋在劍柄上，看起來握住了
    shape(ctx, ellipse(h.x, h.y, 7.5, 7.5), white, lineWidth: 1.8)
}

// MARK: - 地下城 boss（獨立道具圖）
//
// 每個地下城一隻，面向左邊（她站在左邊砍）；她在右邊時程式把圖翻過來。
// 每隻三張：idle_0、idle_1（呼吸 / 晃動）和 hit（被砍中：瞇眼、發白）。

let bossPixel: CGFloat = 2      // 像素風格：一個像素 = 2 點（螢幕上 4×4 個實際像素）
let bossWidth: CGFloat = 150
let bossHeight: CGFloat = 130

// 生氣的眼睛：白眼、黑瞳、往中間壓的眉毛；被砍中時變成 >< 。
func bossEye(_ ctx: CGContext, _ c: CGPoint, size r: CGFloat, hit: Bool, glow: CGColor? = nil, left: Bool) {
    if hit {
        let z = CGMutablePath()
        let s: CGFloat = left ? 1 : -1
        z.addLines(between: [CGPoint(x: c.x - r * 0.7 * s, y: c.y + r * 0.6), CGPoint(x: c.x + r * 0.5 * s, y: c.y),
                             CGPoint(x: c.x - r * 0.7 * s, y: c.y - r * 0.6)])
        line(ctx, z, outline, width: 2.4)
        return
    }
    if let glow {
        ctx.saveGState()
        setGlow(ctx, blur: 6, glow)
        shape(ctx, ellipse(c.x, c.y, r * 1.6, r * 1.2), glow, lineWidth: 1.4)
        ctx.restoreGState()
        return
    }
    shape(ctx, ellipse(c.x, c.y, r * 1.7, r * 1.9), white, lineWidth: 1.6)
    shape(ctx, ellipse(c.x - r * 0.25, c.y - r * 0.1, r * 0.9, r * 1.1), outline, stroke: false)
    shape(ctx, ellipse(c.x - r * 0.4, c.y + r * 0.25, r * 0.35, r * 0.35), white, stroke: false)
    // 眉毛：外高內低（生氣）
    let s: CGFloat = left ? 1 : -1
    line(ctx, segment(CGPoint(x: c.x - r * 1 * s, y: c.y + r * 1.5), CGPoint(x: c.x + r * 0.9 * s, y: c.y + r * 1.0)), outline, width: 2.6)
}

// 被砍中：砍到的地方（左邊、她那一側）爆一個黃色的衝擊星。
func hitBurst(_ ctx: CGContext, at c: CGPoint) {
    let star = CGMutablePath()
    for k in 0..<16 {
        let a = CGFloat(k) / 16 * 2 * .pi
        let r: CGFloat = k % 2 == 0 ? 16 : 7
        let q = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        if k == 0 { star.move(to: q) } else { star.addLine(to: q) }
    }
    star.closeSubpath()
    ctx.saveGState()
    setGlow(ctx, blur: 6, hex(0xFFE27A))
    shape(ctx, star, hex(0xFFE066), lineWidth: 1.6)
    ctx.restoreGState()
    shape(ctx, ellipse(c.x, c.y, 8, 8), white, stroke: false)
}

// 草原：草原史萊姆王——圓滾滾的綠色史萊姆，頭上長草、戴一頂小王冠、插一朵蒲公英。
func drawSlimeKing(_ ctx: CGContext, frame: Int, hit: Bool) {
    let squash: CGFloat = hit ? 0.9 : (frame == 0 ? 1 : 0.95)
    let w: CGFloat = hit ? 118 : (frame == 0 ? 108 : 112)
    let h: CGFloat = 92 * squash
    let cx: CGFloat = 78, base: CGFloat = 6
    let body = CGMutablePath()
    body.move(to: CGPoint(x: cx - w / 2, y: base + 8))
    body.addCurve(to: CGPoint(x: cx, y: base + h), control1: CGPoint(x: cx - w / 2 - 4, y: base + h * 0.75), control2: CGPoint(x: cx - w * 0.3, y: base + h))
    body.addCurve(to: CGPoint(x: cx + w / 2, y: base + 8), control1: CGPoint(x: cx + w * 0.3, y: base + h), control2: CGPoint(x: cx + w / 2 + 4, y: base + h * 0.75))
    body.addQuadCurve(to: CGPoint(x: cx - w / 2, y: base + 8), control: CGPoint(x: cx, y: base - 6))
    body.closeSubpath()
    // 地上的影子
    shape(ctx, ellipse(cx, base + 2, w + 6, 8), hex(0x000000, 0.12), stroke: false)
    gradientFill(ctx, body, [hex(0xA8EE8E), hex(0x5CC456), hex(0x3E9C43)], from: CGPoint(x: cx, y: base + h), to: CGPoint(x: cx, y: base))
    line(ctx, body, outline, width: 2.4)
    // 光澤
    shape(ctx, ellipse(cx - w * 0.25, base + h * 0.72, 20, 10), hex(0xFFFFFF, 0.55), stroke: false)
    shape(ctx, ellipse(cx - w * 0.36, base + h * 0.6, 6, 4), hex(0xFFFFFF, 0.45), stroke: false)
    // 頭上的草
    let top = base + h
    for (dx, len, tilt) in [(CGFloat(-10), CGFloat(13), CGFloat(-0.4)), (-3, 17, -0.1), (5, 14, 0.25), (12, 10, 0.5)] {
        shape(ctx, petal(CGPoint(x: cx + dx, y: top - 3), CGPoint(x: cx + dx + sin(tilt) * len, y: top - 3 + cos(tilt) * len), width: 4),
              hex(0x3E9C43), lineWidth: 1.4)
    }
    // 小王冠（歪一邊）
    withState(ctx, { c in c.translateBy(x: cx + 22, y: top - 6); c.rotate(by: -0.25); c.scaleBy(x: 1.5, y: 1.5) }) {
        let crown = polygon([CGPoint(x: -10, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 11, y: 11), CGPoint(x: 5, y: 5),
                             CGPoint(x: 0, y: 13), CGPoint(x: -5, y: 5), CGPoint(x: -11, y: 11)])
        // 像素風格下外框會吃掉小王冠，所以實心填金色、底下一條深金色
        shape(ctx, crown, hex(0xF7C948), stroke: false)
        line(ctx, segment(CGPoint(x: -10, y: 0.8), CGPoint(x: 10, y: 0.8)), hex(0xC9932E), width: 1.6)
        shape(ctx, ellipse(0, 4.5, 3.4, 3.4), hex(0xE0383A), stroke: false)
    }
    // 蒲公英
    line(ctx, segment(CGPoint(x: cx - 26, y: top - 14), CGPoint(x: cx - 34, y: top + 8)), hex(0x3E9C43), width: 2)
    shape(ctx, ellipse(cx - 34, top + 9, 14, 14), hex(0xFFE066), lineWidth: 1.6)
    shape(ctx, ellipse(cx - 34, top + 9, 5, 5), hex(0xF2A93B), stroke: false)
    // 臉（朝左）
    let ey = base + h * 0.45
    bossEye(ctx, CGPoint(x: cx - 26, y: ey), size: 7, hit: hit, left: true)
    bossEye(ctx, CGPoint(x: cx - 2, y: ey), size: 7, hit: hit, left: false)
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: cx - 24, y: ey - 15))
    mouth.addQuadCurve(to: CGPoint(x: cx - 4, y: ey - 15), control: CGPoint(x: cx - 14, y: ey - (hit ? 30 : 25)))
    mouth.closeSubpath()
    shape(ctx, mouth, hex(0x7A2E3A), lineWidth: 1.8)
    shape(ctx, polygon([CGPoint(x: cx - 19, y: ey - 15), CGPoint(x: cx - 15, y: ey - 15), CGPoint(x: cx - 17, y: ey - 19)]), white, lineWidth: 1)
    if hit { hitBurst(ctx, at: CGPoint(x: 30, y: 50)) }
}

// 森林：古樹樹精——長著臉的老樹幹，枝條手臂、滿頭樹葉、腳邊冒出蘑菇。
func drawTreant(_ ctx: CGContext, frame: Int, hit: Bool) {
    let sway: CGFloat = hit ? 6 : (frame == 0 ? 0 : 3)
    let bark = hex(0x8A5A3C), barkDark = hex(0x5E3B26)
    let leaf = hex(0x4FA35A), leafLight = hex(0x7CC46A)
    shape(ctx, ellipse(78, 8, 90, 8), hex(0x000000, 0.12), stroke: false)
    // 樹根
    for (x0, x1) in [(CGFloat(52), CGFloat(40)), (70, 66), (96, 110)] {
        shape(ctx, petal(CGPoint(x: x0 + 6, y: 22), CGPoint(x: x1, y: 6), width: 9), barkDark, lineWidth: 1.6)
    }
    // 後面的枝條手臂（舉起來）
    let armBack = CGMutablePath()
    armBack.move(to: CGPoint(x: 98, y: 58))
    armBack.addQuadCurve(to: CGPoint(x: 128 + sway, y: 92), control: CGPoint(x: 122, y: 60))
    line(ctx, armBack, outline, width: 9)
    line(ctx, armBack, barkDark, width: 6)
    shape(ctx, ellipse(130 + sway, 96, 22, 18), leaf, lineWidth: 1.8)
    // 樹幹
    let trunk = CGMutablePath()
    trunk.move(to: CGPoint(x: 52, y: 10))
    trunk.addCurve(to: CGPoint(x: 56, y: 86), control1: CGPoint(x: 46, y: 40), control2: CGPoint(x: 52, y: 70))
    trunk.addLine(to: CGPoint(x: 100, y: 86))
    trunk.addCurve(to: CGPoint(x: 106, y: 10), control1: CGPoint(x: 104, y: 70), control2: CGPoint(x: 112, y: 40))
    trunk.closeSubpath()
    shape(ctx, trunk, bark)
    clipped(ctx, to: trunk) {
        for (x, c) in [(CGFloat(62), CGFloat(66)), (78, 80), (94, 90)] {
            line(ctx, quad(CGPoint(x: x, y: 12), CGPoint(x: x + 2, y: 84), CGPoint(x: c, y: 46)), barkDark, width: 1.4)
        }
    }
    // 樹冠
    for (x, y, r) in [(CGFloat(56), CGFloat(92), CGFloat(20)), (78, 106, 26), (102, 94, 20), (66, 112, 16), (92, 114, 17)] {
        shape(ctx, ellipse(x + sway * 0.3, y, r * 2, r * 1.7), leaf, lineWidth: 1.8)
        shape(ctx, ellipse(x - r * 0.3 + sway * 0.3, y + r * 0.3, r * 0.8, r * 0.5), leafLight, stroke: false)
    }
    // 前面的枝條手臂（揮過來）
    let armFront = CGMutablePath()
    armFront.move(to: CGPoint(x: 58, y: 54))
    armFront.addQuadCurve(to: CGPoint(x: 22 - sway, y: 46), control: CGPoint(x: 36, y: 64))
    line(ctx, armFront, outline, width: 9)
    line(ctx, armFront, bark, width: 6)
    for (dx, dy) in [(CGFloat(-6), CGFloat(6)), (-8, -4), (0, -8)] {
        line(ctx, segment(CGPoint(x: 22 - sway, y: 46), CGPoint(x: 22 - sway + dx, y: 46 + dy)), outline, width: 3.4)
        line(ctx, segment(CGPoint(x: 22 - sway, y: 46), CGPoint(x: 22 - sway + dx, y: 46 + dy)), bark, width: 1.8)
    }
    // 臉：發光的樹洞眼睛、大嘴
    for (x, left) in [(CGFloat(66), true), (86, false)] {
        shape(ctx, ellipse(x, 62, 13, 11), barkDark, lineWidth: 1.4)
        bossEye(ctx, CGPoint(x: x, y: 62), size: 4.5, hit: hit, glow: hit ? nil : hex(0xD7FF6B), left: left)
    }
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: 64, y: 44))
    mouth.addQuadCurve(to: CGPoint(x: 88, y: 44), control: CGPoint(x: 76, y: hit ? 30 : 36))
    mouth.closeSubpath()
    shape(ctx, mouth, hex(0x2E1C12), lineWidth: 1.6)
    // 腳邊的蘑菇
    for (x, s) in [(CGFloat(40), CGFloat(1)), (112, 0.8)] {
        line(ctx, segment(CGPoint(x: x, y: 5), CGPoint(x: x, y: 5 + 8 * s)), outline, width: 4.6)
        line(ctx, segment(CGPoint(x: x, y: 5), CGPoint(x: x, y: 5 + 8 * s)), hex(0xF6E7D2), width: 3)
        let cap = CGMutablePath()
        cap.move(to: CGPoint(x: x - 8 * s, y: 12 * s + 1))
        cap.addQuadCurve(to: CGPoint(x: x + 8 * s, y: 12 * s + 1), control: CGPoint(x: x, y: 26 * s))
        cap.closeSubpath()
        shape(ctx, cap, hex(0xE0503C), lineWidth: 1.4)
        shape(ctx, ellipse(x - 2 * s, 16 * s, 3 * s, 2.4 * s), white, stroke: false)
    }
    if hit { hitBurst(ctx, at: CGPoint(x: 48, y: 56)) }
}

// 城堡：黑暗騎士——深紫鎧甲、紅羽毛頭盔、頭盔縫裡發紅光的眼睛，舉著大劍、拿著盾。
func drawDarkKnight(_ ctx: CGContext, frame: Int, hit: Bool) {
    let metal = hex(0x4A4E6A), metalDark = hex(0x2F3248), metalLight = hex(0x8A90B4), plume = hex(0xD8433A)
    let bob: CGFloat = hit ? -2 : (frame == 0 ? 0 : 1.5)
    shape(ctx, ellipse(80, 7, 80, 8), hex(0x000000, 0.14), stroke: false)
    // 腳
    for x in [CGFloat(68), 92] {
        shape(ctx, rounded(x - 8, 5, 16, 30, 4), metalDark, lineWidth: 1.8)
        shape(ctx, rounded(x - 10, 4, 20, 7, 3), metal, lineWidth: 1.6)
    }
    withState(ctx, { c in c.translateBy(x: 0, y: bob) }) {
        // 後面的手舉著大劍
        let blade = polygon([CGPoint(x: 112, y: 62), CGPoint(x: 120, y: 118), CGPoint(x: 116, y: 124), CGPoint(x: 112, y: 118), CGPoint(x: 106, y: 63)])
        shape(ctx, blade, hex(0xC9D2E3), lineWidth: 1.6)
        line(ctx, segment(CGPoint(x: 101, y: 64), CGPoint(x: 117, y: 60)), outline, width: 5)
        line(ctx, segment(CGPoint(x: 101, y: 64), CGPoint(x: 117, y: 60)), hex(0x9C6BD8), width: 3)
        shape(ctx, ellipse(108, 57, 11, 11), metal, lineWidth: 1.6)
        // 身體（胸甲 + 裙甲）
        let body = rounded(56, 30, 48, 42, 10)
        shape(ctx, polygon([CGPoint(x: 56, y: 34), CGPoint(x: 104, y: 34), CGPoint(x: 108, y: 18), CGPoint(x: 52, y: 18)]), metalDark, lineWidth: 1.8)
        shape(ctx, body, metal)
        line(ctx, segment(CGPoint(x: 80, y: 34), CGPoint(x: 80, y: 68)), metalLight, width: 1.6)
        shape(ctx, ellipse(68, 64, 22, 14), metalLight, lineWidth: 1.6)   // 肩甲
        shape(ctx, ellipse(94, 64, 20, 13), metal, lineWidth: 1.6)
        // 頭盔 + 紅羽毛
        let helm = CGMutablePath()
        helm.move(to: CGPoint(x: 62, y: 70))
        helm.addCurve(to: CGPoint(x: 98, y: 70), control1: CGPoint(x: 60, y: 108), control2: CGPoint(x: 100, y: 108))
        helm.closeSubpath()
        shape(ctx, petal(CGPoint(x: 84, y: 98), CGPoint(x: 112, y: 108 + bob * 2), width: 12), plume, lineWidth: 1.6)
        shape(ctx, helm, metal)
        shape(ctx, rounded(62, 80, 26, 8, 3), hex(0x15121C), lineWidth: 1.4)   // 面罩縫（朝左）
        for x in [CGFloat(68), 80] {
            bossEye(ctx, CGPoint(x: x, y: 84), size: 3.4, hit: hit, glow: hit ? nil : hex(0xFF4A4A), left: x < 75)
        }
        line(ctx, segment(CGPoint(x: 80, y: 92), CGPoint(x: 80, y: 104)), metalLight, width: 1.6)
        // 前面的盾（紫底金邊、中間一顆星）
        let shield = CGMutablePath()
        shield.move(to: CGPoint(x: 38, y: 64))
        shield.addLine(to: CGPoint(x: 64, y: 64))
        shield.addQuadCurve(to: CGPoint(x: 51, y: 24), control: CGPoint(x: 66, y: 34))
        shield.addQuadCurve(to: CGPoint(x: 38, y: 64), control: CGPoint(x: 36, y: 34))
        shield.closeSubpath()
        shape(ctx, shield, hex(0x5B2A86), lineWidth: 2)
        line(ctx, shield, hex(0xF2C94C), width: 1.4)
        sparkle(ctx, at: CGPoint(x: 51, y: 48), size: 7, color: hex(0xF2C94C))
        if hit { hitBurst(ctx, at: CGPoint(x: 44, y: 60)) }
    }
}

func bezierPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

// 星空神殿：星空神龍——深藍到紫的長身體、身上滿是星星，金色的角、發光的眼睛，周圍飄著星光。
func drawStarDragon(_ ctx: CGContext, frame: Int, hit: Bool) {
    let bob: CGFloat = hit ? -3 : (frame == 0 ? 0 : 3)
    let navy = hex(0x1E2A6E), purple = hex(0x6A3FC8), glow = hex(0x8FE3FF)
    // 光暈
    let aura = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [hex(0x8FE3FF, 0.35), hex(0xB18CFF, 0.15), hex(0xB18CFF, 0)] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawRadialGradient(aura, startCenter: CGPoint(x: 80, y: 64), startRadius: 0, endCenter: CGPoint(x: 80, y: 64), endRadius: 70, options: [])
    withState(ctx, { c in c.translateBy(x: 0, y: bob) }) {
        // 彎彎的身體（從尾巴繞到脖子）
        let c0 = CGPoint(x: 140, y: 24), c1 = CGPoint(x: 96, y: -6), c2 = CGPoint(x: 60, y: 40), c3 = CGPoint(x: 62, y: 84)
        let bodyWidth: (CGFloat) -> CGFloat = { t in
            let belly: CGFloat = 22 * sin(CGFloat.pi * min(1, t * 1.15))
            return 6 + belly + 4 * t
        }
        let body = hairStrand(c0, c1, c2, c3, width: bodyWidth)
        // 背鰭
        for t in stride(from: CGFloat(0.2), through: 0.8, by: 0.15) {
            let c = bezierPoint(c0, c1, c2, c3, t)
            shape(ctx, polygon([CGPoint(x: c.x + 6, y: c.y + 4), CGPoint(x: c.x + 20, y: c.y + 14), CGPoint(x: c.x + 8, y: c.y - 6)]), purple, lineWidth: 1.4)
        }
        gradientFill(ctx, body, [navy, purple], from: CGPoint(x: 140, y: 24), to: CGPoint(x: 62, y: 84))
        line(ctx, body, outline, width: 2.2)
        clipped(ctx, to: body) {
            for k in 0..<14 {
                let q = CGPoint(x: 50 + 100 * noise(k * 3 + 1), y: 4 + 90 * noise(k * 3 + 2))
                sparkle(ctx, at: q, size: 1.8 + 2 * noise(k * 3 + 3), color: k % 3 == 0 ? hex(0xFFF3C4) : white)
            }
        }
        // 頭（朝左）
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 72, y: 76))
        head.addCurve(to: CGPoint(x: 26, y: 88), control1: CGPoint(x: 60, y: 70), control2: CGPoint(x: 30, y: 76))
        head.addQuadCurve(to: CGPoint(x: 40, y: 104), control: CGPoint(x: 24, y: 100))
        head.addCurve(to: CGPoint(x: 78, y: 98), control1: CGPoint(x: 54, y: 112), control2: CGPoint(x: 72, y: 110))
        head.closeSubpath()
        // 金角
        for (a, b) in [(CGPoint(x: 62, y: 104), CGPoint(x: 80, y: 124)), (CGPoint(x: 52, y: 106), CGPoint(x: 60, y: 126))] {
            shape(ctx, petal(a, b, width: 6), hex(0xF2C94C), lineWidth: 1.5)
        }
        gradientFill(ctx, head, [hex(0x2B3A8C), purple], from: CGPoint(x: 26, y: 90), to: CGPoint(x: 78, y: 100))
        line(ctx, head, outline, width: 2.2)
        // 鬍鬚
        let whisker = quad(CGPoint(x: 30, y: 90), CGPoint(x: 6, y: 72 + bob), CGPoint(x: 12, y: 92))
        line(ctx, whisker, glow, width: 2)
        bossEye(ctx, CGPoint(x: 44, y: 96), size: 4.5, hit: hit, glow: hit ? nil : glow, left: true)
        line(ctx, segment(CGPoint(x: 28, y: 88), CGPoint(x: 42, y: 86)), outline, width: 1.6)   // 嘴
        if hit { hitBurst(ctx, at: CGPoint(x: 60, y: 52)) }
    }
    // 飄著的星光（每格位置不同）
    for k in 0..<6 {
        let n = frame * 13 + k * 5 + (hit ? 99 : 0)
        sparkle(ctx, at: CGPoint(x: 20 + 120 * noise(n), y: 20 + 100 * noise(n + 1)), size: 2 + 3 * noise(n + 2),
                color: k % 2 == 0 ? hex(0xFFF3C4) : white)
    }
}

let bosses: [(id: String, draw: (CGContext, Int, Bool) -> Void)] = [
    ("meadow", drawSlimeKing), ("forest", drawTreant), ("castle", drawDarkKnight), ("temple", drawStarDragon),
]

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

// 像素風格：先在很粗的格子上（每格 cell 個設計單位）不開反鋸齒地畫，半透明的地方二選一變成全透明或不透明，
// 再用最近鄰放大回正常尺寸，看起來就是一格一格的像素圖。
func renderPixelPNG(width: CGFloat, height: CGFloat, cell: CGFloat, _ draw: (CGContext) -> Void) -> Data {
    let gw = Int((width / cell).rounded(.up)), gh = Int((height / cell).rounded(.up))
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    let low = CGContext(data: nil, width: gw, height: gh, bitsPerComponent: 8, bytesPerRow: gw * 4, space: space, bitmapInfo: info)!
    low.setShouldAntialias(false)
    low.setAllowsAntialiasing(false)
    low.scaleBy(x: 1 / cell, y: 1 / cell)
    low.setLineJoin(.miter)
    low.setLineCap(.square)
    pixelCell = cell
    draw(low)
    pixelCell = 0
    let px = low.data!.bindMemory(to: UInt8.self, capacity: gw * gh * 4)
    for i in 0..<(gw * gh) {
        let a = Int(px[i * 4 + 3])
        if a < 110 {
            for k in 0..<4 { px[i * 4 + k] = 0 }
        } else if a < 255 {
            for k in 0..<3 { px[i * 4 + k] = UInt8(min(255, Int(px[i * 4 + k]) * 255 / a)) }
            px[i * 4 + 3] = 255
        }
    }
    let out = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: info)!
    out.interpolationQuality = .none
    out.draw(low.makeImage()!, in: CGRect(x: 0, y: 0, width: CGFloat(gw) * cell * scale, height: CGFloat(gh) * cell * scale))
    return NSBitmapImageRep(cgImage: out.makeImage()!).representation(using: .png, properties: [:])!
}

let fm = FileManager.default
for dir in ["body", "outfits", "looks"] {
    try? fm.removeItem(at: outputRoot.appendingPathComponent(dir))
}

func write(_ data: Data, _ relative: String) throws {
    // props/ 是所有角色共用的，放在 Resources/props；其他放在角色自己的資料夾。
    let url = (relative.hasPrefix("props/") ? resourcesRoot : outputRoot).appendingPathComponent(relative)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

// 調外觀時的快速預覽：LOOK_PREVIEW=idle_0,dance_10 只畫這幾格的外觀圖層（不畫本體、服裝、道具）。
let previewFrames: Set<String>? = ProcessInfo.processInfo.environment["LOOK_PREVIEW"]
    .map { Set($0.split(separator: ",").map(String.init)) }

var count = 0
for spec in actions where previewFrames == nil {
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

if previewFrames == nil || ProcessInfo.processInfo.environment["BOSS_PREVIEW"] != nil {
    for boss in bosses {
        for (name, frame, hit) in [("idle_0", 0, false), ("idle_1", 1, false), ("hit", 0, true)] {
            try write(renderPixelPNG(width: bossWidth, height: bossHeight, cell: bossPixel) { boss.draw($0, frame, hit) },
                      "props/boss_\(boss.id)_\(name).png")
            count += 1
        }
    }
}
if previewFrames == nil {
try write(renderPNG(height: canopyHeight, offset: 0) { drawCanopy($0) }, "props/parachute.png")
try write(renderPNG(height: canopyHeight, offset: 0) { drawUmbrellaProp($0) }, "props/umbrella_open.png")
try write(renderPNG(width: diningWidth, height: diningHeight) { drawDining($0, meal: false) }, "props/dining.png")
try write(renderPNG(width: diningWidth, height: diningHeight) { drawDining($0, meal: true) }, "props/dining_meal.png")
try write(renderPNG(width: computerWidth, height: computerHeight) { drawComputer($0, on: false) }, "props/computer.png")
try write(renderPNG(width: computerWidth, height: computerHeight) { drawComputer($0, on: true) }, "props/computer_on.png")
try write(renderPNG(width: swingWidth, height: swingHeight) { drawSwingTree($0) }, "props/swing.png")
for (part, name) in [(PlanePart.parked, "plane"), (.back, "plane_back"), (.front(0), "plane_front_0"), (.front(1), "plane_front_1")] {
    try write(renderPNG(width: planeWidth, height: planeHeight) { drawPlane($0, part) }, "props/\(name).png")
}
count += 11
}

// 外觀圖層：每種髮型畫 hairBehind / head，每套服裝畫 base / top，各自獨立，App 再疊起來。
// 哪幾格是背對畫面的（App 要把天使翅膀這類「在身後」的服裝改疊到身體前面）。
var backFrames: [String: [Int]] = [:]
for spec in actions {
    for i in 0..<spec.frames {
        var p = pose(spec.name, i, spec.frames)
        p.frame = i
        p.frameCount = spec.frames
        if p.back { backFrames[spec.name, default: []].append(i) }
        if let previewFrames, !previewFrames.contains("\(spec.name)_\(i)") { continue }
        for hair in hairStyles {
            look = Look(hair: hair, clothes: amiyaClothes)
            try write(renderPNG { drawBody($0, p, [.hairBehind]) }, "looks/hair/\(hair.id)/behind/\(spec.name)_\(i).png")
            try write(renderPNG { drawBody($0, p, [.head]) }, "looks/hair/\(hair.id)/head/\(spec.name)_\(i).png")
            count += 2
        }
        for clothes in clothesStyles {
            look = Look(hair: amiyaHair, clothes: clothes)
            try write(renderPNG { drawBody($0, p, [.base]) }, "looks/clothes/\(clothes.id)/base/\(spec.name)_\(i).png")
            try write(renderPNG { drawBody($0, p, [.top]) }, "looks/clothes/\(clothes.id)/top/\(spec.name)_\(i).png")
            count += 2
        }
    }
}
look = defaultLook

// 會呼叫 cutOutBody、畫在她身後的服裝：正面時 App 把它們疊在身體下面，長髮才會蓋在翅膀前面。
let behindOutfits: Set<String> = ["wings", "vip_wings"]

// manifest.json：程式靠它知道有哪些動作、幾格、多快，以及有哪些服裝。
let manifest: [String: Any] = [
    "name": characterName,
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
         "power": outfitPower[$0.id] ?? 0, "dungeon": dungeonOutfits.contains($0.id),
         "behind": behindOutfits.contains($0.id)] as [String: Any]
    },
    // 外觀（髮型 / 服裝）：純外觀、不加戰鬥力。第一個是預設。
    "looks": [
        "hair": hairStyles.map { ["id": $0.id, "name": $0.name] },
        "clothes": clothesStyles.map { ["id": $0.id, "name": $0.name] },
    ],
    "backFrames": backFrames,
]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try write(json, "manifest.json")

print("已產生 \(count) 張圖到 \(outputRoot.path)")
