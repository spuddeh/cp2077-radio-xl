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
//              Without RedFileSystem the file cannot be read: the station is then remembered for
//              the session only, and the two mutes do nothing. RedFileSystem is a dependency of
//              RCF, so a player with the settings panel has it.
// File Version: 0.4.1
// Credits: Rayshader (RedFileSystem, RedData)
// ======================================================================================

module RadioXL

@if(ModuleExists("RedFileSystem"))
import RedFileSystem.*
@if(ModuleExists("RedData.Json"))
import RedData.Json.*

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

  // RedFileSystem hands a storage out ONCE per run; a second GetStorage call for the same name
  // locks it for everyone, so the handle is taken on the first read and kept.
  @if(ModuleExists("RedFileSystem"))
  private let m_storage: ref<FileSystemStorage>;

  @if(ModuleExists("RedFileSystem"))
  private func Storage() -> ref<FileSystemStorage> {
    if !IsDefined(this.m_storage) {
      this.m_storage = FileSystem.GetStorage("RadioXL");
      if !IsDefined(this.m_storage) {
        RadioXLLog("RedFileSystem storage unavailable - station memory is session-only");
      }
    }
    return this.m_storage;
  }

  @if(ModuleExists("RedFileSystem") && ModuleExists("RedData.Json"))
  private func Read() -> Void {
    let storage = this.Storage();
    if !IsDefined(storage) { return; }
    if NotEquals(storage.Exists("state.json"), FileSystemStatus.True) {
      RadioXLLog("no state.json yet - defaults in use");
      return;
    }
    let file = storage.GetFile("state.json");
    if !IsDefined(file) { return; }
    let obj = file.ReadAsJson() as JsonObject;
    if !IsDefined(obj) { return; }
    if obj.HasKey("rememberStation") { this.rememberStation = StringToName(obj.GetKeyString("rememberStation")); }
    if obj.HasKey("muteIdents") { this.muteIdents = obj.GetKeyBool("muteIdents"); }
    if obj.HasKey("muteNews") { this.muteNews = obj.GetKeyBool("muteNews"); }
    RadioXLLog(s"state read: station \(this.rememberStation), idents muted \(this.muteIdents), announcements muted \(this.muteNews)");
  }

  @if(ModuleExists("RedFileSystem") && ModuleExists("RedData.Json"))
  private func Write() -> Void {
    let storage = this.Storage();
    if !IsDefined(storage) { return; }
    let file = storage.GetFile("state.json");
    if !IsDefined(file) {
      RadioXLLog("state.json could not be opened for writing");
      return;
    }
    let obj = new JsonObject();
    obj.SetKeyString("rememberStation", IsNameValid(this.rememberStation) ? NameToString(this.rememberStation) : "None");
    obj.SetKeyBool("muteIdents", this.muteIdents);
    obj.SetKeyBool("muteNews", this.muteNews);
    let ok: Bool = file.WriteJson(obj, "  ");
    RadioXLLog(s"state written (\(ok)): station \(this.rememberStation), idents muted \(this.muteIdents), announcements muted \(this.muteNews)");
  }

  @if(!ModuleExists("RedFileSystem") || !ModuleExists("RedData.Json"))
  private func Read() -> Void {}

  @if(!ModuleExists("RedFileSystem") || !ModuleExists("RedData.Json"))
  private func Write() -> Void {}
}
