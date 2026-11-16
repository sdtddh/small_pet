// ClockFace.swift —— 家具「時鐘」（從土裡長出來的番茄）會動的部分：時針、分針、秒針，和番茄鐘剩下的時間。
//
// 時鐘的圖（Resources/props/clock.png，Tools/generate-bunny.swift 的 drawClock）只畫不會動的土、莖、番茄和錶面；
// 這裡把指針疊在上面。錶面中心、半徑要跟 drawClock 一致。
//
// 番茄鐘 / 倒數進行中，錶面會出現一塊扇形：從 12 點順時針鋪出剩下的分鐘數（一圈 = 60 分鐘），
// 時間越少扇形越小，就像廚房用的計時器。專注是紅色，休息和倒數是藍色，暫停時變淡。
// 每秒由 AppDelegate 呼叫一次 update（時鐘沒擺出來時不呼叫）。
import AppKit

@MainActor
final class ClockFace {

    struct Remaining {
        let minutes: Double
        let focus: Bool
        let paused: Bool
    }

    private static let center = CGPoint(x: 32, y: 61)
    private static let radius: CGFloat = 16.5
    private static let outline = CGColor(srgbRed: 0x2B / 255, green: 0x22 / 255, blue: 0x30 / 255, alpha: 1)

    private let sector = CAShapeLayer()
    private let hourHand = CAShapeLayer()
    private let minuteHand = CAShapeLayer()
    private let secondHand = CAShapeLayer()
    private let cap = CAShapeLayer()

    init(on window: SceneryWindow) {
        let c = Self.center
        sector.fillColor = nil
        window.addOverlay(sector)

        for (hand, length, width, color) in [
            (hourHand, CGFloat(8.5), CGFloat(2.2), Self.outline),
            (minuteHand, 12.5, 1.6, Self.outline),
            (secondHand, 13.5, 0.8, CGColor(srgbRed: 0.85, green: 0.27, blue: 0.23, alpha: 1)),
        ] {
            // 每根指針都是以錶面中心為支點、指向 12 點的線，轉 transform 就好
            hand.frame = CGRect(x: c.x - 20, y: c.y - 20, width: 40, height: 40)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 20, y: 18))
            path.addLine(to: CGPoint(x: 20, y: 20 + length))
            hand.path = path
            hand.strokeColor = color
            hand.lineWidth = width
            hand.lineCap = .round
            hand.actions = ["transform": NSNull()]
            window.addOverlay(hand)
        }
        cap.path = CGPath(ellipseIn: CGRect(x: c.x - 1.8, y: c.y - 1.8, width: 3.6, height: 3.6), transform: nil)
        cap.fillColor = Self.outline
        window.addOverlay(cap)
        update(now: Date(), remaining: nil)
    }

    func update(now: Date, remaining: Remaining?) {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let h = Double(parts.hour ?? 0), m = Double(parts.minute ?? 0), s = Double(parts.second ?? 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hourHand.setAffineTransform(Self.rotation(turns: (h.truncatingRemainder(dividingBy: 12) + m / 60) / 12))
        minuteHand.setAffineTransform(Self.rotation(turns: (m + s / 60) / 60))
        secondHand.setAffineTransform(Self.rotation(turns: s / 60))

        if let remaining, remaining.minutes > 0 {
            let fraction = min(remaining.minutes / 60, 1)
            let path = CGMutablePath()
            path.move(to: Self.center)
            // 從 12 點開始，順時針鋪出剩下的時間（Core Graphics 的 y 軸朝上，順時針就是角度變小）
            path.addArc(center: Self.center, radius: Self.radius, startAngle: .pi / 2,
                        endAngle: .pi / 2 - CGFloat(fraction) * 2 * .pi, clockwise: true)
            path.closeSubpath()
            sector.path = path
            let alpha: CGFloat = remaining.paused ? 0.25 : 0.55
            sector.fillColor = remaining.focus
                ? CGColor(srgbRed: 0.91, green: 0.38, blue: 0.30, alpha: alpha)
                : CGColor(srgbRed: 0.36, green: 0.68, blue: 0.90, alpha: alpha)
            sector.isHidden = false
        } else {
            sector.isHidden = true
        }
        CATransaction.commit()
    }

    // 從 12 點順時針轉幾圈。
    private static func rotation(turns: Double) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: -CGFloat(turns) * 2 * .pi)
    }
}
