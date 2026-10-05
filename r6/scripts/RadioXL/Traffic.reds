// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Puts custom stations among the random picks: traffic car radios and world radios
//              set to start on a random station.
// File Version: 0.6.0
// ======================================================================================
//
// A traffic car picks its station from its own vehicle metadata's `matchingStartupRadioStations`
// (`TrafficVehicleEmitter::PlayRadio`); a station missing from that list is never picked. Most cars
// share one list of nine vanilla stations, and a few carry a themed one. Every list keeps its
// vanilla copy here and is rebuilt from it whenever a setting changes, so switching off returns it
// to vanilla exactly.
//
// A world radio set to randomise picks once, in script, the first time its device initialises,
// and saves the station's enum value with the device. A jukebox picks again on every attach.

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
  private let m_files: array<Int32>;
  private let m_streams: array<Int32>;
  private let m_mode: RadioXLTrafficMode = RadioXLTrafficMode.Shared;
  private let m_worldRadios: Bool = true;
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

  // Called once, as the cooked metadata loads. `slots` are the custom stations that exist in it.
  public func Capture(cooked: ref<audioCookedMetadataResource>, slots: array<Int32>,
                      streams: array<Int32>) -> Void {
    if ArraySize(this.m_lists) > 0 { return; }
    this.m_streams = streams;
    for slot in slots {
      if !ArrayContains(streams, slot) { ArrayPush(this.m_files, slot); }
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

  public func Set(mode: RadioXLTrafficMode, worldRadios: Bool, allowStreams: Bool) -> Void {
    this.m_worldRadios = worldRadios;
    if Equals(mode, this.m_mode) && Equals(allowStreams, this.m_allowStreams) { return; }
    this.m_mode = mode;
    this.m_allowStreams = allowStreams;
    this.Apply();
  }

  // The custom stations a random pick may land on, as slots.
  public func Candidates() -> array<Int32> {
    let slots: array<Int32> = this.m_files;
    if this.m_allowStreams {
      for slot in this.m_streams { ArrayPush(slots, slot); }
    }
    return slots;
  }

  public func WorldRadios() -> Bool {
    return this.m_worldRadios;
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
      for slot in this.Candidates() { ArrayPush(added, RadioXL_StationName(slot)); }
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

// Vanilla draws evenly from the fourteen, less Samizdat. Each custom station is one more equal
// share of the draw.
@wrapMethod(RadioStationDataProvider)
public final static func GetRandomStation() -> ERadioStationList {
  let random = RadioXLTraffic.Get();
  if !IsDefined(random) || !random.WorldRadios() { return wrappedMethod(); }
  let slots: array<Int32> = random.Candidates();
  let pick: Int32 = RandRange(0, 13 + ArraySize(slots));
  if pick < 13 { return wrappedMethod(); }
  let station: ERadioStationList = IntEnum<ERadioStationList>(14 + slots[pick - 13]);
  RadioXLLog(s"world radio: random start on \(RadioXL_StationName(slots[pick - 13]))");
  return station;
}
