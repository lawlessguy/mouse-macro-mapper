; Native, offline GDI+ mouse diagram. The callback selects an editor control only.
; Coordinates and hit tests share the same vector paths, in a 350 x 360 space.
class MouseDiagram {
    __New(window, x, y, w, h, callback) {
        this.Window := window
        this.Callback := callback
        this.Mask := 1
        this.Trigger := "L"
        this.Hover := ""
        this.Disposed := false
        this.Paths := Map()
        this.Token := 0
        this.Family := 0
        this.Module := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        startup := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        NumPut("UInt", 1, startup)
        token := 0
        this.Check(DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", startup, "Ptr", 0), "start GDI+")
        this.Token := token
        family := 0
        this.Check(DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &family), "load diagram font")
        this.Family := family
        this.MakePaths()
        this.Picture := window.AddPicture("x" x " y" y " w" w " h" h " +0x100", "")
        this.Control := this.Picture
        this.ClickHandler := ObjBindMethod(this, "Clicked")
        this.Picture.OnEvent("Click", this.ClickHandler)
        this.HoverTimer := ObjBindMethod(this, "UpdateHover")
        this.Redraw()
        SetTimer(this.HoverTimer, 65)
    }

    SetSelection(mask, trigger) {
        if this.Disposed
            return
        this.Mask := mask & 3
        this.Trigger := trigger
        this.Redraw()
    }

    Clicked(*) {
        if this.Disposed
            return
        part := this.PartAtPointer()
        if part != ""
            this.Callback.Call(part)
    }

    UpdateHover(*) {
        if this.Disposed
            return
        part := ""
        if DllCall("IsWindowVisible", "Ptr", this.Picture.Hwnd) && WinActive("ahk_id " this.Window.Hwnd)
            part := this.PartAtPointer()
        if part != this.Hover {
            this.Hover := part
            this.Redraw()
        }
    }

    PartAtPointer() {
        point := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", point)
        DllCall("ScreenToClient", "Ptr", this.Picture.Hwnd, "Ptr", point)
        size := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", this.Picture.Hwnd, "Ptr", size)
        width := NumGet(size, 8, "Int"), height := NumGet(size, 12, "Int")
        if width <= 0 || height <= 0
            return ""
        return this.HitTest(NumGet(point, 0, "Int") * 350 / width, NumGet(point, 4, "Int") * 360 / height)
    }

    ; Public for isolated geometry checks; never emits input.
    HitTest(x, y) {
        if this.Disposed
            return ""
        for part in ["4", "5", "M", "L", "R"] {
            visible := 0
            DllCall("gdiplus\GdipIsVisiblePathPoint", "Ptr", this.Paths[part], "Float", x, "Float", y, "Ptr", 0, "Int*", &visible)
            if visible
                return part
        }
        return ""
    }

    MakePaths() {
        ; Left sidewall gives both thumb buttons a visible, plausible mounting face.
        this.Paths["side"] := this.Path([
            ["M", 158, 36], ["C", 109, 43, 79, 90, 74, 148],
            ["C", 60, 218, 67, 278, 104, 308], ["C", 122, 323, 154, 333, 180, 333],
            ["L", 187, 41], ["C", 177, 35, 167, 34, 158, 36]])
        this.Paths["shell"] := this.Path([
            ["M", 194, 28], ["C", 251, 28, 287, 83, 291, 151],
            ["C", 297, 213, 318, 271, 266, 316], ["C", 235, 343, 169, 342, 132, 324],
            ["C", 87, 301, 83, 264, 91, 211], ["L", 102, 138],
            ["C", 110, 69, 145, 28, 194, 28]])
        this.Paths["L"] := this.Path([
            ["M", 181, 40], ["C", 138, 46, 116, 84, 109, 140],
            ["L", 106, 166], ["C", 125, 180, 152, 185, 182, 181],
            ["L", 182, 158], ["C", 173, 149, 173, 101, 182, 91], ["L", 185, 41]])
        this.Paths["R"] := this.Path([
            ["M", 203, 40], ["C", 247, 46, 273, 87, 280, 141],
            ["L", 283, 166], ["C", 263, 180, 234, 185, 205, 181],
            ["L", 204, 158], ["C", 213, 149, 213, 101, 204, 91], ["L", 201, 41]])
        this.Paths["M"] := this.RoundedPath(183, 93, 21, 62, 10)
        this.Paths["4"] := this.Path([
            ["M", 88, 123], ["C", 95, 123, 97, 129, 95, 138],
            ["L", 91, 164], ["C", 90, 172, 86, 175, 80, 174],
            ["C", 73, 173, 72, 169, 74, 160], ["L", 78, 134],
            ["C", 79, 126, 82, 123, 88, 123]])
        this.Paths["5"] := this.Path([
            ["M", 78, 185], ["C", 85, 185, 88, 189, 87, 198],
            ["L", 85, 225], ["C", 84, 233, 80, 237, 74, 236],
            ["C", 67, 235, 66, 230, 67, 222], ["L", 69, 196],
            ["C", 70, 188, 73, 185, 78, 185]])
    }

    Redraw() {
        if this.Disposed
            return
        size := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", this.Picture.Hwnd, "Ptr", size)
        width := Max(1, NumGet(size, 8, "Int")), height := Max(1, NumGet(size, 12, "Int"))
        bitmap := 0, graphics := 0
        this.Check(DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", width, "Int", height, "Int", 0,
            "Int", 0x26200A, "Ptr", 0, "Ptr*", &bitmap), "create diagram bitmap")
        try {
            this.Check(DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bitmap, "Ptr*", &graphics), "draw diagram")
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
            DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", graphics, "Int", 4)
            DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFFF3F6FA)
            DllCall("gdiplus\GdipScaleWorldTransform", "Ptr", graphics, "Float", width / 350, "Float", height / 360, "Int", 0)
            ; Restrained ambient shadow and a fine cable stem.
            this.Ellipse(graphics, 97, 315, 201, 27, 0x0C1E2E46)
            this.Ellipse(graphics, 112, 322, 171, 15, 0x0B1E2E46)
            this.Line(graphics, 194, 5, 194, 28, 0xFFCBD5E1, 3)
            this.Shape(graphics, this.Paths["side"], 0xFF172332, 0xFF0E1825, 1)
            this.Shape(graphics, this.Paths["shell"], 0xFF253448, 0xFF101C2C, 1.1)
            for part in ["L", "R", "M", "4", "5"] {
                selected := part = "4" ? (this.Mask & 1) : part = "5" ? (this.Mask & 2) : InStr(this.Trigger, part)
                hovering := this.Hover = part
                isSide := part = "4" || part = "5"
                fill := selected ? (isSide ? 0xFF6778EE : 0xFF5269D7) : (hovering ? 0xFF465B77 : (isSide ? 0xFF3B4D64 : 0xFF30425A))
                stroke := selected ? 0xFFB0BFFF : (hovering ? 0xFF9FB4D4 : 0xFF556982)
                if selected
                    this.Shape(graphics, this.Paths[part], 0, 0x245D7CFF, 7)
                this.Shape(graphics, this.Paths[part], fill, stroke, selected ? 1.8 : 1)
            }
            ; A physical ribbed wheel, with its middle-click label on the palm.
            Loop 7
                this.Line(graphics, 188, 101 + A_Index * 6, 199, 101 + A_Index * 6, 0x88E4ECFF, 1)
            this.Text(graphics, "L", 131, 99, 33, 24, 15, 0xFFF4F7FC, 1)
            this.Text(graphics, "R", 230, 99, 33, 24, 15, 0xFFF4F7FC, 1)
            this.Text(graphics, "4", 74, 137, 23, 22, 12, 0xFFFFFFFF, 1)
            this.Text(graphics, "5", 66, 198, 23, 22, 12, 0xFFFFFFFF, 1)
            this.Text(graphics, "MIDDLE", 165, 195, 59, 15, 8.5, 0xFFA7B9D0, 1)
            this.Line(graphics, 194, 164, 194, 187, 0xFF566D8A, 1)
            ; Small palm mark and quiet outside thumb-button legends.
            this.Line(graphics, 181, 269, 187, 280, 0xFF58718F, 2)
            this.Line(graphics, 187, 280, 194, 265, 0xFF58718F, 2)
            this.Line(graphics, 194, 265, 201, 280, 0xFF58718F, 2)
            this.Line(graphics, 201, 280, 207, 269, 0xFF58718F, 2)
            this.Line(graphics, 42, 149, 65, 149, 0xFFBCC8D8, 1)
            this.Line(graphics, 36, 211, 58, 211, 0xFFBCC8D8, 1)
            this.Text(graphics, "04", 11, 138, 29, 23, 10, 0xFF65768D, 1)
            this.Text(graphics, "05", 5, 200, 29, 23, 10, 0xFF65768D, 1)
            hbitmap := 0
            this.Check(DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bitmap, "Ptr*", &hbitmap, "UInt", 0xFFF3F6FA), "present diagram")
            ; Without *, AHK owns this handle and frees it on replace/destroy.
            try this.Picture.Value := "HBITMAP:" hbitmap
            catch {
                DllCall("DeleteObject", "Ptr", hbitmap)
                throw
            }
        } finally {
            if graphics
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
            DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
        }
    }

    Path(commands) {
        path := 0, px := 0, py := 0
        this.Check(DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path), "create mouse outline")
        for c in commands {
            switch c[1] {
                case "M":
                    px := c[2], py := c[3]
                case "L":
                    DllCall("gdiplus\GdipAddPathLine", "Ptr", path, "Float", px, "Float", py, "Float", c[2], "Float", c[3])
                    px := c[2], py := c[3]
                case "C":
                    DllCall("gdiplus\GdipAddPathBezier", "Ptr", path, "Float", px, "Float", py,
                        "Float", c[2], "Float", c[3], "Float", c[4], "Float", c[5], "Float", c[6], "Float", c[7])
                    px := c[6], py := c[7]
            }
        }
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
        return path
    }

    RoundedPath(x, y, w, h, r) {
        path := 0
        this.Check(DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path), "create wheel outline")
        for arc in [[x,y,180], [x+w-2*r,y,270], [x+w-2*r,y+h-2*r,0], [x,y+h-2*r,90]]
            DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", arc[1], "Float", arc[2],
                "Float", r*2, "Float", r*2, "Float", arc[3], "Float", 90)
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
        return path
    }

    Shape(g, path, fill, stroke := 0, thickness := 1) {
        if fill {
            brush := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", fill, "Ptr*", &brush)
            DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", brush, "Ptr", path)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
        }
        if stroke {
            pen := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", stroke, "Float", thickness, "Int", 2, "Ptr*", &pen)
            DllCall("gdiplus\GdipDrawPath", "Ptr", g, "Ptr", pen, "Ptr", path)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
        }
    }

    Line(g, x1, y1, x2, y2, color, thickness) {
        pen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", thickness, "Int", 2, "Ptr*", &pen)
        DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", x1, "Float", y1, "Float", x2, "Float", y2)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    }

    Ellipse(g, x, y, w, h, color) {
        brush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", color, "Ptr*", &brush)
        DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", brush, "Float", x, "Float", y, "Float", w, "Float", h)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    }

    Text(g, value, x, y, w, h, size, color, bold := 0) {
        font := 0, brush := 0, format := 0
        rect := Buffer(16)
        NumPut("Float", x, "Float", y, "Float", w, "Float", h, rect)
        DllCall("gdiplus\GdipCreateFont", "Ptr", this.Family, "Float", size, "Int", bold, "Int", 2, "Ptr*", &font)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", color, "Ptr*", &brush)
        DllCall("gdiplus\GdipStringFormatGetGenericTypographic", "Ptr*", &format)
        DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", format, "Int", 1)
        DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", format, "Int", 1)
        DllCall("gdiplus\GdipDrawString", "Ptr", g, "WStr", value, "Int", -1, "Ptr", font, "Ptr", rect, "Ptr", format, "Ptr", brush)
        DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", format)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
        DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
    }

    Dispose(*) {
        if this.Disposed
            return
        this.Disposed := true
        if this.HasOwnProp("HoverTimer") {
            SetTimer(this.HoverTimer, 0)
            this.HoverTimer := 0
        }
        if this.HasOwnProp("Picture") {
            if this.HasOwnProp("ClickHandler")
                try this.Picture.OnEvent("Click", this.ClickHandler, 0)
            try this.Picture.Value := ""
        }
        this.ClickHandler := 0
        this.Callback := 0
        for name, path in this.Paths
            DllCall("gdiplus\GdipDeletePath", "Ptr", path)
        this.Paths.Clear()
        if this.Family
            DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", this.Family)
        if this.Token
            DllCall("gdiplus\GdiplusShutdown", "Ptr", this.Token)
        if this.Module
            DllCall("FreeLibrary", "Ptr", this.Module)
    }

    Check(status, action) {
        if status
            throw Error("Could not " action " (GDI+ status " status ").")
    }
}
