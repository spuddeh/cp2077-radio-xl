// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Next, previous, and the automatic skip past a switched-off track. One call changes
//              the track: AudioSystem.RequestSongOnRadioStation(stationEvent, trackEvent).
//              Everything else here decides which track to name.
//
//              A RECEIVER REPORTS THE PLAYING TRACK AS A CNAME BUILT FROM THE TRACK'S
//              primaryLocKey, so the catalog's key is matched through NameToHash. The report
//              lags a request by a moment, so the key just asked for stands in as "current" until
//              the receiver catches up or a short window passes.
//
//              THE EMPTY-STATION RULE. A station whose tracks are ALL switched off ignores the
//              setting: a user press steps through the switched-off set, and the automatic skip
//              leaves the track alone. A station with one song left on is not that station - a
//              press there has nowhere to go and stays put. Streamer mode drops every track
//              flagged as not streaming-friendly, and the two Kerry USC songs stay hidden until
//              the quest fact that unlocks them is set, the same two filters the game applies to
//              its own picks.
// File Version: 0.3.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL

// What the player is listening through, resolved fresh on every call. The vehicle receiver wins
// while the player is in a car with the radio on; otherwise the Radioport whenever it is on.
//
// THE METRO IS NOT A SPECIAL CASE. The Radioport plays on NCART and its keys work there, so a
// guard on `PocketRadio.m_isInMetro` only ever refuses to act while the player is listening.
public class RadioXLReceiver {
  public let vehicle: wref<VehicleObject>;
  public let pocket: wref<PocketRadio>;
  public let stationIndex: Int32;
  public let station: ref<RadioXLCatalogStation>;
  public let reported: CName;

  public func IsValid() -> Bool {
    return IsDefined(this.station);
  }
}

public class RadioXLDeck extends ScriptableService {
  private let m_pendingKey: Uint64;
  private let m_pendingAt: Float;

  public final static func Get() -> ref<RadioXLDeck> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLDeck") as RadioXLDeck;
  }

  // --- what is playing -----------------------------------------------------------------------

  public func Receiver(gi: GameInstance) -> ref<RadioXLReceiver> {
    let r = new RadioXLReceiver();
    r.stationIndex = -1;
    let player = GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) { return r; }
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(catalog) || !catalog.IsBuilt() { return r; }
    let vehicle = player.GetMountedVehicle();
    let pocket = player.GetPocketRadio();
    if IsDefined(vehicle) && vehicle.IsRadioReceiverActive() {
      r.vehicle = vehicle;
      r.stationIndex = Cast<Int32>(vehicle.GetCurrentRadioIndex());
      r.reported = vehicle.GetRadioReceiverTrackName();
    } else if IsDefined(pocket) && pocket.IsActive() {
      r.pocket = pocket;
      r.stationIndex = pocket.GetStation();
      r.reported = pocket.GetTrackName();
    } else {
      return r;
    }
    if r.stationIndex < 0 { return r; }
    r.station = catalog.Station(RadioStationDataProvider.GetStationNameByIndex(r.stationIndex));
    return r;
  }

  // The index of the playing track in its station's list, or -1. A request made within the last
  // two seconds counts as playing even if the receiver still reports the old track.
  private func CurrentIndex(gi: GameInstance, r: ref<RadioXLReceiver>) -> Int32 {
    let catalog = RadioXLCatalog.Get();
    let now = this.Now(gi);
    if this.m_pendingKey != 0ul && now - this.m_pendingAt < 2.0 {
      let pending = catalog.IndexOf(r.station, this.m_pendingKey);
      if pending >= 0 { return pending; }
    }
    this.m_pendingKey = 0ul;
    return catalog.IndexOf(r.station, NameToHash(r.reported));
  }

  // --- the filters --------------------------------------------------------------------------

  private func IsStreamerMode(gi: GameInstance) -> Bool {
    let settings = GameInstance.GetSettingsSystem(gi);
    if !IsDefined(settings) { return false; }
    let variable = settings.GetVar(n"/audio/misc", n"StreamerMode") as ConfigVarBool;
    return IsDefined(variable) && variable.GetValue();
  }

  // The two Kerry USC songs, hidden by the game until the quest that unlocks them sets its fact.
  private func IsLockedByQuest(gi: GameInstance, track: ref<RadioXLCatalogTrack>) -> Bool {
    if track.key != 52893ul && track.key != 52892ul { return false; }
    return GameInstance.GetQuestsSystem(gi).GetFact(n"sq017_enable_kerry_usc_radio_songs") != 1;
  }

  // Whether the game would play this track at all, before the player's own switch is consulted.
  private func IsPlayable(gi: GameInstance, track: ref<RadioXLCatalogTrack>, streamer: Bool) -> Bool {
    let controls = RadioXLControls.Get();
    if streamer && IsDefined(controls) && controls.IsStreamerHidden(track.event) { return false; }
    return !this.IsLockedByQuest(gi, track);
  }

  // --- stepping -------------------------------------------------------------------------------

  // A key press. Steps to the next or previous track the player has left enabled, in the
  // station's own order, wrapping at the ends. With nothing enabled, steps through the disabled
  // set instead, so a station is never left with no way to skip.
  public func Step(gi: GameInstance, forward: Bool) -> Void {
    let r = this.Receiver(gi);
    if !r.IsValid() {
      RadioXLLog(s"song key: no station in the catalog (receiver index \(r.stationIndex))");
      return;
    }
    let count = ArraySize(r.station.tracks);
    if count < 2 { return; }
    let current = this.CurrentIndex(gi, r);
    let streamer = this.IsStreamerMode(gi);
    let picked: Int32 = this.Find(gi, r.station, current, forward, streamer, true);
    if picked < 0 {
      // Nothing else qualifies, and that is two different situations. The station may have one
      // song left on and it is the one already playing, in which case a press has nowhere to go;
      // or it may have none at all, which is the only case that steps through the switched-off
      // songs. Reading the first as the second sends the press to a song the player switched off,
      // and the automatic skip then takes it back half a second later - heard as a snippet.
      if this.PlayableCount(gi, r.station, streamer) > 0 {
        RadioXLLog(s"\(r.station.name): nothing else is switched on, staying put");
        return;
      }
      picked = this.Find(gi, r.station, current, forward, streamer, false);
    }
    if picked < 0 || picked == current { return; }
    this.Play(gi, r, picked);
  }

  // A station key press. Moves the receiver one place along the dial, through the game's own
  // cycle, so the dial order and the skipped stations are honoured with no list of this file's
  // own. Tuning goes through the quick slots, the way My station does, so the in-car display
  // follows.
  public func StepStation(gi: GameInstance, forward: Bool) -> Void {
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) { return; }
    let r = this.Receiver(gi);
    if r.stationIndex < 0 {
      RadioXLLog("station key: nothing is playing, or the station has no index");
      return;
    }
    if !IsDefined(r.vehicle) && !IsDefined(r.pocket) {
      RadioXLLog("station key: no receiver resolved");
      return;
    }
    // A station past the provider's count is one the game cannot name: a RadioExt station, which
    // plays through its own player. Its receiver is switched off by then, so this guard is rarely
    // reached; it stands for a station that is named but off the dial.
    if r.stationIndex >= RadioStationDataProvider.GetStationsCount() {
      RadioXLLog(s"radio is on station \(r.stationIndex), outside the dial - not stepped");
      return;
    }
    let player = GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) { return; }
    let picked: ERadioStationList = forward
      ? RadioStationDataProvider.GetNextStationTo(r.stationIndex)
      : RadioStationDataProvider.GetPreviousStationTo(r.stationIndex);
    // A station the player has set aside is stepped over. The walk is bounded by the size of the
    // dial, so setting every station aside leaves the receiver where it is rather than looping.
    let tried: Int32 = 0;
    let total: Int32 = RadioStationDataProvider.GetStationsCount();
    while controls.IsStationSkipped(RadioStationDataProvider.GetStationName(picked)) && tried < total {
      picked = forward
        ? RadioStationDataProvider.GetNextStationTo(EnumInt(picked))
        : RadioStationDataProvider.GetPreviousStationTo(EnumInt(picked));
      tried += 1;
    }
    if EnumInt(picked) == r.stationIndex {
      RadioXLLog("station key: every other station is set aside");
      return;
    }
    let position: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(EnumInt(picked));
    player.GetQuickSlotsManager().SendRadioEvent(true, true, position);
    RadioXLLog(s"station stepped to \(RadioStationDataProvider.GetStationName(picked)) (enum \(EnumInt(picked)), dial \(position))");
  }

  // Puts the radio popup on screen for whatever is playing now. The controller's own show
  // method is private, so the way in is the song-changed event the game raises itself;
  // RadioXLPopup marks that event as this mod's, so it shows the popup without also being read
  // as a new song.
  public func ShowPopup(gi: GameInstance) -> Void {
    let player = GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) { return; }
    let popup = RadioXLPopup.Get();
    if !IsDefined(popup) { return; }
    let vehicle = player.GetMountedVehicle();
    if IsDefined(vehicle) && vehicle.IsRadioReceiverActive() {
      popup.Show(gi, vehicle.GetRadioReceiverTrackName());
      return;
    }
    let pocket = player.GetPocketRadio();
    if IsDefined(pocket) && pocket.IsActive() {
      popup.Show(gi, pocket.GetTrackName());
    }
  }

  // Switches the song that is playing off and moves on, so a song can be retired without opening
  // the panel and finding it among the rest.
  public func NeverAgain(gi: GameInstance) -> Void {
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) { return; }
    let r = this.Receiver(gi);
    if !r.IsValid() { return; }
    let catalog = RadioXLCatalog.Get();
    let index: Int32 = catalog.IndexOf(r.station, NameToHash(r.reported));
    if index < 0 {
      RadioXLLog("never again: the playing track is not in the catalog");
      return;
    }
    let track = r.station.tracks[index];
    controls.SetSongState(track.event, RadioXL_SongOff());
    RadioXLLog(s"\(r.station.name): \(track.event) switched off from the key");
    // The key gives no other sign it worked, so the song's name goes on screen.
    RadioXLNotify.Line(gi, RadioXLText("RadioXL.noteNeverAgain") + " " + this.TrackTitle(track));
    this.Step(gi, true);
  }

  // Tunes to the station held in My station, whether or not the automatic tuning is switched on:
  // a press is the player asking for it.
  public func JumpToMyStation(gi: GameInstance) -> Void {
    let memory = RadioXLMyStation.Get();
    let state = RadioXLState.Get();
    if !IsDefined(memory) || !IsDefined(state) { return; }
    if !IsNameValid(state.rememberStation) {
      RadioXLLog("my station key: no station is set");
      return;
    }
    let station: Int32 = memory.StationIndex();
    if station < 0 {
      RadioXLLog(s"my station key: \(state.rememberStation) is not installed");
      return;
    }
    let player = GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) { return; }
    let r = this.Receiver(gi);
    if !IsDefined(r.vehicle) && !IsDefined(r.pocket) {
      RadioXLLog("my station key: no receiver is playing");
      return;
    }
    if r.stationIndex == station {
      RadioXLLog(s"my station key: already on \(state.rememberStation)");
      return;
    }
    let position: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(station);
    player.GetQuickSlotsManager().SendRadioEvent(true, true, position);
    RadioXLLog(s"my station key: tuned to \(state.rememberStation) (enum \(station), dial \(position))");
  }

  // The engine has just started `key` on the receiver. If the player switched that track off and
  // the station still has one enabled, move on. Called from the vehicle popup's song-changed
  // handler and from the Radioport poll.
  public func Arrived(gi: GameInstance, key: Uint64) -> Void {
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) || controls.DisabledCount() == 0 { return; }
    let r = this.Receiver(gi);
    if !r.IsValid() { return; }
    let catalog = RadioXLCatalog.Get();
    let index = catalog.IndexOf(r.station, key);
    if index < 0 { return; }
    // A request is answered by the receiver a moment later, and until then the game still
    // reports the old track. A second report of that old track is the lag, not a new arrival.
    if this.m_pendingKey != 0ul {
      if key == this.m_pendingKey {
        this.m_pendingKey = 0ul;
      } else if this.Now(gi) - this.m_pendingAt < 2.0 {
        return;
      }
    }
    if controls.IsTrackEnabled(r.station.tracks[index].event) { return; }
    let picked = this.Find(gi, r.station, index, true, this.IsStreamerMode(gi), true);
    if picked < 0 || picked == index { return; }
    RadioXLLog(s"\(r.station.name): \(r.station.tracks[index].event) is switched off, moving on");
    this.Play(gi, r, picked);
  }

  // The same check against whatever the receiver reports right now.
  public func ArrivedCurrent(gi: GameInstance) -> Void {
    let r = this.Receiver(gi);
    if !r.IsValid() || !IsNameValid(r.reported) { return; }
    this.Arrived(gi, NameToHash(r.reported));
  }

  // How many of the station's tracks the game would play and the player has left on. Zero is the
  // empty station, and it is the only number that changes what a key press does.
  private func PlayableCount(gi: GameInstance, station: ref<RadioXLCatalogStation>, streamer: Bool) -> Int32 {
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) { return 0; }
    let count: Int32 = 0;
    let i: Int32 = 0;
    while i < ArraySize(station.tracks) {
      let track = station.tracks[i];
      if this.IsPlayable(gi, track, streamer) && controls.IsTrackEnabled(track.event) {
        count += 1;
      }
      i += 1;
    }
    return count;
  }

  // The first track after (or before) `from` that is playable and, when `enabledOnly`, switched
  // on. `from` may be -1 when the current track is unknown, in which case the search starts at
  // the top. Returns -1 when no other track qualifies.
  private func Find(gi: GameInstance, station: ref<RadioXLCatalogStation>, from: Int32, forward: Bool,
                    streamer: Bool, enabledOnly: Bool) -> Int32 {
    let controls = RadioXLControls.Get();
    let count = ArraySize(station.tracks);
    let step: Int32 = forward ? 1 : -1;
    let i: Int32 = from < 0 ? (forward ? 0 : count - 1) : from + step;
    let tried: Int32 = 0;
    while tried < count {
      if i < 0 { i = count - 1; }
      if i >= count { i = 0; }
      if i == from { return -1; }
      let track = station.tracks[i];
      if this.IsPlayable(gi, track, streamer) && (!enabledOnly || controls.IsTrackEnabled(track.event)) {
        return i;
      }
      i += step;
      tried += 1;
    }
    return -1;
  }

  private func Play(gi: GameInstance, r: ref<RadioXLReceiver>, index: Int32) -> Void {
    let track = r.station.tracks[index];
    GameInstance.GetAudioSystem(gi).RequestSongOnRadioStation(r.station.name, track.event);
    this.m_pendingKey = track.key;
    this.m_pendingAt = this.Now(gi);
    RadioXLLog(s"\(r.station.name): requested track \(index) \(track.event)");
  }

  // The same lookup the popup makes: the receiver reports the track as a CName built from
  // primaryLocKey, and GetLocalizedTextByKey resolves that name; the event name is the fallback.
  private func TrackTitle(track: ref<RadioXLCatalogTrack>) -> String {
    let text: String = track.key != 0ul ? GetLocalizedTextByKey(HashToName(track.key)) : "";
    if StrLen(text) == 0 && IsNameValid(track.title) {
      text = GetLocalizedText(NameToString(track.title));
    }
    return StrLen(text) > 0 ? text : NameToString(track.event);
  }

  private func Now(gi: GameInstance) -> Float {
    return EngineTime.ToFloat(GameInstance.GetSimTime(gi));
  }
}
