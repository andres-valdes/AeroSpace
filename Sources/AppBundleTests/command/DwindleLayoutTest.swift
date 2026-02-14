@testable import AppBundle
import Common
import XCTest

@MainActor
final class DwindleLayoutTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.defaultRootContainerLayout = .dwindle
    }

    /// Helper: simulate adding a tiling window to a dwindle workspace.
    private func addDwindleWindow(id: UInt32, to workspace: Workspace, rect: Rect) -> TestWindow {
        let data = unbindAndGetBindingDataForNewTilingWindow(workspace, window: nil)
        let window = TestWindow.new(id: id, parent: data.parent, adaptiveWeight: data.adaptiveWeight)
        window.lastAppliedLayoutVirtualRect = rect
        assertEquals(window.focusWindow(), true)
        return window
    }

    // MARK: - Insertion tests

    func testDwindle_firstWindow() {
        let workspace = Workspace.get(byName: name)
        _ = addDwindleWindow(id: 1, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .window(1),
        ]))
    }

    func testDwindle_secondWindow_wideRect() {
        let workspace = Workspace.get(byName: name)
        // Full screen: 1920x1080 → wide → horizontal split
        _ = addDwindleWindow(id: 1, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        _ = addDwindleWindow(id: 2, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .h_dwindle([.window(1), .window(2)]),
        ]))
    }

    func testDwindle_secondWindow_tallRect() {
        let workspace = Workspace.get(byName: name)
        // Tall rect → vertical split
        _ = addDwindleWindow(id: 1, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 500, height: 1080))
        _ = addDwindleWindow(id: 2, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 500, height: 1080))

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .v_dwindle([.window(1), .window(2)]),
        ]))
    }

    func testDwindle_thirdWindow() {
        let workspace = Workspace.get(byName: name)
        _ = addDwindleWindow(id: 1, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        // After first split, w2 gets right half (tall)
        _ = addDwindleWindow(id: 2, to: workspace, rect: .init(topLeftX: 960, topLeftY: 0, width: 960, height: 1080))
        _ = addDwindleWindow(id: 3, to: workspace, rect: .init(topLeftX: 960, topLeftY: 0, width: 960, height: 1080))

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .h_dwindle([
                .window(1),
                .v_dwindle([.window(2), .window(3)]),
            ]),
        ]))
    }

    func testDwindle_fourthWindow() {
        let workspace = Workspace.get(byName: name)
        _ = addDwindleWindow(id: 1, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        _ = addDwindleWindow(id: 2, to: workspace, rect: .init(topLeftX: 960, topLeftY: 0, width: 960, height: 1080))
        _ = addDwindleWindow(id: 3, to: workspace, rect: .init(topLeftX: 960, topLeftY: 540, width: 960, height: 540))
        // w3 gets bottom-right quarter (square/wide → horizontal split)
        _ = addDwindleWindow(id: 4, to: workspace, rect: .init(topLeftX: 960, topLeftY: 540, width: 960, height: 540))

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .h_dwindle([
                .window(1),
                .v_dwindle([
                    .window(2),
                    .h_dwindle([.window(3), .window(4)]),
                ]),
            ]),
        ]))
    }

    func testDwindle_splitFirstWindow() {
        let workspace = Workspace.get(byName: name)
        let w1 = addDwindleWindow(id: 1, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        _ = addDwindleWindow(id: 2, to: workspace, rect: .init(topLeftX: 960, topLeftY: 0, width: 960, height: 1080))

        // Focus window1 — it becomes MRU. It now occupies left half (tall).
        assertEquals(w1.focusWindow(), true)
        w1.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)
        _ = addDwindleWindow(id: 3, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 960, height: 540))

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .h_dwindle([
                .v_dwindle([.window(1), .window(3)]),
                .window(2),
            ]),
        ]))
    }

    // MARK: - Normalization tests

    func testDwindle_removeWindow_normalization() {
        let workspace = Workspace.get(byName: name)

        // Build a 4-window dwindle tree manually
        let root = workspace.rootTilingContainer
        let hBranch = TilingContainer(parent: root, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        TestWindow.new(id: 1, parent: hBranch)
        let vBranch = TilingContainer(parent: hBranch, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        TestWindow.new(id: 2, parent: vBranch)
        let hBranch2 = TilingContainer(parent: vBranch, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        let w3 = TestWindow.new(id: 3, parent: hBranch2)
        TestWindow.new(id: 4, parent: hBranch2)

        assertEquals(root.layoutDescription, .h_dwindle([
            .h_dwindle([
                .window(1),
                .v_dwindle([
                    .window(2),
                    .h_dwindle([.window(3), .window(4)]),
                ]),
            ]),
        ]))

        // Remove window3 and normalize
        config.enableNormalizationFlattenContainers = true
        w3.unbindFromParent()
        workspace.normalizeContainers()

        // hBranch2 has 1 child (window4) → flattened into vBranch.
        // hBranch is the only child of root → replaces root.
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([.window(2), .window(4)]),
        ]))
    }

    // MARK: - Move tests
    //
    // Dwindle moves use the same logic as focus: find the nearest window in the
    // target direction via closestParent + findLeafWindowRecursive, then swap.
    // For perpendicular containers, the MRU child is chosen (matching focus).

    /// Build a 4-window dwindle tree:
    /// ```
    /// h_dwindle([window(1), v_dwindle([window(2), h_dwindle([window(3), window(4)])])])
    /// ```
    /// Visual layout:
    /// ```
    /// |  w1  | w2 |
    /// |      |----|
    /// |      |w3|w4|
    /// ```
    private func buildFourWindowTree() -> (root: TilingContainer, w1: TestWindow, w2: TestWindow, w3: TestWindow, w4: TestWindow) {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let w1 = TestWindow.new(id: 1, parent: root)
        let vBranch = TilingContainer(parent: root, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        let w2 = TestWindow.new(id: 2, parent: vBranch)
        let hBranch = TilingContainer(parent: vBranch, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        let w3 = TestWindow.new(id: 3, parent: hBranch)
        let w4 = TestWindow.new(id: 4, parent: hBranch)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([.window(2), .h_dwindle([.window(3), .window(4)])]),
        ]))

        return (root, w1, w2, w3, w4)
    }

    func testDwindle_moveRight_intoContainer() async throws {
        let (root, w1, w2, _, _) = buildFourWindowTree()
        // Set w2 as MRU of v_dwindle, then focus w1 for the move
        assertEquals(w2.focusWindow(), true)
        assertEquals(w1.focusWindow(), true)

        // Move w1 right → sibling is v_dwindle.
        // findLeafWindowRecursive picks MRU of v_dwindle → w2. Swap w1 ↔ w2.
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .right)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(2),
            .v_dwindle([.window(1), .h_dwindle([.window(3), .window(4)])]),
        ]))
    }

    func testDwindle_moveLeft_crossBranch() async throws {
        let (root, _, _, w3, _) = buildFourWindowTree()
        assertEquals(w3.focusWindow(), true)

        // Move w3 left → crosses from h_dwindle up through v_dwindle to root.
        // Sibling at root level is w1. Swap w3 ↔ w1.
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .left)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(3),
            .v_dwindle([.window(2), .h_dwindle([.window(1), .window(4)])]),
        ]))
    }

    func testDwindle_moveUp_crossBranch() async throws {
        let (root, _, _, _, w4) = buildFourWindowTree()
        assertEquals(w4.focusWindow(), true)

        // Move w4 up → h_dwindle parent has .h orientation, no match for .up.
        // Walks up to v_dwindle (orientation=.v). Sibling is w2. Swap w4 ↔ w2.
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .up)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([.window(4), .h_dwindle([.window(3), .window(2)])]),
        ]))
    }

    func testDwindle_moveLeft_siblingSwap() async throws {
        let (root, _, _, _, w4) = buildFourWindowTree()
        assertEquals(w4.focusWindow(), true)

        // Move w4 left → sibling w3 in same h_dwindle. Direct swap.
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .left)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([.window(2), .h_dwindle([.window(4), .window(3)])]),
        ]))
    }

    func testDwindle_moveDown_intoSubtree() async throws {
        let (root, _, w2, w3, _) = buildFourWindowTree()
        // Set w3 as MRU of h_dwindle, then focus w2 for the move
        assertEquals(w3.focusWindow(), true)
        assertEquals(w2.focusWindow(), true)

        // Move w2 down → sibling is h_dwindle(w3, w4).
        // findLeafWindowRecursive picks MRU of h_dwindle → w3. Swap w2 ↔ w3.
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .down)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([.window(3), .h_dwindle([.window(2), .window(4)])]),
        ]))
    }

    func testDwindle_moveRight_atBoundary() async throws {
        let (root, _, _, _, w4) = buildFourWindowTree()
        assertEquals(w4.focusWindow(), true)

        // Move w4 right with --boundaries-action stop → hits workspace boundary, no change.
        var args = MoveCmdArgs(rawArgs: [], .right)
        args.rawBoundariesAction = .stop
        try await MoveCommand(args: args).run(.defaultEnv, .emptyStdin)

        // Tree unchanged
        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([.window(2), .h_dwindle([.window(3), .window(4)])]),
        ]))
    }
}
