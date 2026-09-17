; Records only a trigger. Mouse ownership remains in ChordState.
; No input, windows, timers, settings, or callbacks are used by this model.
class CombinationCapture {
    __New(upgradeCandidates := unset) {
        this.Phase := "Idle"
        this.Result := 0
        this.Reason := ""
        this.Deadline := 0
        this.Frozen := false
        this.DoubleCandidate := 0
        this.UpgradeCandidates := IsSet(upgradeCandidates) ? upgradeCandidates : []
        if !IsSet(upgradeCandidates) {
            for , mask in [1, 2, 3] {
                for , trigger in ["LR", "LM", "RM", "LRM"]
                    this.UpgradeCandidates.Push({Mask: mask, Trigger: trigger, Buttons: this.ButtonsForTrigger(trigger)})
            }
        }
    }

    Active => this.Phase != "Idle"

    Begin(allReleased, now, timeout := 15000) {
        this.Phase := allReleased ? "Listening" : "Arming"
        this.Result := 0
        this.Reason := ""
        this.Deadline := now + timeout
        this.Frozen := false
        this.DoubleCandidate := 0
    }

    ShouldBlockPrimary(alreadyDown, anySide) {
        ; Runtime exempts only its own Cancel control. Sides are not required
        ; for suppression; existing presses keep their original UP ownership.
        return this.Active && !alreadyDown
    }

    ObservePrimary(mask, button, fresh, primaryMap := unset, now := unset, delayMs := 200) {
        if !fresh
            return false
        if this.Phase = "Matched" && IsObject(this.DoubleCandidate) {
            candidate := this.DoubleCandidate
            if !IsSet(now) || delayMs <= 0 || mask != candidate.Mask || button != candidate.Button
                || now < candidate.FirstDown || now >= candidate.Deadline
                || (IsSet(primaryMap) && !this.IsOnlyPrimary(primaryMap, button)) {
                this.DoubleCandidate := 0
            } else if candidate.Released {
                this.Result.Trigger := "D" SubStr(button, 1, 1)
                this.Frozen := true
                this.DoubleCandidate := 0
                return true
            }
        }
        if mask < 1 || mask > 3
            return false
        if button != "LButton" && button != "RButton" && button != "MButton"
            return false
        if this.Phase = "Listening" {
            this.Result := {Mask: mask, Button: button, Trigger: SubStr(button, 1, 1)}
            this.Phase := "Matched"
            if IsSet(now) && delayMs > 0 && (mask = 1 || mask = 2)
                && (button = "LButton" || button = "RButton")
                && (!IsSet(primaryMap) || this.IsOnlyPrimary(primaryMap, button))
                this.DoubleCandidate := {Mask: mask, Button: button, FirstDown: now, Deadline: now + delayMs, Released: false}
            return true
        }
        if this.Phase != "Matched" || this.Frozen || !IsSet(primaryMap) || mask != this.Result.Mask
            return false
        ; The caller supplies state AFTER the fresh DOWN. Only simultaneous,
        ; exact candidate primaries can strictly extend the tentative result.
        currentButtons := this.ButtonsForTrigger(this.Result.Trigger)
        if this.ContainsButton(currentButtons, button)
            return false
        for , candidate in this.UpgradeCandidates {
            if candidate.Mask != mask || candidate.Buttons.Length <= currentButtons.Length
                continue
            if !this.ContainsButton(candidate.Buttons, button)
                continue
            matches := true
            for , current in currentButtons {
                if !this.ContainsButton(candidate.Buttons, current) {
                    matches := false
                    break
                }
            }
            if !matches
                continue
            for , primary in ["LButton", "RButton", "MButton"] {
                held := primaryMap.Has(primary) && primaryMap[primary]
                if !!held != this.ContainsButton(candidate.Buttons, primary) {
                    matches := false
                    break
                }
            }
            if matches {
                this.Result.Trigger := candidate.Trigger
                this.DoubleCandidate := 0
                return true
            }
        }
        return false
    }

    ObserveUp(buttonOrSide) {
        if this.Phase != "Matched"
            return false
        ; A singleton's first UP ends chord growth but may complete the first
        ; click of a double. Any side release ends continuous-side eligibility.
        if IsObject(this.DoubleCandidate) {
            if buttonOrSide = 4 || buttonOrSide = 5 || buttonOrSide = "XButton1" || buttonOrSide = "XButton2"
                this.DoubleCandidate := 0
            else if buttonOrSide = this.DoubleCandidate.Button
                this.DoubleCandidate.Released := true
        }
        if this.Frozen
            return false
        required := this.ContainsButton(this.ButtonsForTrigger(this.Result.Trigger), buttonOrSide)
        if (buttonOrSide = 4 || buttonOrSide = "XButton1") && (this.Result.Mask & 1)
            required := true
        if (buttonOrSide = 5 || buttonOrSide = "XButton2") && (this.Result.Mask & 2)
            required := true
        if required
            this.Frozen := true
        return required
    }

    ContainsButton(buttons, button) {
        for , item in buttons {
            if item = button
                return true
        }
        return false
    }

    IsOnlyPrimary(primaryMap, button) {
        for , primary in ["LButton", "RButton", "MButton"] {
            held := primaryMap.Has(primary) && primaryMap[primary]
            if !!held != (primary = button)
                return false
        }
        return true
    }

    ButtonsForTrigger(trigger) {
        buttons := []
        for , button in ["LButton", "RButton", "MButton"] {
            if InStr(trigger, SubStr(button, 1, 1))
                buttons.Push(button)
        }
        return buttons
    }

    Cancel(reason := "Recording cancelled.") {
        if !this.Active
            return
        this.Result := 0
        this.DoubleCandidate := 0
        this.Reason := reason
        this.Phase := "Draining"
    }

    Advance(allReleased, now) {
        if !this.Active
            return 0
        if IsObject(this.DoubleCandidate) && now >= this.DoubleCandidate.Deadline
            this.DoubleCandidate := 0
        if now >= this.Deadline && this.Phase != "Draining"
            this.Cancel("Recording timed out.")
        if !allReleased
            return 0
        if this.Phase = "Arming" {
            this.Phase := "Listening"
            return 0
        }
        if this.Phase = "Matched" {
            result := this.Result
            this.Result := 0
            this.DoubleCandidate := 0
            this.Phase := "Idle"
            return {Kind: "Selected", Mask: result.Mask, Button: result.Button, Trigger: result.Trigger}
        }
        if this.Phase = "Draining" {
            this.Phase := "Idle"
            return {Kind: "Cancelled", Reason: this.Reason}
        }
        return 0
    }

    ; Paused mappings deliberately report Mask=0. Capture has its own mask path,
    ; but still requires observed, intercepted downs from the current generation.
    static HeldMask(state) {
        mask := 0
        for id, side in state.Sides {
            if !side.Down
                continue
            if !side.Captured || side.Epoch != state.Epoch
                return 0
            mask |= id = 4 ? 1 : 2
        }
        return mask
    }
}
