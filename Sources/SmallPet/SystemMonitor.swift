// SystemMonitor.swift —— 床頭櫃（系統監視器）：CPU 用量和記憶體壓力。
//
//   - 床頭櫃上的儀表：指針是整台電腦的 CPU 用量，燈泡顏色是記憶體壓力（綠 / 黃 / 紅）。
//   - 按住床頭櫃往上拉：打開「系統資訊」小視窗，另外看得到 SmallPet 自己的用量，「詳細」裡有記憶體用量、壓縮、交換檔。
//
// 為什麼看「記憶體壓力」而不是「用了幾 GB」：macOS 會把閒著的記憶體拿去當快取，「已使用」常常接近滿也沒事；
// 真的不夠用時系統才會開始壓縮、寫交換檔，這時壓力才會變黃、變紅（跟活動監視器的「記憶體壓力」同一個數值）。
//
// 數值都直接跟系統要（mach / sysctl），不需要任何權限。床頭櫃沒擺出來、視窗也沒開的時候不讀。
import AppKit
import Darwin
import SwiftUI

// MARK: - 讀數值

struct SystemSnapshot {
    enum Pressure: Int {
        case normal = 1, warning = 2, critical = 4

        var title: String {
            switch self {
            case .normal: return "正常"
            case .warning: return "偏緊"
            case .critical: return "不足"
            }
        }
        var detail: String {
            switch self {
            case .normal: return "記憶體夠用。"
            case .warning: return "記憶體有點緊，系統正在壓縮記憶體，可能會變慢。"
            case .critical: return "記憶體不夠了，系統大量使用交換檔，建議關掉一些 App。"
            }
        }
        var color: NSColor {
            switch self {
            case .normal: return NSColor(srgbRed: 0.30, green: 0.80, blue: 0.35, alpha: 1)
            case .warning: return NSColor(srgbRed: 0.95, green: 0.70, blue: 0.24, alpha: 1)
            case .critical: return NSColor(srgbRed: 0.92, green: 0.20, blue: 0.17, alpha: 1)
            }
        }
    }

    var cpu: Double = 0                 // 整台電腦的 CPU 用量，0…1
    var pressure = Pressure.normal
    var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var memoryUsed: UInt64 = 0          // 跟活動監視器的「已使用記憶體」同算法：App 記憶體 + 系統佔用 + 已壓縮
    var memoryCompressed: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var ownCPU: Double = 0              // SmallPet 自己，跟活動監視器一樣以一顆核心為 100%
    var ownMemory: UInt64 = 0
}

@MainActor
final class SystemMonitor: ObservableObject {

    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var hasSample = false
    // 有沒有人在看（床頭櫃擺出來、或資訊視窗開著）；沒人看就不讀。
    var isNeeded: () -> Bool = { false }
    var onSample: ((SystemSnapshot) -> Void)?

    private let host = mach_host_self()
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastOwn: (cpu: Double, wall: Double)?
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // 馬上讀一次（剛擺出床頭櫃、剛打開視窗時，不用等下一秒）。
    func tick() {
        guard isNeeded() else {
            // 停一陣子再開始時，CPU 要重新取樣兩次才算得出來，別拿很久以前的數字來比。
            lastTicks = nil
            lastOwn = nil
            return
        }
        var s = snapshot
        if let ticks = cpuTicks() {
            if let last = lastTicks, ticks.total > last.total {
                s.cpu = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
            }
            lastTicks = ticks
        }
        readMemory(into: &s)
        readOwn(into: &s)
        snapshot = s
        hasSample = true
        onSample?(s)
    }

    private func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    private func readMemory(into s: inout SystemSnapshot) {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            s.pressure = SystemSnapshot.Pressure(rawValue: Int(level)) ?? (level > 2 ? .critical : .normal)
        }

        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        if result == KERN_SUCCESS {
            let page = UInt64(pageSize)
            let app = UInt64(vm.internal_page_count) - min(UInt64(vm.internal_page_count), UInt64(vm.purgeable_count))
            s.memoryCompressed = UInt64(vm.compressor_page_count) * page
            s.memoryUsed = (app + UInt64(vm.wire_count)) * page + s.memoryCompressed
        }

        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            s.swapUsed = swap.xsu_used
            s.swapTotal = swap.xsu_total
        }
    }

    private func readOwn(into s: inout SystemSnapshot) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS { s.ownMemory = info.phys_footprint }

        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let wall = CACurrentMediaTime()
        if let last = lastOwn, wall > last.wall {
            s.ownCPU = max(0, (cpu - last.cpu) / (wall - last.wall))
        }
        lastOwn = (cpu, wall)
    }
}

// MARK: - 床頭櫃上會動的部分

// 指針和燈泡疊在 monitor.png 上面。座標跟 generate-bunny.swift 的 drawMonitor 一致。
// 記憶體壓力不只看顏色：燈泡裡有符號（✓ / ! / ✕），光芒也越來越多（3 / 5 / 7 條），紅綠色弱也分得出來。
@MainActor
final class SystemGauge {

    private static let size = CGSize(width: 64, height: 112)
    private static let pivot = CGPoint(x: 32, y: 58)
    private static let needleLength: CGFloat = 14
    private static let bulb = CGPoint(x: 32, y: 94)

    private let needle = CAShapeLayer()
    private let cap = CAShapeLayer()
    private let bulbLayer = CAShapeLayer()
    private let shine = CAShapeLayer()
    private let rays = CAShapeLayer()
    private let symbol = CAShapeLayer()     // 燈泡裡的 ✓ / ! / ✕：色弱的人不用靠顏色也看得出來
    private let symbolDot = CAShapeLayer()  // 「!」下面那一點
    private var pressure: SystemSnapshot.Pressure?

    private static let outline = CGColor(srgbRed: 0x2B / 255, green: 0x22 / 255, blue: 0x30 / 255, alpha: 1)

    init(on window: SceneryWindow) {
        let p = Self.pivot
        // 指針：整張圖大小的圖層，以支點旋轉
        needle.bounds = CGRect(origin: .zero, size: Self.size)
        needle.anchorPoint = CGPoint(x: p.x / Self.size.width, y: p.y / Self.size.height)
        needle.position = p
        let path = CGMutablePath()
        path.move(to: p)
        path.addLine(to: CGPoint(x: p.x, y: p.y + Self.needleLength))
        needle.path = path
        needle.strokeColor = CGColor(srgbRed: 0.85, green: 0.27, blue: 0.23, alpha: 1)
        needle.lineWidth = 1.8
        needle.lineCap = .round
        cap.path = CGPath(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5), transform: nil)
        cap.fillColor = Self.outline

        let b = Self.bulb
        bulbLayer.path = CGPath(ellipseIn: CGRect(x: b.x - 7.5, y: b.y - 7.5, width: 15, height: 15), transform: nil)
        bulbLayer.strokeColor = Self.outline
        bulbLayer.lineWidth = 1.6
        bulbLayer.shadowOffset = .zero
        bulbLayer.shadowRadius = 5
        bulbLayer.shadowOpacity = 0.9
        shine.path = CGPath(ellipseIn: CGRect(x: b.x - 5.2, y: b.y + 2.2, width: 2.8, height: 2.8), transform: nil)
        shine.fillColor = CGColor(gray: 1, alpha: 0.75)
        symbol.strokeColor = Self.outline
        symbol.fillColor = nil
        symbol.lineWidth = 1.9
        symbol.lineCap = .round
        symbol.lineJoin = .round
        symbolDot.path = CGPath(ellipseIn: CGRect(x: b.x - 1.1, y: b.y - 4.1, width: 2.2, height: 2.2), transform: nil)
        symbolDot.fillColor = Self.outline
        rays.lineWidth = 1.4
        rays.lineCap = .round
        rays.fillColor = nil

        for layer in [needle, cap, rays, bulbLayer, shine, symbol, symbolDot] as [CALayer] {
            if layer !== needle { layer.frame = CGRect(origin: .zero, size: Self.size) }
            window.addOverlay(layer)
        }
        setCPU(0, animated: false)
        setPressure(.normal)
    }

    func update(_ s: SystemSnapshot) {
        setCPU(s.cpu, animated: true)
        setPressure(s.pressure)
    }

    private func setCPU(_ value: Double, animated: Bool) {
        let f = CGFloat(min(max(value, 0), 1))
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.8 : 0)
        CATransaction.setDisableActions(!animated)
        // f = 0 指向左邊（逆時針轉 90°），f = 1 指向右邊
        needle.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 2 - .pi * f))
        CATransaction.commit()
    }

    private func setPressure(_ p: SystemSnapshot.Pressure) {
        guard p != pressure else { return }
        pressure = p
        let (fill, ray): (UInt32, UInt32) = switch p {
        case .normal: (0x4CD964, 0x2FB24C)
        case .warning: (0xFFD45C, 0xF2B33C)
        case .critical: (0xFF3B30, 0xD7261E)
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        rays.path = Self.rays(count: p == .normal ? 3 : p == .warning ? 5 : 7)
        symbol.path = Self.symbol(for: p)
        symbolDot.isHidden = p != .warning
        bulbLayer.fillColor = Self.color(fill)
        bulbLayer.shadowColor = Self.color(fill)
        rays.strokeColor = Self.color(ray)
        CATransaction.commit()
        // 記憶體不足時燈泡一閃一閃
        for layer in [bulbLayer, rays] {
            if p == .critical {
                let blink = CABasicAnimation(keyPath: "opacity")
                blink.fromValue = 1
                blink.toValue = 0.35
                blink.duration = 0.6
                blink.autoreverses = true
                blink.repeatCount = .infinity
                layer.add(blink, forKey: "blink")
            } else {
                layer.removeAnimation(forKey: "blink")
            }
        }
    }

    // 光芒：由上往兩邊、往下加
    private static func rays(count: Int) -> CGPath {
        let b = bulb
        let all: [(CGFloat, CGFloat)] = [(0, 12.5), (-8, 10), (8, 10), (-11, 3.5), (11, 3.5), (-11.5, -3.5), (11.5, -3.5)]
        let r = CGMutablePath()
        for (dx, dy) in all.prefix(count) {
            let n = hypot(dx, dy), k = (n + 3) / n
            r.move(to: CGPoint(x: b.x + dx, y: b.y + dy))
            r.addLine(to: CGPoint(x: b.x + dx * k, y: b.y + dy * k))
        }
        return r
    }

    private static func symbol(for p: SystemSnapshot.Pressure) -> CGPath {
        let b = bulb
        let path = CGMutablePath()
        switch p {
        case .normal:    // ✓
            path.move(to: CGPoint(x: b.x - 3.4, y: b.y + 0.2))
            path.addLine(to: CGPoint(x: b.x - 0.8, y: b.y - 2.6))
            path.addLine(to: CGPoint(x: b.x + 3.6, y: b.y + 2.8))
        case .warning:   // ! 的直線（點是 symbolDot）
            path.move(to: CGPoint(x: b.x, y: b.y + 3.6))
            path.addLine(to: CGPoint(x: b.x, y: b.y - 0.6))
        case .critical:  // ✕
            path.move(to: CGPoint(x: b.x - 3, y: b.y + 3))
            path.addLine(to: CGPoint(x: b.x + 3, y: b.y - 3))
            path.move(to: CGPoint(x: b.x + 3, y: b.y + 3))
            path.addLine(to: CGPoint(x: b.x - 3, y: b.y - 3))
        }
        return path
    }

    private static func color(_ v: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

// MARK: - 系統資訊視窗

@MainActor
final class SystemInfoWindowController {

    private var window: NSWindow?
    private let monitor: SystemMonitor
    var isVisible: Bool { window?.isVisible ?? false }

    init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    // anchor：床頭櫃視窗的位置，資訊視窗開在它正上方。
    func show(above anchor: NSRect) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "系統資訊"
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: SystemInfoView(monitor: monitor))
            host.sizingOptions = [.preferredContentSize]
            w.contentView = host
            window = w
        }
        guard let window else { return }
        if !window.isVisible, let visible = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            let x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            let y = min(anchor.maxY + 8, visible.maxY - size.height)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        window.bringToFront()
        monitor.tick()
    }
}

struct SystemInfoView: View {
    @ObservedObject var monitor: SystemMonitor
    @State var showDetail = false

    var body: some View {
        let s = monitor.snapshot
        VStack(alignment: .leading, spacing: 14) {
            section("CPU") {
                HStack(alignment: .firstTextBaseline) {
                    Text(monitor.hasSample ? percent(s.cpu) : "—").font(.system(size: 26, weight: .bold).monospacedDigit())
                    Spacer()
                    Text(cpuWord(s.cpu)).foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule().fill(cpuColor(s.cpu)).frame(width: g.size.width * min(max(s.cpu, 0), 1))
                    }
                }
                .frame(height: 8)
                .animation(.easeOut(duration: 0.6), value: s.cpu)
            }
            section("記憶體壓力") {
                HStack(spacing: 8) {
                    Circle().fill(Color(nsColor: s.pressure.color)).frame(width: 14, height: 14)
                    Text(s.pressure.title).font(.system(size: 20, weight: .bold))
                }
                Text(s.pressure.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            section("SmallPet 自己") {
                Text("CPU \(percent(s.ownCPU))　記憶體 \(bytes(s.ownMemory))").monospacedDigit()
            }
            DisclosureGroup("詳細", isExpanded: $showDetail) {
                VStack(alignment: .leading, spacing: 4) {
                    row("已使用記憶體", "\(bytes(s.memoryUsed)) / \(bytes(s.memoryTotal))")
                    row("其中壓縮", bytes(s.memoryCompressed))
                    row("交換檔", "\(bytes(s.swapUsed)) / \(bytes(s.swapTotal))")
                    Text("macOS 會把閒著的記憶體拿去當快取，「已使用」接近滿也很正常，看上面的記憶體壓力就好。")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(width: 280)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func bytes(_ v: UInt64) -> String {
        let gb = Double(v) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : "\(Int((Double(v) / 1_048_576).rounded())) MB"
    }

    private func cpuWord(_ v: Double) -> String { v < 0.45 ? "輕鬆" : v < 0.72 ? "有點忙" : "很忙" }
    private func cpuColor(_ v: Double) -> Color {
        Color(nsColor: v < 0.45 ? SystemSnapshot.Pressure.normal.color : v < 0.72 ? SystemSnapshot.Pressure.warning.color : SystemSnapshot.Pressure.critical.color)
    }
}
