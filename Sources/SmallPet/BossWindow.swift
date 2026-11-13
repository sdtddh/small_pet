// BossWindow.swift —— 地下城的 boss：出發冒險時出現在她旁邊，讓她拿劍砍。
//
// 一個透明小視窗，上面是名字和血條，下面是 boss 的圖（Resources/props/boss_<地下城>_*.png）。
// 血條跟著冒險的進度往下掉；她每砍中一刀，boss 換成被砍中的圖、往後晃一下、飄出傷害數字。
// 冒險結束：贏了 boss 縮小淡出；輸了 boss 得意地晃一晃再淡出。
// 點 boss：她多砍一刀，冒險時間少 1 秒（由 AppDelegate 處理，這裡只回報點擊、飄出「-1 秒」）。
import AppKit

@MainActor
final class BossWindow: NSWindow {

    static let artSize = NSSize(width: 150, height: 130)
    private static let barHeight: CGFloat = 26   // 名字 + 血條

    private let idleFrames: [NSImage?]
    private let hitImage: NSImage?
    private let holder = CALayer()   // 震動、縮小用；裡面的 art 負責左右翻面
    private let art = CALayer()
    private let barBack = CALayer()
    private let barFill = CALayer()
    private let nameLabel = CATextLayer()
    private var hitUntil: Double = 0
    var onClick: (() -> Void)?
    private var finished = false

    // boss 的圖是面向左畫的；她在 boss 右邊時要翻過來。
    init(dungeon: Dungeon, sprites: SpriteLibrary, facingLeft: Bool) {
        idleFrames = [sprites.prop("boss_\(dungeon.id)_idle_0"), sprites.prop("boss_\(dungeon.id)_idle_1")]
        hitImage = sprites.prop("boss_\(dungeon.id)_hit")
        let size = NSSize(width: Self.artSize.width, height: Self.artSize.height + Self.barHeight)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isExcludedFromWindowsMenu = true
        let view = BossClickView(frame: NSRect(origin: .zero, size: size))
        view.onClick = { [weak self] in self?.onClick?() }
        view.wantsLayer = true
        contentView = view
        let root = view.layer!

        holder.frame = NSRect(origin: .zero, size: Self.artSize)
        root.addSublayer(holder)
        art.frame = holder.bounds
        art.contentsGravity = .resizeAspect
        art.actions = ["contents": NSNull()]
        if !facingLeft { art.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1)) }
        art.contents = idleFrames[0]
        holder.addSublayer(art)

        // 血條
        let barRect = NSRect(x: 25, y: Self.artSize.height + 4, width: Self.artSize.width - 50, height: 7)
        barBack.frame = barRect
        barBack.backgroundColor = NSColor(white: 0.15, alpha: 0.75).cgColor
        barBack.cornerRadius = 3.5
        barBack.borderColor = NSColor(white: 1, alpha: 0.8).cgColor
        barBack.borderWidth = 1
        root.addSublayer(barBack)
        barFill.frame = barRect.insetBy(dx: 1.5, dy: 1.5)
        barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        barFill.position = CGPoint(x: barRect.minX + 1.5, y: barRect.midY)
        barFill.backgroundColor = NSColor(calibratedRed: 0.93, green: 0.27, blue: 0.3, alpha: 1).cgColor
        barFill.cornerRadius = 2
        barFill.actions = ["bounds": NSNull(), "position": NSNull()]
        root.addSublayer(barFill)

        // 名字
        nameLabel.string = dungeon.bossName
        nameLabel.font = NSFont.boldSystemFont(ofSize: 11)
        nameLabel.fontSize = 11
        nameLabel.foregroundColor = NSColor.white.cgColor
        nameLabel.alignmentMode = .center
        nameLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        nameLabel.shadowColor = NSColor.black.cgColor
        nameLabel.shadowOpacity = 0.9
        nameLabel.shadowRadius = 1.5
        nameLabel.shadowOffset = .zero
        nameLabel.frame = NSRect(x: 0, y: Self.artSize.height + 11, width: Self.artSize.width, height: 15)
        root.addSublayer(nameLabel)
    }

    // 每一幀呼叫：progress 是冒險進度（0 剛出發 → 1 時間到），血條跟著掉，但結算前最少留一點。
    func update(progress: Double, time: Double) {
        guard !finished else { return }
        setHP(max(0.06, 1 - progress))
        let now = CACurrentMediaTime()
        art.contents = now < hitUntil ? hitImage : idleFrames[Int(time * 2.5) % idleFrames.count]
    }

    private func setHP(_ fraction: Double) {
        let full = barBack.frame.width - 3
        barFill.bounds.size.width = full * CGFloat(min(max(fraction, 0), 1))
    }

    // 被砍中：換成被砍的圖、往後震一下、飄出傷害數字。
    func hit(damage: Int) {
        guard !finished else { return }
        hitUntil = CACurrentMediaTime() + 0.22
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        let x = holder.position.x
        shake.values = [x, x + 5, x - 2, x]
        shake.duration = 0.22
        holder.add(shake, forKey: "shake")

        float("-\(damage)", color: NSColor(calibratedRed: 1, green: 0.88, blue: 0.3, alpha: 1), size: 15,
              at: CGPoint(x: CGFloat.random(in: 40...100), y: 80))
    }

    // 飄起來再淡掉的一行字（傷害數字、-1 秒）。
    private func float(_ text: String, color: NSColor, size: CGFloat, at center: CGPoint) {
        let label = CATextLayer()
        label.string = text
        label.font = NSFont.systemFont(ofSize: size, weight: .heavy)
        label.fontSize = size
        label.foregroundColor = color.cgColor
        label.shadowColor = NSColor.black.cgColor
        label.shadowOpacity = 1
        label.shadowRadius = 1.5
        label.shadowOffset = .zero
        label.alignmentMode = .center
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        label.frame = NSRect(x: center.x - 30, y: center.y - 10, width: 60, height: 20)
        contentView?.layer?.addSublayer(label)
        CATransaction.begin()
        CATransaction.setCompletionBlock { label.removeFromSuperlayer() }
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.byValue = 30
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [rise, fade]
        group.duration = 0.8
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        label.add(group, forKey: "pop")
        CATransaction.commit()
    }

    // 點擊加速：在 boss 上方飄出「-1 秒」。
    func showTimeBonus(_ text: String) {
        guard !finished else { return }
        float(text, color: NSColor(calibratedRed: 0.55, green: 0.9, blue: 1, alpha: 1), size: 12,
              at: CGPoint(x: Self.artSize.width / 2, y: Self.artSize.height - 22))
    }

    // 冒險結束。won：boss 被打倒，縮小淡出；輸了：boss 晃一晃得意地淡出。做完關掉視窗再呼叫 done。
    func finish(won: Bool, then done: @escaping () -> Void) {
        finished = true
        setHP(won ? 0 : 0.35)
        art.contents = won ? hitImage : idleFrames[0]
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.orderOut(nil)
            done()
        }
        // boss 本體：贏了縮小、輸了得意地左右晃
        let motion: CAAnimation
        if won {
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1
            shrink.toValue = 0.3
            shrink.beginTime = CACurrentMediaTime() + 0.5
            shrink.duration = 0.7
            motion = shrink
        } else {
            let wobble = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            wobble.values = [0, 0.08, -0.08, 0.08, -0.08, 0]
            wobble.duration = 1.2
            motion = wobble
        }
        motion.isRemovedOnCompletion = false
        motion.fillMode = .both
        holder.add(motion, forKey: "finish")
        // 整個視窗（含血條、名字）最後淡出
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + (won ? 0.6 : 1.2)
        fade.duration = 0.6
        fade.isRemovedOnCompletion = false
        fade.fillMode = .both
        contentView?.layer?.add(fade, forKey: "fade")
        CATransaction.commit()
    }
}

// boss 的畫面：第一下點擊就要算（App 沒在前景時也一樣）。透明的地方 macOS 會讓點擊穿過去。
private final class BossClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
