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

    // MARK: - Move-node-to-workspace tests

    /// Moving a window from workspace A to dwindle workspace B (which has || layout)
    /// should use dwindle insertion (split MRU window), not just append to root container.
    func testDwindle_moveNodeToWorkspace_usesDwindleInsertion() async throws {
        // Workspace A: one window
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        // Workspace B: dwindle with two windows side by side (||)
        let workspaceB = Workspace.get(byName: "b")
        let rootB = workspaceB.rootTilingContainer
        let w2 = TestWindow.new(id: 2, parent: rootB)
        TestWindow.new(id: 3, parent: rootB)
        // Focus w2 so it becomes MRU — new window should split w2
        assertEquals(w2.focusWindow(), true)
        w2.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)

        assertEquals(rootB.layoutDescription, .h_dwindle([
            .window(2),
            .window(3),
        ]))

        // Move w1 from workspace A to workspace B
        // Focus w1 first so it's the subject of the move
        assertEquals(TestWindow.get(byId: 1)!.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        // Should use dwindle insertion: split MRU window (w2), NOT append as |||
        assertEquals(rootB.layoutDescription, .h_dwindle([
            .v_dwindle([.window(2), .window(1)]),
            .window(3),
        ]))
    }

    /// join-with in a dwindle workspace should create a dwindle container
    /// with orientation based on the target window's rect (wider = .h, taller = .v).
    func testDwindle_joinWith_usesDwindleOrientation() async throws {
        let workspace = Workspace.get(byName: "a")
        let root = workspace.rootTilingContainer
        let w1 = TestWindow.new(id: 1, parent: root)
        assertEquals(w1.focusWindow(), true)
        let w2 = TestWindow.new(id: 2, parent: root)
        let w3 = TestWindow.new(id: 3, parent: root)
        // Give w2 a wide rect so the dwindle split should be horizontal
        w2.lastAppliedLayoutVirtualRect = .init(topLeftX: 640, topLeftY: 0, width: 1280, height: 540)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .window(2),
            .window(3),
        ]))

        // join-with right: w1 should split into w2's position using dwindle logic
        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)

        // w2 is wide → horizontal dwindle split; w1 joins as first child (positive direction)
        assertEquals(root.layoutDescription, .h_dwindle([
            .h_dwindle([
                .window(1),
                .window(2),
            ]),
            .window(3),
        ]))
    }

    /// join-with in dwindle uses spatial positioning along the dwindle-determined orientation.
    /// Dwindle picks .v (tall target), so spatial comparison is along y-axis.
    /// Without spatial logic, direction-based (.left = negative) would put w2 at bottom — spatial overrides this.
    func testDwindle_joinWith_spatialPositioning() async throws {
        let workspace = Workspace.get(byName: "a")
        let root = workspace.rootTilingContainer
        let w1 = TestWindow.new(id: 1, parent: root)
        w1.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 960, height: 1080) // tall → .v
        let w2 = TestWindow.new(id: 2, parent: root)
        w2.lastAppliedLayoutVirtualRect = .init(topLeftX: 960, topLeftY: 0, width: 960, height: 540) // top-right
        assertEquals(w2.focusWindow(), true)
        let w3 = TestWindow.new(id: 3, parent: root)

        // w2 joins left into w1
        // w1 is tall (960x1080) → dwindle picks .v orientation for new container
        // Spatial along .v: w2 center y=270 < w1 center y=540 → w2 on top
        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .left)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_dwindle([
            .v_dwindle([
                .window(2),
                .window(1),
            ]),
            .window(3),
        ]))
    }

    /// When two siblings are the only children of a dwindle container and the dwindle-determined
    /// orientation matches the parent's, fall back to opposite orientation. Otherwise normalization
    /// flattens the singleton parent and the join becomes a no-op.
    func testDwindle_joinWith_siblingPairFallsBackToOpposite() async throws {
        let workspace = Workspace.get(byName: "a")
        let root = workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        let hBranch = TilingContainer(parent: root, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        let w2 = TestWindow.new(id: 2, parent: hBranch)
        w2.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 540, width: 960, height: 540) // wide
        let w3 = TestWindow.new(id: 3, parent: hBranch)
        w3.lastAppliedLayoutVirtualRect = .init(topLeftX: 960, topLeftY: 540, width: 960, height: 540) // wide
        assertEquals(w2.focusWindow(), true)

        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .h_dwindle([.window(2), .window(3)]),
        ]))

        // w3 is wide → dwindle would pick .h, same as parent. Should fall back to .v.
        // Normalization is disabled in tests, so we can verify the new container orientation directly.
        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)

        // Both windows have the same y-center (same row), so spatial comparison
        // along .v sees equal positions → w2 goes to INDEX_BIND_LAST
        assertEquals(root.layoutDescription, .h_dwindle([
            .window(1),
            .h_dwindle([
                .v_dwindle([
                    .window(3),
                    .window(2),
                ]),
            ]),
        ]))
    }

    /// join-with in a dwindle workspace where the target is a container (not a window)
    /// should fall back to parent.orientation.opposite for the new container orientation.
    func testDwindle_joinWith_containerTarget_fallback() async throws {
        let workspace = Workspace.get(byName: "a")
        let root = workspace.rootTilingContainer
        let w1 = TestWindow.new(id: 1, parent: root)
        let vBranch = TilingContainer(parent: root, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        TestWindow.new(id: 2, parent: vBranch)
        TestWindow.new(id: 3, parent: vBranch)
        assertEquals(w1.focusWindow(), true)

        // join-with right: target is v_dwindle([w2, w3]) — a container, not a window.
        // Falls back to parent.orientation.opposite: root is .h → new container is .v
        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_dwindle([
            .v_dwindle([
                .window(1),
                .v_dwindle([
                    .window(2),
                    .window(3),
                ]),
            ]),
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

    // MARK: - Binary property preservation tests

    /// Helper: recursively assert that every dwindle container has at most 2 children.
    private func assertDwindleBinaryProperty(_ container: TilingContainer, file: StaticString = #filePath, line: UInt = #line) {
        if container.layout == .dwindle {
            XCTAssertLessThanOrEqual(
                container.children.count, 2,
                "Dwindle container has \(container.children.count) children (expected ≤ 2): \(container.layoutDescription)",
                file: file, line: line
            )
        }
        for child in container.children {
            if let childContainer = child as? TilingContainer {
                assertDwindleBinaryProperty(childContainer, file: file, line: line)
            }
        }
    }

    /// Move a window to another workspace and back — tree should remain binary.
    func testDwindle_moveToWorkspaceAndBack_preservesBinary() async throws {
        let wsA = Workspace.get(byName: "a")
        let rootA = wsA.rootTilingContainer

        // Build a 3-window dwindle tree in workspace A
        let w1 = TestWindow.new(id: 1, parent: rootA)
        let vBranch = TilingContainer(parent: rootA, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        let w2 = TestWindow.new(id: 2, parent: vBranch)
        TestWindow.new(id: 3, parent: vBranch)
        w2.lastAppliedLayoutVirtualRect = .init(topLeftX: 960, topLeftY: 0, width: 960, height: 540)
        assertEquals(w1.focusWindow(), true)
        w1.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)

        assertEquals(rootA.layoutDescription, .h_dwindle([
            .window(1),
            .v_dwindle([.window(2), .window(3)]),
        ]))

        // Move w1 to workspace B
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        // Normalize workspace A after removal
        config.enableNormalizationFlattenContainers = true
        wsA.normalizeContainers()

        assertDwindleBinaryProperty(wsA.rootTilingContainer)

        // Move w1 back to workspace A (focus it first)
        assertEquals(w1.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "a")).run(.defaultEnv, .emptyStdin)

        assertDwindleBinaryProperty(wsA.rootTilingContainer)
    }

    /// Removing a window and then inserting a new one should maintain binary property.
    func testDwindle_removeAndInsert_preservesBinary() {
        let workspace = Workspace.get(byName: "a")

        // Build 4-window tree
        _ = addDwindleWindow(id: 1, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        let w2 = addDwindleWindow(id: 2, to: workspace, rect: .init(topLeftX: 960, topLeftY: 0, width: 960, height: 1080))
        _ = addDwindleWindow(id: 3, to: workspace, rect: .init(topLeftX: 960, topLeftY: 540, width: 960, height: 540))
        _ = addDwindleWindow(id: 4, to: workspace, rect: .init(topLeftX: 960, topLeftY: 540, width: 480, height: 540))

        assertDwindleBinaryProperty(workspace.rootTilingContainer)

        // Remove w2 and normalize
        config.enableNormalizationFlattenContainers = true
        w2.unbindFromParent()
        workspace.normalizeContainers()

        assertDwindleBinaryProperty(workspace.rootTilingContainer)

        // Insert a new window — should still be binary
        _ = addDwindleWindow(id: 5, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 960, height: 540))

        assertDwindleBinaryProperty(workspace.rootTilingContainer)
    }

    /// With opposite-orientation normalization disabled, same-orientation nesting is preserved.
    /// This is the recommended config for dwindle (enable-normalization-opposite-orientation-for-nested-containers = false).
    func testDwindle_normalization_disabled_preservesSameOrientationNesting() {
        let workspace = Workspace.get(byName: "a")
        let root = workspace.rootTilingContainer

        // Create h_dwindle inside h_dwindle (same-orientation nesting, valid for dwindle)
        let hBranch = TilingContainer(parent: root, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        TestWindow.new(id: 1, parent: hBranch)
        TestWindow.new(id: 2, parent: hBranch)
        TestWindow.new(id: 3, parent: root)

        assertEquals(root.layoutDescription, .h_dwindle([
            .h_dwindle([.window(1), .window(2)]),
            .window(3),
        ]))

        // With opposite-orientation normalization OFF, orientations are preserved
        config.enableNormalizationOppositeOrientationForNestedContainers = false
        workspace.normalizeContainers()

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .h_dwindle([.window(1), .window(2)]),
            .window(3),
        ]))
    }

    /// Multiple move-node-to-workspace operations should maintain binary property.
    func testDwindle_multipleWorkspaceMoves_preservesBinary() async throws {
        let wsA = Workspace.get(byName: "a")
        let wsB = Workspace.get(byName: "b")

        // Create 3 windows in workspace A
        let w1 = TestWindow.new(id: 1, parent: wsA.rootTilingContainer)
        w1.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        assertEquals(w1.focusWindow(), true)

        let w2 = addDwindleWindow(id: 2, to: wsA, rect: .init(topLeftX: 960, topLeftY: 0, width: 960, height: 1080))
        let w3 = addDwindleWindow(id: 3, to: wsA, rect: .init(topLeftX: 960, topLeftY: 540, width: 960, height: 540))

        assertDwindleBinaryProperty(wsA.rootTilingContainer)

        // Move w2 to workspace B
        assertEquals(w2.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        config.enableNormalizationFlattenContainers = true
        wsA.normalizeContainers()

        assertDwindleBinaryProperty(wsA.rootTilingContainer)
        assertDwindleBinaryProperty(wsB.rootTilingContainer)

        // Move w3 to workspace B
        assertEquals(w3.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        wsA.normalizeContainers()

        assertDwindleBinaryProperty(wsA.rootTilingContainer)
        assertDwindleBinaryProperty(wsB.rootTilingContainer)

        // Move w1 to workspace B (all 3 in B now)
        assertEquals(w1.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        wsA.normalizeContainers()

        assertDwindleBinaryProperty(wsB.rootTilingContainer)
    }

    /// Dwindle insertion with same-orientation rect creates same-orientation nesting.
    /// With opposite-orientation normalization disabled, the nesting is preserved after flattening.
    func testDwindle_insertSameOrientation_preservedWithNormalizationOff() {
        let workspace = Workspace.get(byName: "a")

        // First window: wide rect
        _ = addDwindleWindow(id: 1, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        // Second window: also wide (same as parent h orientation → h inside h)
        _ = addDwindleWindow(id: 2, to: workspace, rect: .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))

        // Before normalization: should have h_dwindle inside h_dwindle
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .h_dwindle([.window(1), .window(2)]),
        ]))

        // After normalization with opposite-orientation disabled (recommended for dwindle)
        config.enableNormalizationFlattenContainers = true
        config.enableNormalizationOppositeOrientationForNestedContainers = false
        workspace.normalizeContainers()

        // Root had 1 child → flattened. Orientation preserved as .h
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_dwindle([
            .window(1), .window(2),
        ]))
    }

    /// After multiple swaps via move command, binary property is maintained.
    func testDwindle_multipleSwaps_preservesBinary() async throws {
        let (root, w1, _, w3, w4) = buildFourWindowTree()

        // Series of moves
        assertEquals(w4.focusWindow(), true)
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .left)).run(.defaultEnv, .emptyStdin)  // w4 ↔ w3
        assertDwindleBinaryProperty(root)

        assertEquals(w4.focusWindow(), true)
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .up)).run(.defaultEnv, .emptyStdin)    // w4 ↔ w2
        assertDwindleBinaryProperty(root)

        assertEquals(w1.focusWindow(), true)
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .right)).run(.defaultEnv, .emptyStdin) // w1 ↔ MRU of right subtree
        assertDwindleBinaryProperty(root)

        assertEquals(w3.focusWindow(), true)
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .left)).run(.defaultEnv, .emptyStdin)  // w3 ↔ w1 (now left)
        assertDwindleBinaryProperty(root)
    }

    /// join-with should maintain binary property on the resulting tree.
    func testDwindle_joinWith_preservesBinary() async throws {
        let workspace = Workspace.get(byName: "a")
        let root = workspace.rootTilingContainer
        let w1 = TestWindow.new(id: 1, parent: root)
        TestWindow.new(id: 2, parent: root)
        let w3 = TestWindow.new(id: 3, parent: root)

        // join-with right from w1
        assertEquals(w1.focusWindow(), true)
        w1.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 640, height: 1080)
        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)
        assertDwindleBinaryProperty(root)

        // join-with left from w3
        assertEquals(w3.focusWindow(), true)
        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .left)).run(.defaultEnv, .emptyStdin)
        assertDwindleBinaryProperty(root)
    }

    // MARK: - Move-to-workspace: exhaustive permutations

    /// BUG REPRO: When workspace has a floating window as MRU, moving a tiling window
    /// into it bypasses dwindleInsert and appends directly to root, creating a 3rd child.
    func testDwindle_moveToWorkspace_withFloatingWindowMRU_preservesBinary() async throws {
        let wsA = Workspace.get(byName: "a")
        let wsB = Workspace.get(byName: "b")

        // Workspace A: one tiling window
        let w1 = TestWindow.new(id: 1, parent: wsA.rootTilingContainer)
        assertEquals(w1.focusWindow(), true)

        // Workspace B: two tiling windows + one floating window
        let rootB = wsB.rootTilingContainer
        let w2 = TestWindow.new(id: 2, parent: rootB)
        TestWindow.new(id: 3, parent: rootB)
        w2.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)

        // Add a floating window to workspace B and focus it (makes it the workspace MRU)
        let wFloat = TestWindow.new(id: 99, parent: wsB, adaptiveWeight: WEIGHT_AUTO)
        assertEquals(wFloat.focusWindow(), true)

        // Now focus w1 (on workspace A) to make it the subject of the move
        assertEquals(w1.focusWindow(), true)

        // Move w1 to workspace B — should NOT append to root as 3rd child
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        assertDwindleBinaryProperty(wsB.rootTilingContainer)
    }

    /// Move into workspace with 2 tiling windows (MRU = first child).
    func testDwindle_moveToWorkspace_2windows_mruFirst() async throws {
        let wsA = Workspace.get(byName: "a")
        let wsB = Workspace.get(byName: "b")

        let w1 = TestWindow.new(id: 1, parent: wsA.rootTilingContainer)
        assertEquals(w1.focusWindow(), true)

        let rootB = wsB.rootTilingContainer
        let w2 = TestWindow.new(id: 2, parent: rootB)
        TestWindow.new(id: 3, parent: rootB)
        assertEquals(w2.focusWindow(), true)
        w2.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)

        assertEquals(w1.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        assertDwindleBinaryProperty(rootB)
        assertEquals(rootB.children.count, 2)
    }

    /// Move into workspace with 2 tiling windows (MRU = second child).
    func testDwindle_moveToWorkspace_2windows_mruSecond() async throws {
        let wsA = Workspace.get(byName: "a")
        let wsB = Workspace.get(byName: "b")

        let w1 = TestWindow.new(id: 1, parent: wsA.rootTilingContainer)
        assertEquals(w1.focusWindow(), true)

        let rootB = wsB.rootTilingContainer
        TestWindow.new(id: 2, parent: rootB)
        let w3 = TestWindow.new(id: 3, parent: rootB)
        assertEquals(w3.focusWindow(), true)
        w3.lastAppliedLayoutVirtualRect = .init(topLeftX: 960, topLeftY: 0, width: 960, height: 1080)

        assertEquals(w1.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        assertDwindleBinaryProperty(rootB)
        assertEquals(rootB.children.count, 2)
    }

    /// Move into deep binary tree (MRU = leaf node deep in tree).
    func testDwindle_moveToWorkspace_deepTree_mruDeepLeaf() async throws {
        let wsA = Workspace.get(byName: "a")
        let wsB = Workspace.get(byName: "b")

        let w1 = TestWindow.new(id: 1, parent: wsA.rootTilingContainer)
        assertEquals(w1.focusWindow(), true)

        // Build a 4-window tree in workspace B
        let rootB = wsB.rootTilingContainer
        TestWindow.new(id: 2, parent: rootB)
        let vBranch = TilingContainer(parent: rootB, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        TestWindow.new(id: 3, parent: vBranch)
        let hBranch = TilingContainer(parent: vBranch, adaptiveWeight: 1, .h, .dwindle, index: INDEX_BIND_LAST)
        let w4 = TestWindow.new(id: 4, parent: hBranch)
        TestWindow.new(id: 5, parent: hBranch)
        assertEquals(w4.focusWindow(), true)
        w4.lastAppliedLayoutVirtualRect = .init(topLeftX: 960, topLeftY: 540, width: 480, height: 540)

        assertEquals(w1.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        assertDwindleBinaryProperty(rootB)
    }

    /// Move two windows sequentially into the same workspace.
    func testDwindle_moveToWorkspace_twoSequentialMoves() async throws {
        let wsA = Workspace.get(byName: "a")
        let wsB = Workspace.get(byName: "b")

        let w1 = TestWindow.new(id: 1, parent: wsA.rootTilingContainer)
        let w2 = TestWindow.new(id: 2, parent: wsA.rootTilingContainer)

        // Workspace B has 2 windows
        let rootB = wsB.rootTilingContainer
        let w3 = TestWindow.new(id: 3, parent: rootB)
        TestWindow.new(id: 4, parent: rootB)
        assertEquals(w3.focusWindow(), true)
        w3.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)

        // Move w1 to B
        assertEquals(w1.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        assertDwindleBinaryProperty(rootB)

        // Move w2 to B
        assertEquals(w2.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        assertDwindleBinaryProperty(rootB)
    }

    /// Move three windows sequentially into the same workspace.
    func testDwindle_moveToWorkspace_threeSequentialMoves() async throws {
        let wsA = Workspace.get(byName: "a")
        let wsB = Workspace.get(byName: "b")

        let w1 = TestWindow.new(id: 1, parent: wsA.rootTilingContainer)
        let w2 = TestWindow.new(id: 2, parent: wsA.rootTilingContainer)
        let w3 = TestWindow.new(id: 3, parent: wsA.rootTilingContainer)

        // Workspace B has 1 window
        let rootB = wsB.rootTilingContainer
        let w4 = TestWindow.new(id: 4, parent: rootB)
        assertEquals(w4.focusWindow(), true)
        w4.lastAppliedLayoutVirtualRect = .init(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)

        // Move w1
        assertEquals(w1.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        assertDwindleBinaryProperty(rootB)

        // Move w2
        assertEquals(w2.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        assertDwindleBinaryProperty(rootB)

        // Move w3
        assertEquals(w3.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        assertDwindleBinaryProperty(rootB)
    }

    /// Move into workspace where MRU window has no lastAppliedLayoutVirtualRect.
    func testDwindle_moveToWorkspace_mruWithoutRect() async throws {
        let wsA = Workspace.get(byName: "a")
        let wsB = Workspace.get(byName: "b")

        let w1 = TestWindow.new(id: 1, parent: wsA.rootTilingContainer)
        assertEquals(w1.focusWindow(), true)

        // Workspace B: 2 windows, MRU has NO rect (simulates window that hasn't been laid out)
        let rootB = wsB.rootTilingContainer
        let w2 = TestWindow.new(id: 2, parent: rootB)
        TestWindow.new(id: 3, parent: rootB)
        assertEquals(w2.focusWindow(), true)
        // NOTE: w2.lastAppliedLayoutVirtualRect is nil

        assertEquals(w1.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        assertDwindleBinaryProperty(rootB)
        assertEquals(rootB.children.count, 2)
    }

    /// Move into workspace after normalization has flattened containers.
    func testDwindle_moveToWorkspace_afterNormalization() async throws {
        let wsA = Workspace.get(byName: "a")
        let wsB = Workspace.get(byName: "b")

        let w1 = TestWindow.new(id: 1, parent: wsA.rootTilingContainer)
        assertEquals(w1.focusWindow(), true)

        // Workspace B: build a tree, remove a window, normalize
        let rootB = wsB.rootTilingContainer
        TestWindow.new(id: 2, parent: rootB)
        let vBranch = TilingContainer(parent: rootB, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        let w3 = TestWindow.new(id: 3, parent: vBranch)
        let w4 = TestWindow.new(id: 4, parent: vBranch)
        assertEquals(w4.focusWindow(), true)
        w4.lastAppliedLayoutVirtualRect = .init(topLeftX: 960, topLeftY: 540, width: 960, height: 540)

        // Remove w3 → v_dwindle has 1 child → normalize flattens it
        w3.unbindFromParent()
        config.enableNormalizationFlattenContainers = true
        wsB.normalizeContainers()

        // Should now be h_dwindle([w2, w4])
        assertDwindleBinaryProperty(wsB.rootTilingContainer)

        // Move w1 into the normalized workspace
        assertEquals(w1.focusWindow(), true)
        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        assertDwindleBinaryProperty(wsB.rootTilingContainer)
    }
}
