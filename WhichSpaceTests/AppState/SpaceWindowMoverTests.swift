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
    private(set) var attemptedWindowIDs: [CGWindowID] = []
    private var spacesByWindow: [CGWindowID: [Int]]

    init(
        available: Set<WindowMoveBackend> = [.bridged],
        effective: Set<WindowMoveBackend> = [.bridged],
        // The Space `makeAppState` starts on, so the window looks like it lives
        // on the display whose Spaces are being numbered
        spaces: [Int] = [100],
        spacesByWindow: [CGWindowID: [Int]] = [:]
    ) {
        self.available = available
        self.effective = effective
        self.spaces = spaces
        self.spacesByWindow = spacesByWindow
    }

    func isAvailable(_ backend: WindowMoveBackend) -> Bool {
        available.contains(backend)
    }

    /// When true, an effective move adds the target without dropping the source,
    /// which is a copy rather than a move.
    var leavesSourceMembership = false

    func perform(_ backend: WindowMoveBackend, windowID: CGWindowID, spaceID: Int) -> Bool {
        attempted.append(backend)
        attemptedWindowIDs.append(windowID)
        if effective.contains(backend) {
            if let windowSpaces = spacesByWindow[windowID] {
                spacesByWindow[windowID] = leavesSourceMembership ? windowSpaces + [spaceID] : [spaceID]
            } else {
                spaces = leavesSourceMembership ? spaces + [spaceID] : [spaceID]
            }
        }
        return true
    }

    func spaceIDs(forWindow windowID: CGWindowID) -> [Int] {
        spacesByWindow[windowID] ?? spaces
    }
}

private struct FakeLocator: FrontWindowLocating {
    var windows: [FrontWindow]

    init(window: FrontWindow?) {
        windows = window.map { [$0] } ?? []
    }

    init(windows: [FrontWindow]) {
        self.windows = windows
    }

    func frontWindows(fallbackPID _: pid_t?) -> [FrontWindow] {
        windows
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
        windows: [FrontWindow] = [],
        raiser: FakeRaiser = FakeRaiser(),
        isProcessTrusted: Bool = true,
        followed: FollowRecorder = FollowRecorder(),
        activateApp: @escaping @MainActor (pid_t) -> Void = { _ in },
        permitted: [WindowMoveBackend] = WindowMoveBackend.allCases
    ) -> SpaceWindowMover {
        SpaceWindowMover(
            mover: mover,
            locator: FakeLocator(windows: windows.isEmpty ? window.map { [$0] } ?? [] : windows),
            raiser: raiser,
            isProcessTrusted: { isProcessTrusted },
            followAction: { target, ownerPID in followed.record(target: target, ownerPID: ownerPID) },
            activateApp: activateApp,
            permitted: permitted,
            confirmationTimeout: .milliseconds(30),
            confirmationInterval: .milliseconds(1),
            arrivalTimeout: .milliseconds(30),
            arrivalInterval: .milliseconds(1)
        )
    }

    @MainActor
    final class FollowRecorder {
        private(set) var calls: [(target: SpaceWindowMover.FollowTarget, ownerPID: pid_t)] = []

        func record(target: SpaceWindowMover.FollowTarget, ownerPID: pid_t) {
            calls.append((target, ownerPID))
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

    // MARK: - Global Desktop Moves

    private func makeMultiDisplayAppState() -> AppState {
        stub.activeDisplayIdentifier = "Main"
        stub.displays = [
            CGSStub.makeDisplay(
                displayID: "Main",
                spaces: [(id: 100, isFullscreen: false), (id: 101, isFullscreen: false)],
                activeSpaceID: 100
            ),
            CGSStub.makeDisplay(
                displayID: "Side",
                spaces: [
                    (id: 200, isFullscreen: true),
                    (id: 201, isFullscreen: false),
                    (id: 202, isFullscreen: false),
                ],
                activeSpaceID: 201
            ),
        ]
        return AppState(displaySpaceProvider: stub, skipObservers: true, store: store)
    }

    @Test("global Desktop numbers resolve across displays")
    func moveGlobal_targetsOtherDisplaySpace() async throws {
        let fake = FakeWindowMover()
        let mover = makeMover(fake)

        try await mover.move(toGlobalDesktop: 3, follow: false, appState: makeMultiDisplayAppState())

        #expect(fake.spaces == [201], "Desktop 3 is the second display's first regular Space")
    }

    @Test("global Desktop numbering skips fullscreen Spaces")
    func moveGlobal_skipsFullscreenSpaces() async throws {
        let fake = FakeWindowMover()
        let mover = makeMover(fake)

        try await mover.move(toGlobalDesktop: 4, follow: false, appState: makeMultiDisplayAppState())

        #expect(fake.spaces == [202], "The fullscreen Space consumes no Desktop number")
    }

    @Test("global Desktop move past the last Desktop throws")
    func moveGlobal_outOfRange_throws() async {
        let mover = makeMover(FakeWindowMover())
        let appState = makeMultiDisplayAppState()

        await #expect(throws: MoveError.self) {
            try await mover.move(toGlobalDesktop: 5, follow: false, appState: appState)
        }
    }

    @Test("global Desktop follow routes through the numbered Desktop")
    func moveGlobal_followUsesDesktopRoute() async throws {
        let fake = FakeWindowMover()
        let followed = FollowRecorder()
        let mover = makeMover(fake, followed: followed)

        try await mover.move(toGlobalDesktop: 3, follow: true, appState: makeMultiDisplayAppState())

        #expect(followed.calls.count == 1)
        #expect(followed.calls.first?.target == .desktop(number: 3, spaceID: 201))
    }

    @Test("global Desktop move accepts a window on another display")
    func moveGlobal_windowOnOtherDisplay_moves() async throws {
        let fake = FakeWindowMover(spaces: [201])
        let mover = makeMover(fake)

        try await mover.move(toGlobalDesktop: 1, follow: false, appState: makeMultiDisplayAppState())

        #expect(fake.spaces == [100], "Global numbering may move a window across displays")
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

    @Test("move skips candidates that are not on an active addressable Space")
    func move_skipsInactiveSpaceCandidate() async throws {
        let fake = FakeWindowMover(spacesByWindow: [41: [101], 42: [100]])
        let mover = makeMover(
            fake,
            windows: [
                FrontWindow(id: 41, ownerPID: 10),
                FrontWindow(id: 42, ownerPID: 20),
            ]
        )

        try await mover.move(toSpaceNumber: 2, follow: false, appState: makeAppState())

        #expect(fake.attemptedWindowIDs == [42], "The inactive-Space window must not be moved")
    }

    @Test("local move does not substitute a window on the numbered display")
    func move_frontWindowOnOtherDisplay_doesNotSubstituteCandidate() async {
        let fake = FakeWindowMover(spacesByWindow: [41: [201], 42: [100]])
        let mover = makeMover(
            fake,
            windows: [
                FrontWindow(id: 41, ownerPID: 10),
                FrontWindow(id: 42, ownerPID: 20),
            ]
        )

        await #expect(throws: MoveError.self) {
            try await mover.move(toSpaceNumber: 2, follow: false, appState: makeMultiDisplayAppState())
        }
        #expect(fake.attemptedWindowIDs.isEmpty, "The command must not silently move a different window")
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
        let fake = FakeWindowMover(spaces: [100, 101])
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
        #expect(followed.calls.first?.target == .space(id: 101))
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
        let mover = makeMover(FakeWindowMover(spaces: [100, 101]), raiser: raiser)

        try await mover.move(toSpaceNumber: 2, follow: true, appState: makeAppState())

        #expect(raiser.raised.count == 1, "An incumbent can cover a sticky window as much as a moved one")
    }

    @Test("arrival re-asserts the raise and activation")
    func move_arrival_reRaises() async throws {
        let raiser = FakeRaiser()
        let events = EventLog()
        let mover = makeMover(FakeWindowMover(spaces: [101]), raiser: raiser) { _ in events.record("activate") }

        // The stub already reports the target Space as current, so the switch
        // is seen to land immediately
        try await mover.move(toSpaceNumber: 2, follow: true, appState: makeAppState(activeSpaceID: 101))

        #expect(raiser.raised.count == 2, "Once before the switch and once on arrival")
        #expect(events.events == ["activate"])
    }

    @Test("a switch that never lands keeps the pre-switch raise only")
    func move_neverArrives_skipsReRaise() async throws {
        let raiser = FakeRaiser()
        let events = EventLog()
        let mover = makeMover(FakeWindowMover(), raiser: raiser) { _ in events.record("activate") }

        try await mover.move(toSpaceNumber: 2, follow: true, appState: makeAppState())

        #expect(raiser.raised.count == 1, "Arrival cannot be confirmed, so the raise is not repeated")
        #expect(events.events.isEmpty)
    }

    @Test("send never waits for arrival or re-raises")
    func move_send_skipsArrival() async throws {
        let raiser = FakeRaiser()
        let events = EventLog()
        let mover = makeMover(FakeWindowMover(spaces: [101]), raiser: raiser) { _ in events.record("activate") }

        try await mover.move(toSpaceNumber: 2, follow: false, appState: makeAppState(activeSpaceID: 101))

        #expect(raiser.raised.count == 1)
        #expect(events.events.isEmpty)
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
            activateApp: { _ in },
            permitted: WindowMoveBackend.allCases,
            confirmationTimeout: .milliseconds(30),
            confirmationInterval: .milliseconds(1),
            arrivalTimeout: .milliseconds(30),
            arrivalInterval: .milliseconds(1)
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

    @Test("wrapping carries the window round to the far end", arguments: [true, false])
    func moveRelative_wrapsAtEdges(goRight: Bool) async throws {
        // Sitting on the edge the requested direction runs off
        let active = goRight ? 102 : 100
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: false),
                (id: 101, isFullscreen: false),
                (id: 102, isFullscreen: false),
            ],
            activeSpaceID: active
        )
        let fake = FakeWindowMover(spaces: [active])
        let mover = makeMover(fake)

        try await mover.moveRelative(goRight: goRight, follow: false, wrap: true, appState: appState)

        #expect(fake.spaces == [goRight ? 100 : 102])
    }

    @Test("wrapping steps over a fullscreen Space at the far end")
    func moveRelative_wrapSkipsFullscreen() async throws {
        let appState = makeAppState(
            spaces: [
                (id: 100, isFullscreen: true),
                (id: 101, isFullscreen: false),
                (id: 102, isFullscreen: false),
            ],
            activeSpaceID: 102
        )
        let fake = FakeWindowMover(spaces: [102])
        let mover = makeMover(fake)

        try await mover.moveRelative(goRight: true, follow: false, wrap: true, appState: appState)

        #expect(fake.spaces == [101], "Wrapping lands on the first Space that can hold a window")
    }

    @Test("wrapping onto the only regular Space is refused")
    func moveRelative_wrapRefusesSelf() async {
        let appState = makeAppState(spaces: [(id: 100, isFullscreen: false)], activeSpaceID: 100)
        let fake = FakeWindowMover()
        let mover = makeMover(fake)

        await #expect(throws: MoveError.self) {
            try await mover.moveRelative(goRight: true, follow: false, wrap: true, appState: appState)
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
        let list = [window(number: 1, pid: 10), window(number: 2, pid: 20), window(number: 3, pid: 20)]

        let resolved = SystemFrontWindowLocator.resolve(windowList: list, preferredPID: 20, excluding: [99])

        #expect(resolved == [
            FrontWindow(id: 2, ownerPID: 20),
            FrontWindow(id: 3, ownerPID: 20),
            FrontWindow(id: 1, ownerPID: 10),
        ])
    }

    @Test("front window prefers the focused window over sibling windows")
    func resolve_prefersFocusedWindow() {
        let list = [window(number: 1, pid: 10), window(number: 2, pid: 20), window(number: 3, pid: 20)]

        let resolved = SystemFrontWindowLocator.resolve(
            windowList: list,
            preferredPID: 20,
            focusedWindowID: 3,
            excluding: [99]
        )

        #expect(resolved == [
            FrontWindow(id: 3, ownerPID: 20),
            FrontWindow(id: 2, ownerPID: 20),
            FrontWindow(id: 1, ownerPID: 10),
        ], "The focused window moves even when WindowServer orders a sibling first")
    }

    @Test("a focused window outside the frontmost app leaves the order unchanged")
    func resolve_ignoresForeignFocusedWindow() {
        let list = [window(number: 1, pid: 10), window(number: 2, pid: 20), window(number: 3, pid: 20)]

        let resolved = SystemFrontWindowLocator.resolve(
            windowList: list,
            preferredPID: 20,
            focusedWindowID: 1,
            excluding: [99]
        )

        #expect(resolved == [
            FrontWindow(id: 2, ownerPID: 20),
            FrontWindow(id: 3, ownerPID: 20),
            FrontWindow(id: 1, ownerPID: 10),
        ], "Stale focus data never promotes another application's window")
    }

    @Test("front window falls back to front-to-back order")
    func resolve_fallsBackToWindowOrder() {
        let list = [window(number: 1, pid: 10), window(number: 2, pid: 20)]

        let resolved = SystemFrontWindowLocator.resolve(windowList: list, preferredPID: 77, excluding: [99])

        #expect(resolved == [FrontWindow(id: 1, ownerPID: 10), FrontWindow(id: 2, ownerPID: 20)])
    }

    @Test("front window skips excluded application windows")
    func resolve_skipsExcludedProcesses() {
        let list = [
            window(number: 1, pid: 1242),
            window(number: 2, pid: 99),
            window(number: 3, pid: 20),
        ]

        let resolved = SystemFrontWindowLocator.resolve(
            windowList: list,
            preferredPID: 1242,
            excluding: [99, 1242]
        )

        #expect(
            resolved == [FrontWindow(id: 3, ownerPID: 20)],
            "WhichSpace and WindowManager windows must never be moved"
        )
    }

    @Test("front window skips non-regular, tiny and invisible windows")
    func resolve_skipsIneligibleWindows() {
        let list = [
            window(number: 1, pid: 10, layer: 25),
            window(number: 2, pid: 11, width: 4, height: 4),
            window(number: 3, pid: 12, alpha: 0),
            window(number: 4, pid: 13),
        ]

        let resolved = SystemFrontWindowLocator.resolve(windowList: list, preferredPID: nil, excluding: [99])

        #expect(resolved == [FrontWindow(id: 4, ownerPID: 13)])
    }

    @Test("front window is nil when nothing qualifies")
    func resolve_withoutCandidates_isNil() {
        #expect(SystemFrontWindowLocator.resolve(windowList: [], preferredPID: nil, excluding: [99]).isEmpty)
    }
}

/// Collects event markers on the main actor, so overlapping serializer
/// operations can record their interleaving without a data race.
@MainActor
private final class EventLog {
    private(set) var events: [Int] = []

    func append(_ event: Int) {
        events.append(event)
    }
}

@MainActor
struct MoveSerializerTests {
    @Test("a second command waits for the first to finish")
    func serializesOverlappingCommands() async {
        let serializer = MoveSerializer()
        let log = EventLog()
        let (started, startSignal) = AsyncStream.makeStream(of: Void.self)
        let (gate, release) = AsyncStream.makeStream(of: Void.self)

        let first = Task { @MainActor in
            await serializer.run {
                log.append(1)
                startSignal.yield(())
                for await _ in gate {
                    break
                }
                log.append(2)
            }
        }
        var startIterator = started.makeAsyncIterator()
        _ = await startIterator.next()
        let second = Task { @MainActor in
            await serializer.run {
                log.append(3)
            }
        }
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(log.events == [1], "The second command must not start while the first is in flight")

        release.yield(())
        release.finish()
        await first.value
        await second.value
        #expect(log.events == [1, 2, 3], "Commands complete in arrival order")
    }

    @Test("a command's result survives the queue")
    func returnsOperationResult() async {
        let serializer = MoveSerializer()

        let value = await serializer.run { 42 }

        #expect(value == 42)
    }

    @Test("cancelling the surface task does not abandon an admitted command")
    func cancellationDoesNotAbandonOperation() async {
        let serializer = MoveSerializer()
        let log = EventLog()
        let (started, startSignal) = AsyncStream.makeStream(of: Void.self)
        let (gate, release) = AsyncStream.makeStream(of: Void.self)

        let surface = Task { @MainActor in
            await serializer.run {
                log.append(1)
                startSignal.yield(())
                for await _ in gate {
                    break
                }
                log.append(2)
            }
        }
        var startIterator = started.makeAsyncIterator()
        _ = await startIterator.next()
        surface.cancel()
        release.yield(())
        release.finish()
        _ = await surface.value

        #expect(log.events == [1, 2], "A move already admitted runs to completion, never mid-mutation abandonment")

        await serializer.run {
            log.append(3)
        }
        #expect(log.events == [1, 2, 3], "The queue stays usable after a cancelled caller")
    }
}
