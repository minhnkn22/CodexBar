import Darwin
import Foundation
import Testing
@testable import CodexBar

struct CodexBarLaunchModeTests {
    @Test
    func `normal launch starts the application`() {
        #expect(CodexBarLaunchMode.resolve(arguments: ["/Applications/CodexBar"]) == .application)
    }

    @Test
    func `hook event launch skips application initialization`() {
        #expect(CodexBarLaunchMode.resolve(
            arguments: ["/Applications/CodexBar", "--hook-event"]) == .hookEvent)
    }

    @Test
    func `hook event is recognized among other arguments`() {
        #expect(CodexBarLaunchMode.resolve(
            arguments: ["/Applications/CodexBar", "--verbose", "--hook-event"]) == .hookEvent)
    }

    @Test
    func `similar argument still starts the application`() {
        #expect(CodexBarLaunchMode.resolve(
            arguments: ["/Applications/CodexBar", "--hook-events"]) == .application)
    }

    @Test
    func `application starts after acquiring lock with no legacy instance`() {
        #expect(CodexBarSingleInstanceGuard.shouldStart(
            lockResult: .acquired,
            hasOtherRunningApplication: false))
    }

    @Test
    func `application exits when another process holds the lock`() {
        #expect(CodexBarSingleInstanceGuard.shouldStart(
            lockResult: .contended,
            hasOtherRunningApplication: false) == false)
    }

    @Test
    func `application exits for a legacy instance without a lock`() {
        #expect(CodexBarSingleInstanceGuard.shouldStart(
            lockResult: .acquired,
            hasOtherRunningApplication: true) == false)
    }

    @Test
    func `lock setup failure does not make the app disappear`() {
        #expect(CodexBarSingleInstanceGuard.shouldStart(
            lockResult: .unavailable(EACCES),
            hasOtherRunningApplication: false))
        #expect(CodexBarSingleInstanceGuard.shouldStart(
            lockResult: .unavailable(EACCES),
            hasOtherRunningApplication: true) == false)
    }

    @Test
    func `advisory lock excludes a duplicate and releases for relaunch`() {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarLaunchModeTests-\(UUID().uuidString).lock")
        let first = CodexBarInstanceLock()
        let duplicate = CodexBarInstanceLock()
        defer {
            first.release()
            duplicate.release()
            try? FileManager.default.removeItem(at: lockURL)
        }

        #expect(first.acquire(at: lockURL) == .acquired)
        #expect(duplicate.acquire(at: lockURL) == .contended)
        first.release()
        #expect(duplicate.acquire(at: lockURL) == .acquired)
    }
}
