import Foundation

struct CleanupRule: Sendable {
    let path: String
    let title: String
    let note: String
}
struct DeepScanner {
    static let rules: [CleanupRule] = [
        .init(path: "Library/Developer/Xcode/DerivedData", title: "Xcode 构建产物", note: "项目索引、中间产物和构建缓存。请退出 Xcode；清理后首次打开项目及构建会更慢，依赖可能需要重新下载。不会扫描 Archives。"),
        .init(path: ".npm/_cacache", title: "npm 下载缓存", note: "已下载的 npm 包缓存。退出 npm 安装与构建任务后再清理；之后安装可能需要联网重新下载。不包括 npm 配置和全局安装包。"),
        .init(path: ".npm/_npx", title: "npx 临时执行缓存", note: "临时下载的 npx 工具。停止 npm/npx 任务后再清理；下次执行需重新下载。"),
        .init(path: "Library/Caches/pip", title: "pip 缓存", note: "Python 下载和编译缓存；后续安装可能重新下载。"),
        .init(path: ".npm/_logs", title: "npm 历史日志", note: "npm 安装与执行日志。清理后无法查看这些历史诊断记录。"),
        .init(path: ".gradle/caches", title: "Gradle 构建缓存", note: "Gradle 依赖与构建缓存。请停止 Gradle 和 Android Studio 构建；下次构建可能需要联网和较长时间。"),
        .init(path: ".gradle/wrapper/dists", title: "Gradle 分发包", note: "下载的 Gradle 版本。清理后对应版本需重新下载；离线构建可能受影响。"),
        .init(path: ".cargo/registry/cache", title: "Cargo 下载缓存", note: "Rust registry 已下载的压缩包。清理后可能需要联网重新下载；不包括源码和已安装的可执行程序。"),
        .init(path: ".cache/pip", title: "pip 下载缓存", note: "此默认位置中的 Python 安装缓存。清理后可能重新下载或编译依赖。自定义缓存位置不会自动扫描。"),
        .init(path: ".cache/uv", title: "uv 缓存分析", note: "uv 缓存可能通过链接与环境共享文件；请使用 uv cache clean 管理。这里只分析占用，不提供直接清理。")
    ]
    static let archiveExtensions: Set<String> = ["dmg", "pkg", "iso", "zip", "7z", "rar", "tar", "gz", "bz2", "xz"]
    static func isArchive(_ url: URL) -> Bool { archiveExtensions.contains(url.pathExtension.lowercased()) }
    static func allowedTrash(_ url: URL, home: URL) -> Bool {
        for path in ["Library/Caches", "Library/Logs"] + rules.filter({ $0.path != ".cache/uv" }).map(\.path) {
            let root = home.appendingPathComponent(path)
            if url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL && ScanPolicy.permitted(url, root: root) { return true }
        }
        let downloads = home.appendingPathComponent("Downloads")
        return isArchive(url) && ScanPolicy.permitted(url, root: downloads) && (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }
    static func scan(home: URL, kind: ScanKind) -> ScanReport {
        var result = ScanReport()
        func append(root: URL, scanKind: ScanKind, title: String, note: String, readOnly: Bool = false) {
            if Task<Never, Never>.isCancelled { return }
            do { _ = try root.resourceValues(forKeys: [.isDirectoryKey]) }
            catch {
                let error = error as NSError
                if !(error.domain == NSCocoaErrorDomain && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError)) { result.skipped += 1 }
                return
            }
            var report = DiskScanner.scan(root: root, kind: scanKind)
            report.items = report.items.map { item in
                var item = item; item.category = title; item.note = note; item.reviewOnly = readOnly; item.cleanupRoot = root; return item
            }
            result.items += report.items; result.skipped += report.skipped
        }
        switch kind {
        case .deep:
            append(root: home.appendingPathComponent("Library/Caches"), scanKind: .caches, title: "应用缓存", note: "应用生成的缓存目录。退出相关应用后再清理，可能需要重新下载离线资源、重新登录或重建索引。目录会整体移入废纸篓。")
            append(root: home.appendingPathComponent("Library/Logs"), scanKind: .logs, title: "运行日志", note: "应用运行记录。清理会丢失历史排错信息；建议先退出相关应用。")
            for rule in rules where !rule.path.hasPrefix("Library/Caches/") {
                append(root: home.appendingPathComponent(rule.path), scanKind: .caches, title: rule.title, note: rule.note, readOnly: rule.path == ".cache/uv")
            }
        case .installers:
            append(root: home.appendingPathComponent("Downloads"), scanKind: .installers, title: "安装包与归档", note: "下载目录中的安装包或压缩文件。这只是按扩展名识别，不代表已安装、重复或没有价值；可能包含唯一的个人资料，请先打开核对。")
        case .support:
            append(root: home.appendingPathComponent("Library/Containers"), scanKind: .caches, title: "应用沙盒 · 仅分析", note: "包含微信等应用的数据。聊天记录、数据库和个人资料不能按目录整体清理；微信媒体请使用微信专项。", readOnly: true)
            append(root: home.appendingPathComponent("Library/Application Support"), scanKind: .caches, title: "应用数据 · 仅分析", note: "这里可能保存账号、数据库、聊天记录、模型、存档和离线资料。无法仅凭名称判断它是否为卸载残留；请通过对应应用管理数据。这里只提供占用分析与 Finder 定位。", readOnly: true)
        default: break
        }
        result.cancelled = Task<Never, Never>.isCancelled
        result.items.sort { $0.bytes > $1.bytes }
        return result
    }
}
