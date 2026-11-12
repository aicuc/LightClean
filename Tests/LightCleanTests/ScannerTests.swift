import Foundation
@main struct ScannerTests {
    static func main() async throws {
        let tests = ScannerTests()
        try tests.testSizeAndSymbolicLinks()
        try tests.testScanRealFixture()
        try tests.testDeepRules()
        try tests.testSpecialRules()
        await tests.testCancellation()
        print("PASS: file sizes, symlinks, protected paths, path traversal, cancellation, deep rules, archive filters, read-only data, WeChat database protection, media deletion, project build cleanup")
    }
    func testSizeAndSymbolicLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 12345).write(to: child.appendingPathComponent("data"))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)
        // Resolve /var -> /private/var on macOS so fixture policy sees canonical paths.
        let canonical = root.resolvingSymlinksInPath()
        // Temporary directories are protected against cleanup, but scanning can measure entries.
        assertFalse(ScanPolicy.permitted(link, root: root))
        assertFalse(ScanPolicy.permitted(canonical, root: canonical))
        assertFalse(ScanPolicy.permitted(URL(fileURLWithPath: "/System/Library/test"), root: URL(fileURLWithPath: "/System")))
    }
    func testScanRealFixture() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lightclean-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 12345).write(to: child.appendingPathComponent("sample"))
        let report = DiskScanner.scan(root: root, kind: .caches)
        assertEqual(report.items.count, 1)
        assertEqual(report.items.first?.bytes, 12345)
        assert(ScanPolicy.permitted(child, root: root))
        assertFalse(ScanPolicy.permitted(root.appendingPathComponent("../outside"), root: root))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)
        assertFalse(ScanPolicy.permitted(link, root: root))
        assertEqual(DiskScanner.scan(root: root, kind: .caches).items.count, 1)
    }
    func testDeepRules() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lightclean-deep-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        func file(_ path: String) throws -> URL {
            let url = home.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 42).write(to: url)
            return url
        }
        let cache = try file(".npm/_cacache/entry")
        let protected = try file("Library/Application Support/Important/database")
        let archive = try file("Downloads/nested/Keep.ZIP")
        _ = try file("Downloads/photo.jpg")
        _ = try file("Library/Caches/test/blob")
        _ = try file(".cache/uv/archive/data")
        let deep = DeepScanner.scan(home: home, kind: .deep)
        assertEqual(deep.items.count, 3)
        assertEqual(deep.items.reduce(Int64(0)) { $0 + $1.bytes }, 126)
        assert(DeepScanner.allowedTrash(cache, home: home))
        assertFalse(DeepScanner.allowedTrash(protected, home: home))
        assertFalse(DeepScanner.allowedTrash(home.appendingPathComponent(".npm"), home: home))
        assertFalse(DeepScanner.allowedTrash(home.appendingPathComponent(".cache/uv/archive"), home: home))
        assertEqual(deep.items.filter { $0.reviewOnly }.count, 1)
        let data = DeepScanner.scan(home: home, kind: .support)
        assertEqual(data.items.count, 1)
        assert(data.items[0].reviewOnly)
        let downloads = DeepScanner.scan(home: home, kind: .installers)
        assertEqual(downloads.items.count, 1)
        assertEqual(downloads.items[0].url, archive)
        assert(DeepScanner.allowedTrash(archive, home: home))
        assertFalse(DeepScanner.allowedTrash(home.appendingPathComponent("Downloads/photo.jpg"), home: home))
        let link = home.appendingPathComponent("Downloads/link.zip")
        try fm.createSymbolicLink(at: link, withDestinationURL: archive)
        assertFalse(DeepScanner.allowedTrash(link, home: home))
        assertEqual(DeepScanner.scan(home: home, kind: .installers).items.count, 1)
    }
    func testSpecialRules() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lightclean-special-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        func file(_ path: String) throws -> URL {
            let url = home.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 3, count: 128).write(to: url); return url
        }
        let account = SpecialScanner.wechatBase + "/test-account"
        let db = try file(account + "/db_storage/message/message.db")
        let config = try file(account + "/config/login")
        let favorite = try file(account + "/business/favorite/keep.jpg")
        let video = try file(account + "/msg/video/2026-10/sample.mp4")
        _ = try file(account + "/msg/attach/group/image.dat")
        _ = try file(account + "/cache/2026-10/temp")
        _ = try file(account + "/msg/migrate/keep.db")
        let report = SpecialScanner.wechat(home: home)
        assertEqual(report.items.count, 3)
        assert(report.items.allSatisfy { SpecialScanner.allowed($0, kind: .wechat, home: home) })
        for url in [db, config, favorite, home.appendingPathComponent(account + "/db_storage"), home.appendingPathComponent(account)] {
            let fake = ScanItem(url: url, bytes: 128, modified: nil, cleanupRoot: home)
            assertFalse(SpecialScanner.allowed(fake, kind: .wechat, home: home))
            assertFalse(SpecialScanner.allowed(fake, kind: .large, home: home))
            assert(SpecialScanner.clean(fake, kind: .wechat, home: home, permanent: true) != nil)
        }
        let outside = try file("keep/safe")
        let link = home.appendingPathComponent(account + "/cache/link")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        assertFalse(SpecialScanner.isWeChatTarget(link, home: home))
        let media = report.items.first { $0.url.lastPathComponent == "2026-10" && $0.category == "微信视频" }!
        assert(SpecialScanner.clean(media, kind: .wechat, home: home, permanent: true) == nil)
        assertFalse(fm.fileExists(atPath: video.path))
        assertEqual(try Data(contentsOf: db), Data(repeating: 3, count: 128))
        assert(fm.fileExists(atPath: outside.path))
        _ = try file("projects/App/Package.swift")
        _ = try file("projects/App/.build/release/binary")
        let source = try file("projects/App/Sources/main.swift")
        _ = try file("projects/Other/.build/keep")
        let projectRoot = home.appendingPathComponent("projects")
        let projects = SpecialScanner.projects(root: projectRoot)
        assertEqual(projects.items.count, 1)
        assert(SpecialScanner.allowed(projects.items[0], kind: .projects, home: home))
        assert(SpecialScanner.clean(projects.items[0], kind: .projects, home: home, permanent: true) == nil)
        assert(fm.fileExists(atPath: source.path))
        assert(fm.fileExists(atPath: projectRoot.appendingPathComponent("Other/.build/keep").path))
        let readOnly = ScanItem(url: source, bytes: 128, modified: nil, reviewOnly: true, cleanupRoot: projectRoot)
        assertFalse(SpecialScanner.allowed(readOnly, kind: .large, home: home))
    }
    func testCancellation() async {
        let task = Task.detached { while !Task<Never, Never>.isCancelled { await Task.yield() }; return DiskScanner.scan(root: FileManager.default.homeDirectoryForCurrentUser, kind: .caches) }
        task.cancel()
        let report = await task.value
        assert(report.cancelled)
        assert(report.items.isEmpty)
    }
}

func assertFalse(_ value: Bool) { assert(!value) }
func assertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { assert(a == b, "Expected \(b), got \(a)", file: file, line: line) }
