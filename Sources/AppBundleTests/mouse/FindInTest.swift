@testable import AppBundle
import Common
import XCTest

@MainActor
final class FindInTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testFindInTilingWindows() {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer

        let w1 = TestWindow.new(id: 1, parent: root)
        let w2 = TestWindow.new(id: 2, parent: root)

        // Layout: w1 is left half [0,0 - 640,1080], w2 is right half [640,0 - 1280,1080]
        w1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 640, height: 1080)
        w2.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 640, topLeftY: 0, width: 640, height: 1080)

        let point1 = CGPoint(x: 320, y: 540) // Center of w1
        assertEquals(point1.findIn(tree: root, virtual: false)?.windowId, 1)

        let point2 = CGPoint(x: 960, y: 540) // Center of w2
        assertEquals(point2.findIn(tree: root, virtual: false)?.windowId, 2)
    }

    func testFindInReturnsNilOutsideAllWindows() {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer

        let w1 = TestWindow.new(id: 1, parent: root)
        w1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 640, height: 1080)

        let outside = CGPoint(x: 800, y: 540)
        assertEquals(outside.findIn(tree: root, virtual: false)?.windowId, nil)
    }

    func testFindInNestedContainers() {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer

        let w1 = TestWindow.new(id: 1, parent: root)
        w1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 640, height: 1080)

        let vContainer = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1)
        vContainer.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 640, topLeftY: 0, width: 640, height: 1080)

        let w2 = TestWindow.new(id: 2, parent: vContainer)
        let w3 = TestWindow.new(id: 3, parent: vContainer)
        w2.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 640, topLeftY: 0, width: 640, height: 540)
        w3.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 640, topLeftY: 540, width: 640, height: 540)

        let point1 = CGPoint(x: 320, y: 540) // In w1
        assertEquals(point1.findIn(tree: root, virtual: false)?.windowId, 1)

        let point2 = CGPoint(x: 960, y: 270) // In w2 (top-right)
        assertEquals(point2.findIn(tree: root, virtual: false)?.windowId, 2)

        let point3 = CGPoint(x: 960, y: 810) // In w3 (bottom-right)
        assertEquals(point3.findIn(tree: root, virtual: false)?.windowId, 3)
    }

    func testFindInAccordionUseMru() {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer

        let accordion = TilingContainer(parent: root, adaptiveWeight: 1, .h, .accordion, index: INDEX_BIND_LAST)
        accordion.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 1280, height: 1080)

        let w1 = TestWindow.new(id: 1, parent: accordion)
        let w2 = TestWindow.new(id: 2, parent: accordion)
        w1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 1280, height: 1080)
        w2.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 1280, height: 1080)

        // Accordion uses MRU, not spatial lookup — w2 is most recent (last bound)
        let point = CGPoint(x: 640, y: 540)
        assertEquals(point.findIn(tree: root, virtual: false)?.windowId, 2)

        // Mark w1 as most recent
        w1.markAsMostRecentChild()
        assertEquals(point.findIn(tree: root, virtual: false)?.windowId, 1)
    }

    func testFindInUsesPhysicalRect() {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer

        let w1 = TestWindow.new(id: 1, parent: root)
        let w2 = TestWindow.new(id: 2, parent: root)

        // Physical rects have a gap between them
        w1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 630, height: 1080)
        w2.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 650, topLeftY: 0, width: 630, height: 1080)

        // Virtual rects cover the full area (no gap)
        w1.lastAppliedLayoutVirtualRect = Rect(topLeftX: 0, topLeftY: 0, width: 640, height: 1080)
        w2.lastAppliedLayoutVirtualRect = Rect(topLeftX: 640, topLeftY: 0, width: 640, height: 1080)

        // Point in the gap — physical search finds nothing, virtual search finds w1
        let gapPoint = CGPoint(x: 635, y: 540)
        assertEquals(gapPoint.findIn(tree: root, virtual: false)?.windowId, nil)
        assertEquals(gapPoint.findIn(tree: root, virtual: true)?.windowId, 1)
    }

    func testFindInEmptyContainer() {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer

        let point = CGPoint(x: 640, y: 540)
        assertEquals(point.findIn(tree: root, virtual: false)?.windowId, nil)
    }
}
