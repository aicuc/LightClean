import SwiftUI
import AppKit

@MainActor
final class Cleaner: ObservableObject {
    @Published var permanent = false
    @Published var diskRefresh = 0
    @Published var skipped = 0
    @Published var kind: ScanKind = .deep
    @Published var items: [ScanItem] = []
    @Published var selected: Set<String> = []
    @Published var scanning = false
    @Published var cleaning = false
    @Published var scanned = false
    @Published var status = "准备好，给 Mac 腾出一点空间。"
    @Published var query = ""
    @Published var category = "全部分类"
    @Published var oldOnly = false
    @Published var folder: URL?
    @Published var root: URL?
    @Published var showConfirm = false
    @Published var detail: ScanItem?
    @Published var error: String?
    private var work: Task<ScanReport, Never>?
    var total: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var chosen: [ScanItem] { items.filter { selected.contains($0.id) && !$0.reviewOnly } }
    var selectedBytes: Int64 { chosen.reduce(0) { $0 + $1.bytes } }
    var categories: [String] { ["全部分类"] + Set(items.map(\.category)).sorted() }
    var visible: [ScanItem] { items.filter { item in
        (query.isEmpty || item.url.path.localizedCaseInsensitiveContains(query) || item.category.localizedCaseInsensitiveContains(query)) &&
        (category == "全部分类" || category == item.category) && (!oldOnly || (item.ageDays ?? -1) >= 30)
    } }
    var selectable: [ScanItem] { visible.filter { !$0.reviewOnly } }
    func switchKind(_ value: ScanKind) { guard !scanning && !cleaning else { return }; kind = value; items = []; selected = []; skipped = 0; scanned = false; query = ""; category = "全部分类"; oldOnly = false; status = "准备扫描\(value.rawValue)。" }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "扫描此文件夹"
        if panel.runModal() == .OK { folder = panel.url; scan() }
    }
    func scan() {
        guard !scanning && !cleaning else { return }
        if (kind == .large || kind == .projects) && folder == nil { chooseFolder(); return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let enhanced = [.deep, .installers, .support, .wechat].contains(kind)
        let location = (kind == .large || kind == .projects) ? folder! : enhanced ? home : home.appendingPathComponent(kind == .caches ? "Library/Caches" : "Library/Logs")
        root = location; items = []; selected = []; skipped = 0; category = "全部分类"; scanned = false; scanning = true; status = "正在扫描 \(location.path)…"
        let currentKind = kind
        let task = Task.detached(priority: .utility) {
            if currentKind == .wechat { return SpecialScanner.wechat(home: home) }
            if currentKind == .projects { return SpecialScanner.projects(root: location) }
            if enhanced { return DeepScanner.scan(home: home, kind: currentKind) }
            var report = DiskScanner.scan(root: location, kind: currentKind)
            report.items = report.items.map { item in
                var item = item; item.category = currentKind.rawValue
                item.note = currentKind == .large ? "这是个人文件，大小不代表可以丢弃。请打开文件核对用途；删除后需要从废纸篓恢复。" : currentKind == .caches ? "应用生成的缓存。退出相关应用后再清理，可能需要重新下载资源或重建索引。目录会整体移入废纸篓。" : "运行诊断记录。清理会丢失历史排错信息；建议先退出相关应用。"
                item.cleanupRoot = location; return item
            }
            return report
        }
        work = task
        Task { let report = await task.value
            items = report.items; skipped = report.skipped; scanning = false; scanned = true; work = nil
            diskRefresh += 1
            status = "\(report.cancelled ? "已停止，显示部分结果" : "扫描完成") · \(report.items.count) 个项目" + (report.skipped > 0 ? " · \(report.skipped) 处不可访问或已跳过，可检查完全磁盘访问权限" : "")
        }
    }
    func cancel() { work?.cancel() }
    static func available() -> Int64 {
        Int64((try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity ?? 0)
    }
    var wechatRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.tencent.xinWeChat" || $0.executableURL?.lastPathComponent == "WeChat" }
    }
    func trash() {
        guard !scanning && !cleaning, !chosen.isEmpty else { return }
        if kind == .wechat && wechatRunning { error = "请先退出微信，再清理媒体和缓存。聊天数据库不会被清理。"; return }
        let targets = chosen, mode = permanent, currentKind = kind
        let home = FileManager.default.homeDirectoryForCurrentUser
        let before = Self.available()
        cleaning = true
        Task {
            var removed: Set<String> = []; var failures: [String] = []; var processedBytes: Int64 = 0
            for (index, item) in targets.enumerated() {
                if currentKind == .wechat && wechatRunning { failures.append("微信已重新启动，后续项目停止清理。"); break }
                status = "正在\(mode ? "永久删除" : "移入废纸篓") \(index + 1)/\(targets.count)：\(item.url.lastPathComponent)"
                let failure: String? = await Task.detached(priority: .utility) {
                    SpecialScanner.clean(item, kind: currentKind, home: home, permanent: mode)
                }.value
                if let failure { failures.append(failure) } else { removed.insert(item.id); processedBytes += item.bytes }
            }
            items.removeAll { removed.contains($0.id) }; selected.subtract(removed); cleaning = false; diskRefresh += 1
            let delta = Self.available() - before
            status = "已\(mode ? "永久删除" : "移入废纸篓") \(removed.count) 项（逻辑大小 \(formatBytes(processedBytes))）。" +
                (mode ? "磁盘可用空间变化：\(delta >= 0 ? "+" : "−")\(formatBytes(abs(delta)))，会受系统活动影响。" : "尚未永久释放；可在 Finder 废纸篓恢复或自行清空。")
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
        }
    }

}

@main
struct LightCleanApp: App {
    @StateObject private var model = Cleaner()
    var body: some Scene {
        WindowGroup("轻舟清理") { ContentView().environmentObject(model).frame(minWidth: 980, minHeight: 680) }
            .windowStyle(.hiddenTitleBar).defaultSize(width: 1100, height: 760)
        Settings { VStack(alignment: .leading, spacing: 16) { Text("轻舟清理").font(.title); Text("所有扫描均在本机进行。可选择移入废纸篓，或经单独确认永久删除所选项目。"); Text("部分目录可能需要在系统设置 → 隐私与安全性中授予访问权限。") }.padding(30).frame(width: 430) }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: Cleaner
    private let accent = Color(red: 0.13, green: 0.48, blue: 0.39)
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 24) {
                HStack { VStack(alignment: .leading, spacing: 5) { Text("让空间，重新轻盈。").font(.system(size: 29, weight: .semibold, design: .rounded)); Text("看清每一份占用，再决定如何整理。").foregroundStyle(.secondary) }; Spacer(); Label("本机处理", systemImage: "lock.shield").font(.caption).foregroundStyle(accent).padding(10).background(accent.opacity(0.08), in: Capsule()) }
                overview
                HStack { VStack(alignment: .leading, spacing: 5) { Text(m.kind.rawValue).font(.title2.bold()); Text(description).foregroundStyle(.secondary).font(.callout) }; Spacer(); if m.kind == .large || m.kind == .projects { Button("选择文件夹…") { m.chooseFolder() }.disabled(m.scanning || m.cleaning) }; Button { m.scanning ? m.cancel() : m.scan() } label: { Label(m.scanning ? "停止扫描" : m.scanned ? "重新扫描" : "开始扫描", systemImage: m.scanning ? "stop.fill" : "viewfinder").padding(.horizontal, 6).padding(.vertical, 4) }.buttonStyle(.borderedProminent).tint(accent).disabled(m.cleaning) }
                HStack {
                    Picker("清理方式", selection: $m.permanent) { Text("移入废纸篓 · 可恢复").tag(false); Text("永久删除 · 立即腾空间").tag(true) }.frame(maxWidth: 420).disabled(m.cleaning || m.scanning)
                    Spacer()
                    Button("完全磁盘访问设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }.font(.caption)
                }
                if m.skipped > 0 {
                    Label("部分位置不可访问或被安全规则跳过。微信专项若无结果，请在完全磁盘访问中添加轻舟清理，退出重开后扫描。", systemImage: "exclamationmark.shield").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                results
                HStack { VStack(alignment: .leading, spacing: 4) { Text(m.status).font(.caption).foregroundStyle(.secondary).lineLimit(3); if !m.selected.isEmpty { Text("已选 \(m.selected.count) 项 · \(formatBytes(m.selectedBytes))").font(.callout.bold()) } }; Spacer(); Button { m.showConfirm = true } label: { Label(m.cleaning ? "正在处理…" : m.permanent ? "永久删除所选" : "移入废纸篓", systemImage: "trash").padding(5) }.buttonStyle(.borderedProminent).tint(accent).disabled(m.selected.isEmpty || m.scanning || m.cleaning) }
            }.padding(30).background(Color(red: 0.97, green: 0.98, blue: 0.97))
        }.tint(accent).preferredColorScheme(.light)
        .confirmationDialog("\(m.permanent ? "永久删除" : "移入废纸篓") \(m.chosen.count) 个项目（\(formatBytes(m.selectedBytes))）？", isPresented: $m.showConfirm, titleVisibility: .visible) {
            Button(m.permanent ? "确认永久删除，无法从废纸篓恢复" : "移入废纸篓", role: .destructive) { m.trash() }
            Button("取消", role: .cancel) {}
        } message: {
            Text((m.kind == .wechat ? "请退出微信。只处理已选媒体/缓存，保留聊天数据库；相关本地图片、视频和文件可能无法再打开。" : "请退出相关应用并停止构建任务，核对所选项目。") + (m.permanent ? "所选内容将直接删除，不经过废纸篓，无法从废纸篓恢复。" : "目录会整体移入废纸篓，通常不会立即释放空间。"))
        }

        .sheet(item: $m.detail) { item in
            VStack(alignment: .leading, spacing: 18) {
                HStack { Image(systemName: item.reviewOnly ? "eye" : "doc.text.magnifyingglass").foregroundStyle(accent); Text(item.url.lastPathComponent).font(.title2.bold()).textSelection(.enabled) }
                Text(item.category).font(.headline).foregroundStyle(accent)
                Text(item.note).fixedSize(horizontal: false, vertical: true).lineSpacing(5)
                Divider()
                LabeledContent("占用", value: formatBytes(item.bytes))
                LabeledContent("最后修改", value: item.modified?.formatted(date: .abbreviated, time: .shortened) ?? "未知")
                Text("修改时间不代表最近使用时间。文件大小为逻辑大小；共享、压缩文件的实际可释放空间可能不同。").font(.caption).foregroundStyle(.secondary)
                Text(item.url.path).font(.caption.monospaced()).textSelection(.enabled)
                HStack { Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }; Spacer(); Button("完成") { m.detail = nil }.keyboardShortcut(.defaultAction) }
            }.padding(28).frame(width: 560)
        }
        .alert("清理提示", isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) { Button("好") { m.error = nil } } message: { Text(m.error ?? "") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) { Image(systemName: "leaf.circle.fill").font(.system(size: 32)).foregroundStyle(accent); VStack(alignment: .leading) { Text("轻舟清理").font(.headline); Text("LIGHTCLEAN").font(.system(size: 9, weight: .medium, design: .rounded)).tracking(2).foregroundStyle(.secondary) } }.padding(.top, 20)
            VStack(alignment: .leading, spacing: 8) { Text("空间整理").font(.caption).foregroundStyle(.secondary).padding(.bottom, 5); ForEach(ScanKind.allCases, id: \.self) { kind in Button { m.switchKind(kind) } label: { HStack(spacing: 12) { Image(systemName: kind.symbol).frame(width: 20); Text(kind.rawValue); Spacer(); if m.kind == kind { Circle().fill(accent).frame(width: 6, height: 6) } }.padding(12).background(m.kind == kind ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(m.kind == kind ? accent : .primary) }.buttonStyle(.plain).accessibilityLabel(kind.rawValue).disabled(m.scanning || m.cleaning) } }
            Spacer()
            VStack(alignment: .leading, spacing: 8) { Image(systemName: "hand.raised").font(.title2).foregroundStyle(accent); Text("清理由你掌控").font(.callout.bold()); Text("逐项查看，自主选择。\n不会自动删除任何文件。").font(.caption).foregroundStyle(.secondary).lineSpacing(4) }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            Text("为你的 Mac，留一点余地。 ").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(20).frame(width: 200).background(Color(red: 0.91, green: 0.94, blue: 0.92))
    }
    var description: String { switch m.kind { case .wechat: "只清理新版微信的缓存与媒体附件；保留聊天数据库、联系人、收藏和配置。"; case .projects: "选择项目或工作目录，最多向下检查 5 层 Swift 项目 .build，保留源码和安装包。"; case .caches: "查看当前用户的应用缓存，建议退出相关应用后再清理。"; case .logs: "检查当前用户的运行日志，保留仍需排查问题的记录。"; case .large: "选择文件夹，查找超过 100 MB 的文件。"; case .deep: "按清理规则检查应用与开发缓存，查看详情后再选择。"; case .installers: "查找下载目录中的安装包和压缩文件，需核对内容。"; case .support: "查看应用资料占用；仅分析，不直接清理。" } }
    var overview: some View {
        let _ = m.diskRefresh
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let available = Int64(values?.volumeAvailableCapacity ?? 0)
        let fraction = total > 0 ? min(1, max(0, Double(total - available) / Double(total))) : 0
        return HStack(spacing: 26) {
            ZStack { Circle().stroke(accent.opacity(0.1), lineWidth: 13); Circle().trim(from: 0, to: fraction).stroke(accent, style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(-90)); VStack(spacing: 2) { Text(total > 0 ? "\(Int(fraction * 100))%" : "—").font(.system(size: 25, weight: .semibold, design: .rounded)); Text("已使用").font(.caption2).foregroundStyle(.secondary) } }.frame(width: 105, height: 105)
            VStack(alignment: .leading, spacing: 10) { Label("Mac 磁盘", systemImage: "internaldrive").font(.headline); Text("\(formatBytes(available)) 可用").font(.system(size: 24, weight: .medium, design: .rounded)); Text("总容量 \(formatBytes(total)) · 当前可用空间，不含预计可回收容量").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Rectangle().fill(accent.opacity(0.12)).frame(width: 1, height: 75)
            VStack(alignment: .leading, spacing: 9) { Text(m.kind == .support ? "数据占用" : "本次发现").foregroundStyle(.secondary); Text(m.scanned ? formatBytes(m.total) : "等待扫描").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(accent); Text(m.scanned ? "请查看后选择需要清理的项目" : "从左侧选择一种整理方式").font(.caption).foregroundStyle(.secondary) }
        }.padding(25).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
    var results: some View {
        VStack(spacing: 0) {
            HStack { Toggle("选择当前结果", isOn: Binding(get: { !m.selectable.isEmpty && m.selectable.allSatisfy { m.selected.contains($0.id) } }, set: { value in for item in m.selectable { if value { m.selected.insert(item.id) } else { m.selected.remove(item.id) } } })).disabled(m.scanning || m.cleaning || m.selectable.isEmpty); Spacer(); Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索名称或路径", text: $m.query).textFieldStyle(.plain).frame(width: 160) }.font(.caption).padding(15)
            HStack {
                Picker("分类", selection: $m.category) { ForEach(m.categories, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 240)
                Toggle("仅看 30 天未修改", isOn: $m.oldOnly).toggleStyle(.checkbox).help("修改时间不是最近使用时间，也不能证明文件无用")
                Spacer()
                Text("\(m.visible.count) 项").foregroundStyle(.secondary)
            }.font(.caption).padding(.horizontal, 15).padding(.bottom, 12)
            Divider()
            if m.scanning { VStack(spacing: 16) { ProgressView(); Text("正在计算文件大小…").font(.headline); Text("文件较多时可能需要一些时间").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if m.visible.isEmpty { VStack(spacing: 13) { Image(systemName: m.scanned ? "checkmark.seal" : "sparkle.magnifyingglass").font(.system(size: 38, weight: .light)).foregroundStyle(accent); Text(m.scanned ? (m.query.isEmpty ? (m.skipped > 0 ? "扫描范围受限，请检查访问权限" : "没有发现符合条件的项目") : "没有匹配的结果") : "从一次扫描开始").font(.headline); Text(m.scanned ? "扫描仅覆盖可访问的位置；未扫描的位置不代表没有占用。" : "只读取文件信息，扫描不会更改文件。").font(.callout).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ScrollView { LazyVStack(spacing: 0) { ForEach(m.visible) { item in HStack(spacing: 12) { Toggle("选择 \(item.url.lastPathComponent)", isOn: Binding(get: { m.selected.contains(item.id) }, set: { if $0 { m.selected.insert(item.id) } else { m.selected.remove(item.id) } })).labelsHidden().disabled(m.cleaning || item.reviewOnly); Image(systemName: m.kind.symbol).font(.title3).foregroundStyle(accent).frame(width: 34, height: 36).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8)); VStack(alignment: .leading, spacing: 4) { HStack { Text(item.category == "Swift 项目构建缓存" ? item.url.deletingLastPathComponent().lastPathComponent + " / .build" : item.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1); if item.reviewOnly { Text("仅分析").font(.caption2).foregroundStyle(.orange) } };
                        Text(item.category + (item.ageDays.map { " · \($0) 天前修改" } ?? "")).font(.caption2).foregroundStyle(accent); Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }; Spacer(); Text(formatBytes(item.bytes)).font(.callout.monospacedDigit()); Button { m.detail = item } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).help("用途与清理影响"); Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(.plain).help("在 Finder 中显示") }.padding(.horizontal, 15).padding(.vertical, 11); Divider().padding(.leading, 55) } } } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 16)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
