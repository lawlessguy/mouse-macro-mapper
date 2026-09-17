#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/ProfileCycleHotkey.ahk

; All registration, physical input reads and callback level changes are mocked.
; The native adapter is never instantiated or called by this test.
global ProfileCycleChecks := 0, ProfileCycleFailures := []
ProfileCycleTest("unset default and normalized keyboard grammar", TestProfileCycleGrammar)
ProfileCycleTest("reserved and invalid shortcuts leave registration unchanged", TestProfileCycleInvalid)
ProfileCycleTest("one physical activation per held key and ignored synthetic input", TestProfileCyclePresses)
ProfileCycleTest("replacement registration errors roll back working shortcut", TestProfileCycleRollback)
ProfileCycleTest("held-key replacement and stale callbacks are inert", TestProfileCycleReplacement)
ProfileCycleTest("clear dispose and callback failures preserve ownership and levels", TestProfileCycleCleanup)
FileAppend("Assertions: " ProfileCycleChecks "`n", "*")
for , profileCycleFailure in ProfileCycleFailures
    FileAppend("FAIL: " profileCycleFailure "`n", "*")
FileAppend(ProfileCycleFailures.Length ? "RESULT: FAIL`n" : "RESULT: PASS`n", "*")
ExitApp(ProfileCycleFailures.Length ? 1 : 0)

ProfileCycleTest(label, callback) {
    global ProfileCycleFailures
    try {
        callback.Call()
        FileAppend("PASS: " label "`n", "*")
    } catch Error as err {
        ProfileCycleFailures.Push(label ": " err.Message " (line " err.Line ")")
    }
}

ProfileCycleCheck(condition, message) {
    global ProfileCycleChecks
    ProfileCycleChecks += 1
    if !condition
        throw Error(message)
}

ProfileCycleThrows(callback, part) {
    caught := ""
    try callback.Call()
    catch Error as err
        caught := err.Message
    ProfileCycleCheck(part = "" ? caught != "" : InStr(caught, part), "Expected error containing '" part "', got '" caught "'")
}

class ProfileCycleSpy {
    __New() {
        this.Registered := [], this.Physical := Map()
        this.FailOnce := ""
        this.Count := 0, this.Level := 7, this.CallbackLevel := -1
        this.Service := ProfileCycleHotkey(ObjBindMethod(this, "Cycle"), this)
    }
    Cycle() {
        this.Count += 1
        this.CallbackLevel := this.Level
        this.Fail("callback")
    }
    Fail(operation) {
        if this.FailOnce = operation {
            this.FailOnce := ""
            throw Error(operation " failed")
        }
    }
    Register(spec, downCallback, upCallback) {
        this.Fail("register")
        registration := {Spec: spec, Down: downCallback, Up: upCallback, Enabled: false}
        this.Registered.Push(registration)
        return registration
    }
    Enable(registration) {
        registration.Enabled := true
        this.Fail("enable")
    }
    Disable(registration) {
        registration.Enabled := false
        this.Fail("disable")
    }
    Dispose(registration) => this.Disable(registration)
    PhysicalKey(key) => this.Physical.Has(key) && this.Physical[key]
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
        saved := this.Level
        try {
            this.Level := 0
            callback.Call()
        } finally {
            this.Level := saved
        }
    }
}

TestProfileCycleGrammar() {
    spy := ProfileCycleSpy()
    ProfileCycleCheck(spy.Service.Shortcut = "" && !spy.Registered.Length, "Constructor registers no surprise shortcut")
    ProfileCycleCheck(spy.Service.Configure("  ") = "" && !spy.Registered.Length, "Blank configuration stays unregistered")
    ProfileCycleCheck(spy.Service.Configure(" alt + CONTROL + f10 ") = "Ctrl+Alt+F10", "Modifiers and aliases normalize")
    spec := spy.Registered[1].Spec
    ProfileCycleCheck(spec.Down = "$^!F10" && spec.Up = "~*$F10 Up", "Hook DOWN and pass-through wildcard base UP")
    ProfileCycleCheck(spec.InputLevel = 1, "Mapper SendLevel0 and1 events excluded by input level")
    spy.Service.Configure("Control+Alt+F10")
    ProfileCycleCheck(spy.Registered.Length = 1, "Equivalent settings do not register again")
    for , text in ["Win+Shift+a", "F24", "Ctrl+9", "Alt+PageDown", "Shift+Space", "Ctrl+Return"] {
        parsed := ProfileCycleHotkey.Parse(text)
        ProfileCycleCheck(parsed.Key != "" && parsed.InputLevel = 1, "Supported keyboard grammar parses")
    }
    ProfileCycleCheck(ProfileCycleHotkey.Parse("Win+Shift+a").Shortcut = "Shift+Win+A", "Stable modifier order")
}

TestProfileCycleInvalid() {
    spy := ProfileCycleSpy(), spy.Service.Configure("Ctrl+Alt+F10")
    original := spy.Registered[1]
    for , text in ["Esc", "Ctrl+Escape", "Alt+Control+F12", "Ctrl+Alt+Shift+F12", "Ctrl", "Ctrl+Ctrl+F10",
        "Ctrl+LButton", "XButton1", "F25", "Ctrl+", "Ctrl++A", "A+B", "$^F10"] {
        ProfileCycleThrows(ObjBindMethod(spy.Service, "Configure", text), "")
        ProfileCycleCheck(spy.Service.Shortcut = "Ctrl+Alt+F10" && original.Enabled
            && spy.Registered.Length = 1, "Invalid shortcut leaves old registration unchanged")
    }
}

TestProfileCyclePresses() {
    spy := ProfileCycleSpy(), spy.Service.Configure("Ctrl+Alt+F10")
    registration := spy.Registered[1]
    registration.Down.Call()
    ProfileCycleCheck(spy.Count = 0, "Synthetic base input cannot cycle")
    spy.Physical["F10"] := true
    registration.Down.Call()
    ProfileCycleCheck(spy.Count = 0, "Synthetic modifiers cannot satisfy physical shortcut")
    spy.Physical["Ctrl"] := true, spy.Physical["Alt"] := true
    registration.Down.Call()
    registration.Down.Call()
    registration.Down.Call()
    ProfileCycleCheck(spy.Count = 1, "Auto-repeat cycles only once")
    registration.Up.Call()
    registration.Down.Call()
    ProfileCycleCheck(spy.Count = 1, "Synthetic UP while physical key is held cannot rearm")
    spy.Physical["F10"] := false
    registration.Up.Call()
    spy.Physical["F10"] := true
    registration.Down.Call()
    ProfileCycleCheck(spy.Count = 2, "Physical base UP rearms next press")
    ProfileCycleCheck(spy.CallbackLevel = 0 && spy.Level = 7, "Callback runs at level0 and restores prior level")
}

TestProfileCycleRollback() {
    for , failurePoint in ["register", "enable", "disable"] {
        spy := ProfileCycleSpy(), spy.Service.Configure("Ctrl+F9")
        original := spy.Registered[1]
        spy.FailOnce := failurePoint
        ProfileCycleThrows(ObjBindMethod(spy.Service, "Configure", "Alt+F10"), failurePoint " failed")
        ProfileCycleCheck(original.Enabled && spy.Service.Shortcut = "Ctrl+F9", "Old shortcut survives replacement failure")
        if spy.Registered.Length > 1
            ProfileCycleCheck(!spy.Registered[2].Enabled, "Failed replacement is disabled")
        spy.Physical["Ctrl"] := true, spy.Physical["F9"] := true
        original.Down.Call()
        ProfileCycleCheck(spy.Count = 1, "Preserved old shortcut still cycles")
    }
}

TestProfileCycleReplacement() {
    spy := ProfileCycleSpy(), spy.Service.Configure("Ctrl+F9")
    old := spy.Registered[1]
    spy.Physical["F10"] := true, spy.Physical["Alt"] := true
    spy.Service.Configure("Alt+F10")
    current := spy.Registered[2]
    current.Down.Call()
    ProfileCycleCheck(spy.Count = 0, "Configuring a held key waits for its physical release")
    spy.Physical["Ctrl"] := true, spy.Physical["F9"] := true
    old.Down.Call(), old.Up.Call()
    ProfileCycleCheck(spy.Count = 0 && !old.Enabled, "Stale callbacks and old registration are inert")
    spy.Physical["F10"] := false
    current.Up.Call()
    spy.Physical["F10"] := true
    current.Down.Call()
    ProfileCycleCheck(spy.Count = 1 && current.Enabled, "New shortcut activates after release")
}

TestProfileCycleCleanup() {
    spy := ProfileCycleSpy(), spy.Service.Configure("F9")
    registration := spy.Registered[1]
    spy.Physical["F9"] := true, spy.FailOnce := "callback"
    ProfileCycleThrows(registration.Down, "callback failed")
    registration.Down.Call()
    ProfileCycleCheck(spy.Count = 1 && spy.Level = 7, "Failed callback keeps press latch and restores send level")
    spy.FailOnce := "disable"
    ProfileCycleThrows(ObjBindMethod(spy.Service, "Clear"), "disable failed")
    ProfileCycleCheck(registration.Enabled && spy.Service.Shortcut = "F9", "Failed clear restores prior registration")
    spy.Service.Clear()
    registration.Down.Call()
    ProfileCycleCheck(spy.Service.Shortcut = "" && !registration.Enabled && spy.Count = 1, "Clear disables only owned shortcut")
    spy.Service.Configure("F10")
    spy.Service.Dispose()
    ProfileCycleCheck(spy.Service.Disposed && !spy.Registered[2].Enabled, "Dispose cleans current registration")
    ProfileCycleThrows(ObjBindMethod(spy.Service, "Configure", "F11"), "disposed")
}
