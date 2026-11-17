// ClockFace.swift —— 家具「時鐘」會動的部分：時針、分針、秒針，和番茄鐘剩下的時間。也定義時鐘的外觀（ClockLook）。
//
// 時鐘的圖（Resources/props/clock_tomato.png、clock_pumpkin.png，Tools/generate-bunny.swift 的 drawTomatoClock / drawPumpkinClock）
// 只畫不會動的植物和錶面；
// 這裡把指針疊在上面。錶面中心、半徑要跟 drawClock 一致。
//
// 番茄鐘 / 倒數進行中，錶面會出現一塊扇形：從 12 點順時針鋪出剩下的分鐘數（一圈 = 60 分鐘），
// 時間越少扇形越小，就像廚房用的計時器。專注是紅色，休息和倒數是藍色，暫停時變淡。
// 每秒由 AppDelegate 呼叫一次 update（時鐘沒擺出來時不呼叫）。
import AppKit

// 時鐘的外觀：使用者在時鐘往上拉打開的視窗「外觀」分頁挑。存在 UserDefaults，換了會發 didChange 通知。
enum ClockLook: String, CaseIterable, Identifiable {
    case tomato     // 從土裡長出來的番茄
    case pumpkin    // 草地上的南瓜

    static let key = "scenery.clock.look"
    static let didChange = Notification.Name("ClockLookDidChange")

    static var current: ClockLook {
        UserDefaults.standard.string(forKey: key).flatMap(ClockLook.init) ?? .tomato
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .tomato: "番茄"
        case .pumpkin: "南瓜"
        }
    }

    // Resources/props/ 裡的圖名。
    var propName: String { "clock_\(rawValue)" }

    // 錶面中心在圖上的位置（點，原點在左下角）；要跟 generate-bunny.swift 畫的一致。
    var faceCenter: CGPoint {
        switch self {
        case .tomato: CGPoint(x: 32, y: 61)
        case .pumpkin: CGPoint(x: 46, y: 24)
        }
    }

    // 澆水時水要落在圖上哪裡（離圖左邊幾點）：她站左邊澆的位置、站右邊澆的位置。
    // 番茄澆在莖兩旁的土上，南瓜澆在南瓜左右兩側。
    var waterSpots: (left: CGFloat, right: CGFloat) {
        switch self {
        case .tomato: (20, 45)
        case .pumpkin: (24, 72)
        }
    }
}

@MainActor
final class ClockFace {

    struct Remaining {
        let minutes: Double
        let focus: Bool
        let paused: Bool
    }

    private var center = ClockLook.current.faceCenter
    private static let radius: CGFloat = 16.5
    private static let outline = CGColor(srgbRed: 0x2B / 255, green: 0x22 / 255, blue: 0x30 / 255, alpha: 1)

    private let sector = CAShapeLayer()
    private let hourHand = CAShapeLayer()
    private let minuteHand = CAShapeLayer()
    private let secondHand = CAShapeLayer()
    private let cap = CAShapeLayer()

    init(on window: SceneryWindow) {
        sector.fillColor = nil
        window.addOverlay(sector)

        for (hand, length, width, color) in [
            (hourHand, CGFloat(8.5), CGFloat(2.2), Self.outline),
            (minuteHand, 12.5, 1.6, Self.outline),
            (secondHand, 13.5, 0.8, CGColor(srgbRed: 0.85, green: 0.27, blue: 0.23, alpha: 1)),
        ] {
            // 每根指針都是以錶面中心為支點、指向 12 點的線，轉 transform 就好（位置在 layout 擺）
            hand.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
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
        cap.fillColor = Self.outline
        cap.actions = ["position": NSNull(), "path": NSNull()]
        window.addOverlay(cap)
        move(to: center)
    }

    // 換外觀時錶面中心跟著搬：指針、中心的小圓點都移過去，扇形下次 update 用新的中心畫。
    func move(to newCenter: CGPoint) {
        center = newCenter
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for hand in [hourHand, minuteHand, secondHand] { hand.position = newCenter }
        cap.path = CGPath(ellipseIn: CGRect(x: newCenter.x - 1.8, y: newCenter.y - 1.8, width: 3.6, height: 3.6), transform: nil)
        CATransaction.commit()
        update(now: Date(), remaining: lastRemaining)
    }
    private var lastRemaining: Remaining?

    func update(now: Date, remaining: Remaining?) {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let h = Double(parts.hour ?? 0), m = Double(parts.minute ?? 0), s = Double(parts.second ?? 0)
        lastRemaining = remaining
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hourHand.setAffineTransform(Self.rotation(turns: (h.truncatingRemainder(dividingBy: 12) + m / 60) / 12))
        minuteHand.setAffineTransform(Self.rotation(turns: (m + s / 60) / 60))
        secondHand.setAffineTransform(Self.rotation(turns: s / 60))

        if let remaining, remaining.minutes > 0 {
            let fraction = min(remaining.minutes / 60, 1)
            let path = CGMutablePath()
            path.move(to: center)
            // 從 12 點開始，順時針鋪出剩下的時間（Core Graphics 的 y 軸朝上，順時針就是角度變小）
            path.addArc(center: center, radius: Self.radius, startAngle: .pi / 2,
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
