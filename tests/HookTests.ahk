#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ../lib/MacroModel.ahk

; INTEGRATION TEST: takes foreground focus and injects simulated input into its own
; disposable native windows. Close any other Mouse Macro Mapper instance first.
; This never edits the real mappings.ini and never claims physical-mouse coverage.
; Run with the same AutoHotkey v2 interpreter as the app, e.g.:
; AutoHotkey64.exe /ErrorStdOut tests\HookTests.ahk
SetTitleMatchMode(3)
DetectHiddenWindows(true)
CoordMode("Mouse", "Screen")
SendMode("Event")
SetKeyDelay(15, 15)
SetMouseDelay(15)
global Harness := HookHarness()
OnExit((*) => Harness.Cleanup())
exitCode := 1
try {
    Harness.Run()
    exitCode := 0
} catch Error as err {
    Harness.Log("FAIL: " err.Message " (" err.File ":" err.Line ")")
} finally {
    Harness.Cleanup()
    Harness.Finish(exitCode)
}
ExitApp(exitCode)

class HookHarness {
    __New() {
        this.ChildPid := 0
        this.ChildHwnd := 0
        this.Assertions := 0
        this.Groups := 0
        this.Skipped := 0
        this.NativeX2 := true
        this.Events := []
        this.Trace := []
        this.Windows := Map()
        this.Receivers := Map()
        this.Held := Map()
        this.Current := ""
        this.Cleaned := false
        this.Finished := false
        this.RunID := ProcessExist() "-" A_TickCount
        this.ArtifactDir := A_ScriptDir "\artifacts"
        this.AppDir := this.ArtifactDir "\hook-app\" this.RunID
        DirCreate(this.AppDir "\lib")
        DirCreate(this.AppDir "\tests")
        this.ReportPath := this.ArtifactDir "\hook-report-" this.RunID ".log"
        this.Log("Mouse Macro Mapper simulated input integration test")
        this.Log("AHK " A_AhkVersion " / " A_AhkPath)
        this.Log("Isolated app: " this.AppDir)
        this.Log("Mouse/key messages are observed at disposable receiver windows.")
        this.Log("Mouse injection: Win32 mouse_event with explicit XBUTTON data; keyboard injection: SendLevel(1) + SendEvent.")
        this.Log("This is injected-input validation, not physical hardware validation.")
    }

    Run() {
        if WinGetList("Mouse Macro Mapper ahk_class AutoHotkeyGUI").Length
            throw Error("Close the other Mouse Macro Mapper instance before running this test. No input was injected.")
        for , key in ["LButton", "RButton", "MButton", "XButton1", "XButton2", "Ctrl", "Alt", "Shift", "LWin", "RWin"]
            if GetKeyState(key)
                throw Error("Release " key " before running this test. No input was injected.")
        for , path in ["MouseMacroMapper.ahk", "lib\MacroModel.ahk", "lib\ChordState.ahk", "lib\CombinationCapture.ahk", "lib\BindingGestures.ahk", "lib\HeldKeyOutput.ahk", "lib\MapperKeyOutput.ahk", "lib\WindowDrag.ahk", "lib\WindowDragOverlay.ahk", "lib\AlwaysOnTop.ahk", "lib\ProfileCycleHotkey.ahk", "lib\AppearanceSettings.ahk", "lib\MouseDiagram.ahk", "tests\UiTests.ahk", "tests\RecordUiTests.ahk", "tests\BindingEditorTests.ahk", "tests\ChordRuntimeTests.ahk", "tests\ProfileRuntimeTests.ahk", "tests\NativeActionRuntimeTests.ahk", "tests\BindingRuntimeTests.ahk"]
            FileCopy(A_ScriptDir "\..\" path, this.AppDir "\" path, true)
        this.BuildReceivers()
        this.Group("receiver baseline without mapper", ObjBindMethod(this, "Baseline"))
        this.StartChild()
        this.Group("all nine mappings; both side press/release orders and early side releases", ObjBindMethod(this, "AllChords"))
        this.Group("preserved unused side actions are emitted only on release", ObjBindMethod(this, "PreservedSides"))
        this.Group("normal clicks, dragging, and wheel remain intact", ObjBindMethod(this, "NormalInput"))
        this.Group("repeated gestures and duplicate downs keep one trigger per click", ObjBindMethod(this, "RepeatedClicks"))
        this.Group("pointer recipient changes suppress pending standalone replay", ObjBindMethod(this, "PointerCancellation"))
        this.Group("preserve toggle is saved and blocks unused side actions", ObjBindMethod(this, "DisabledPreserve"))
        this.StartChild("unassigned")
        this.Group("unassigned combos pass clicks and never fall back to single-side mappings", ObjBindMethod(this, "Unassigned"))
        this.StartChild("delayed")
        this.Group("pause cancels delayed output and keeps mapped release cleanup", ObjBindMethod(this, "PauseCancellation"))
        this.Group("pause restores normal input; resume with held side waits for release", ObjBindMethod(this, "PausedAndResume"))
        this.Group("focus changes cancel delayed output in both receiver windows", ObjBindMethod(this, "FocusCancellation"))
        this.Group("Escape cancels delayed output", ObjBindMethod(this, "EscapeCancellation"))
        this.Log("Completed: " this.Groups " groups; " this.Assertions " assertions; " this.Skipped " receiver assertions unavailable")
    }

    BuildReceivers() {
        width := Min(460, (A_ScreenWidth - 90) // 2)
        for index, name in ["A", "B"] {
            window := Gui("-MaximizeBox -MinimizeBox", "Disposable mouse test receiver " name " - " this.RunID)
            window.BackColor := name = "A" ? "DDEEF4" : "F3E6DC"
            window.SetFont("s11", "Segoe UI")
            ; Keep the input target itself empty: no context menus, shortcuts,
            ; navigation, user data, or child-control default actions.
            window.Show("x" (30 + (index - 1) * (width + 30)) " y80 w" width " h320")
            this.Receivers[name] := window
            this.Windows[window.Hwnd] := name
        }
        this.MessageFn := ObjBindMethod(this, "Receive")
        for , msg in [0x100, 0x101, 0x102, 0x104, 0x105,
            0x200, 0x201, 0x202, 0x203, 0x204, 0x205, 0x206,
            0x207, 0x208, 0x209, 0x20A, 0x20B, 0x20C, 0x20D, 0x20E, 0x7B]
            OnMessage(msg, this.MessageFn)
        this.Focus("A")
    }

    Receive(wParam, lParam, msg, hwnd) {
        if !this.Windows.Has(hwnd)
            return
        names := Map(0x100, "KD", 0x101, "KU", 0x102, "CHAR", 0x104, "KD", 0x105, "KU",
            0x200, "MOVE", 0x201, "LD", 0x202, "LU", 0x203, "LD",
            0x204, "RD", 0x205, "RU", 0x206, "RD", 0x207, "MD", 0x208, "MU", 0x209, "MD",
            0x20A, "WHEEL", 0x20E, "HWHEEL", 0x7B, "CONTEXT")
        kind := (msg = 0x20B || msg = 0x20D) ? "X" ((wParam >> 16) & 0xFFFF) "D"
            : msg = 0x20C ? "X" ((wParam >> 16) & 0xFFFF) "U" : names[msg]
        entry := {Window: this.Windows[hwnd], Kind: kind, Value: wParam, At: A_TickCount}
        this.Events.Push(entry)
        this.Trace.Push(entry.At " " entry.Window " " kind " " Format("0x{:X}", wParam))
        ; A real native capture path makes the drag regression meaningful.
        if msg = 0x201
            DllCall("SetCapture", "Ptr", hwnd)
        else if msg = 0x202
            DllCall("ReleaseCapture")
        ; Mark all receiver input handled; these windows have no real actions.
        return (msg = 0x20B || msg = 0x20C || msg = 0x20D) ? 1 : 0
    }

    StartChild(profile := "all") {
        this.StopChild()
        settings := MapperSettings(this.AppDir "\mappings.ini")
        settings.Preserve := true
        settings.Paused := false
        for index, id in MacroModel.IDs {
            source := "key F" (index + 12)
            if profile = "unassigned" && (id = "4L" || id = "45M")
                source := ""
            if profile = "delayed" && id = "4L"
                source := "key F13`ndelay 600`nkey F22"
            settings.Mappings[id] := {Name: "TEST " id, Source: source, Steps: MacroModel.Parse(source)}
        }
        settings.Save()
        Run('"' A_AhkPath '" /ErrorStdOut "' this.AppDir '\MouseMacroMapper.ahk"', this.AppDir, , &childPid)
        this.ChildPid := childPid
        this.ChildHwnd := WinWait("Mouse Macro Mapper ahk_pid " childPid, , 5)
        if !this.ChildHwnd
            throw Error("Isolated mapper did not show its GUI. Check inherited ErrorStdOut.")
        ; DetectHiddenWindows also finds a GUI while it is still being built.
        ; Wait for the child's initial Show to finish before taking focus back.
        if !WinWaitActive("ahk_id " this.ChildHwnd, , 5)
            throw Error("Isolated mapper GUI did not complete its initial activation.")
        Sleep(150)
        this.Focus("A")
        this.Clear()
        this.Log("Loaded profile: " profile " (child PID " childPid ")")
    }

    StopChild() {
        if this.ChildPid && ProcessExist(this.ChildPid) {
            if this.ChildHwnd && WinExist("ahk_id " this.ChildHwnd) {
                try ControlClick("Exit mapper", "ahk_id " this.ChildHwnd, , "Left", 1, "NA")
                catch Error
                    Sleep(10)
                ProcessWaitClose(this.ChildPid, 1)
            }
            if ProcessExist(this.ChildPid)
                ProcessClose(this.ChildPid)
            ProcessWaitClose(this.ChildPid, 2)
        }
        this.ChildPid := 0
        this.ChildHwnd := 0
    }

    Group(name, callback) {
        this.Log("RUN: " name)
        this.Focus("A")
        this.Clear()
        callback.Call()
        this.Assert(this.Held.Count = 0, "Group ended with injected mouse buttons held")
        this.Groups += 1
        this.Log("PASS: " name)
    }

    Baseline() {
        this.Key("{F24}")
        this.ExpectKey(0x87, 1, "Receiver observes injected F24")
        for , button in ["LButton", "RButton", "MButton", "XButton1", "XButton2"] {
            this.Clear()
            this.Tap(button)
            if button = "XButton2" && this.Count("X2D") = 0 && this.Count("X2U") = 0 {
                this.NativeX2 := false
                this.Skipped += 2
                this.Log("ENVIRONMENT LIMITATION: XButton2 down/up do not reach the native receiver BEFORE mapper starts.")
                this.Log("Continuing active production-hook tests; XButton2 standalone/passthrough receiver assertions will be explicitly unavailable.")
                continue
            }
            this.MousePair(button, 1, "Receiver baseline " button)
        }
    }

    AllChords() {
        for index, id in MacroModel.IDs {
            sides := SubStr(id, 1, StrLen(id) - 1)
            button := Map("L", "LButton", "R", "RButton", "M", "MButton")[SubStr(id, StrLen(id))]
            pressOrders := sides = "45" ? [["XButton1", "XButton2"], ["XButton2", "XButton1"]]
                : [[sides = "4" ? "XButton1" : "XButton2"]]
            for , order in pressOrders {
                releaseOrders := order.Length = 2 ? [[order[1], order[2]], [order[2], order[1]]] : [order]
                for , releases in releaseOrders {
                    for , early in [false, true] {
                        this.Clear()
                        for , side in order
                            this.Down(side)
                        this.Down(button)
                        if early
                            for , side in releases
                                this.Up(side)
                        this.Up(button)
                        if !early
                            for , side in releases
                                this.Up(side)
                        this.Wait(100)
                        label := id " / first=" order[1] " / release=" releases[1] " / early=" early
                        this.ExpectKey(0x7B + index, 1, label)
                        this.Assert(this.FunctionDowns() = 1, label " must trigger exactly one mapping")
                        this.NoMouse(label " must suppress click and used side actions")
                    }
                }
            }
        }
    }

    PreservedSides() {
        for , side in ["XButton1", "XButton2"] {
            this.Clear()
            this.Down(side)
            this.Wait(80)
            this.NoMouse("Standalone " side " must not be forwarded before release")
            this.Up(side)
            this.Wait(100)
            this.MousePair(side, 1, "Standalone " side " replays once")
            this.Assert(this.FunctionDowns() = 0, "Standalone must not trigger a mapping")
        }
    }

    NormalInput() {
        for , button in ["LButton", "RButton", "MButton"] {
            this.Clear()
            this.Tap(button)
            this.MousePair(button, 1, "Normal " button)
            this.Assert(this.FunctionDowns() = 0, "Ordinary click must not emit macro key")
        }
        this.Clear()
        this.Down("LButton")
        this.Down("XButton1")
        this.MoveInside("A", 35)
        this.Up("XButton1")
        this.Up("LButton")
        this.MousePair("LButton", 1, "Drag begun before side remains a normal drag")
        this.Assert(this.Count("X1D") + this.Count("X1U") = 0, "Side overlapping drag is consumed")
        this.Assert(this.FunctionDowns() = 0, "Drag first must not become a mapping")
        movedHeld := false
        for , event in this.Events
            if event.Kind = "MOVE" && (event.Value & 1)
                movedHeld := true
        this.Assert(movedHeld, "Receiver observed a real mouse-move message while left button was down")
        this.Clear()
        ; Separate opposite wheel ticks so Windows cannot coalesce them to zero.
        this.Key("{WheelUp}")
        this.Key("{WheelDown}")
        this.Assert(this.Count("WHEEL") = 2, "Ordinary wheel messages pass unchanged")
        this.Assert(this.FunctionDowns() = 0, "Wheel is not mapped")
    }

    RepeatedClicks() {
        this.Down("XButton1")
        this.Tap("RButton")
        this.Wait(100)
        this.Tap("RButton")
        this.Wait(100)
        this.Up("XButton1")
        this.ExpectKey(0x7D, 2, "Two discrete clicks while held produce two F14 taps")
        this.NoMouse("Repeated mapped clicks and used side remain suppressed")
        this.Clear()
        this.Down("XButton2")
        this.Down("MButton")
        this.Wait(100)
        this.Down("MButton")
        this.Up("XButton2")
        this.Up("MButton")
        this.ExpectKey(0x81, 1, "Duplicate down produces only one F18 tap")
        this.NoMouse("Mapped up stays blocked after side is released")
    }

    PointerCancellation() {
        this.Down("XButton1")
        this.MoveInside("B")
        this.Up("XButton1")
        this.Wait(100)
        this.NoMouse("Moving to a different native recipient cancels standalone replay")
        this.Assert(this.FunctionDowns() = 0, "Pointer change emits no key")
        this.MoveInside("A")
    }

    DisabledPreserve() {
        this.Guard()
        ControlClick("Preserve unused side-button actions (replay on release)", "ahk_id " this.ChildHwnd, , "Left", 1, "NA")
        this.Wait(100)
        settings := MapperSettings(this.AppDir "\mappings.ini")
        this.Assert(!settings.Preserve && !settings.Paused, "GUI preserve toggle persists without changing active mode")
        for , side in ["XButton1", "XButton2"] {
            this.Clear()
            this.Tap(side)
            this.NoMouse("Preserve disabled blocks " side " completely")
        }
        this.Clear()
        this.Down("XButton1")
        this.Tap("RButton")
        this.Up("XButton1")
        this.Wait(100)
        this.ExpectKey(0x7D, 1, "Mappings continue with preserve disabled")
        this.NoMouse("Preserve disabled still swallows mapped click")
    }

    Unassigned() {
        this.Down("XButton1")
        this.Tap("LButton")
        this.Up("XButton1")
        this.MousePair("LButton", 1, "Unassigned single-side click passes")
        this.Assert(this.FunctionDowns() = 0, "Unassigned single-side click emits no key")
        this.Assert(this.Count("X1D") + this.Count("X1U") = 0, "Unassigned single-side consumes side")
        for , order in [["XButton1", "XButton2"], ["XButton2", "XButton1"]] {
            this.Clear()
            for , side in order
                this.Down(side)
            this.Down("MButton")
            this.Up(order[1])
            this.Up(order[2])
            this.Up("MButton")
            this.MousePair("MButton", 1, "Unassigned both-side click passes, even with sides released first")
            this.Assert(this.FunctionDowns() = 0, "Unassigned both-side must not fall back to F15 or F18")
            this.Assert(this.SideEvents() = 0, "Both used sides stay consumed")
        }
    }

    PauseCancellation() {
        this.Down("XButton1")
        this.Down("LButton")
        this.WaitForKey(0x7C)
        this.Key("^!{F12}")
        this.Assert(MapperSettings(this.AppDir "\mappings.ini").Paused, "Global shortcut persists paused state")
        this.Up("XButton1")
        this.Up("LButton")
        this.Wait(750)
        this.ExpectKey(0x7C, 1, "First delayed macro step was received")
        this.ExpectKey(0x85, 0, "Pause cancels delayed F22")
        this.NoMouse("Pause keeps previously blocked releases swallowed")
    }

    PausedAndResume() {
        this.Assert(MapperSettings(this.AppDir "\mappings.ini").Paused, "Previous group left child paused")
        for , button in ["LButton", "RButton", "MButton", "XButton1", "XButton2"] {
            this.Clear()
            this.Down(button)
            if button = "XButton2" && !this.NativeX2 && this.Count("X2D") = 0 {
                this.Skipped += 1
                this.Log("UNAVAILABLE: Paused XButton2 immediate down: native baseline was already intercepted.")
            } else
                this.Assert(this.Count(this.MouseStem(button) "D") = 1, "Paused " button " down passes immediately")
            this.Up(button)
            this.MousePair(button, 1, "Paused ordinary " button)
        }
        this.Clear()
        this.Down("XButton1")
        this.Key("^!{F12}")
        this.Assert(!MapperSettings(this.AppDir "\mappings.ini").Paused, "Resume persists active mode")
        this.Tap("RButton")
        this.Up("XButton1")
        this.MousePair("XButton1", 1, "Side begun while paused retains normal release after resume")
        this.MousePair("RButton", 1, "Resume while held waits for all buttons to release")
        this.Assert(this.FunctionDowns() = 0, "Held gesture on resume cannot trigger mapping")
        this.Clear()
        this.Down("XButton1")
        this.Tap("RButton")
        this.Up("XButton1")
        this.Wait(100)
        this.ExpectKey(0x7D, 1, "Fresh gesture works after rearming")
        this.NoMouse("Fresh mapped gesture is swallowed after resume")
    }

    FocusCancellation() {
        this.Down("XButton1")
        this.Tap("LButton")
        this.Up("XButton1")
        this.WaitForKey(0x7C)
        this.Focus("B")
        this.Wait(750)
        this.ExpectKey(0x7C, 1, "First step reached original receiver")
        this.ExpectKey(0x85, 0, "Focus change prevents delayed F22 in both receivers")
        this.Assert(this.Count("KD", 0x7C, "A") = 1, "First step belongs to receiver A")
        this.Assert(this.Count("KD", 0x7C, "B") = 0, "No first-step output reached receiver B")
        this.Focus("A")
        this.Clear()
        this.Down("XButton2")
        this.Focus("B")
        this.Up("XButton2")
        this.NoMouse("Focus change also cancels pending unused-side replay")
        this.Focus("A")
    }

    EscapeCancellation() {
        this.Down("XButton1")
        this.Tap("LButton")
        this.Up("XButton1")
        this.WaitForKey(0x7C)
        this.Key("{Esc}")
        this.Wait(750)
        this.ExpectKey(0x7C, 1, "Escape test received first step")
        this.ExpectKey(0x85, 0, "Escape cancels delayed F22")
    }

    Focus(name) {
        hwnd := this.Receivers[name].Hwnd
        WinActivate("ahk_id " hwnd)
        if !WinWaitActive("ahk_id " hwnd, , 2)
            throw Error("Could not activate disposable receiver " name "; no further input will be sent.")
        this.Current := name
        DllCall("SetFocus", "Ptr", hwnd)
        this.MoveInside(name)
        this.Wait(120)
    }

    MoveInside(name, offset := 0) {
        this.Guard()
        WinGetClientPos(&x, &y, &w, &h, "ahk_id " this.Receivers[name].Hwnd)
        MouseMove(x + w // 2 + offset, y + h // 2, 0)
        Sleep(40)
        this.Guard()
    }

    Guard() {
        if this.Current = "" || WinExist("A") != this.Receivers[this.Current].Hwnd
            throw Error("Foreground moved away from the expected disposable receiver. Injection aborted.")
        if this.ChildPid && !ProcessExist(this.ChildPid)
            throw Error("Isolated mapper exited unexpectedly. Injection aborted.")
    }

    Down(button) {
        this.Guard()
        this.Held[button] := true
        this.InjectMouse(button, true)
        Sleep(45)
        this.Guard()
    }

    Up(button) {
        this.Guard()
        this.InjectMouse(button, false)
        if this.Held.Has(button)
            this.Held.Delete(button)
        Sleep(45)
        this.Guard()
    }

    InjectMouse(button, down) {
        ; Explicit XBUTTON1=1 / XBUTTON2=2 avoids AHK SendEvent button-name
        ; translation and lets the native baseline verify the OS event path.
        flags := Map("LButton", [0x2, 0x4], "RButton", [0x8, 0x10],
            "MButton", [0x20, 0x40], "XButton1", [0x80, 0x100], "XButton2", [0x80, 0x100])
        data := button = "XButton1" ? 1 : button = "XButton2" ? 2 : 0
        DllCall("mouse_event", "UInt", flags[button][down ? 1 : 2],
            "UInt", 0, "UInt", 0, "UInt", data, "UPtr", 0x4D4D4854)
    }

    Tap(button) {
        this.Down(button)
        this.Up(button)
    }

    Key(sequence) {
        this.Guard()
        SendLevel(1)
        SendEvent(sequence)
        Sleep(80)
        this.Guard()
    }

    Wait(ms) {
        deadline := A_TickCount + ms
        while A_TickCount < deadline {
            this.Guard()
            Sleep(Max(1, Min(20, deadline - A_TickCount)))
        }
        this.Guard()
    }

    WaitForKey(vk) {
        deadline := A_TickCount + 1000
        while !this.Count("KD", vk) && A_TickCount < deadline
            this.Wait(15)
        this.Assert(this.Count("KD", vk) > 0, "Expected first key did not reach receiver")
    }

    Clear() {
        this.Wait(65)
        this.Events := []
        this.Trace.Push("---- next assertion case ----")
    }

    Count(kind, value := -1, window := "") {
        count := 0
        for , event in this.Events
            if event.Kind = kind && (value = -1 || event.Value = value) && (window = "" || event.Window = window)
                count += 1
        return count
    }

    FunctionDowns() {
        count := 0
        for , event in this.Events
            if event.Kind = "KD" && event.Value >= 0x7C && event.Value <= 0x87
                count += 1
        return count
    }

    SideEvents() => this.Count("X1D") + this.Count("X1U") + this.Count("X2D") + this.Count("X2U")
    MouseStem(button) => Map("LButton", "L", "RButton", "R", "MButton", "M", "XButton1", "X1", "XButton2", "X2")[button]

    MousePair(button, expected, label) {
        stem := this.MouseStem(button)
        if button = "XButton2" && !this.NativeX2 && expected > 0 && this.Count("X2D") = 0 && this.Count("X2U") = 0 {
            this.Skipped += 2
            this.Log("UNAVAILABLE: " label ": native XButton2 baseline was already intercepted before the mapper started.")
            return
        }
        this.Assert(this.Count(stem "D") = expected, label " down count expected " expected "; got " this.Count(stem "D"))
        this.Assert(this.Count(stem "U") = expected, label " up count expected " expected "; got " this.Count(stem "U"))
    }

    ExpectKey(vk, expected, label) {
        this.Assert(this.Count("KD", vk) = expected, label " key-down expected " expected "; got " this.Count("KD", vk))
        this.Assert(this.Count("KU", vk) = expected, label " key-up expected " expected "; got " this.Count("KU", vk))
    }

    NoMouse(label) {
        count := this.SideEvents()
        for , kind in ["LD", "LU", "RD", "RU", "MD", "MU"]
            count += this.Count(kind)
        this.Assert(count = 0, label "; observed " count " mouse button messages")
    }

    Assert(condition, message) {
        this.Assertions += 1
        if !condition
            throw Error(message)
    }

    Log(message) {
        FileAppend(message "`n", this.ReportPath, "UTF-8")
        try FileAppend(message "`n", "*")
    }

    Cleanup() {
        if this.Cleaned
            return
        this.Cleaned := true
        ; Terminate only the PID returned by this harness's Run call, before any
        ; cleanup releases. Never close/replace another mapper or user process.
        this.StopChild()
        if this.Held.Count && this.Receivers.Has("A") {
            hwnd := this.Receivers["A"].Hwnd
            try {
                WinActivate("ahk_id " hwnd)
                if WinWaitActive("ahk_id " hwnd, , 2) {
                    SendLevel(0)
                    for button, down in this.Held
                        this.InjectMouse(button, false)
                    this.Held.Clear()
                } else
                    this.Log("CLEANUP: Receiver could not be activated for safe injected-button release.")
            } catch Error as err
                this.Log("CLEANUP: " err.Message)
        }
        DllCall("ReleaseCapture")
        for , window in this.Receivers
            try window.Destroy()
    }

    Finish(exitCode) {
        if this.Finished
            return
        this.Finished := true
        result := exitCode != 0 ? "FAIL" : this.Skipped ? "PASS WITH ENVIRONMENT LIMITATIONS" : "PASS"
        this.Log("RESULT: " result " / groups=" this.Groups " / assertions=" this.Assertions " / unavailable=" this.Skipped)
        this.Log("--- native receiver trace ---")
        for , line in this.Trace
            FileAppend(line "`n", this.ReportPath, "UTF-8")
        FileCopy(this.ReportPath, this.ArtifactDir "\hook-latest.log", true)
        try FileAppend("Report: " this.ReportPath "`n", "*")
    }
}
