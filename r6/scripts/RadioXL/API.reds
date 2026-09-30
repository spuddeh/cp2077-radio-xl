// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The script API: what other mods read from RadioXL, ask it to do, and hear from it.
// File Version: 0.5.1
// ======================================================================================
//
// **This class is the promise.** Every other class, function and native in RadioXL is public only
// because the module needs it, and changes between releases without notice.
//
// A station is named by its CName (`radio_station_01_att_rock`) and a song by its track event
// (`radio_station_20_tool_03`); never by a dial position, which moves when a station mod is added.
//
// From CET the class is the Lua global `RadioXL_RadioXLAPI`, and a Lua string is taken where a
// CName is asked for: `RadioXL_RadioXLAPI.Tracks("radio_station_01_att_rock")`. A returned CName
// reads as text through `.value`. Events are in Events.reds; API.md in the repository documents both.
//
// **Put an array these functions return into a `let` before `ArraySize`, `ArrayContains` or
// an index.** Redscript reads such a call's result from uninitialised memory otherwise, which can
// crash the game: `let tracks = RadioXLAPI.Tracks(station); ArraySize(tracks)`.
//
// `Version()` goes up only when something here changes in a way that breaks a caller. A function
// added is not a break.
//
// A station built for RadioXL 0.1.0 registers itself with `RegisterStation`. That call has to exist,
// or the station mod fails script validation and takes every redscript mod on the machine down with
// it. Adopting such a station outright is issue #10; until then the call is answered and logged,
// and the station is not created.

module RadioXL

import Codeware.Localization.*

// What a song is set to in RadioXL's Stations tab. `StreamerOff` hides it while Streamer Mode is on.
public enum RadioXLSongState {
  On = 0,
  Off = 1,
  StreamerOff = 2,
}

// A stream station's connection. `Blocked` is AudioXL.ini not allowing http, which only the player
// can change.
public enum RadioXLStreamState {
  NotStream = 0,
  Blocked = 1,
  Connecting = 2,
  Live = 3,
  Failed = 4,
}

public abstract class RadioXLAPI {
  public final static func Version() -> Int32 {
    return 1;
  }

  public final static func RegisterStation(name: String) -> Void {
    RadioXLLog(s"RegisterStation(\"\(name)\"): a RadioXL 0.1.0 station definition. A station.json manifest is what makes it play; adopting the old shape unchanged is issue #10");
  }

  // --- stations ----------------------------------------------------------------------------------

  // True once every station and track has been read, which is also when `RadioXL/Ready` fires.
  public final static func IsReady() -> Bool {
    let catalog = RadioXLCatalog.Get();
    return IsDefined(catalog) && catalog.IsBuilt();
  }

  // Every station, vanilla and custom, in dial order.
  public final static func Stations() -> array<CName> {
    let out: array<CName>;
    let count: Int32 = RadioStationDataProvider.GetStationsCount();
    let position: Int32 = 0;
    while position < count {
      ArrayPush(out, RadioStationDataProvider.GetStationName(RadioStationDataProvider.GetRadioStationByUIIndex(position)));
      position += 1;
    }
    return out;
  }

  // The label the game shows, frequency first, in the player's language.
  public final static func StationName(station: CName) -> String {
    let e: Int32 = RadioXLAPI.EnumOf(station);
    if e < 0 { return ""; }
    let slot: Int32 = RadioXLDial.Slot(e);
    if slot >= 0 { return RadioXL_StationDisplayName(slot); }
    return GetLocalizedTextByKey(StringToName(RadioStationDataProvider.GetChannelName(IntEnum<ERadioStationList>(e))));
  }

  // -1 when the station is unknown.
  public final static func StationFrequency(station: CName) -> Float {
    let e: Int32 = RadioXLAPI.EnumOf(station);
    return e < 0 ? -1.0 : RadioXL_Frequency(e);
  }

  // The station's place in the dial, from 0. It moves when a station mod is added or removed.
  public final static func StationDialPosition(station: CName) -> Int32 {
    let e: Int32 = RadioXLAPI.EnumOf(station);
    return e < 0 ? -1 : RadioStationDataProvider.GetRadioStationUIIndex(e);
  }

  // The station's UIIcon record.
  public final static func StationIcon(station: CName) -> TweakDBID {
    let e: Int32 = RadioXLAPI.EnumOf(station);
    if e < 0 { return TDBID.None(); }
    let record = TweakDBInterface.GetRadioStationRecord(RadioXLDial.StationRecord(e));
    let icon = IsDefined(record) ? record.Icon() : null;
    return IsDefined(icon) ? icon.GetID() : TDBID.None();
  }

  public final static func IsCustomStation(station: CName) -> Bool {
    return RadioXLAPI.SlotOf(station) >= 0;
  }

  // The folder the station's manifest is installed in; "" for a vanilla station.
  public final static func StationMod(station: CName) -> String {
    let slot: Int32 = RadioXLAPI.SlotOf(station);
    return slot < 0 ? "" : RadioXL_StationSource(slot);
  }

  // Whether the news reaches the station. True for all fourteen vanilla stations.
  public final static func StationHasNews(station: CName) -> Bool {
    let e: Int32 = RadioXLAPI.EnumOf(station);
    if e < 0 { return false; }
    let slot: Int32 = RadioXLDial.Slot(e);
    return slot < 0 || RadioXL_StationNews(slot);
  }

  public final static func IsStreamStation(station: CName) -> Bool {
    let slot: Int32 = RadioXLAPI.SlotOf(station);
    return slot >= 0 && RadioXL_StationTrackCount(slot) > 0 && RadioXLAudio.IsStream(RadioXL_StationTrackFile(slot, 0));
  }

  public final static func StreamState(station: CName) -> RadioXLStreamState {
    if !RadioXLAPI.IsStreamStation(station) { return RadioXLStreamState.NotStream; }
    if !RadioXLAudio.HttpAllowed() { return RadioXLStreamState.Blocked; }
    let event: CName = RadioXL_StationTrack(RadioXLAPI.SlotOf(station), 0);
    if RadioXLAudio.Has(event) { return RadioXLStreamState.Live; }
    let service = RadioXLService.Get();
    if IsDefined(service) && service.IsRefused(event) { return RadioXLStreamState.Failed; }
    // AudioXL drops a URL it could not reach from its pending list without making a row.
    if IsDefined(service) && service.IsAudioDone() && RadioXLAudio.PendingStreams() == 0 {
      return RadioXLStreamState.Failed;
    }
    return RadioXLStreamState.Connecting;
  }

  // The station's description in the player's language; "" when it has none, which every vanilla
  // station is. RadioXL itself shows it nowhere.
  public final static func StationDescription(station: CName) -> String {
    let slot: Int32 = RadioXLAPI.SlotOf(station);
    if slot < 0 { return ""; }
    let language: String = "en-us";
    let loc = LocalizationSystem.GetInstance(GetGameInstance());
    if IsDefined(loc) && IsNameValid(loc.GetInterfaceLanguage()) { language = NameToString(loc.GetInterfaceLanguage()); }
    return RadioXL_StationDescription(slot, language);
  }

  // What the station's manifest carries for one mod under `extensions`, as JSON text; "" when
  // nothing. RadioXL reads none of it.
  public final static func StationExtension(station: CName, mod: String) -> String {
    let slot: Int32 = RadioXLAPI.SlotOf(station);
    return slot < 0 ? "" : RadioXL_StationExtension(slot, mod);
  }

  // --- tracks ------------------------------------------------------------------------------------

  // The station's songs by track event, idents left out. The list is the engine's live one, so
  // songs a quest adds during a session are included.
  public final static func Tracks(station: CName) -> array<CName> {
    let out: array<CName>;
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(catalog) { return out; }
    catalog.Refresh(station);
    let s = catalog.Station(station);
    if !IsDefined(s) { return out; }
    for track in s.tracks {
      ArrayPush(out, track.event);
    }
    return out;
  }

  public final static func Idents(station: CName) -> array<CName> {
    let catalog = RadioXLCatalog.Get();
    let none: array<CName>;
    return IsDefined(catalog) ? catalog.Idents(station) : none;
  }

  // The song's title in the player's language; the track event when it has none.
  public final static func TrackTitle(track: CName) -> String {
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(catalog) { return ""; }
    return catalog.TitleOf(catalog.Track(catalog.Owner(track), track));
  }

  // Seconds. A custom song's is read from its file; a vanilla song's is the length its station
  // schedules against, a little under the recording.
  public final static func TrackLength(track: CName) -> Float {
    let slot: Int32;
    let index: Int32;
    if RadioXLAPI.CustomTrack(track, slot, index) {
      return RadioXL_StationTrackDuration(slot, index);
    }
    let service = RadioXLService.Get();
    return IsDefined(service) ? service.EventDuration(track) : 0.0;
  }

  // The game's own streamer flag. The player's choice is SongState.
  public final static func IsStreamingFriendly(track: CName) -> Bool {
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(catalog) { return true; }
    let t = catalog.Track(catalog.Owner(track), track);
    return !IsDefined(t) || t.streamingFriendly;
  }

  // A custom song's audio file, the full path; "" for a stream or a vanilla song.
  public final static func TrackFile(track: CName) -> String {
    let slot: Int32;
    let index: Int32;
    if !RadioXLAPI.CustomTrack(track, slot, index) { return ""; }
    let file: String = RadioXL_StationTrackFile(slot, index);
    return RadioXLAudio.IsStream(file) ? "" : file;
  }

  // The level RadioXL plays a custom song at: the station's gain times the song's own. 1 for a
  // vanilla song.
  public final static func TrackGain(track: CName) -> Float {
    let slot: Int32;
    let index: Int32;
    if !RadioXLAPI.CustomTrack(track, slot, index) { return 1.0; }
    return RadioXL_StationGain(slot) * RadioXL_StationTrackGain(slot, index);
  }

  // --- the player's choices ----------------------------------------------------------------------

  public final static func SongState(track: CName) -> RadioXLSongState {
    let controls = RadioXLControls.Get();
    return IsDefined(controls) ? IntEnum<RadioXLSongState>(controls.SongState(track)) : RadioXLSongState.On;
  }

  // Whether RadioXL itself would play the song now: not switched off, not hidden while Streamer
  // Mode is on, and not held back by a quest. A mod building its own pool of songs checks this.
  public final static func IsSongPlayable(track: CName) -> Bool {
    let catalog = RadioXLCatalog.Get();
    let deck = RadioXLDeck.Get();
    if !IsDefined(catalog) || !IsDefined(deck) { return false; }
    return deck.CanPlay(GetGameInstance(), catalog.Track(catalog.Owner(track), track));
  }

  public final static func MyStation() -> CName {
    let state = RadioXLState.Get();
    return IsDefined(state) ? state.rememberStation : n"None";
  }

  // Whether the station keys step over the station.
  public final static func IsStationSkipped(station: CName) -> Bool {
    let controls = RadioXLControls.Get();
    return IsDefined(controls) && controls.IsStationSkipped(station);
  }

  public final static func IdentsMuted() -> Bool {
    let state = RadioXLState.Get();
    return IsDefined(state) && state.muteIdents;
  }

  public final static func NewsMuted() -> Bool {
    let state = RadioXLState.Get();
    return IsDefined(state) && state.muteNews;
  }

  // --- what is playing ---------------------------------------------------------------------------

  public final static func Receiver() -> RadioXLReceiverKind {
    let deck = RadioXLDeck.Get();
    if !IsDefined(deck) { return RadioXLReceiverKind.None; }
    let gi = GetGameInstance();
    return RadioXLEvents.KindOf(gi, deck.Receiver(gi));
  }

  public final static func CurrentStation() -> CName {
    let deck = RadioXLDeck.Get();
    if !IsDefined(deck) { return n"None"; }
    let gi = GetGameInstance();
    let r = deck.Receiver(gi);
    return r.IsValid() && NotEquals(RadioXLEvents.KindOf(gi, r), RadioXLReceiverKind.None) ? r.station.name : n"None";
  }

  public final static func CurrentTrack() -> CName {
    let deck = RadioXLDeck.Get();
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(deck) || !IsDefined(catalog) { return n"None"; }
    let gi = GetGameInstance();
    let r = deck.Receiver(gi);
    if !r.IsValid() || Equals(RadioXLEvents.KindOf(gi, r), RadioXLReceiverKind.None) { return n"None"; }
    let index: Int32 = catalog.IndexOf(r.station, NameToHash(r.reported));
    return index >= 0 ? r.station.tracks[index].event : n"None";
  }

  // The station's songs not yet played this cycle. The engine picks among them at random, so the
  // order means nothing.
  public final static func Remaining(station: CName) -> array<CName> {
    return RadioXL_StationRemaining(station);
  }

  // Seconds into the song the station is on, from the engine's own station clock. A station runs
  // whether or not anyone is listening. -1 when the station cannot be read.
  public final static func Position(station: CName) -> Float {
    let seconds: Float = RadioXL_StationPosition(station);
    return seconds < 0.0 ? -1.0 : seconds;
  }

  // The songs played on the station being listened to, oldest first, at most 32. It starts again
  // when the station changes, and it is empty when nothing is playing.
  public final static func History() -> array<CName> {
    let deck = RadioXLDeck.Get();
    let none: array<CName>;
    if !IsDefined(deck) || NotEquals(deck.HistoryStation(), RadioXLAPI.CurrentStation()) { return none; }
    return deck.History();
  }

  // The song in History that is playing now, as an index into it; -1 when History is empty. It
  // sits before the end after a previous-song key.
  public final static func HistoryCursor() -> Int32 {
    let deck = RadioXLDeck.Get();
    if !IsDefined(deck) || NotEquals(deck.HistoryStation(), RadioXLAPI.CurrentStation()) { return -1; }
    return deck.HistoryCursor();
  }

  // The "Mute the radio when..." situations silencing the Radioport now, by PocketRadioRestrictions
  // member name. Only those whose switch is on are listed: the others are let through.
  public final static func SilencedBy() -> array<CName> {
    let out: array<CName>;
    let state = RadioXLRestrictions.Get();
    let cfg = RadioXLConfig.Get();
    if !IsDefined(state) || !IsDefined(cfg) { return out; }
    let i: Int32 = 0;
    while i < EnumInt(PocketRadioRestrictions.PocketRadioRestrictionCount) {
      if state.Actual(i) && cfg.MutesOn(i) {
        ArrayPush(out, EnumValueToName(n"PocketRadioRestrictions", Cast<Int64>(i)));
      }
      i += 1;
    }
    return out;
  }

  // --- acting ------------------------------------------------------------------------------------
  // Every song change goes through RadioXL's own deck, so the station's schedule, its ident count
  // and the history stay right. Each returns false when nothing happened.

  public final static func NextSong() -> Bool {
    return RadioXLAPI.Step(true);
  }

  public final static func PreviousSong() -> Bool {
    return RadioXLAPI.Step(false);
  }

  // Plays a named song on its station now. Refused for a song the player switched off or the game
  // would not play (IsSongPlayable).
  public final static func PlaySong(station: CName, track: CName) -> Bool {
    let deck = RadioXLDeck.Get();
    return IsDefined(deck) && deck.Request(GetGameInstance(), station, track);
  }

  public final static func NextStation() -> Bool {
    return RadioXLAPI.StepStation(true);
  }

  public final static func PreviousStation() -> Bool {
    return RadioXLAPI.StepStation(false);
  }

  // Tunes the radio that is playing to the station.
  public final static func TuneStation(station: CName) -> Bool {
    let deck = RadioXLDeck.Get();
    let e: Int32 = RadioXLAPI.EnumOf(station);
    return IsDefined(deck) && e >= 0 && deck.Tune(GetGameInstance(), e, "script API");
  }

  // Sets a song the way the Stations tab does, and saves it. Switching off the song that is playing
  // moves on to another.
  public final static func SetSongState(track: CName, state: RadioXLSongState) -> Bool {
    let controls = RadioXLControls.Get();
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(controls) || !IsDefined(catalog) || !IsDefined(catalog.Owner(track)) { return false; }
    let value: Int32 = EnumInt(state);
    if !controls.SetSongState(track, value) { return false; }
    RadioXLConfig.Persist();
    RadioXLEvents.SongStateChanged(track, value);
    if Equals(RadioXLAPI.CurrentTrack(), track) {
      let deck = RadioXLDeck.Get();
      if IsDefined(deck) { deck.ArrivedCurrent(GetGameInstance()); }
    }
    return true;
  }

  public final static func SetStationSkipped(station: CName, skipped: Bool) -> Bool {
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) || RadioXLAPI.EnumOf(station) < 0 { return false; }
    if !controls.SetStationSkipped(station, skipped) { return false; }
    RadioXLConfig.Persist();
    RadioXLEvents.StationSkipChanged(station, skipped);
    return true;
  }

  // `n"None"` clears it.
  public final static func SetMyStation(station: CName) -> Bool {
    let state = RadioXLState.Get();
    let clear: Bool = !IsNameValid(station);
    if clear { station = n"None"; }
    if !IsDefined(state) || (!clear && RadioXLAPI.EnumOf(station) < 0) || Equals(state.rememberStation, station) { return false; }
    state.SetRememberStation(station);
    return true;
  }

  public final static func SetIdentsMuted(muted: Bool) -> Bool {
    let state = RadioXLState.Get();
    if !IsDefined(state) || Equals(state.muteIdents, muted) { return false; }
    state.SetMuteIdents(muted);
    return true;
  }

  public final static func SetNewsMuted(muted: Bool) -> Bool {
    let state = RadioXLState.Get();
    if !IsDefined(state) || Equals(state.muteNews, muted) { return false; }
    state.SetMuteNews(muted);
    return true;
  }

  // The radio popup when `popup` is set, else the on-screen line, for the song playing now.
  public final static func ShowNowPlaying(popup: Bool) -> Bool {
    let gi = GetGameInstance();
    let deck = RadioXLDeck.Get();
    if !IsDefined(deck) { return false; }
    let r = deck.Receiver(gi);
    if !r.IsValid() { return false; }
    if popup {
      deck.ShowPopup(gi);
    } else {
      RadioXLNotify.Onscreen(gi, StringToName(RadioStationDataProvider.GetChannelName(IntEnum<ERadioStationList>(r.stationIndex))), r.reported);
    }
    return true;
  }

  // --- helpers -----------------------------------------------------------------------------------

  private final static func Step(forward: Bool) -> Bool {
    let deck = RadioXLDeck.Get();
    if !IsDefined(deck) || !deck.Receiver(GetGameInstance()).IsValid() { return false; }
    deck.Step(GetGameInstance(), forward);
    return true;
  }

  private final static func StepStation(forward: Bool) -> Bool {
    let deck = RadioXLDeck.Get();
    if !IsDefined(deck) || deck.Receiver(GetGameInstance()).stationIndex < 0 { return false; }
    deck.StepStation(GetGameInstance(), forward);
    return true;
  }

  // The station's ERadioStationList value, vanilla or custom; -1 when it is not installed.
  private final static func EnumOf(station: CName) -> Int32 {
    if !IsNameValid(station) { return -1; }
    let count: Int32 = RadioStationDataProvider.GetStationsCount();
    let i: Int32 = 0;
    while i < count {
      if Equals(RadioStationDataProvider.GetStationName(IntEnum<ERadioStationList>(i)), station) { return i; }
      i += 1;
    }
    return -1;
  }

  // The station's index among the custom stations; -1 for a vanilla or unknown one.
  private final static func SlotOf(station: CName) -> Int32 {
    let e: Int32 = RadioXLAPI.EnumOf(station);
    return e < 0 ? -1 : RadioXLDial.Slot(e);
  }

  // Where a custom song sits in its manifest, idents counted, as the natives number it.
  private final static func CustomTrack(track: CName, out slot: Int32, out index: Int32) -> Bool {
    let count: Int32 = RadioXL_StationCount();
    slot = 0;
    while slot < count {
      let tracks: Int32 = RadioXL_StationTrackCount(slot);
      index = 0;
      while index < tracks {
        if Equals(RadioXL_StationTrack(slot, index), track) { return true; }
        index += 1;
      }
      slot += 1;
    }
    slot = -1;
    index = -1;
    return false;
  }
}
