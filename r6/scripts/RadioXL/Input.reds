// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The keys. Every key press reaches this listener through Codeware's Input/Key
//              event; a press that matches a bind runs its action on whichever radio is playing.
//              The framework ships no input mapping and RCF never applies these keys itself: RCF
//              only captures and stores them.
//
//              A HELD MODIFIER WINS OVER THE BARE KEY. When two binds share a key and one of
//              them carries a modifier that is held, that one runs; otherwise the bare one does.
//              Modifiers are read only while the panel's modifier switch is on.
// File Version: 0.5.1
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL

public class RadioXLInput extends ScriptableService {
  private let m_registered: Bool;
  private let m_held: array<EInputKey>;

  private cb func OnLoad() {
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Session/Ready", this, n"OnSessionReady");
  }

  private cb func OnSessionReady(event: ref<GameSessionEvent>) {
    if this.m_registered { return; }
    this.m_registered = true;
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Input/Key", this, n"OnKey", true);
  }

  private cb func OnKey(event: ref<KeyInputEvent>) {
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) { return; }
    let key = event.GetKey();
    if Equals(key, EInputKey.IK_None) { return; }
    this.TrackModifier(controls, key, event.GetAction());
    if NotEquals(event.GetAction(), EInputAction.IACT_Press) { return; }
    let gi = GetGameInstance();
    let player = GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) { return; }
    let onFoot: Bool = !IsDefined(player.GetMountedVehicle());
    let bind = this.Match(controls, key, controls.SetFor(onFoot));
    if !IsDefined(bind) { return; }
    if this.IsInMenu(gi) { return; }
    let deck = RadioXLDeck.Get();
    if !IsDefined(deck) { return; }
    if Equals(bind.action, RadioXLAction.NextSong) { deck.Step(gi, true); }
    else if Equals(bind.action, RadioXLAction.PreviousSong) { deck.Step(gi, false); }
    else if Equals(bind.action, RadioXLAction.NextStation) { deck.StepStation(gi, true); }
    else if Equals(bind.action, RadioXLAction.PreviousStation) { deck.StepStation(gi, false); }
    else if Equals(bind.action, RadioXLAction.ShowPopup) { deck.ShowPopup(gi); }
    else if Equals(bind.action, RadioXLAction.NeverAgain) { deck.NeverAgain(gi); }
    else if Equals(bind.action, RadioXLAction.MyStation) { deck.JumpToMyStation(gi); }
  }

  private func Match(controls: ref<RadioXLControls>, key: EInputKey, set: RadioXLBindSet) -> ref<RadioXLBind> {
    let binds = controls.Binds();
    let best: ref<RadioXLBind>;
    let bestScore: Int32 = -1;
    let i: Int32 = 0;
    while i < ArraySize(binds) {
      let bind = binds[i];
      i += 1;
      if Equals(bind.set, set) && Equals(bind.key, key) && NotEquals(bind.key, EInputKey.IK_None) {
        let modifier: EInputKey = controls.ModifierOf(bind);
        let chord: Bool = NotEquals(modifier, EInputKey.IK_None);
        if !chord || ArrayContains(this.m_held, modifier) {
          let score: Int32 = chord ? 1 : 0;
          if score > bestScore {
            bestScore = score;
            best = bind;
          }
        }
      }
    }
    return best;
  }

  private func TrackModifier(controls: ref<RadioXLControls>, key: EInputKey, action: EInputAction) -> Void {
    if Equals(action, EInputAction.IACT_Press) {
      if controls.IsModifier(key) && !ArrayContains(this.m_held, key) {
        ArrayPush(this.m_held, key);
      }
    } else if Equals(action, EInputAction.IACT_Release) {
      ArrayRemove(this.m_held, key);
    }
  }

  private func IsInMenu(gi: GameInstance) -> Bool {
    let defs = GetAllBlackboardDefs();
    let boards = GameInstance.GetBlackboardSystem(gi);
    let ui = boards.Get(defs.UI_System);
    if IsDefined(ui) && ui.GetBool(defs.UI_System.IsInMenu) { return true; }
    let photo = boards.Get(defs.PhotoMode);
    if IsDefined(photo) && photo.GetBool(defs.PhotoMode.IsActive) { return true; }
    return false;
  }
}
