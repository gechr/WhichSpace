import CoreGraphics
import Foundation
import Testing
@testable import WhichSpace

/// Records every request so tests can assert what was attempted, and confirms
/// membership only for the backends they mark as working.
private final class FakeWindowMover: WindowMoving, @unchecked Sendable {
    var available: Set<WindowMoveBackend>
    /// Backends whose move actually lands. Anything else issues and then fails
    /// confirmation, which is how a neutered private API behaves.
    var effective: Set<WindowMoveBackend>
    var spaces: [Int]
    private(set) var attempted: [WindowMoveBackend] = []

    init(
        available: Set<WindowMoveBackend> = [.bridged],
        effective: Set<WindowMoveBackend> = [.bridged],
        // The Space `makeAppState` starts on, so the window looks like it lives
        // on the display whose Spaces are being numbered
        spaces: [Int] = [100]
    ) {
        self.available = available
        self.effective = effective
        self.spaces = spaces
    }

    func isAvailable(_ backend: WindowMoveBackend) -> Bool {
        available.contains(backend)
    }

    /// When true, an effective move adds the target without dropping the source,
    /// which is a copy rather than a move.
    var leavesSourceMembership = false

    func perform(_ backend: WindowMoveBackend, windowID _: CGWindowID, spaceID: Int) -> Bool {
        attempted.append(backend)
        if effective.contains(backend) {
            spaces = leavesSourceMembership ? spaces + [spaceID] : [spaceID]
        }
        return true
    }

    func spaceIDs(forWindow _: CGWindowID) -> [Int] {
        spaces
    }
}

private struct FakeLocator: FrontWindowLocating {
    var window: FrontWindow?

    func frontWindow() -> FrontWindow? {
        window
    }
}

/// Records raised windows and reports a configurable result, so tests cover
/// the raise ladder without messaging a real AX server.
private final class FakeRaiser: WindowRaising, @unchecked Sendable {
    var result = true
    var onRaise: (() -> Void)?
    private(set) var raised: [FrontWindow] = []

    @discardableResult
    func raise(_ window: FrontWindow) -> Bool {
        raised.append(window)
        onRaise?()
        return result
    }
}

@MainActor
struct SpaceWindowMoverTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite
    private let stub: CGSStub

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
        stub = CGSStub()
    }

    private func makeAppState(
        spaces: [(id: Int, isFullscreen: Bool)] = [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
        activeSpaceID: Int = 100
    ) -> AppState {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(displayID: "Main", spaces: spaces, activeSpaceID: activeSpaceID),
        ]
        return AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    private func makeMover(
        _ mover: FakeWindowMover,
        window: FrontWindow? = FrontWindow(id: 42, ownerPID: 99),
        raiser: FakeRaiser = FakeRaiser(),
        isProcessTrusted: Bool = true,
        followed: FollowRecorder = FollowRecorder(),
        permitted: [WindowMoveBackend] = WindowMoveBackend.allCases
    ) -> SpaceWindowMover {
        SpaceWindowMover(
            mover: mover,
            locator: FakeLocator(window: window),
            raiser: raiser,
            isProcessTrusted: { isProcessTrusted },
            followAction: { spaceID, ownerPID in followed.record(spaceID: spaceID, ownerPID: ownerPID) },
            permitted: permitted,
            confirmationTimeout: .milliseconds(30),
            confirmationInterval: .milliseconds(1)
        )
    }

    @MainActor
    final class FollowRecorder {
        private(set) var calls: [(spaceID: Int, ownerPID: pid_t)] = []

        func record(spaceID: Int, ownerPID: pid_t) {
            calls.append((spaceID, ownerPID))
        }
    }

    // MARK: - Absolute Moves

    @Test("move targets the space id at the requested 1-based number")
    func move_targetsRequestedSpaceID() async throws {
        let fake = FakeWindowMover()
        let mover = makeMover(fake)

        try await mover.move(toSpaceNumber: 2, follow: false, appState: makeAppState())

        #expect(fake.spaces == [101], "Space 2 is the second entry, whose id is 101")
    }

    @Test("move with no spaces throws")
    func move_withoutSpaces_throws() async {
        let appState = AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
        let mover = makeMover(FakeWindowMover())

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 1, follow: false, appState: appState)
        }
    }

    @Test("move below the first space throws out of range", arguments: [0, -1, 3])
    func move_outOfRange_throws(number: Int) async {
        let mover = makeMover(FakeWindowMover())
        let appState = makeAppState()

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: number, follow: false, appState: appState)
        }
    }

    @Test("move to a fullscreen space throws")
    func move_toFullscreenSpace_throws() async {
        let appState = makeAppState(
            spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: true)]
        )
        let fake = FakeWindowMover()
        let mover = makeMover(fake)

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: false, appState: appState)
        }
        #expect(fake.attempted.isEmpty, "A fullscreen target must be rejected before any move is issued")
    }

    @Test("move without a front window throws")
    func move_withoutWindow_throws() async {
        let fake = FakeWindowMover()
        let mover = makeMover(fake, window: nil)
        let appState = makeAppState()

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: false, appState: appState)
        }
        #expect(fake.attempted.isEmpty)
    }

    @Test("move with no available backend throws without attempting one")
    func move_withoutBackend_throws() async {
        let fake = FakeWindowMover(available: [], effective: [])
        let mover = makeMover(fake)
        let appState = makeAppState()

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: false, appState: appState)
        }
        #expect(fake.attempted.isEmpty)
    }

    @Test("a window already on the target space is not moved again")
    func move_alreadyOnTarget_skipsMove() async throws {
        let fake = FakeWindowMover(spaces: [101])
        let followed = FollowRecorder()
        let mover = makeMover(fake, followed: followed)

        try await mover.move(toSpaceNumber: 2, follow: true, appState: makeAppState())

        #expect(fake.attempted.isEmpty, "A sticky or already-placed window needs no move")
        #expect(followed.calls.count == 1, "Following still applies")
    }

    // MARK: - Following

    @Test("follow switches once, with the target space and owning process")
    func move_following_switchesOnce() async throws {
        let followed = FollowRecorder()
        let mover = makeMover(FakeWindowMover(), followed: followed)

        try await mover.move(toSpaceNumber: 2, follow: true, appState: makeAppState())

        #expect(followed.calls.count == 1)
        #expect(followed.calls.first?.spaceID == 101)
        #expect(followed.calls.first?.ownerPID == 99)
    }

    @Test("send does not switch")
    func move_withoutFollowing_staysPut() async throws {
        let followed = FollowRecorder()
        let mover = makeMover(FakeWindowMover(), followed: followed)

        try await mover.move(toSpaceNumber: 2, follow: false, appState: makeAppState())

        #expect(followed.calls.isEmpty)
    }

    @Test("following without accessibility fails before the window is moved")
    func move_followingUntrusted_throwsBeforeMoving() async {
        let fake = FakeWindowMover()
        let mover = makeMover(fake, isProcessTrusted: false)
        let appState = makeAppState()

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: true, appState: appState)
        }
        #expect(fake.attempted.isEmpty, "A permission failure must never leave the window relocated")
    }

    @Test("sending needs no accessibility permission")
    func move_withoutFollowing_ignoresAccessibility() async throws {
        let fake = FakeWindowMover()
        let mover = makeMover(fake, isProcessTrusted: false)

        try await mover.move(toSpaceNumber: 2, follow: false, appState: makeAppState())

        #expect(fake.spaces == [101])
    }

    // MARK: - Raising

    @Test("a confirmed move raises the moved window")
    func move_confirmed_raisesWindow() async throws {
        let raiser = FakeRaiser()
        let mover = makeMover(FakeWindowMover(), raiser: raiser)

        try await mover.move(toSpaceNumber: 2, follow: true, appState: makeAppState())

        #expect(raiser.raised == [FrontWindow(id: 42, ownerPID: 99)])
    }

    @Test("a trusted send raises so the window is frontmost when visited")
    func move_sendTrusted_raisesWindow() async throws {
        let raiser = FakeRaiser()
        let mover = makeMover(FakeWindowMover(), raiser: raiser)

        try await mover.move(toSpaceNumber: 2, follow: false, appState: makeAppState())

        #expect(raiser.raised.count == 1)
    }

    @Test("an untrusted send skips the raise and still succeeds")
    func move_sendUntrusted_skipsRaise() async throws {
        let fake = FakeWindowMover()
        let raiser = FakeRaiser()
        let mover = makeMover(fake, raiser: raiser, isProcessTrusted: false)

        try await mover.move(toSpaceNumber: 2, follow: false, appState: makeAppState())

        #expect(raiser.raised.isEmpty, "Sending must stay permission-free, so the raise is best-effort")
        #expect(fake.spaces == [101])
    }

    @Test("a failed raise does not fail the move")
    func move_raiseFails_moveStillSucceeds() async throws {
        let fake = FakeWindowMover()
        let raiser = FakeRaiser()
        raiser.result = false
        let mover = makeMover(fake, raiser: raiser)

        try await mover.move(toSpaceNumber: 2, follow: false, appState: makeAppState())

        #expect(fake.spaces == [101])
    }

    @Test("a failed move never raises")
    func move_unconfirmed_doesNotRaise() async {
        let raiser = FakeRaiser()
        let mover = makeMover(FakeWindowMover(available: [.bridged], effective: []), raiser: raiser)
        let appState = makeAppState()

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: false, appState: appState)
        }
        #expect(raiser.raised.isEmpty)
    }

    @Test("the sticky path raises too")
    func move_alreadyOnTarget_raises() async throws {
        let raiser = FakeRaiser()
        let mover = makeMover(FakeWindowMover(spaces: [101]), raiser: raiser)

        try await mover.move(toSpaceNumber: 2, follow: true, appState: makeAppState())

        #expect(raiser.raised.count == 1, "An incumbent can cover a sticky window as much as a moved one")
    }

    @Test("the raise lands before the follow switch")
    func move_raisesBeforeFollowing() async throws {
        // Raising after the switch would race the arrival, so the order is the
        // crux of the focus fix
        let events = EventLog()
        let raiser = FakeRaiser()
        raiser.onRaise = { events.record("raise") }
        let mover = SpaceWindowMover(
            mover: FakeWindowMover(),
            locator: FakeLocator(window: FrontWindow(id: 42, ownerPID: 99)),
            raiser: raiser,
            isProcessTrusted: { true },
            followAction: { _, _ in events.record("follow") },
            permitted: WindowMoveBackend.allCases,
            confirmationTimeout: .milliseconds(30),
            confirmationInterval: .milliseconds(1)
        )

        try await mover.move(toSpaceNumber: 2, follow: true, appState: makeAppState())

        #expect(events.events == ["raise", "follow"])
    }

    final class EventLog: @unchecked Sendable {
        private(set) var events: [String] = []

        func record(_ event: String) {
            events.append(event)
        }
    }

    // MARK: - Backend Ladder

    @Test("an unconfirmed backend falls through to the next")
    func move_unconfirmedBackend_fallsThrough() async throws {
        let fake = FakeWindowMover(
            available: [.bridged, .managedSpace],
            effective: [.managedSpace]
        )
        let mover = makeMover(fake)

        try await mover.move(toSpaceNumber: 2, follow: false, appState: makeAppState())

        #expect(fake.attempted == [.bridged, .managedSpace], "Backends are tried newest first")
        #expect(fake.spaces == [101])
    }

    @Test("a backend that copies instead of moving is not accepted")
    func move_backendLeavesSourceMembership_throws() async {
        let fake = FakeWindowMover()
        fake.leavesSourceMembership = true
        let mover = makeMover(fake)
        let appState = makeAppState()

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: false, appState: appState)
        }
        #expect(fake.spaces.sorted() == [100, 101], "Arriving without leaving is a copy, not a move")
    }

    @Test("a window on another display is not moved")
    func move_windowOnAnotherDisplay_throws() async {
        // Membership that no entry of the numbered display contains
        let fake = FakeWindowMover(spaces: [777])
        let mover = makeMover(fake)
        let appState = makeAppState()

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: false, appState: appState)
        }
        #expect(fake.attempted.isEmpty, "Numbering is per display, so this would cross displays unasked")
    }

    @Test("a fullscreen front window is not moved")
    func move_fullscreenSourceWindow_throws() async {
        let appState = makeAppState(
            spaces: [(id: 100, isFullscreen: true), (id: 101, isFullscreen: false)],
            activeSpaceID: 100
        )
        let fake = FakeWindowMover(spaces: [100])
        let mover = makeMover(fake)

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: false, appState: appState)
        }
        #expect(fake.attempted.isEmpty)
    }

    @Test("a move that never confirms throws")
    func move_neverConfirms_throws() async {
        let fake = FakeWindowMover(available: [.bridged], effective: [])
        let mover = makeMover(fake)
        let appState = makeAppState()

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: false, appState: appState)
        }
        #expect(fake.attempted == [.bridged])
    }

    @Test("the bridged backend is tried first on every supported release")
    func permittedBackends_leadWithBridged() {
        #expect(SpaceWindowMover.permittedBackends.first == .bridged)
    }

    @Test("the legacy backends are only permitted on the release that honours them")
    func permittedBackends_excludeNeuteredLegacyCalls() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let permitted = SpaceWindowMover.permittedBackends
        guard version.majorVersion == 14 else {
            // Apple added validation to the plain call in 14.5 and neutered the
            // compat-ID pair in 15.0, so both are callable and useless here
            #expect(permitted == [.bridged])
            return
        }
        #expect(permitted.contains(version.minorVersion < 5 ? .managedSpace : .compatID))
    }

    // MARK: - Relative Moves

    @Test("relative move steps to the neighbouring space")
    func moveRelative_stepsOneSpace() async throws {
        let fake = FakeWindowMover()
        let mover = makeMover(fake)

        try await mover.moveRelative(goRight: true, follow: false, appState: makeAppState())

        #expect(fake.spaces == [101])
    }

    @Test("relative move skips fullscreen spaces")
    func moveRelative_skipsFullscreen() async throws {
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: true),
                (id: 102, isFullscreen: false),
            ]
        )
        let fake = FakeWindowMover()
        let mover = makeMover(fake)

        try await mover.moveRelative(goRight: true, follow: false, appState: appState)

        #expect(fake.spaces == [102], "The fullscreen Space cannot receive windows, so it is stepped over")
    }

    @Test("relative move errors at both edges", arguments: [true, false])
    func moveRelative_errorsAtEdges(goRight: Bool) async {
        // A single space has no neighbour in either direction
        let appState = makeAppState(spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100)
        let fake = FakeWindowMover()
        let mover = makeMover(fake)

        await #expect(throws: MoveError.self) {
            try await mover.moveRelative(goRight: goRight, follow: false, appState: appState)
        }
        #expect(fake.attempted.isEmpty)
    }

    // MARK: - Front Window Resolution

    private func window(
        number: Int,
        pid: pid_t,
        layer: Int = 0,
        width: Double = 800,
        height: Double = 600,
        alpha: Double = 1
    ) -> [String: Any] {
        [
            kCGWindowNumber as String: number,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: ["Width": width, "Height": height],
        ]
    }

    @Test("front window prefers the frontmost app")
    func resolve_prefersFrontmostApp() {
        let list = [window(number: 1, pid: 10), window(number: 2, pid: 20)]

        let resolved = SystemFrontWindowLocator.resolve(windowList: list, frontmostPID: 20, excluding: 99)

        #expect(resolved == FrontWindow(id: 2, ownerPID: 20))
    }

    @Test("front window falls back to front-to-back order")
    func resolve_fallsBackToWindowOrder() {
        let list = [window(number: 1, pid: 10), window(number: 2, pid: 20)]

        let resolved = SystemFrontWindowLocator.resolve(windowList: list, frontmostPID: 77, excluding: 99)

        #expect(resolved == FrontWindow(id: 1, ownerPID: 10))
    }

    @Test("front window skips our own windows")
    func resolve_skipsOwnProcess() {
        let list = [window(number: 1, pid: 99), window(number: 2, pid: 20)]

        let resolved = SystemFrontWindowLocator.resolve(windowList: list, frontmostPID: 99, excluding: 99)

        #expect(resolved == FrontWindow(id: 2, ownerPID: 20), "Our own Settings window must never be the one moved")
    }

    @Test("front window skips non-regular, tiny and invisible windows")
    func resolve_skipsIneligibleWindows() {
        let list = [
            window(number: 1, pid: 10, layer: 25),
            window(number: 2, pid: 11, width: 4, height: 4),
            window(number: 3, pid: 12, alpha: 0),
            window(number: 4, pid: 13),
        ]

        let resolved = SystemFrontWindowLocator.resolve(windowList: list, frontmostPID: nil, excluding: 99)

        #expect(resolved == FrontWindow(id: 4, ownerPID: 13))
    }

    @Test("front window is nil when nothing qualifies")
    func resolve_withoutCandidates_isNil() {
        #expect(SystemFrontWindowLocator.resolve(windowList: [], frontmostPID: nil, excluding: 99) == nil)
    }
}
