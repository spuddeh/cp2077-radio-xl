// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Every station and every track, read from the game's own tables. The engine holds
//              them in cooked_metadata.audio_metadata: one audioRadioStationMetadata entry per
//              station (its event name and its track events, in play order) and one
//              audioRadioTracksMetadata table (each track's title key and streamer flag).
//              A mod that adds a track pushes into those arrays as the resource loads, and so does
//              this framework's plugin, so a catalog built from the loaded resource sees every
//              station with no patch file and no second list.
//
//              THE CATALOG IS BUILT AT SESSION READY, NOT AS THE RESOURCE LOADS. Every mod that
//              adds a station or a track writes during the load callback, and callback order is
//              not promised, so a read taken during the load can miss a track pushed a moment
//              later. The token is taken at session ready as well: a token taken at service load
//              starts the load early, before other mods have registered their load callbacks,
//              and a mod that listens only for the load (Restore Nebula) then never hears it.
//
//              THE TWO MUTES are applied three times: as the resource loads, at session ready,
//              and the moment the setting changes. Each station's idents and the announcement
//              graph's nodes are kept aside when cleared, so switching a mute off puts them back.
// File Version: 0.5.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL

// One track. `key` is what the receiver reports as the playing track: the radio hands back a
// CName built from primaryLocKey, so this is the identity to match on, and `title` is the
// localization key the HUD resolves for its name.
public class RadioXLCatalogTrack {
  public let event: CName;
  public let title: CName;
  public let key: Uint64;
  public let streamingFriendly: Bool;
}

// One station: its event name (the identity every receiver and the audio system use) and its
// tracks in the order the station plays them.
public class RadioXLCatalogStation {
  public let name: CName;
  public let tracks: array<ref<RadioXLCatalogTrack>>;
}

// One announcement node, with the scene each of its entries pointed at before anything was
// muted. Blanking is reversible because this is what it is reversed from.
public class RadioXLAnnouncements {
  public let node: ref<questRadioAnnouncementNodeType>;
  public let scenes: array<ResRef>;
  public let blocks: array<Bool>;
}

// A station's idents, kept aside while they are muted.
public class RadioXLIdents {
  public let station: CName;
  public let blips: array<audioRadioBlip>;
}

public class RadioXLCatalog extends ScriptableService {
  private let m_token: ref<ResourceToken>;
  private let m_contentToken: ref<ResourceToken>;
  private let m_stations: array<ref<RadioXLCatalogStation>>;
  private let m_titles: ref<audioRadioTracksMetadata>;
  private let m_built: Bool;

  private let m_identsMuted: Bool;
  private let m_idents: array<ref<RadioXLIdents>>;
  private let m_newsMuted: Bool;
  private let m_newsApplied: Bool;
  private let m_announcements: array<ref<RadioXLAnnouncements>>;
  private let m_walked: Bool;

  public final static func Get() -> ref<RadioXLCatalog> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLCatalog") as RadioXLCatalog;
  }

  private cb func OnLoad() {
    let cb = GameInstance.GetCallbackSystem();
    cb.RegisterCallback(n"Session/Ready", this, n"OnSessionReady");
    // Resource/Load fires while a load is in progress, which is the one moment the engine will
    // still read a change to the station data. Nothing here starts a load of its own.
    cb.RegisterCallback(n"Resource/Load", this, n"OnCookedMetadata")
      .AddTarget(ResourceTarget.Path(r"base\\sound\\metadata\\cooked_metadata.audio_metadata"));
    cb.RegisterCallback(n"Resource/Load", this, n"OnRadioContent")
      .AddTarget(ResourceTarget.Path(r"base\\media\\radio\\radio_content.questphase"));
  }

  // The main menu is a session too, and a station mod can only have written by the time the
  // resource has loaded, so the build is retried on every session until it has something.
  private cb func OnSessionReady(event: ref<GameSessionEvent>) {
    let depot = GameInstance.GetResourceDepot();
    if !IsDefined(this.m_token) {
      this.m_token = depot.LoadResource(r"base\\sound\\metadata\\cooked_metadata.audio_metadata");
    }
    if !IsDefined(this.m_contentToken) {
      this.m_contentToken = depot.LoadResource(r"base\\media\\radio\\radio_content.questphase");
    }
    this.Build();
    this.ApplyMutes();
  }

  private func Cooked() -> ref<audioCookedMetadataResource> {
    if !IsDefined(this.m_token) || !this.m_token.IsLoaded() { return null; }
    return this.m_token.GetResource() as audioCookedMetadataResource;
  }

  private func Content() -> ref<questQuestPhaseResource> {
    if !IsDefined(this.m_contentToken) || !this.m_contentToken.IsLoaded() { return null; }
    return this.m_contentToken.GetResource() as questQuestPhaseResource;
  }

  // Walks the loaded resource. Safe to call more than once: a second call rebuilds only when the
  // first found nothing, which is the resource not yet being loaded.
  public func Build() -> Void {
    if this.m_built { return; }
    let cooked = this.Cooked();
    if !IsDefined(cooked) {
      RadioXLLog("cooked audio metadata is not loaded yet - catalog deferred");
      return;
    }
    let titles: ref<audioRadioTracksMetadata>;
    for entry in cooked.entries {
      let table = entry as audioRadioTracksMetadata;
      if IsDefined(table) { titles = table; }
    }
    this.m_titles = titles;
    let stations: array<ref<RadioXLCatalogStation>>;
    let trackCount: Int32 = 0;
    let names: String = "";
    for entry in cooked.entries {
      let meta = entry as audioRadioStationMetadata;
      if IsDefined(meta) && IsNameValid(meta.name) {
        let station = new RadioXLCatalogStation();
        station.name = meta.name;
        for event in meta.tracks {
          let track = new RadioXLCatalogTrack();
          track.event = event;
          track.streamingFriendly = true;
          this.FillTitle(titles, track);
          ArrayPush(station.tracks, track);
          trackCount += 1;
        }
        ArrayPush(stations, station);
        names += s" \(meta.name)=\(ArraySize(meta.tracks))";
      }
    }
    if ArraySize(stations) == 0 {
      RadioXLLog("no station entries in the cooked audio metadata - catalog deferred");
      return;
    }
    this.m_stations = stations;
    this.m_built = true;
    this.SeedStreamerFlags(stations);
    RadioXLLog(s"catalog built: \(ArraySize(stations)) stations, \(trackCount) tracks -\(names)");
  }

  // The engine's streaming flag becomes the song's starting state, so one list answers what a
  // song does. A song the engine has no entry for - every song a mod adds - stays On, and the
  // panel is where it can be marked. RCF restores the player's own picks over this a moment later.
  private func SeedStreamerFlags(stations: array<ref<RadioXLCatalogStation>>) -> Void {
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) { return; }
    let hidden: Int32 = 0;
    for station in stations {
      for track in station.tracks {
        if !track.streamingFriendly {
          controls.SetSongState(track.event, RadioXL_SongStreamerOff());
          hidden += 1;
        }
      }
    }
    RadioXLLog(s"\(hidden) tracks are flagged not streamer friendly by the game");
  }

  private func FillTitle(titles: ref<audioRadioTracksMetadata>, track: ref<RadioXLCatalogTrack>) -> Void {
    if !IsDefined(titles) { return; }
    let i: Int32 = 0;
    while i < ArraySize(titles.radioTracks) {
      if Equals(titles.radioTracks[i].trackEventName, track.event) {
        track.title = titles.radioTracks[i].localizationKey;
        track.key = titles.radioTracks[i].primaryLocKey;
        track.streamingFriendly = titles.radioTracks[i].isStreamingFriendly;
        return;
      }
      i += 1;
    }
  }

  // --- keeping up with the engine -----------------------------------------------------------------

  // Brings one station's track list in line with the engine's live one. The cooked resource this
  // catalog is built from is a snapshot, and a quest can add tracks to a station during a session
  // (Body Heat gains two once the Kerry fact is set), so the list comes from the plugin. Tracks
  // already known keep their objects; a new one is titled from the same table as at build, and a
  // song the game flags not streamer friendly starts Off while streaming, as at build. True when
  // the list changed.
  public func Refresh(name: CName) -> Bool {
    let station = this.Station(name);
    if !IsDefined(station) { return false; }
    let live: array<CName> = RadioXL_StationTracks(name);
    let n: Int32 = ArraySize(live);
    if n == 0 { return false; }
    if n == ArraySize(station.tracks) {
      let same: Bool = true;
      let i: Int32 = 0;
      while same && i < n {
        if NotEquals(station.tracks[i].event, live[i]) { same = false; }
        i += 1;
      }
      if same { return false; }
    }
    let controls = RadioXLControls.Get();
    let tracks: array<ref<RadioXLCatalogTrack>>;
    let added: Int32 = 0;
    for event in live {
      let known = this.Track(station, event);
      if IsDefined(known) {
        ArrayPush(tracks, known);
      } else {
        let track = new RadioXLCatalogTrack();
        track.event = event;
        track.streamingFriendly = true;
        this.FillTitle(this.m_titles, track);
        if !track.streamingFriendly && IsDefined(controls) {
          controls.SetSongState(track.event, RadioXL_SongStreamerOff());
        }
        ArrayPush(tracks, track);
        added += 1;
      }
    }
    RadioXLLog(s"\(name): track list refreshed from the engine, \(ArraySize(station.tracks)) to \(n) (\(added) new)");
    station.tracks = tracks;
    return true;
  }

  // Every station, for the panel: one walk of the manager per station, cheap enough per open.
  public func RefreshAll() -> Void {
    for station in this.m_stations {
      this.Refresh(station.name);
    }
  }

  // --- lookups ----------------------------------------------------------------------------------

  public func IsBuilt() -> Bool {
    return this.m_built;
  }

  public func Stations() -> array<ref<RadioXLCatalogStation>> {
    return this.m_stations;
  }

  public func Station(name: CName) -> ref<RadioXLCatalogStation> {
    let i: Int32 = 0;
    while i < ArraySize(this.m_stations) {
      if Equals(this.m_stations[i].name, name) { return this.m_stations[i]; }
      i += 1;
    }
    return null;
  }

  // The track a receiver reports, resolved against the station it is tuned to. -1 when the key
  // is not one of the station's tracks, which is what NoneTrack and a station change look like.
  public func IndexOf(station: ref<RadioXLCatalogStation>, key: Uint64) -> Int32 {
    if !IsDefined(station) { return -1; }
    let i: Int32 = 0;
    while i < ArraySize(station.tracks) {
      if station.tracks[i].key == key { return i; }
      i += 1;
    }
    return -1;
  }

  public func Track(station: ref<RadioXLCatalogStation>, event: CName) -> ref<RadioXLCatalogTrack> {
    if !IsDefined(station) { return null; }
    let i: Int32 = 0;
    while i < ArraySize(station.tracks) {
      if Equals(station.tracks[i].event, event) { return station.tracks[i]; }
      i += 1;
    }
    return null;
  }

  // --- the two mutes ----------------------------------------------------------------------------

  private cb func OnCookedMetadata(event: ref<ResourceEvent>) {
    RadioXLLog("cooked audio metadata load event received");
    this.SetIdentsMuted(event.GetResource() as audioCookedMetadataResource, RadioXLState.Get().muteIdents);
  }

  private cb func OnRadioContent(event: ref<ResourceEvent>) {
    RadioXLLog("radio content questphase load event received");
    // A fresh load is a fresh set of node objects; the ones held here would be writes into
    // nothing, so the walk starts again and the level is re-applied.
    this.m_walked = false;
    this.m_newsApplied = false;
    ArrayClear(this.m_announcements);
    this.SetNewsMuted(event.GetResource() as questQuestPhaseResource, RadioXLState.Get().muteNews);
  }

  // Brings the loaded resources in line with the settings. Called at session ready and whenever
  // either mute changes in the panel.
  public func ApplyMutes() -> Void {
    let state = RadioXLState.Get();
    if !IsDefined(state) { return; }
    this.SetIdentsMuted(this.Cooked(), state.muteIdents);
    this.SetNewsMuted(this.Content(), state.muteNews);
  }

  // A station ident is a spoken blip held in the station's own `blips` array. Muting empties the
  // array and keeps the blips aside; unmuting puts them back.
  private func SetIdentsMuted(cooked: ref<audioCookedMetadataResource>, muted: Bool) -> Void {
    if !IsDefined(cooked) || (muted && this.m_identsMuted) || (!muted && !this.m_identsMuted) { return; }
    this.m_identsMuted = muted;
    let count: Int32 = 0;
    for entry in cooked.entries {
      let meta = entry as audioRadioStationMetadata;
      if IsDefined(meta) {
        if muted {
          if ArraySize(meta.blips) > 0 {
            let kept = new RadioXLIdents();
            kept.station = meta.name;
            kept.blips = meta.blips;
            ArrayPush(this.m_idents, kept);
            count += ArraySize(meta.blips);
            ArrayClear(meta.blips);
          }
        } else {
          let kept = this.KeptIdents(meta.name);
          if IsDefined(kept) {
            meta.blips = kept.blips;
            count += ArraySize(kept.blips);
          }
        }
      }
    }
    if !muted { ArrayClear(this.m_idents); }
    RadioXLLog(muted ? s"station idents muted: \(count) blip(s) removed" : s"station idents restored: \(count) blip(s) put back");
  }

  private func KeptIdents(station: CName) -> ref<RadioXLIdents> {
    let i: Int32 = 0;
    while i < ArraySize(this.m_idents) {
      if Equals(this.m_idents[i].station, station) { return this.m_idents[i]; }
      i += 1;
    }
    return null;
  }

  // The DJ's talk between songs is a quest graph, radio_content.questphase, and every announcement
  // in it is a node carrying one scene reference per station it can speak on, and the speaker who
  // reads it. Muting BLANKS those references rather than removing the node: a node with no scene
  // to play has nothing to say, the graph keeps its shape, and the original reference is kept here
  // so unmuting puts it back exactly.
  //
  // The nodes are reached through the resource, and the quest system walks those same node
  // objects, so a reference blanked here is blanked in the graph the game is running.
  private func SetNewsMuted(phase: ref<questQuestPhaseResource>, muted: Bool) -> Void {
    if !IsDefined(phase) { return; }
    if this.m_newsApplied {
      if muted && this.m_newsMuted { return; }
      if !muted && !this.m_newsMuted { return; }
    }
    let graph = phase.graph as questGraphDefinition;
    if !IsDefined(graph) {
      RadioXLLog("radio content questphase carries no graph - nothing to mute");
      return;
    }
    if !this.m_walked {
      this.m_walked = true;
      this.Walk(graph);
      let entries: Int32 = 0;
      let empty: Int32 = 0;
      for held in this.m_announcements {
        for scene in held.scenes {
          entries += 1;
          if ResRef.GetHash(scene) == 0ul { empty += 1; }
        }
      }
      RadioXLLog(s"radio announcements: \(ArraySize(this.m_announcements)) node(s), \(entries) scene reference(s) captured, \(empty) of them already empty");
    }
    this.m_newsMuted = muted;
    this.m_newsApplied = true;
    let blank: ResRef;
    let changed: Int32 = 0;
    for held in this.m_announcements {
      let events = held.node.radioStationEvents;
      let touched: Bool = false;
      let i: Int32 = 0;
      while i < ArraySize(events) && i < ArraySize(held.scenes) {
        let entry = events[i];
        let original: ResRef = held.scenes[i];
        // WHO SPEAKS IS WHAT DECIDES, not whether the entry queues: Radio Hosts (DJs) Fix ships
        // its own graph with the queue flag inverted, and a rule built on the flag mutes almost
        // nothing there. Kurt Hansen is the one speaker left alone: he broadcasts over Dogtown
        // and his station has no RadioStation record, so nothing he says arrives through the
        // player's radio.
        let silence: Bool = muted && NotEquals(entry.speaker, audioRadioSpeakerType.Kurtz);
        let wanted: Uint64 = silence ? 0ul : ResRef.GetHash(original);
        // `blockSignal` stops the music while the announcement plays, and it is released when the
        // scene ends. An entry with no scene never ends, so the block is cleared with the scene:
        // left set, the station holds on "No Track" for good.
        let block: Bool = silence ? false : held.blocks[i];
        if ResRef.GetHash(ResourceAsyncRef.GetPath(entry.announcementScene)) != wanted {
          ResourceAsyncRef.SetPath(entry.announcementScene, silence ? blank : original);
          entry.blockSignal = block;
          events[i] = entry;
          touched = true;
          changed += 1;
        }
        i += 1;
      }
      if touched { held.node.radioStationEvents = events; }
    }
    RadioXLLog(s"radio announcements \(muted ? "muted" : "restored"): \(changed) reference(s) changed");
  }

  // The announcements are not all at the top: the graph holds phase nodes, each with a graph of
  // its own, and that is where most of them live.
  private func Walk(graph: ref<questGraphDefinition>) -> Void {
    for node in graph.nodes {
      let audio = node as questAudioNodeDefinition;
      if IsDefined(audio) {
        let announcement = audio.type as questRadioAnnouncementNodeType;
        if IsDefined(announcement) {
          let held = new RadioXLAnnouncements();
          held.node = announcement;
          for entry in announcement.radioStationEvents {
            ArrayPush(held.scenes, ResourceAsyncRef.GetPath(entry.announcementScene));
            ArrayPush(held.blocks, entry.blockSignal);
          }
          ArrayPush(this.m_announcements, held);
        }
      }
      let phase = node as questPhaseNodeDefinition;
      if IsDefined(phase) && IsDefined(phase.phaseGraph) {
        this.Walk(phase.phaseGraph);
      }
    }
  }
}
