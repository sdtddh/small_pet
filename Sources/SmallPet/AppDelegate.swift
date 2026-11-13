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
    private var inputSync: InputSync!

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()

    // App 啟動完成後呼叫。
    func applicationDidFinishLaunching(_ notification: Notification) {
        sprites = SpriteLibrary()
        wardrobe = Wardrobe(sprites: sprites, stats: stats)
        stats.outfitBonus = wardrobe.powerBonus
        wardrobeWindow = WardrobeWindowController(wardrobe: wardrobe)
        statusWindow = StatusWindowController(
            stats: stats, wardrobe: wardrobe,
            onFeed: { [weak self] in self?.feed() },
            onSnack: { [weak self] in self?.feed(snack: true) },
            onStartRun: { [weak self] dungeon in self?.startRun(dungeon) }
        )

        pet = Pet(sprites: sprites, speech: PetSpeech(resources: sprites.root))
        pet.view.setOutfits(wardrobe.equipped)
        pet.view.setLook(wardrobe.look)
        pet.holdsUmbrella = wardrobe.equipped["hand"] == "umbrella"
        wardrobe.onChange = { [weak self] in
            guard let self else { return }
            self.pet.view.setOutfits(self.wardrobe.equipped)
            self.pet.view.setLook(self.wardrobe.look)
            self.pet.holdsUmbrella = self.wardrobe.equipped["hand"] == "umbrella"
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
        HotKey.register { [weak self] in self?.toggleEverything() }
        pet.onOuting = { [weak self] in self?.goOut() ?? false }
        pet.speech.follow(pet.window.frame)
        if stats.run != nil {
            pet.hideAway()   // 上次關掉 App 時她還在冒險，時間到了會在動畫迴圈裡回家
        } else {
            pet.speech.greet()
        }

        inputSync = InputSync()
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

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let actionMenu = NSMenu()
        for action in PetAction.selectable {
            let item = NSMenuItem(title: action.displayName, action: #selector(performAction(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue
            item.target = self
            item.state = pet.action == action ? .on : .off
            actionMenu.addItem(item)
        }
        let actionItem = NSMenuItem(title: "動作", action: nil, keyEquivalent: "")
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

        let hideItem = NSMenuItem(title: pet.concealed ? "顯示全部" : "隱藏全部", action: #selector(toggleEverything), keyEquivalent: "f")
        hideItem.keyEquivalentModifierMask = [.option]
        hideItem.target = self
        menu.addItem(hideItem)

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

        let autoItem = NSMenuItem(title: "自動行動", action: #selector(toggleAutoMode), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = pet.autoMode ? .on : .off
        menu.addItem(autoItem)

        let syncItem = NSMenuItem(title: "跟著我打字 / 點擊", action: #selector(toggleInputSync), keyEquivalent: "")
        syncItem.target = self
        syncItem.state = inputSync.enabled ? .on : .off
        menu.addItem(syncItem)
        if inputSync.enabled, !inputSync.keyboardAllowed {
            // 還沒給鍵盤權限：點了打開設定頁
            let permItem = NSMenuItem(title: "　⚠︎ 鍵盤需要「輔助使用」權限…", action: #selector(openAccessibility), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        let talkItem = NSMenuItem(title: "說句話", action: #selector(talk), keyEquivalent: "")
        talkItem.target = self
        menu.addItem(talkItem)

        // 飛機有擺出來才能開
        let flyItem = NSMenuItem(title: "開飛機", action: scenery.isShown(scenery.plane) ? #selector(flyFromMenu) : nil, keyEquivalent: "")
        flyItem.target = self
        menu.addItem(flyItem)

        let home = pet.travel == .none
        let feedItem = NSMenuItem(title: "餵食（今天還剩 \(stats.feedsLeft) 次）", action: home ? #selector(feedFromMenu) : nil, keyEquivalent: "")
        feedItem.target = self
        menu.addItem(feedItem)

        let statusMenuItem = NSMenuItem(title: "狀態 / 地下城…（Lv.\(stats.level)）", action: #selector(openStatus), keyEquivalent: "")
        statusMenuItem.target = self
        menu.addItem(statusMenuItem)

        if let run = stats.run, let dungeon = Dungeon.find(run.dungeonID) {
            let minutes = max(1, Int(ceil(run.endsAt.timeIntervalSinceNow / 60)))
            menu.addItem(NSMenuItem(title: "冒險中：\(dungeon.name)（約 \(minutes) 分鐘後回來）", action: nil, keyEquivalent: ""))
        }

        let wardrobeItem = NSMenuItem(title: "衣櫃…", action: #selector(openWardrobe), keyEquivalent: "")
        wardrobeItem.target = self
        menu.addItem(wardrobeItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "結束", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = PetAction(rawValue: raw) else { return }
        setEverythingConcealed(false)
        pet.perform(action)
    }

    @objc private func toggleAutoMode() {
        pet.autoMode.toggle()
    }

    @objc private func toggleInputSync() {
        inputSync.setEnabled(!inputSync.enabled)
    }

    @objc private func openAccessibility() {
        inputSync.openAccessibilitySettings()
    }

    @objc private func talk() {
        setEverythingConcealed(false)
        pet.speech.say("click")
    }

    @objc private func flyFromMenu() {
        setEverythingConcealed(false)
        guard pet.canAct, pet.action != .fly, !scenery.mealInProgress else { return }
        visit(scenery.plane, doing: .fly)
    }

    @objc private func feedFromMenu() {
        feed()
    }

    // ⌥F：寵物和家具全部藏起來 / 顯示回來。不記住，下次開 App 一定看得到她。
    @objc private func toggleEverything() {
        setEverythingConcealed(!pet.concealed)
    }

    private func setEverythingConcealed(_ on: Bool) {
        guard on != pet.concealed else { return }
        pet.setConcealed(on)
        scenery.setConcealed(on, below: pet.window)
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
            pet.speech.sayText("出發去\(dungeon.name)冒險囉！")
            pet.leave()
        }
    }

    // 動畫迴圈每一幀呼叫：她在外面、時間也到了，就結算並讓她跑回來報告。
    private func checkRun() {
        guard pet.travel == .away, stats.runFinished,
              let result = stats.finishRun(outfits: sprites.manifest.outfits) else { return }
        pet.arrive { [weak self] in
            guard let self else { return }
            switch result.reward {
            case .outfit(_, let name)?:
                self.pet.speech.sayText("我回來了！在\(result.dungeon.name)拿到「\(name)」✨")
                self.pet.interlude(.dance)
            case .snack?:
                self.pet.speech.sayText("我回來了！在\(result.dungeon.name)撿到零食～")
                self.pet.interlude(.dance)
            case nil:
                self.pet.speech.say("lose")
            }
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
                self.checkRun()
                self.checkProps()
            }
        }
        // .common 模式：打開選單、拖曳時動畫也不會停。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
