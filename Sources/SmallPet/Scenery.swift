// Scenery.swift —— 桌面上的家具佈景：餐桌、電腦桌、鞦韆（一棵樹）、飛機。
//
// 每件家具是獨立的透明視窗，擺在螢幕底部、寵物後面。可以左右拖曳，位置會記住。
// 選單的「家具與佈景」可以一起顯示 / 隱藏，也可以個別勾選要擺哪幾件。
// ⌥F 是另一回事：把寵物和家具全部藏起來（見 AppDelegate.toggleEverything），勾選不會變。
//   - 餐桌：餵食時盤子會放上胡蘿蔔，她自己走過來坐下吃；就算家具是隱藏的也會暫時出現，吃完再收起來。
//   - 電腦桌、鞦韆、飛機：家具顯示時，她閒著會自己過去打電腦、盪鞦韆、開飛機。
//     飛機分成兩個視窗夾住寵物：後層在她後面、前層（機身、螺旋槳）在她前面，看起來就像坐在駕駛艙裡。
//
// 圖片用的座標跟寵物畫布一樣，所以寵物視窗的 x 對齊家具視窗的 x，她就剛好坐在凳子 / 座板上。
import AppKit
import Carbon.HIToolbox

@MainActor
final class Scenery {

    let dining: Prop
    let computer: Prop
    let swing: Prop
    let plane: Prop
    private let rig: SwingRig
    private let planeFront: SceneryWindow
    private let planeParked: NSImage?
    private let planeBack: NSImage?
    private let propellerFrames: [NSImage?]
    private var planeHome: NSPoint?     // 飛行中，飛機原本停的位置
    var all: [Prop] { [dining, computer, swing, plane] }

    // 家具總開關（選單切換）。打開時只顯示有勾選的那幾件（Prop.enabled）。
    private(set) var pinned: Bool {
        didSet { UserDefaults.standard.set(pinned, forKey: "scenery.visible") }
    }

    var mealInProgress: Bool { dining.inUse }

    // 被 ⌥F 藏起來了：不管勾選什麼都不顯示，選單改勾選要等顯示回來才看得到。
    private var concealed = false

    func setConcealed(_ on: Bool, below pet: NSWindow) {
        concealed = on
        refresh(below: pet)
    }

    init(sprites: SpriteLibrary) {
        let mid = NSScreen.main?.visibleFrame.midX ?? 0
        // 第一次的預設位置：電腦桌在左、餐桌在中間、鞦韆在右。
        dining = Prop(sprites: sprites, title: "餐桌", name: "dining", activeName: "dining_meal", key: "scenery.x", defaultX: mid - 70)
        computer = Prop(sprites: sprites, title: "電腦桌", name: "computer", activeName: "computer_on", key: "scenery.computer.x", defaultX: mid - 330)
        swing = Prop(sprites: sprites, title: "鞦韆", name: "swing", activeName: nil, key: "scenery.swing.x", defaultX: mid + 180)
        plane = Prop(sprites: sprites, title: "飛機", name: "plane", activeName: nil, key: "scenery.plane.x",
                     defaultX: mid + 420, sink: Self.planeMargin)
        rig = SwingRig()
        swing.window.addOverlay(rig.layer)
        planeParked = sprites.prop("plane")
        planeBack = sprites.prop("plane_back")
        propellerFrames = [sprites.prop("plane_front_0"), sprites.prop("plane_front_1")]
        planeFront = SceneryWindow(image: propellerFrames[0])
        planeFront.ignoresMouseEvents = true
        pinned = UserDefaults.standard.bool(forKey: "scenery.visible")
    }

    // 啟動時呼叫：依記住的狀態顯示。要在寵物視窗之後呼叫，才會排在寵物後面。
    func restore(below pet: NSWindow) {
        refresh(below: pet)
    }

    // 這件家具現在是不是擺出來的（不算吃飯時暫時出現）。
    func isShown(_ prop: Prop) -> Bool { pinned && prop.enabled }

    func toggle(below pet: NSWindow) {
        pinned.toggle()
        // 上次把每一件都取消了的話，重新打開就全部擺回來，不然按了會沒反應。
        if pinned, !all.contains(where: \.enabled) { all.forEach { $0.enabled = true } }
        refresh(below: pet)
    }

    // 切換單件家具。總開關關著時，勾哪件就只擺那一件；取消到一件不剩就等於關掉總開關。
    func toggle(_ prop: Prop, below pet: NSWindow) {
        if pinned {
            prop.enabled.toggle()
            if !all.contains(where: \.enabled) { pinned = false }
        } else {
            all.forEach { $0.enabled = $0 === prop }
            pinned = true
        }
        refresh(below: pet)
    }

    // 她要用這件家具了：換成「使用中」的圖、一定顯示、不能拖。
    func use(_ prop: Prop, below pet: NSWindow) {
        prop.inUse = true
        refresh(below: pet)
    }

    // 不用了（做完、被抓走、改做別的事）。
    func release(_ prop: Prop, below pet: NSWindow) {
        guard prop.inUse else { return }
        prop.inUse = false
        refresh(below: pet)
    }

    func releaseAll(below pet: NSWindow) {
        all.forEach { release($0, below: pet) }
    }

    // 飛機圖上下各多留的空間（generate-bunny.swift 的 planeMargin），和駕駛座的位置。
    // 駕駛座：寵物畫布上她屁股的位置，飛機圖上同一點要再加 planeMargin。
    static let planeMargin: CGFloat = 16
    private static let seat = CGPoint(x: 58, y: 17)

    // 每一幀呼叫：她坐進飛機後，飛機拆成前後兩層夾住她，跟著她走、轉向、傾斜，螺旋槳轉動；
    // 下飛機（或被抓走）就停回原位、換回停著的圖。
    // - rider：她的視窗；nil 代表她不在飛機上。
    func updatePlane(rider window: NSWindow?, facingLeft: Bool, pitch: CGFloat, time: Double) {
        guard let window, plane.inUse else {
            if let home = planeHome {
                planeHome = nil
                planeFront.orderOut(nil)
                plane.window.setImage(planeParked)
                for w in [plane.window, planeFront] {
                    w.setFrameOrigin(home)
                    w.setArtTransform(.identity)
                }
            }
            return
        }
        if planeHome == nil {
            planeHome = plane.window.frame.origin
            plane.window.setImage(planeBack)
            if plane.window.isVisible { planeFront.order(.above, relativeTo: window.windowNumber) }
        }

        // 圖以視窗中心為基準翻面、傾斜，再把視窗擺到「駕駛座剛好在她屁股下面」的位置。
        let flip: CGFloat = facingLeft ? -1 : 1
        let transform = CGAffineTransform(rotationAngle: pitch * flip).scaledBy(x: flip, y: 1)
        let size = plane.window.frame.size
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let seat = CGPoint(x: Self.seat.x - center.x, y: Self.seat.y + Self.planeMargin - center.y).applying(transform)
        let rider = window.frame
        let riderSeat = CGPoint(x: rider.minX + (facingLeft ? rider.width - Self.seat.x : Self.seat.x), y: rider.minY + Self.seat.y)
        let origin = NSPoint(x: riderSeat.x - center.x - seat.x, y: riderSeat.y - center.y - seat.y)
        for w in [plane.window, planeFront] {
            w.setFrameOrigin(origin)
            w.setArtTransform(transform)
        }
        planeFront.setImage(propellerFrames[Int(time * 20) % propellerFrames.count])
    }

    // 每一幀呼叫：她在盪鞦韆時，繩子和座板跟著她的視窗位置走；不然就靜靜垂著。
    func updateSwing(riderOrigin: NSPoint?) {
        let rest = swing.window.frame.origin
        rig.offset = riderOrigin.map { CGPoint(x: $0.x - rest.x, y: $0.y - rest.y) } ?? .zero
    }

    private func refresh(below pet: NSWindow) {
        for prop in all {
            if !concealed, isShown(prop) || prop.inUse {
                prop.clampToScreen()
                prop.window.order(.below, relativeTo: pet.windowNumber)
            } else {
                prop.window.orderOut(nil)
            }
        }
        // 飛機前層只在她坐進去後出現（不然她走過飛機前面會被機身擋住）。
        if plane.window.isVisible, planeHome != nil {
            planeFront.order(.above, relativeTo: pet.windowNumber)
        } else {
            planeFront.orderOut(nil)
        }
    }
}

// MARK: - 一件家具

@MainActor
final class Prop {

    let title: String
    let window: SceneryWindow
    private let image: NSImage?
    private let activeImage: NSImage?

    // 她正在用（吃飯、打電腦、盪鞦韆）：換圖、不能拖。
    var inUse = false {
        didSet {
            window.isDraggable = !inUse
            window.setImage(inUse ? activeImage ?? image : image)
        }
    }

    // 選單上有沒有勾選這件（會記住）。
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: enabledKey) }
    }
    private let enabledKey: String

    var x: CGFloat { window.frame.minX }

    // sink：視窗要比地面低多少（圖下方有留白的家具，例如飛機）。
    private let sink: CGFloat

    init(sprites: SpriteLibrary, title: String, name: String, activeName: String?, key: String, defaultX: CGFloat, sink: CGFloat = 0) {
        self.title = title
        self.sink = sink
        enabledKey = "scenery.enabled.\(name)"
        enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        image = sprites.prop(name)
        activeImage = activeName.flatMap { sprites.prop($0) }
        window = SceneryWindow(image: image)

        let visible = NSScreen.main?.visibleFrame ?? .zero
        let saved = UserDefaults.standard.object(forKey: key) as? Double
        window.setFrameOrigin(NSPoint(x: saved.map { CGFloat($0) } ?? defaultX, y: visible.minY - sink))
        window.onMoved = { x in UserDefaults.standard.set(Double(x), forKey: key) }
        clampToScreen()
    }

    // 換螢幕或 Dock 變高時，貼回地面、別超出畫面。
    func clampToScreen() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let x = min(max(window.frame.minX, visible.minX), visible.maxX - window.frame.width)
        window.setFrameOrigin(NSPoint(x: x, y: visible.minY - sink))
    }
}

// MARK: - 鞦韆的繩子和座板

// 樹是圖片，繩子和座板會動，所以用 CAShapeLayer 畫。座標跟 generate-bunny.swift 的
// swingPivot、座板位置一致（已經加上 offsetX 8）。offset 是她的視窗離靜止位置多遠。
@MainActor
final class SwingRig {
    let layer = CALayer()
    private let ropes = CAShapeLayer()
    private let seat = CAShapeLayer()

    private let pivot = CGPoint(x: 73.5, y: 130)
    private let ropeEnds = [CGPoint(x: 40, y: 16.5), CGPoint(x: 76, y: 16.5)]
    private let seatRect = CGRect(x: 34, y: 12, width: 54, height: 4.5)

    var offset = CGPoint.zero {
        didSet { if offset != oldValue { redraw() } }
    }

    init() {
        ropes.strokeColor = NSColor(srgbRed: 0.45, green: 0.32, blue: 0.22, alpha: 1).cgColor
        ropes.fillColor = nil
        ropes.lineWidth = 1.6
        ropes.lineCap = .round
        seat.fillColor = NSColor(srgbRed: 0.784, green: 0.576, blue: 0.353, alpha: 1).cgColor
        seat.strokeColor = NSColor(srgbRed: 0.169, green: 0.133, blue: 0.188, alpha: 1).cgColor
        seat.lineWidth = 1.6
        layer.addSublayer(ropes)
        layer.addSublayer(seat)
        // 靜止時的動畫關掉，位置每一幀直接更新
        for l in [ropes, seat] { l.actions = ["path": NSNull()] }
        redraw()
    }

    private func redraw() {
        let r = CGMutablePath()
        for end in ropeEnds {
            r.move(to: pivot)
            r.addLine(to: CGPoint(x: end.x + offset.x, y: end.y + offset.y))
        }
        ropes.path = r
        seat.path = CGPath(roundedRect: seatRect.offsetBy(dx: offset.x, dy: offset.y), cornerWidth: 2, cornerHeight: 2, transform: nil)
    }
}

// MARK: - 視窗

final class SceneryWindow: NSWindow {

    var onMoved: ((CGFloat) -> Void)?
    var isDraggable = true

    private let imageView = NSView()
    // 圖片放在子圖層，才能整張翻面、傾斜（飛機用）。
    private let art = CALayer()
    private var grabX: CGFloat?

    init(image: NSImage?) {
        // 產生器輸出 2 倍解析度的 PNG，NSImage 讀進來的 size 是像素，除以 2 才是點。
        let size = image.map { NSSize(width: $0.size.width / 2, height: $0.size.height / 2) } ?? NSSize(width: 1, height: 1)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isExcludedFromWindowsMenu = true

        imageView.frame = NSRect(origin: .zero, size: size)
        imageView.wantsLayer = true
        art.frame = imageView.bounds
        art.contentsGravity = .resizeAspect
        art.actions = ["contents": NSNull(), "transform": NSNull()]   // 每一幀直接換，不要淡入淡出
        imageView.layer?.addSublayer(art)
        contentView = imageView
        setImage(image)
    }

    func setImage(_ image: NSImage?) {
        art.contents = image
    }

    // 把寵物拖到這件家具上時，家具周圍亮起一圈光，表示放手就會用它。
    func setHighlighted(_ on: Bool) {
        art.shadowColor = NSColor(calibratedRed: 1, green: 0.85, blue: 0.35, alpha: 1).cgColor
        art.shadowOffset = .zero
        art.shadowRadius = 5
        art.shadowOpacity = on ? 1 : 0
    }

    // 以視窗中心為基準翻面 / 旋轉圖片。
    func setArtTransform(_ transform: CGAffineTransform) {
        art.setAffineTransform(transform)
    }

    // 疊在圖片上面的圖層（鞦韆的繩子）。
    func addOverlay(_ layer: CALayer) {
        layer.frame = imageView.bounds
        imageView.layer?.addSublayer(layer)
    }

    // 只能左右拖（家具一直貼著地面）。
    override func mouseDown(with event: NSEvent) {
        grabX = isDraggable ? NSEvent.mouseLocation.x - frame.minX : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grabX, let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let x = min(max(NSEvent.mouseLocation.x - grabX, visible.minX), visible.maxX - frame.width)
        setFrameOrigin(NSPoint(x: x, y: frame.minY))
    }

    override func mouseUp(with event: NSEvent) {
        if grabX != nil { onMoved?(frame.minX) }
        grabX = nil
    }
}

// MARK: - 全域快捷鍵

// 用 Carbon 的 RegisterEventHotKey 註冊全域快捷鍵：就算焦點在別的 App 也收得到，
// 而且不需要「輔助使用」權限（用 NSEvent 監聽全域按鍵就需要）。
@MainActor
enum HotKey {
    private static var handler: (() -> Void)?
    private static var ref: EventHotKeyRef?

    // 註冊 ⌥F。
    static func register(_ action: @escaping () -> Void) {
        handler = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon 在主執行緒呼叫這個 C 函式，不能捕捉變數，所以透過 static 找到要做的事。
            MainActor.assumeIsolated { HotKey.handler?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x534D_5054), id: 1)   // 'SMPT'
        RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
