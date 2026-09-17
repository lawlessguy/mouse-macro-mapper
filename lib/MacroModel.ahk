class MacroModel {
    static Chords := [
        {ID: "4L", Kind: "Chord", Mask: 1, Trigger: "L", Buttons: ["LButton"], Label: "Button 4 + Left"},
        {ID: "4R", Kind: "Chord", Mask: 1, Trigger: "R", Buttons: ["RButton"], Label: "Button 4 + Right"},
        {ID: "4M", Kind: "Chord", Mask: 1, Trigger: "M", Buttons: ["MButton"], Label: "Button 4 + Middle"},
        {ID: "5L", Kind: "Chord", Mask: 2, Trigger: "L", Buttons: ["LButton"], Label: "Button 5 + Left"},
        {ID: "5R", Kind: "Chord", Mask: 2, Trigger: "R", Buttons: ["RButton"], Label: "Button 5 + Right"},
        {ID: "5M", Kind: "Chord", Mask: 2, Trigger: "M", Buttons: ["MButton"], Label: "Button 5 + Middle"},
        {ID: "45L", Kind: "Chord", Mask: 3, Trigger: "L", Buttons: ["LButton"], Label: "Buttons 4 + 5 + Left"},
        {ID: "45R", Kind: "Chord", Mask: 3, Trigger: "R", Buttons: ["RButton"], Label: "Buttons 4 + 5 + Right"},
        {ID: "45M", Kind: "Chord", Mask: 3, Trigger: "M", Buttons: ["MButton"], Label: "Buttons 4 + 5 + Middle"},
        {ID: "4LR", Kind: "Chord", Mask: 1, Trigger: "LR", Buttons: ["LButton", "RButton"], Label: "Button 4 + Left + Right"},
        {ID: "4LM", Kind: "Chord", Mask: 1, Trigger: "LM", Buttons: ["LButton", "MButton"], Label: "Button 4 + Left + Middle"},
        {ID: "4RM", Kind: "Chord", Mask: 1, Trigger: "RM", Buttons: ["RButton", "MButton"], Label: "Button 4 + Right + Middle"},
        {ID: "4LRM", Kind: "Chord", Mask: 1, Trigger: "LRM", Buttons: ["LButton", "RButton", "MButton"], Label: "Button 4 + Left + Right + Middle"},
        {ID: "5LR", Kind: "Chord", Mask: 2, Trigger: "LR", Buttons: ["LButton", "RButton"], Label: "Button 5 + Left + Right"},
        {ID: "5LM", Kind: "Chord", Mask: 2, Trigger: "LM", Buttons: ["LButton", "MButton"], Label: "Button 5 + Left + Middle"},
        {ID: "5RM", Kind: "Chord", Mask: 2, Trigger: "RM", Buttons: ["RButton", "MButton"], Label: "Button 5 + Right + Middle"},
        {ID: "5LRM", Kind: "Chord", Mask: 2, Trigger: "LRM", Buttons: ["LButton", "RButton", "MButton"], Label: "Button 5 + Left + Right + Middle"},
        {ID: "45LR", Kind: "Chord", Mask: 3, Trigger: "LR", Buttons: ["LButton", "RButton"], Label: "Buttons 4 + 5 + Left + Right"},
        {ID: "45LM", Kind: "Chord", Mask: 3, Trigger: "LM", Buttons: ["LButton", "MButton"], Label: "Buttons 4 + 5 + Left + Middle"},
        {ID: "45RM", Kind: "Chord", Mask: 3, Trigger: "RM", Buttons: ["RButton", "MButton"], Label: "Buttons 4 + 5 + Right + Middle"},
        {ID: "45LRM", Kind: "Chord", Mask: 3, Trigger: "LRM", Buttons: ["LButton", "RButton", "MButton"], Label: "Buttons 4 + 5 + Left + Right + Middle"},
        {ID: "4DL", Kind: "Double", Mask: 1, Trigger: "DL", Buttons: ["LButton"], Label: "Button 4 + Double Left"},
        {ID: "4DR", Kind: "Double", Mask: 1, Trigger: "DR", Buttons: ["RButton"], Label: "Button 4 + Double Right"},
        {ID: "5DL", Kind: "Double", Mask: 2, Trigger: "DL", Buttons: ["LButton"], Label: "Button 5 + Double Left"},
        {ID: "5DR", Kind: "Double", Mask: 2, Trigger: "DR", Buttons: ["RButton"], Label: "Button 5 + Double Right"}]
    static IDs := MacroModel.ChordValues("ID")
    static Labels := MacroModel.ChordValues("Label")

    static ChordValues(property) {
        values := []
        for , chord in this.Chords
            values.Push(chord.%property%)
        return values
    }

    static Chord(id) {
        for , chord in this.Chords
            if chord.ID == id
                return chord
        return 0
    }

    static ChordID(mask, trigger) {
        aliases := Map("lbutton", "L", "rbutton", "R", "mbutton", "M")
        trigger := aliases.Has(StrLower(trigger)) ? aliases[StrLower(trigger)] : StrUpper(trigger)
        for , chord in this.Chords
            if chord.Mask = mask && chord.Trigger == trigger
                return chord.ID
        return ""
    }

    static PrimaryTrigger(primaryMap) {
        trigger := ""
        for , button in ["LButton", "RButton", "MButton"]
            if primaryMap.Has(button) && primaryMap[button]
                trigger .= SubStr(button, 1, 1)
        return trigger
    }

    static Parse(source) {
        steps := []
        totalDelay := 0
        if StrLen(source) > 16000
            throw ValueError("A macro can contain at most 16,000 characters.")
        for lineNumber, raw in StrSplit(StrReplace(source, "`r"), "`n") {
            line := Trim(raw)
            if line = "" || SubStr(line, 1, 1) = ";"
                continue
            if !RegExMatch(line, "i)^(key|delay|text)\s+(.+)$", &m)
                throw ValueError("Line " lineNumber ": use key, delay, or text followed by a value.")
            kind := StrLower(m[1])
            value := m[2]
            if kind = "key" {
                try value := this.Key(value)
                catch Error as err
                    throw ValueError("Line " lineNumber ": " err.Message)
            } else if kind = "delay" {
                if !RegExMatch(value, "^\d+$") || Integer(value) > 60000
                    throw ValueError("Line " lineNumber ": delay must be 0 to 60,000 milliseconds.")
                value := Integer(value)
                totalDelay += value
                if totalDelay > 300000
                    throw ValueError("Total delays cannot exceed five minutes.")
            } else if StrLen(value) > 1000
                throw ValueError("Line " lineNumber ": text is limited to 1,000 characters per step.")
            steps.Push({Kind: kind, Value: value})
            if steps.Length > 200
                throw ValueError("A macro can contain at most 200 steps.")
        }
        return steps
    }

    static Key(value) {
        modifiers := Map("ctrl", "^", "control", "^", "alt", "!", "shift", "+", "win", "#")
        aliases := Map("escape", "Esc", "return", "Enter", "plus", "+", "minus", "-",
            "comma", ",", "period", ".", "slash", "/", "backslash", "\", "semicolon", ";",
            "quote", "'", "leftbracket", "[", "rightbracket", "]", "backtick", Chr(96),
            "equal", "=", "space", "Space", "win", "LWin", "alt", "LAlt",
            "ctrl", "LControl", "control", "LControl", "shift", "LShift",
            "lwin", "LWin", "rwin", "RWin", "lalt", "LAlt", "ralt", "RAlt",
            "lctrl", "LControl", "lcontrol", "LControl", "rctrl", "RControl", "rcontrol", "RControl",
            "lshift", "LShift", "rshift", "RShift")
        parts := StrSplit(value, "+")
        prefix := ""
        seen := Map()
        loop parts.Length - 1 {
            part := StrLower(Trim(parts[A_Index]))
            if !modifiers.Has(part) || seen.Has(modifiers[part])
                throw ValueError("Use a key or shortcut such as F8, Ctrl+C, or Ctrl+Shift+S.")
            prefix .= modifiers[part]
            seen[modifiers[part]] := true
        }
        key := Trim(parts[parts.Length])
        lower := StrLower(key)
        if aliases.Has(lower)
            key := aliases[lower]
        else if !RegExMatch(key, "i)^(?:[a-z0-9]|F(?:[1-9]|1\d|2[0-4])|Enter|Tab|Esc|Space|Backspace|Delete|Insert|Home|End|PgUp|PgDn|Up|Down|Left|Right|CapsLock|NumLock|ScrollLock|PrintScreen|Pause|AppsKey|Numpad(?:[0-9]|Dot|Div|Mult|Add|Sub|Enter|Ins|End|Down|PgDn|Left|Clear|Right|Home|Up|PgUp|Del)|Volume_(?:Mute|Down|Up)|Media_(?:Next|Prev|Stop|Play_Pause)|Browser_(?:Back|Forward|Refresh|Stop|Search|Favorites|Home))$")
            throw ValueError("Unknown key '" key "'. Use a keyboard key; mouse buttons and raw Send syntax are not supported.")
        if StrLower(key) = "f12" && seen.Has("^") && seen.Has("!")
            throw ValueError("Ctrl+Alt+F12 is reserved for pause/resume.")
        if RegExMatch(key, "^[A-Za-z]$")
            key := StrLower(key)
        ; One-shot playback uses a complete tap; HoldKeys decomposes a hold binding.
        return prefix "{" key "}"
    }

    static Action(mapping) {
        value := mapping.HasOwnProp("Action") ? mapping.Action : "Macro"
        if !(value == "Macro" || value == "MoveWindow" || value == "ResizeWindow" || value == "ToggleTopmost")
            throw ValueError("Mapping action must be Macro, MoveWindow, ResizeWindow, or ToggleTopmost.")
        return value
    }

    static Assigned(mapping) => this.Action(mapping) != "Macro" || mapping.Steps.Length > 0

    static MappingSteps(source, action) {
        action := this.Action({Action: action})
        return action = "Macro" ? this.Parse(source) : []
    }

    static ValidateMapping(mapping) {
        action := this.Action(mapping)
        this.Timing(mapping)
        hold := this.IsHold(mapping)
        steps := this.MappingSteps(mapping.Source, action)
        if action = "Macro"
            this.ValidateBinding(steps, hold)
        return steps
    }

    static Timing(mapping) {
        value := mapping.HasOwnProp("Timing") ? mapping.Timing : "Press"
        if !(value == "Press" || value == "Release")
            throw ValueError("Trigger timing must be Press or Release.")
        return value
    }

    static IsHold(mapping) {
        value := mapping.HasOwnProp("Hold") ? mapping.Hold : false
        if !(value == 0 || value == 1)
            throw ValueError("Hold must be enabled or disabled.")
        return value = 1
    }

    static ValidateBinding(steps, hold) {
        if hold
            this.HoldKeys(steps)
        return true
    }

    static HoldKeys(steps) {
        if steps.Length != 1 || steps[1].Kind != "key"
            throw ValueError("Hold requires exactly one key or shortcut command. Text, delay, and multiple commands cannot be held.")
        if !RegExMatch(steps[1].Value, "^([\^!+#]*)\{([^{}]+)\}$", &binding)
            throw ValueError("Invalid key command for Hold.")
        key := binding[2]
        ; A symbol can require implicit modifiers which depend on the keyboard
        ; layout. Require explicit named keys rather than silently hold a wrong key.
        if RegExMatch(key, "^[^A-Za-z0-9_]$")
            throw ValueError("Hold does not support punctuation or symbol keys. Use a letter, digit, or named key with explicit modifiers.")
        keys := []
        seen := Map()
        for , modifier in [["^", "LControl"], ["!", "LAlt"], ["+", "LShift"], ["#", "LWin"]] {
            if InStr(binding[1], modifier[1]) {
                canonical := this.HoldKeyIdentity(modifier[2])
                keys.Push(canonical)
                seen[canonical] := true
            }
        }
        canonical := this.HoldKeyIdentity(key)
        if !seen.Has(canonical)
            keys.Push(canonical)
        return keys
    }

    static HoldKeyIdentity(key) {
        vk := GetKeyVK(key)
        sc := GetKeySC(key)
        if !vk && !sc
            throw ValueError("This keyboard key cannot be held.")
        ; Scan-code identity keeps aliases on one physical key reference-counted
        ; together and distinguishes extended keys such as NumpadEnter.
        return sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
    }

    static Summary(source) {
        for , line in StrSplit(StrReplace(source, "`r"), "`n") {
            line := Trim(line)
            if line != "" && SubStr(line, 1, 1) != ";"
                return StrLen(line) > 52 ? SubStr(line, 1, 49) "..." : line
        }
        return "Unassigned - normal click"
    }
}

class MapperSettings {
    __New(path) {
        this.Path := path
        this.Preserve := true
        this.Paused := true
        this.ChordDelayMs := 200
        this.OverlayColor := "FFFFFF"
        this.OverlayTransparency := 60
        this.PinOutlineEnabled := true
        this.PinOutlineColor := "0078D4"
        this.PinOutlineThickness := 3
        this.View := "Mouse"
        this.Selected := "4L"
        this.CycleShortcut := ""
        this.ActiveProfileID := "default"
        this.Profiles := [{ID: "default", Name: "Default", Mappings: this.NewMappings()}]
        this.Mappings := this.Profiles[1].Mappings
        this.LoadError := ""
        if FileExist(path) {
            try this.Load()
            catch Error as err {
                this.Paused := true
                this.LoadError := err.Message
            }
        }
    }

    NewMappings() {
        mappings := Map()
        for , id in MacroModel.IDs
            mappings[id] := {Name: "", Source: "", Steps: [], Timing: "Press", Hold: false, Action: "Macro"}
        return mappings
    }

    FindProfile(id) {
        for , profile in this.Profiles
            if profile.ID == id
                return profile
        throw ValueError("Unknown profile.")
    }

    ActiveProfile() => this.FindProfile(this.ActiveProfileID)

    SelectProfile(id) {
        profile := this.FindProfile(id)
        this.ActiveProfileID := profile.ID
        this.Mappings := profile.Mappings
        return profile
    }

    CreateProfile(name, duplicateID := "") {
        name := this.ValidateProfileName(name)
        mappings := this.NewMappings()
        if duplicateID != "" {
            source := this.FindProfile(duplicateID).Mappings
            for , chordID in MacroModel.IDs {
                original := source[chordID]
                mapping := {Name: original.Name, Source: original.Source, Action: MacroModel.Action(original),
                    Timing: MacroModel.Timing(original), Hold: MacroModel.IsHold(original)}
                mapping.Steps := MacroModel.ValidateMapping(mapping)
                mappings[chordID] := mapping
            }
        }
        loop {
            id := "profile-" Format("{:08x}-{:08x}", A_TickCount, Random(0, 0x7FFFFFFF))
            duplicate := false
            for , profile in this.Profiles
                if profile.ID == id
                    duplicate := true
            if !duplicate
                break
        }
        this.Profiles.Push({ID: id, Name: name, Mappings: mappings})
        return id
    }

    RenameProfile(id, name) {
        profile := this.FindProfile(id)
        profile.Name := this.ValidateProfileName(name, id)
    }

    DeleteProfile(id) {
        this.FindProfile(id)
        if this.Profiles.Length = 1
            throw ValueError("The last profile cannot be deleted.")
        for index, profile in this.Profiles {
            if profile.ID != id
                continue
            this.Profiles.RemoveAt(index)
            if this.ActiveProfileID == id
                this.SelectProfile(this.Profiles[index <= this.Profiles.Length ? index : 1].ID)
            return
        }
    }

    ValidateProfileName(name, exceptID := "") {
        name := Trim(name)
        if name = "" || StrLen(name) > 80
            throw ValueError("Profile names must contain 1 to 80 characters.")
        for , profile in this.Profiles
            if profile.ID != exceptID && StrLower(profile.Name) = StrLower(name)
                throw ValueError("A profile with that name already exists.")
        return name
    }

    ValidateProfiles(profiles, activeID) {
        if !profiles.Length
            throw ValueError("At least one profile is required.")
        ids := Map()
        names := Map()
        activeFound := false
        for , profile in profiles {
            if !RegExMatch(profile.ID, "^[a-z0-9][a-z0-9_-]{0,63}$") || ids.Has(profile.ID)
                throw ValueError("Invalid or duplicate profile identifier.")
            ids[profile.ID] := true
            name := Trim(profile.Name)
            if name = "" || StrLen(name) > 80 || names.Has(StrLower(name))
                throw ValueError("Invalid or duplicate profile name.")
            names[StrLower(name)] := true
            if profile.ID == activeID
                activeFound := true
        }
        if !activeFound
            throw ValueError("The active profile does not exist.")
    }

    ValidateCycleShortcut(value) {
        if StrLen(value) > 80 || InStr(value, "`r") || InStr(value, "`n")
            throw ValueError("The profile-cycle shortcut must be one line of at most 80 characters.")
        return value
    }

    Load() {
        data := this.ReadIni()
        version := this.ReadValue(data, "Settings", "Version", "")
        if !(version == "1" || version == "2" || version == "3" || version == "4" || version == "5" || version == "6")
            throw ValueError("Unsupported or missing settings version. Original file has been preserved.")
        preserve := this.ReadValue(data, "Settings", "Preserve", "1")
        paused := this.ReadValue(data, "Settings", "Paused", "1")
        chordDelay := this.ValidateChordDelay(this.ReadValue(data, "Settings", "ChordDelayMs", "200"))
        overlayColor := this.ValidateColor(this.ReadValue(data, "Settings", "OverlayColor", "FFFFFF"))
        overlayTransparency := this.ValidateOverlayTransparency(this.ReadValue(data, "Settings", "OverlayTransparency", "60"))
        pinEnabled := this.ReadValue(data, "Settings", "PinOutlineEnabled", "1")
        if !RegExMatch(pinEnabled, "^[01]$")
            throw ValueError("The pin outline enabled setting must be 0 or 1.")
        pinColor := this.ValidateColor(this.ReadValue(data, "Settings", "PinOutlineColor", "0078D4"), "Pin outline")
        pinThickness := this.ValidatePinOutlineThickness(this.ReadValue(data, "Settings", "PinOutlineThickness", "3"))
        view := this.ReadValue(data, "Settings", "View", "Mouse")
        selected := this.ReadValue(data, "Settings", "Selected", "4L")
        if !RegExMatch(preserve, "^[01]$") || !RegExMatch(paused, "^[01]$")
            throw ValueError("Invalid saved preference. Original file has been preserved.")
        this.ValidateNavigation(view, selected)
        profiles := []
        if Integer(version) < 4 {
            profiles.Push({ID: "default", Name: "Default", Mappings: this.ReadMappings(data)})
            activeID := "default"
            cycleShortcut := ""
        } else {
            order := this.ReadValue(data, "Settings", "ProfileOrder", "")
            for , id in StrSplit(order, ",") {
                if !RegExMatch(id, "^[a-z0-9][a-z0-9_-]{0,63}$")
                    throw ValueError("Invalid saved profile order.")
                name := Trim(this.Decode(this.ReadValue(data, "Profile:" id, "Name", "")))
                profiles.Push({ID: id, Name: name, Mappings: this.ReadMappings(data, "Profile:" id ":")})
            }
            activeID := this.ReadValue(data, "Settings", "ActiveProfile", "")
            cycleShortcut := this.ValidateCycleShortcut(this.Decode(this.ReadValue(data, "Settings", "CycleShortcut", "")))
        }
        this.ValidateProfiles(profiles, activeID)
        this.Profiles := profiles
        this.SelectProfile(activeID)
        this.CycleShortcut := cycleShortcut
        this.Preserve := Integer(preserve)
        this.Paused := Integer(paused)
        this.ChordDelayMs := chordDelay
        this.OverlayColor := overlayColor
        this.OverlayTransparency := overlayTransparency
        this.PinOutlineEnabled := Integer(pinEnabled)
        this.PinOutlineColor := pinColor
        this.PinOutlineThickness := pinThickness
        this.View := view
        this.Selected := selected
    }

    ReadMappings(data, prefix := "") {
        loaded := Map()
        for , id in MacroModel.IDs {
            section := prefix id
            name := this.Decode(this.ReadValue(data, section, "Name", ""))
            source := this.Decode(this.ReadValue(data, section, "Macro", ""))
            action := this.ReadValue(data, section, "Action", "Macro")
            timing := this.ReadValue(data, section, "Timing", "Press")
            hold := this.ReadValue(data, section, "Hold", "0")
            if !RegExMatch(hold, "^[01]$")
                throw ValueError("Invalid Hold setting for " id ". Original file has been preserved.")
            mapping := {Name: name, Source: source, Action: action, Timing: timing, Hold: Integer(hold)}
            mapping.Steps := MacroModel.ValidateMapping(mapping)
            loaded[id] := mapping
        }
        return loaded
    }

    ReadIni() {
        ; Win32 profile APIs can silently truncate values above 64 KiB. A valid
        ; 16,000-character Unicode macro can exceed that once encoded as hex.
        if FileGetSize(this.Path) > 4 * 1024 * 1024
            throw ValueError("Settings exceed the 4 MiB limit. Original file has been preserved.")
        content := FileRead(this.Path, "UTF-8")
        if SubStr(content, 1, 1) = Chr(0xFEFF)
            content := SubStr(content, 2)
        sections := Map()
        sections.CaseSense := "Off"
        current := ""
        for lineNumber, raw in StrSplit(content, "`n") {
            line := Trim(raw, " `t`r")
            if line = "" || SubStr(line, 1, 1) = ";"
                continue
            if StrLen(line) > 128010 || InStr(line, "`r")
                throw ValueError("Invalid settings line " lineNumber ". Original file has been preserved.")
            if SubStr(line, 1, 1) = "[" {
                if !RegExMatch(line, "^\[([^\[\]]+)\]$", &sectionMatch)
                    throw ValueError("Malformed settings section on line " lineNumber ". Original file has been preserved.")
                section := Trim(sectionMatch[1])
                if section = "" || sections.Has(section)
                    throw ValueError("Empty or duplicate settings section on line " lineNumber ". Original file has been preserved.")
                current := Map()
                current.CaseSense := "Off"
                sections[section] := current
            } else {
                if !IsObject(current) || !RegExMatch(line, "^([A-Za-z][A-Za-z0-9_]*)\s*=(.*)$", &entry)
                    throw ValueError("Malformed settings entry on line " lineNumber ". Original file has been preserved.")
                key := entry[1]
                if current.Has(key)
                    throw ValueError("Duplicate settings key on line " lineNumber ". Original file has been preserved.")
                current[key] := Trim(entry[2])
            }
        }
        return sections
    }

    ReadValue(data, section, key, fallback) => data.Has(section) && data[section].Has(key) ? data[section][key] : fallback

    ValidateNavigation(view, selected) {
        if !(view == "Mouse" || view == "List")
            throw ValueError("Invalid saved view. Original file has been preserved.")
        for , id in MacroModel.IDs
            if selected == id
                return
        throw ValueError("Invalid selected mapping. Original file has been preserved.")
    }

    ValidateChordDelay(value) {
        if !RegExMatch(value, "^\d+$") || Integer(value) > 1000
            throw ValueError("Chord delay must be a whole number from 0 to 1000 milliseconds.")
        return Integer(value)
    }

    ValidateColor(value, label := "Overlay") {
        if !RegExMatch(value, "i)^[0-9a-f]{6}$")
            throw ValueError(label " color must contain six hexadecimal digits.")
        return StrUpper(value)
    }

    ValidateOverlayTransparency(value) {
        if !RegExMatch(value, "^\d+$") || Integer(value) > 100
            throw ValueError("Overlay transparency must be a whole number from 0 to 100.")
        return Integer(value)
    }

    ValidatePinOutlineThickness(value) {
        if !RegExMatch(value, "^\d+$") || Integer(value) < 1 || Integer(value) > 12
            throw ValueError("Pin outline thickness must be a whole number from 1 to 12 pixels.")
        return Integer(value)
    }

    Save() {
        if this.LoadError != ""
            throw ValueError("Settings could not be loaded. Fix or rename mappings.ini, then restart. " this.LoadError)
        this.ValidateNavigation(this.View, this.Selected)
        chordDelay := this.ValidateChordDelay(this.ChordDelayMs)
        overlayColor := this.ValidateColor(this.OverlayColor)
        overlayTransparency := this.ValidateOverlayTransparency(this.OverlayTransparency)
        if !(this.PinOutlineEnabled == 0 || this.PinOutlineEnabled == 1)
            throw ValueError("The pin outline enabled setting must be 0 or 1.")
        pinColor := this.ValidateColor(this.PinOutlineColor, "Pin outline")
        pinThickness := this.ValidatePinOutlineThickness(this.PinOutlineThickness)
        cycleShortcut := this.ValidateCycleShortcut(this.CycleShortcut)
        this.ValidateProfiles(this.Profiles, this.ActiveProfileID)
        profileFeature := this.Profiles.Length != 1 || this.Profiles[1].ID != "default"
            || !(this.Profiles[1].Name == "Default") || cycleShortcut != ""
        version := profileFeature ? 4 : 1
        profileOrder := ""
        profileContent := ""
        legacyContent := ""
        for , profile in this.Profiles {
            profileOrder .= (profileOrder = "" ? "" : ",") profile.ID
            profileContent .= "`r`n[Profile:" profile.ID "]`r`nName=" this.Encode(profile.Name) "`r`n"
            for , id in MacroModel.IDs {
                mapping := profile.Mappings[id]
                action := MacroModel.Action(mapping)
                timing := MacroModel.Timing(mapping)
                hold := MacroModel.IsHold(mapping)
                steps := MacroModel.ValidateMapping(mapping)
                chord := MacroModel.Chord(id)
                assigned := action != "Macro" || steps.Length
                if action = "ToggleTopmost"
                    version := 6
                else if chord.Kind = "Double" && assigned
                    version := Max(version, 5)
                else if chord.Buttons.Length > 1 && assigned
                    version := Max(version, 3)
                else if action != "Macro"
                    version := Max(version, 2)
                fields := "Name=" this.Encode(mapping.Name) "`r`nMacro=" this.Encode(mapping.Source) "`r`n"
                    . "Timing=" timing "`r`nHold=" Integer(hold) "`r`nAction=" action "`r`n"
                profileContent .= "`r`n[Profile:" profile.ID ":" id "]`r`n" fields
                if this.Profiles.Length = 1
                    legacyContent .= "`r`n[" id "]`r`n" fields
            }
        }
        content := "[Settings]`r`nVersion=" version "`r`nPreserve=" Integer(this.Preserve) "`r`nPaused=" Integer(this.Paused) "`r`n"
            . "View=" this.View "`r`nSelected=" this.Selected "`r`nChordDelayMs=" chordDelay "`r`n"
            . "OverlayColor=" overlayColor "`r`nOverlayTransparency=" overlayTransparency "`r`n"
            . "PinOutlineEnabled=" Integer(this.PinOutlineEnabled) "`r`nPinOutlineColor=" pinColor "`r`nPinOutlineThickness=" pinThickness "`r`n"
        content .= version >= 4
            ? "ProfileOrder=" profileOrder "`r`nActiveProfile=" this.ActiveProfileID "`r`nCycleShortcut=" this.Encode(cycleShortcut) "`r`n" profileContent
            : legacyContent
        if StrPut(content, "UTF-8") - 1 > 4 * 1024 * 1024
            throw ValueError("Settings exceed the 4 MiB limit. The previous file has been preserved.")
        temp := this.Path "." ProcessExist() ".tmp"
        try {
            stream := FileOpen(temp, "w", "UTF-8-RAW")
            stream.Write(content)
            DllCall("FlushFileBuffers", "Ptr", stream.Handle)
            stream.Close()
            if !DllCall("MoveFileExW", "Str", temp, "Str", this.Path, "UInt", 0x9)
                throw OSError()
        } finally {
            if FileExist(temp)
                FileDelete(temp)
        }
    }

    static Encode(value) {
        buf := Buffer(StrPut(value, "UTF-8"))
        len := StrPut(value, buf, "UTF-8") - 1
        encoded := ""
        loop len
            encoded .= Format("{:02X}", NumGet(buf, A_Index - 1, "UChar"))
        return encoded
    }

    static Decode(value) {
        if value = ""
            return ""
        if Mod(StrLen(value), 2) || !RegExMatch(value, "^[0-9A-Fa-f]+$") || StrLen(value) > 128000
            throw ValueError("Invalid encoded mapping. Original file has been preserved.")
        buf := Buffer(StrLen(value) // 2 + 1, 0)
        loop StrLen(value) // 2
            NumPut("UChar", Integer("0x" SubStr(value, A_Index * 2 - 1, 2)), buf, A_Index - 1)
        decoded := StrGet(buf, "UTF-8")
        if StrLower(this.Encode(decoded)) != StrLower(value)
            throw ValueError("Invalid UTF-8 or embedded NUL in saved mapping. Original file has been preserved.")
        return decoded
    }

    Encode(value) => MapperSettings.Encode(value)
    Decode(value) => MapperSettings.Decode(value)
}
