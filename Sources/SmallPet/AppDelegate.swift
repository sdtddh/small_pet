// AppDelegate.swift —— 把所有東西組起來：寵物、衣櫃、選單、動畫計時器。
import AppKit

// @MainActor：宣告這個類別的所有程式都在主執行緒執行，
// 因為 AppKit 的 UI 操作都必須在主執行緒。這也消除 Swift 6 的並行性警告。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var sprites: SpriteLibrary!
    private var pet: Pet!
    private var wardrobe: Wardrobe!
    private var wardrobeWindow: WardrobeWindowController!
    private let stats = PetStats()
    private var statusWindow: StatusWindowController!
    private var scenery: Scenery!
    private let calculator = CalculatorWindowController()
    private var inputSync: InputSync!
    private var boss: BossWindow?
    // 試打 boss：不算冒險次數、不存檔、不給戰利品，打 15 秒看看效果。
    private var trial: (dungeon: Dungeon, startedAt: Date, endsAt: Date)?
    private static let trialSeconds: TimeInterval = 15

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()

    // App 啟動完成後呼叫。
    func applicationDidFinishLaunching(_ notification: Notification) {
        sprites = SpriteLibrary()
        wardrobe = Wardrobe(sprites: sprites, stats: stats)
        stats.outfitBonus = wardrobe.powerBonus
        wardrobeWindow = WardrobeWindowController(wardrobe: wardrobe)
        inputSync = InputSync()   // 先建好：狀態視窗的「跟著我打字」開關和「權限」頁要用（onKey / onClick 等寵物建好再接）
        statusWindow = StatusWindowController(
            stats: stats, wardrobe: wardrobe, inputSync: inputSync,
            onFeed: { [weak self] in self?.feed() },
            onSnack: { [weak self] in self?.feed(snack: true) },
            onStartRun: { [weak self] dungeon in self?.startRun(dungeon) },
            onTrial: { [weak self] dungeon in self?.startTrial(dungeon) }
        )

        pet = Pet(sprites: sprites, speech: PetSpeech(resources: sprites.root))
        pet.view.setOutfits(wardrobe.equipped)
        pet.view.setLook(wardrobe.look)
        wardrobe.onChange = { [weak self] in
            guard let self else { return }
            self.pet.view.setOutfits(self.wardrobe.equipped)
            self.pet.view.setLook(self.wardrobe.look)
            self.stats.outfitBonus = self.wardrobe.powerBonus
            if self.pet.travel == .none { self.pet.speech.say("wardrobe") }
        }
        pet.view.onRightClick = { [weak self] event in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.makeMenu(), with: event, for: self.pet.view)
        }

        // 放在主螢幕左下角。
        let visible = NSScreen.main?.visibleFrame ?? .zero
        pet.show(at: NSPoint(x: visible.minX + 40, y: visible.minY))
        scenery = Scenery(sprites: sprites)
        scenery.restore(below: pet.window)
        setUpPropGestures()
        HotKey.register { [weak self] in self?.toggleEverything() }
        pet.onOuting = { [weak self] in self?.goOut() ?? false }
        pet.onDragHover = { [weak self] frame in self?.highlightProp(under: frame) }
        pet.onDrop = { [weak self] frame in self?.dropAction(at: frame) }
        pet.speech.follow(pet.window.frame)
        pet.onAttackHit = { [weak self] in self?.bossHit() }
        if let run = stats.run, let dungeon = Dungeon.find(run.dungeonID) {
            beginBattle(dungeon)   // 上次關掉 App 時她還在冒險：接著打，時間到了在動畫迴圈裡結算
        } else {
            pet.speech.greet()
        }

        inputSync.onKey = { [weak self] in
            guard let self, !self.pet.concealed else { return }
            self.pet.keyPressed()
        }
        inputSync.onClick = { [weak self] point in
            guard let self, !self.pet.concealed else { return }
            self.pet.mouseClicked(at: point)
        }

        setupStatusItem()
        startAnimating()
    }

    // MARK: - 選單

    // 選單列（右上角）圖示。每次打開前由 menuNeedsUpdate 重建，勾選狀態才會正確。
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐾"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        makeMenu().items.forEach { item in
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }

    // 右鍵和選單列共用同一份選單。
    // 換角色會重開 App（等級、背包、衣櫃都是各角色分開的）。
    @objc private func switchCharacter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Character.switchTo(id)
    }

    // 右鍵選單，由上往下：狀態、衣櫃、動作、角色、家具；最後是隱藏全部、結束。
    // 「跟著我打字 / 點擊」的開關在狀態視窗的「狀態」頁，需要的權限在「權限」頁；試打 boss 在「地下城」頁。
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "狀態 / 地下城…（Lv.\(stats.level)）", action: #selector(openStatus), keyEquivalent: "")
        statusMenuItem.target = self
        menu.addItem(statusMenuItem)

        let wardrobeItem = NSMenuItem(title: "衣櫃…", action: #selector(openWardrobe), keyEquivalent: "")
        wardrobeItem.target = self
        menu.addItem(wardrobeItem)

        // 動作：
        //   說句話——只是讓她說一句，不會改變正在做的動作，也不影響自動行動
        //   自動行動——她自己隨機換動作
        //   其他——指定一個動作（跳躍只跳一次）
        let actionMenu = NSMenu()
        let talkItem = NSMenuItem(title: "說句話", action: #selector(talk), keyEquivalent: "")
        talkItem.target = self
        actionMenu.addItem(talkItem)
        actionMenu.addItem(.separator())
        let autoItem = NSMenuItem(title: "自動行動", action: #selector(toggleAutoMode), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = pet.autoMode ? .on : .off
        actionMenu.addItem(autoItem)
        actionMenu.addItem(.separator())
        for action in PetAction.selectable {
            let item = NSMenuItem(title: action.displayName, action: #selector(performAction(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue
            item.target = self
            item.state = pet.action == action ? .on : .off
            actionMenu.addItem(item)
        }
        // 沒開自動行動時，標題直接告訴你她被鎖定在哪個動作
        let actionTitle = pet.lockedAction.map { "行動（鎖定為：\($0.displayName)）" } ?? "動作"
        let actionItem = NSMenuItem(title: actionTitle, action: nil, keyEquivalent: "")
        actionItem.submenu = actionMenu
        menu.addItem(actionItem)

        let characterMenu = NSMenu()
        for character in Character.all {
            let item = NSMenuItem(title: character.name, action: #selector(switchCharacter(_:)), keyEquivalent: "")
            item.representedObject = character.id
            item.target = self
            item.state = Character.current == character.id ? .on : .off
            characterMenu.addItem(item)
        }
        let characterItem = NSMenuItem(title: "角色", action: nil, keyEquivalent: "")
        characterItem.submenu = characterMenu
        menu.addItem(characterItem)

        let sceneryMenu = NSMenu()
        let allItem = NSMenuItem(title: scenery.pinned ? "隱藏家具" : "顯示家具", action: #selector(toggleScenery), keyEquivalent: "")
        allItem.target = self
        sceneryMenu.addItem(allItem)
        sceneryMenu.addItem(.separator())
        for prop in scenery.all {
            let item = NSMenuItem(title: prop.title, action: #selector(toggleProp(_:)), keyEquivalent: "")
            item.representedObject = prop
            item.target = self
            item.state = scenery.isShown(prop) ? .on : .off
            sceneryMenu.addItem(item)
        }
        let sceneryItem = NSMenuItem(title: "家具與佈景", action: nil, keyEquivalent: "")
        sceneryItem.submenu = sceneryMenu
        menu.addItem(sceneryItem)

        if let run = stats.run, let dungeon = Dungeon.find(run.dungeonID) {
            let minutes = max(1, Int(ceil(run.endsAt.timeIntervalSinceNow / 60)))
            menu.addItem(NSMenuItem(title: "戰鬥中：\(dungeon.name)的\(dungeon.bossName)（約 \(minutes) 分鐘後分出勝負）", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let hideItem = NSMenuItem(title: pet.concealed ? "顯示全部" : "隱藏全部", action: #selector(toggleEverything), keyEquivalent: "f")
        hideItem.keyEquivalentModifierMask = [.option]
        hideItem.target = self
        menu.addItem(hideItem)

        let quitItem = NSMenuItem(title: "結束", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = PetAction(rawValue: raw) else { return }
        setEverythingConcealed(false)
        guard pet.canAct else { return }
        // 指定了動作就一直做這個，要再讓她自己換就勾回「自動行動」。
        // 跳躍例外：只跳一次，跳完回到原本的狀態（自動行動照舊）
        if action != .jump { pet.autoMode = false }
        pet.perform(action)
    }

    @objc private func toggleAutoMode() {
        pet.autoMode.toggle()
    }

    @objc private func talk() {
        setEverythingConcealed(false)
        pet.speech.say("click")
    }

    // ⌥F：寵物和家具全部藏起來 / 顯示回來。不記住，下次開 App 一定看得到她。
    @objc private func toggleEverything() {
        setEverythingConcealed(!pet.concealed)
    }

    private func setEverythingConcealed(_ on: Bool) {
        guard on != pet.concealed else { return }
        pet.setConcealed(on)
        scenery.setConcealed(on, below: pet.window)
        if let boss {
            if on { boss.orderOut(nil) } else { boss.order(.below, relativeTo: pet.window.windowNumber) }
        }
    }

    @objc private func toggleScenery() {
        scenery.toggle(below: pet.window)
        leaveHiddenProps()
    }

    @objc private func toggleProp(_ sender: NSMenuItem) {
        guard let prop = sender.representedObject as? Prop else { return }
        scenery.toggle(prop, below: pet.window)
        leaveHiddenProps()
    }

    // 按住家具往下拉：收起來；往上拉：開小工具——電腦桌是計算機，餐桌是叫她來吃飯（算一次餵食）。
    private func setUpPropGestures() {
        for prop in scenery.all {
            prop.window.onSwipeDown = { [weak self, unowned prop] in
                guard let self else { return }
                self.scenery.hide(prop, below: self.pet.window)
            }
        }
        scenery.computer.window.onSwipeUp = { [weak self] in
            guard let self else { return }
            self.calculator.show(above: self.scenery.computer.window.frame)
        }
        scenery.dining.window.onSwipeUp = { [weak self] in
            guard let self, self.pet.travel == .none else { return }   // 出門冒險 / 打 boss 時不能吃
            self.feed()
        }
    }

    // 她正在用的電腦桌、鞦韆或飛機被隱藏了（開飛機時會直接掉下來，夠高就開傘）：不用了，家具才會馬上收起來。
    // 餐桌不算：吃飯時餐桌本來就會暫時出現，吃完才收。
    private func leaveHiddenProps() {
        if [scenery.computer, scenery.swing, scenery.plane].contains(where: { $0.inUse && !scenery.isShown($0) }) {
            pet.stopBusy()
        }
    }

    // 餵食：餐桌擺上胡蘿蔔 → 她走過去坐下吃 3 秒 → 吃完才顯示拿到的 XP；升等的話再跳一段舞慶祝。
    // 中途被抓走的話 XP 照拿，只是不會說出來（由 checkMeal 收拾餐桌）。
    // - snack：true 時吃背包裡的零食，不佔今天的餵食次數。
    private func feed(snack: Bool = false) {
        setEverythingConcealed(false)
        guard pet.canAct, !scenery.mealInProgress else { return }
        guard case let .fed(xp, newLevel) = snack ? stats.eatSnack() : stats.feed() else {
            if !snack { pet.speech.say("full") }
            return
        }
        scenery.releaseAll(below: pet.window)
        scenery.use(scenery.dining, below: pet.window)
        pet.speech.say("meal")
        pet.walk(to: scenery.dining.x, hurry: true) { [weak self] in
            guard let self else { return }
            self.pet.speech.say("eat")
            self.pet.interlude(.eat) { [weak self] in
                self?.finishMeal(xp: xp, newLevel: newLevel)
            }
        }
    }

    private func finishMeal(xp: Int, newLevel: Int?) {
        scenery.release(scenery.dining, below: pet.window)
        if let newLevel {
            pet.speech.sayText("升到 Lv.\(newLevel) 了！戰鬥力 \(stats.power) ✨")
            pet.interlude(.dance)
        } else {
            pet.speech.sayText("+\(xp) XP！（\(stats.xp)/\(stats.xpNeeded)）")
        }
    }

    // 動畫迴圈每一幀呼叫：吃飯 / 打電腦 / 盪鞦韆途中被抓走或改做別的事，就把家具收拾好。
    private func checkProps() {
        if !pet.isBusy { scenery.releaseAll(below: pet.window) }
        scenery.updateSwing(riderOrigin: pet.action == .swing ? pet.window.frame.origin : nil)
        scenery.updatePlane(rider: pet.action == .fly ? pet.window : nil,
                            facingLeft: pet.facingLeft, pitch: pet.flightPitch, time: CACurrentMediaTime())
    }

    // MARK: - 自己找事做

    // 自動模式換動作時偶爾呼叫：去角落坐好一陣子；電腦桌、鞦韆、飛機有擺出來的話，也可能過去。
    // 回傳 true 代表已經出發了。
    private func goOut() -> Bool {
        var choices = ["corner", "corner"]
        if scenery.isShown(scenery.computer) { choices.append("computer") }
        if scenery.isShown(scenery.swing) { choices.append("swing") }
        if scenery.isShown(scenery.plane) { choices.append("plane") }
        switch choices.randomElement() {
        case "computer": visit(scenery.computer, doing: .typing)
        case "swing": visit(scenery.swing, doing: .swing)
        case "plane": visit(scenery.plane, doing: .fly)
        default: restInCorner()
        }
        return true
    }

    // 走到比較近的螢幕角落（偶爾去遠的那邊），面向畫面坐著發呆或打瞌睡，待上一兩分鐘。
    private func restInCorner() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let width = pet.window.frame.width
        let left = visible.minX
        let right = visible.maxX - width
        var toLeft = pet.x - left < right - pet.x
        if Double.random(in: 0..<1) < 0.3 { toLeft.toggle() }
        pet.walk(to: toLeft ? left : right, facing: toLeft ? 1 : -1) { [weak self] in
            guard let self else { return }
            let nap = Double.random(in: 0..<1) < 0.35
            self.pet.speech.say(nap ? "sleep" : "corner", chance: self.pet.chatterChance, force: false)
            self.pet.interlude(nap ? .sleep : .sit, duration: .random(in: 40...120))
        }
    }

    // MARK: - 拖到家具上

    private var highlightedProp: Prop?

    // 她在 frame（她的視窗）的位置下面是哪件家具：用她身體中間、靠腳的那一點判斷，
    // 家具範圍往上多算一點，放在家具上方一點點也算。只看有擺出來、沒在用的家具。
    private func prop(under frame: NSRect) -> Prop? {
        let point = NSPoint(x: frame.midX, y: frame.minY + 20)
        return scenery.all.first { prop in
            scenery.isShown(prop) && !prop.inUse && prop.window.isVisible
                && prop.window.frame.insetBy(dx: -6, dy: -24).contains(point)
        }
    }

    private func highlightProp(under frame: NSRect?) {
        let target = frame.flatMap { prop(under: $0) }
        guard target !== highlightedProp else { return }
        highlightedProp?.window.setHighlighted(false)
        target?.window.setHighlighted(true)
        highlightedProp = target
    }

    // 放手時：在家具上的話，回傳落地後要做的事（吃飯、打電腦、盪鞦韆、開飛機）。
    private func dropAction(at frame: NSRect) -> (() -> Void)? {
        guard !pet.concealed, !scenery.mealInProgress, let prop = prop(under: frame) else { return nil }
        return { [weak self] in
            guard let self else { return }
            if prop === self.scenery.dining {
                self.feed()   // 今天餵滿了的話她會說吃不下
            } else if prop === self.scenery.computer {
                self.visit(prop, doing: .typing)
            } else if prop === self.scenery.swing {
                self.visit(prop, doing: .swing)
            } else if prop === self.scenery.plane {
                self.visit(prop, doing: .fly)
            }
        }
    }

    // 走到家具旁邊做事（打電腦、盪鞦韆），時間長短用動作預設的。
    private func visit(_ prop: Prop, doing action: PetAction) {
        scenery.releaseAll(below: pet.window)
        scenery.use(prop, below: pet.window)
        pet.walk(to: prop.x) { [weak self] in
            guard let self else { return }
            self.pet.speech.say(action.rawValue, chance: 0.6, force: false)
            self.pet.interlude(action)
        }
    }

    // MARK: - 地下城

    private func startRun(_ dungeon: Dungeon) {
        setEverythingConcealed(false)
        guard pet.canAct else { return }
        switch stats.startRun(dungeon) {
        case .noRunsLeft?:
            pet.speech.say("tired")
        case .busy?:
            break
        case nil:
            pet.speech.sayText("出發去\(dungeon.name)！遇到了\(dungeon.bossName)，看劍！⚔️")
            beginBattle(dungeon)
        }
    }

    // 在她旁邊叫出這個地下城的 boss，讓她面向 boss 開始砍。右邊放得下就放右邊，不然放左邊。
    private func beginBattle(_ dungeon: Dungeon) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        scenery.releaseAll(below: pet.window)
        let petWidth = pet.window.frame.width
        let bossWidth = BossWindow.artSize.width
        let reach: CGFloat = 92          // 劍尖大概在她視窗左邊算起 92 點的地方
        var x = pet.x
        var bossX = x + reach
        var facing: CGFloat = 1
        if bossX + bossWidth > visible.maxX {
            bossX = x + petWidth - reach - bossWidth
            facing = -1
            if bossX < visible.minX {   // 左邊也放不下：把她挪一下
                bossX = visible.minX
                x = bossX + bossWidth + reach - petWidth
            }
        }
        if x != pet.x { pet.show(at: NSPoint(x: x, y: visible.minY)) }
        let window = BossWindow(dungeon: dungeon, sprites: sprites, facingLeft: facing > 0)
        window.onClick = { [weak self] in self?.bossClicked() }
        window.setFrameOrigin(NSPoint(x: bossX, y: visible.minY))
        if !pet.concealed { window.order(.below, relativeTo: pet.window.windowNumber) }
        boss?.orderOut(nil)
        boss = window
        pet.startBattle(facing: facing)
    }

    // 試打：跟真的冒險一樣叫出 boss 開打，15 秒後依現在的戰鬥力算一次勝負，但什麼都不記錄。
    private func startTrial(_ dungeon: Dungeon) {
        setEverythingConcealed(false)
        guard pet.canAct, stats.run == nil, trial == nil else { return }
        let now = Date()
        trial = (dungeon, now, now.addingTimeInterval(Self.trialSeconds))
        pet.speech.sayText("試打\(dungeon.bossName)！看劍！⚔️")
        beginBattle(dungeon)
    }

    // 你點了 boss：她馬上多砍一刀，冒險時間少 1 秒（試打的話是試打時間少 1 秒）。
    private func bossClicked() {
        guard pet.travel == .fighting, let boss else { return }
        pet.quickSlash()
        bossHit()
        if let t = trial {
            trial = (t.dungeon, t.startedAt, t.endsAt.addingTimeInterval(-1))
        } else {
            stats.shortenRun(by: 1)
        }
        boss.showTimeBonus("⏱ -1 秒")
    }

    // 她砍中一刀：傷害大概是戰鬥力上下浮動。
    private func bossHit() {
        let base = max(1, stats.power)
        boss?.hit(damage: Int.random(in: max(1, base * 3 / 4)...(base * 5 / 4 + 1)))
    }

    // 每一幀：血條跟著冒險進度往下掉。
    private func updateBoss() {
        guard let boss else { return }
        if let trial {
            let total = trial.endsAt.timeIntervalSince(trial.startedAt)
            boss.update(progress: 1 - trial.endsAt.timeIntervalSinceNow / total, time: CACurrentMediaTime())
            return
        }
        guard let run = stats.run, let dungeon = Dungeon.find(run.dungeonID) else { return }
        let remaining = run.endsAt.timeIntervalSinceNow
        boss.update(progress: 1 - remaining / dungeon.duration, time: CACurrentMediaTime())
    }

    // 試打時間到：用跟真的冒險一樣的成功率算勝負，只講結果，不給東西。
    private func checkTrial() {
        guard let trial, pet.travel == .fighting, Date() >= trial.endsAt else { return }
        self.trial = nil
        let won = Double.random(in: 0..<1) < trial.dungeon.successChance(power: stats.power)
        let finishing = boss
        boss = nil
        pet.endBattle()
        if won {
            pet.speech.sayText("試打成功！打倒\(trial.dungeon.bossName)了～")
            pet.interlude(.dance)
        } else {
            pet.speech.sayText("試打輸了…\(trial.dungeon.bossName)好強")
            pet.interlude(.sit, duration: 6)
        }
        finishing?.finish(won: won) { _ = finishing }
    }

    // 動畫迴圈每一幀呼叫：她在外面、時間也到了，就結算並讓她跑回來報告。
    private func checkRun() {
        if trial != nil { return checkTrial() }
        guard pet.travel == .fighting, stats.runFinished,
              let result = stats.finishRun(outfits: sprites.manifest.outfits) else { return }
        let won = result.reward != nil
        let finishing = boss
        boss = nil
        pet.endBattle()
        switch result.reward {
        case .outfit(_, let name)?:
            pet.speech.sayText("打倒\(result.dungeon.bossName)了！拿到「\(name)」✨")
            pet.interlude(.dance)
        case .snack?:
            pet.speech.sayText("打倒\(result.dungeon.bossName)了！撿到零食～")
            pet.interlude(.dance)
        case nil:
            pet.speech.say("lose")
            pet.interlude(.sit, duration: 6)
        }
        if let finishing {
            finishing.finish(won: won) { _ = finishing }   // 動畫做完才放掉視窗
        }
    }

    @objc private func openStatus() {
        statusWindow.show()
    }

    @objc private func openWardrobe() {
        wardrobeWindow.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 動畫迴圈

    private func startAnimating() {
        // 約 60 FPS 更新一次。用實際經過的時間計算，就算掉幀速度也一致。
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = CACurrentMediaTime()
                let dt = min(now - self.lastTick, 1.0 / 20.0)   // 避免卡頓後瞬移
                self.lastTick = now
                guard !self.pet.concealed else { return }   // 藏起來時暫停；冒險時間到了等顯示回來才回家
                self.pet.tick(dt: dt)
                self.updateBoss()
                self.checkRun()
                self.checkProps()
            }
        }
        // .common 模式：打開選單、拖曳時動畫也不會停。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
