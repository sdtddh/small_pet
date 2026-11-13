// Pet.swift —— 寵物的行為：動作狀態機 + 簡單物理。
//
// 每一幀 (tick) 做三件事：
//   1. 物理：在空中就受重力往下掉；在地上依動作走 / 跑。
//   2. 狀態機：動作時間到了就換下一個（自動模式），跳躍、掉落則等落地才結束。
//   3. 畫面：算出該顯示哪一格圖，交給 PetView。
import AppKit

@MainActor
final class Pet {

    // MARK: - 可調整的手感參數

    struct Tuning {
        var walkSpeed: CGFloat = 45         // 走路速度：點/秒
        var runSpeed: CGFloat = 150         // 跑步速度
        var gravity: CGFloat = 1800         // 重力加速度：點/秒²
        var jumpVelocity: CGFloat = 620     // 起跳的向上初速度
        var jumpForward: CGFloat = 110      // 起跳時順便往前的速度
        var crouchTime: Double = 0.12       // 起跳前蹲下的時間
        var landTime: Double = 0.15         // 落地緩衝的時間
        var maxThrowSpeed: CGFloat = 1800   // 甩出去的最大速度
        var parachuteHeight: CGFloat = 0.5  // 往下掉時離地超過螢幕高度的這個比例，就開傘
        var parachuteSpeed: CGFloat = 70    // 開傘後的下降速度：點/秒
        var parachuteDrag: CGFloat = 3      // 開傘後速度收斂的快慢（越大越快變慢）
        var swingPeriod: Double = 2.4       // 盪鞦韆一來一回幾秒（要跟素材 swing 的 fps 對上）
        var swingAngle: CGFloat = 0.3       // 盪鞦韆最大擺角（弧度）
        var swingLength: CGFloat = 113.5    // 繩長：樹枝到座板的距離（點）
        var flySpeed: CGFloat = 200         // 飛機巡航速度：點/秒
        var flyAltitude: CGFloat = 0.45     // 巡航高度：螢幕高度的比例（上下再飄 50 點）
    }
    var tuning = Tuning()

    // MARK: - 狀態

    let window: PetWindow
    let view: PetView
    private let canopy: CanopyWindow
    let speech: PetSpeech
    private let sprites: SpriteLibrary
    private let size: NSSize

    // 視窗左下角的位置與速度。
    private var posX: CGFloat = 0
    private var posY: CGFloat = 0
    private var vx: CGFloat = 0
    private var vy: CGFloat = 0
    private var direction: CGFloat = 1      // 1 向右、-1 向左

    private(set) var action: PetAction = .idle
    private var actionTime: Double = 0      // 目前動作已經做了幾秒
    private var actionDuration: Double = 3  // 自動模式下這個動作預計做幾秒

    // 自動模式：寵物自己隨機決定要做什麼。關掉後會一直做你選的動作。
    var autoMode = true
    // 手動模式下，跳躍 / 掉落結束後要回到的動作。
    private var heldAction: PetAction = .idle

    // 沒開自動行動時，她一直在做的那個動作（跳躍、吃飯這類插播做完會回到它）。
    var lockedAction: PetAction? { autoMode ? nil : heldAction }

    // 插播動作（吃東西、升等跳舞）：做完 actionDuration 秒就回到原本的節奏，
    // 手動模式下也一樣。afterInterlude 在正常做完時呼叫；中途被抓起來就取消。
    private var isInterlude = false
    private var afterInterlude: (() -> Void)?

    // 走到某個位置（例如餐桌）：到了轉向 walkFacing、呼叫 afterWalk。中途被抓走或換動作就取消。
    private var walkTarget: CGFloat?
    private var walkFacing: CGFloat = 1
    private var afterWalk: (() -> Void)?

    // 盪鞦韆時，靜止的位置（視窗 x）。
    private var swingCenter: CGFloat = 0

    // 開飛機：滑行 → 起飛 → 在天上飄（碰到螢幕邊就掉頭）→ 時間到從左邊進場，降落滑回停機位。
    private enum FlightPhase { case taxi, air, landing(distance: CGFloat, altitude: CGFloat) }
    private var flightPhase = FlightPhase.taxi
    private var flightHome: CGFloat = 0
    private var flightSpeed: CGFloat = 0
    // 機頭仰角（弧度，正值往上），給飛機的圖傾斜用。
    private(set) var flightPitch: CGFloat = 0
    var facingLeft: Bool { direction < 0 }

    // 自動模式換動作時，有 outingChance 的機率先問 onOuting 要不要去哪裡
    // （角落坐坐、打電腦、盪鞦韆）；它回 true 代表已經安排好了。
    var onOuting: (() -> Bool)?
    var outingChance = 0.35

    // 出門冒險：跑出螢幕 → 藏起來 → 時間到從螢幕邊跑回來。
    // fighting：在桌面上砍地下城的 boss（冒險期間一直打，時間到才結束）。
    enum Travel { case none, leaving, away, arriving, fighting }

    // 砍 boss 時每砍中一刀呼叫（attack 動作的第 3 格）。
    var onAttackHit: (() -> Void)?
    private static let attackImpactFrame = 3
    private var lastAttackFrame = -1
    private(set) var travel = Travel.none
    private var afterTravel: (() -> Void)?

    // 跳躍的階段。
    private var jumpLaunched = false
    private var landedAt: Double?

    // 拖曳：記錄最近幾個位置，放手時算出甩出去的速度。
    private var isDragging = false
    private var dragSamples: [(time: Double, point: NSPoint)] = []
    private var wasThrown = false   // 被甩出去，落地時要說話

    // 拖到家具上放手：拖曳中每次移動都回報她現在的位置（讓家具亮起來，放手時傳 nil）；
    // 放手時問 onDrop 這裡有沒有家具，有的話她直直落下（不甩出去），落地後執行它回傳的事。
    var onDragHover: ((NSRect?) -> Void)?
    var onDrop: ((NSRect) -> (() -> Void)?)?
    private var afterLanding: (() -> Void)?

    // 自動換動作時，碎念的機率。
    var chatterChance = 0.3

    // 跟著你打字 / 點擊：按了幾次（決定跳舞、打電腦顯示哪一格）、最後一次按的時間。
    private var inputCount = 0
    private var lastInputTime: Double = -10
    private var inputRecent: Bool { CACurrentMediaTime() - lastInputTime < 0.6 }
    // 正在跟著你的節奏跳舞（跟升等慶祝、自動模式的跳舞分開，那些照時間播）。
    private var syncDancing = false
    // 停手多久之後才停下來。
    private let syncLinger: Double = 1.5

    init(sprites: SpriteLibrary, speech: PetSpeech) {
        self.sprites = sprites
        self.speech = speech
        size = sprites.canvasSize
        window = PetWindow(size: size)
        view = PetView(frame: NSRect(origin: .zero, size: size), sprites: sprites)
        canopy = CanopyWindow(image: sprites.prop("parachute"), width: size.width)
        window.contentView = view
        window.isMovableByWindowBackground = false

        view.onDragBegan = { [weak self] in self?.dragBegan() }
        view.onDragMoved = { [weak self] origin in self?.dragMoved(to: origin) }
        view.onDragEnded = { [weak self] in self?.dragEnded() }
        view.onClick = { [weak self] in self?.clicked() }
        view.onDoubleClick = { [weak self] in self?.perform(.jump) }
    }

    func show(at point: NSPoint) {
        posX = point.x
        posY = point.y
        window.setFrameOrigin(point)
        window.orderFrontRegardless()
        setAction(.idle)
    }

    // MARK: - 指定動作（選單、雙擊會呼叫）

    func perform(_ newAction: PetAction) {
        guard canAct else { return }
        if newAction != .jump { heldAction = newAction }
        setAction(newAction)
        speech.say(newAction.rawValue)   // 你叫牠做的，牠一定回應
    }

    // 現在能不能接受指令（被抓著或在空中時不行）。
    var canAct: Bool { !isDragging && onGround && travel == .none }

    // 正在走去某處或做插播動作（吃東西、跳舞慶祝）。
    var isBusy: Bool { walkTarget != nil || isInterlude }

    // 視窗左下角的 x。
    var x: CGFloat { posX }

    // 走到視窗 x 座標為 x 的地方，到了面向 facing（1 右、-1 左），再呼叫 done。
    // 平常慢慢走，很遠才用跑的；hurry（開飯了）時遠一點就跑。
    func walk(to x: CGFloat, facing: CGFloat = 1, hurry: Bool = false, then done: @escaping () -> Void) {
        guard canAct else { return }
        if abs(x - posX) < 2 {
            posX = x
            direction = facing
            return done()
        }
        setAction(abs(x - posX) > (hurry ? 250 : 700) ? .run : .walk)
        direction = x > posX ? 1 : -1   // 要在 setAction 之後：開始走路時有機率隨機轉向
        walkTarget = x
        walkFacing = facing
        afterWalk = done
    }

    // 插播一個動作，做 duration 秒（沒給就用動作預設的長度），做完呼叫 done。
    func interlude(_ newAction: PetAction, duration: Double? = nil, then done: (() -> Void)? = nil) {
        guard canAct else { return }
        setAction(newAction)
        if let duration { actionDuration = duration }
        if newAction == .swing { swingCenter = posX }
        if newAction == .fly { beginFlight() }
        isInterlude = true
        afterInterlude = done
    }

    // 藏起來（⌥F）：視窗收掉、不說話、時間暫停，顯示回來時從原本的地方接著做。
    private(set) var concealed = false

    func setConcealed(_ on: Bool) {
        guard on != concealed else { return }
        if on, isDragging { dragEnded() }   // 視窗收掉後收不到放開滑鼠的事件
        concealed = on
        speech.muted = on
        if on {
            window.orderOut(nil)
            closeCanopies()
        } else if travel != .away {
            window.orderFrontRegardless()
        }
    }

    // 放下手邊的事（走去家具、打電腦、盪鞦韆）。在鞦韆上的話會掉回地面。
    func stopBusy() {
        guard isBusy else { return }
        setAction(.fall)
    }

    // 出門：往比較近的螢幕邊跑出去，跑出去之後呼叫 done。
    func leave(then done: (() -> Void)? = nil) {
        guard canAct, let visible = NSScreen.main?.visibleFrame else { return }
        setAction(.run)
        direction = posX - visible.minX < visible.maxX - size.width - posX ? -1 : 1
        travel = .leaving
        afterTravel = done
    }

    // 啟動時發現她還在冒險中：直接藏起來。
    func hideAway() {
        travel = .away
        window.orderOut(nil)
        closeCanopies()
    }

    private func closeCanopies() {
        canopy.setOpen(false, above: window.frame)
    }

    // 回家：從隨機一側的螢幕外跑進來，跑進畫面後呼叫 done。
    func arrive(then done: (() -> Void)? = nil) {
        guard travel == .away, let visible = NSScreen.main?.visibleFrame else { return }
        let fromLeft = Bool.random()
        posX = fromLeft ? visible.minX - size.width : visible.maxX
        posY = visible.minY
        vx = 0
        vy = 0
        setAction(.run)
        direction = fromLeft ? 1 : -1   // 要在 setAction 之後：開始跑步時有機率隨機轉向
        travel = .arriving
        afterTravel = done
        window.setFrameOrigin(NSPoint(x: posX, y: posY))
        window.orderFrontRegardless()
    }

    // MARK: - 跟著你打字 / 點擊（InputSync 呼叫）

    // 你按了一個鍵：在電腦桌前打電腦時，她的手跟著你的節奏敲；不在電腦桌前就跟著跳一步舞。
    func keyPressed() {
        if action == .typing {
            inputCount += 1
            lastInputTime = CACurrentMediaTime()
            return
        }
        danceStep()
    }

    // 你在螢幕某處點了一下滑鼠：不在電腦桌前就轉向游標那邊、跟著跳一步舞。
    func mouseClicked(at point: NSPoint) {
        guard action != .typing else { return }   // 打電腦時專心打字
        guard danceStep() else { return }
        let center = posX + size.width / 2
        if abs(point.x - center) > 4 { direction = point.x > center ? 1 : -1 }
    }

    // 每按一次跳一格：你按越快她跳越快，停手 1.5 秒後回去做原本的事。
    // 睡覺、被抓、在空中、出門、正在忙（走去吃飯、盪鞦韆、開飛機、升等跳舞…）時不打擾她。回傳有沒有跳。
    @discardableResult
    private func danceStep() -> Bool {
        if action == .dance, syncDancing {
            inputCount += 1
            actionDuration = actionTime + syncLinger
            return true
        }
        guard canAct, action != .sleep, !isBusy else { return false }
        setAction(.dance)
        isInterlude = true
        syncDancing = true
        inputCount = 0
        actionDuration = syncLinger
        speech.say("syncdance", chance: 0.25, force: false)
        return true
    }

    // 單擊：睡覺中就被叫醒，否則回應一句。
    private func clicked() {
        if action == .sleep, onGround {
            heldAction = .idle
            setAction(.idle)
            speech.say("wake")
        } else {
            speech.say("click")
        }
    }

    private func setAction(_ newAction: PetAction) {
        action = newAction
        isInterlude = false
        syncDancing = false
        afterInterlude = nil
        walkTarget = nil
        afterWalk = nil
        actionTime = 0
        let range = newAction.autoDuration
        actionDuration = Double.random(in: range)
        jumpLaunched = false
        landedAt = nil
        if newAction == .walk || newAction == .run, Double.random(in: 0...1) < 0.3 {
            direction = -direction   // 偶爾換個方向走
        }
    }

    // 自動模式：依權重隨機挑下一個動作（不重複上一個）。
    private func pickNextAction() {
        if let onOuting, Double.random(in: 0..<1) < outingChance, onOuting() { return }
        let candidates = PetAction.selectable.filter { $0 != action }
        let total = candidates.reduce(0) { $0 + $1.autoWeight }
        var roll = Int.random(in: 0..<total)
        for candidate in candidates {
            roll -= candidate.autoWeight
            if roll < 0 {
                setAction(candidate)
                speech.say(candidate.rawValue, chance: chatterChance, force: false)
                return
            }
        }
    }

    // 跳躍 / 掉落 / 插播動作結束後要做什麼。
    private func finishAirAction() {
        if autoMode { setAction(.idle) } else { setAction(heldAction) }
    }

    // MARK: - 每一幀

    private var ground: CGFloat { NSScreen.main?.visibleFrame.minY ?? 0 }
    private var onGround: Bool { posY <= ground && vy <= 0 }

    func tick(dt: Double) {
        guard let visible = NSScreen.main?.visibleFrame, travel != .away, !concealed else { return }
        actionTime += dt
        let t = CGFloat(dt)
        let minX = visible.minX
        let maxX = visible.maxX - size.width

        if isDragging {
            // 位置由 dragMoved 直接決定，這裡什麼都不做。
        } else if action == .swing {
            updateSwing()
        } else if action == .fly {
            updateFlight(t: t, visible: visible)
        } else if !onGround {
            // 在空中：從夠高的地方往下掉就開傘。
            if action == .fall, vy < 0, posY - ground > visible.height * tuning.parachuteHeight {
                setAction(.parachute)
                speech.say("parachute")
            }
            if action == .parachute {
                // 開傘：速度慢慢收斂到固定的下降速度，左右也被空氣拖慢
                let k = min(1, tuning.parachuteDrag * t)
                vy += (-tuning.parachuteSpeed - vy) * k
                vx -= vx * k
                // 傘在寵物頭上，別讓它超出螢幕頂端
                posY = min(posY, visible.maxY - size.height - canopy.frame.height)
            } else {
                // 受重力影響，撞到左右邊界就反彈。
                vy -= tuning.gravity * t
            }
            posX += vx * t
            posY += vy * t
            if posX < minX { posX = minX; vx = abs(vx) * 0.5 }
            if posX > maxX { posX = maxX; vx = -abs(vx) * 0.5 }
            if posY > visible.maxY - size.height { posY = visible.maxY - size.height; vy = min(vy, 0) }
            if vx != 0 { direction = vx > 0 ? 1 : -1 }
            if posY <= ground { land() }
        } else {
            posY = ground   // 換螢幕或 Dock 變高時，貼回地面
            updateGroundAction(t: t, minX: minX, maxX: maxX)
        }

        view.facingLeft = direction < 0
        let frame = currentFrame()
        view.show(action, frame: frame)
        // 砍中的那一格：通知 boss 被砍
        if action == .attack {
            if frame == Self.attackImpactFrame, lastAttackFrame != frame { onAttackHit?() }
            lastAttackFrame = frame
        }
        window.setFrameOrigin(NSPoint(x: posX, y: posY))
        canopy.setOpen(action == .parachute, above: window.frame)
        speech.follow(window.frame)
    }

    private func updateGroundAction(t: CGFloat, minX: CGFloat, maxX: CGFloat) {
        if travel != .none { return updateTravel(t: t, minX: minX, maxX: maxX) }
        if let target = walkTarget {
            let speed = action == .run ? tuning.runSpeed : tuning.walkSpeed
            posX += speed * direction * t
            if (target - posX) * direction <= 0 {
                posX = target
                direction = walkFacing
                let done = afterWalk
                walkTarget = nil
                afterWalk = nil
                done?()
            }
            return
        }
        switch action {
        case .walk:
            posX += tuning.walkSpeed * direction * t
        case .run:
            posX += tuning.runSpeed * direction * t
        case .jump:
            if let landedAt {
                // 落地緩衝結束
                if actionTime - landedAt >= tuning.landTime { finishAirAction() }
            } else if !jumpLaunched, actionTime >= tuning.crouchTime {
                // 蹲完了，起跳！
                jumpLaunched = true
                vy = tuning.jumpVelocity
                vx = tuning.jumpForward * direction
                posY += 1   // 離開地面，下一幀就會進入空中狀態
            }
            return
        case .fall:
            finishAirAction()
            runAfterLanding()
            return
        default:
            break
        }

        // 走到邊界就轉向。
        if posX >= maxX { posX = maxX; direction = -1 }
        if posX <= minX { posX = minX; direction = 1 }

        if isInterlude, actionTime >= actionDuration {
            let done = afterInterlude
            finishAirAction()   // 回到自動模式，或你指定的動作
            done?()
        } else if autoMode, actionTime >= actionDuration {
            pickNextAction()
        }
    }

    // 盪鞦韆：以 swingCenter 為中心沿著圓弧擺，開頭和結尾各花 2 秒慢慢加大 / 減小，最後停回地面。
    private func updateSwing() {
        let ramp = min(1, actionTime / 2, max(0, actionDuration - actionTime) / 2)
        let angle = tuning.swingAngle * CGFloat(ramp * sin(2 * .pi * actionTime / tuning.swingPeriod))
        posX = swingCenter + tuning.swingLength * sin(angle)
        posY = ground + tuning.swingLength * (1 - cos(angle))
        direction = 1
        if actionTime >= actionDuration {
            posX = swingCenter
            posY = ground
            let done = afterInterlude
            finishAirAction()
            done?()
        }
    }

    private func beginFlight() {
        flightHome = posX
        flightPhase = .taxi
        flightSpeed = 0
        flightPitch = 0
        // 飛機停著時機頭朝右；右邊空間不夠就往左滑行起飛
        let right = (NSScreen.main?.visibleFrame.maxX ?? .infinity) - size.width
        direction = right - posX > 400 ? 1 : -1
    }

    private func updateFlight(t: CGFloat, visible: NSRect) {
        // 掉頭的位置可以稍微超出螢幕，像飛機真的繞出去再回來
        let left = visible.minX - 120
        let right = visible.maxX - size.width + 120
        let oldY = posY
        switch flightPhase {
        case .taxi:
            flightSpeed = min(tuning.flySpeed, flightSpeed + 160 * t)
            posX += flightSpeed * direction * t
            posY = ground
            if flightSpeed >= 140 { flightPhase = .air }   // 速度夠了就拉起來
        case .air:
            flightSpeed = tuning.flySpeed
            posX += flightSpeed * direction * t
            if posX > right { direction = -1 }
            if posX < left { direction = 1 }
            let cruise = ground + visible.height * tuning.flyAltitude + 50 * CGFloat(sin(actionTime * 0.9))
            posY += min(max((cruise - posY) * 1.5, -120), 120) * t
            // 時間到了，等飛機朝右、離停機位夠遠，就開始進場
            let distance = flightHome - posX
            if actionTime >= actionDuration, direction > 0, distance >= min(350, flightHome - left - 5) {
                flightPhase = .landing(distance: distance, altitude: posY - ground)
                speech.say("landing", chance: 0.6, force: false)
            }
        case .landing(let distance0, let altitude0):
            // 沿直線滑下來，離停機位 90 點時著地，再減速滑進停機位
            let distance = flightHome - posX
            let glide = max(0, (distance - 90) / max(1, distance0 - 90))
            posY = ground + altitude0 * glide
            flightSpeed = distance < 90 ? 30 + 170 * distance / 90 : tuning.flySpeed
            posX += flightSpeed * t
            if posX >= flightHome {
                posX = flightHome
                posY = ground
                flightPitch = 0
                let done = afterInterlude
                finishAirAction()
                done?()
                return
            }
        }
        // 機頭跟著爬升 / 下降的方向抬起或壓低，慢慢跟上，不要一頓一頓的
        let climb = t > 0 ? (posY - oldY) / t : 0
        let target = min(max(atan2(climb, max(flightSpeed, 1)), -0.18), 0.18)
        flightPitch += (target - flightPitch) * min(1, 4 * t)
    }

    // MARK: - 地下城：砍 boss

    // 開打：原地拿劍，面向 boss（facing 1 右、-1 左）。
    func startBattle(facing: CGFloat) {
        vx = 0
        vy = 0
        posY = ground
        setAction(.attack)
        direction = facing
        travel = .fighting
        lastAttackFrame = -1
        if !concealed { window.orderFrontRegardless() }
    }

    // 你點了 boss：馬上砍中一刀（直接跳到砍中的那一格），之後照常繼續揮。
    func quickSlash() {
        guard travel == .fighting, action == .attack else { return }
        let fps = sprites.info(.attack).fps
        actionTime = Double(Self.attackImpactFrame) / max(fps, 1) + 0.001
        lastAttackFrame = Self.attackImpactFrame   // 這一刀由點擊算，不要再自動多算一次
    }

    // 打完了：回到平常的樣子（之後要跳舞慶祝或坐下來沮喪，由呼叫的人決定）。
    func endBattle() {
        guard travel == .fighting else { return }
        travel = .none
        finishAirAction()
    }

    // 出門 / 回家途中：一直跑，不受螢幕邊界限制。打 boss 時站在原地。
    private func updateTravel(t: CGFloat, minX: CGFloat, maxX: CGFloat) {
        if travel == .fighting { return }
        posX += tuning.runSpeed * direction * t
        switch travel {
        case .leaving where posX < minX - size.width || posX > maxX + size.width:
            travel = .away
            window.orderOut(nil)
            finishTravel()
        case .arriving where posX >= minX + 30 && posX <= maxX - 30:
            travel = .none
            finishAirAction()
            finishTravel()
        default:
            break
        }
    }

    private func finishTravel() {
        let done = afterTravel
        afterTravel = nil
        done?()
    }

    private func land() {
        posY = ground
        vy = 0
        vx = 0
        if action == .jump {
            landedAt = actionTime   // 播一下落地格，再由 updateGroundAction 結束
        } else {
            if wasThrown || action == .parachute { speech.say("landed") }
            finishAirAction()
            runAfterLanding()
        }
        wasThrown = false
    }

    // 落地了：有被放到家具上的話，現在去用它。
    private func runAfterLanding() {
        let done = afterLanding
        afterLanding = nil
        done?()
    }

    // 目前該顯示第幾格。
    private func currentFrame() -> Int {
        let info = sprites.info(action)
        let last = max(info.frames - 1, 0)
        // 跟著你打字 / 點擊：每按一次換一格
        if (action == .dance && syncDancing) || (action == .typing && inputRecent) {
            return inputCount % max(info.frames, 1)
        }
        if action == .jump {
            // 跳躍的格子由物理狀態決定：0 蹲、1 上升、2 下降、3 落地
            if !jumpLaunched { return 0 }
            if landedAt != nil { return min(3, last) }
            return min(vy > 0 ? 1 : 2, last)
        }
        let f = Int(actionTime * info.fps)
        return info.loop ? f % max(info.frames, 1) : min(f, last)
    }

    // MARK: - 拖曳與甩出

    private func dragBegan() {
        guard travel == .none else { return }   // 出門 / 回家途中抓不住
        isDragging = true
        vx = 0
        vy = 0
        dragSamples = []
        afterLanding = nil
        setAction(.dragged)
        speech.say("dragged")
    }

    private func dragMoved(to origin: NSPoint) {
        guard isDragging else { return }
        posX = origin.x
        posY = origin.y
        let now = CACurrentMediaTime()
        dragSamples.append((now, origin))
        dragSamples.removeAll { now - $0.time > 0.1 }   // 只看最近 0.1 秒
        onDragHover?(NSRect(origin: origin, size: size))
    }

    private func dragEnded() {
        guard isDragging else { return }
        isDragging = false
        // 用最近 0.1 秒的位移估算放手時的速度。
        if let first = dragSamples.first, let last = dragSamples.last, last.time - first.time > 0.01 {
            let dt = CGFloat(last.time - first.time)
            let limit = tuning.maxThrowSpeed
            vx = min(max((last.point.x - first.point.x) / dt, -limit), limit)
            vy = min(max((last.point.y - first.point.y) / dt, -limit), limit)
        }
        if posY < ground { posY = ground }
        onDragHover?(nil)
        if let action = onDrop?(NSRect(x: posX, y: posY, width: size.width, height: size.height)) {
            // 放在家具上：不甩出去，直直落下，落地後去用它
            vx = 0
            vy = 0
            wasThrown = false
            afterLanding = action
            setAction(.fall)
            return
        }
        // 甩得夠用力才算「被丟出去」
        wasThrown = hypot(vx, vy) > 500
        if wasThrown { speech.say("thrown") }
        setAction(.fall)
    }
}
