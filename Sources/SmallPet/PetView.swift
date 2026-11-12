// PetView.swift —— 負責「畫出寵物」以及「處理滑鼠互動」的自訂 View。
//
// 畫面由好幾層 CALayer 疊成：最底下是本體（髮型 / 衣服各自一層），上面依序是各部位的服裝。
// 每一層都換成同一個動作、同一格的圖，所以衣服會跟著身體一起動。
import AppKit

final class PetView: NSView {

    private let sprites: SpriteLibrary

    // 所有圖層的容器；面向左邊時把整個容器水平翻轉。
    private let spriteRoot = CALayer()
    private var bodyLayers: [CALayer] = []              // 本體的各層（見 SpriteLibrary.bodyLayers）
    private var outfitLayers: [String: CALayer] = [:]   // 部位 id → 圖層

    // 目前顯示的狀態，沒變就不重設圖片。
    private var shownAction: PetAction?
    private var shownFrame = -1
    private var outfits: [String: String] = [:]
    private var look: Look

    var facingLeft = false {
        didSet {
            guard facingLeft != oldValue else { return }
            withoutAnimation {
                spriteRoot.transform = facingLeft ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
            }
        }
    }

    // 滑鼠事件交給外部（Pet）處理。
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((_ windowOrigin: NSPoint) -> Void)?   // 視窗應該移到的螢幕座標
    var onDragEnded: (() -> Void)?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    init(frame: NSRect, sprites: SpriteLibrary) {
        self.sprites = sprites
        self.look = sprites.defaultLook
        super.init(frame: frame)

        wantsLayer = true
        spriteRoot.frame = bounds
        layer?.addSublayer(spriteRoot)

        // 本體在最下面，服裝依 manifest 的 slots 順序往上疊。
        for _ in 0..<4 {
            let l = CALayer()
            setupImageLayer(l)
            bodyLayers.append(l)
        }
        for slot in sprites.manifest.slots {
            let l = CALayer()
            setupImageLayer(l)
            outfitLayers[slot.id] = l
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupImageLayer(_ l: CALayer) {
        l.frame = bounds
        l.contentsGravity = .resizeAspect
        spriteRoot.addSublayer(l)
    }

    // MARK: - 更新畫面

    // 顯示某個動作的某一格。
    func show(_ action: PetAction, frame: Int) {
        guard action != shownAction || frame != shownFrame else { return }
        shownAction = action
        shownFrame = frame
        refreshImages()
    }

    // 換髮型 / 衣服。
    func setLook(_ look: Look) {
        self.look = look
        refreshImages()
    }

    // 換裝：部位 id → 服裝 id。
    func setOutfits(_ equipped: [String: String]) {
        outfits = equipped
        refreshImages()
    }

    private func refreshImages() {
        guard let action = shownAction else { return }
        withoutAnimation {
            let images = sprites.bodyLayers(look, action, shownFrame)
            for (i, layer) in bodyLayers.enumerated() {
                layer.contents = i < images.count ? images[i] : nil
            }
            for (slot, layer) in outfitLayers {
                let id = outfits[slot]
                layer.contents = id.flatMap { sprites.outfitFrame($0, action, shownFrame) }
                // 翅膀在正面時是在她身後：疊到本體下面，長髮才會蓋在翅膀前面
                layer.zPosition = id.map { sprites.isBehind($0, action, shownFrame) } == true ? -1 : 0
            }
        }
    }

    // CALayer 改屬性預設會有 0.25 秒的淡入淡出，逐格動畫不需要。
    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: - 滑鼠互動

    // 按下時滑鼠在視窗內的位置，拖曳時讓這個點一直黏在游標下。
    private var grabOffset: NSPoint?
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        grabOffset = event.locationInWindow
        didDrag = false
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grab = grabOffset else { return }
        if !didDrag {
            didDrag = true
            onDragBegan?()
        }
        // 用螢幕座標計算，視窗移動時也不會累積誤差。
        let mouse = NSEvent.mouseLocation
        onDragMoved?(NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            onDragEnded?()
        } else if event.clickCount == 1 {
            onClick?()
        }
        grabOffset = nil
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}
