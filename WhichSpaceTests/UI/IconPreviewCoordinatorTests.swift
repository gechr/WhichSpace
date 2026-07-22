import Testing
@testable import WhichSpace

@MainActor
struct IconPreviewCoordinatorTests {
    private func request(_ symbol: String) -> IconPreviewRequest {
        IconPreviewRequest(
            background: nil,
            badgePosition: nil,
            clearSymbol: false,
            foreground: nil,
            labelStyle: nil,
            separatorColor: nil,
            skinTone: nil,
            style: nil,
            symbol: symbol,
            symbolColor: nil,
            symbolPosition: nil,
            symbolWrap: nil
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("first preview applies immediately")
    func show_whenIdle_appliesImmediately() {
        var appliedSymbols: [String] = []
        let coordinator = IconPreviewCoordinator(
            applyPreview: {
                appliedSymbols.append($0.symbol ?? "")
                return true
            },
            restoreBaseIcon: {}
        )
        defer { coordinator.endWithoutRestore() }

        coordinator.show(request("first"))

        #expect(appliedSymbols == ["first"])
        #expect(coordinator.isPreviewing)
    }

    @Test("throttled previews apply the latest request")
    func show_duringThrottle_appliesLatestRequest() async {
        var appliedSymbols: [String] = []
        let coordinator = IconPreviewCoordinator(
            applyPreview: {
                appliedSymbols.append($0.symbol ?? "")
                return true
            },
            restoreBaseIcon: {}
        )
        defer { coordinator.endWithoutRestore() }

        coordinator.show(request("first"))
        coordinator.show(request("second"))
        coordinator.show(request("third"))

        #expect(appliedSymbols == ["first"])
        await waitUntil { appliedSymbols.count == 2 }
        try? await Task.sleep(for: .milliseconds(40))

        #expect(appliedSymbols == ["first", "third"])
        #expect(coordinator.isPreviewing)
    }

    @Test("a new preview cancels deferred restoration")
    func show_afterScheduleRestore_cancelsRestore() async {
        var appliedSymbols: [String] = []
        var restoreCount = 0
        let coordinator = IconPreviewCoordinator(
            applyPreview: {
                appliedSymbols.append($0.symbol ?? "")
                return true
            },
            restoreBaseIcon: { restoreCount += 1 }
        )
        defer { coordinator.endWithoutRestore() }

        coordinator.show(request("first"))
        coordinator.scheduleRestore()
        coordinator.show(request("second"))

        await waitUntil { appliedSymbols.count == 2 }
        try? await Task.sleep(for: .milliseconds(120))

        #expect(appliedSymbols == ["first", "second"])
        #expect(restoreCount == 0)
        #expect(coordinator.isPreviewing)
    }

    @Test("ending without restoration cancels pending work")
    func endWithoutRestore_cancelsPendingRequest() async {
        var appliedSymbols: [String] = []
        var restoreCount = 0
        let coordinator = IconPreviewCoordinator(
            applyPreview: {
                appliedSymbols.append($0.symbol ?? "")
                return true
            },
            restoreBaseIcon: { restoreCount += 1 }
        )

        coordinator.show(request("first"))
        coordinator.show(request("stale"))
        coordinator.endWithoutRestore()
        try? await Task.sleep(for: .milliseconds(40))

        #expect(appliedSymbols == ["first"])
        #expect(restoreCount == 0)
        #expect(!coordinator.isPreviewing)
    }
}
