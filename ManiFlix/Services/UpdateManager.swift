import Foundation
import Combine

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var config: AppVersionResponse?
    @Published var showSoftPrompt = false
    @Published var showForceBlocker = false
    @Published var isChecking = false
    @Published var lastCheckNote: String = ""

    private let snoozeUntilKey = "update.softSnoozeUntil"

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.3"
    }

    var currentBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "5"
    }

    var displayVersion: String {
        "\(currentVersion) (\(currentBuild))"
    }

    func checkForUpdates(manual: Bool = false) async {
        isChecking = true
        defer { isChecking = false }
        do {
            let remote = try await ManiFlixAPI.shared.fetchAppVersion()
            self.config = remote

            let mustForceByMin = isVersion(currentVersion, lowerThan: remote.minRequiredVersion ?? "0.0.0")
            let isForced = (remote.forceUpdate ?? false) || (remote.mode == "force") || mustForceByMin
            let hasNewer = isVersion(currentVersion, lowerThan: remote.latestVersion)

            if isForced && (hasNewer || mustForceByMin || (remote.forceUpdate ?? false)) {
                showSoftPrompt = false
                showForceBlocker = true
                lastCheckNote = "Yêu cầu cập nhật bắt buộc lên v\(remote.latestVersion)"
                return
            }

            if hasNewer {
                if manual {
                    showSoftPrompt = true
                } else {
                    let snoozedUntil = UserDefaults.standard.double(forKey: snoozeUntilKey)
                    if Date().timeIntervalSince1970 >= snoozedUntil {
                        showSoftPrompt = true
                    }
                }
                lastCheckNote = "Đã có phiên bản mới v\(remote.latestVersion)"
            } else {
                lastCheckNote = "Bạn đang dùng bản mới nhất (v\(currentVersion))"
            }
        } catch {
            if manual {
                lastCheckNote = "Không thể kiểm tra cập nhật: \(error.localizedDescription)"
            }
        }
    }

    func snoozeSoftUpdateFor24Hours() {
        let until = Date().addingTimeInterval(24 * 60 * 60).timeIntervalSince1970
        UserDefaults.standard.set(until, forKey: snoozeUntilKey)
        showSoftPrompt = false
    }

    func recommendedVariantURL() -> URL? {
        let hasPlugIns = FileManager.default.fileExists(atPath: Bundle.main.bundlePath + "/PlugIns")
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let isLegacyBuild = bundleId.contains(".legacy")

        if let variants = config?.variants, !variants.isEmpty {
            if let exact = variants.first(where: { v in
                let wantLegacy = v.key.hasPrefix("legacy")
                let wantPlug = v.hasPlugins ?? !v.key.lowercased().contains("noplug")
                return wantLegacy == isLegacyBuild && wantPlug == hasPlugIns
            }) {
                return URL(string: exact.downloadUrl)
            }
        }
        return URL(string: config?.downloadUrl ?? "https://github.com/Maniakov132414/ManiFlix-iOS/releases/latest/download/ManiFlix.ipa")
    }

    private func isVersion(_ lhs: String, lowerThan rhs: String) -> Bool {
        let l = lhs.split(separator: ".").compactMap { Int($0) }
        let r = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(l.count, r.count)
        for i in 0..<count {
            let lv = i < l.count ? l[i] : 0
            let rv = i < r.count ? r[i] : 0
            if lv != rv {
                return lv < rv
            }
        }
        return false
    }
}
