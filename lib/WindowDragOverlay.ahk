#Requires AutoHotkey v2.0

; Two reusable windows keep the colored wash translucent and geometry legible.
; HiddenOnly fixtures exercise native styles/geometry without ever showing them.
class WindowDragOverlay {
    __New(hiddenOnly := false, color := "FFFFFF", transparency := 60) {
        this.HiddenOnly := !!hiddenOnly
        this.Active := false
        this.Disposed := false
        this.TargetHwnd := 0
        this.LastRect := 0
        this.LastLabelRect := 0
        this.LastText := ""
        this.WithDpi(ObjBindMethod(this, "CreateWindows"))
        try this.Configure(color, transparency)
        catch Error as err {
            this.Dispose()
            throw err
        }
    }

    CreateWindows() {
        ; WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE, plus tool/topmost.
        options := "+AlwaysOnTop +ToolWindow -Caption -Border -Resize -DPIScale +E0x08080020"
        this.Wash := Gui(options, "Mouse Macro Mapper drag wash")
        try {
            this.Badge := Gui(options, "Mouse Macro Mapper drag geometry")
            this.Badge.BackColor := "000000"
            this.Badge.SetFont("s9 cFFFFFF", "Segoe UI")
            this.GeometryText := this.Badge.AddText("x10 y10 w160 h34 Center BackgroundTrans", "")
            if !DllCall("User32\SetLayeredWindowAttributes", "Ptr", this.Badge.Hwnd, "UInt", 0, "UChar", 255, "UInt", 2, "Int")
                throw Error("Windows could not initialize the drag geometry label.")
        } catch Error as err {
            if this.HasOwnProp("Badge")
                this.Badge.Destroy()
            this.Wash.Destroy()
            throw err
        }
    }

    Configure(color, transparency) {
        if this.Disposed
            throw Error("The window drag overlay has been disposed.")
        if !RegExMatch(color, "i)^[0-9a-f]{6}$")
            throw ValueError("Overlay color must contain six hexadecimal digits.")
        if !RegExMatch(transparency, "^\d+$") || Integer(transparency) > 100
            throw ValueError("Overlay transparency must be a whole number from 0 to 100.")
        this.WithDpi(ObjBindMethod(this, "ConfigurePhysical"), StrUpper(color), Integer(transparency))
    }

    ConfigurePhysical(color, transparency) {
        this.Wash.BackColor := color
        alpha := Round(255 * (100 - transparency) / 100)
        if !DllCall("User32\SetLayeredWindowAttributes", "Ptr", this.Wash.Hwnd, "UInt", 0, "UChar", alpha, "UInt", 2, "Int")
            throw Error("Windows could not set the window drag overlay transparency.")
        this.Color := color
        this.Transparency := transparency
        this.Alpha := alpha
    }

    Begin(target, cursor) {
        if this.Disposed
            throw Error("The window drag overlay has been disposed.")
        this.Hide()
        this.TargetHwnd := target.Hwnd
        this.Active := true
        return this.Update(target, cursor)
    }

    Update(target, cursor) {
        if !this.Active || this.Disposed
            return false
        try {
            if target.Hwnd != this.TargetHwnd
                throw Error("The drag overlay target changed.")
            if target.Rect.W <= 0 || target.Rect.H <= 0
                throw Error("The drag overlay rectangle is empty.")
            this.WithDpi(ObjBindMethod(this, "UpdatePhysical"), target.Rect, cursor)
            return true
        } catch Error as err {
            this.Hide()
            throw err
        }
    }

    UpdatePhysical(rect, cursor) {
        text := "X: " Round(rect.X) " Y: " Round(rect.Y) "`nW: " Round(rect.W) " H: " Round(rect.H)
        size := this.MeasureText(text)
        work := this.ReadWorkArea(cursor)
        label := WindowDragOverlay.LabelBounds(cursor, size, work)
        this.GeometryText.Text := text
        this.GeometryText.Move(10, 10, Max(1, label.W - 20), Max(1, label.H - 20))
        ; HiddenOnly never passes SWP_SHOWWINDOW. No Gui.Show or activation calls.
        flags := 0x210 | (this.HiddenOnly ? 0 : 0x40)
        this.Position(this.Wash.Hwnd, rect, flags)
        this.Position(this.Badge.Hwnd, label, flags)
        this.LastRect := rect.Clone()
        this.LastLabelRect := label.Clone()
        this.LastText := text
    }

    MeasureText(text) {
        dc := DllCall("User32\GetDC", "Ptr", this.Badge.Hwnd, "Ptr")
        if !dc
            throw Error("The drag label font could not be measured.")
        previousFont := 0
        try {
            font := DllCall("User32\SendMessageW", "Ptr", this.GeometryText.Hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
            if font
                previousFont := DllCall("Gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
            bounds := Buffer(16, 0)
            if !DllCall("User32\DrawTextW", "Ptr", dc, "Str", text, "Int", -1, "Ptr", bounds, "UInt", 0xC01, "Int")
                throw Error("The drag geometry label could not be measured.")
            return {W: NumGet(bounds, 8, "Int") + 20, H: NumGet(bounds, 12, "Int") + 20}
        } finally {
            if previousFont
                DllCall("Gdi32\SelectObject", "Ptr", dc, "Ptr", previousFont, "Ptr")
            DllCall("User32\ReleaseDC", "Ptr", this.Badge.Hwnd, "Ptr", dc, "Int")
        }
    }

    ReadWorkArea(cursor) {
        point := Buffer(8, 0)
        NumPut("Int", Round(cursor.X), "Int", Round(cursor.Y), point)
        monitor := DllCall("User32\MonitorFromPoint", "Int64", NumGet(point, 0, "Int64"), "UInt", 2, "Ptr")
        info := Buffer(40, 0)
        NumPut("UInt", 40, info)
        if !monitor || !DllCall("User32\GetMonitorInfoW", "Ptr", monitor, "Ptr", info, "Int")
            throw Error("The drag label monitor work area is unavailable.")
        return {X: NumGet(info, 20, "Int"), Y: NumGet(info, 24, "Int"),
            W: NumGet(info, 28, "Int") - NumGet(info, 20, "Int"), H: NumGet(info, 32, "Int") - NumGet(info, 24, "Int")}
    }

    static LabelBounds(cursor, size, work) {
        width := Min(size.W, work.W), height := Min(size.H, work.H)
        x := cursor.X + 16, y := cursor.Y + 20
        if x + width > work.X + work.W
            x := cursor.X - width - 16
        if y + height > work.Y + work.H
            y := cursor.Y - height - 20
        return {X: Round(Max(work.X, Min(x, work.X + work.W - width))),
            Y: Round(Max(work.Y, Min(y, work.Y + work.H - height))), W: width, H: height}
    }

    Position(hwnd, rect, flags) {
        if !DllCall("User32\SetWindowPos", "Ptr", hwnd, "Ptr", -1,
            "Int", Round(rect.X), "Int", Round(rect.Y), "Int", Round(rect.W), "Int", Round(rect.H), "UInt", flags, "Int")
            throw Error("Windows could not position the drag overlay.")
    }

    Hide() {
        this.Active := false
        this.TargetHwnd := 0
        if !this.Disposed {
            DllCall("User32\ShowWindow", "Ptr", this.Wash.Hwnd, "Int", 0, "Int")
            DllCall("User32\ShowWindow", "Ptr", this.Badge.Hwnd, "Int", 0, "Int")
        }
    }

    Dispose() {
        if this.Disposed
            return
        this.Hide()
        this.Disposed := true
        try this.Wash.Destroy()
        finally this.Badge.Destroy()
    }

    WithDpi(callback, args*) {
        previousCritical := A_IsCritical
        Critical("On")
        previousDpi := 0
        try {
            previousDpi := DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
            if !previousDpi
                throw Error("Windows could not establish physical coordinates for the drag overlay.")
            return callback.Call(args*)
        } finally {
            if previousDpi
                DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", previousDpi, "Ptr")
            Critical(previousCritical)
        }
    }
}
