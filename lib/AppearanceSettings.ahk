; The native picker is opened only by an explicit color-button click.
class MapperAppearance {
    static CustomColors := Buffer(64, 0xFF)

    __New(host) {
        this.Host := host
        this.OverlayColor := host.Config.OverlayColor
        this.PinColor := host.Config.PinOutlineColor
        this.Window := Gui("+Owner" host.Window.Hwnd " -MinimizeBox -MaximizeBox", "Window appearance")
        this.Window.SetFont("s10", "Segoe UI")
        this.Window.BackColor := "F3F6FA"
        this.Window.AddText("x20 y18 w460 h23", "Move / resize preview")
        this.TintButton := this.Window.AddButton("x20 y51 w167 h30", "Tint: #" this.OverlayColor)
        this.TintButton.OnEvent("Click", (*) => this.PickColor("Overlay"))
        this.Window.AddText("x204 y32 w275 h20", "Transparency: 0% opaque, 100% invisible")
        this.TransparencySlider := this.Window.AddSlider("x200 y53 w208 h30 Range0-100 ToolTip", host.Config.OverlayTransparency)
        this.TransparencyEdit := this.Window.AddEdit("x420 y54 w48 h25 Number Limit3", host.Config.OverlayTransparency)
        this.Window.AddText("x475 y56 w20 h20", "%")
        this.TransparencySlider.OnEvent("Change", (*) => this.SliderChanged())
        this.TransparencyEdit.OnEvent("Change", (*) => this.PercentChanged())
        this.Preview := this.Window.AddProgress("x20 y99 w460 h44 Range0-100", 100)
        this.Window.AddText("x20 y148 w460 h22 c57657B", "Tint preview over gray. Geometry text stays legible.")
        this.OutlineEnabled := this.Window.AddCheckbox("x20 y184 w460 h26", "Outline windows pinned with Always on top")
        this.OutlineEnabled.Value := host.Config.PinOutlineEnabled
        this.PinButton := this.Window.AddButton("x20 y220 w167 h30", "Outline: #" this.PinColor)
        this.PinButton.OnEvent("Click", (*) => this.PickColor("Pin"))
        this.Window.AddText("x222 y226 w130 h24", "Thickness (px)")
        this.ThicknessEdit := this.Window.AddEdit("x357 y222 w85 h25 Number Limit2", host.Config.PinOutlineThickness)
        this.Feedback := this.Window.AddText("x20 y264 w460 h37 cA03030", "")
        this.Window.AddButton("x228 y310 w120 h30 Default", "Save appearance").OnEvent("Click", (*) => this.Save())
        this.Window.AddButton("x360 y310 w120 h30", "Cancel").OnEvent("Click", (*) => this.Close())
        this.Window.OnEvent("Close", (*) => this.Close())
        this.Window.OnEvent("Escape", (*) => this.Close())
        this.UpdatePreview()
        if !host.Testing
            this.Window.Show("w502 h359")
    }

    SliderChanged() {
        this.TransparencyEdit.Value := this.TransparencySlider.Value
        this.UpdatePreview()
    }

    PercentChanged() {
        value := this.TransparencyEdit.Value
        if RegExMatch(value, "^\d+$") && Integer(value) <= 100 {
            this.TransparencySlider.Value := Integer(value)
            this.UpdatePreview()
        }
    }

    static Blend(color, transparency) {
        rgb := Integer("0x" color), result := 0
        for , shift in [16, 8, 0] {
            component := (rgb >> shift) & 255
            blended := Round(component * (100 - transparency) / 100 + 96 * transparency / 100)
            result |= blended << shift
        }
        return Format("{:06X}", result)
    }

    UpdatePreview() {
        this.Preview.Opt("c" MapperAppearance.Blend(this.OverlayColor, this.TransparencySlider.Value))
        this.TintButton.Text := "Tint: #" this.OverlayColor
        this.PinButton.Text := "Outline: #" this.PinColor
    }

    PickColor(kind) {
        if this.Host.Testing
            return
        current := kind = "Overlay" ? this.OverlayColor : this.PinColor
        chosen := MapperAppearance.ChooseColor(this.Window.Hwnd, current)
        if chosen = ""
            return
        if kind = "Overlay"
            this.OverlayColor := chosen
        else
            this.PinColor := chosen
        this.UpdatePreview()
    }

    static ChooseColor(owner, color) {
        rgb := Integer("0x" color)
        colorRef := ((rgb & 255) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 255)
        data := Buffer(A_PtrSize = 8 ? 72 : 36, 0)
        NumPut("UInt", data.Size, data, 0)
        NumPut("Ptr", owner, data, A_PtrSize = 8 ? 8 : 4)
        NumPut("UInt", colorRef, data, A_PtrSize = 8 ? 24 : 12)
        NumPut("Ptr", this.CustomColors.Ptr, data, A_PtrSize = 8 ? 32 : 16)
        NumPut("UInt", 3, data, A_PtrSize = 8 ? 40 : 20) ; RGBINIT | FULLOPEN
        if !DllCall("Comdlg32\ChooseColorW", "Ptr", data, "Int")
            return ""
        selected := NumGet(data, A_PtrSize = 8 ? 24 : 12, "UInt")
        return Format("{:06X}", ((selected & 255) << 16) | (selected & 0xFF00) | ((selected >> 16) & 255))
    }

    Save() {
        config := this.Host.Config
        previous := Map("OverlayColor", config.OverlayColor, "OverlayTransparency", config.OverlayTransparency,
            "PinOutlineEnabled", config.PinOutlineEnabled, "PinOutlineColor", config.PinOutlineColor,
            "PinOutlineThickness", config.PinOutlineThickness)
        try {
            if !RegExMatch(this.OverlayColor, "i)^[0-9A-F]{6}$") || !RegExMatch(this.PinColor, "i)^[0-9A-F]{6}$")
                throw ValueError("Choose a valid six-digit RGB color.")
            if !RegExMatch(this.TransparencyEdit.Value, "^\d+$") || Integer(this.TransparencyEdit.Value) > 100
                throw ValueError("Transparency must be 0 to 100 percent.")
            if !RegExMatch(this.ThicknessEdit.Value, "^\d+$") || Integer(this.ThicknessEdit.Value) < 1 || Integer(this.ThicknessEdit.Value) > 12
                throw ValueError("Outline thickness must be 1 to 12 pixels.")
            this.Host.Cancel("Window appearance updated.")
            config.OverlayColor := StrUpper(this.OverlayColor)
            config.OverlayTransparency := Integer(this.TransparencyEdit.Value)
            config.PinOutlineEnabled := !!this.OutlineEnabled.Value
            config.PinOutlineColor := StrUpper(this.PinColor)
            config.PinOutlineThickness := Integer(this.ThicknessEdit.Value)
            this.Host.ApplyAppearance()
            if !this.Host.SavePreferences()
                throw Error("Appearance was not saved.")
            this.Close()
            return true
        } catch Error as err {
            for property, value in previous
                config.%property% := value
            try this.Host.ApplyAppearance()
            this.Feedback.Text := err.Message
            return false
        }
    }

    Close() {
        this.Window.Destroy()
        if this.Host.HasOwnProp("Appearance")
            this.Host.DeleteProp("Appearance")
    }
}
