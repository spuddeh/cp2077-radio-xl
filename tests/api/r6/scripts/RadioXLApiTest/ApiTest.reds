// ======================================================================================
// Mod Name: RadioXL API Test
// Author: Spuddeh
// Description: Runs every RadioXLAPI function and checks every event, in game. A test harness:
//              deployed to the Testing instance on its own, never shipped.
// File Version: 0.5.1
// ======================================================================================
//
// Start it with a save loaded, on foot, from the CET console or the live bridge:
//
//   RadioXLApiTest_RadioXLApiTest.Start()
//
// and read the result once `Running()` is false, about 40 seconds later:
//
//   print(RadioXLApiTest_RadioXLApiTest.Report())
//
// The run uses the Radioport. It switches it on if it is off, changes station and song, flips each
// setting and puts every one back, and leaves the radio as it found it. It listens to the events
// the way a redscript mod does, registered by name in OnLoad; the CET route is checked from the
// bridge with Observe.

module RadioXLApiTest

import RadioXL.*

public class RadioXLApiTestTick extends DelayCallback {
  public let runner: wref<RadioXLApiTest>;
  public let step: Int32;

  public func Call() -> Void {
    if IsDefined(this.runner) { this.runner.Step(this.step); }
  }
}

public class RadioXLApiTest extends ScriptableService {
  private let m_events: array<String>;
  private let m_counts: array<Int32>;
  private let m_lasts: array<String>;

  private let m_lines: array<String>;
  private let m_passed: Int32;
  private let m_failed: Int32;
  private let m_running: Bool;

  // What the run changes, so it can be put back, and what it has seen so far.
  private let m_wasOn: Bool;
  private let m_wasStation: CName;
  private let m_station: CName;
  private let m_seen: array<CName>;
  private let m_track: CName;
  private let m_position: Float;
  private let m_mark: array<Int32>;

  public final static func Get() -> ref<RadioXLApiTest> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXLApiTest.RadioXLApiTest") as RadioXLApiTest;
  }

  // --- the events, as a redscript consumer registers them -----------------------------------------

  private cb func OnLoad() {
    let cs = GameInstance.GetCallbackSystem();
    cs.RegisterCallback(n"RadioXL/Ready", this, n"OnReady", true);
    cs.RegisterCallback(n"RadioXL/SongChanged", this, n"OnSongChanged");
    cs.RegisterCallback(n"RadioXL/StationChanged", this, n"OnStationChanged");
    cs.RegisterCallback(n"RadioXL/RadioPower", this, n"OnRadioPower");
    cs.RegisterCallback(n"RadioXL/CatalogRefreshed", this, n"OnCatalogRefreshed");
    cs.RegisterCallback(n"RadioXL/SongStateChanged", this, n"OnSongStateChanged");
    cs.RegisterCallback(n"RadioXL/MutesChanged", this, n"OnMutesChanged");
    cs.RegisterCallback(n"RadioXL/Silenced", this, n"OnSilenced");
    cs.RegisterCallback(n"RadioXL/MyStationChanged", this, n"OnMyStationChanged");
    cs.RegisterCallback(n"RadioXL/StationSkipChanged", this, n"OnStationSkipChanged");
  }

  private cb func OnReady(e: ref<RadioXLReadyEvent>) { this.Heard("Ready", s"version \(e.Version()), \(e.Stations()) stations"); }
  private cb func OnSongChanged(e: ref<RadioXLSongChangedEvent>) {
    this.Heard("SongChanged", s"\(e.Station()) \(e.Track()) \(EnumInt(e.Receiver())) requested=\(e.Requested())");
  }
  private cb func OnStationChanged(e: ref<RadioXLStationChangedEvent>) {
    this.Heard("StationChanged", s"\(e.Previous()) -> \(e.Station()) \(EnumInt(e.Receiver()))");
  }
  private cb func OnRadioPower(e: ref<RadioXLRadioPowerEvent>) { this.Heard("RadioPower", s"\(EnumInt(e.Receiver())) on=\(e.On())"); }
  private cb func OnCatalogRefreshed(e: ref<RadioXLCatalogRefreshedEvent>) { this.Heard("CatalogRefreshed", s"\(e.Station()) +\(e.Added())"); }
  private cb func OnSongStateChanged(e: ref<RadioXLSongStateChangedEvent>) { this.Heard("SongStateChanged", s"\(e.Track()) \(EnumInt(e.State()))"); }
  private cb func OnMutesChanged(e: ref<RadioXLMutesChangedEvent>) { this.Heard("MutesChanged", s"idents=\(e.Idents()) news=\(e.News())"); }
  private cb func OnSilenced(e: ref<RadioXLSilencedEvent>) { this.Heard("Silenced", s"\(e.Restriction()) \(e.Silenced())"); }
  private cb func OnMyStationChanged(e: ref<RadioXLMyStationChangedEvent>) { this.Heard("MyStationChanged", s"\(e.Station())"); }
  private cb func OnStationSkipChanged(e: ref<RadioXLStationSkipChangedEvent>) { this.Heard("StationSkipChanged", s"\(e.Station()) \(e.Skipped())"); }

  private func At(event: String) -> Int32 {
    let i: Int32 = 0;
    while i < ArraySize(this.m_events) {
      if Equals(this.m_events[i], event) { return i; }
      i += 1;
    }
    ArrayPush(this.m_events, event);
    ArrayPush(this.m_counts, 0);
    ArrayPush(this.m_lasts, "");
    return ArraySize(this.m_events) - 1;
  }

  private func Heard(event: String, detail: String) -> Void {
    let i: Int32 = this.At(event);
    this.m_counts[i] += 1;
    this.m_lasts[i] = detail;
  }

  // How many times an event has arrived, and what the last one carried. Readable from CET.
  public func Count(event: String) -> Int32 { return this.m_counts[this.At(event)]; }
  public func Last(event: String) -> String { return this.m_lasts[this.At(event)]; }

  // Remembers every count, so a step can ask how many arrived since.
  private func Mark() -> Void {
    ArrayClear(this.m_mark);
    let names: array<String> = ["Ready", "SongChanged", "StationChanged", "RadioPower", "CatalogRefreshed",
                                "SongStateChanged", "MutesChanged", "Silenced", "MyStationChanged", "StationSkipChanged"];
    for name in names { this.At(name); }
    for count in this.m_counts { ArrayPush(this.m_mark, count); }
  }

  private func Since(event: String) -> Int32 {
    let i: Int32 = this.At(event);
    return i < ArraySize(this.m_mark) ? this.m_counts[i] - this.m_mark[i] : this.m_counts[i];
  }

  // --- the report ---------------------------------------------------------------------------------

  private func Check(label: String, ok: Bool, detail: String) -> Void {
    if ok { this.m_passed += 1; } else { this.m_failed += 1; }
    ArrayPush(this.m_lines, (ok ? "PASS  " : "FAIL  ") + label + (StrLen(detail) > 0 ? "  (" + detail + ")" : ""));
  }

  private func Note(text: String) -> Void {
    ArrayPush(this.m_lines, "      " + text);
  }

  public final static func Running() -> Bool {
    let self = RadioXLApiTest.Get();
    return IsDefined(self) && self.m_running;
  }

  public final static func Report() -> String {
    let self = RadioXLApiTest.Get();
    if !IsDefined(self) { return "RadioXLApiTest is not loaded"; }
    let out: String = s"RadioXL API test: \(self.m_passed) passed, \(self.m_failed) failed\(self.m_running ? " (still running)" : "")";
    for line in self.m_lines { out += "\n" + line; }
    return out;
  }

  // --- the run ------------------------------------------------------------------------------------

  public final static func Start() -> Bool {
    let self = RadioXLApiTest.Get();
    if !IsDefined(self) || self.m_running { return false; }
    ArrayClear(self.m_lines);
    ArrayClear(self.m_seen);
    self.m_passed = 0;
    self.m_failed = 0;
    self.m_running = true;
    self.Step(0);
    return true;
  }

  private func Next(step: Int32, seconds: Float) -> Void {
    let tick = new RadioXLApiTestTick();
    tick.runner = this;
    tick.step = step;
    GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(tick, seconds);
  }

  private func Finish() -> Void {
    this.m_running = false;
    this.Note("Not exercised here: CatalogRefreshed (a quest adding songs) and Silenced (a phone call or a scene).");
  }

  private func Player() -> ref<PlayerPuppet> {
    return GameInstance.GetPlayerSystem(GetGameInstance()).GetLocalPlayerMainGameObject() as PlayerPuppet;
  }

  // The Radioport on at a station, or off with `station` set to None.
  private func Radioport(station: CName) -> Void {
    let player = this.Player();
    if !IsDefined(player) { return; }
    let position: Int32 = IsNameValid(station) ? RadioXLAPI.StationDialPosition(station) : -1;
    player.GetQuickSlotsManager().SendRadioEvent(position >= 0, true, position);
  }

  public func Step(step: Int32) -> Void {
    switch step {
      case 0: this.Reads(); break;
      case 1: this.PowerOn(); break;
      case 2: this.Tune(); break;
      case 3: this.FirstNext(); break;
      case 4: this.SecondNext(); break;
      case 5: this.Previous(); break;
      case 6: this.Forward(); break;
      case 7: this.Play(); break;
      case 8: this.SwitchOff(); break;
      case 9: this.Settings(); break;
      case 10: this.Clock(); break;
      case 11: this.PowerOff(); break;
      case 12: this.Restore(); break;
      default: this.Finish();
    }
  }

  // Everything that needs no radio playing.
  private func Reads() -> Void {
    this.Check("Ready arrived, registered sticky in OnLoad", this.Count("Ready") >= 1, this.Last("Ready"));
    this.Check("Version() is 1", RadioXLAPI.Version() == 1, s"\(RadioXLAPI.Version())");
    this.Check("IsReady()", RadioXLAPI.IsReady(), "");

    let stations: array<CName> = RadioXLAPI.Stations();
    let total: Int32 = RadioStationDataProvider.GetStationsCount();
    this.Check("Stations() lists every station", ArraySize(stations) == total, s"\(ArraySize(stations)) of \(total)");

    let vanilla: Int32 = 0;
    let dialOk: Bool = true;
    let namesOk: Bool = true;
    let frequencyOk: Bool = true;
    let iconOk: Bool = true;
    let customOk: Bool = true;
    let newsOk: Bool = true;
    let streamOk: Bool = true;
    let descriptionOk: Bool = true;
    let tracksOk: Bool = true;
    let trackCount: Int32 = 0;
    let bad: String = "";
    let i: Int32 = 0;
    while i < ArraySize(stations) {
      let st: CName = stations[i];
      let custom: Bool = RadioXLAPI.IsCustomStation(st);
      if !custom { vanilla += 1; }
      if RadioXLAPI.StationDialPosition(st) != i { dialOk = false; bad += s" dial:\(st)"; }
      if StrLen(RadioXLAPI.StationName(st)) == 0 { namesOk = false; bad += s" name:\(st)"; }
      let f: Float = RadioXLAPI.StationFrequency(st);
      if f < 10.0 || f >= 1000.0 { frequencyOk = false; bad += s" freq:\(st)"; }
      if !TDBID.IsValid(RadioXLAPI.StationIcon(st)) { iconOk = false; bad += s" icon:\(st)"; }
      if NotEquals(custom, StrLen(RadioXLAPI.StationMod(st)) > 0) { customOk = false; bad += s" mod:\(st)"; }
      if !custom && !RadioXLAPI.StationHasNews(st) { newsOk = false; }
      if NotEquals(RadioXLAPI.IsStreamStation(st), NotEquals(RadioXLAPI.StreamState(st), RadioXLStreamState.NotStream)) {
        streamOk = false; bad += s" stream:\(st)";
      }
      if !custom && StrLen(RadioXLAPI.StationDescription(st)) > 0 { descriptionOk = false; }
      let tracks: array<CName> = RadioXLAPI.Tracks(st);
      if ArraySize(tracks) == 0 { tracksOk = false; bad += s" tracks:\(st)"; }
      for t in tracks {
        trackCount += 1;
        if StrLen(RadioXLAPI.TrackTitle(t)) == 0 { tracksOk = false; bad += s" title:\(t)"; }
        if RadioXLAPI.TrackLength(t) <= 0.0 { tracksOk = false; bad += s" length:\(t)"; }
        let file: String = RadioXLAPI.TrackFile(t);
        if !custom && (StrLen(file) > 0 || RadioXLAPI.TrackGain(t) != 1.0) { tracksOk = false; bad += s" vanillafile:\(t)"; }
        if custom && !RadioXLAPI.IsStreamStation(st) && StrLen(file) == 0 { tracksOk = false; bad += s" file:\(t)"; }
        if RadioXLAPI.TrackGain(t) <= 0.0 { tracksOk = false; bad += s" gain:\(t)"; }
      }
      i += 1;
    }
    this.Check("fourteen vanilla stations", vanilla == 14, s"\(vanilla)");
    this.Check("StationDialPosition matches the Stations() order", dialOk, "");
    this.Check("StationName for every station", namesOk, "");
    this.Check("StationFrequency in range for every station", frequencyOk, "");
    this.Check("Morro Rock is 107.3", AbsF(RadioXLAPI.StationFrequency(n"radio_station_01_att_rock") - 107.3) < 0.01,
               s"\(RadioXLAPI.StationFrequency(n"radio_station_01_att_rock"))");
    this.Check("StationIcon is a record for every station", iconOk, "");
    this.Check("StationMod set exactly for custom stations", customOk, "");
    this.Check("StationHasNews true for the fourteen", newsOk, "");
    this.Check("StreamState agrees with IsStreamStation", streamOk, "");
    this.Check("no vanilla station has a description", descriptionOk, "");
    this.Check(s"every track has a title, a length, a gain, and a file exactly when custom (\(trackCount) tracks)", tracksOk, "");
    if StrLen(bad) > 0 { this.Note("faults:" + bad); }

    let noTracks: array<CName> = RadioXLAPI.Tracks(n"radioxl_no_such_station");
    this.Check("an unknown station reads empty", StrLen(RadioXLAPI.StationName(n"radioxl_no_such_station")) == 0
               && RadioXLAPI.StationFrequency(n"radioxl_no_such_station") < 0.0
               && ArraySize(noTracks) == 0, "");
    this.Check("an unknown station is refused", !RadioXLAPI.TuneStation(n"radioxl_no_such_station")
               && !RadioXLAPI.PlaySong(n"radioxl_no_such_station", n"radioxl_no_such_track")
               && !RadioXLAPI.SetStationSkipped(n"radioxl_no_such_station", true), "");
    this.Check("StationExtension for a mod with nothing is empty", StrLen(RadioXLAPI.StationExtension(stations[0], "RadioXLApiTest")) == 0, "");
    let silenced: array<CName> = RadioXLAPI.SilencedBy();
    this.Note(s"SilencedBy: \(ArraySize(silenced)) situation(s); MyStation \(RadioXLAPI.MyStation()); idents muted \(RadioXLAPI.IdentsMuted()); news muted \(RadioXLAPI.NewsMuted())");

    if Equals(RadioXLAPI.Receiver(), RadioXLReceiverKind.Vehicle) {
      this.Note("In a vehicle: the receiver steps use the Radioport. Get out and run it again.");
      this.Finish();
      return;
    }
    this.m_wasOn = Equals(RadioXLAPI.Receiver(), RadioXLReceiverKind.Radioport);
    this.m_wasStation = RadioXLAPI.CurrentStation();
    this.Next(1, 0.5);
  }

  private func PowerOn() -> Void {
    this.Mark();
    if !this.m_wasOn {
      let stations: array<CName> = RadioXLAPI.Stations();
      this.Radioport(stations[0]);
      this.Next(2, 2.5);
      return;
    }
    this.Next(2, 0.1);
  }

  // Tunes to a station other than the one playing: a custom one when there is one.
  private func Tune() -> Void {
    this.Check("the Radioport is on", Equals(RadioXLAPI.Receiver(), RadioXLReceiverKind.Radioport), s"\(EnumInt(RadioXLAPI.Receiver()))");
    if !this.m_wasOn {
      this.Check("RadioPower on arrived", this.Since("RadioPower") >= 1 && StrContains(this.Last("RadioPower"), "on=true"), this.Last("RadioPower"));
    }
    let current: CName = RadioXLAPI.CurrentStation();
    let target: CName = n"None";
    let stations: array<CName> = RadioXLAPI.Stations();
    for st in stations {
      let tracks: array<CName> = RadioXLAPI.Tracks(st);
      if NotEquals(st, current) && !RadioXLAPI.IsStreamStation(st) && ArraySize(tracks) >= 3 {
        if !IsNameValid(target) || (RadioXLAPI.IsCustomStation(st) && !RadioXLAPI.IsCustomStation(target)) { target = st; }
      }
    }
    this.m_station = target;
    this.Note(s"testing on \(target)");
    this.Mark();
    this.Check("TuneStation to another station", RadioXLAPI.TuneStation(target), s"\(target)");
    this.Check("TuneStation to the station already playing is refused", !RadioXLAPI.TuneStation(current), "");
    this.Next(3, 3.0);
  }

  private func FirstNext() -> Void {
    this.Check("CurrentStation is the tuned station", Equals(RadioXLAPI.CurrentStation(), this.m_station), s"\(RadioXLAPI.CurrentStation())");
    this.Check("StationChanged arrived once", this.Since("StationChanged") == 1, s"\(this.Since("StationChanged")): \(this.Last("StationChanged"))");
    this.m_track = RadioXLAPI.CurrentTrack();
    let tracks: array<CName> = RadioXLAPI.Tracks(this.m_station);
    this.Check("CurrentTrack is one of the station's songs", ArrayContains(tracks, this.m_track), s"\(this.m_track)");
    ArrayPush(this.m_seen, this.m_track);
    this.Mark();
    this.Check("NextSong", RadioXLAPI.NextSong(), "");
    this.Next(4, 3.0);
  }

  private func SecondNext() -> Void {
    let now: CName = RadioXLAPI.CurrentTrack();
    this.Check("NextSong changed the song", NotEquals(now, this.m_track) && IsNameValid(now), s"\(this.m_track) -> \(now)");
    this.Check("SongChanged arrived, requested", this.Since("SongChanged") >= 1 && StrContains(this.Last("SongChanged"), "requested=true"),
               s"\(this.Since("SongChanged")): \(this.Last("SongChanged"))");
    ArrayPush(this.m_seen, now);
    this.m_track = now;
    this.Mark();
    RadioXLAPI.NextSong();
    this.Next(5, 3.0);
  }

  private func Previous() -> Void {
    let now: CName = RadioXLAPI.CurrentTrack();
    ArrayPush(this.m_seen, now);
    let history: array<CName> = RadioXLAPI.History();
    this.Check("History holds the songs played, in order", ArraySize(history) >= 3
               && Equals(history[ArraySize(history) - 1], now) && Equals(history[ArraySize(history) - 2], this.m_track),
               s"\(ArraySize(history)) entries");
    this.Check("HistoryCursor is the last entry", RadioXLAPI.HistoryCursor() == ArraySize(history) - 1, s"\(RadioXLAPI.HistoryCursor())");
    this.m_track = now;
    this.Mark();
    this.Check("PreviousSong", RadioXLAPI.PreviousSong(), "");
    this.Next(6, 3.0);
  }

  private func Forward() -> Void {
    let now: CName = RadioXLAPI.CurrentTrack();
    let expected: CName = this.m_seen[ArraySize(this.m_seen) - 2];
    this.Check("PreviousSong went back one song", Equals(now, expected), s"\(now), expected \(expected)");
    let history: array<CName> = RadioXLAPI.History();
    this.Check("HistoryCursor stepped back", RadioXLAPI.HistoryCursor() == ArraySize(history) - 2, s"\(RadioXLAPI.HistoryCursor())");
    this.Mark();
    RadioXLAPI.NextSong();
    this.Next(7, 3.0);
  }

  private func Play() -> Void {
    let now: CName = RadioXLAPI.CurrentTrack();
    this.Check("NextSong after PreviousSong went forward through the history", Equals(now, this.m_track), s"\(now), expected \(this.m_track)");
    let pick: CName = n"None";
    let tracks: array<CName> = RadioXLAPI.Tracks(this.m_station);
    for t in tracks {
      if !IsNameValid(pick) && NotEquals(t, now) && !ArrayContains(this.m_seen, t) && RadioXLAPI.IsSongPlayable(t) { pick = t; }
    }
    this.m_track = pick;
    this.Mark();
    this.Check("PlaySong a playable song", RadioXLAPI.PlaySong(this.m_station, pick), s"\(pick)");
    this.Next(8, 3.0);
  }

  private func SwitchOff() -> Void {
    let now: CName = RadioXLAPI.CurrentTrack();
    this.Check("PlaySong is what plays", Equals(now, this.m_track), s"\(now)");
    this.Check("SongChanged for PlaySong is requested", StrContains(this.Last("SongChanged"), "requested=true"), this.Last("SongChanged"));
    this.Mark();
    this.Check("SetSongState Off", RadioXLAPI.SetSongState(now, RadioXLSongState.Off), "");
    this.Check("SongState reads Off", Equals(RadioXLAPI.SongState(now), RadioXLSongState.Off), "");
    this.Check("a switched-off song is not playable", !RadioXLAPI.IsSongPlayable(now), "");
    this.Check("PlaySong refuses a switched-off song", !RadioXLAPI.PlaySong(this.m_station, now), "");
    this.Check("SetSongState to the same value does nothing", !RadioXLAPI.SetSongState(now, RadioXLSongState.Off), "");
    this.Check("SongStateChanged arrived once", this.Since("SongStateChanged") == 1, this.Last("SongStateChanged"));
    this.Next(9, 3.0);
  }

  private func Settings() -> Void {
    let now: CName = RadioXLAPI.CurrentTrack();
    this.Check("switching off the playing song moved on", NotEquals(now, this.m_track), s"\(now)");
    this.Check("SetSongState back On", RadioXLAPI.SetSongState(this.m_track, RadioXLSongState.On), "");

    this.Mark();
    let st: CName = this.m_station;
    let skipped: Bool = RadioXLAPI.IsStationSkipped(st);
    this.Check("SetStationSkipped", RadioXLAPI.SetStationSkipped(st, !skipped) && NotEquals(RadioXLAPI.IsStationSkipped(st), skipped), "");
    RadioXLAPI.SetStationSkipped(st, skipped);
    this.Check("StationSkipChanged arrived for both changes", this.Since("StationSkipChanged") == 2, s"\(this.Since("StationSkipChanged"))");

    let mine: CName = RadioXLAPI.MyStation();
    let stations: array<CName> = RadioXLAPI.Stations();
    let other: CName = Equals(mine, st) ? stations[0] : st;
    this.Check("SetMyStation", RadioXLAPI.SetMyStation(other) && Equals(RadioXLAPI.MyStation(), other), s"\(other)");
    RadioXLAPI.SetMyStation(mine);
    this.Check("SetMyStation put back", Equals(RadioXLAPI.MyStation(), mine), s"\(RadioXLAPI.MyStation())");
    this.Check("MyStationChanged arrived for both changes", this.Since("MyStationChanged") == 2, s"\(this.Since("MyStationChanged"))");

    let idents: Bool = RadioXLAPI.IdentsMuted();
    let news: Bool = RadioXLAPI.NewsMuted();
    this.Check("SetIdentsMuted", RadioXLAPI.SetIdentsMuted(!idents) && NotEquals(RadioXLAPI.IdentsMuted(), idents), "");
    RadioXLAPI.SetIdentsMuted(idents);
    this.Check("SetNewsMuted", RadioXLAPI.SetNewsMuted(!news) && NotEquals(RadioXLAPI.NewsMuted(), news), "");
    RadioXLAPI.SetNewsMuted(news);
    this.Check("MutesChanged arrived for all four changes", this.Since("MutesChanged") == 4, s"\(this.Since("MutesChanged"))");
    this.Check("the mutes put back", Equals(RadioXLAPI.IdentsMuted(), idents) && Equals(RadioXLAPI.NewsMuted(), news), "");

    let idents: array<CName> = RadioXLAPI.Idents(st);
    let remaining: array<CName> = RadioXLAPI.Remaining(st);
    let tracks: array<CName> = RadioXLAPI.Tracks(st);
    this.Note(s"Idents on \(st): \(ArraySize(idents)); remaining \(ArraySize(remaining)) of \(ArraySize(tracks))");
    this.Check("ShowNowPlaying", RadioXLAPI.ShowNowPlaying(false), "the on-screen line should show now");
    this.m_track = RadioXLAPI.CurrentTrack();
    this.m_position = RadioXLAPI.Position(st);
    this.Check("Position reads", this.m_position >= 0.0, s"\(this.m_position) s");
    this.Next(10, 2.0);
  }

  private func Clock() -> Void {
    let position: Float = RadioXLAPI.Position(this.m_station);
    if Equals(RadioXLAPI.CurrentTrack(), this.m_track) {
      this.Check("Position moves on with the song", position > this.m_position, s"\(this.m_position) -> \(position)");
    } else {
      this.Note("the song changed during the clock check; Position not compared");
    }
    let vanilla: CName = n"radio_station_01_att_rock";
    this.Check("Position reads a vanilla station nobody is listening to", RadioXLAPI.Position(vanilla) >= 0.0, s"\(RadioXLAPI.Position(vanilla)) s");
    this.Mark();
    this.Radioport(n"None");
    this.Next(11, 2.5);
  }

  private func PowerOff() -> Void {
    this.Check("the Radioport is off", Equals(RadioXLAPI.Receiver(), RadioXLReceiverKind.None), s"\(EnumInt(RadioXLAPI.Receiver()))");
    this.Check("RadioPower off arrived", this.Since("RadioPower") >= 1 && StrContains(this.Last("RadioPower"), "on=false"), this.Last("RadioPower"));
    this.Check("NextSong with no radio on is refused", !RadioXLAPI.NextSong(), "");
    let history: array<CName> = RadioXLAPI.History();
    this.Check("History is empty with no radio on", ArraySize(history) == 0, "");
    this.Next(12, 0.1);
  }

  private func Restore() -> Void {
    if this.m_wasOn { this.Radioport(this.m_wasStation); }
    this.Note(this.m_wasOn ? s"the Radioport is back on \(this.m_wasStation)" : "the Radioport is left off, as it was");
    this.Next(13, 0.1);
  }
}
