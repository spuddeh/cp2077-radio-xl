// ======================================================================================
// Mod Name: RadioXL API Test
// Author: Spuddeh
// Description: The redscript examples in docs/script-api.md, as written there, so a compile of the test mod
//              checks them. Change one here when it changes there.
// File Version: 0.6.0
// ======================================================================================

module RadioXLApiTest.Examples

import RadioXL.*

public abstract class RadioXLDocQuickStart {
  public static func Run() -> array<String> {
    let titles: array<String>;
    let tracks = RadioXLAPI.Tracks(n"radio_station_12_growl_fm");
    for track in tracks {
      if RadioXLAPI.IsSongPlayable(track) {
        ArrayPush(titles, RadioXLAPI.TrackTitle(track));
      }
    }
    return titles;
  }
}

public class MyRadioListener extends ScriptableService {
  private cb func OnLoad() {
    let cs = GameInstance.GetCallbackSystem();
    cs.RegisterCallback(n"RadioXL/Ready", this, n"OnReady", true);
    cs.RegisterCallback(n"RadioXL/SongChanged", this, n"OnSong");
  }
  private cb func OnReady(evt: ref<RadioXLReadyEvent>) { /* safe to read now */ }
  private cb func OnSong(evt: ref<RadioXLSongChangedEvent>) {
    let title = RadioXLAPI.TrackTitle(evt.Track());
  }
}

public abstract class RadioXLDocPool {
  public static func Run() -> array<CName> {
    let pool: array<CName>;
    let stations = RadioXLAPI.Stations();
    for station in stations {
      if RadioXLAPI.IsCustomStation(station) && !RadioXLAPI.IsStreamStation(station) {
        let tracks = RadioXLAPI.Tracks(station);
        for track in tracks {
          if RadioXLAPI.IsSongPlayable(track) { ArrayPush(pool, track); }
        }
      }
    }
    return pool;
  }
}
