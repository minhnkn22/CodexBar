import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct OverviewMenuCardRowViewTests {
    @Test
    @MainActor
    func `compact overview shows weekly before session`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = try Self.makeClaudeModel(
            primaryUsedPercent: 25,
            secondaryUsedPercent: 60,
            updatedAt: now)

        #expect(model.metrics.map(\.id) == ["primary", "secondary"])
        let row = OverviewMenuCardRowView(model: model, storageText: nil, width: 310)
        let liveModel = row.resolvedLiveModel(refreshMonitor: nil)
        #expect(row.visibleMetrics(for: liveModel).map(\.id) == ["secondary", "primary"])
        #expect(OverviewMenuCardRowView.maximumVisibleMetrics == 3)
    }

    @Test
    @MainActor
    func `compact overview respects providers whose primary metric is weekly`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = try Self.makeModel(
            provider: .kimi,
            primaryUsedPercent: 25,
            secondaryUsedPercent: 60,
            updatedAt: now)

        #expect(model.metrics.map(\.id) == ["secondary", "primary"])
        let row = OverviewMenuCardRowView(model: model, storageText: nil, width: 310)
        #expect(row.visibleMetrics(for: model).map(\.id) == ["primary", "secondary"])
    }

    @Test
    @MainActor
    func `non cadence metrics preserve provider order`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = try Self.makeModel(
            provider: .gemini,
            primaryUsedPercent: 25,
            secondaryUsedPercent: 60,
            primaryWindowMinutes: 24 * 60,
            secondaryWindowMinutes: 24 * 60,
            updatedAt: now)

        #expect(model.metrics.map(\.id) == ["primary", "secondary"])
        let row = OverviewMenuCardRowView(model: model, storageText: nil, width: 310)
        #expect(row.visibleMetrics(for: model).map(\.id) == ["primary", "secondary"])
    }

    @Test
    @MainActor
    func `preordered provider metrics remain weekly first`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.kilo])
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "25/100 credits"),
            secondary: RateWindow(
                usedPercent: 60,
                windowMinutes: nil,
                resetsAt: now.addingTimeInterval(86400),
                resetDescription: "$60 / $100"),
            updatedAt: now,
            identity: nil)
        let model = UsageMenuCardView.Model.make(Self.input(
            provider: .kilo,
            metadata: metadata,
            snapshot: snapshot,
            now: now))

        #expect(model.metrics.map(\.id) == ["secondary", "primary"])
    }

    @Test
    @MainActor
    func `doubao keeps weekly agent meter within three row cap`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.doubao])
        let snapshot = UsageSnapshot(
            primary: Self.rateWindow(minutes: 5 * 60, now: now),
            secondary: Self.rateWindow(minutes: 7 * 24 * 60, now: now),
            tertiary: Self.rateWindow(minutes: 30 * 24 * 60, now: now),
            extraRateWindows: [
                NamedRateWindow(
                    id: "doubao-agent-session",
                    title: "5-hour",
                    window: Self.rateWindow(minutes: 5 * 60, now: now)),
                NamedRateWindow(
                    id: "doubao-agent-weekly",
                    title: "Weekly",
                    window: Self.rateWindow(minutes: 7 * 24 * 60, now: now)),
                NamedRateWindow(
                    id: "doubao-agent-monthly",
                    title: "Monthly",
                    window: Self.rateWindow(minutes: 30 * 24 * 60, now: now)),
            ],
            updatedAt: now,
            identity: nil)
        let model = UsageMenuCardView.Model.make(Self.input(
            provider: .doubao,
            metadata: metadata,
            snapshot: snapshot,
            now: now))
        let row = OverviewMenuCardRowView(model: model, storageText: nil, width: 310)

        #expect(row.visibleMetrics(for: model).map(\.id) == [
            "secondary",
            "primary",
            "doubao-agent-weekly",
        ])
    }

    @Test
    @MainActor
    func `compact overview resolves refreshed quota meters from the live monitor`() throws {
        let stale = try Self.makeClaudeModel(
            primaryUsedPercent: 25,
            secondaryUsedPercent: 60,
            updatedAt: Date(timeIntervalSince1970: 1))
        let refreshed = try Self.makeClaudeModel(
            primaryUsedPercent: 70,
            secondaryUsedPercent: 80,
            updatedAt: Date(timeIntervalSince1970: 2))
        let monitor = MenuCardRefreshMonitor(
            resolveModel: { provider in
                provider == .claude ? refreshed : nil
            },
            isProviderRefreshActive: { _ in false })
        let row = OverviewMenuCardRowView(model: stale, storageText: nil, width: 310)

        let liveModel = row.resolvedLiveModel(refreshMonitor: monitor)
        #expect(row.visibleMetrics(for: liveModel).map(\.percent) == [20, 30])
    }

    @Test
    @MainActor
    func `compact overview replaces verbose errors with a short status`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: nil,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: "A deliberately long OAuth failure that belongs in provider details, not Overview.",
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: Date(timeIntervalSince1970: 1_700_000_000)))
        let row = OverviewMenuCardRowView(model: model, storageText: nil, width: 310)

        #expect(model.metrics.isEmpty)
        #expect(row.compactStatusText(for: model) == "Unavailable")
    }

    private static func makeClaudeModel(
        primaryUsedPercent: Double,
        secondaryUsedPercent: Double,
        updatedAt: Date) throws -> UsageMenuCardView.Model
    {
        try self.makeModel(
            provider: .claude,
            primaryUsedPercent: primaryUsedPercent,
            secondaryUsedPercent: secondaryUsedPercent,
            updatedAt: updatedAt)
    }

    private static func makeModel(
        provider: UsageProvider,
        primaryUsedPercent: Double,
        secondaryUsedPercent: Double,
        primaryWindowMinutes: Int? = nil,
        secondaryWindowMinutes: Int? = nil,
        updatedAt: Date) throws -> UsageMenuCardView.Model
    {
        let metadata = try #require(ProviderDefaults.metadata[provider])
        let resolvedPrimaryWindowMinutes = primaryWindowMinutes ?? (provider == .kimi ? 10080 : 300)
        let resolvedSecondaryWindowMinutes = secondaryWindowMinutes ?? (provider == .kimi ? 300 : 10080)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: primaryUsedPercent,
                windowMinutes: resolvedPrimaryWindowMinutes,
                resetsAt: updatedAt.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: secondaryUsedPercent,
                windowMinutes: resolvedSecondaryWindowMinutes,
                resetsAt: updatedAt.addingTimeInterval(86400),
                resetDescription: nil),
            updatedAt: updatedAt,
            identity: nil)
        return UsageMenuCardView.Model.make(.init(
            provider: provider,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            usesLiveSubtitle: true,
            now: updatedAt))
    }

    private static func rateWindow(minutes: Int, now: Date) -> RateWindow {
        RateWindow(
            usedPercent: 25,
            windowMinutes: minutes,
            resetsAt: now.addingTimeInterval(3600),
            resetDescription: nil)
    }

    private static func input(
        provider: UsageProvider,
        metadata: ProviderMetadata,
        snapshot: UsageSnapshot,
        now: Date) -> UsageMenuCardView.Model.Input
    {
        .init(
            provider: provider,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            usesLiveSubtitle: true,
            now: now)
    }
}
