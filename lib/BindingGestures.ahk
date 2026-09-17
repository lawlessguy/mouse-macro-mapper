; Pure binding lifetimes. The caller owns mouse interception, eligibility, focus,
; and delivery of these actions. This class never sends input or evaluates UI.
class BindingGestures {
    __New() {
        this.Active := Map()
        this.Sequence := 0
    }

    Down(mask, primaryMap, mappings, changedButton := "", now := 0, delayMs := 200) {
        actions := []
        ; A side-mask change cancels timers and pending releases. Started output
        ; ends before any replacement binding is evaluated.
        for key, binding in this.Active.Clone() {
            if binding.Mask != mask {
                this.Active.Delete(key)
                this.Finish(binding, actions)
            }
        }
        if mask != 1 && mask != 2 && mask != 3
            return actions

        cancelledDoubles := []
        primaryCount := this.PrimaryCount(primaryMap)
        for key, binding in this.Active.Clone() {
            if !binding.DoublePending
                continue
            if primaryCount > 1 || (changedButton != "" && changedButton != binding.Button) || delayMs <= 0 {
                cancelledDoubles.Push({Key: key, Binding: binding})
            } else if binding.Released && changedButton = binding.Button && now < binding.Due {
                this.Active.Delete(key)
                binding.Pending := false
                binding.DoublePending := false
                this.Latch(binding.DoubleChord, binding.DoubleMapping,
                    binding.DoubleChord.ID, actions, now, 0)
            }
        }

        ; Resolve overdue starts even if timer delivery was late. A larger chord
        ; remains eligible after a smaller action has already fired.
        for , action in this.Advance(now)
            actions.Push(action)

        ; A double starts only with a fresh primary DOWN while the exact side
        ; mask is already held. The first candidate remains taggable in Active,
        ; even after its UP, until recognition succeeds or its deadline expires.
        if delayMs > 0 && primaryCount = 1 && (changedButton = "LButton" || changedButton = "RButton")
            && !this.Active.Has(changedButton) && !this.DoubleOwns(changedButton) {
            doubleChord := this.AssignedDouble(mask, changedButton, mappings)
            if IsObject(doubleChord) {
                singleID := MacroModel.ChordID(mask, changedButton)
                singleMapping := mappings.Has(singleID) ? mappings[singleID] : {Steps: []}
                this.Latch(MacroModel.Chord(singleID), singleMapping, changedButton, actions, now, delayMs)
                pending := this.Active[changedButton]
                pending.Pending := true
                pending.Due := now + delayMs
                pending.DoublePending := true
                pending.DoubleChord := doubleChord
                pending.DoubleMapping := mappings[doubleChord.ID]
            }
        }

        completed := []
        for , chord in MacroModel.Chords
            if chord.Kind = "Chord" && chord.Mask = mask && mappings.Has(chord.ID) && MacroModel.Assigned(mappings[chord.ID])
                && this.AllDown(chord.Buttons, primaryMap)
                completed.Push(chord)

        ; Resolve a cancelled first click before unrelated new actions, unless
        ; a completed larger chord will consume that deferred singleton.
        for , candidate in cancelledDoubles {
            if !this.Active.Has(candidate.Key) || this.Active[candidate.Key] != candidate.Binding
                continue
            binding := candidate.Binding
            if !binding.DoublePending
                continue
            consumed := false
            for , larger in completed
                if this.StrictSubset(binding.Buttons, larger.Buttons) {
                    consumed := true
                    break
                }
            if consumed
                continue
            binding.DoublePending := false
            if binding.Released {
                this.Active.Delete(candidate.Key)
                this.Finish(binding, actions, true)
            } else if !this.IsWindow(binding) && !this.IsKeyboardHold(binding) && binding.Timing = "Release"
                binding.Pending := false
            else if !this.HasAssignedSuperset(MacroModel.Chord(binding.ID), mappings)
                this.Start(binding, actions)
        }

        for , chord in completed {
            key := this.BindingKey(chord)
            if this.Active.Has(key) || (chord.Buttons.Length = 1 && this.DoubleOwns(chord.Buttons[1]))
                || (changedButton != "" && !this.Contains(chord.Buttons, changedButton))
                continue
            superseded := false
            for , larger in completed
                if this.StrictSubset(chord.Buttons, larger.Buttons) {
                    superseded := true
                    break
                }
            if superseded
                continue
            mapping := mappings[chord.ID]
            this.Supersede(chord, mapping, actions)
            delay := this.HasAssignedSuperset(chord, mappings) ? Max(0, delayMs) : 0
            this.Latch(chord, mapping, key, actions, now, delay)
        }
        return actions
    }

    BindingKey(chord) => chord.Kind = "Chord" && chord.Buttons.Length = 1 ? chord.Buttons[1] : chord.ID

    IsWindow(binding) => binding.Action = "MoveWindow" || binding.Action = "ResizeWindow"
    IsKeyboardHold(binding) => binding.Action = "Macro" && binding.Hold

    PrimaryCount(primaryMap) {
        count := 0
        for , button in ["LButton", "RButton", "MButton"]
            if primaryMap.Has(button) && primaryMap[button]
                count += 1
        return count
    }

    AssignedDouble(mask, button, mappings) {
        for , chord in MacroModel.Chords
            if chord.Kind = "Double" && chord.Mask = mask && chord.Buttons[1] = button
                && mappings.Has(chord.ID) && MacroModel.Assigned(mappings[chord.ID])
                return chord
        return 0
    }

    DoubleOwns(button) {
        for , binding in this.Active
            if binding.IsDouble && this.Contains(binding.Buttons, button)
                return true
        return false
    }

    Contains(buttons, button) {
        for , candidate in buttons
            if candidate = button
                return true
        return false
    }

    AllDown(buttons, primaryMap) {
        for , button in buttons
            if !primaryMap.Has(button) || !primaryMap[button]
                return false
        return true
    }

    StrictSubset(smaller, larger) {
        if smaller.Length >= larger.Length
            return false
        for , button in smaller
            if !this.Contains(larger, button)
                return false
        return true
    }

    HasAssignedSuperset(chord, mappings) {
        for , larger in MacroModel.Chords
            if larger.Kind = "Chord" && larger.Mask = chord.Mask && this.StrictSubset(chord.Buttons, larger.Buttons)
                && mappings.Has(larger.ID) && MacroModel.Assigned(mappings[larger.ID])
                return true
        return false
    }

    Supersede(chord, mapping, actions) {
        additiveHold := MacroModel.Action(mapping) = "Macro" && MacroModel.IsHold(mapping)
        for key, binding in this.Active.Clone() {
            if binding.Mask != chord.Mask || !this.StrictSubset(binding.Buttons, chord.Buttons)
                continue
            ; Already-fired Press bindings keep their completion latch. Started
            ; keyboard holds coexist only with another keyboard hold.
            if binding.Started && !this.IsWindow(binding)
                && ((!this.IsKeyboardHold(binding) && binding.Timing = "Press")
                    || (this.IsKeyboardHold(binding) && additiveHold))
                continue
            this.Active.Delete(key)
            this.Finish(binding, actions)
        }
    }

    Latch(chord, mapping, key, actions, now, delay) {
        this.Sequence += 1
        binding := {ID: chord.ID, Mask: chord.Mask, Button: chord.Buttons[1], Buttons: chord.Buttons.Clone(),
            Mapping: mapping, Token: this.Sequence, Action: MacroModel.Action(mapping),
            Timing: MacroModel.Timing(mapping), Hold: MacroModel.IsHold(mapping),
            Assigned: !!MacroModel.Assigned(mapping), IsDouble: chord.Kind = "Double",
            DoublePending: false, Released: false, Pending: false, Due: 0, Started: false}
        this.Active[key] := binding
        if !this.IsWindow(binding) && !this.IsKeyboardHold(binding) && binding.Timing = "Release"
            return
        if delay > 0 {
            binding.Pending := true
            binding.Due := now + delay
        } else
            this.Start(binding, actions)
    }

    Start(binding, actions) {
        binding.Pending := false
        if !binding.Assigned
            return
        binding.Started := true
        kind := binding.Action = "ToggleTopmost" ? "ToggleTopmost"
            : this.IsWindow(binding) ? "BeginWindow" : this.IsKeyboardHold(binding) ? "BeginHold" : "Tap"
        actions.Push({Kind: kind, Binding: binding})
    }

    Advance(now) {
        actions := []
        for key, binding in this.Active.Clone() {
            if !binding.Pending || now < binding.Due
                continue
            if binding.DoublePending {
                binding.DoublePending := false
                if binding.Released {
                    this.Active.Delete(key)
                    this.Finish(binding, actions, true)
                } else if !this.IsWindow(binding) && !this.IsKeyboardHold(binding) && binding.Timing = "Release"
                    binding.Pending := false
                else
                    this.Start(binding, actions)
            } else
                this.Start(binding, actions)
        }
        return actions
    }

    Up(buttonOrSide, now := 0) {
        actions := []
        sideBit := buttonOrSide = 4 ? 1 : buttonOrSide = 5 ? 2 : 0
        for key, binding in this.Active.Clone() {
            if sideBit ? !(binding.Mask & sideBit) : !this.Contains(binding.Buttons, buttonOrSide)
                continue
            if !sideBit && binding.DoublePending && now < binding.Due {
                binding.Released := true
                continue
            }
            this.Active.Delete(key)
            binding.DoublePending := false
            this.Finish(binding, actions, true)
        }
        ; Only DOWN evaluates candidates: unwinding never starts a subset, but
        ; a fresh DOWN can re-complete a larger chord with its partners held.
        return actions
    }

    Finish(binding, actions, released := false) {
        if !binding.Assigned {
            binding.Pending := false
            binding.DoublePending := false
            return
        }
        if binding.Pending {
            binding.Pending := false
            if released && !this.IsWindow(binding) {
                this.Start(binding, actions)
                if this.IsKeyboardHold(binding)
                    actions.Push({Kind: "EndHold", Binding: binding})
            }
            return
        }
        if this.IsWindow(binding) {
            if binding.Started
                actions.Push({Kind: "EndWindow", Binding: binding})
        } else if this.IsKeyboardHold(binding) {
            if binding.Started
                actions.Push({Kind: "EndHold", Binding: binding})
        } else if released && binding.Timing = "Release"
            actions.Push({Kind: binding.Action = "ToggleTopmost" ? "ToggleTopmost" : "Tap", Binding: binding})
    }

    Cancel() {
        actions := []
        for , binding in this.Active
            this.Finish(binding, actions)
        this.Active.Clear()
        return actions
    }

    PendingRelease() {
        ; Delayed starts must also enable the runtime's Escape/cancellation gate.
        for , binding in this.Active
            if binding.Pending || (!this.IsWindow(binding) && !this.IsKeyboardHold(binding) && binding.Timing = "Release")
                return true
        return false
    }
}
