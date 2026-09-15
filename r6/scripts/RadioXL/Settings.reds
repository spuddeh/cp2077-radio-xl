// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The settings panel, through the Redscript Configuration Framework, and the
//              "Mute the radio when..." switches it started with. RCF owns the panel and the
//              saved values (r6/storages/RedscriptConfigFramework/RadioXL.json); this provider
//              bridges its Get*/Set* to RadioXLConfig, RadioXLControls and RadioXLState. The
//              whole panel compiles to nothing when RCF is absent, and the mod then runs on its
//              defaults with no way to change them.
//
//              THIS IS THE ONLY SETTINGS UI. Mirroring a setting into Mod Settings is forbidden:
//              ModSettings.AcceptChanges() is global and applies every other mod's pending
//              changes as a side effect.
//
//              FOUR TABS. Controls holds the keys and the two notifications; My station the
//              remembered station; Stations one section per station from the catalog, each with
//              its step-over switch and its songs; Mute the station talk and the twelve
//              situation switches. Rows behind a switch (modifiers, the Radioport keys) exist
//              only while the switch is on: RCF rebuilds the panel the moment such a switch flips.
//
//              THE KEY ROWS ARE LOCAL-ONLY. RCF stores the key and never pushes it to its input
//              plugin, because this mod matches the key itself on Codeware's Input/Key event.
// File Version: 0.3.0
// Credits: Redscript Configuration Framework by DigitalVixen.
// ======================================================================================
//
// A custom station is a real station, so every rule that silences the pocket radio silences it
// too: a scene, a phone call, a club, fast travel and the rest, exactly as they silence a vanilla
// station. The situation switches let the player keep the Radioport playing through a situation
// the game would silence it in, on every station. Every switch is on by default, which is the
// game's own behaviour.
//
// **Combat and police heat are not here.** The game ducks and stops the radio in those through
// the Wwise mix state on the radio buses, which a station on the game's own radio route cannot
// opt out of.

module RadioXL

@if(ModuleExists("RedscriptConfigFramework"))
import RedscriptConfigFramework.*

public class RadioXLConfig extends ScriptableSystem {
  public static func Get() -> ref<RadioXLConfig> {
    return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
      .Get(n"RadioXL.RadioXLConfig") as RadioXLConfig;
  }

  // One per PocketRadioRestrictions member, in enum order.
  public let muteSceneTier: Bool = true;
  public let muteUpperBodyState: Bool = true;
  public let muteQuestContentLock: Bool = true;
  public let muteInDaClub: Bool = true;
  public let muteBlockFastTravel: Bool = true;
  public let muteVehicleScene: Bool = true;
  public let muteVehicleBlockPocketRadio: Bool = true;
  public let mutePhoneCall: Bool = true;
  public let mutePhoneNoTexting: Bool = true;
  public let mutePhoneNoCalling: Bool = true;
  public let muteFastForward: Bool = true;
  public let muteFastForwardHintActive: Bool = true;

  // Whether the game's own silence for this restriction is kept.
  public func MutesOn(restriction: Int32) -> Bool {
    if restriction == EnumInt(PocketRadioRestrictions.SceneTier) { return this.muteSceneTier; }
    if restriction == EnumInt(PocketRadioRestrictions.UpperBodyState) { return this.muteUpperBodyState; }
    if restriction == EnumInt(PocketRadioRestrictions.QuestContentLock) { return this.muteQuestContentLock; }
    if restriction == EnumInt(PocketRadioRestrictions.InDaClub) { return this.muteInDaClub; }
    if restriction == EnumInt(PocketRadioRestrictions.BlockFastTravel) { return this.muteBlockFastTravel; }
    if restriction == EnumInt(PocketRadioRestrictions.VehicleScene) { return this.muteVehicleScene; }
    if restriction == EnumInt(PocketRadioRestrictions.VehicleBlockPocketRadio) { return this.muteVehicleBlockPocketRadio; }
    if restriction == EnumInt(PocketRadioRestrictions.PhoneCall) { return this.mutePhoneCall; }
    if restriction == EnumInt(PocketRadioRestrictions.PhoneNoTexting) { return this.mutePhoneNoTexting; }
    if restriction == EnumInt(PocketRadioRestrictions.PhoneNoCalling) { return this.mutePhoneNoCalling; }
    if restriction == EnumInt(PocketRadioRestrictions.FastForward) { return this.muteFastForward; }
    if restriction == EnumInt(PocketRadioRestrictions.FastForwardHintActive) { return this.muteFastForwardHintActive; }
    return true;
  }

  @if(ModuleExists("RedscriptConfigFramework"))
  private let m_provider: ref<RadioXLConfigProvider>;

  // The saved values are restored at attach, before any session, so the situation switches are
  // in force from the first PocketRadio wrap. The panel is registered at every Session/Ready,
  // the main menu's included, with the catalog built first so the Stations tab lists what the
  // save has.
  @if(ModuleExists("RedscriptConfigFramework"))
  private func OnAttach() -> Void {
    let gi: GameInstance = this.GetGameInstance();
    this.m_provider = new RadioXLConfigProvider();
    this.m_provider.Init(this);
    this.m_provider.BeginRestore();
    DVRCF_Store.RestoreInto(gi, "RadioXL", this.m_provider, this.m_provider.BuildSchema());
    this.m_provider.EndRestore();
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Session/Ready", this, n"OnSessionReady")
      .SetLifetime(CallbackLifetime.Forever);
  }

  @if(ModuleExists("RedscriptConfigFramework"))
  protected cb func OnSessionReady(event: ref<GameSessionEvent>) -> Void {
    if !IsDefined(this.m_provider) { return; }
    let catalog = RadioXLCatalog.Get();
    if IsDefined(catalog) { catalog.Build(); }
    this.m_provider.BeginRestore();
    DVRCF.Register(this.GetGameInstance(), "RadioXL", "RadioXL.modName", "RadioXL.modDesc", this.m_provider);
    this.m_provider.EndRestore();
  }
}

// Row keys. One set of constants so the schema and the Get/Set switches cannot drift apart.
// Renaming one orphans every player's saved value for it.
public func RadioXL_KeyUseModifiers() -> String { return "useModifiers"; }
public func RadioXL_KeySeparateRadioport() -> String { return "separateRadioportKeys"; }
// A key row's own id is the bind id, from RadioXLControls. Its modifier rides a second row whose
// key is the bind id behind a fixed prefix, so the two can never be confused for each other or
// for a setting above.
public func RadioXL_ModifierPrefix() -> String { return "mod:"; }
public func RadioXL_KeyNotifyRadioport() -> String { return "notifyRadioport"; }
public func RadioXL_KeyNotifyOnscreen() -> String { return "notifyOnscreen"; }
public func RadioXL_KeyRememberEnabled() -> String { return "rememberEnabled"; }
public func RadioXL_KeyRememberStation() -> String { return "rememberStation"; }
public func RadioXL_KeyPlayOnEnter() -> String { return "playOnEnter"; }
public func RadioXL_KeyPlayOnVehiclePowerOn() -> String { return "playOnVehiclePowerOn"; }
public func RadioXL_KeyPlayOnPocketPowerOn() -> String { return "playOnPocketPowerOn"; }
public func RadioXL_KeyIgnorePocketRadio() -> String { return "ignorePocketRadio"; }
public func RadioXL_KeyMuteIdents() -> String { return "muteIdents"; }
public func RadioXL_KeyMuteNews() -> String { return "muteNews"; }
// A song row's key is the event name behind a fixed prefix; a station's step-over row is its
// event name behind another. The name comes back out of each unchanged.
public func RadioXL_SongPrefix() -> String { return "song:"; }
public func RadioXL_SkipPrefix() -> String { return "skip:"; }

@if(ModuleExists("RedscriptConfigFramework"))
public class RadioXLConfigProvider extends DVRCF_Provider {
  private let m_cfg: wref<RadioXLConfig>;
  private let m_restoring: Bool;

  public func Init(cfg: ref<RadioXLConfig>) -> Void {
    this.m_cfg = cfg;
  }

  // RCF restores every saved row through Set* at registration. Three rows ignore that restore:
  // the remembered station and the two mutes live in the mod's own file, read before RCF has
  // anything, and a stale copy in RCF's JSON must not overwrite them.
  public func BeginRestore() -> Void { this.m_restoring = true; }
  public func EndRestore() -> Void { this.m_restoring = false; }

  // Rebuilt on every panel open and on every switch marked Rebuilds, so a station mod installed
  // since the last open is listed and an unfolded station shows its songs.
  public func BuildSchema() -> ref<DVRCF_Schema> {
    let b: ref<DVRCF_SchemaBuilder> = DVRCF_SchemaBuilder.New("RadioXL.modName");
    let controls = RadioXLControls.Get();

    // --- Controls ---
    b.Tab("RadioXL.tabControls");
    b.Section("RadioXL.secKeys");
    b.Label("RadioXL.tipKeys");
    this.AddKeys(b, controls, RadioXLBindSet.Main);
    b.Toggle(RadioXL_KeyUseModifiers(), "RadioXL.optUseModifiers").Rebuilds();
    b.Tip("RadioXL.tipUseModifiers");
    if IsDefined(controls) && controls.useModifiers {
      b.Group("RadioXL.grpModifiers");
      this.AddModifiers(b, controls, RadioXLBindSet.Main);
    }
    b.Toggle(RadioXL_KeySeparateRadioport(), "RadioXL.optSeparateRadioport").Rebuilds();
    b.Tip("RadioXL.tipSeparateRadioport");
    if IsDefined(controls) && controls.separateRadioportKeys {
      b.Group("RadioXL.grpRadioport");
      this.AddKeys(b, controls, RadioXLBindSet.Radioport);
      if controls.useModifiers {
        this.AddModifiers(b, controls, RadioXLBindSet.Radioport);
      }
    }
    b.Section("RadioXL.secOnScreen");
    b.Toggle(RadioXL_KeyNotifyRadioport(), "RadioXL.optNotifyRadioport");
    b.Tip("RadioXL.tipNotifyRadioport");
    b.Toggle(RadioXL_KeyNotifyOnscreen(), "RadioXL.optNotifyOnscreen");
    b.Tip("RadioXL.tipNotifyOnscreen");

    // --- My station ---
    b.Tab("RadioXL.tabMyStation");
    b.Section("RadioXL.secMyStation");
    b.Toggle(RadioXL_KeyRememberEnabled(), "RadioXL.optRemember");
    b.Tip("RadioXL.tipRemember");
    b.Dropdown(RadioXL_KeyRememberStation(), "RadioXL.optStation", this.StationOptions());
    b.Tip("RadioXL.tipStation");
    b.Toggle(RadioXL_KeyPlayOnEnter(), "RadioXL.optPlayOnEnter");
    b.Tip("RadioXL.tipPlayOnEnter");
    b.Toggle(RadioXL_KeyPlayOnVehiclePowerOn(), "RadioXL.optPlayOnVehiclePowerOn");
    b.Tip("RadioXL.tipPlayOnVehiclePowerOn");
    b.Toggle(RadioXL_KeyPlayOnPocketPowerOn(), "RadioXL.optPlayOnPocketPowerOn");
    b.Tip("RadioXL.tipPlayOnPocketPowerOn");
    b.Toggle(RadioXL_KeyIgnorePocketRadio(), "RadioXL.optIgnorePocket");
    b.Tip("RadioXL.tipIgnorePocket");

    // --- Stations ---
    b.Tab("RadioXL.tabStations");
    this.AddStations(b, controls);

    // --- Mute ---
    b.Tab("RadioXL.tabMute");
    b.Section("RadioXL.secTalk");
    b.Toggle(RadioXL_KeyMuteIdents(), "RadioXL.optMuteIdents");
    b.Tip("RadioXL.tipMuteIdents");
    b.Toggle(RadioXL_KeyMuteNews(), "RadioXL.optMuteNews");
    b.Tip("RadioXL.tipMuteNews");
    b.Section("RadioXL.secMuteWhen");
    // **A Tip attaches to the LAST row built, whatever it is.** Text that belongs to a section
    // is a Label.
    b.Label("RadioXL.labMuteWhen1");
    b.Label("RadioXL.labMuteWhen2");
    b.Label("RadioXL.labMuteWhen3");
    b.Toggle("muteSceneTier", "RadioXL.muteSceneTier");
    b.Tip("RadioXL.tipMuteSceneTier");
    b.Toggle("mutePhoneCall", "RadioXL.mutePhoneCall");
    b.Tip("RadioXL.tipMutePhoneCall");
    b.Toggle("muteQuestContentLock", "RadioXL.muteQuestContentLock");
    b.Tip("RadioXL.tipMuteQuestContentLock");
    b.Toggle("muteInDaClub", "RadioXL.muteInDaClub");
    b.Tip("RadioXL.tipMuteInDaClub");
    b.Toggle("muteVehicleScene", "RadioXL.muteVehicleScene");
    b.Tip("RadioXL.tipMuteVehicleScene");
    b.Toggle("muteVehicleBlockPocketRadio", "RadioXL.muteVehicleBlockPocketRadio");
    b.Tip("RadioXL.tipMuteVehicleBlockPocketRadio");
    b.Toggle("muteUpperBodyState", "RadioXL.muteUpperBodyState");
    b.Tip("RadioXL.tipMuteUpperBodyState");
    b.Toggle("muteBlockFastTravel", "RadioXL.muteBlockFastTravel");
    b.Tip("RadioXL.tipMuteBlockFastTravel");
    b.Toggle("mutePhoneNoTexting", "RadioXL.mutePhoneNoTexting");
    b.Tip("RadioXL.tipMutePhoneNoTexting");
    b.Toggle("mutePhoneNoCalling", "RadioXL.mutePhoneNoCalling");
    b.Tip("RadioXL.tipMutePhoneNoCalling");
    b.Toggle("muteFastForward", "RadioXL.muteFastForward");
    b.Tip("RadioXL.tipMuteFastForward");
    b.Toggle("muteFastForwardHintActive", "RadioXL.muteFastForwardHintActive");
    b.Tip("RadioXL.tipMuteFastForwardHintActive");
    b.Label("RadioXL.labMuteCombat");

    return b.Build();
  }

  // --- the key rows ------------------------------------------------------------------------------

  private func AddKeys(b: ref<DVRCF_SchemaBuilder>, controls: ref<RadioXLControls>, set: RadioXLBindSet) -> Void {
    if !IsDefined(controls) { return; }
    let binds = controls.Binds();
    let i: Int32 = 0;
    while i < ArraySize(binds) {
      let bind = binds[i];
      i += 1;
      if Equals(bind.set, set) {
        b.ModifierKeybind(bind.id, this.ActionLabel(bind.action));
        let tip: String = this.ActionTip(bind.action);
        if StrLen(tip) > 0 { b.Tip(tip); }
      }
    }
  }

  private func AddModifiers(b: ref<DVRCF_SchemaBuilder>, controls: ref<RadioXLControls>, set: RadioXLBindSet) -> Void {
    let binds = controls.Binds();
    let i: Int32 = 0;
    while i < ArraySize(binds) {
      let bind = binds[i];
      i += 1;
      if Equals(bind.set, set) {
        b.ModifierKeybind(RadioXL_ModifierPrefix() + bind.id, this.ModifierLabel(bind.action));
        b.Tip("RadioXL.tipModifier");
      }
    }
  }

  private func ActionLabel(action: RadioXLAction) -> String {
    if Equals(action, RadioXLAction.NextSong) { return "RadioXL.keyNext"; }
    if Equals(action, RadioXLAction.PreviousSong) { return "RadioXL.keyPrevious"; }
    if Equals(action, RadioXLAction.NextStation) { return "RadioXL.keyNextStation"; }
    if Equals(action, RadioXLAction.PreviousStation) { return "RadioXL.keyPreviousStation"; }
    if Equals(action, RadioXLAction.NeverAgain) { return "RadioXL.keyNever"; }
    if Equals(action, RadioXLAction.MyStation) { return "RadioXL.keyMyStation"; }
    return "RadioXL.keyShowPopup";
  }

  private func ModifierLabel(action: RadioXLAction) -> String {
    if Equals(action, RadioXLAction.NextSong) { return "RadioXL.modNext"; }
    if Equals(action, RadioXLAction.PreviousSong) { return "RadioXL.modPrevious"; }
    if Equals(action, RadioXLAction.NextStation) { return "RadioXL.modNextStation"; }
    if Equals(action, RadioXLAction.PreviousStation) { return "RadioXL.modPreviousStation"; }
    if Equals(action, RadioXLAction.NeverAgain) { return "RadioXL.modNever"; }
    if Equals(action, RadioXLAction.MyStation) { return "RadioXL.modMyStation"; }
    return "RadioXL.modShowPopup";
  }

  private func ActionTip(action: RadioXLAction) -> String {
    if Equals(action, RadioXLAction.NextStation) || Equals(action, RadioXLAction.PreviousStation) {
      return "RadioXL.tipStationKeys";
    }
    if Equals(action, RadioXLAction.ShowPopup) { return "RadioXL.tipShowPopup"; }
    if Equals(action, RadioXLAction.NeverAgain) { return "RadioXL.tipNever"; }
    if Equals(action, RadioXLAction.MyStation) { return "RadioXL.tipMyStation"; }
    return "";
  }

  // --- the station dropdown ---------------------------------------------------------------------
  // Option 0 is "none"; the rest are the dial in order. The stored value is the station's event
  // name, so the index is derived on every read and survives the dial changing between sessions.
  // Dropdown options are the one place RCF takes text rather than a key, so they are resolved here.

  private func StationOptions() -> array<String> {
    let options: array<String>;
    ArrayPush(options, RadioXLText("RadioXL.dropNone"));
    let count: Int32 = RadioStationDataProvider.GetStationsCount();
    let position: Int32 = 0;
    while position < count {
      ArrayPush(options, this.StationLabel(RadioStationDataProvider.GetRadioStationByUIIndex(position)));
      position += 1;
    }
    return options;
  }

  private func StationAtOption(option: Int32) -> CName {
    let position: Int32 = option - 1;
    if position < 0 || position >= RadioStationDataProvider.GetStationsCount() { return n"None"; }
    return RadioStationDataProvider.GetStationName(RadioStationDataProvider.GetRadioStationByUIIndex(position));
  }

  private func OptionOfStation(station: CName) -> Int32 {
    if !IsNameValid(station) { return 0; }
    let count: Int32 = RadioStationDataProvider.GetStationsCount();
    let position: Int32 = 0;
    while position < count {
      if Equals(this.StationAtOption(position + 1), station) { return position + 1; }
      position += 1;
    }
    return 0;
  }

  // --- the Stations tab -------------------------------------------------------------------------
  // One section per station, in dial order: the step-over switch, then a dropdown per song keyed
  // by the song's event name. Section and song labels are the
  // game's own resolved text: RCF runs every label through its localizer and keeps a string it
  // cannot resolve, so resolved text passes through unchanged.

  private func AddStations(b: ref<DVRCF_SchemaBuilder>, controls: ref<RadioXLControls>) -> Void {
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(catalog) || !catalog.IsBuilt() || !IsDefined(controls) {
      b.Section("RadioXL.tabStations").Label("RadioXL.noteNoCatalog");
      return;
    }
    b.Section("RadioXL.tabStations");
    b.Label("RadioXL.labStations");
    b.Label("RadioXL.tipStreamer");
    b.Label(this.IsStreamerMode() ? "RadioXL.noteStreamerOn" : "RadioXL.noteStreamerOff");
    let options: array<String> = this.SongOptions();
    let count: Int32 = RadioStationDataProvider.GetStationsCount();
    let position: Int32 = 0;
    while position < count {
      let enumValue: ERadioStationList = RadioStationDataProvider.GetRadioStationByUIIndex(position);
      let name: CName = RadioStationDataProvider.GetStationName(enumValue);
      position += 1;
      if IsNameValid(name) {
        let station = catalog.Station(name);
        b.Section(this.StationLabel(enumValue));
        b.Toggle(RadioXL_SkipPrefix() + NameToString(name), "RadioXL.optSkipStation");
        b.Tip("RadioXL.tipSkipStation");
        if IsDefined(station) && ArraySize(station.tracks) > 0 {
          let i: Int32 = 0;
          while i < ArraySize(station.tracks) {
            let track = station.tracks[i];
            b.Dropdown(RadioXL_SongPrefix() + NameToString(track.event), this.SongLabel(track), options);
            i += 1;
          }
        }
      }
    }
  }

  // RCF has no greyed-out row, so a song the game is hiding right now says so in its own label.
  private func SongLabel(track: ref<RadioXLCatalogTrack>) -> String {
    let controls = RadioXLControls.Get();
    let label: String = this.TrackLabel(track);
    if this.IsStreamerMode() && IsDefined(controls) && controls.IsStreamerHidden(track.event) {
      return label + "  - " + RadioXLText("RadioXL.noteHidden");
    }
    return label;
  }

  private func SongOptions() -> array<String> {
    let options: array<String>;
    ArrayPush(options, RadioXLText("RadioXL.songOn"));
    ArrayPush(options, RadioXLText("RadioXL.songOff"));
    ArrayPush(options, RadioXLText("RadioXL.songStreamerOff"));
    return options;
  }

  private func IsStreamerMode() -> Bool {
    let settings = GameInstance.GetSettingsSystem(GetGameInstance());
    if !IsDefined(settings) { return false; }
    let variable = settings.GetVar(n"/audio/misc", n"StreamerMode") as ConfigVarBool;
    return IsDefined(variable) && variable.GetValue();
  }

  private func StationLabel(enumValue: ERadioStationList) -> String {
    let text = GetLocalizedText(RadioStationDataProvider.GetChannelName(enumValue));
    return StrLen(text) > 0 ? text : NameToString(RadioStationDataProvider.GetStationName(enumValue));
  }

  // The same lookup the radio popup and the station selector make: the receiver reports the
  // track as a CName built from primaryLocKey, and GetLocalizedTextByKey resolves that name. The
  // row's string key is the fallback, then the event name.
  private func TrackLabel(track: ref<RadioXLCatalogTrack>) -> String {
    let text: String = track.key != 0ul ? GetLocalizedTextByKey(HashToName(track.key)) : "";
    if StrLen(text) == 0 && IsNameValid(track.title) {
      text = GetLocalizedText(NameToString(track.title));
    }
    return StrLen(text) > 0 ? text : NameToString(track.event);
  }

  // --- values --------------------------------------------------------------------------------

  public func GetBool(key: String) -> Bool {
    let c: wref<RadioXLConfig> = this.m_cfg;
    if IsDefined(c) {
      if Equals(key, "muteSceneTier") { return c.muteSceneTier; }
      if Equals(key, "muteUpperBodyState") { return c.muteUpperBodyState; }
      if Equals(key, "muteQuestContentLock") { return c.muteQuestContentLock; }
      if Equals(key, "muteInDaClub") { return c.muteInDaClub; }
      if Equals(key, "muteBlockFastTravel") { return c.muteBlockFastTravel; }
      if Equals(key, "muteVehicleScene") { return c.muteVehicleScene; }
      if Equals(key, "muteVehicleBlockPocketRadio") { return c.muteVehicleBlockPocketRadio; }
      if Equals(key, "mutePhoneCall") { return c.mutePhoneCall; }
      if Equals(key, "mutePhoneNoTexting") { return c.mutePhoneNoTexting; }
      if Equals(key, "mutePhoneNoCalling") { return c.mutePhoneNoCalling; }
      if Equals(key, "muteFastForward") { return c.muteFastForward; }
      if Equals(key, "muteFastForwardHintActive") { return c.muteFastForwardHintActive; }
    }
    let s = RadioXLControls.Get();
    if !IsDefined(s) { return false; }
    if StrBeginsWith(key, RadioXL_SkipPrefix()) {
      return s.IsStationSkipped(StringToName(StrMid(key, StrLen(RadioXL_SkipPrefix()))));
    }
    if Equals(key, RadioXL_KeyUseModifiers()) { return s.useModifiers; }
    if Equals(key, RadioXL_KeySeparateRadioport()) { return s.separateRadioportKeys; }
    if Equals(key, RadioXL_KeyNotifyRadioport()) { return s.notifyRadioport; }
    if Equals(key, RadioXL_KeyNotifyOnscreen()) { return s.notifyOnscreen; }
    if Equals(key, RadioXL_KeyRememberEnabled()) { return s.rememberEnabled; }
    if Equals(key, RadioXL_KeyPlayOnEnter()) { return s.playOnEnter; }
    if Equals(key, RadioXL_KeyPlayOnVehiclePowerOn()) { return s.playOnVehiclePowerOn; }
    if Equals(key, RadioXL_KeyPlayOnPocketPowerOn()) { return s.playOnPocketPowerOn; }
    if Equals(key, RadioXL_KeyIgnorePocketRadio()) { return s.ignorePocketRadio; }
    if Equals(key, RadioXL_KeyMuteIdents()) { return RadioXLState.Get().muteIdents; }
    if Equals(key, RadioXL_KeyMuteNews()) { return RadioXLState.Get().muteNews; }
    return false;
  }

  // Called live per click, and again on load through RCF's restore, before anything else has
  // run; it only touches the settings services.
  public func SetBool(key: String, value: Bool) -> Void {
    let c: wref<RadioXLConfig> = this.m_cfg;
    if IsDefined(c) && StrBeginsWith(key, "mute") && !Equals(key, RadioXL_KeyMuteIdents()) && !Equals(key, RadioXL_KeyMuteNews()) {
      if Equals(key, "muteSceneTier") { c.muteSceneTier = value; }
      if Equals(key, "muteUpperBodyState") { c.muteUpperBodyState = value; }
      if Equals(key, "muteQuestContentLock") { c.muteQuestContentLock = value; }
      if Equals(key, "muteInDaClub") { c.muteInDaClub = value; }
      if Equals(key, "muteBlockFastTravel") { c.muteBlockFastTravel = value; }
      if Equals(key, "muteVehicleScene") { c.muteVehicleScene = value; }
      if Equals(key, "muteVehicleBlockPocketRadio") { c.muteVehicleBlockPocketRadio = value; }
      if Equals(key, "mutePhoneCall") { c.mutePhoneCall = value; }
      if Equals(key, "mutePhoneNoTexting") { c.mutePhoneNoTexting = value; }
      if Equals(key, "mutePhoneNoCalling") { c.mutePhoneNoCalling = value; }
      if Equals(key, "muteFastForward") { c.muteFastForward = value; }
      if Equals(key, "muteFastForwardHintActive") { c.muteFastForwardHintActive = value; }
      // A switch changed while a restriction is in force takes effect now, not at the next scene.
      RadioXLRestrictions.Refresh();
      return;
    }
    let s = RadioXLControls.Get();
    if !IsDefined(s) { return; }
    if StrBeginsWith(key, RadioXL_SkipPrefix()) {
      s.SetStationSkipped(StringToName(StrMid(key, StrLen(RadioXL_SkipPrefix()))), value);
      return;
    }
    if Equals(key, RadioXL_KeyUseModifiers()) { s.useModifiers = value; }
    else if Equals(key, RadioXL_KeySeparateRadioport()) { s.separateRadioportKeys = value; }
    else if Equals(key, RadioXL_KeyNotifyRadioport()) { s.notifyRadioport = value; }
    else if Equals(key, RadioXL_KeyNotifyOnscreen()) { s.notifyOnscreen = value; }
    else if Equals(key, RadioXL_KeyRememberEnabled()) { s.rememberEnabled = value; }
    else if Equals(key, RadioXL_KeyPlayOnEnter()) { s.playOnEnter = value; }
    else if Equals(key, RadioXL_KeyPlayOnVehiclePowerOn()) { s.playOnVehiclePowerOn = value; }
    else if Equals(key, RadioXL_KeyPlayOnPocketPowerOn()) { s.playOnPocketPowerOn = value; }
    else if Equals(key, RadioXL_KeyIgnorePocketRadio()) { s.ignorePocketRadio = value; }
    // The two mutes live in the mod's own file, read before RCF restores anything. RCF's restore
    // of them is ignored so a stale copy in its JSON cannot overwrite the file.
    else if Equals(key, RadioXL_KeyMuteIdents()) { if !this.m_restoring { RadioXLState.Get().SetMuteIdents(value); } }
    else if Equals(key, RadioXL_KeyMuteNews()) { if !this.m_restoring { RadioXLState.Get().SetMuteNews(value); } }
  }

  // Key rows travel on the Int channel as an EInputKey cast to Int32. 0 is IK_None: a key not
  // bound, which is a valid state for most of them.
  public func GetInt(key: String) -> Int32 {
    let s = RadioXLControls.Get();
    if !IsDefined(s) { return 0; }
    if StrBeginsWith(key, RadioXL_SongPrefix()) {
      return s.SongState(this.SongEvent(key));
    }
    if StrBeginsWith(key, RadioXL_ModifierPrefix()) {
      let modified = s.Bind(StrMid(key, StrLen(RadioXL_ModifierPrefix())));
      return IsDefined(modified) ? EnumInt(modified.modifier) : 0;
    }
    let bind = s.Bind(key);
    if IsDefined(bind) { return EnumInt(bind.key); }
    // A Dropdown rides the Int channel; the value is the selected option's index.
    if Equals(key, RadioXL_KeyRememberStation()) { return this.OptionOfStation(RadioXLState.Get().rememberStation); }
    return 0;
  }

  public func SetInt(key: String, value: Int32) -> Void {
    let s = RadioXLControls.Get();
    if !IsDefined(s) { return; }
    if StrBeginsWith(key, RadioXL_SongPrefix()) {
      s.SetSongState(this.SongEvent(key), value);
      return;
    }
    if StrBeginsWith(key, RadioXL_ModifierPrefix()) {
      let modified = s.Bind(StrMid(key, StrLen(RadioXL_ModifierPrefix())));
      if IsDefined(modified) { modified.modifier = IntEnum<EInputKey>(value); }
      return;
    }
    let bind = s.Bind(key);
    if IsDefined(bind) {
      bind.key = IntEnum<EInputKey>(value);
      return;
    }
    // RCF restores the saved option INDEX at registration, and that index points at a different
    // station once the dial has changed. The name in the store is the truth, so the restore is
    // ignored and only a pick made in the panel writes the name.
    if Equals(key, RadioXL_KeyRememberStation()) {
      if !this.m_restoring {
        RadioXLState.Get().SetRememberStation(this.StationAtOption(value));
      }
    }
  }

  private func SongEvent(key: String) -> CName {
    return StringToName(StrMid(key, StrLen(RadioXL_SongPrefix())));
  }
}
