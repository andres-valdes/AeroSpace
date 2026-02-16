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

    func testDwindle_insertAfterMove_splitsFocusedWindow() async throws {
        // Setup: |= layout
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let w1 = TestWindow.new(id: 1, parent: root)
        let vBranch = TilingContainer(parent: root, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        let w2 = TestWindow.new(id: 2, parent: vBranch)
        TestWindow.new(id: 3, parent: vBranch)
        assertEquals(w2.focusWindow(), true)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([.window(2), .window(3)]),
        ]))

        // Move w2 left → swaps with w1. w2 should remain the focused/MRU window.
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .left)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_dwindle([
            .window(2),
            .v_dwindle([.window(1), .window(3)]),
        ]))

        // Verify MRU points to the moved window (w2), not the swapped-out window (w1)
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, w2.windowId)

        // Insert a new window — should split w2 (the moved window), not w1
        w2.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)
        _ = addDwindleWindow(id: 4, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 480, height: 1080))

        assertEquals(root.layoutDescription, .h_dwindle([
            .v_dwindle([.window(2), .window(4)]),
            .v_dwindle([.window(1), .window(3)]),
        ]))
    }

    /// Reproduce: moving a window "up" swaps diagonally instead of with the window directly above.
    ///
    /// Tree:
    /// ```
    /// h_dwindle([w1, v_dwindle([h_dwindle([w2, w3]), h_dwindle([w4, w5])])])
    /// ```
    /// Visual:
    /// ```
    /// | w1 | w2 | w3 |
    /// |    |---------|
    /// |    | w4 | w5 |
    /// ```
    /// Moving w5 up should swap with w3 (directly above), not w2 (diagonal).
    func testDwindle_moveUp_swapsWithWindowDirectlyAbove() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        TestWindow.new(id: 1, parent: root)
        let vBranch = TilingContainer(parent: root, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        let topRow = TilingContainer(parent: vBranch, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        let w2 = TestWindow.new(id: 2, parent: topRow)
        TestWindow.new(id: 3, parent: topRow)
        let bottomRow = TilingContainer(parent: vBranch, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        TestWindow.new(id: 4, parent: bottomRow)
        let w5 = TestWindow.new(id: 5, parent: bottomRow)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([
                .h_dwindle([.window(2), .window(3)]),
                .h_dwindle([.window(4), .window(5)]),
            ]),
        ]))

        // Make w2 the MRU of topRow (so the bug manifests — MRU picks w2 instead of w3)
        assertEquals(w2.focusWindow(), true)
        assertEquals(w5.focusWindow(), true)

        // Move w5 up — should swap with w3 (directly above), not w2 (MRU of topRow)
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .up)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([
                .h_dwindle([.window(2), .window(5)]),
                .h_dwindle([.window(4), .window(3)]),
            ]),
        ]))
    }

    /// Complex 6-window test with asymmetric subtree depths.
    ///
    /// Tree:
    /// ```
    /// v_dwindle([
    ///     h_dwindle([v_dwindle([w1, w2]), v_dwindle([w3, w4])]),
    ///     h_dwindle([w5, w6])
    /// ])
    /// ```
    /// Visual (2x3 grid with top half nested deeper):
    /// ```
    /// | w1 | w3 |
    /// |----|----|
    /// | w2 | w4 |
    /// |---------|
    /// | w5 | w6 |
    /// ```
    private func buildSixWindowGrid() -> (root: TilingContainer, w1: TestWindow, w2: TestWindow, w3: TestWindow, w4: TestWindow, w5: TestWindow, w6: TestWindow) {
        config.defaultRootContainerOrientation = .vertical
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let topHalf = TilingContainer(parent: root, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        let leftCol = TilingContainer(parent: topHalf, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        let w1 = TestWindow.new(id: 1, parent: leftCol)
        let w2 = TestWindow.new(id: 2, parent: leftCol)
        let rightCol = TilingContainer(parent: topHalf, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        let w3 = TestWindow.new(id: 3, parent: rightCol)
        let w4 = TestWindow.new(id: 4, parent: rightCol)
        let bottomHalf = TilingContainer(parent: root, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        let w5 = TestWindow.new(id: 5, parent: bottomHalf)
        let w6 = TestWindow.new(id: 6, parent: bottomHalf)

        assertEquals(root.layoutDescription, .v_dwindle([
            .h_dwindle([
                .v_dwindle([.window(1), .window(2)]),
                .v_dwindle([.window(3), .window(4)]),
            ]),
            .h_dwindle([.window(5), .window(6)]),
        ]))

        return (root, w1, w2, w3, w4, w5, w6)
    }

    /// w6 up → should swap with w4 (directly above, index=1 in rightCol), not w3 (index=0).
    func testDwindle_6window_moveUp_rightSide() async throws {
        let (root, w3, _, _, _, _, w6) = buildSixWindowGrid()
        // Make w3 MRU of rightCol so MRU-based targeting would pick w3 (wrong)
        assertEquals(w3.focusWindow(), true)
        assertEquals(w6.focusWindow(), true)

        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .up)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .v_dwindle([
            .h_dwindle([
                .v_dwindle([.window(1), .window(2)]),
                .v_dwindle([.window(3), .window(6)]),
            ]),
            .h_dwindle([.window(5), .window(4)]),
        ]))
    }

    /// w5 up → should swap with w2 (directly above, index=1 in leftCol), not w1 (index=0).
    func testDwindle_6window_moveUp_leftSide() async throws {
        let (root, w1, _, _, _, w5, _) = buildSixWindowGrid()
        // Make w1 MRU of leftCol so MRU-based targeting would pick w1 (wrong)
        assertEquals(w1.focusWindow(), true)
        assertEquals(w5.focusWindow(), true)

        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .up)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .v_dwindle([
            .h_dwindle([
                .v_dwindle([.window(1), .window(5)]),
                .v_dwindle([.window(3), .window(4)]),
            ]),
            .h_dwindle([.window(2), .window(6)]),
        ]))
    }

    /// w2 right → should swap with w4 (same row, index=1 in rightCol), not w3 (index=0).
    func testDwindle_6window_moveRight_mirrorsRow() async throws {
        let (root, _, w2, w3, _, _, _) = buildSixWindowGrid()
        // Make w3 MRU of rightCol so MRU-based targeting would pick w3 (wrong)
        assertEquals(w3.focusWindow(), true)
        assertEquals(w2.focusWindow(), true)

        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .right)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .v_dwindle([
            .h_dwindle([
                .v_dwindle([.window(1), .window(4)]),
                .v_dwindle([.window(3), .window(2)]),
            ]),
            .h_dwindle([.window(5), .window(6)]),
        ]))
    }

    /// w4 down → crosses from deep subtree (depth 3) into shallow subtree (depth 2).
    /// Should swap with w6 (right side, index=1 in bottomHalf), not w5 (index=0).
    func testDwindle_6window_moveDown_asymmetricDepth() async throws {
        let (root, _, _, _, w4, w5, _) = buildSixWindowGrid()
        // Make w5 MRU of bottomHalf so MRU-based targeting would pick w5 (wrong)
        assertEquals(w5.focusWindow(), true)
        assertEquals(w4.focusWindow(), true)

        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .down)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .v_dwindle([
            .h_dwindle([
                .v_dwindle([.window(1), .window(2)]),
                .v_dwindle([.window(3), .window(6)]),
            ]),
            .h_dwindle([.window(5), .window(4)]),
        ]))
    }

    /// w1 down → should swap with w2 (sibling swap within leftCol), not cross into other containers.
    func testDwindle_6window_moveDown_siblingSwap() async throws {
        let (root, w1, _, _, _, _, _) = buildSixWindowGrid()
        assertEquals(w1.focusWindow(), true)

        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .down)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .v_dwindle([
            .h_dwindle([
                .v_dwindle([.window(2), .window(1)]),
                .v_dwindle([.window(3), .window(4)]),
            ]),
            .h_dwindle([.window(5), .window(6)]),
        ]))
    }

    // MARK: - Focus tests (spatial targeting)

    /// Focus up from w5 should focus w2 (directly above), not w1 (MRU of leftCol).
    func testDwindle_6window_focusUp_spatial() async throws {
        let (_, w1, _, _, _, w5, _) = buildSixWindowGrid()
        // Make w1 MRU of leftCol so MRU-based targeting would pick w1 (wrong)
        assertEquals(w1.focusWindow(), true)
        assertEquals(w5.focusWindow(), true)

        try await FocusCommand(args: FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(.up))).run(.defaultEnv, .emptyStdin)

        assertEquals(focus.windowOrNil?.windowId, UInt32(2))
    }

    /// Focus right from w2 should focus w4 (same row), not w3 (MRU of rightCol).
    func testDwindle_6window_focusRight_spatial() async throws {
        let (_, _, w2, w3, _, _, _) = buildSixWindowGrid()
        // Make w3 MRU of rightCol
        assertEquals(w3.focusWindow(), true)
        assertEquals(w2.focusWindow(), true)

        try await FocusCommand(args: FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(.right))).run(.defaultEnv, .emptyStdin)

        assertEquals(focus.windowOrNil?.windowId, UInt32(4))
    }

    /// Focus down from w4 should focus w6 (right side of bottom row), not w5 (MRU of bottomHalf).
    func testDwindle_6window_focusDown_asymmetricDepth() async throws {
        let (_, _, _, _, w4, w5, _) = buildSixWindowGrid()
        // Make w5 MRU of bottomHalf
        assertEquals(w5.focusWindow(), true)
        assertEquals(w4.focusWindow(), true)

        try await FocusCommand(args: FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(.down))).run(.defaultEnv, .emptyStdin)

        assertEquals(focus.windowOrNil?.windowId, UInt32(6))
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
