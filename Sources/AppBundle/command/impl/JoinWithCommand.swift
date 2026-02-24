import AppKit
import Common

struct JoinWithCommand: Command {
    let args: JoinWithCmdArgs
    /*conforms*/ var shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let direction = args.direction.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        guard let (parent, ownIndex) = currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) else {
            return io.err("No windows in the specified direction")
        }
        let joinWithTarget = parent.children[ownIndex + direction.focusOffset]
        let prevBinding = joinWithTarget.unbindFromParent()
        let newOrientation: Orientation
        let newLayout: Layout
        if parent.layout == .dwindle {
            // Use dwindle logic: pick orientation based on target window's rect dimensions
            if let targetWindow = joinWithTarget as? Window,
               let rect = targetWindow.lastAppliedLayoutVirtualRect {
                let dwindleOrientation: Orientation = rect.width >= rect.height ? .h : .v
                // When the current window is the only remaining child (joinWithTarget already
                // unbound), the parent will become a singleton after the join and get flattened
                // by normalization. If the new container has the same orientation as the parent,
                // flattening undoes the join entirely. Fall back to opposite orientation.
                if dwindleOrientation == parent.orientation && parent.children.count == 1 {
                    newOrientation = parent.orientation.opposite
                } else {
                    newOrientation = dwindleOrientation
                }
            } else {
                newOrientation = parent.orientation.opposite
            }
            newLayout = .dwindle
        } else {
            newOrientation = parent.orientation.opposite
            newLayout = .tiles
        }
        let newParent = TilingContainer(
            parent: parent,
            adaptiveWeight: prevBinding.adaptiveWeight,
            newOrientation,
            newLayout,
            index: prevBinding.index,
        )
        currentWindow.unbindFromParent()

        let currentWindowIndex: Int
        if let currentRect = currentWindow.lastAppliedLayoutVirtualRect,
           let targetRect = joinWithTarget.lastAppliedLayoutVirtualRect {
            let currentPos = currentRect.center.getProjection(newOrientation)
            let targetPos = targetRect.center.getProjection(newOrientation)
            currentWindowIndex = currentPos < targetPos ? 0 : INDEX_BIND_LAST
        } else {
            currentWindowIndex = direction.isPositive ? 0 : INDEX_BIND_LAST
        }

        joinWithTarget.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
        currentWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: currentWindowIndex)
        return true
    }
}
