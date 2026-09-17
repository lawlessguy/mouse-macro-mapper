#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/WindowDrag.ahk

; Pure adapters plus one explicitly allowlisted hidden, process-owned window.
; No hooks, synthetic input, cursor movement, visible windows, or user settings.
global DragChecks := 0, DragFailures := []
DragTest("move uses original rectangle and signed desktop coordinates", TestDragMove)
DragTest("nearest corner resize preserves opposite corner and minimum size", TestDragResize)
DragTest("token completion and cancellation stop output", TestDragLifetime)
DragTest("ineligible targets reject before motion", TestDragRejections)
DragTest("frozen window identity and adapter errors cancel", TestDragFailures)
DragTest("reentrant cancellation cannot apply stale geometry", TestDragReentrancy)
DragTest("move preserves independently changed window size", TestDragMoveSize)
DragTest("native hidden fixture preserves visibility focus and DPI context", TestDragNative)
FileAppend("Assertions: " DragChecks "`n", "*")
for , dragFailure in DragFailures
    FileAppend("FAIL: " dragFailure "`n", "*")
FileAppend(DragFailures.Length ? "RESULT: FAIL`n" : "RESULT: PASS`n", "*")
ExitApp(DragFailures.Length ? 1 : 0)

DragTest(label, callback) {
    global DragFailures
    try {
        callback.Call()
        FileAppend("PASS: " label "`n", "*")
    } catch Error as err {
        DragFailures.Push(label ": " err.Message " (line " err.Line ")")
    }
}

DragCheck(condition, message) {
    global DragChecks
    DragChecks += 1
    if !condition
        throw Error(message)
}

DragThrows(callback, messagePart) {
    caught := ""
    try callback.Call()
    catch Error as err
        caught := err.Message
    DragCheck(InStr(caught, messagePart), "Expected '" messagePart "', got '" caught "'")
}

DragRect(rect, x, y, width, height) {
    DragCheck(rect.X = x && rect.Y = y && rect.W = width && rect.H = height,
        "Unexpected rectangle: " rect.X "," rect.Y "," rect.W "," rect.H)
}

DragRaise(message) {
    throw Error(message)
}

class DragFakeAdapter {
    __New() {
        this.Target := {Hwnd: 100, PID: 10, Thread: 20, Class: "Example",
            Rect: {X: -1200, Y: -400, W: 600, H: 400}, Own: false, Visible: true,
            Minimized: false, Maximized: false, Excluded: false, Resizable: true}
        this.Cursor := {X: -1100, Y: -300}
        this.Minimum := {W: 160, H: 100}
        this.Applied := []
        this.FailRead := false, this.FailApply := false
        this.OnCursor := 0, this.CursorCritical := 0
    }
    ReadTarget(hwnd) {
        if this.FailRead
            throw Error("target closed")
        DragCheck(hwnd = 100, "Adapter always receives frozen target handle")
        return this.Target
    }
    ReadCursor() {
        this.CursorCritical := A_IsCritical
        if IsObject(this.OnCursor) {
            callback := this.OnCursor
            this.OnCursor := 0
            callback.Call()
        }
        return this.Cursor.Clone()
    }
    ReadMinimum(hwnd) => this.Minimum.Clone()
    ApplyRect(hwnd, rect) {
        if this.FailApply
            throw Error("apply failed")
        this.Applied.Push(rect.Clone())
        this.Target.Rect := rect.Clone()
    }
}

TestDragMove() {
    adapter := DragFakeAdapter(), drag := WindowDrag(adapter)
    DragCheck(drag.Begin("move", "MoveWindow", 100) && drag.Active, "Move begins")
    drag.Tick()
    DragCheck(!adapter.Applied.Length, "Stationary pointer produces no output")
    adapter.Cursor := {X: -1000, Y: -350}
    drag.Tick()
    DragRect(adapter.Applied[1], -1100, -450, 600, 400)
    adapter.Cursor := {X: 1400, Y: 750}
    drag.Tick()
    DragRect(adapter.Applied[2], 1300, 650, 600, 400)
    drag.Tick()
    DragCheck(adapter.Applied.Length = 2, "No cumulative drift or duplicate stationary moves")
    drag.Cancel()
}

TestDragResize() {
    for , corner in [{X: -1190, Y: -390, L: true, T: true},
        {X: -610, Y: -390, L: false, T: true}, {X: -1190, Y: -10, L: true, T: false},
        {X: -610, Y: -10, L: false, T: false}] {
        adapter := DragFakeAdapter(), adapter.Cursor := {X: corner.X, Y: corner.Y}
        drag := WindowDrag(adapter)
        drag.Begin(1, "ResizeWindow", 100)
        adapter.Cursor.X += corner.L ? -80 : 80
        adapter.Cursor.Y += corner.T ? -50 : 50
        drag.Tick()
        DragRect(adapter.Applied[1], corner.L ? -1280 : -1200,
            corner.T ? -450 : -400, 680, 450)
        adapter.Cursor.X := corner.X + (corner.L ? 2000 : -2000)
        adapter.Cursor.Y := corner.Y + (corner.T ? 2000 : -2000)
        drag.Tick()
        DragRect(adapter.Applied[2], corner.L ? -760 : -1200,
            corner.T ? -100 : -400, 160, 100)
    }
}

TestDragLifetime() {
    adapter := DragFakeAdapter(), drag := WindowDrag(adapter)
    DragCheck(!drag.Tick() && !drag.End(1), "Idle updates are inert")
    drag.Begin(1, "MoveWindow", 100)
    DragThrows(ObjBindMethod(drag, "Begin", 2, "ResizeWindow", 100), "current window drag")
    DragCheck(!drag.End(2) && drag.Active, "Another token cannot end the drag")
    adapter.Cursor.X += 50
    DragCheck(drag.End(1) && !drag.Active, "Correct token applies final cursor and ends")
    DragRect(adapter.Applied[1], -1150, -400, 600, 400)
    DragCheck(!drag.End(1) && !drag.Tick(), "Repeated release does not move again")
    drag.Begin(2, "MoveWindow", 100)
    adapter.Cursor.X += 50
    drag.End(2, false)
    DragCheck(adapter.Applied.Length = 1, "Cancellation never applies pending pointer delta")
}

TestDragRejections() {
    for , rule in [{Field: "Own", Value: true, Error: "another application's"},
        {Field: "Visible", Value: false, Error: "hidden"},
        {Field: "Minimized", Value: true, Error: "minimized"},
        {Field: "Maximized", Value: true, Error: "maximized"},
        {Field: "Excluded", Value: true, Error: "overlay"},
        {Field: "Resizable", Value: false, Error: "resizing"}] {
        adapter := DragFakeAdapter(), adapter.Target.%rule.Field% := rule.Value
        drag := WindowDrag(adapter)
        DragThrows(ObjBindMethod(drag, "Begin", 1, "ResizeWindow", 100), rule.Error)
        DragCheck(!drag.Active && !adapter.Applied.Length, "Rejected target has no drag/output")
    }
}

TestDragFailures() {
    for , field in ["PID", "Thread", "Class"] {
        adapter := DragFakeAdapter(), drag := WindowDrag(adapter)
        drag.Begin(1, "MoveWindow", 100)
        adapter.Target.%field% := "changed"
        adapter.Cursor.X += 10
        DragThrows(ObjBindMethod(drag, "Tick"), "target window changed")
        DragCheck(!drag.Active && !adapter.Applied.Length, "Identity changes cancel without motion")
    }
    for , failRead in [true, false] {
        adapter := DragFakeAdapter(), drag := WindowDrag(adapter)
        drag.Begin(1, "MoveWindow", 100)
        adapter.FailRead := failRead, adapter.FailApply := !failRead
        adapter.Cursor.X += 10
        DragThrows(ObjBindMethod(drag, "Tick"), failRead ? "target closed" : "apply failed")
        DragCheck(!drag.Active, "Native errors end drag state")
    }
    adapter := DragFakeAdapter(), drag := WindowDrag(adapter)
    drag.Begin(1, "MoveWindow", 100)
    adapter.Target.Maximized := true
    DragThrows(ObjBindMethod(drag, "Tick"), "maximized")
    DragCheck(!drag.Active, "Eligibility is rechecked while active")
}

TestDragReentrancy() {
    adapter := DragFakeAdapter(), drag := WindowDrag(adapter)
    adapter.OnCursor := ObjBindMethod(drag, "Cancel")
    DragCheck(!drag.Begin(1, "MoveWindow", 100) && !drag.Active,
        "Cancel during Begin prevents later session publication")
    DragCheck(!adapter.Applied.Length && !IsObject(drag.Starting), "Cancelled Begin leaves no pending state")
    drag.Begin(1, "MoveWindow", 100)
    adapter.Cursor.X += 50
    adapter.OnCursor := ObjBindMethod(drag, "Cancel")
    previousCritical := A_IsCritical
    try {
        Critical(17)
        DragCheck(!drag.Tick() && !drag.Active, "Cancel during ReadCursor stops current Tick")
        DragCheck(A_IsCritical = 17 && adapter.CursorCritical,
            "Geometry calls are critical and caller Critical setting is restored")
    } finally {
        Critical(previousCritical)
    }
    DragCheck(!adapter.Applied.Length, "Cancelled Tick never calls ApplyRect")
    drag.Begin(1, "MoveWindow", 100)
    adapter.Cursor.X += 50
    adapter.OnCursor := DragReplaceSession.Bind(drag)
    drag.End(1)
    DragCheck(drag.Active && drag.Session.Token = 2,
        "Stale End cleanup cannot cancel a replacement session")
    DragCheck(!adapter.Applied.Length, "Replaced session never receives stale geometry")
    drag.Cancel()
}

DragReplaceSession(drag) {
    drag.Cancel()
    drag.Begin(2, "MoveWindow", 100)
}

TestDragMoveSize() {
    adapter := DragFakeAdapter(), drag := WindowDrag(adapter)
    adapter.Target.Rect := {X: -1200, Y: -400, W: 400, H: 200}
    drag.Begin(1, "MoveWindow", 100)
    adapter.Target.Rect.W := 500, adapter.Target.Rect.H := 300
    adapter.Cursor.X += 50, adapter.Cursor.Y += 30
    drag.Tick()
    DragRect(adapter.Applied[1], -1150, -370, 500, 300)
    DragCheck(adapter.Applied[1].MoveOnly, "Move requests native SWP_NOSIZE behavior")
    drag.Cancel()
}

class DragFixtureAdapter extends WindowDragNativeAdapter {
    ReadCursor() => this.Cursor.Clone()
}

TestDragNative() {
    foreground := DllCall("User32\GetForegroundWindow", "Ptr")
    dpi := DllCall("User32\GetThreadDpiAwarenessContext", "Ptr")
    hwnd := WindowDragNativeAdapter().WithDpi(DragCreateNativeFixture)
    try {
        adapter := DragFixtureAdapter(hwnd)
        adapter.ApplyRect(hwnd, {X: -1200, Y: -900, W: 500, H: 400})
        target := adapter.ReadTarget(hwnd)
        DragRect(target.Rect, -1200, -900, 500, 400)
        production := WindowDrag()
        DragThrows(ObjBindMethod(production, "Begin", 1, "MoveWindow", hwnd), "another application's")
        adapter.Cursor := {X: -1100, Y: -800}
        drag := WindowDrag(adapter)
        drag.Begin(1, "MoveWindow", hwnd)
        adapter.Cursor := {X: -1040, Y: -770}
        drag.Tick()
        drag.End(1, false)
        DragRect(adapter.ReadTarget(hwnd).Rect, -1140, -870, 500, 400)
        adapter.Cursor := {X: -650, Y: -480}
        drag.Begin(2, "ResizeWindow", hwnd)
        adapter.Cursor.X += 80, adapter.Cursor.Y += 50
        drag.End(2)
        DragRect(adapter.ReadTarget(hwnd).Rect, -1140, -870, 580, 450)
        adapter.ApplyRect(hwnd, {X: -1100, Y: -800, W: 999, H: 999, MoveOnly: true})
        DragRect(adapter.ReadTarget(hwnd).Rect, -1100, -800, 580, 450)
        DragCheck(!DllCall("User32\IsWindowVisible", "Ptr", hwnd, "Int"), "Fixture remains hidden")
        DragCheck(DllCall("User32\GetForegroundWindow", "Ptr") = foreground, "Focus unchanged")
        DragThrows(ObjBindMethod(adapter, "WithDpi", DragRaise.Bind("scoped failure")), "scoped failure")
        DragCheck(DllCall("User32\AreDpiAwarenessContextsEqual", "Ptr", dpi,
            "Ptr", DllCall("User32\GetThreadDpiAwarenessContext", "Ptr"), "Int"),
            "DPI context restored after successful and failed native work")
    } finally {
        DllCall("User32\DestroyWindow", "Ptr", hwnd, "Int")
    }
}

DragCreateNativeFixture() {
    ; Native STATIC class with normal sizing frame, no WS_VISIBLE or activation.
    hwnd := DllCall("User32\CreateWindowExW", "UInt", 0, "Str", "Static",
        "Str", "WindowDrag hidden test fixture", "UInt", 0x00CF0000,
        "Int", -1200, "Int", -900, "Int", 500, "Int", 400,
        "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
    if !hwnd
        throw Error("Could not create hidden native fixture.")
    return hwnd
}
