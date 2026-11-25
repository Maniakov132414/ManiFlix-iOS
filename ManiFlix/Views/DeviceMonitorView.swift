import SwiftUI
import UIKit
import Combine
import Darwin

private struct NetStatsHistorySample: Codable {
    let ts: Double?
    let rxMbps: Double?
    let txMbps: Double?
    let cpuPct: Double?
    let memPct: Double?
}

private struct NetStatsResponse: Codable {
    let ok: Bool?
    let ts: Double?
    let rxMbps: Double?
    let txMbps: Double?
    let peakRxMbps: Double?
    let peakTxMbps: Double?
    let cpuPct: Double?
    let memPct: Double?
    let reqPerSec: Double?
    let activeRequests: Int?
    let uptimeSec: Int?
    let history: [NetStatsHistorySample]?
}

private enum HardwareModelMapper {
    static func machineIdentifier() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !sim.isEmpty {
            return sim
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "AppleDevice"
            }
        }
    }

    static func friendlyName(for id: String) -> String {
        let map: [String: String] = [
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,5": "iPhone 13",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,6": "iPhone SE (3rd gen)",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone13,2": "iPhone 12",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "iPad16,3": "iPad Pro 11\" M4",
            "iPad16,4": "iPad Pro 11\" M4",
            "iPad16,5": "iPad Pro 13\" M4",
            "iPad16,6": "iPad Pro 13\" M4",
            "iPad14,8": "iPad Air 11\" M2",
            "iPad14,9": "iPad Air 11\" M2",
            "iPad14,10": "iPad Air 13\" M2",
            "iPad14,11": "iPad Air 13\" M2",
            "iPad14,3": "iPad Pro 11\" M2",
            "iPad14,4": "iPad Pro 11\" M2",
            "iPad14,5": "iPad Pro 12.9\" M2",
            "iPad14,6": "iPad Pro 12.9\" M2",
            "iPad13,18": "iPad (10th gen)",
            "iPad13,19": "iPad (10th gen)",
            "iPad14,1": "iPad mini (6th gen)",
            "iPad14,2": "iPad mini (6th gen)"
        ]
        if let name = map[id] {
            return "\(name) (\(id))"
        }
        if id.hasPrefix("iPad") {
            return "iPad (\(id))"
        }
        if id.hasPrefix("iPhone") {
            return "iPhone (\(id))"
        }
        return "\(UIDevice.current.model) (\(id))"
    }

    static func appResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }

    static func diskStatsGB() -> (freeGB: Double, totalGB: Double) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let freeBytes = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let totalBytes = Double(values?.volumeTotalCapacity ?? 0)
        return (freeBytes / 1_000_000_000.0, totalBytes / 1_000_000_000.0)
    }
}

@MainActor
private final class DeviceMonitorViewModel: ObservableObject {
    @Published var isLiveProbeEnabled = true
    @Published var isRunningSpeedtest = false
    @Published var isConnected = false
    @Published var rxMbps: Double = 0
    @Published var txMbps: Double = 0
    @Published var peakRxMbps: Double = 0
    @Published var peakTxMbps: Double = 0
    @Published var serverCpuPct: Double = 0
    @Published var serverMemPct: Double = 0
    @Published var reqPerSec: Double = 0
    @Published var uptimeSec: Int = 0

    @Published var downloadMbps: Double = 0
    @Published var uploadMbps: Double = 0
    @Published var pingMs: Double = 0
    @Published var jitterMs: Double = 0
    @Published var appRAMMB: Double = 0

    @Published var speedHistory: [Double] = []
    @Published var pingHistory: [Double] = []

    private var pollTask: Task<Void, Never>?
    private let baseURL = AppPreferences.shared.normalizedBaseURL

    func start() {
        refreshHardwareSnapshots()
        pollTask?.cancel()
        pollTask = Task {
            await pollCycle(includeProbe: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled { break }
                await pollCycle(includeProbe: isLiveProbeEnabled)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshHardwareSnapshots() {
        appRAMMB = HardwareModelMapper.appResidentMemoryMB()
    }

    func runSpeedtestNow() async {
        guard !isRunningSpeedtest else { return }
        isRunningSpeedtest = true
        defer { isRunningSpeedtest = false }

        refreshHardwareSnapshots()
        await fetchNetStats()
        await measurePingAndJitter(samples: 3)
        await measureDownload(kb: 256)
        await measureUpload(kb: 128)
        Haptics.notify(.success)
    }

    private func pollCycle(includeProbe: Bool) async {
        refreshHardwareSnapshots()
        await fetchNetStats()
        if includeProbe && !isRunningSpeedtest {
            await measurePingAndJitter(samples: 1)
            await measureDownload(kb: 128)
        }
    }

    private func fetchNetStats() async {
        guard let url = URL(string: "\(baseURL)/api/net-stats") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("ManiFlix-iOS/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                isConnected = false
                return
            }
            let stats = try JSONDecoder().decode(NetStatsResponse.self, from: data)
            isConnected = stats.ok ?? true
            rxMbps = stats.rxMbps ?? 0
            txMbps = stats.txMbps ?? 0
            peakRxMbps = stats.peakRxMbps ?? 0
            peakTxMbps = stats.peakTxMbps ?? 0
            serverCpuPct = stats.cpuPct ?? 0
            serverMemPct = stats.memPct ?? 0
            reqPerSec = stats.reqPerSec ?? 0
            uptimeSec = stats.uptimeSec ?? 0
        } catch {
            isConnected = false
        }
    }

    private func measurePingAndJitter(samples: Int) async {
        guard let url = URL(string: "\(baseURL)/api/net-probe?kb=4") else { return }
        var pings: [Double] = []
        for _ in 0..<max(1, samples) {
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let t0 = CFAbsoluteTimeGetCurrent()
            if let (_, response) = try? await URLSession.shared.data(for: req),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                let elapsedMs = max(1, (CFAbsoluteTimeGetCurrent() - t0) * 1000.0)
                pings.append(elapsedMs)
            }
        }
        guard !pings.isEmpty else { return }
        let avgPing = pings.reduce(0, +) / Double(pings.count)
        let prev = pingMs
        pingMs = avgPing
        if pings.count > 1 {
            var diffs: [Double] = []
            for i in 1..<pings.count { diffs.append(abs(pings[i] - pings[i - 1])) }
            jitterMs = diffs.reduce(0, +) / Double(diffs.count)
        } else if prev > 0 {
            jitterMs = abs(avgPing - prev)
        }
        appendSample(&pingHistory, value: avgPing)
    }

    private func measureDownload(kb: Int) async {
        guard let url = URL(string: "\(baseURL)/api/net-probe?kb=\(kb)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let elapsed = max(0.005, CFAbsoluteTimeGetCurrent() - t0)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let mbps = (Double(data.count) * 8.0) / elapsed / 1_000_000.0
            downloadMbps = mbps
            appendSample(&speedHistory, value: mbps)
        } catch {}
    }

    private func measureUpload(kb: Int) async {
        guard let url = URL(string: "\(baseURL)/api/net-up") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data(repeating: 0x4D, count: kb * 1024)
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await URLSession.shared.upload(for: req, from: payload)
            let elapsed = max(0.005, CFAbsoluteTimeGetCurrent() - t0)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            uploadMbps = (Double(payload.count) * 8.0) / elapsed / 1_000_000.0
        } catch {}
    }

    private func appendSample(_ arr: inout [Double], value: Double) {
        arr.append(value)
        if arr.count > 24 {
            arr.removeFirst(arr.count - 24)
        }
    }

    var capacityScore: Double {
        let dlScore = min(max(downloadMbps / 50.0, 0), 1.0) * 55.0
        let pingPenalty = min(max((pingMs - 20.0) / 180.0, 0), 1.0) * 20.0
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        let hwScore = min(max(ramGB / 8.0, 0.35), 1.0) * 25.0 + 20.0
        return min(max(dlScore + hwScore - pingPenalty, 15.0), 100.0)
    }
}

struct DeviceMonitorView: View {
    @StateObject private var vm = DeviceMonitorViewModel()
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var spatial = AudioSpatialEngine.shared
    @Environment(\.colorScheme) private var colorScheme

    private let machineId = HardwareModelMapper.machineIdentifier()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerActionBar
                kpiGrid
                stockChartsSection
                capacityCard
                hardwareSpecCard
                networkSpecCard
            }
            .padding(16)
            .padding(.bottom, 76)
        }
        .background(ManiFlixTheme.background(scheme: colorScheme).ignoresSafeArea())
        .navigationTitle("Kiểm tra mạng & Thiết bị")
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveSoftScrollEdge()
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            vm.start()
        }
        .onDisappear {
            vm.stop()
        }
    }

    private var headerActionBar: some View {
        HStack(spacing: 10) {
            Button {
                vm.isLiveProbeEnabled.toggle()
                Haptics.impact(.light)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isLiveProbeEnabled ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                    Text("Live Probe: \(vm.isLiveProbeEnabled ? "BẬT" : "TẮT")")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .adaptiveGlassCapsule(interactive: true)

            Spacer()

            Button {
                Task { await vm.runSpeedtestNow() }
            } label: {
                HStack(spacing: 6) {
                    if vm.isRunningSpeedtest {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(.white)
                    } else {
                        Image(systemName: "speedometer")
                            .font(.caption.weight(.bold))
                    }
                    Text(vm.isRunningSpeedtest ? "Đang đo..." : "Đo Speedtest Ngay")
                        .font(.caption.weight(.bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(prefs.currentAccentColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vm.isRunningSpeedtest)
        }
    }

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            kpiCard(
                title: "Tải xuống",
                value: vm.downloadMbps > 0 ? String(format: "%.1f Mbps", vm.downloadMbps) : "—",
                sub: "Đỉnh server: \(String(format: "%.1f Mbps", vm.peakRxMbps))",
                icon: "arrow.down.circle.fill",
                tint: prefs.currentAccentColor
            )
            kpiCard(
                title: "Tải lên",
                value: vm.uploadMbps > 0 ? String(format: "%.1f Mbps", vm.uploadMbps) : "—",
                sub: "Server TX: \(String(format: "%.1f Mbps", vm.txMbps))",
                icon: "arrow.up.circle.fill",
                tint: .blue
            )
            kpiCard(
                title: "Độ trễ (Ping)",
                value: vm.pingMs > 0 ? String(format: "%.0f ms", vm.pingMs) : "—",
                sub: "Jitter: \(String(format: "%.1f ms", vm.jitterMs))",
                icon: "bolt.horizontal.circle.fill",
                tint: .orange
            )
            kpiCard(
                title: "RAM Ứng dụng",
                value: String(format: "%.0f MB", vm.appRAMMB),
                sub: String(format: "Tổng máy: %.1f GB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0),
                icon: "memorychip",
                tint: .green
            )
        }
    }

    private func kpiCard(title: String, value: String, sub: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(tint)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                Spacer()
            }
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                .lineLimit(1)
            Text(sub)
                .font(.caption2)
                .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassCard(cornerRadius: 12)
    }

    private var stockChartsSection: some View {
        VStack(spacing: 12) {
            stockChartCard(
                title: "Tốc độ tải thực tế (Mbps)",
                latestText: vm.downloadMbps > 0 ? String(format: "%.1f Mbps", vm.downloadMbps) : "Chờ mẫu...",
                values: vm.speedHistory,
                lineColor: prefs.currentAccentColor
            )
            stockChartCard(
                title: "Biến động độ trễ Ping (ms)",
                latestText: vm.pingMs > 0 ? String(format: "%.0f ms", vm.pingMs) : "Chờ mẫu...",
                values: vm.pingHistory,
                lineColor: .orange
            )
        }
    }

    private func stockChartCard(title: String, latestText: String, values: [Double], lineColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                Spacer()
                Text(latestText)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundColor(lineColor)
            }

            LiveStockLineChart(values: values, lineColor: lineColor, gridColor: ManiFlixTheme.cardStroke(colorScheme))
                .frame(height: 94)
        }
        .padding(12)
        .adaptiveGlassCard(cornerRadius: 14)
    }

    private var capacityCard: some View {
        let score = vm.capacityScore
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sức Tải Tối Đa Của Máy & Mạng")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                Spacer()
                Text("\(Int(score))%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundColor(prefs.currentAccentColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ManiFlixTheme.cardFill(colorScheme))
                        .frame(height: 8)
                    Capsule()
                        .fill(prefs.currentAccentColor)
                        .frame(width: max(12, geo.size.width * CGFloat(score / 100.0)), height: 8)
                }
            }
            .frame(height: 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tierPill("720p HD", active: vm.downloadMbps >= 3 || vm.downloadMbps == 0)
                    tierPill("1080p60", active: vm.downloadMbps >= 10)
                    tierPill("2K/4K HDR", active: vm.downloadMbps >= 25)
                    tierPill("Spatial Audio", active: spatial.isSpatialEligibleRoute || spatial.isHeadphoneOutput)
                }
            }
        }
        .padding(14)
        .adaptiveGlassCard(cornerRadius: 14)
    }

    private func tierPill(_ title: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(active ? .white : ManiFlixTheme.secondaryText(colorScheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? prefs.currentAccentColor : ManiFlixTheme.cardFill(colorScheme))
        .clipShape(Capsule())
    }

    private var hardwareSpecCard: some View {
        let disk = HardwareModelMapper.diskStatsGB()
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        let pxW = Int(bounds.width * scale)
        let pxH = Int(bounds.height * scale)
        let hz = UIScreen.main.maximumFramesPerSecond
        let thermalText: String = {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return "Bình thường"
            case .fair: return "Hơi ấm"
            case .serious: return "Nóng"
            case .critical: return "Quá nhiệt"
            @unknown default: return "Không rõ"
            }
        }()
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryText = batteryLevel >= 0 ? "\(Int(batteryLevel * 100))%" : "Không rõ"
        let hasPlugIns = FileManager.default.fileExists(atPath: Bundle.main.bundlePath + "/PlugIns")
        let isLegacy = (Bundle.main.bundleIdentifier ?? "").contains(".legacy")
        let variantText = "\(isLegacy ? "Legacy iOS 15+" : "iOS 17+ Liquid Glass") • \(hasPlugIns ? "Full + Widget" : "NoPlug")"

        return VStack(alignment: .leading, spacing: 10) {
            Text("Thông số thiết bị")
                .font(.subheadline.weight(.bold))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))

            specRow("Thiết bị", HardwareModelMapper.friendlyName(for: machineId))
            specRow("Hệ điều hành", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            specRow("CPU", "\(ProcessInfo.processInfo.activeProcessorCount)/\(ProcessInfo.processInfo.processorCount) nhân")
            specRow("RAM", String(format: "%.0f MB app / %.2f GB máy", vm.appRAMMB, Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0))
            specRow("Bộ nhớ trống", String(format: "%.1f / %.1f GB", disk.freeGB, disk.totalGB))
            specRow("Màn hình", "\(pxW)×\(pxH) px • \(hz) Hz")
            specRow("Nhiệt độ & Pin", "\(thermalText) • \(batteryText)")
            specRow("Đầu ra âm thanh", spatial.outputRouteName)
            specRow("Biến thể IPA", variantText)
        }
        .padding(14)
        .adaptiveGlassCard(cornerRadius: 14)
    }

    private var networkSpecCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thông số mạng & Máy chủ")
                .font(.subheadline.weight(.bold))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))

            specRow("Trạng thái API", vm.isConnected ? "Trực tuyến" : "Đang kết nối...")
            specRow("Máy chủ", "phim.maniakov.bond")
            specRow("Server RX / TX", String(format: "%.2f / %.2f Mbps", vm.rxMbps, vm.txMbps))
            specRow("CPU / RAM Server", String(format: "%.1f%% / %.1f%%", vm.serverCpuPct, vm.serverMemPct))
            specRow("Lưu lượng", String(format: "%.1f req/s • Uptime %ds", vm.reqPerSec, vm.uptimeSec))
        }
        .padding(14)
        .adaptiveGlassCard(cornerRadius: 14)
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LiveStockLineChart: View {
    let values: [Double]
    let lineColor: Color
    let gridColor: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            guard w > 4, h > 4 else { return }

            for frac in [0.25, 0.5, 0.75] {
                let y = h * frac
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: w, y: y))
                context.stroke(grid, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
            }

            let pts = values.isEmpty ? [0.0, 0.0] : (values.count == 1 ? [values[0], values[0]] : values)
            let maxVal = max(pts.max() ?? 1.0, 1.0)
            let minVal = max(0.0, (pts.min() ?? 0.0) * 0.8)
            let span = max(maxVal - minVal, 0.5)

            var line = Path()
            var fill = Path()

            for (idx, val) in pts.enumerated() {
                let x = w * CGFloat(idx) / CGFloat(max(pts.count - 1, 1))
                let norm = CGFloat((val - minVal) / span)
                let y = h - (norm * (h - 12) + 6)
                let pt = CGPoint(x: x, y: y)
                if idx == 0 {
                    line.move(to: pt)
                    fill.move(to: CGPoint(x: x, y: h))
                    fill.addLine(to: pt)
                } else {
                    line.addLine(to: pt)
                    fill.addLine(to: pt)
                }
            }

            fill.addLine(to: CGPoint(x: w, y: h))
            fill.closeSubpath()

            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [lineColor.opacity(0.32), lineColor.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: h)
                )
            )
            context.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
