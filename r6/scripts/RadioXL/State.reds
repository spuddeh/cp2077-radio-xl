// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The values RCF cannot hold for this mod, in the mod's own file
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
//
//              The equaliser's choices are NAMES for the same reason as the station: a preset is a
//              file, and adding one moves every option index after it. The global preset, the custom
//              bands, each station's own preset (absent = the global one) and each station's own custom
//              bands are kept here. A station's bands outlive a change to a preset, so switching back to
//              Custom finds them as they were.
// File Version: 0.8.1
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
  // The global equaliser: a preset's name, or RadioXL_EqCustom() for the nine custom bands.
  public let eqPreset: String = "Flat";
  public let eqBands: array<Int32>;
  // On, every station plays its own equaliser; off, every station plays the global one.
  public let perStationEq: Bool = false;
  private let m_stationEq: array<CName>;
  private let m_stationEqPreset: array<String>;
  // Nine values per station, in the order of m_stationBandKeys.
  private let m_stationBandKeys: array<CName>;
  private let m_stationBands: array<Int32>;

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
    let changed: Bool = NotEquals(station, this.rememberStation);
    this.rememberStation = station;
    this.Write();
    if changed { RadioXLEvents.MyStationChanged(station); }
  }

  public func SetEqPreset(name: String) -> Void {
    this.eqPreset = name;
    this.Write();
  }

  public func SetPerStationEq(on: Bool) -> Void {
    this.perStationEq = on;
    this.Write();
  }

  public func EqBand(band: Int32) -> Int32 {
    return band >= 0 && band < ArraySize(this.eqBands) ? this.eqBands[band] : 0;
  }

  public func SetEqBand(band: Int32, db: Int32) -> Void {
    while ArraySize(this.eqBands) < 9 { ArrayPush(this.eqBands, 0); }
    if band < 0 || band >= 9 { return; }
    this.eqBands[band] = db;
    this.Write();
  }

  // A station's saved preset name, or "" when none is saved.
  public func StationEq(station: CName) -> String {
    let i: Int32 = ArrayFindFirst(this.m_stationEq, station);
    return i >= 0 ? this.m_stationEqPreset[i] : "";
  }

  public func SetStationEq(station: CName, name: String) -> Void {
    let i: Int32 = ArrayFindFirst(this.m_stationEq, station);
    if i >= 0 {
      ArrayErase(this.m_stationEq, i);
      ArrayErase(this.m_stationEqPreset, i);
    }
    if StrLen(name) > 0 {
      ArrayPush(this.m_stationEq, station);
      ArrayPush(this.m_stationEqPreset, name);
    }
    this.Write();
  }

  public func HasStationBands(station: CName) -> Bool {
    return ArrayContains(this.m_stationBandKeys, station);
  }

  public func StationBand(station: CName, band: Int32) -> Int32 {
    let i: Int32 = ArrayFindFirst(this.m_stationBandKeys, station);
    return i >= 0 && band >= 0 && band < 9 ? this.m_stationBands[i * 9 + band] : 0;
  }

  // Stores the station's nine bands in one write.
  public func SetStationBands(station: CName, bands: array<Int32>) -> Void {
    let i: Int32 = ArrayFindFirst(this.m_stationBandKeys, station);
    if i < 0 {
      i = ArraySize(this.m_stationBandKeys);
      ArrayPush(this.m_stationBandKeys, station);
      let b: Int32 = 0;
      while b < 9 { ArrayPush(this.m_stationBands, 0); b += 1; }
    }
    let band: Int32 = 0;
    while band < 9 {
      this.m_stationBands[i * 9 + band] = band < ArraySize(bands) ? bands[band] : 0;
      band += 1;
    }
    this.Write();
  }

  public func SetMuteIdents(value: Bool) -> Void {
    let changed: Bool = NotEquals(value, this.muteIdents);
    this.muteIdents = value;
    this.Write();
    this.Apply();
    if changed { RadioXLEvents.MutesChanged(this.muteIdents, this.muteNews); }
  }

  public func SetMuteNews(value: Bool) -> Void {
    let changed: Bool = NotEquals(value, this.muteNews);
    this.muteNews = value;
    this.Write();
    this.Apply();
    if changed { RadioXLEvents.MutesChanged(this.muteIdents, this.muteNews); }
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
    if obj.Contains("eqPreset") { this.eqPreset = obj.Text("eqPreset"); }
    if obj.Contains("perStationEq") { this.perStationEq = obj.Bool("perStationEq"); }
    ArrayClear(this.eqBands);
    let b: Int32 = 0;
    while b < 9 {
      ArrayPush(this.eqBands, obj.Int(s"eqBand\(b)", 0));
      b += 1;
    }
    if obj.Contains("stationEq") {
      let map = obj.Map("stationEq");
      if IsDefined(map) {
        for key in map.KeyList() {
          ArrayPush(this.m_stationEq, StringToName(key));
          ArrayPush(this.m_stationEqPreset, map.Text(key));
        }
      }
    }
    if obj.Contains("stationEqBands") {
      let bandMap = obj.Map("stationEqBands");
      if IsDefined(bandMap) {
        for key in bandMap.KeyList() {
          let list = bandMap.List(key);
          if IsDefined(list) {
            ArrayPush(this.m_stationBandKeys, StringToName(key));
            let band: Int32 = 0;
            while band < 9 {
              ArrayPush(this.m_stationBands, Clamp(list.IntAt(band, 0), -12, 12));
              band += 1;
            }
          }
        }
      }
    }
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
    obj.PutText("eqPreset", this.eqPreset);
    obj.PutBool("perStationEq", this.perStationEq);
    let b: Int32 = 0;
    while b < 9 {
      obj.PutInt(s"eqBand\(b)", this.EqBand(b));
      b += 1;
    }
    let map = JsonMap.Make();
    let i: Int32 = 0;
    while i < ArraySize(this.m_stationEq) {
      map.PutText(NameToString(this.m_stationEq[i]), this.m_stationEqPreset[i]);
      i += 1;
    }
    obj.Put("stationEq", map);
    let bandMap = JsonMap.Make();
    i = 0;
    while i < ArraySize(this.m_stationBandKeys) {
      let list = JsonList.Make();
      let band: Int32 = 0;
      while band < 9 {
        list.PushInt(this.m_stationBands[i * 9 + band]);
        band += 1;
      }
      bandMap.Put(NameToString(this.m_stationBandKeys[i]), list);
      i += 1;
    }
    obj.Put("stationEqBands", bandMap);
    let ok: Bool = storage.WriteJson("state.json", obj);
    RadioXLLog(s"state written (\(ok)): station \(this.rememberStation), idents muted \(this.muteIdents), announcements muted \(this.muteNews)");
  }

  @if(!ModuleExists("RedFunctions.Storage") || !ModuleExists("RedFunctions.Json"))
  private func Read() -> Void {}

  @if(!ModuleExists("RedFunctions.Storage") || !ModuleExists("RedFunctions.Json"))
  private func Write() -> Void {}
}
