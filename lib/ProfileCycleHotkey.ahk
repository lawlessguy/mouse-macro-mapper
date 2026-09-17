#Requires AutoHotkey v2.0

; No registration occurs until a nonempty shortcut is configured.
class ProfileCycleHotkey {
    __New(callback, adapter := unset) {
        this.Callback := callback
        this.Adapter := IsSet(adapter) ? adapter : ProfileCycleHotkeyNativeAdapter()
        this.Registration := 0
        this.Shortcut := ""
        this.Disposed := false
    }

    static Parse(text) {
        text := Trim(text)
        if text = ""
            return {Shortcut: "", Key: "", Modifiers: [], Down: "", Up: "", InputLevel: 1}
        parts := StrSplit(text, "+")
        aliases := Map("ctrl", "Ctrl", "control", "Ctrl", "alt", "Alt",
            "shift", "Shift", "win", "Win", "windows", "Win")
        modifiers := Map()
        loop parts.Length - 1 {
            part := StrLower(Trim(parts[A_Index]))
            if !aliases.Has(part)
                throw ValueError("Use Ctrl, Alt, Shift, or Win before one keyboard key.")
            modifier := aliases[part]
            if modifiers.Has(modifier)
                throw ValueError("A shortcut modifier cannot appear twice.")
            modifiers[modifier] := true
        }
        base := StrLower(Trim(parts[parts.Length]))
        names := Map("enter", "Enter", "return", "Enter", "tab", "Tab", "space", "Space",
            "backspace", "Backspace", "bs", "Backspace", "delete", "Delete", "del", "Delete",
            "insert", "Insert", "ins", "Insert", "home", "Home", "end", "End",
            "pgup", "PgUp", "pageup", "PgUp", "pgdn", "PgDn", "pagedown", "PgDn",
            "up", "Up", "down", "Down", "left", "Left", "right", "Right",
            "capslock", "CapsLock", "numlock", "NumLock", "scrolllock", "ScrollLock",
            "printscreen", "PrintScreen", "pause", "Pause")
        if base = "esc" || base = "escape"
            throw ValueError("Escape is reserved for cancelling mapper actions.")
        if RegExMatch(base, "^[a-z0-9]$")
            key := StrUpper(base)
        else if RegExMatch(base, "^f([1-9]|1[0-9]|2[0-4])$")
            key := StrUpper(base)
        else if names.Has(base)
            key := names[base]
        else
            throw ValueError("Choose a keyboard key: F1-F24, a letter, digit, or navigation key; mouse and bare modifier keys are unsupported.")
        if key = "F12" && modifiers.Has("Ctrl") && modifiers.Has("Alt")
            throw ValueError("Ctrl+Alt+F12 is reserved for pausing the mapper.")
        normalized := "", symbols := "", ordered := []
        for , pair in [["Ctrl", "^"], ["Alt", "!"], ["Shift", "+"], ["Win", "#"]] {
            if modifiers.Has(pair[1]) {
                normalized .= pair[1] "+"
                symbols .= pair[2]
                ordered.Push(pair[1])
            }
        }
        return {Shortcut: normalized key, Key: key, Modifiers: ordered,
            Down: "$" symbols key, Up: "~*$" key " Up", InputLevel: 1}
    }

    Configure(text) {
        if this.Disposed
            throw Error("The profile-cycle shortcut service has been disposed.")
        spec := ProfileCycleHotkey.Parse(text)
        if spec.Shortcut = this.Shortcut
            return this.Shortcut
        if spec.Shortcut = "" {
            this.Clear()
            return ""
        }
        previousCritical := A_IsCritical
        Critical("On")
        previous := this.Registration, staged := 0
        try {
            token := {Spec: spec, Pressed: this.Adapter.PhysicalKey(spec.Key)}
            staged := this.Adapter.Register(spec, ObjBindMethod(this, "OnDown", token), ObjBindMethod(this, "OnUp", token))
            token.Native := staged
            this.Adapter.Enable(staged)
            if IsObject(previous)
                this.Adapter.Disable(previous.Native)
            this.Registration := token
            this.Shortcut := spec.Shortcut
            return this.Shortcut
        } catch Error as err {
            rollback := ""
            if IsObject(staged) {
                try this.Adapter.Dispose(staged)
                catch Error as cleanupError
                    rollback .= " Replacement cleanup: " cleanupError.Message
            }
            if IsObject(previous) {
                try this.Adapter.Enable(previous.Native)
                catch Error as restoreError
                    rollback .= " Previous shortcut restoration: " restoreError.Message
            }
            throw Error("Could not register the profile-cycle shortcut: " err.Message rollback)
        } finally {
            Critical(previousCritical)
        }
    }

    OnDown(token, *) {
        if !IsObject(this.Registration) || this.Registration != token || token.Pressed
            return false
        if !this.Adapter.PhysicalShortcut(token.Spec)
            return false
        token.Pressed := true
        this.Adapter.Invoke(this.Callback)
        return true
    }

    OnUp(token, *) {
        if !IsObject(this.Registration) || this.Registration != token
            return false
        if this.Adapter.PhysicalKey(token.Spec.Key)
            return false
        token.Pressed := false
        return true
    }

    Clear() {
        previousCritical := A_IsCritical
        Critical("On")
        previous := this.Registration
        try {
            if IsObject(previous)
                this.Adapter.Disable(previous.Native)
            this.Registration := 0
            this.Shortcut := ""
        } catch Error as err {
            if IsObject(previous) {
                try this.Adapter.Enable(previous.Native)
                catch Error as restoreError
                    throw Error(err.Message " Previous shortcut restoration: " restoreError.Message)
            }
            throw err
        } finally {
            Critical(previousCritical)
        }
    }

    Dispose() {
        this.Clear()
        this.Disposed := true
    }
}

class ProfileCycleHotkeyNativeAdapter {
    Register(spec, downCallback, upCallback) {
        registration := {Enabled: false, Names: [], Spec: spec}
        registration.Context := (*) => registration.Enabled
        HotIf(registration.Context)
        try {
            Hotkey(spec.Down, downCallback, "Off I1 T1 B0")
            registration.Names.Push(spec.Down)
            Hotkey(spec.Up, upCallback, "Off I1 T1 B0")
            registration.Names.Push(spec.Up)
        } catch Error as err {
            try this.Dispose(registration)
            catch Error {
            }
            throw err
        } finally {
            HotIf()
        }
        return registration
    }

    Enable(registration) {
        registration.Enabled := false
        HotIf(registration.Context)
        try {
            for , name in registration.Names
                Hotkey(name, "On", "I1 T1 B0")
            registration.Enabled := true
        } finally {
            HotIf()
        }
    }

    Disable(registration) {
        registration.Enabled := false
        failure := 0
        HotIf(registration.Context)
        try {
            for , name in registration.Names {
                try Hotkey(name, "Off")
                catch Error as err {
                    if !failure
                        failure := err
                }
            }
        } finally {
            HotIf()
        }
        if failure
            throw failure
    }

    Dispose(registration) => this.Disable(registration)
    PhysicalKey(key) => GetKeyState(key, "P")

    PhysicalShortcut(spec) {
        if !this.PhysicalKey(spec.Key)
            return false
        for , modifier in spec.Modifiers {
            if !this.PhysicalKey(modifier)
                return false
        }
        return true
    }

    Invoke(callback) {
        ; I1 excludes mapper SendLevel0/1 input. It also starts this callback's
        ; thread at level1, so do not let that raised level escape into actions.
        previousLevel := A_SendLevel
        try {
            SendLevel(0)
            callback.Call()
        } finally {
            SendLevel(previousLevel)
        }
    }
}
