// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The equaliser and processing the player radio plays through, chosen per station.
//
//              With per-station on, every station plays its own choice: the one saved for it (a
//              preset, or its own nine custom bands), else RadioXL's suggestion, else Flat. With it
//              off, every station plays the global equaliser: a preset, or the global nine custom
//              bands. Presets are files the plugin reads at load
//              (red4ext/plugins/RadioXL/presets); a preset named here that no longer exists plays
//              Flat. Processing is Off, Broadcast (all three stages) or Custom (each stage's own
//              switch). Applied when a setting changes and whenever the radio the player hears
//              changes station.
// File Version: 0.8.1
// ======================================================================================

module RadioXL

public enum RadioXLProcessing {
  Off = 0,
  Broadcast = 1,
  Custom = 2
}

public enum RadioXLProcessingStage {
  Agc = 0,
  PeakCompressor = 1,
  Limiter = 2
}

// What became of a preset saved from the game.
public enum RadioXLPresetSave {
  Saved = 0,
  BadName = 1,     // empty, over 40 characters, a control character, a space at an end, or "Custom"
  NameTaken = 2,   // a loaded preset has the name, ignoring case
  WriteFailed = 3
}

public func RadioXL_EqCustom() -> String { return "Custom"; }
public func RadioXL_EqBandCount() -> Int32 { return 9; }

public abstract class RadioXLEqualiser {
  // The preset with this name, ignoring case, or -1.
  public final static func PresetIndex(name: String) -> Int32 {
    let wanted: String = StrLower(name);
    let count: Int32 = RadioXL_EqPresetCount();
    let i: Int32 = 0;
    while i < count {
      if Equals(StrLower(RadioXL_EqPresetName(i)), wanted) { return i; }
      i += 1;
    }
    return -1;
  }

  // The preset RadioXL suggests for one of the game's own stations, or "". The suggestion lives here and
  // not in the preset files, which players edit and share. Growl FM is a deliberate mix and has none.
  public final static func Suggested(station: CName) -> String {
    switch station {
      case n"radio_station_01_att_rock": return "Rock";
      case n"radio_station_02_aggro_ind": return "Industrial";
      case n"radio_station_03_elec_ind": return "Electronic";
      case n"radio_station_04_hiphop": return "Hip hop";
      case n"radio_station_05_pop": return "Pop";
      case n"radio_station_06_minim_techno": return "Techno";
      case n"radio_station_07_aggro_techno": return "Techno";
      case n"radio_station_08_jazz": return "Jazz";
      case n"radio_station_09_downtempo": return "Downtempo";
      case n"radio_station_10_latino": return "Latin";
      case n"radio_station_11_metal": return "Metal";
      case n"radio_station_13_dark_star": return "Atmospheric";
      case n"radio_station_14_impulse_fm": return "Techno";
    }
    return "";
  }

  public final static func PresetNames() -> array<String> {
    let names: array<String>;
    let count: Int32 = RadioXL_EqPresetCount();
    let i: Int32 = 0;
    while i < count {
      ArrayPush(names, RadioXL_EqPresetName(i));
      i += 1;
    }
    return names;
  }

  // The station's own choice as heard: "" while the global equaliser plays (per-station off, or no
  // station), else the choice saved for it, else RadioXL's suggestion, else Flat.
  public final static func OwnChoice(station: CName) -> String {
    let state = RadioXLState.Get();
    if !IsDefined(state) || !state.perStationEq || !IsNameValid(station) { return ""; }
    let saved: String = state.StationEq(station);
    if StrLen(saved) > 0 { return saved; }
    let suggested: String = RadioXLAPI.SuggestedEqPreset(station);
    return StrLen(suggested) > 0 ? suggested : "Flat";
  }

  // The preset the station plays: its own, else the global one; a name no longer loaded reads as Flat.
  public final static func Active(station: CName) -> String {
    let state = RadioXLState.Get();
    if !IsDefined(state) { return "Flat"; }
    let name: String = RadioXLEqualiser.OwnChoice(station);
    if StrLen(name) == 0 { name = state.eqPreset; }
    if Equals(name, RadioXL_EqCustom()) { return name; }
    let index: Int32 = RadioXLEqualiser.PresetIndex(name);
    return index < 0 ? "Flat" : RadioXL_EqPresetName(index);
  }

  // The gains, rounded to whole dB, that the station plays now. A station switched to Custom starts
  // from these, so the switch itself changes nothing that is heard.
  public final static func Bands(station: CName) -> array<Int32> {
    let out: array<Int32>;
    let state = RadioXLState.Get();
    let own: String = RadioXLEqualiser.OwnChoice(station);
    let name: String = StrLen(own) > 0 ? own : (IsDefined(state) ? state.eqPreset : "Flat");
    let index: Int32 = Equals(name, RadioXL_EqCustom()) ? -1 : RadioXLEqualiser.PresetIndex(name);
    if !Equals(name, RadioXL_EqCustom()) && index < 0 { index = RadioXLEqualiser.PresetIndex("Flat"); }
    let band: Int32 = 0;
    while band < RadioXL_EqBandCount() {
      if !Equals(name, RadioXL_EqCustom()) {
        ArrayPush(out, Clamp(RoundMath(RadioXL_EqPresetBand(index, band)), -12, 12));
      } else if StrLen(own) > 0 {
        ArrayPush(out, state.StationBand(station, band));
      } else {
        ArrayPush(out, state.EqBand(band));
      }
      band += 1;
    }
    return out;
  }

  public final static func Apply() -> Void {
    let state = RadioXLState.Get();
    if !IsDefined(state) { return; }
    let station: CName = RadioXLAPI.CurrentStation();
    let own: String = RadioXLEqualiser.OwnChoice(station);
    let name: String = own;
    if StrLen(name) == 0 { name = state.eqPreset; }
    RadioXLEvents.EqChanged(station, RadioXLEqualiser.Active(station));
    let band: Int32 = 0;
    if Equals(name, RadioXL_EqCustom()) {
      let stationOwn: Bool = StrLen(own) > 0;
      while band < RadioXL_EqBandCount() {
        RadioXL_SetEqBand(band, Cast<Float>(stationOwn ? state.StationBand(station, band) : state.EqBand(band)));
        band += 1;
      }
    } else {
      let index: Int32 = RadioXLEqualiser.PresetIndex(name);
      if index < 0 {
        RadioXLLog(s"equaliser: no preset named \"\(name)\" - Flat");
        index = RadioXLEqualiser.PresetIndex("Flat");
      }
      while band < RadioXL_EqBandCount() {
        RadioXL_SetEqBand(band, RadioXL_EqPresetBand(index, band));
        band += 1;
      }
    }
    RadioXLEqualiser.ApplyProcessing();
  }

  // 0 Off, 1 Broadcast (all three stages), 2 Custom (each stage's own switch).
  public final static func ApplyProcessing() -> Void {
    let c = RadioXLConfig.Get();
    if !IsDefined(c) { return; }
    let broadcast: Bool = c.processingMode == 1;
    let custom: Bool = c.processingMode == 2;
    RadioXL_SetProcessing(0, broadcast || (custom && c.processAgc));
    RadioXL_SetProcessing(1, broadcast || (custom && c.processPeak));
    RadioXL_SetProcessing(2, broadcast || (custom && c.processLimiter));
  }

  // A stage as heard: every stage under Broadcast, none under Off, its own switch under Custom.
  public final static func StageOn(stage: Int32) -> Bool {
    let c = RadioXLConfig.Get();
    if !IsDefined(c) { return false; }
    if c.processingMode == 1 { return true; }
    if c.processingMode != 2 { return false; }
    switch stage {
      case 0: return c.processAgc;
      case 1: return c.processPeak;
      case 2: return c.processLimiter;
    }
    return false;
  }

  // The three switches are the processing setting: none on is Off, all three is Broadcast, any other
  // mix is Custom. The result depends only on which switches end up on, so RCF can restore them in
  // any order.
  public final static func SetStageOn(stage: Int32, on: Bool) -> Void {
    let c = RadioXLConfig.Get();
    if !IsDefined(c) || stage < 0 || stage > 2 { return; }
    let heard: array<Bool> = [RadioXLEqualiser.StageOn(0), RadioXLEqualiser.StageOn(1), RadioXLEqualiser.StageOn(2)];
    heard[stage] = on;
    c.processAgc = heard[0];
    c.processPeak = heard[1];
    c.processLimiter = heard[2];
    let count: Int32 = (heard[0] ? 1 : 0) + (heard[1] ? 1 : 0) + (heard[2] ? 1 : 0);
    c.processingMode = count == 0 ? 0 : (count == 3 ? 1 : 2);
    RadioXLEqualiser.ApplyProcessing();
  }
}
