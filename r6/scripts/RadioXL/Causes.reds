// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Logs every cause that raises or drops a Radioport restriction, by name.
// File Version: 0.8.0
// ======================================================================================
//
// The twelve restrictions have fifteen causes: twelve GameplayRestriction status effects (the
// effect's record names it), a quest content lock (its source names it), a scene tier of 2 or
// higher, and the upper body state ForceEmptyHands. A situation applies several at once, and which
// ones is in quest and scene data, not in script, so each cause is logged: `cause +` when it
// arrives and `cause -` when it goes, with the restrictions it carries. Nothing here changes what
// the radio does.

module RadioXL

public abstract class RadioXLCauses {
  // The restriction tags an effect carries, as text.
  public static func RestrictionTags(tags: array<CName>) -> String {
    let known: array<CName> = [n"InDaClub", n"BlockFastTravel", n"VehicleScene", n"VehicleBlockPocketRadio",
                               n"PhoneCall", n"PhoneNoTexting", n"PhoneNoCalling", n"FastForward",
                               n"FastForwardHintActive", n"MetroRide", n"BinocularView",
                               n"PocketRadioRestrictionUnlockDelay"];
    let out: String = "";
    for tag in known {
      if ArrayContains(tags, tag) {
        out += (StrLen(out) > 0 ? " " : "") + NameToString(tag);
      }
    }
    return out;
  }

  public static func Effect(record: ref<StatusEffect_Record>) -> String {
    return IsDefined(record) ? TDBID.ToStringDEBUG(record.GetID()) : "?";
  }
}

@wrapMethod(PocketRadio)
public final func OnStatusEffectRemoved(evt: ref<RemoveStatusEffect>, gameplayTags: script_ref<[CName]>) -> Void {
  let carried: String = RadioXLCauses.RestrictionTags(Deref(gameplayTags));
  if StrLen(carried) > 0 {
    RadioXLLog(s"cause - effect \(RadioXLCauses.Effect(evt.staticData)) [\(carried)]");
  }
  wrappedMethod(evt, gameplayTags);
}

@wrapMethod(PocketRadio)
public final func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>, gameplayTags: script_ref<[CName]>) -> Void {
  let carried: String = RadioXLCauses.RestrictionTags(Deref(gameplayTags));
  if StrLen(carried) > 0 {
    RadioXLLog(s"cause + effect \(RadioXLCauses.Effect(evt.staticData)) [\(carried)]");
  }
  wrappedMethod(evt, gameplayTags);
}

@wrapMethod(PocketRadioQuestContentLockListener)
protected cb func OnBlocked(source: CName) -> Bool {
  RadioXLLog(s"cause + quest lock \(NameToString(source))");
  return wrappedMethod(source);
}

@wrapMethod(PocketRadioQuestContentLockListener)
protected cb func OnUnblocked(source: CName) -> Bool {
  RadioXLLog(s"cause - quest lock \(NameToString(source))");
  return wrappedMethod(source);
}

@wrapMethod(PlayerPuppet)
protected cb func OnSceneTierChange(newState: Int32) -> Bool {
  RadioXLLog(s"cause scene tier \(newState)\(newState >= 2 ? " (restricts)" : "")");
  return wrappedMethod(newState);
}

@addField(PlayerPuppet)
private let m_radioxlEmptyHands: Bool;

// ForceEmptyHands is held by any of five sources (DefaultTransition.IsEmptyHandsForced): a safe
// zone, the quest fact ForceEmptyHands, a NoCombat effect (not while fast-forwarding), a
// VehicleScene effect, or the state machine's own parameter (scene tier, inspection, minigame),
// which script cannot read and is named only when none of the others holds.
@wrapMethod(PlayerPuppet)
protected cb func OnUpperBodyStateChange(newState: Int32) -> Bool {
  let emptyHands: Bool = newState == 5;
  if NotEquals(emptyHands, this.m_radioxlEmptyHands) {
    this.m_radioxlEmptyHands = emptyHands;
    let sources: String = "";
    if this.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones) == 2 {
      sources += " safe-zone";
    }
    if GameInstance.GetQuestsSystem(this.GetGame()).GetFact(n"ForceEmptyHands") > 0 {
      sources += " quest-fact";
    }
    if StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"NoCombat")
       && !StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"FastForward") {
      sources += " NoCombat";
    }
    if StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"VehicleScene") {
      sources += " VehicleScene";
    }
    if emptyHands && StrLen(sources) == 0 {
      sources = " state-parameter";
    }
    RadioXLLog(s"cause \(emptyHands ? "+" : "-") upper body ForceEmptyHands [\(StrMid(sources, 1))]");
  }
  return wrappedMethod(newState);
}
