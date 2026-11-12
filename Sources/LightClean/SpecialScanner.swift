import Foundation

enum SpecialScanner {
    static let wechatBase = "Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files"
    static let mediaPaths = ["cache", "temp", "msg/video", "msg/file", "msg/attach"]
    static func isWeChatTarget(_ url: URL, home: URL) -> Bool {
        let base = home.appendingPathComponent(wechatBase)
        guard ScanPolicy.permitted(url, root: base) else { return false }
        let parts = String(url.path.dropFirst(base.path.count + 1)).split(separator: "/").map(String.init)
        guard parts.count >= 3, !["all_users", "Backup", "old_backup", "WMPF", "finderlivemaker"].contains(parts[0]) else { return false }
        return mediaPaths.contains { relative in
            let root = base.appendingPathComponent(parts[0]).appendingPathComponent(relative)
            return url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
        }
    }
    static func protected(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = home.appendingPathComponent("Library/Containers/com.tencent.xinWeChat").path
        // The generic large-file picker must not bypass WeChat's dedicated boundary.
        if path == base || path.hasPrefix(base + "/") { return !isWeChatTarget(url, home: home) }
        return false
    }
    static func wechat(home: URL) -> ScanReport {
        var result = ScanReport()
        let base = home.appendingPathComponent(wechatBase)
        guard FileManager.default.fileExists(atPath: base.path) else { return result }
        do {
            for account in try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey]) {
                guard ScanPolicy.permitted(account, root: base), (try? account.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      FileManager.default.fileExists(atPath: account.appendingPathComponent("db_storage").path) else { continue }
                for relative in mediaPaths {
                    if Task<Never, Never>.isCancelled { result.cancelled = true; return result }
                    let root = account.appendingPathComponent(relative)
                    guard FileManager.default.fileExists(atPath: root.path) else { continue }
                    var report = DiskScanner.scan(root: root, kind: .caches)
                    report.items = report.items.filter { isWeChatTarget($0.url, home: home) }.map { item in
                        var item = item
                        item.category = relative == "cache" || relative == "temp" ? "微信缓存" : relative == "msg/video" ? "微信视频" : relative == "msg/file" ? "微信文件" : "微信图片与附件"
                        item.note = "需退出微信。只处理媒体或缓存目录，不触碰聊天数据库、联系人、收藏和登录配置。清理后对应本地图片、视频或文件可能无法再打开，不能保证重新下载。分组目录中的文件会整体处理。"
                        item.cleanupRoot = root; return item
                    }
                    result.items += report.items; result.skipped += report.skipped
                }
            }
        } catch { result.skipped += 1 }
        result.cancelled = Task<Never, Never>.isCancelled
        result.items.sort { $0.bytes > $1.bytes }; return result
    }
    static func projects(root: URL) -> ScanReport {
        var result = ScanReport()
        func walk(_ directory: URL, depth: Int) {
            guard depth <= 4, !Task<Never, Never>.isCancelled else { return }
            do {
                for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                    guard ScanPolicy.permitted(url, root: root), let info = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), info.isDirectory == true, info.isSymbolicLink != true else { continue }
                    if url.lastPathComponent == ".build", FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                        // Measure the build directory through its parent; no source tree recursion.
                        let measured = DiskScanner.measure(url)
                        result.skipped += measured.skipped
                        if measured.bytes > 0 { result.items.append(ScanItem(url: url, bytes: measured.bytes, modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, category: "Swift 项目构建缓存", note: "请停止此项目的构建并退出相关 IDE。这是 SwiftPM 的 .build，可重新构建；源码、Package.swift 和 dist 安装包会保留，首次重新构建较慢。", cleanupRoot: root)) }
                    } else if !url.lastPathComponent.hasPrefix("."), !["node_modules", "vendor", "dist", "Library"].contains(url.lastPathComponent), url.pathExtension != "app" { walk(url, depth: depth + 1) }
                }
            } catch { result.skipped += 1 }
        }
        walk(root, depth: 0); result.cancelled = Task<Never, Never>.isCancelled
        result.items.sort { $0.bytes > $1.bytes }; return result
    }
    static func clean(_ item: ScanItem, kind: ScanKind, home: URL, permanent: Bool) -> String? {
        do {
            guard allowed(item, kind: kind, home: home) else { throw CocoaError(.fileWriteNoPermission) }
            if permanent { try FileManager.default.removeItem(at: item.url) }
            else { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
            return nil
        } catch { return "\(item.url.lastPathComponent)：\(error.localizedDescription)" }
    }
    static func allowed(_ item: ScanItem, kind: ScanKind, home: URL) -> Bool {
        guard !item.reviewOnly, let root = item.cleanupRoot, ScanPolicy.permitted(item.url, root: root), !protected(item.url, home: home) else { return false }
        if kind == .wechat { return isWeChatTarget(item.url, home: home) }
        if kind == .projects {
            return item.url.lastPathComponent == ".build" && FileManager.default.fileExists(atPath: item.url.deletingLastPathComponent().appendingPathComponent("Package.swift").path)
        }
        return kind == .large || DeepScanner.allowedTrash(item.url, home: home)
    }
}
