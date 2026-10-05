// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Puts custom stations on the lists traffic cars tune to.
// File Version: 0.6.0
// ======================================================================================
//
// A traffic car picks its station from its own vehicle metadata's `matchingStartupRadioStations`
// (`TrafficVehicleEmitter::PlayRadio`); a station missing from that list is never picked. Most cars
// share one list of nine vanilla stations, and a few carry a themed one. Every list keeps its
// vanilla copy here and is rebuilt from it whenever a setting changes, so switching off returns it
// to vanilla exactly.

module RadioXL

public enum RadioXLTrafficMode {
  Off = 0,
  Shared = 1,
  All = 2
}

public class RadioXLTrafficList {
  public let vehicle: ref<audioVehicleMetadata>;
  public let vanilla: array<CName>;
  public let shared: Bool;
}

public class RadioXLTraffic extends ScriptableService {

  private let m_lists: array<ref<RadioXLTrafficList>>;
  private let m_files: array<CName>;
  private let m_streams: array<CName>;
  private let m_mode: RadioXLTrafficMode = RadioXLTrafficMode.Shared;
  private let m_allowStreams: Bool = false;

  public final static func Get() -> ref<RadioXLTraffic> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLTraffic") as RadioXLTraffic;
  }

  // The nine stations most vanilla cars list. A list holding all nine is a shared one; any other
  // list is themed, and Shared leaves it alone.
  private final static func SharedStations() -> array<CName> {
    return [
      n"radio_station_01_att_rock", n"radio_station_02_aggro_ind", n"radio_station_03_elec_ind",
      n"radio_station_04_hiphop", n"radio_station_05_pop", n"radio_station_07_aggro_techno",
      n"radio_station_09_downtempo", n"radio_station_10_latino", n"radio_station_11_metal"
    ];
  }

  // Called once, as the cooked metadata loads. `stations` are the custom stations that exist in it.
  public func Capture(cooked: ref<audioCookedMetadataResource>, stations: array<CName>,
                      streams: array<CName>) -> Void {
    if ArraySize(this.m_lists) > 0 { return; }
    this.m_streams = streams;
    for name in stations {
      if !ArrayContains(streams, name) { ArrayPush(this.m_files, name); }
    }
    let shared: array<CName> = RadioXLTraffic.SharedStations();
    for entry in cooked.entries {
      let vehicle = entry as audioVehicleMetadata;
      if IsDefined(vehicle) && vehicle.hasRadioReceiver && this.Takes(vehicle.matchingStartupRadioStations) {
        let list = new RadioXLTrafficList();
        list.vehicle = vehicle;
        list.vanilla = vehicle.matchingStartupRadioStations;
        list.shared = RadioXLTraffic.HoldsAll(list.vanilla, shared);
        ArrayPush(this.m_lists, list);
      }
    }
    this.Apply();
  }

  public func Set(mode: RadioXLTrafficMode, allowStreams: Bool) -> Void {
    if Equals(mode, this.m_mode) && Equals(allowStreams, this.m_allowStreams) { return; }
    this.m_mode = mode;
    this.m_allowStreams = allowStreams;
    this.Apply();
  }

  // An empty list means the car plays nothing, and a police list plays the scanner; neither takes
  // a music station.
  private func Takes(list: array<CName>) -> Bool {
    return ArraySize(list) > 0 && !ArrayContains(list, n"radio_station_police");
  }

  private final static func HoldsAll(list: array<CName>, wanted: array<CName>) -> Bool {
    for name in wanted {
      if !ArrayContains(list, name) { return false; }
    }
    return true;
  }

  private func Apply() -> Void {
    let added: array<CName>;
    if !Equals(this.m_mode, RadioXLTrafficMode.Off) {
      added = this.m_files;
      if this.m_allowStreams {
        for name in this.m_streams { ArrayPush(added, name); }
      }
    }
    let changed: Int32 = 0;
    for list in this.m_lists {
      let stations: array<CName> = list.vanilla;
      if ArraySize(added) > 0 && (list.shared || Equals(this.m_mode, RadioXLTrafficMode.All)) {
        for name in added {
          if !ArrayContains(stations, name) { ArrayPush(stations, name); }
        }
        changed += 1;
      }
      list.vehicle.matchingStartupRadioStations = stations;
    }
    RadioXLLog(s"traffic: \(ArraySize(added)) custom station(s) on \(changed) of \(ArraySize(this.m_lists)) vehicle list(s), mode \(EnumInt(this.m_mode)), streams \(this.m_allowStreams)");
  }
}
