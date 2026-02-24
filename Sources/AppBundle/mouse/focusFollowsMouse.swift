import AppKit
import Common

@MainActor
private var focusFollowsMouseTask: Task<(), any Error>? = nil

@MainActor
func handleMouseMovedForFocusFollowsMouse() {
    guard config.focusFollowsMouse else { return }
    guard currentlyManipulatedWithMouseWindowId == nil, !isLeftMouseButtonDown else { return }
    guard let token: RunSessionGuard = .isServerEnabled else { return }

    focusFollowsMouseTask?.cancel()
    focusFollowsMouseTask = Task {
        try checkCancellation()
        try await focusWindowUnderMouse(token)
    }
}

@MainActor
private func focusWindowUnderMouse(_ token: RunSessionGuard) async throws {
    let mouse = mouseLocation
    let currentMonitor = mouse.monitorApproximation
    let currentWorkspace = currentMonitor.activeWorkspace

    // Check tiling windows first (fast, synchronous, uses cached layout rects)
    if let tilingWindow = mouse.findIn(tree: currentWorkspace.rootTilingContainer, virtual: false) {
        if tilingWindow == focus.windowOrNil { return }
        try await runLightSession(.focusFollowsMouse, token) {
            _ = tilingWindow.focusWindow()
            tilingWindow.nativeFocus()
        }
        return
    }

    // Check floating windows (async AX calls, reverse iteration for z-order priority)
    for window in currentWorkspace.floatingWindows.reversed() {
        if let rect = try await window.getAxRect(), rect.contains(mouse) {
            if window == focus.windowOrNil { return }
            try checkCancellation()
            try await runLightSession(.focusFollowsMouse, token) {
                _ = window.focusWindow()
                window.nativeFocus()
            }
            return
        }
        try checkCancellation()
    }

    // No window match — if cursor is on a different monitor, focus that workspace
    if currentWorkspace != focus.workspace {
        try await runLightSession(.focusFollowsMouse, token) {
            _ = currentWorkspace.focusWorkspace()
        }
    }
}
