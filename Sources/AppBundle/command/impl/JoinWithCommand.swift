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
                newOrientation = rect.width >= rect.height ? .h : .v
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

        joinWithTarget.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
        currentWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: direction.isPositive ? 0 : INDEX_BIND_LAST)
        return true
    }
}
