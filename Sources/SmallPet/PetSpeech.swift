// PetSpeech.swift —— 寵物說話：讀台詞庫、在頭上顯示對話泡泡。
//
// 台詞放在 Resources/phrases.json，依「情境」分類，每類隨機挑一句。
// 想改台詞、加台詞，直接編輯那個檔案即可。
import AppKit

@MainActor
final class PetSpeech {

    private var phrases: [String: [String]] = [:]
    private let bubble = BubbleWindow()

    // 自動碎念之間至少間隔幾秒，避免一直講話。
    var chatterCooldown: Double = 8
    private var lastSpokeAt: Double = -.infinity

    // 寵物最新的位置，說話時用來擺放泡泡。
    private var petFrame: NSRect = .zero

    // 整個藏起來時不說話，正在顯示的泡泡也收掉。
    var muted = false {
        didSet {
            guard muted else { return }
            generation += 1
            bubble.orderOut(nil)
        }
    }

    // 每次說話遞增，用來判斷「要淡出的是不是同一句」。
    private var generation = 0

    init(resources: URL) {
        let url = resources.appendingPathComponent("phrases.json")
        do {
            let data = try Data(contentsOf: url)
            phrases = try JSONDecoder().decode([String: [String]].self, from: data)
        } catch {
            NSLog("phrases.json 讀取失敗，寵物不會說話：\(error)")
        }
    }

    // 從某個情境隨機挑一句來說。
    // - chance：說話的機率（0~1），用在「偶爾碎念」。
    // - force：false 時若剛說過話或泡泡還在，就跳過（自動觸發用）；
    //          true 時一定說（使用者互動觸發用）。
    func say(_ category: String, chance: Double = 1, force: Bool = true) {
        guard Double.random(in: 0..<1) < chance else { return }
        if !force {
            let now = CACurrentMediaTime()
            guard !bubble.isVisible, now - lastSpokeAt >= chatterCooldown else { return }
        }
        guard let text = phrases[category]?.randomElement() else { return }
        show(text)
    }

    // 直接說一句指定的話（例如「+20 XP！」）。
    func sayText(_ text: String) {
        show(text)
    }

    // 依現在時間挑打招呼的情境。
    func greet() {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: say("greeting_morning")
        case 12..<18: say("greeting_afternoon")
        case 18..<23: say("greeting_evening")
        default: say("greeting_night")
        }
    }

    // 每一幀由 Pet 呼叫，讓泡泡跟著寵物移動。
    func follow(_ petFrame: NSRect) {
        self.petFrame = petFrame
        guard bubble.isVisible else { return }
        bubble.place(above: petFrame)
    }

    // MARK: - 顯示與淡出

    private func show(_ text: String) {
        guard !muted else { return }
        generation += 1
        let current = generation
        lastSpokeAt = CACurrentMediaTime()

        bubble.setText(text)
        bubble.place(above: petFrame)
        bubble.alphaValue = 1
        bubble.orderFrontRegardless()

        // 字越多停留越久（2~6 秒）。
        let duration = min(2 + Double(text.count) * 0.15, 6)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.fadeOut(generation: current)
        }
    }

    private func fadeOut(generation expected: Int) {
        // 期間如果又說了新的一句，就不要把新的那句收掉。
        guard expected == generation else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            bubble.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, expected == self.generation else { return }
                self.bubble.orderOut(nil)
            }
        })
    }
}

// MARK: - 泡泡視窗

// 跟寵物一樣是透明、無邊框、置頂的視窗，但不接收滑鼠（點擊會穿過去）。
final class BubbleWindow: NSWindow {

    private let bubbleView = BubbleView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isExcludedFromWindowsMenu = true
        contentView = bubbleView
    }

    func setText(_ text: String) {
        bubbleView.text = text
        setContentSize(bubbleView.fittingSize)
    }

    // 擺在寵物頭上；靠近螢幕邊緣時泡泡往內收，但尾巴仍指向寵物。
    func place(above petFrame: NSRect) {
        let size = frame.size
        // 角色頭頂大約在畫布高度 78% 的位置（畫布上方有留白給帽子）。
        let headTop = petFrame.minY + petFrame.height * 0.78
        var x = petFrame.midX - size.width / 2
        if let visible = NSScreen.main?.visibleFrame {
            x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        setFrameOrigin(NSPoint(x: x, y: headTop))
        bubbleView.tailX = petFrame.midX - x
    }
}

final class BubbleView: NSView {

    var text = "" {
        didSet { needsDisplay = true }
    }
    // 尾巴尖端的 x 座標（視圖座標）。
    var tailX: CGFloat = 0 {
        didSet { if tailX != oldValue { needsDisplay = true } }
    }

    private let maxTextWidth: CGFloat = 180
    private let padding = NSSize(width: 12, height: 8)
    private let tailHeight: CGFloat = 8
    private let outline = NSColor(srgbRed: 0x5B / 255.0, green: 0x3A / 255.0, blue: 0x29 / 255.0, alpha: 1)

    private var attributes: [NSAttributedString.Key: Any] {
        let base = NSFont.systemFont(ofSize: 13, weight: .medium)
        let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 13) } ?? base
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return [
            .font: rounded,
            .foregroundColor: NSColor(srgbRed: 0x3B / 255.0, green: 0x24 / 255.0, blue: 0x18 / 255.0, alpha: 1),
            .paragraphStyle: style,
        ]
    }

    private var textSize: NSSize {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return NSSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    override var fittingSize: NSSize {
        let t = textSize
        return NSSize(width: t.width + padding.width * 2 + 2,
                      height: t.height + padding.height * 2 + tailHeight + 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 1, y: tailHeight + 1,
                          width: bounds.width - 2, height: bounds.height - tailHeight - 2)
        let tip = min(max(tailX, body.minX + 14), body.maxX - 14)

        // 圓角泡泡本體
        let bubble = NSBezierPath(roundedRect: body, xRadius: 10, yRadius: 10)
        NSColor.white.setFill()
        bubble.fill()
        outline.setStroke()
        bubble.lineWidth = 2
        bubble.stroke()

        // 指向寵物的小尾巴：先填白蓋掉泡泡底線，再描兩條斜邊。
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: tip - 6, y: body.minY + 1.5))
        tail.line(to: NSPoint(x: tip, y: 1))
        tail.line(to: NSPoint(x: tip + 6, y: body.minY + 1.5))
        tail.close()
        NSColor.white.setFill()
        tail.fill()

        let edges = NSBezierPath()
        edges.move(to: NSPoint(x: tip - 6, y: body.minY))
        edges.line(to: NSPoint(x: tip, y: 1))
        edges.line(to: NSPoint(x: tip + 6, y: body.minY))
        edges.lineWidth = 2
        edges.lineJoinStyle = .round
        edges.stroke()

        // 文字
        let t = textSize
        let textRect = NSRect(x: (bounds.width - t.width) / 2,
                              y: body.minY + padding.height,
                              width: t.width, height: t.height)
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: attributes)
    }
}
