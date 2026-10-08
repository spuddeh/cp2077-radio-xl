// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Keeps the Radioport playing through a situation the player chose not to mute in.
// File Version: 0.8.0
// ======================================================================================
//
// The game silences the pocket radio through `PocketRadio.HandleRestriction`: twelve restrictions,
// and while any is set the radio is off and every tune request is ignored. A situation raises
// several restrictions at once, and one restriction is raised by several situations, so a switch
// is a SITUATION: phone calls, scenes, driving scenes, clubs, safe areas and quests.
//
// Each restriction the game reports is held by one or more situations, read from the live game
// state each time anything changes (`Holders`). **A restriction is lifted only when every
// situation holding it is switched off**, so a scene inside a club stays silent until both
// switches are off. A restriction no situation accounts for stays as the game set it.
//
// A scene tier, the forced empty hands of a scene and the skip prompt belong to whatever they
// happen inside: a club while `InDaClub` holds, a driving scene while a `VehicleScene` effect
// holds, otherwise a scene.

module RadioXL

public enum RadioXLSituation {
  Calls = 0,
  Scenes = 1,
  DrivingScenes = 2,
  Clubs = 3,
  SafeAreas = 4,
  Quests = 5
}

public class RadioXLRestrictions extends ScriptableSystem {

  // The value the game last reported for each restriction, before any switch was applied.
  private let m_actual: array<Bool>;
  // What the Silenced event last reported for each restriction.
  private let m_reported: array<Bool>;
  // The quest content locks in force, by source. The game keeps one flag for all of them.
  private let m_locks: array<CName>;

  public static func Get() -> ref<RadioXLRestrictions> {
    return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
      .Get(n"RadioXL.RadioXLRestrictions") as RadioXLRestrictions;
  }

  private func OnAttach() -> Void {
    let i: Int32 = 0;
    while i < EnumInt(PocketRadioRestrictions.PocketRadioRestrictionCount) {
      ArrayPush(this.m_actual, false);
      ArrayPush(this.m_reported, false);
      i += 1;
    }
  }

  public func Record(restriction: Int32, restricted: Bool) -> Void {
    if restriction >= 0 && restriction < ArraySize(this.m_actual) {
      this.m_actual[restriction] = restricted;
    }
  }

  public func Actual(restriction: Int32) -> Bool {
    return restriction >= 0 && restriction < ArraySize(this.m_actual) && this.m_actual[restriction];
  }

  // `holo_interrupt` and `__phonecall__` never reach the restriction (the game's listener drops
  // them), and `ALL_SOURCES` lifts every lock at once.
  public func LockOn(source: CName) -> Void {
    if Equals(source, n"holo_interrupt") || Equals(source, n"__phonecall__") { return; }
    if !ArrayContains(this.m_locks, source) { ArrayPush(this.m_locks, source); }
  }

  public func LockOff(source: CName) -> Void {
    if Equals(source, n"ALL_SOURCES") {
      ArrayClear(this.m_locks);
      return;
    }
    ArrayRemove(this.m_locks, source);
  }

  // Emits RadioXL/Silenced when what the Radioport is told for a restriction changes.
  public func Report(restriction: Int32, silenced: Bool) -> Void {
    if restriction < 0 || restriction >= ArraySize(this.m_reported) { return; }
    if NotEquals(this.m_reported[restriction], silenced) {
      this.m_reported[restriction] = silenced;
      RadioXLEvents.Silenced(restriction, silenced);
    }
  }

  // --- which situations hold a restriction --------------------------------------------------------

  private static func HasTag(player: ref<PlayerPuppet>, tag: CName) -> Bool {
    return StatusEffectSystem.ObjectHasStatusEffectWithTag(player, tag);
  }

  private static func SceneTier(player: ref<PlayerPuppet>) -> Int32 {
    return player.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.SceneTier);
  }

  // A scene tier, empty hands from a scene and the skip prompt belong to the situation around them.
  private static func Context(player: ref<PlayerPuppet>) -> RadioXLSituation {
    if RadioXLRestrictions.HasTag(player, n"InDaClub") { return RadioXLSituation.Clubs; }
    if RadioXLRestrictions.HasTag(player, n"VehicleScene") { return RadioXLSituation.DrivingScenes; }
    return RadioXLSituation.Scenes;
  }

  private static func Add(out list: array<RadioXLSituation>, s: RadioXLSituation) -> Void {
    if !ArrayContains(list, s) { ArrayPush(list, s); }
  }

  // Empty hands are forced by a safe zone, a NoCombat effect (not while fast-forwarding), a
  // VehicleScene effect, the quest fact ForceEmptyHands, or the state machine's own parameter
  // (scene tier, inspection, minigame), which script cannot read: that one is assumed whenever
  // a scene tier of 2 or more is up, or nothing else accounts for the hands.
  private static func EmptyHandsHolders(player: ref<PlayerPuppet>, out list: array<RadioXLSituation>) -> Void {
    if player.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones) == 2 {
      RadioXLRestrictions.Add(list, RadioXLSituation.SafeAreas);
    }
    if RadioXLRestrictions.HasTag(player, n"NoCombat") && !RadioXLRestrictions.HasTag(player, n"FastForward") {
      RadioXLRestrictions.Add(list, RadioXLSituation.SafeAreas);
    }
    if RadioXLRestrictions.HasTag(player, n"VehicleScene") {
      RadioXLRestrictions.Add(list, RadioXLSituation.DrivingScenes);
    }
    if GameInstance.GetQuestsSystem(player.GetGame()).GetFact(n"ForceEmptyHands") > 0 {
      RadioXLRestrictions.Add(list, RadioXLSituation.Quests);
    }
    if RadioXLRestrictions.SceneTier(player) >= 2 || ArraySize(list) == 0 {
      RadioXLRestrictions.Add(list, RadioXLRestrictions.Context(player));
    }
  }

  // A call's own effect carries the fast-travel block; any other effect that carries it is a quest's.
  private static func FastTravelHolders(player: ref<PlayerPuppet>, out list: array<RadioXLSituation>) -> Void {
    let effects: array<ref<StatusEffect>>;
    GameInstance.GetStatusEffectSystem(player.GetGame()).GetAppliedEffectsWithTag(player.GetEntityID(), n"BlockFastTravel", effects);
    for effect in effects {
      let record = effect.GetRecord();
      if IsDefined(record) && ArrayContains(record.GameplayTags(), n"PhoneCall") {
        RadioXLRestrictions.Add(list, RadioXLSituation.Calls);
      } else {
        RadioXLRestrictions.Add(list, RadioXLSituation.Quests);
      }
    }
    if ArraySize(list) == 0 { RadioXLRestrictions.Add(list, RadioXLSituation.Quests); }
  }

  // The `impulse` lock is the club's; every other source is a quest's.
  private func LockHolders(out list: array<RadioXLSituation>) -> Void {
    for source in this.m_locks {
      RadioXLRestrictions.Add(list, Equals(source, n"impulse") ? RadioXLSituation.Clubs : RadioXLSituation.Quests);
    }
    if ArraySize(list) == 0 { RadioXLRestrictions.Add(list, RadioXLSituation.Quests); }
  }

  public func Holders(restriction: PocketRadioRestrictions, player: ref<PlayerPuppet>) -> array<RadioXLSituation> {
    let list: array<RadioXLSituation>;
    switch restriction {
      case PocketRadioRestrictions.SceneTier:
      case PocketRadioRestrictions.FastForward:
      case PocketRadioRestrictions.FastForwardHintActive:
        RadioXLRestrictions.Add(list, RadioXLRestrictions.Context(player));
        break;
      case PocketRadioRestrictions.UpperBodyState:
        RadioXLRestrictions.EmptyHandsHolders(player, list);
        break;
      case PocketRadioRestrictions.QuestContentLock:
        this.LockHolders(list);
        break;
      case PocketRadioRestrictions.InDaClub:
        RadioXLRestrictions.Add(list, RadioXLSituation.Clubs);
        break;
      case PocketRadioRestrictions.BlockFastTravel:
        RadioXLRestrictions.FastTravelHolders(player, list);
        break;
      case PocketRadioRestrictions.VehicleScene:
      case PocketRadioRestrictions.VehicleBlockPocketRadio:
        RadioXLRestrictions.Add(list, RadioXLSituation.DrivingScenes);
        break;
      case PocketRadioRestrictions.PhoneCall:
      case PocketRadioRestrictions.PhoneNoTexting:
      case PocketRadioRestrictions.PhoneNoCalling:
        RadioXLRestrictions.Add(list, RadioXLSituation.Calls);
        break;
      default:
        break;
    }
    return list;
  }

  // The value the pocket radio is told: restricted while any situation holding it keeps its mute.
  public func Applied(restriction: Int32, player: ref<PlayerPuppet>) -> Bool {
    if !this.Actual(restriction) { return false; }
    let cfg = RadioXLConfig.Get();
    if !IsDefined(cfg) || !IsDefined(player) { return true; }
    let holders: array<RadioXLSituation> = this.Holders(IntEnum<PocketRadioRestrictions>(restriction), player);
    if ArraySize(holders) == 0 { return true; }
    for s in holders {
      if cfg.Mutes(s) { return true; }
    }
    return false;
  }

  // Re-applies every restriction with the switches as they stand. Called when a switch changes.
  public static func Refresh() -> Void {
    let gi: GameInstance = GetGameInstance();
    if !GameInstance.IsValid(gi) { return; }
    let player = GetPlayer(gi);
    if !IsDefined(player) { return; }
    let radio = player.GetPocketRadio();
    if IsDefined(radio) { radio.RadioXLReapply(); }
  }
}

// Every restriction is re-evaluated whenever one changes, because one cause changes which
// situation holds another: a vehicle scene's tier arrives before its VehicleScene effect.
@addMethod(PocketRadio)
public final func RadioXLReapply() -> Void {
  let state = RadioXLRestrictions.Get();
  if !IsDefined(state) || !IsDefined(this.m_player) { return; }
  let changed: Bool = false;
  let i: Int32 = 0;
  while i < ArraySize(this.m_restrictions) {
    let applied: Bool = state.Applied(i, this.m_player);
    if NotEquals(this.m_restrictions[i], applied) {
      this.m_restrictions[i] = applied;
      changed = true;
    }
    state.Report(i, applied);
    i += 1;
  }
  if changed && !this.m_isRestrictionOverwritten {
    this.UpdateConditionRestricted();
    this.HandleRestrictionStateChanged();
  }
}

@wrapMethod(PocketRadio)
public final func HandleRestriction(restriction: PocketRadioRestrictions, restricted: Bool) -> Void {
  let state = RadioXLRestrictions.Get();
  if !IsDefined(state) || !IsDefined(this.m_player) {
    wrappedMethod(restriction, restricted);
    return;
  }
  state.Record(EnumInt(restriction), restricted);
  let applied: Bool = state.Applied(EnumInt(restriction), this.m_player);
  state.Report(EnumInt(restriction), applied);
  wrappedMethod(restriction, applied);
  this.RadioXLReapply();
}

@wrapMethod(PocketRadioQuestContentLockListener)
protected cb func OnBlocked(source: CName) -> Bool {
  let state = RadioXLRestrictions.Get();
  if IsDefined(state) { state.LockOn(source); }
  return wrappedMethod(source);
}

@wrapMethod(PocketRadioQuestContentLockListener)
protected cb func OnUnblocked(source: CName) -> Bool {
  let state = RadioXLRestrictions.Get();
  if IsDefined(state) { state.LockOff(source); }
  return wrappedMethod(source);
}
