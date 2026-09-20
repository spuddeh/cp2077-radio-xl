// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The player-side settings - keys, notifications, station memory, song switches
//              and the stations the station keys step over - held on one service. RCF owns the
//              panel and the saved values (r6/storages/RedscriptConfigFramework/RadioXL.json)
//              and writes them here through RadioXLConfigProvider; nothing else writes these
//              fields.
//
//              A SWITCHED-OFF SONG IS STORED BY ITS EVENT NAME. The event name is the one key a
//              track keeps across mods and game versions - a title key can be reused and a list
//              position moves - and it is what the audio system takes to play a track.
//
//              ONE SET OF KEYS SERVES BOTH RADIOS. The receiver is known at the moment a key is
//              pressed (a mounted vehicle with its radio on, else the Radioport), so a key needs no
//              receiver of its own. A second set for the Radioport exists behind a switch, for a
//              player who wants the two radios on different keys. Every key can carry a modifier,
//              so one key can serve two actions: F3 alone for the next song and Shift+F3 for the
//              next station.
// File Version: 0.4.1
// Credits: DigitalVixen (RCF)
// ======================================================================================

module RadioXL

// What a key does. The number is never stored, so it can be renumbered freely.
public enum RadioXLAction {
  NextSong = 0,
  PreviousSong = 1,
  NextStation = 2,
  PreviousStation = 3,
  ShowPopup = 4,
  NeverAgain = 5,
  MyStation = 6,
}

// Which set a key belongs to. Main serves both radios; Radioport is the optional second set.
public enum RadioXLBindSet {
  Main = 0,
  Radioport = 1,
}

// What a song is set to. The number is the dropdown's option index and is written into the
// player's config, so the order of these three cannot change.
public func RadioXL_SongOn() -> Int32 { return 0; }
public func RadioXL_SongOff() -> Int32 { return 1; }
public func RadioXL_SongStreamerOff() -> Int32 { return 2; }

// One key row of the panel, and the key that must be held with it. `id` is the RCF row key and is
// written into the player's config, so renaming one orphans their binding.
public class RadioXLBind {
  public let id: String;
  public let set: RadioXLBindSet;
  public let action: RadioXLAction;
  public let key: EInputKey;
  public let modifier: EInputKey;
}

public class RadioXLControls extends ScriptableService {
  // The keys. Modifiers are read only while `useModifiers` is on; the Radioport set only while
  // `separateRadioportKeys` is on. Both are off out of the box, and the panel hides the rows.
  public let useModifiers: Bool = false;
  public let separateRadioportKeys: Bool = false;

  // Notifications. The vehicle popup is the game's own; the Radioport has none, so this mod
  // drives the same widget for it. The on-screen line is the alternative at the left of the screen.
  public let notifyRadioport: Bool = false;
  public let notifyOnscreen: Bool = false;

  // When to tune to the remembered station. The station itself is a name and lives in RadioXLState.
  public let rememberEnabled: Bool = false;
  public let playOnEnter: Bool = true;
  public let playOnVehiclePowerOn: Bool = true;
  public let playOnPocketPowerOn: Bool = true;
  public let ignorePocketRadio: Bool = true;

  // What each song is set to, by event name. A song absent from the list is On. The engine's own
  // streaming flag is seeded in here by the catalog, so this list is the one answer to what a song
  // does - and a song the engine says nothing about, which is every song a mod adds, can be marked
  // here the same way.
  private let m_songEvent: array<CName>;
  private let m_songState: array<Int32>;

  // Stations the station keys step over, by event name. A name rather than a dial position,
  // because a position moves the moment a station mod is added or removed.
  private let m_skipped: array<CName>;

  private let m_binds: array<ref<RadioXLBind>>;

  public final static func Get() -> ref<RadioXLControls> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLControls") as RadioXLControls;
  }

  // --- the keys --------------------------------------------------------------------------------

  // Only the two song keys are bound out of the box. A station key and the popup key start
  // unbound, so the mod takes no key the player may already be using.
  private func EnsureBinds() -> Void {
    if ArraySize(this.m_binds) > 0 { return; }
    this.AddBind("nextKey", RadioXLBindSet.Main, RadioXLAction.NextSong, EInputKey.IK_F3);
    this.AddBind("previousKey", RadioXLBindSet.Main, RadioXLAction.PreviousSong, EInputKey.IK_F2);
    this.AddBind("nextStationKey", RadioXLBindSet.Main, RadioXLAction.NextStation, EInputKey.IK_None);
    this.AddBind("previousStationKey", RadioXLBindSet.Main, RadioXLAction.PreviousStation, EInputKey.IK_None);
    this.AddBind("showPopupKey", RadioXLBindSet.Main, RadioXLAction.ShowPopup, EInputKey.IK_None);
    this.AddBind("neverKey", RadioXLBindSet.Main, RadioXLAction.NeverAgain, EInputKey.IK_None);
    this.AddBind("myStationKey", RadioXLBindSet.Main, RadioXLAction.MyStation, EInputKey.IK_None);
    this.AddBind("pocketNextKey", RadioXLBindSet.Radioport, RadioXLAction.NextSong, EInputKey.IK_F3);
    this.AddBind("pocketPreviousKey", RadioXLBindSet.Radioport, RadioXLAction.PreviousSong, EInputKey.IK_F2);
    this.AddBind("pocketNextStationKey", RadioXLBindSet.Radioport, RadioXLAction.NextStation, EInputKey.IK_None);
    this.AddBind("pocketPreviousStationKey", RadioXLBindSet.Radioport, RadioXLAction.PreviousStation, EInputKey.IK_None);
    this.AddBind("pocketShowPopupKey", RadioXLBindSet.Radioport, RadioXLAction.ShowPopup, EInputKey.IK_None);
    this.AddBind("pocketNeverKey", RadioXLBindSet.Radioport, RadioXLAction.NeverAgain, EInputKey.IK_None);
    this.AddBind("pocketMyStationKey", RadioXLBindSet.Radioport, RadioXLAction.MyStation, EInputKey.IK_None);
  }

  private func AddBind(id: String, set: RadioXLBindSet, action: RadioXLAction, key: EInputKey) -> Void {
    let bind = new RadioXLBind();
    bind.id = id;
    bind.set = set;
    bind.action = action;
    bind.key = key;
    bind.modifier = EInputKey.IK_None;
    ArrayPush(this.m_binds, bind);
  }

  public func Binds() -> array<ref<RadioXLBind>> {
    this.EnsureBinds();
    return this.m_binds;
  }

  public func Bind(id: String) -> ref<RadioXLBind> {
    this.EnsureBinds();
    let i: Int32 = 0;
    while i < ArraySize(this.m_binds) {
      if UnicodeStringEqual(this.m_binds[i].id, id) { return this.m_binds[i]; }
      i += 1;
    }
    return null;
  }

  // Whether a bind's modifier counts right now. Off, every key acts on its own.
  public func ModifierOf(bind: ref<RadioXLBind>) -> EInputKey {
    return this.useModifiers ? bind.modifier : EInputKey.IK_None;
  }

  // Which set answers for a receiver: the Radioport set only when it is switched on and the
  // player is on foot.
  public func SetFor(onFoot: Bool) -> RadioXLBindSet {
    return this.separateRadioportKeys && onFoot ? RadioXLBindSet.Radioport : RadioXLBindSet.Main;
  }

  // Whether any live bind uses this key as its modifier, which is what decides whether the input
  // listener bothers to remember it as held.
  public func IsModifier(key: EInputKey) -> Bool {
    if Equals(key, EInputKey.IK_None) || !this.useModifiers { return false; }
    this.EnsureBinds();
    let i: Int32 = 0;
    while i < ArraySize(this.m_binds) {
      if Equals(this.m_binds[i].modifier, key) { return true; }
      i += 1;
    }
    return false;
  }

  // --- the stations the keys step over ---------------------------------------------------------

  public func IsStationSkipped(station: CName) -> Bool {
    return ArrayContains(this.m_skipped, station);
  }

  public func SetStationSkipped(station: CName, skipped: Bool) -> Void {
    if !IsNameValid(station) { return; }
    if skipped {
      if !ArrayContains(this.m_skipped, station) { ArrayPush(this.m_skipped, station); }
    } else {
      ArrayRemove(this.m_skipped, station);
    }
  }

  // --- the song switches -----------------------------------------------------------------------

  private func SongIndex(event: CName) -> Int32 {
    let i: Int32 = 0;
    while i < ArraySize(this.m_songEvent) {
      if Equals(this.m_songEvent[i], event) { return i; }
      i += 1;
    }
    return -1;
  }

  public func SongState(event: CName) -> Int32 {
    let at: Int32 = this.SongIndex(event);
    return at < 0 ? RadioXL_SongOn() : this.m_songState[at];
  }

  public func SetSongState(event: CName, state: Int32) -> Void {
    if !IsNameValid(event) { return; }
    let at: Int32 = this.SongIndex(event);
    if at < 0 {
      ArrayPush(this.m_songEvent, event);
      ArrayPush(this.m_songState, state);
    } else {
      this.m_songState[at] = state;
    }
  }

  public func IsTrackEnabled(event: CName) -> Bool {
    return this.SongState(event) != RadioXL_SongOff();
  }

  public func IsStreamerHidden(event: CName) -> Bool {
    return this.SongState(event) == RadioXL_SongStreamerOff();
  }

  // Songs that are anything but plain On, which is what decides whether the automatic skip has
  // any work to do at all.
  public func DisabledCount() -> Int32 {
    let count: Int32 = 0;
    let i: Int32 = 0;
    while i < ArraySize(this.m_songState) {
      if this.m_songState[i] != RadioXL_SongOn() { count += 1; }
      i += 1;
    }
    return count;
  }
}
