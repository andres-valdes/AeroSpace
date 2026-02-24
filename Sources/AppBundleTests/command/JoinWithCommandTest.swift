@testable import AppBundle
import Common
import XCTest

@MainActor
final class JoinWithCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testMoveIn() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([
                .window(1),
                .window(2),
            ]),
        ]))
    }

    /// Top-right quadrant window joins left into left-half window -> should end up on TOP of new vertical container.
    func testJoinWithLeftFromTopRight() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            let w1 = TestWindow.new(id: 1, parent: $0) // left half
            w1.lastAppliedLayoutVirtualRect = Rect(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)

            let vRight = TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            let w2 = TestWindow.new(id: 2, parent: vRight) // top-right
            w2.lastAppliedLayoutVirtualRect = Rect(topLeftX: 960, topLeftY: 0, width: 960, height: 540)
            assertEquals(w2.focusWindow(), true)
            let w3 = TestWindow.new(id: 3, parent: vRight) // bottom-right
            w3.lastAppliedLayoutVirtualRect = Rect(topLeftX: 960, topLeftY: 540, width: 960, height: 540)
        }

        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .left)).run(.defaultEnv, .emptyStdin)
        // w2 (top-right, center y=270) should be ABOVE w1 (left-half, center y=540)
        // vRight remains as singleton container around w3 (join-with doesn't normalize)
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([
                .window(2),
                .window(1),
            ]),
            .v_tiles([
                .window(3),
            ]),
        ]))
    }

    /// Bottom-right quadrant window joins left into left-half window -> should end up on BOTTOM of new vertical container.
    func testJoinWithLeftFromBottomRight() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            let w1 = TestWindow.new(id: 1, parent: $0) // left half
            w1.lastAppliedLayoutVirtualRect = Rect(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)

            let vRight = TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            let w2 = TestWindow.new(id: 2, parent: vRight) // top-right
            w2.lastAppliedLayoutVirtualRect = Rect(topLeftX: 960, topLeftY: 0, width: 960, height: 540)
            let w3 = TestWindow.new(id: 3, parent: vRight) // bottom-right
            w3.lastAppliedLayoutVirtualRect = Rect(topLeftX: 960, topLeftY: 540, width: 960, height: 540)
            assertEquals(w3.focusWindow(), true)
        }

        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .left)).run(.defaultEnv, .emptyStdin)
        // w3 (bottom-right, center y=810) should be BELOW w1 (left-half, center y=540)
        // vRight remains as singleton container around w2
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([
                .window(1),
                .window(3),
            ]),
            .v_tiles([
                .window(2),
            ]),
        ]))
    }

    /// Deeply nested window joins left, skipping vertical containers to reach root -> spatial position preserved.
    func testJoinWithDeeplyNested() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            let w1 = TestWindow.new(id: 1, parent: $0) // left half
            w1.lastAppliedLayoutVirtualRect = Rect(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)

            let vRight = TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            let w2 = TestWindow.new(id: 2, parent: vRight) // top-right
            w2.lastAppliedLayoutVirtualRect = Rect(topLeftX: 960, topLeftY: 0, width: 960, height: 540)

            let vBottomRight = TilingContainer.newVTiles(parent: vRight, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            let w3 = TestWindow.new(id: 3, parent: vBottomRight)
            w3.lastAppliedLayoutVirtualRect = Rect(topLeftX: 960, topLeftY: 540, width: 960, height: 270)
            let w4 = TestWindow.new(id: 4, parent: vBottomRight) // deeply nested, bottom
            w4.lastAppliedLayoutVirtualRect = Rect(topLeftX: 960, topLeftY: 810, width: 960, height: 270)
            assertEquals(w4.focusWindow(), true)
        }

        // w4's parents are all v_tiles, so closestParent skips them for .left, reaching root
        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .left)).run(.defaultEnv, .emptyStdin)
        // w4 (center y=945) should be BELOW w1 (center y=540)
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([
                .window(1),
                .window(4),
            ]),
            .v_tiles([
                .window(2),
                .v_tiles([
                    .window(3),
                ]),
            ]),
        ]))
    }

    /// Window joins with a TilingContainer target -> spatial comparison uses container's rect.
    func testJoinWithTargetIsContainer() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            let w1 = TestWindow.new(id: 1, parent: $0) // left
            w1.lastAppliedLayoutVirtualRect = Rect(topLeftX: 0, topLeftY: 0, width: 640, height: 1080)
            assertEquals(w1.focusWindow(), true)

            let vRight = TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            vRight.lastAppliedLayoutVirtualRect = Rect(topLeftX: 640, topLeftY: 0, width: 640, height: 1080)
            let w2 = TestWindow.new(id: 2, parent: vRight)
            w2.lastAppliedLayoutVirtualRect = Rect(topLeftX: 640, topLeftY: 0, width: 640, height: 540)
            let w3 = TestWindow.new(id: 3, parent: vRight)
            w3.lastAppliedLayoutVirtualRect = Rect(topLeftX: 640, topLeftY: 540, width: 640, height: 540)
        }

        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)
        // w1 (center y=540) == vRight container (center y=540), equal centers -> INDEX_BIND_LAST
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([
                .v_tiles([
                    .window(2),
                    .window(3),
                ]),
                .window(1),
            ]),
        ]))
    }

    /// No rects available -> falls back to direction-based ordering (existing behavior preserved).
    func testJoinWithFallbackWhenNoRects() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }

        // No lastAppliedLayoutVirtualRect set on any window -> fallback to direction-based
        try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)
        // direction=right is positive -> currentWindowIndex=0 -> current window first
        assertEquals(root.layoutDescription, .h_tiles([
            .window(1),
            .v_tiles([
                .window(2),
                .window(3),
            ]),
        ]))
    }
}
