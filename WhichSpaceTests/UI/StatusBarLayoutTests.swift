import Testing
@testable import WhichSpace

@Suite("StatusBarLayout")
@MainActor
struct StatusBarLayoutTests {
    // MARK: - slot(at:)

    @Test("correct space returned for coordinates within slots")
    func slotAt_correctSpaceForCoordinate() {
        let layout = StatusBarLayout(slots: [
            StatusBarIconSlot(startX: 0, width: 20, label: "1", targetSpace: 1, spaceID: 100),
            StatusBarIconSlot(startX: 20, width: 20, label: "2", targetSpace: 2, spaceID: 101),
            StatusBarIconSlot(startX: 40, width: 20, label: "3", targetSpace: 3, spaceID: 102),
        ])

        // Middle of first slot
        let slot1 = layout.slot(at: 10)
        #expect(slot1?.targetSpace == 1)
        #expect(slot1?.label == "1")

        // Middle of second slot
        let slot2 = layout.slot(at: 30)
        #expect(slot2?.targetSpace == 2)

        // Middle of third slot
        let slot3 = layout.slot(at: 50)
        #expect(slot3?.targetSpace == 3)
    }

    @Test("boundary conditions: start and end of slot")
    func slotAt_boundaries() {
        let layout = StatusBarLayout(slots: [
            StatusBarIconSlot(startX: 0, width: 20, label: "1", targetSpace: 1, spaceID: 100),
            StatusBarIconSlot(startX: 20, width: 20, label: "2", targetSpace: 2, spaceID: 101),
        ])

        // Exact start of first slot
        let atStart = layout.slot(at: 0)
        #expect(atStart?.targetSpace == 1)

        // Exact boundary (20) matches first slot due to inclusive upper bound
        let atBoundary = layout.slot(at: 20)
        #expect(atBoundary?.targetSpace == 1)

        // Just past boundary hits second slot
        let pastBoundary = layout.slot(at: 20.1)
        #expect(pastBoundary?.targetSpace == 2)

        // Exact end of second slot
        let atEnd = layout.slot(at: 40)
        #expect(atEnd?.targetSpace == 2)
    }

    @Test("outside all slots returns nil")
    func slotAt_outsideSlots_returnsNil() {
        let layout = StatusBarLayout(slots: [
            StatusBarIconSlot(startX: 10, width: 20, label: "1", targetSpace: 1, spaceID: 100),
        ])

        // Before any slot
        #expect(layout.slot(at: 5) == nil)

        // After all slots
        #expect(layout.slot(at: 35) == nil)
    }

    @Test("negative coordinate returns nil")
    func slotAt_negativeCoordinate_returnsNil() {
        let layout = StatusBarLayout(slots: [
            StatusBarIconSlot(startX: 0, width: 20, label: "1", targetSpace: 1, spaceID: 100),
        ])

        #expect(layout.slot(at: -5) == nil)
    }

    @Test("empty layout returns nil")
    func slotAt_emptyLayout_returnsNil() {
        let layout = StatusBarLayout.empty

        #expect(layout.slot(at: 10) == nil)
        #expect(layout.totalWidth == 0)
    }

    @Test("fullscreen slots return nil targetSpace")
    func slotAt_fullscreenSlots_returnNilTargetSpace() {
        let layout = StatusBarLayout(slots: [
            StatusBarIconSlot(startX: 0, width: 20, label: "1", targetSpace: 1, spaceID: 100),
            StatusBarIconSlot(startX: 20, width: 20, label: "F", targetSpace: nil, spaceID: 101),
            StatusBarIconSlot(startX: 40, width: 20, label: "2", targetSpace: 2, spaceID: 102),
        ])

        // Fullscreen slot
        let fsSlot = layout.slot(at: 30)
        #expect(fsSlot?.label == "F")
        #expect(fsSlot?.targetSpace == nil)
        #expect(fsSlot?.spaceID == 101)

        // targetSpace(at:) should also return nil for fullscreen
        #expect(layout.targetSpace(at: 30) == nil)
    }

    // MARK: - totalWidth

    @Test("totalWidth reflects all slots")
    func totalWidth_reflectsAllSlots() {
        let layout = StatusBarLayout(slots: [
            StatusBarIconSlot(startX: 0, width: 20, label: "1", targetSpace: 1, spaceID: 100),
            StatusBarIconSlot(startX: 20, width: 20, label: "2", targetSpace: 2, spaceID: 101),
            StatusBarIconSlot(startX: 40, width: 20, label: "3", targetSpace: 3, spaceID: 102),
        ])

        #expect(layout.totalWidth == 60)
    }
}
