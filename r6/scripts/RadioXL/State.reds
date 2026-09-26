// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The three values RCF cannot hold for this mod, in the mod's own file
//              (r6/storages/RadioXL/state.json).
//
//              The remembered station is a NAME, and RCF has no string channel: its dropdown
//              stores an option index, which points at a different station once the dial has
//              changed. The ident switch is read while the game's resources LOAD, before RCF has
//              restored anything, because a station's blips are consumed by the engine at that
//              moment. The announcement switch is read there too, so a fresh session starts in
//              the right state without waiting for the panel.
//
//              Without RedFunctions the file cannot be read: the station is then remembered for
//              the session only, and the two mutes do nothing. RedFunctions is a dependency of
//              RCF, so a player with the settings panel has it.
// File Version: 0.5.1
// Credits: DV (RedFunctions)
// ======================================================================================

module RadioXL

@if(ModuleExists("RedFunctions.Storage"))
import RedFunctions.Storage.*
@if(ModuleExists("RedFunctions.Json"))
import RedFunctions.Json.*

public class RadioXLState extends ScriptableService {
  public let rememberStation: CName = n"None";
  public let muteIdents: Bool = false;
  public let muteNews: Bool = false;

  private let m_loaded: Bool;

  public final static func Get() -> ref<RadioXLState> {
    let store = GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLState") as RadioXLState;
    if IsDefined(store) { store.Load(); }
    return store;
  }

  // Idempotent, and called on first use rather than from OnLoad: service load order is not
  // promised, and the catalog needs these values while its resource loads.
  public func Load() -> Void {
    if this.m_loaded { return; }
    this.m_loaded = true;
    this.Read();
  }

  public func SetRememberStation(station: CName) -> Void {
    this.rememberStation = station;
    this.Write();
  }

  public func SetMuteIdents(value: Bool) -> Void {
    this.muteIdents = value;
    this.Write();
    this.Apply();
  }

  public func SetMuteNews(value: Bool) -> Void {
    this.muteNews = value;
    this.Write();
    this.Apply();
  }

  private func Apply() -> Void {
    let catalog = RadioXLCatalog.Get();
    if IsDefined(catalog) { catalog.ApplyMutes(); }
  }

  @if(ModuleExists("RedFunctions.Storage"))
  private func Storage() -> ref<ModStorage> {
    let storage = ModStorage.Open("RadioXL");
    if !IsDefined(storage) {
      RadioXLLog(s"RedFunctions storage unavailable (\(ModStorage.LastError())) - station memory is session-only");
    }
    return storage;
  }

  @if(ModuleExists("RedFunctions.Storage") && ModuleExists("RedFunctions.Json"))
  private func Read() -> Void {
    let storage = this.Storage();
    if !IsDefined(storage) { return; }
    if !storage.Has("state.json") {
      RadioXLLog("no state.json yet - defaults in use");
      return;
    }
    let root = storage.ReadJson("state.json");
    if !IsDefined(root) || !root.IsMap() { return; }
    let obj = root.AsMap();
    if obj.Contains("rememberStation") { this.rememberStation = StringToName(obj.Text("rememberStation")); }
    if obj.Contains("muteIdents") { this.muteIdents = obj.Bool("muteIdents"); }
    if obj.Contains("muteNews") { this.muteNews = obj.Bool("muteNews"); }
    RadioXLLog(s"state read: station \(this.rememberStation), idents muted \(this.muteIdents), announcements muted \(this.muteNews)");
  }

  @if(ModuleExists("RedFunctions.Storage") && ModuleExists("RedFunctions.Json"))
  private func Write() -> Void {
    let storage = this.Storage();
    if !IsDefined(storage) { return; }
    let obj = JsonMap.Make();
    obj.PutText("rememberStation", IsNameValid(this.rememberStation) ? NameToString(this.rememberStation) : "None");
    obj.PutBool("muteIdents", this.muteIdents);
    obj.PutBool("muteNews", this.muteNews);
    let ok: Bool = storage.WriteJson("state.json", obj);
    RadioXLLog(s"state written (\(ok)): station \(this.rememberStation), idents muted \(this.muteIdents), announcements muted \(this.muteNews)");
  }

  @if(!ModuleExists("RedFunctions.Storage") || !ModuleExists("RedFunctions.Json"))
  private func Read() -> Void {}

  @if(!ModuleExists("RedFunctions.Storage") || !ModuleExists("RedFunctions.Json"))
  private func Write() -> Void {}
}
