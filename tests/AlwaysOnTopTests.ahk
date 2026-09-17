#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/AlwaysOnTop.ahk

; Mocked window lifecycle plus one raw hidden owned fixture. Native outlines
; use noShow=true: no visible windows, hooks, synthetic input, or user settings.
global TopChecks := 0, TopFailures := []
TopTest("owned toggle and preexisting external topmost state", TestTopOwnership)
TopTest("multiple pins and maximized targets restore on disposal", TestTopMultiple)
TopTest("identity and property lease prevent reused-window cleanup", TestTopIdentity)
TopTest("outline follows hides reuses and validates preferences", TestTopOutline)
TopTest("failed pin rolls back and failed disposal remains retryable", TestTopFailures)
TopTest("ineligible targets remain untouched", TestTopRejections)
TopTest("native hidden fixture pin cleanup and passive outline styles", TestTopNative)
FileAppend("Assertions: " TopChecks "`n", "*")
for , topFailure in TopFailures
    FileAppend("FAIL: " topFailure "`n", "*")
FileAppend(TopFailures.Length ? "RESULT: FAIL`n" : "RESULT: PASS`n", "*")
ExitApp(TopFailures.Length ? 1 : 0)

TopTest(label, callback) {
    global TopFailures
    try {
        callback.Call()
        FileAppend("PASS: " label "`n", "*")
    } catch Error as err {
        TopFailures.Push(label ": " err.Message " (line " err.Line ")")
    }
}

TopCheck(condition, message) {
    global TopChecks
    TopChecks += 1
    if !condition
        throw Error(message)
}

TopThrows(callback, expected) {
    caught := ""
    try callback.Call()
    catch Error as err
        caught := err.Message
    TopCheck(InStr(caught, expected), "Expected '" expected "', got '" caught "'")
}

class TopFakeAdapter {
    __New() {
        this.Windows := Map(), this.Claims := Map(), this.SetCalls := []
        this.Clock := 0, this.Sequence := 0, this.FailNextSet := false
        loop 3
            this.Windows[A_Index] := {Hwnd: A_Index, PID: A_Index + 100, Thread: A_Index + 200,
                Class: "TestWindow", Rect: {X: -800, Y: 50, W: 600, H: 400}, Topmost: false,
                Own: false, Visible: true, Minimized: false, Maximized: false, Excluded: false}
    }
    Now() => this.Clock
    Exists(hwnd) => this.Windows.Has(hwnd)
    ReadTarget(hwnd) {
        if !this.Exists(hwnd)
            throw Error("window closed")
        target := this.Windows[hwnd].Clone()
        target.Rect := target.Rect.Clone()
        return target
    }
    Claim(hwnd) {
        this.Sequence += 1
        lease := {ID: this.Sequence}
        this.Claims[hwnd] := lease
        return lease
    }
    OwnsClaim(hwnd, lease) => this.Claims.Has(hwnd) && this.Claims[hwnd] = lease
    ReleaseClaim(hwnd, lease) {
        if this.OwnsClaim(hwnd, lease)
            this.Claims.Delete(hwnd)
    }
    SetTopmost(hwnd, topmost, lease) {
        if !this.OwnsClaim(hwnd, lease)
            throw Error("ownership changed")
        this.SetCalls.Push({Hwnd: hwnd, Topmost: topmost})
        this.Windows[hwnd].Topmost := topmost
        if this.FailNextSet {
            this.FailNextSet := false
            throw Error("native set failed")
        }
    }
}

class TopFakeOutlines {
    __New() {
        this.Items := []
    }
    Create() {
        item := TopFakeOutline()
        this.Items.Push(item)
        return item
    }
}

class TopFakeOutline {
    __New() {
        this.Visible := false, this.Disposed := false, this.Shows := 0
    }
    Configure(color, thickness) {
        this.Color := color, this.Thickness := thickness
    }
    Show(rect) {
        this.Rect := rect.Clone(), this.Visible := true, this.Shows += 1
    }
    Hide() => this.Visible := false
    Dispose() {
        this.Disposed := true, this.Visible := false
    }
}

TopFixture() {
    adapter := TopFakeAdapter(), outlines := TopFakeOutlines()
    return {Adapter: adapter, Outlines: outlines, Manager: AlwaysOnTop(adapter, ObjBindMethod(outlines, "Create"))}
}

TestTopOwnership() {
    fixture := TopFixture(), manager := fixture.Manager, adapter := fixture.Adapter
    TopCheck(manager.Pins.Count = 0 && !adapter.SetCalls.Length, "Construction pins nothing")
    TopCheck(InStr(manager.Toggle(1), "on."), "Toggle reports owned pin")
    TopCheck(adapter.Windows[1].Topmost && manager.Pins.Count = 1 && adapter.Claims.Count = 1, "Pin records owned state and lease")
    outline := fixture.Outlines.Items[1]
    TopCheck(outline.Visible && outline.Color = "0078D4" && outline.Thickness = 3, "Default visible blue three-pixel border")
    TopCheck(InStr(manager.Toggle(1), "off."), "Second toggle unpins")
    TopCheck(!adapter.Windows[1].Topmost && !manager.Pins.Count && !adapter.Claims.Count && outline.Disposed, "Owned cleanup restores state and removes outline")
    adapter.Windows[2].Topmost := true
    count := adapter.SetCalls.Length
    TopCheck(InStr(manager.Toggle(2), "already"), "External topmost is explained")
    manager.Dispose()
    TopCheck(adapter.Windows[2].Topmost && adapter.SetCalls.Length = count && !manager.Pins.Count, "External topmost is never adopted or removed")
}

TestTopMultiple() {
    fixture := TopFixture(), manager := fixture.Manager, adapter := fixture.Adapter
    adapter.Windows[2].Maximized := true
    adapter.Windows[3].Topmost := true
    manager.Toggle(1), manager.Toggle(2)
    TopCheck(manager.Pins.Count = 2 && fixture.Outlines.Items.Length = 2, "Multiple pins include maximized window")
    manager.Dispose()
    TopCheck(!adapter.Windows[1].Topmost && !adapter.Windows[2].Topmost && adapter.Windows[3].Topmost, "Dispose restores only manager-owned topmost states")
    TopCheck(!manager.Pins.Count && !adapter.Claims.Count, "Dispose clears owned records and markers")
    count := adapter.SetCalls.Length
    manager.Dispose()
    TopCheck(adapter.SetCalls.Length = count, "Repeated disposal is inert")
}

TestTopIdentity() {
    for , change in ["PID", "Thread", "Class", "Lease", "Closed"] {
        fixture := TopFixture(), manager := fixture.Manager, adapter := fixture.Adapter
        manager.Toggle(1)
        if change = "Lease"
            adapter.Claims[1] := {ID: -1}
        else if change = "Closed"
            adapter.Windows.Delete(1)
        else
            adapter.Windows[1].%change% := "new target"
        adapter.Clock += 100
        manager.Tick()
        TopCheck(!manager.Pins.Count && fixture.Outlines.Items[1].Disposed, "Changed identity or lease drops owned outline")
        manager.Dispose()
        TopCheck(adapter.SetCalls.Length = 1, "Reused or closed target is never unpinned")
    }
}

TestTopOutline() {
    fixture := TopFixture(), manager := fixture.Manager, adapter := fixture.Adapter
    manager.Toggle(1)
    outline := fixture.Outlines.Items[1]
    adapter.Windows[1].Rect := {X: -1800, Y: -200, W: 900, H: 700}
    adapter.Clock := 100
    manager.Tick()
    TopCheck(outline.Rect.X = -1800 && outline.Rect.Y = -200 && outline.Rect.W = 900, "Outline follows signed virtual-desktop rectangle")
    shows := outline.Shows
    adapter.Clock := 199
    manager.Tick()
    TopCheck(outline.Shows = shows, "Tick is rate-limited to 100ms")
    adapter.Windows[1].Minimized := true, adapter.Clock := 200
    manager.Tick()
    TopCheck(!outline.Visible && manager.Pins.Count = 1 && adapter.Windows[1].Topmost, "Minimized target hides border without unpinning")
    adapter.Windows[1].Minimized := false, adapter.Windows[1].Visible := false, adapter.Clock := 300
    manager.Tick()
    TopCheck(!outline.Visible, "Hidden or cloaked target keeps border hidden")
    adapter.Windows[1].Visible := true, adapter.Clock := 400
    manager.Tick()
    TopCheck(outline.Visible && fixture.Outlines.Items.Length = 1, "Restoring target reuses owned outline")
    manager.ConfigureOutline(true, "#a1b2c3", 8)
    TopCheck(outline.Color = "A1B2C3" && outline.Thickness = 8, "Color and thickness update existing border")
    manager.ConfigureOutline(false, "A1B2C3", 8)
    TopCheck(!outline.Visible && adapter.Windows[1].Topmost, "Outline disabled independently of pin")
    TopThrows(ObjBindMethod(manager, "ConfigureOutline", true, "red", 3), "six hexadecimal")
    TopThrows(ObjBindMethod(manager, "ConfigureOutline", true, "0078D4", 13), "1 to 12")
    TopCheck(!manager.OutlineEnabled && manager.Color = "A1B2C3", "Invalid preferences preserve previous configuration")
    manager.ConfigureOutline(true, "0078D4", 1)
    TopCheck(outline.Visible && fixture.Outlines.Items.Length = 1, "Reenabled outline remains reusable")
    adapter.Windows[1].Topmost := false, adapter.Clock += 100
    manager.Tick()
    TopCheck(!manager.Pins.Count && !adapter.Claims.Count && outline.Disposed, "External unpin releases marker without reasserting topmost")
}

TestTopFailures() {
    fixture := TopFixture(), manager := fixture.Manager, adapter := fixture.Adapter
    adapter.FailNextSet := true
    TopThrows(ObjBindMethod(manager, "Toggle", 1), "native set failed")
    TopCheck(!adapter.Windows[1].Topmost && !manager.Pins.Count && !adapter.Claims.Count, "Failed pin rolls back possible native side effect")
    manager.Toggle(1), manager.Toggle(2)
    adapter.FailNextSet := true
    TopThrows(ObjBindMethod(manager, "Dispose"), "native set failed")
    TopCheck(manager.Pins.Count = 1 && !adapter.Windows[2].Topmost, "Cleanup continues across other pins and preserves retry state")
    TopCheck(manager.Pins[1].PendingCleanup, "Failed disposal is explicitly queued for cleanup")
    adapter.Clock += 100
    manager.Tick()
    TopCheck(!manager.Pins.Count && !adapter.Claims.Count, "Tick automatically completes failed cleanup")
    manager.Toggle(1)
    adapter.FailNextSet := true
    TopThrows(ObjBindMethod(manager, "Toggle", 1), "native set failed")
    TopCheck(manager.Pins[1].PendingCleanup && !fixture.Outlines.Items[3].Visible, "Failed unpin queues cleanup and hides its outline")
    callCount := adapter.SetCalls.Length
    adapter.Clock += 100
    manager.Tick()
    TopCheck(!manager.Pins.Count && !adapter.Claims.Count && !adapter.Windows[1].Topmost,
        "Tick automatically completes a failed manual unpin")
    TopCheck(adapter.SetCalls.Length = callCount, "Cleanup retry never reasserts topmost after native unpin succeeded")
}

TestTopRejections() {
    for , field in ["Own", "Excluded", "Minimized", "Visible"] {
        fixture := TopFixture()
        fixture.Adapter.Windows[1].%field% := field != "Visible"
        try fixture.Manager.Toggle(1)
        catch Error {
        }
        TopCheck(!fixture.Adapter.SetCalls.Length && !fixture.Manager.Pins.Count, "Ineligible target is untouched")
    }
}

TestTopNative() {
    foreground := DllCall("User32\GetForegroundWindow", "Ptr")
    dpi := DllCall("User32\GetThreadDpiAwarenessContext", "Ptr")
    hwnd := WindowDragNativeAdapter().WithDpi(TopCreateHiddenFixture)
    manager := 0
    try {
        adapter := AlwaysOnTopNativeAdapter(hwnd)
        manager := AlwaysOnTop(adapter, () => AlwaysOnTopOutline(true))
        initial := adapter.ReadTarget(hwnd)
        TopCheck(!initial.Topmost, "Hidden fixture begins non-topmost")
        manager.Toggle(hwnd)
        record := manager.Pins[hwnd]
        TopCheck(adapter.ReadTarget(hwnd).Topmost && adapter.OwnsClaim(hwnd, record.Lease), "Native pin and unique property marker are installed")
        TopCheck(record.Outline.Windows.Length = 4, "Four reusable native edge windows created")
        for , window in record.Outline.Windows {
            exStyle := DllCall("User32\GetWindowLongW", "Ptr", window.Hwnd, "Int", -20, "UInt")
            TopCheck((exStyle & 0x080800A0) = 0x080800A0, "Outline is layered transparent no-activate tool window")
            TopCheck(!DllCall("User32\IsWindowVisible", "Ptr", window.Hwnd, "Int"), "Test outline remains hidden")
        }
        manager.ConfigureOutline(true, "FFAA00", 5)
        manager.Toggle(hwnd)
        TopCheck(!adapter.ReadTarget(hwnd).Topmost && !adapter.OwnsClaim(hwnd, record.Lease), "Native unpin restores state and removes marker")
        manager.Toggle(hwnd)
        manager.Dispose()
        TopCheck(!adapter.ReadTarget(hwnd).Topmost, "Native disposal restores owned pin")
        finalRect := adapter.ReadTarget(hwnd).Rect
        TopCheck(finalRect.X = initial.Rect.X && finalRect.Y = initial.Rect.Y
            && finalRect.W = initial.Rect.W && finalRect.H = initial.Rect.H, "Pinning never changes target geometry")
        TopCheck(!DllCall("User32\IsWindowVisible", "Ptr", hwnd, "Int")
            && DllCall("User32\GetForegroundWindow", "Ptr") = foreground, "Fixture remains hidden and foreground unchanged")
        TopCheck(DllCall("User32\AreDpiAwarenessContextsEqual", "Ptr", dpi,
            "Ptr", DllCall("User32\GetThreadDpiAwarenessContext", "Ptr"), "Int"), "DPI context restored")
    } finally {
        if IsObject(manager)
            manager.Dispose()
        DllCall("User32\DestroyWindow", "Ptr", hwnd, "Int")
    }
}

TopCreateHiddenFixture() {
    hwnd := DllCall("User32\CreateWindowExW", "UInt", 0, "Str", "Static",
        "Str", "AlwaysOnTop hidden test fixture", "UInt", 0x00CF0000,
        "Int", -1200, "Int", -900, "Int", 500, "Int", 400,
        "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
    if !hwnd
        throw Error("Could not create hidden native fixture.")
    return hwnd
}
