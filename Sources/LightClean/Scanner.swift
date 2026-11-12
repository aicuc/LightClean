import Foundation

enum ScanKind: String, CaseIterable, Sendable {
    case wechat = "微信专项", projects = "项目构建缓存", deep = "深度清理", caches = "应用缓存", logs = "运行日志", installers = "安装包与归档", support = "应用数据分析", large = "大文件"
    var symbol: String { switch self { case .wechat: "bubble.left.and.bubble.right"; case .projects: "hammer"; case .caches: "shippingbox"; case .logs: "doc.text"; case .large: "externaldrive"; case .deep: "sparkles"; case .installers: "opticaldisc"; case .support: "chart.bar.xaxis" } }
}
struct ScanItem: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let bytes: Int64
    let modified: Date?
    var category = "待核对项目"
    var note = "请核对文件内容与用途后再清理。"
    var reviewOnly = false
    var cleanupRoot: URL? = nil
    var ageDays: Int? { modified.map { max(0, Int(Date().timeIntervalSince($0) / 86400)) } }
}
struct ScanReport: Sendable { var items: [ScanItem] = []; var skipped = 0; var cancelled = false }
struct ScanPolicy {
    static func permitted(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        guard path.hasPrefix(base + "/"), url.resolvingSymlinksInPath().path == path else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let forbidden = ["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private", home + "/.Trash"]
        return !forbidden.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
struct DiskScanner {
    static let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
    static func measure(_ url: URL) -> (bytes: Int64, skipped: Int) {
        if Task<Never, Never>.isCancelled { return (0, 0) }
        guard let info = try? url.resourceValues(forKeys: Set(keys)), info.isSymbolicLink != true else { return (0, 1) }
        if info.isRegularFile == true { return (Int64(info.fileSize ?? 0), 0) }
        guard info.isDirectory == true else { return (0, 0) }
        do {
            var bytes: Int64 = 0, skipped = 0
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys) {
                if Task<Never, Never>.isCancelled { break }
                let result = measure(child); bytes += result.bytes; skipped += result.skipped
            }
            return (bytes, skipped)
        } catch { return (0, 1) }
    }
    static func scan(root: URL, kind: ScanKind) -> ScanReport {
        var report = ScanReport()
        let fm = FileManager.default
        func size(_ url: URL) -> Int64 {
            let measured = measure(url); report.skipped += measured.skipped; return measured.bytes
        }
        if kind == .large || kind == .installers {
            let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in report.skipped += 1; return true })
            if enumerator == nil { report.skipped += 1 }
            while let url = enumerator?.nextObject() as? URL {
                if Task<Never, Never>.isCancelled { break }
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { report.skipped += 1; continue }
                if v.isSymbolicLink == true { report.skipped += 1; continue }
                guard ScanPolicy.permitted(url, root: root), !SpecialScanner.protected(url, home: fm.homeDirectoryForCurrentUser) else {
                    if v.isDirectory == true { enumerator?.skipDescendants() }
                    report.skipped += 1; continue
                }
                if v.isRegularFile == true, let bytes = v.fileSize, (kind == .installers ? DeepScanner.isArchive(url) : bytes >= 100_000_000) { report.items.append(ScanItem(url: url, bytes: Int64(bytes), modified: v.contentModificationDate)) }
            }
        } else {
            do {
                for url in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) {
                    if Task<Never, Never>.isCancelled { break }
                    guard ScanPolicy.permitted(url, root: root) else { report.skipped += 1; continue }
                    let bytes = size(url)
                    if bytes > 0 { report.items.append(ScanItem(url: url, bytes: bytes, modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)) }
                }
            } catch { report.skipped += 1 }
        }
        report.cancelled = Task<Never, Never>.isCancelled
        report.items.sort { $0.bytes > $1.bytes }
        return report
    }
}
func formatBytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
