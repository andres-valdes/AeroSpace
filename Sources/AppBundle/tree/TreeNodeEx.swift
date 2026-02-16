import AppKit
import Common

extension TreeNode {
    private func visit(node: TreeNode, result: inout [Window]) {
        if let node = node as? Window {
            result.append(node)
        }
        for child in node.children {
            visit(node: child, result: &result)
        }
    }
    var allLeafWindowsRecursive: [Window] {
        var result: [Window] = []
        visit(node: self, result: &result)
        return result
    }

    var ownIndex: Int? {
        guard let parent else { return nil }
        return parent.children.firstIndex(of: self).orDie()
    }

    var parents: [NonLeafTreeNodeObject] { parent.flatMap { [$0] + $0.parents } ?? [] }
    var parentsWithSelf: [TreeNode] { parent.flatMap { [self] + $0.parentsWithSelf } ?? [self] }

    /// Also see visualWorkspace
    var nodeWorkspace: Workspace? {
        self as? Workspace ?? parent?.nodeWorkspace
    }

    /// Also see: workspace
    @MainActor
    var visualWorkspace: Workspace? { nodeWorkspace ?? nodeMonitor?.activeWorkspace }

    @MainActor
    var nodeMonitor: Monitor? {
        switch self.nodeCases {
            case .workspace(let ws): ws.workspaceMonitor
            case .window: parent?.nodeMonitor
            case .tilingContainer: parent?.nodeMonitor
            case .macosFullscreenWindowsContainer: parent?.nodeMonitor
            case .macosHiddenAppsWindowsContainer: parent?.nodeMonitor
            case .macosMinimizedWindowsContainer, .macosPopupWindowsContainer: nil
        }
    }

    var mostRecentWindowRecursive: Window? {
        self as? Window ?? mostRecentChild?.mostRecentWindowRecursive
    }

    var anyLeafWindowRecursive: Window? {
        if let window = self as? Window {
            return window
        }
        for child in children {
            if let window = child.anyLeafWindowRecursive {
                return window
            }
        }
        return nil
    }

    // Doesn't contain at least one window
    var isEffectivelyEmpty: Bool {
        anyLeafWindowRecursive == nil
    }

    @MainActor
    var hWeight: CGFloat {
        get { getWeight(.h) }
        set { setWeight(.h, newValue) }
    }

    @MainActor
    var vWeight: CGFloat {
        get { getWeight(.v) }
        set { setWeight(.v, newValue) }
    }

    /// Compute the index path from an ancestor node down to a descendant window.
    /// Used by dwindle spatial targeting to mirror the window's position across subtrees.
    @MainActor
    func indexPath(to descendant: Window) -> [Int] {
        var path: [Int] = []
        var current: TreeNode = descendant
        while current !== self {
            if let index = current.ownIndex {
                path.append(index)
            }
            guard let parent = current.parent else { break }
            current = parent as TreeNode
        }
        return path.reversed()
    }

    /// Walk into a subtree, mirroring the source window's position for perpendicular
    /// containers and picking the entry edge for same-orientation containers.
    /// Used by dwindle focus and move to find spatially correct targets.
    @MainActor
    func findDwindleSpatialTarget(
        direction: CardinalDirection,
        path: ArraySlice<Int>,
    ) -> Window? {
        if let window = self as? Window { return window }
        guard let container = self as? TilingContainer else { return nil }

        let child: TreeNode?
        let remainingPath = path.dropFirst()

        if container.orientation == direction.orientation {
            // Same orientation as move: pick the entry edge
            child = direction.isPositive ? container.children.first : container.children.last
        } else if let index = path.first {
            // Perpendicular: mirror the window's position
            let clampedIndex = min(index, container.children.count - 1)
            child = container.children[clampedIndex]
        } else {
            // Path exhausted: fall back to MRU
            child = container.mostRecentChild
        }

        return child.flatMap { $0.findDwindleSpatialTarget(direction: direction, path: remainingPath) }
    }

    /// Returns closest parent that has children in the specified direction relative to `self`
    func closestParent(
        hasChildrenInDirection direction: CardinalDirection,
        withLayout layout: Layout?,
    ) -> (parent: TilingContainer, ownIndex: Int)? {
        let innermostChild = parentsWithSelf.first(where: { (node: TreeNode) -> Bool in
            return switch node.parent?.cases {
                // stop searching. We didn't find it, or something went wrong
                case .workspace, nil, .macosMinimizedWindowsContainer,
                     .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
                    true
                case .tilingContainer(let parent):
                    (layout == nil || parent.layout == layout) &&
                        parent.orientation == direction.orientation &&
                        (node.ownIndex.map { parent.children.indices.contains($0 + direction.focusOffset) } ?? true)
            }
        })
        guard let innermostChild else { return nil }
        switch innermostChild.parent?.cases {
            case .tilingContainer(let parent):
                check(parent.orientation == direction.orientation)
                return innermostChild.ownIndex.map { (parent, $0) }
            case .workspace, nil, .macosMinimizedWindowsContainer,
                 .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
                return nil
        }
    }
}
