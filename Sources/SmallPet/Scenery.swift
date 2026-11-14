// Scenery.swift —— 桌面上的家具佈景：餐桌、電腦桌、床、飛機。
//
// 每件家具是獨立的透明視窗，擺在螢幕底部、寵物後面。按住家具：
//   - 左右拖：移動（位置會記住）
//   - 往下拉：收起來（等於在選單取消勾選這件）
//   - 往上拉：打開這件家具的小工具（電腦桌是計算機）；還沒有小工具的家具會彈一下
// 選單的「家具與佈景」可以一起顯示 / 隱藏，也可以個別勾選要擺哪幾件。
// ⌥F 是另一回事：把寵物和家具全部藏起來（見 AppDelegate.toggleEverything），勾選不會變。
//   - 餐桌：餵食時盤子會放上胡蘿蔔，她自己走過來坐下吃；就算家具是隱藏的也會暫時出現，吃完再收起來。
//   - 電腦桌、床、飛機：家具顯示時，她閒著會自己過去打電腦、上床睡覺、開飛機。
//     床分成兩層：床架、枕頭在她後面，她躺好後棉被（另一個視窗）蓋在她前面。
//     飛機分成兩個視窗夾住寵物：後層在她後面、前層（機身、螺旋槳）在她前面，看起來就像坐在駕駛艙裡。
//
// 圖片用的座標跟寵物畫布一樣，所以寵物視窗的 x 對齊家具視窗的 x，她就剛好坐在凳子 / 座板上。
import AppKit
import Carbon.HIToolbox

@MainActor
final class Scenery {

    let dining: Prop
    let computer: Prop
    let bed: Prop
    let plane: Prop
    private let blanket: SceneryWindow
    private let planeFront: SceneryWindow
    private let planeParked: NSImage?
    private let planeBack: NSImage?
    private let propellerFrames: [NSImage?]
    private var planeHome: NSPoint?     // 飛行中，飛機原本停的位置
    var all: [Prop] { [dining, computer, bed, plane] }

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
        // 第一次的預設位置：電腦桌在左、餐桌在中間、床在右。
        dining = Prop(sprites: sprites, title: "餐桌", name: "dining", activeName: "dining_meal", key: "scenery.x", defaultX: mid - 70)
        computer = Prop(sprites: sprites, title: "電腦桌", name: "computer", activeName: "computer_on", key: "scenery.computer.x", defaultX: mid - 330)
        bed = Prop(sprites: sprites, title: "床", name: "bed", activeName: "bed_back", key: "scenery.bed.x", defaultX: mid + 170)
        plane = Prop(sprites: sprites, title: "飛機", name: "plane", activeName: nil, key: "scenery.plane.x",
                     defaultX: mid + 420, sink: Self.planeMargin)
        blanket = SceneryWindow(image: sprites.prop("bed_front"))
        blanket.ignoresMouseEvents = true
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

    // 往下拉收起一件家具：取消勾選；一件都不剩就等於關掉總開關。
    func hide(_ prop: Prop, below pet: NSWindow) {
        guard isShown(prop), !prop.inUse else { return }
        prop.enabled = false
        if !all.contains(where: \.enabled) { pinned = false }
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
        // 飛行中點到她（或飛機），被點的視窗會跳到最前面，她就穿出機身。每一幀檢查三層的順序，亂了就排回去：
        // 後層 < 她 < 前層（orderedIndex 越小越前面）。
        if plane.window.isVisible {
            if plane.window.orderedIndex < window.orderedIndex { plane.window.order(.below, relativeTo: window.windowNumber) }
            if !planeFront.isVisible || planeFront.orderedIndex > window.orderedIndex {
                planeFront.order(.above, relativeTo: window.windowNumber)
            }
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

    // 每一幀呼叫：她躺在床上時，棉被蓋在她前面（點到她、她的視窗跳到最前面時再蓋回去）；起床就收起來。
    // - sleeper：她的視窗；nil 代表她不在床上。
    func updateBed(sleeper window: NSWindow?) {
        guard let window, bed.inUse, bed.window.isVisible else {
            if blanket.isVisible { blanket.orderOut(nil) }
            return
        }
        blanket.setFrameOrigin(bed.window.frame.origin)
        if !blanket.isVisible || blanket.orderedIndex > window.orderedIndex {
            blanket.order(.above, relativeTo: window.windowNumber)
        }
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

    // 她正在用（吃飯、打電腦、睡床）：換圖、不能拖、不能往下拉收起來（往上拉開小工具還是可以）。
    var inUse = false {
        didSet {
            window.isDraggable = !inUse
            window.canSwipeDown = !inUse
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

// MARK: - 視窗

final class SceneryWindow: NSWindow {

    var onMoved: ((CGFloat) -> Void)?
    var onSwipeDown: (() -> Void)?     // 往下拉：收起來
    var onSwipeUp: (() -> Void)?       // 往上拉：開小工具（nil = 這件家具還沒有小工具）
    var isDraggable = true
    var canSwipeDown = true

    private let imageView = NSView()
    // 拉動時的回饋（往下沉、往上伸）套在 holder 上；圖片在 holder 裡的 art，才能整張翻面、傾斜（飛機用）。
    private let holder = CALayer()
    private let art = CALayer()

    // 按下去之後先不動，拖超過 dead 點才決定是哪一種手勢；拉超過 trigger 點放手才算數。
    private enum Gesture { case undecided, move, down, up, none }
    private var gesture = Gesture.none
    private var grab = NSPoint.zero        // 按下時滑鼠的位置
    private var grabX: CGFloat = 0         // 按下時滑鼠離視窗左邊多遠
    private static let dead: CGFloat = 6
    private static let trigger: CGFloat = 28

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
        // holder 以底邊中央為支點：往上拉時從地面往上伸長
        holder.anchorPoint = CGPoint(x: 0.5, y: 0)
        holder.frame = imageView.bounds
        art.frame = holder.bounds
        art.contentsGravity = .resizeAspect
        art.actions = ["contents": NSNull(), "transform": NSNull()]   // 每一幀直接換，不要淡入淡出
        holder.addSublayer(art)
        imageView.layer?.addSublayer(holder)
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

    // MARK: 拖動手勢

    override func mouseDown(with event: NSEvent) {
        grab = NSEvent.mouseLocation
        grabX = grab.x - frame.minX
        gesture = .undecided
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - grab.x, dy = now.y - grab.y
        if gesture == .undecided, hypot(dx, dy) > Self.dead {
            // 比較偏左右就是移動（家具一直貼著地面）；比較偏上下就是拉
            if abs(dx) >= abs(dy) {
                gesture = isDraggable ? .move : .none
            } else if dy < 0 {
                gesture = canSwipeDown && onSwipeDown != nil ? .down : .none
            } else {
                gesture = .up
            }
        }
        switch gesture {
        case .move:
            guard let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
            let x = min(max(now.x - grabX, visible.minX), visible.maxX - frame.width)
            setFrameOrigin(NSPoint(x: x, y: frame.minY))
        case .down:
            // 往地面沉下去、慢慢變淡；超過門檻後再拉就不太動了（橡皮筋）
            let d = rubberBand(-dy)
            setFeedback(CATransform3DMakeTranslation(0, -d, 0), opacity: 1 - 0.5 * min(d / Self.trigger, 1))
        case .up:
            // 從地面往上伸長一點；沒有小工具的家具伸得比較少
            let k: CGFloat = onSwipeUp == nil ? 0.004 : 0.008
            setFeedback(CATransform3DMakeScale(1, 1 + rubberBand(dy) * k, 1), opacity: 1)
        case .undecided, .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let dy = NSEvent.mouseLocation.y - grab.y
        switch gesture {
        case .move:
            onMoved?(frame.minX)
        case .down where -dy >= Self.trigger:
            // 整個沉到地下再收起來
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setCompletionBlock { [weak self] in
                self?.onSwipeDown?()
                self?.setFeedback(CATransform3DIdentity, opacity: 1)   // 下次顯示時是原本的樣子
            }
            holder.transform = CATransform3DMakeTranslation(0, -frame.height, 0)
            holder.opacity = 0
            CATransaction.commit()
        case .up where dy >= Self.trigger:
            springBack()
            onSwipeUp?()
        default:
            springBack()
        }
        gesture = .none
    }

    // 拉越遠阻力越大：門檻以內 1:1，之後只跟一點點。
    private func rubberBand(_ d: CGFloat) -> CGFloat {
        let d = max(d, 0)
        return d <= Self.trigger ? d : Self.trigger + (d - Self.trigger) * 0.15
    }

    // 拖曳中直接套用，不要動畫（不然會跟不上滑鼠）。
    private func setFeedback(_ transform: CATransform3D, opacity: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.transform = transform
        holder.opacity = Float(opacity)
        CATransaction.commit()
    }

    private func springBack() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        holder.transform = CATransform3DIdentity
        holder.opacity = 1
        CATransaction.commit()
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
