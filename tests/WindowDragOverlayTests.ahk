#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/WindowDrag.ahk
#Include ../lib/WindowDragOverlay.ahk

; Hidden native overlay windows and mocked motion only. Never shows a window,
; reads desktop pixels, changes focus, moves the pointer, or injects input.
global OverlayChecks := 0
try {
    TestOverlayHiddenNative()
    TestOverlayDragLifecycle()
    FileAppend("PASS: window drag overlay / " OverlayChecks " assertions`n", "*")
} catch Error as overlayTestError {
    FileAppend("FAIL: " overlayTestError.Message " (" overlayTestError.File ":" overlayTestError.Line ")`n", "*")
    ExitApp(1)
}
ExitApp(0)

TestOverlayHiddenNative() {
    foreground := DllCall("User32\GetForegroundWindow", "Ptr")
    dpi := DllCall("User32\GetThreadDpiAwarenessContext", "Ptr")
    criticalState := A_IsCritical
    overlay := WindowDragOverlay(true)
    wash := overlay.Wash.Hwnd, badge := overlay.Badge.Hwnd
    try {
        OverlayCheck(!overlay.Active && !OverlayVisible(wash) && !OverlayVisible(badge), "Construction creates only hidden inactive windows")
        for , hwnd in [wash, badge] {
            style := DllCall("User32\GetWindowLongW", "Ptr", hwnd, "Int", -16, "UInt")
            exStyle := DllCall("User32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "UInt")
            OverlayCheck((exStyle & 0x080800A8) = 0x080800A8, "Overlay is layered, topmost, click-through, noactivate and a tool window")
            OverlayCheck(!(style & 0x00C40000), "Overlay has no caption, border or resize frame")
        }
        OverlayCheck(overlay.Color = "FFFFFF" && overlay.Transparency = 60 && OverlayAlpha(wash) = 102, "Default wash matches white at forty percent opacity")
        OverlayCheck(OverlayAlpha(badge) = 255, "Black geometry label stays fully opaque")
        target := {Hwnd: 100, Rect: {X: -1400, Y: 50, W: 730, H: 510}}
        cursor := {X: -1200, Y: 200}
        OverlayCheck(overlay.Begin(target, cursor) && overlay.Active, "Hidden overlay begins logically")
        actual := overlay.WithDpi(OverlayReadRect, wash)
        OverlayCheck(actual.X = -1400 && actual.Y = 50 && actual.W = 730 && actual.H = 510, "White wash exactly follows supplied target rectangle in physical coordinates")
        OverlayCheck(overlay.LastText = "X: -1400 Y: 50`nW: 730 H: 510", "Label reports the same rectangle as the wash")
        OverlayCheck(!OverlayVisible(wash) && !OverlayVisible(badge), "Hidden-only Begin never shows either native window")
        target.Rect := {X: 40, Y: -300, W: 920, H: 650}
        overlay.Update(target, {X: 500, Y: -200})
        actual := overlay.WithDpi(OverlayReadRect, wash)
        OverlayCheck(actual.X = 40 && actual.Y = -300 && actual.W = 920 && actual.H = 650, "Update moves and resizes only the owned hidden wash")
        OverlayCheck(overlay.LastText = "X: 40 Y: -300`nW: 920 H: 650", "Label updates actual preview coordinates and dimensions together")
        OverlayCheck(!OverlayVisible(wash) && !OverlayVisible(badge), "Hidden-only Update never shows either native window")
        placement := WindowDragOverlay.LabelBounds({X: 20, Y: 30}, {W: 160, H: 50}, {X: 0, Y: 0, W: 1000, H: 700})
        OverlayCheck(placement.X = 36 && placement.Y = 50, "Geometry label sits near the supplied pointer")
        placement := WindowDragOverlay.LabelBounds({X: -1, Y: 1079}, {W: 160, H: 50}, {X: -1920, Y: 0, W: 1920, H: 1080})
        OverlayCheck(placement.X >= -1920 && placement.Y >= 0 && placement.X + placement.W <= 0 && placement.Y + placement.H <= 1080, "Label clamps inside a negative-coordinate monitor work area")
        placement := WindowDragOverlay.LabelBounds({X: -3000, Y: -200}, {W: 160, H: 50}, {X: -1920, Y: 0, W: 1920, H: 1080})
        OverlayCheck(placement.X = -1920 && placement.Y = 0, "Off-monitor pointer data still clamps the label")
        overlay.Configure("aabbcc", 0)
        OverlayCheck(overlay.Color = "AABBCC" && overlay.Alpha = 255 && OverlayAlpha(wash) = 255, "Zero transparency gives the configured fully opaque wash")
        overlay.Configure("123456", 100)
        OverlayCheck(overlay.Alpha = 0 && OverlayAlpha(wash) = 0 && OverlayAlpha(badge) = 255, "Full transparency hides the wash while preserving readable geometry")
        OverlayReject(() => overlay.Configure("#FFFFFF", 60), "Color rejects a non-six-digit value")
        OverlayReject(() => overlay.Configure("FFFFFF", 101), "Transparency rejects an out-of-range value")
        OverlayCheck(overlay.Color = "123456" && overlay.Transparency = 100, "Invalid appearance changes preserve prior settings")
        OverlayReject(() => overlay.Update({Hwnd: 101, Rect: target.Rect}, cursor), "Changing overlay target fails closed")
        OverlayCheck(!overlay.Active && !OverlayVisible(wash) && !OverlayVisible(badge), "Overlay errors hide both windows")
        overlay.Begin(target, cursor)
        overlay.Hide()
        OverlayCheck(!overlay.Active && !overlay.Update(target, cursor), "Hidden inactive overlay ignores later updates")
        OverlayCheck(DllCall("User32\GetForegroundWindow", "Ptr") = foreground, "Hidden overlay operations preserve foreground focus")
        OverlayCheck(DllCall("User32\AreDpiAwarenessContextsEqual", "Ptr", dpi, "Ptr", DllCall("User32\GetThreadDpiAwarenessContext", "Ptr"), "Int") && A_IsCritical = criticalState, "Overlay operations restore thread DPI and critical state")
    } finally {
        overlay.Dispose()
    }
    OverlayCheck(!DllCall("User32\IsWindow", "Ptr", wash, "Int") && !DllCall("User32\IsWindow", "Ptr", badge, "Int"), "Dispose destroys both owned hidden windows")
    overlay.Dispose()
    OverlayReject(() => overlay.Begin({Hwnd: 100, Rect: {X: 0, Y: 0, W: 100, H: 100}}, {X: 0, Y: 0}), "Disposed overlay cannot restart")
}

TestOverlayDragLifecycle() {
    adapter := OverlayLaggingTarget(), overlay := OverlayFake(), drag := WindowDrag(adapter, overlay)
    OverlayCheck(drag.Begin("move", "MoveWindow", 100) && overlay.Active && overlay.BeginCount = 1, "Validated drag begins its injected overlay")
    adapter.Cursor := {X: 340, Y: 220}
    reads := adapter.Reads
    drag.Tick()
    OverlayCheck(adapter.Reads = reads + 1, "Overlay adds no post-apply target read")
    OverlayCheck(adapter.Target.Rect.X = 100 && overlay.LastRect.X = 320 && overlay.LastRect.Y = 200, "Preview advances to intended geometry while observed target lags unchanged")
    OverlayCheck(adapter.Applied[1].X = overlay.LastRect.X && adapter.Applied[1].Y = overlay.LastRect.Y, "Preview and asynchronous target request share desired geometry")
    adapter.Cursor := {X: 400, Y: 260}
    drag.End("move")
    OverlayCheck(!drag.Active && !overlay.Active && adapter.Applied[2].X = 380 && adapter.Applied[2].Y = 240, "Normal completion requests final intended geometry and hides overlay")
    drag.Begin("cancel", "MoveWindow", 100)
    applied := adapter.Applied.Length
    adapter.Cursor.X += 100
    drag.Cancel()
    OverlayCheck(!overlay.Active && adapter.Applied.Length = applied, "Cancellation hides without applying an extra pointer delta")
    drag.Begin("failure", "MoveWindow", 100)
    overlay.FailUpdate := true
    OverlayReject(() => drag.Tick(), "Overlay rendering errors stop the drag")
    OverlayCheck(!drag.Active && !overlay.Active, "Rendering error cleans up session and overlay")
    overlay.FailUpdate := false
    overlay.FailBegin := true
    OverlayReject(() => drag.Begin("failed-begin", "MoveWindow", 100), "Overlay begin errors reject the drag")
    OverlayCheck(!drag.Active && !overlay.Active, "Failed begin does not retain a session or overlay")
    overlay.FailBegin := false
    drag.Begin("exit", "ResizeWindow", 100)
    drag.Dispose()
    OverlayCheck(!drag.Active && !overlay.Active && overlay.Disposed, "Dispose cancels active resize and disposes the injected overlay")
    drag.Dispose()
}

class OverlayLaggingTarget {
    __New() {
        this.Target := {Hwnd: 100, PID: 1, Thread: 2, Class: "Fixture", Rect: {X: 100, Y: 100, W: 500, H: 300},
            Own: false, Visible: true, Minimized: false, Maximized: false, Excluded: false, Resizable: true}
        this.Cursor := {X: 120, Y: 120}
        this.Applied := []
        this.Reads := 0
    }
    ReadTarget(hwnd) {
        this.Reads += 1
        return this.Target
    }
    ReadCursor() => this.Cursor.Clone()
    ReadMinimum(hwnd) => {W: 80, H: 60}
    ApplyRect(hwnd, rect) => this.Applied.Push(rect.Clone())
}

class OverlayFake {
    __New() {
        this.Active := false
        this.Disposed := false
        this.FailBegin := false
        this.FailUpdate := false
        this.BeginCount := 0
    }
    Begin(target, cursor) {
        this.Active := true
        this.BeginCount += 1
        if this.FailBegin
            throw Error("fixture begin failure")
        this.Update(target, cursor)
    }
    Update(target, cursor) {
        if this.FailUpdate
            throw Error("fixture render failure")
        this.LastRect := target.Rect.Clone()
    }
    Hide() => this.Active := false
    Dispose() => this.Disposed := true
}

OverlayReadRect(hwnd) {
    rect := Buffer(16, 0)
    if !DllCall("User32\GetWindowRect", "Ptr", hwnd, "Ptr", rect, "Int")
        throw Error("Could not inspect owned hidden overlay bounds.")
    return {X: NumGet(rect, 0, "Int"), Y: NumGet(rect, 4, "Int"),
        W: NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int"), H: NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")}
}

OverlayVisible(hwnd) => DllCall("User32\IsWindowVisible", "Ptr", hwnd, "Int")

OverlayAlpha(hwnd) {
    color := 0, alpha := 0, flags := 0
    if !DllCall("User32\GetLayeredWindowAttributes", "Ptr", hwnd, "UInt*", &color, "UChar*", &alpha, "UInt*", &flags, "Int")
        throw Error("Could not inspect owned hidden overlay alpha.")
    return alpha
}

OverlayCheck(condition, message) {
    global OverlayChecks
    OverlayChecks += 1
    if !condition
        throw Error(message)
}

OverlayReject(callback, message) {
    rejected := false
    try callback.Call()
    catch Error
        rejected := true
    OverlayCheck(rejected, message)
}
