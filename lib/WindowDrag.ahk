#Requires AutoHotkey v2.0

; Geometry and lifetime are independent of input hooks and native window calls.
class WindowDrag {
    __New(adapter := unset, overlay := unset) {
        this.Adapter := IsSet(adapter) ? adapter : WindowDragNativeAdapter()
        this.Overlay := IsSet(overlay) ? overlay : 0
        this.Session := 0
        this.Starting := 0
    }

    Active => IsObject(this.Session)

    Begin(token, action, hwnd) {
        previousCritical := A_IsCritical
        Critical("On")
        attempt := 0
        startedSession := 0
        try {
            if this.Active || IsObject(this.Starting)
                throw Error("Finish the current window drag before starting another.")
            if action != "MoveWindow" && action != "ResizeWindow"
                throw ValueError("Choose Move window or Resize window.")
            attempt := {}, this.Starting := attempt
            original := this.Adapter.ReadTarget(hwnd).Clone()
            if this.Starting != attempt
                return false
            this.Validate(original, action)
            minimum := action = "ResizeWindow" ? this.Adapter.ReadMinimum(hwnd) : {W: 1, H: 1}
            if this.Starting != attempt
                return false
            cursor := this.Adapter.ReadCursor()
            if this.Starting != attempt
                return false
            target := this.Adapter.ReadTarget(hwnd)
            if this.Starting != attempt
                return false
            this.Validate(target, action)
            this.ValidateIdentity(target, original)
            rect := target.Rect.Clone()
            minimum := {W: Max(1, Min(32767, minimum.W)), H: Max(1, Min(32767, minimum.H))}
            startedSession := {Token: token, Action: action, Target: target.Clone(), Origin: rect,
                Cursor: cursor.Clone(), Minimum: minimum, Last: rect.Clone(),
                Left: cursor.X < rect.X + rect.W / 2, Top: cursor.Y < rect.Y + rect.H / 2}
            this.Session := startedSession
            if IsObject(this.Overlay)
                this.Overlay.Begin(target, cursor)
            if !this.IsCurrent(startedSession)
                return false
            return true
        } catch Error as err {
            if IsObject(attempt) && (this.Starting = attempt || this.IsCurrent(startedSession))
                this.Cancel()
            throw err
        } finally {
            if IsObject(attempt) && this.Starting = attempt
                this.Starting := 0
            Critical(previousCritical)
        }
    }

    Tick() {
        previousCritical := A_IsCritical
        Critical("On")
        session := 0
        try {
            if !this.Active
                return false
            session := this.Session
            cursor := this.Adapter.ReadCursor()
            if !this.IsCurrent(session)
                return false
            target := this.Adapter.ReadTarget(session.Target.Hwnd)
            if !this.IsCurrent(session)
                return false
            this.Validate(target, session.Action)
            this.ValidateIdentity(target, session.Target)
            dx := cursor.X - session.Cursor.X, dy := cursor.Y - session.Cursor.Y
            rect := session.Origin.Clone()
            if session.Action = "MoveWindow" {
                rect.X += dx, rect.Y += dy
                rect.W := target.Rect.W, rect.H := target.Rect.H
                rect.MoveOnly := true
            } else {
                rect.W := Max(session.Minimum.W, rect.W + (session.Left ? -dx : dx))
                rect.H := Max(session.Minimum.H, rect.H + (session.Top ? -dy : dy))
                if session.Left
                    rect.X := session.Origin.X + session.Origin.W - rect.W
                if session.Top
                    rect.Y := session.Origin.Y + session.Origin.H - rect.H
            }
            last := session.Last
            if rect.X != last.X || rect.Y != last.Y || rect.W != last.W || rect.H != last.H {
                if !this.IsCurrent(session)
                    return false
                this.Adapter.ApplyRect(target.Hwnd, rect)
                if !this.IsCurrent(session)
                    return false
                session.Last := rect.Clone()
            }
            if IsObject(this.Overlay) {
                ; Preview follows intended geometry immediately. ASYNCWINDOWPOS
                ; may leave the observed target one or more frames behind.
                previewTarget := target.Clone()
                previewTarget.Rect := rect.Clone()
                this.Overlay.Update(previewTarget, cursor)
                if !this.IsCurrent(session)
                    return false
            }
            return true
        } catch Error as err {
            if this.IsCurrent(session)
                this.Cancel()
            throw err
        } finally {
            Critical(previousCritical)
        }
    }

    End(token, finish := true) {
        previousCritical := A_IsCritical
        Critical("On")
        session := 0
        try {
            if !this.Active || token != this.Session.Token
                return false
            session := this.Session
            if finish
                this.Tick()
            return true
        } finally {
            if this.IsCurrent(session)
                this.Cancel()
            Critical(previousCritical)
        }
    }

    Cancel() {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            this.Session := 0
            this.Starting := 0
            if IsObject(this.Overlay)
                this.Overlay.Hide()
        } finally {
            Critical(previousCritical)
        }
    }

    Dispose() {
        try this.Cancel()
        finally {
            if IsObject(this.Overlay)
                this.Overlay.Dispose()
            this.Overlay := 0
        }
    }

    IsCurrent(session) => IsObject(session) && this.Active && this.Session = session

    ValidateIdentity(target, original) {
        if target.Hwnd != original.Hwnd || target.PID != original.PID
            || target.Thread != original.Thread || target.Class != original.Class
            throw Error("Window drag stopped because the target window changed.")
    }

    Validate(target, action) {
        if target.Own
            throw Error("Choose another application's window; mapper windows cannot be dragged.")
        if !target.Visible
            throw Error("The target window is hidden or no longer visible.")
        if target.Minimized
            throw Error("Restore the minimized window before dragging it.")
        if target.Maximized
            throw Error("Restore the maximized window before dragging it.")
        if target.Excluded
            throw Error("Desktop, taskbar, tooltips, and overlay windows cannot be dragged.")
        if action = "ResizeWindow" && !target.Resizable
            throw Error("This window does not support resizing.")
        if target.Rect.W <= 0 || target.Rect.H <= 0
            throw Error("The target window has no usable rectangle.")
    }
}

class WindowDragNativeAdapter {
    ; Tests may opt in for ONE hidden window owned by the test process only.
    ; Normal construction provides no exception for mapper-owned/hidden windows.
    __New(hiddenFixtureHwnd := 0) {
        this.HiddenFixtureHwnd := hiddenFixtureHwnd
        if hiddenFixtureHwnd
            this.CheckFixture(hiddenFixtureHwnd)
    }

    ReadTarget(hwnd) => this.WithDpi(ObjBindMethod(this, "ReadTargetPhysical"), hwnd)
    ReadCursor() => this.WithDpi(ObjBindMethod(this, "ReadCursorPhysical"))
    ReadMinimum(hwnd) => this.WithDpi(ObjBindMethod(this, "ReadMinimumPhysical"), hwnd)
    ApplyRect(hwnd, rect) => this.WithDpi(ObjBindMethod(this, "ApplyRectPhysical"), hwnd, rect)

    WithDpi(callback, args*) {
        previousCritical := A_IsCritical
        Critical("On")
        previousDpi := 0
        try {
            previousDpi := DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
            if !previousDpi
                throw Error("Windows could not establish physical coordinates for window dragging.")
            return callback.Call(args*)
        } finally {
            if previousDpi
                DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", previousDpi, "Ptr")
            Critical(previousCritical)
        }
    }

    CheckFixture(hwnd) {
        pid := 0
        DllCall("User32\GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid, "UInt")
        if hwnd != this.HiddenFixtureHwnd || pid != DllCall("Kernel32\GetCurrentProcessId", "UInt")
            || DllCall("User32\IsWindowVisible", "Ptr", hwnd, "Int")
            throw Error("Native drag test access requires the exact hidden, process-owned fixture.")
    }

    ReadTargetPhysical(hwnd) {
        if !hwnd || !DllCall("User32\IsWindow", "Ptr", hwnd, "Int")
            throw Error("The target window was closed or is no longer available.")
        if this.HiddenFixtureHwnd
            this.CheckFixture(hwnd)
        pid := 0
        targetThread := DllCall("User32\GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid, "UInt")
        classBuffer := Buffer(512, 0)
        if !targetThread || !DllCall("User32\GetClassNameW", "Ptr", hwnd, "Ptr", classBuffer, "Int", 256, "Int")
            throw Error("The target window's identity could not be read.")
        className := StrGet(classBuffer)
        style := DllCall("User32\GetWindowLongW", "Ptr", hwnd, "Int", -16, "UInt")
        exStyle := DllCall("User32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "UInt")
        rectBuffer := Buffer(16, 0)
        if !DllCall("User32\GetWindowRect", "Ptr", hwnd, "Ptr", rectBuffer, "Int")
            throw Error("The target window's rectangle could not be read.")
        x := NumGet(rectBuffer, 0, "Int"), y := NumGet(rectBuffer, 4, "Int")
        cloaked := 0
        DllCall("Dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14,
            "UInt*", &cloaked, "UInt", 4, "Int")
        excludedClass := RegExMatch(className,
            "i)^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd|tooltips_class32|SysShadow|#32768|MultitaskingViewFrame)$")
        return {Hwnd: hwnd, PID: pid, Thread: targetThread, Class: className,
            Rect: {X: x, Y: y, W: NumGet(rectBuffer, 8, "Int") - x, H: NumGet(rectBuffer, 12, "Int") - y},
            Own: !this.HiddenFixtureHwnd && pid = DllCall("Kernel32\GetCurrentProcessId", "UInt"),
            Visible: this.HiddenFixtureHwnd || (DllCall("User32\IsWindowVisible", "Ptr", hwnd, "Int") && !cloaked),
            Minimized: DllCall("User32\IsIconic", "Ptr", hwnd, "Int"),
            Maximized: DllCall("User32\IsZoomed", "Ptr", hwnd, "Int"),
            Excluded: excludedClass || (style & 0x48000000) || (exStyle & 0x080000A0)
                || !(style & 0x00C40000), Resizable: !!(style & 0x00040000)}
    }

    ReadCursorPhysical() {
        point := Buffer(8, 0)
        if !DllCall("User32\GetCursorPos", "Ptr", point, "Int")
            throw Error("The pointer position is unavailable on the current desktop.")
        return {X: NumGet(point, 0, "Int"), Y: NumGet(point, 4, "Int")}
    }

    ReadMinimumPhysical(hwnd) {
        if this.HiddenFixtureHwnd
            this.CheckFixture(hwnd)
        width := Max(80, DllCall("User32\GetSystemMetrics", "Int", 34, "Int"))
        height := Max(60, DllCall("User32\GetSystemMetrics", "Int", 35, "Int"))
        info := Buffer(40, 0)
        NumPut("Int", width, "Int", height, info, 24)
        result := 0
        ; WM_GETMINMAXINFO is a marshalled system message; one target, 50 ms.
        if DllCall("User32\SendMessageTimeoutW", "Ptr", hwnd, "UInt", 0x24,
            "UPtr", 0, "Ptr", info, "UInt", 0x23, "UInt", 50, "UPtr*", &result, "Ptr") {
            width := Max(width, NumGet(info, 24, "Int"))
            height := Max(height, NumGet(info, 28, "Int"))
        }
        return {W: Min(32767, width), H: Min(32767, height)}
    }

    ApplyRectPhysical(hwnd, rect) {
        if this.HiddenFixtureHwnd
            this.CheckFixture(hwnd)
        ; ASYNCWINDOWPOS avoids waiting on another app's window procedure.
        ; NOZORDER | NOACTIVATE | NOOWNERZORDER preserves focus and stacking.
        flags := 0x4214 | (rect.HasOwnProp("MoveOnly") && rect.MoveOnly ? 0x1 : 0)
        if !DllCall("User32\SetWindowPos", "Ptr", hwnd, "Ptr", 0,
            "Int", rect.X, "Int", rect.Y, "Int", rect.W, "Int", rect.H, "UInt", flags, "Int")
            throw Error("Windows could not move or resize this window (it may require elevation).")
    }
}
