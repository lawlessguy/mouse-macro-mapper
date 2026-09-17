#Requires AutoHotkey v2.0

; Only held shortcuts use this sender. SendEvent above another script's
; InputLevel can activate its keyboard-hook hotkeys. Mouse replay and one-shot
; macros keep their own policy.
class MapperKeyOutput {
    static HeldSendLevel := 1
    static ControlInputLevel := 1

    ; Inject all effects for tests: no real keyboard events or level changes.
    __New(sendEventFn := unset, readLevelFn := unset, writeLevelFn := unset) {
        this.SendEventFn := IsSet(sendEventFn) ? sendEventFn : (keys) => SendEvent(keys)
        this.ReadLevelFn := IsSet(readLevelFn) ? readLevelFn : () => A_SendLevel
        this.WriteLevelFn := IsSet(writeLevelFn) ? writeLevelFn : (level) => SendLevel(level)
    }

    SendHeldKey(key, down) {
        previousLevel := this.ReadLevelFn.Call()
        try {
            this.WriteLevelFn.Call(MapperKeyOutput.HeldSendLevel)
            ; Blind preserves the modifier DOWNs owned by HeldKeyOutput; that
            ; model emits the base key UP before releasing its modifiers.
            this.SendEventFn.Call("{Blind}{" key (down ? " down}" : " up}"))
        } finally {
            ; Never leak our raised level into later output or cleanup.
            this.WriteLevelFn.Call(previousLevel)
        }
    }
}
