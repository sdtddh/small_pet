// CanopyWindow.swift —— 降落傘的傘面。
//
// 傘比寵物的畫布還高，所以不塞進寵物圖片裡，而是另開一個透明小視窗，
// 每一幀擺在寵物視窗正上方。寵物圖裡的繩子剛好畫到畫布頂端，跟這張圖的繩子接起來。
// 這個視窗不接收滑鼠，點到傘的位置會直接穿過去。
import AppKit

final class CanopyWindow: NSWindow {

    private let imageLayer = CALayer()

    init(image: NSImage?, width: CGFloat) {
        // 依圖片比例決定高度；沒有圖（例如換回小貓素材）就是一個看不到的空視窗。
        let height = image.map { width * $0.size.height / max($0.size.width, 1) } ?? 1
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isExcludedFromWindowsMenu = true
        ignoresMouseEvents = true

        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.wantsLayer = true
        imageLayer.frame = view.bounds
        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspect
        view.layer?.addSublayer(imageLayer)
        contentView = view
    }

    // 開傘 / 收傘。
    func setOpen(_ open: Bool, above petFrame: NSRect) {
        if open {
            setFrameOrigin(NSPoint(x: petFrame.minX, y: petFrame.maxY))
            if !isVisible { orderFrontRegardless() }
        } else if isVisible {
            orderOut(nil)
        }
    }
}
