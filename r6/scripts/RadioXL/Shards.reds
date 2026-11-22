// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Shards: the player's own song lists, played on the shard slot, one station the
//              plugin registers last on the dial whose track list is replaced by the slotted shard's.
//
//              ALL SONGS is every song on every station, vanilla and custom, each once. Entries in
//              the station metadata that are not music are left out: the police scanner and
//              Kurtz entries hold only radio noise, Body Heat's second entry repeats Body Heat,
//              Impulse's single track is one long DJ set (in only behind its switch), and a stream
//              station's track is a URL. Idents live in each station's blips, never its tracks.
//
//              SLOTTING writes the shard's songs into the slot's cooked metadata entry, which is
//              the object the engine's station reads. The remaining list is cleared BEFORE the
//              write: entries left from the old list are indices, and they would name arbitrary
//              songs in the new one. All songs is what the slot holds when nothing else is
//              slotted; picking another station on the same radio ejects the shard and puts All
//              songs back.
//
//              IN ORDER keeps exactly one entry in the slot's remaining list, the song after the
//              one playing, so the engine's own pick lands on it.
// File Version: 0.11.0
// Credits: Codeware by psiberx.
// ======================================================================================

module RadioXL


// One of the player's shards. `songs` are track events, in the order an in-order shard plays them.
public class RadioXLShard {
  public let name: String;
  public let songs: array<CName>;
  public let ordered: Bool;
}

public abstract class RadioXLShardSongs {

  public final static func ImpulseSet() -> CName {
    return n"mus_radio_14_impulse_djset";
  }

  // Station entries whose tracks are never songs, or repeat another entry's.
  private final static func Skipped(station: CName) -> Bool {
    return Equals(station, n"radio_station_police")
      || Equals(station, n"radio_station_kurtz")
      || Equals(station, n"radio_station_05_pop_completed_sq017")
      || RadioXLIsShard(station);
  }

  // Every custom track that is a stream URL rather than a file.
  private final static func Streams() -> array<CName> {
    let out: array<CName>;
    let slot: Int32 = 0;
    while slot < RadioXL_StationCount() {
      let t: Int32 = 0;
      while t < RadioXL_StationTrackCount(slot) {
        if RadioXLAudio.IsStream(RadioXL_StationTrackFile(slot, t)) {
          ArrayPush(out, RadioXL_StationTrack(slot, t));
        }
        t += 1;
      }
      slot += 1;
    }
    return out;
  }

  // Every song in the metadata, in station order, each once.
  public final static func Every(cooked: ref<audioCookedMetadataResource>, impulse: Bool) -> array<CName> {
    let out: array<CName>;
    if !IsDefined(cooked) { return out; }
    let streams: array<CName> = RadioXLShardSongs.Streams();
    for entry in cooked.entries {
      let station = entry as audioRadioStationMetadata;
      if IsDefined(station) && !RadioXLShardSongs.Skipped(station.name) {
        for track in station.tracks {
          let wanted: Bool = IsNameValid(track) && !ArrayContains(out, track) && !ArrayContains(streams, track);
          if wanted && (impulse || !Equals(track, RadioXLShardSongs.ImpulseSet())) {
            ArrayPush(out, track);
          }
        }
      }
    }
    return out;
  }
}

// The slot's name asked for again, once the translations are collected.
public class RadioXLShardRename extends DelayCallback {
  public func Call() -> Void {
    let shards = RadioXLShards.Get();
    if IsDefined(shards) { shards.Rename(); }
  }
}

public class RadioXLShards extends ScriptableService {
  // The radio the last station change was heard on: a station change on the SAME radio ejects.
  private let m_kind: RadioXLReceiverKind;
  // The songs written into the slot, in the order written.
  private let m_written: array<CName>;
  private let m_listening: Bool;

  // The slot's name as every UI shows it: the shard slotted, or All songs. Kept here so the localization
  // package, which builds while the translations are being collected, never has to look a text up.
  private let m_slotName: String;

  public func SlotName() -> String {
    return StrLen(this.m_slotName) > 0 ? this.m_slotName : "All songs";
  }

  // The slot station is named after what it plays. Its localization key resolves to that name once
  // Codeware collects the translations again, so the game's own UIs (the popup, the on-screen station
  // name, the car's dashboard) show it; its record's display name follows, so the popup still matches the
  // two when it looks for the playing row.
  public func Rename() -> Void {
    let slotted: String = this.Slotted();
    let name: String = StrLen(slotted) > 0 ? slotted : RadioXLText("RadioXL.libAll");
    let slot: Int32 = RadioXL_ShardSlot();
    if slot < 0 { return; }
    // Early in a session the translations are not collected yet and the key comes back as its own text;
    // the key is never written as the station's name, and the name is asked for again a second later.
    if Equals(name, "RadioXL.libAll") {
      let again = new RadioXLShardRename();
      GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(again, 1.0, false);
      return;
    }
    if NotEquals(name, this.m_slotName) {
      this.m_slotName = name;
      RadioXLRenameRecord(RadioXLDial.RecordName(slot), name);
      // Every UI that shows the slot's name reads its key, so the key's text is what changes.
      if !RadioXL_SetText(NameToString(RadioXL_StationKey(slot)), name) { RadioXLLog(s"shard slot name not set: \(name)"); }
    }
  }

  public final static func Get() -> ref<RadioXLShards> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLShards") as RadioXLShards;
  }

  private cb func OnLoad() {
    GameInstance.GetCallbackSystem().RegisterCallback(n"Session/Ready", this, n"OnSessionReady");
  }

  // The RadioXL events are registered by RadioXLEvents as it loads, so the listeners go on once a
  // session is ready rather than from OnLoad, whose order against that service is not promised.
  private cb func OnSessionReady(event: ref<GameSessionEvent>) {
    if !this.m_listening {
      this.m_listening = true;
      let cs = GameInstance.GetCallbackSystem();
      cs.RegisterCallback(n"RadioXL/StationChanged", this, n"OnStationChanged");
      cs.RegisterCallback(n"RadioXL/SongChanged", this, n"OnSongChanged");
      cs.RegisterCallback(n"RadioXL/SongStateChanged", this, n"OnSongStateChanged");
      cs.RegisterCallback(n"RadioXL/CatalogRefreshed", this, n"OnCatalogRefreshed");
    }
    // Load registered All songs unfiltered; the slotted shard and the player's filters go on now.
    this.Apply(false);
  }

  // --- reading ------------------------------------------------------------------------------------

  public func Station() -> CName {
    return RadioXLShardName();
  }

  public func Slotted() -> String {
    let state = RadioXLState.Get();
    return IsDefined(state) ? state.slottedShard : "";
  }

  public func Names() -> array<String> {
    let out: array<String>;
    let state = RadioXLState.Get();
    if !IsDefined(state) { return out; }
    for shard in state.Shards() {
      ArrayPush(out, shard.name);
    }
    return out;
  }

  // A shard's songs as stored, or All songs as it stands now for "".
  public func Songs(name: String) -> array<CName> {
    let out: array<CName>;
    if StrLen(name) == 0 { return this.AllSongs(); }
    let state = RadioXLState.Get();
    let shard = IsDefined(state) ? state.Shard(name) : null;
    if IsDefined(shard) { out = shard.songs; }
    return out;
  }

  public func IsOrdered(name: String) -> Bool {
    let state = RadioXLState.Get();
    let shard = IsDefined(state) && StrLen(name) > 0 ? state.Shard(name) : null;
    return IsDefined(shard) && shard.ordered;
  }

  // Every song, without the songs the player switched off or the game would not play now.
  public func AllSongs() -> array<CName> {
    let out: array<CName>;
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(catalog) || !catalog.IsBuilt() { return out; }
    let cfg = RadioXLConfig.Get();
    let impulse: Bool = IsDefined(cfg) && cfg.impulseInAllSongs;
    return this.Playable(RadioXLShardSongs.Every(catalog.CookedMetadata(), impulse));
  }

  // The songs the deck would play now, in the order given. A song on no station is dropped.
  private func Playable(songs: array<CName>) -> array<CName> {
    let out: array<CName>;
    let catalog = RadioXLCatalog.Get();
    let deck = RadioXLDeck.Get();
    if !IsDefined(catalog) || !IsDefined(deck) { return out; }
    let gi = GetGameInstance();
    for song in songs {
      let owner = catalog.Owner(song);
      if IsDefined(owner) && !RadioXLIsShard(owner.name) && deck.CanPlay(gi, catalog.Track(owner, song)) {
        ArrayPush(out, song);
      }
    }
    return out;
  }

  // --- the slot -----------------------------------------------------------------------------------

  // Writes the slotted shard into the slot. With `request`, the radio is tuned to the slot and a first
  // song is asked for; without, the list is only put in place (a session start, a filter change).
  private func Apply(request: Bool, opt want: CName) -> Bool {
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(catalog) || RadioXL_ShardSlot() < 0 { return false; }
    // Session/Ready callbacks run in no promised order, so the catalog may not have built yet.
    catalog.Build();
    if !catalog.IsBuilt() { return false; }
    let name: String = this.Slotted();
    let songs: array<CName> = StrLen(name) == 0 ? this.AllSongs() : this.Playable(this.Songs(name));
    if ArraySize(songs) == 0 {
      RadioXLLog(s"shard '\(name)': nothing playable to slot");
      return false;
    }
    let ordered: Bool = this.IsOrdered(name);
    if !this.Write(songs, ordered) { return false; }
    this.Rename();
    if !request { return true; }
    let gi = GetGameInstance();
    let deck = RadioXLDeck.Get();
    let slot: Int32 = RadioXL_ShardSlot();
    if !IsDefined(deck) || slot < 0 { return false; }
    deck.Tune(gi, RadioXL_SlotEnum(slot), "shard");
    let first: CName = ordered ? songs[0] : songs[RandRange(0, ArraySize(songs))];
    if IsNameValid(want) && ArrayContains(songs, want) { first = want; }
    deck.Request(gi, this.Station(), first);
    // The request consumed the queued first song. The song after it is queued now rather than when
    // the song is heard starting, since nothing reports a start on a slot no radio is tuned to.
    if ordered { this.QueueAfter(first); }
    return true;
  }

  // The remaining list is cleared before the track list changes and set again after it, so no stale
  // index survives the swap.
  private func Write(songs: array<CName>, ordered: Bool) -> Bool {
    let station: CName = this.Station();
    let catalog = RadioXLCatalog.Get();
    let entry = IsDefined(catalog) ? catalog.CookedStation(station) : null;
    if !IsNameValid(station) || !IsDefined(entry) {
      RadioXLLog("shard slot: the slot's metadata entry is not loaded - nothing written");
      return false;
    }
    let empty: array<CName>;
    RadioXL_StationSetRemaining(station, empty);
    entry.tracks = songs;
    this.m_written = songs;
    if ordered {
      let first: array<CName>;
      ArrayPush(first, songs[0]);
      RadioXL_StationSetRemaining(station, first);
    }
    catalog.Refresh(station);
    RadioXLLog(s"shard slot: '\(this.Slotted())' written, \(ArraySize(songs)) song(s), \(ordered ? "in order" : "shuffled")");
    return true;
  }

  // Slots the shard and starts `first` from it, or a song of its own choosing without one. A shard already
  // slotted and playing only changes song.
  public func Slot(name: String, opt first: CName) -> Bool {
    let state = RadioXLState.Get();
    if !IsDefined(state) || (StrLen(name) > 0 && !IsDefined(state.Shard(name))) { return false; }
    let deck = RadioXLDeck.Get();
    if IsNameValid(first) && IsDefined(deck) && Equals(state.slottedShard, name)
      && Equals(RadioXLAPI.CurrentStation(), this.Station()) && ArrayContains(this.m_written, first) {
      deck.Request(GetGameInstance(), this.Station(), first);
      if this.IsOrdered(name) { this.QueueAfter(first); }
      return true;
    }
    let previous: String = state.slottedShard;
    state.SetSlottedShard(name);
    if !this.Apply(true, first) {
      state.SetSlottedShard(previous);
      return false;
    }
    RadioXLEvents.ShardSlotted(name);
    RadioXLEqualiser.Apply();
    return true;
  }

  // Puts All songs back in the slot. The radio stays where it is.
  public func Eject() -> Bool {
    let state = RadioXLState.Get();
    if !IsDefined(state) || StrLen(state.slottedShard) == 0 { return false; }
    let was: String = state.slottedShard;
    state.SetSlottedShard("");
    this.Apply(false);
    RadioXLLog(s"shard '\(was)' ejected");
    RadioXLEvents.ShardEjected(was);
    RadioXLEqualiser.Apply();
    return true;
  }

  // The Impulse switch changed: All songs is rebuilt if it is in the slot.
  public func AllSongsChanged() -> Void {
    if StrLen(this.Slotted()) == 0 { this.Apply(false); }
  }

  // --- the player's shards, for the panel ----------------------------------------------------------

  // Adds a shard, or replaces the one with that name. "" is All songs and cannot be stored.
  public func Save(name: String, songs: array<CName>, ordered: Bool) -> Bool {
    let state = RadioXLState.Get();
    if !IsDefined(state) || StrLen(name) == 0 { return false; }
    let shard = new RadioXLShard();
    shard.name = name;
    shard.ordered = ordered;
    for song in songs {
      if IsNameValid(song) && !ArrayContains(shard.songs, song) { ArrayPush(shard.songs, song); }
    }
    state.PutShard(shard);
    RadioXLEvents.ShardsChanged(name);
    if Equals(this.Slotted(), name) { this.Apply(false); }
    return true;
  }

  // A shard keeps its place in the list and its songs; the slot shows the new name when it holds it.
  public func RenameShard(from: String, to: String) -> Bool {
    let state = RadioXLState.Get();
    if !IsDefined(state) || !state.RenameShard(from, to) { return false; }
    RadioXLEvents.ShardsChanged(to);
    if Equals(this.Slotted(), to) { this.Rename(); }
    return true;
  }

  public func Delete(name: String) -> Bool {
    let state = RadioXLState.Get();
    if !IsDefined(state) { return false; }
    let slotted: Bool = Equals(state.slottedShard, name);
    if !state.RemoveShard(name) { return false; }
    RadioXLEvents.ShardsChanged(name);
    if slotted {
      this.Apply(false);
      RadioXLEvents.ShardEjected(name);
    }
    return true;
  }

  // --- following the radio ------------------------------------------------------------------------

  private cb func OnStationChanged(e: ref<RadioXLStationChangedEvent>) {
    let sameRadio: Bool = Equals(e.Receiver(), this.m_kind);
    this.m_kind = e.Receiver();
    let slot: CName = this.Station();
    if sameRadio && Equals(e.Previous(), slot) && NotEquals(e.Station(), slot) {
      this.Eject();
    }
  }

  // In order: the song after the one that started is the only one left to pick.
  private cb func OnSongChanged(e: ref<RadioXLSongChangedEvent>) {
    if !Equals(e.Station(), this.Station()) || !this.IsOrdered(this.Slotted()) { return; }
    this.QueueAfter(e.Track());
  }

  private func QueueAfter(song: CName) -> Void {
    let n: Int32 = ArraySize(this.m_written);
    let i: Int32 = ArrayFindFirst(this.m_written, song);
    if n == 0 || i < 0 { return; }
    let next: array<CName>;
    ArrayPush(next, this.m_written[(i + 1) % n]);
    RadioXL_StationSetRemaining(this.Station(), next);
  }

  // A song switched off while the slot holds it leaves the remaining list only; the list itself is
  // kept, so the song playing is not cut.
  private cb func OnSongStateChanged(e: ref<RadioXLSongStateChangedEvent>) {
    if !ArrayContains(this.m_written, e.Track()) { return; }
    let catalog = RadioXLCatalog.Get();
    let deck = RadioXLDeck.Get();
    let owner = IsDefined(catalog) ? catalog.Owner(e.Track()) : null;
    if !IsDefined(owner) || !IsDefined(deck) || deck.CanPlay(GetGameInstance(), catalog.Track(owner, e.Track())) { return; }
    let station: CName = this.Station();
    let remaining: array<CName> = RadioXL_StationRemaining(station);
    if !ArrayContains(remaining, e.Track()) { return; }
    ArrayRemove(remaining, e.Track());
    RadioXL_StationSetRemaining(station, remaining);
    RadioXLLog(s"shard slot: \(e.Track()) switched off, out of the remaining list");
  }

  // A quest added songs to a station: All songs takes them at the end, so no index moves.
  private cb func OnCatalogRefreshed(e: ref<RadioXLCatalogRefreshedEvent>) {
    if e.Added() <= 0 || RadioXLIsShard(e.Station()) || StrLen(this.Slotted()) > 0 { return; }
    let catalog = RadioXLCatalog.Get();
    let entry = IsDefined(catalog) ? catalog.CookedStation(this.Station()) : null;
    if !IsDefined(entry) { return; }
    let added: Int32 = 0;
    for song in this.AllSongs() {
      if !ArrayContains(entry.tracks, song) {
        ArrayPush(entry.tracks, song);
        ArrayPush(this.m_written, song);
        added += 1;
      }
    }
    if added > 0 {
      catalog.Refresh(this.Station());
      RadioXLLog(s"shard slot: \(added) new song(s) joined All songs");
    }
  }
}

// The slot's record takes the name it plays under; without TweakXL there is no record to rename.
@if(ModuleExists("TweakXL"))
public func RadioXLRenameRecord(record: String, name: String) -> Void {
  TweakDBManager.SetFlat(TDBID.Create(record + ".displayName"), ToVariant(name));
  TweakDBManager.UpdateRecord(TDBID.Create(record));
}

@if(!ModuleExists("TweakXL"))
public func RadioXLRenameRecord(record: String, name: String) -> Void {}
