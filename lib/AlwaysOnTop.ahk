#Requires AutoHotkey v2.0
#Include WindowDrag.ahk

; Owns only pins created by this instance. Profiles and input cancellation do
; not affect these records; Dispose is the explicit shutdown cleanup boundary.
class AlwaysOnTop {
    __New(adapter := unset, outlineFactory := unset) {
        this.Adapter := IsSet(adapter) ? adapter : AlwaysOnTopNativeAdapter()
        this.OutlineFactory := IsSet(outlineFactory) ? outlineFactory : () => AlwaysOnTopOutline()
        this.Pins := Map()
        this.OutlineEnabled := true, this.Color := "0078D4", this.Thickness := 3
        this.LastTick := -100, this.LastError := ""
    }

    Toggle(hwnd) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if this.Pins.Has(hwnd) {
                record := this.Pins[hwnd]
                if this.Owns(record) {
                    this.Unpin(record)
                    return "Always on top off."
                }
                this.Drop(record)
            }
            target := this.Adapter.ReadTarget(hwnd)
            this.Validate(target)
            if target.Topmost
                return "This window is already always on top; its existing setting was left unchanged."
            lease := this.Adapter.Claim(hwnd)
            record := {Target: target.Clone(), Lease: lease, Outline: 0, PendingCleanup: false}
            this.Pins[hwnd] := record
            try {
                if !this.Owns(record)
                    throw Error("The target window changed before it could be pinned.")
                this.Adapter.SetTopmost(hwnd, true, record.Lease)
                this.Refresh(record)
            } catch Error as err {
                rollback := ""
                try this.Unpin(record)
                catch Error as cleanupError
                    rollback := " Cleanup will retry: " cleanupError.Message
                throw Error(err.Message rollback)
            }
            return "Always on top on."
        } finally {
            Critical(previousCritical)
        }
    }

    ConfigureOutline(enabled, color, thickness) {
        color := StrUpper(Trim(color))
        if SubStr(color, 1, 1) = "#"
            color := SubStr(color, 2)
        if !RegExMatch(color, "^[0-9A-F]{6}$")
            throw ValueError("Outline color must contain six hexadecimal digits, for example 0078D4.")
        if !IsInteger(thickness) || thickness < 1 || thickness > 12
            throw ValueError("Outline thickness must be an integer from 1 to 12 pixels.")
        previousCritical := A_IsCritical
        Critical("On")
        try {
            this.OutlineEnabled := !!enabled, this.Color := color, this.Thickness := Integer(thickness)
            this.LastTick := -100
            this.Tick()
        } finally {
            Critical(previousCritical)
        }
    }

    Tick() {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            now := this.Adapter.Now()
            if now - this.LastTick < 100
                return
            this.LastTick := now
            for , record in this.Records() {
                try {
                    if record.PendingCleanup
                        this.Unpin(record)
                    else
                        this.Refresh(record)
                }
                catch Error as err {
                    this.LastError := err.Message
                    if IsObject(record.Outline)
                        try record.Outline.Hide()
                }
            }
        } finally {
            Critical(previousCritical)
        }
    }

    Dispose() {
        previousCritical := A_IsCritical
        Critical("On")
        failure := 0
        try {
            for , record in this.Records() {
                try this.Unpin(record)
                catch Error as err {
                    if !failure
                        failure := err
                    if IsObject(record.Outline)
                        try record.Outline.Hide()
                }
            }
        } finally {
            Critical(previousCritical)
        }
        if failure
            throw failure
    }

    Records() {
        records := []
        for , record in this.Pins
            records.Push(record)
        return records
    }

    Validate(target) {
        if target.Own
            throw Error("Choose another application's window; mapper and outline windows cannot be pinned.")
        if !target.Visible || target.Minimized
            throw Error("Restore and show the target window before pinning it.")
        if target.Excluded || target.Rect.W <= 0 || target.Rect.H <= 0
            throw Error("Desktop, taskbar, tooltips, and overlay windows cannot be pinned.")
    }

    SameTarget(current, original) => current.Hwnd = original.Hwnd && current.PID = original.PID
        && current.Thread = original.Thread && current.Class = original.Class

    Owns(record) {
        hwnd := record.Target.Hwnd
        if !this.Adapter.Exists(hwnd)
            return false
        current := this.Adapter.ReadTarget(hwnd)
        return this.SameTarget(current, record.Target) && this.Adapter.OwnsClaim(hwnd, record.Lease)
    }

    Refresh(record) {
        hwnd := record.Target.Hwnd
        if !this.Owns(record) {
            this.Drop(record)
            return
        }
        current := this.Adapter.ReadTarget(hwnd)
        if !current.Topmost {
            this.Adapter.ReleaseClaim(hwnd, record.Lease)
            this.Drop(record)
            return
        }
        if !this.OutlineEnabled || !current.Visible || current.Minimized {
            if IsObject(record.Outline)
                record.Outline.Hide()
            return
        }
        if !IsObject(record.Outline)
            record.Outline := this.OutlineFactory.Call()
        record.Outline.Configure(this.Color, this.Thickness)
        record.Outline.Show(current.Rect)
    }

    Unpin(record) {
        try {
            hwnd := record.Target.Hwnd
            if this.Owns(record) {
                current := this.Adapter.ReadTarget(hwnd)
                if current.Topmost
                    this.Adapter.SetTopmost(hwnd, false, record.Lease)
                this.Adapter.ReleaseClaim(hwnd, record.Lease)
            }
            this.Drop(record)
        } catch Error as err {
            record.PendingCleanup := true
            if IsObject(record.Outline)
                try record.Outline.Hide()
            throw err
        }
    }

    Drop(record) {
        if IsObject(record.Outline)
            record.Outline.Dispose()
        hwnd := record.Target.Hwnd
        if this.Pins.Has(hwnd) && this.Pins[hwnd] = record
            this.Pins.Delete(hwnd)
    }
}

class AlwaysOnTopNativeAdapter extends WindowDragNativeAdapter {
    __New(hiddenFixtureHwnd := 0) {
        super.__New(hiddenFixtureHwnd)
        this.LeaseCounter := 0
        this.PropertyPrefix := "MouseMacroMapper.Topmost." ProcessExist() "." A_TickCount "." Random(1, 2147483647) "."
    }

    Now() => A_TickCount
    Exists(hwnd) => !!DllCall("User32\IsWindow", "Ptr", hwnd, "Int")

    ReadTargetPhysical(hwnd) {
        target := super.ReadTargetPhysical(hwnd)
        target.Topmost := !!(DllCall("User32\GetWindowLongW", "Ptr", hwnd, "Int", -20, "UInt") & 0x8)
        ; DWM visible frame bounds are physical pixels, excluding invisible
        ; resize borders so maximized-window outlines stay on screen.
        bounds := Buffer(16, 0)
        if !DllCall("Dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", bounds, "UInt", 16, "Int") {
            x := NumGet(bounds, 0, "Int"), y := NumGet(bounds, 4, "Int")
            width := NumGet(bounds, 8, "Int") - x, height := NumGet(bounds, 12, "Int") - y
            if width > 0 && height > 0
                target.Rect := {X: x, Y: y, W: width, H: height}
        }
        return target
    }

    Claim(hwnd) {
        if this.HiddenFixtureHwnd
            this.CheckFixture(hwnd)
        this.LeaseCounter += 1
        lease := {Name: this.PropertyPrefix this.LeaseCounter, Value: this.LeaseCounter}
        if !DllCall("User32\SetPropW", "Ptr", hwnd, "Str", lease.Name, "Ptr", lease.Value, "Int")
            throw Error("Windows could not mark this window for safe pin ownership (it may require elevation).")
        return lease
    }

    OwnsClaim(hwnd, lease) => DllCall("User32\GetPropW", "Ptr", hwnd, "Str", lease.Name, "Ptr") = lease.Value

    ReleaseClaim(hwnd, lease) {
        if this.HiddenFixtureHwnd
            this.CheckFixture(hwnd)
        if this.OwnsClaim(hwnd, lease)
            if DllCall("User32\RemovePropW", "Ptr", hwnd, "Str", lease.Name, "Ptr") != lease.Value
                throw Error("Windows could not remove this mapper's pin ownership marker.")
    }

    SetTopmost(hwnd, topmost, lease) {
        if this.HiddenFixtureHwnd
            this.CheckFixture(hwnd)
        if !this.OwnsClaim(hwnd, lease)
            throw Error("The target window's pin ownership marker changed.")
        ; Pin/unpin only: never activate, move, resize, show, or reorder owner.
        if !DllCall("User32\SetWindowPos", "Ptr", hwnd, "Ptr", topmost ? -1 : -2,
            "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x213, "Int")
            throw Error("Windows could not change always-on-top state for this window.")
    }
}

class AlwaysOnTopOutline {
    ; noShow is an explicit test-only switch: geometry/style can be checked
    ; against hidden owned windows without drawing on the user's desktop.
    __New(noShow := false) {
        this.NoShow := noShow, this.Windows := []
        this.Dpi := WindowDragNativeAdapter()
        this.Color := "", this.Thickness := 3, this.LastRect := 0
        try this.Dpi.WithDpi(ObjBindMethod(this, "Create"))
        catch Error as err {
            this.Dispose()
            throw err
        }
    }

    Create() {
        loop 4 {
            window := Gui("-Caption +ToolWindow +AlwaysOnTop +E0x08080020 -DPIScale", "Mouse Mapper pin outline")
            this.Windows.Push(window)
            if !DllCall("User32\SetLayeredWindowAttributes", "Ptr", window.Hwnd, "UInt", 0, "UChar", 255, "UInt", 2, "Int")
                throw Error("Windows could not create the click-through pin outline.")
        }
    }

    Configure(color, thickness) {
        if this.Color != color {
            for , window in this.Windows
                window.BackColor := color
            this.Color := color
        }
        this.Thickness := thickness
    }

    Show(rect) {
        this.LastRect := rect.Clone()
        this.Dpi.WithDpi(ObjBindMethod(this, "Place"), rect)
    }

    Place(rect) {
        thickness := Max(1, Min(this.Thickness, Floor(rect.W / 2), Floor(rect.H / 2)))
        edges := [{X: rect.X, Y: rect.Y, W: rect.W, H: thickness},
            {X: rect.X, Y: rect.Y + rect.H - thickness, W: rect.W, H: thickness},
            {X: rect.X, Y: rect.Y + thickness, W: thickness, H: Max(1, rect.H - 2 * thickness)},
            {X: rect.X + rect.W - thickness, Y: rect.Y + thickness, W: thickness, H: Max(1, rect.H - 2 * thickness)}]
        for index, edge in edges {
            ; NOACTIVATE | NOOWNERZORDER; SHOWWINDOW is absent in hidden tests.
            flags := 0x210 | (this.NoShow ? 0 : 0x40)
            if !DllCall("User32\SetWindowPos", "Ptr", this.Windows[index].Hwnd, "Ptr", -1,
                "Int", edge.X, "Int", edge.Y, "Int", edge.W, "Int", edge.H, "UInt", flags, "Int")
                throw Error("Windows could not position the pin outline.")
        }
    }

    Hide() {
        for , window in this.Windows
            window.Hide()
    }

    Dispose() {
        for , window in this.Windows
            window.Destroy()
        this.Windows := []
    }
}
