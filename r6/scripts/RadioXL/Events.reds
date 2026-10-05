// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The script API's events: one Codeware callback event per kind, and one method per
//              event on RadioXLEvents for CET mods to Observe.
// File Version: 0.7.0
// Credits: psiberx (Codeware)
// ======================================================================================
//
// A redscript mod registers for an event by name:
//
//   GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/SongChanged", this, n"OnSong");
//   cb func OnSong(evt: ref<RadioXLSongChangedEvent>) { ... }
//
// `RadioXL/Ready` should be registered with `sticky` set, so a mod that registers after the
// catalog is built still receives it.
//
// **CET cannot register a Lua function with the callback system, and `Observe` does not fire on a
// static.** So every dispatch also calls an empty instance method on the RadioXLEvents service:
//
//   Observe("RadioXL.RadioXLEvents", "OnSongChanged", function(self, station, track, receiver, requested) end)
//
// The names and the fields are a public contract. Add to them; never rename or remove one.

module RadioXL

// What the player is listening through.
public enum RadioXLReceiverKind {
  None = 0,
  Vehicle = 1,
  Radioport = 2,
}

public class RadioXLReadyEvent extends CallbackSystemEvent {
  private let version: Int32;
  private let stations: Int32;
  public func Version() -> Int32 { return this.version; }
  public func Stations() -> Int32 { return this.stations; }
  public static func Create(version: Int32, stations: Int32) -> ref<RadioXLReadyEvent> {
    let e = new RadioXLReadyEvent();
    e.version = version;
    e.stations = stations;
    return e;
  }
}

// `requested` is true when a song key or the API asked for the song, false when the station
// picked it itself.
public class RadioXLSongChangedEvent extends CallbackSystemEvent {
  private let station: CName;
  private let track: CName;
  private let receiver: RadioXLReceiverKind;
  private let requested: Bool;
  public func Station() -> CName { return this.station; }
  public func Track() -> CName { return this.track; }
  public func Receiver() -> RadioXLReceiverKind { return this.receiver; }
  public func Requested() -> Bool { return this.requested; }
  public static func Create(station: CName, track: CName, receiver: RadioXLReceiverKind, requested: Bool) -> ref<RadioXLSongChangedEvent> {
    let e = new RadioXLSongChangedEvent();
    e.station = station;
    e.track = track;
    e.receiver = receiver;
    e.requested = requested;
    return e;
  }
}

public class RadioXLStationChangedEvent extends CallbackSystemEvent {
  private let station: CName;
  private let previous: CName;
  private let receiver: RadioXLReceiverKind;
  public func Station() -> CName { return this.station; }
  public func Previous() -> CName { return this.previous; }
  public func Receiver() -> RadioXLReceiverKind { return this.receiver; }
  public static func Create(station: CName, previous: CName, receiver: RadioXLReceiverKind) -> ref<RadioXLStationChangedEvent> {
    let e = new RadioXLStationChangedEvent();
    e.station = station;
    e.previous = previous;
    e.receiver = receiver;
    return e;
  }
}

public class RadioXLRadioPowerEvent extends CallbackSystemEvent {
  private let receiver: RadioXLReceiverKind;
  private let on: Bool;
  public func Receiver() -> RadioXLReceiverKind { return this.receiver; }
  public func On() -> Bool { return this.on; }
  public static func Create(receiver: RadioXLReceiverKind, on: Bool) -> ref<RadioXLRadioPowerEvent> {
    let e = new RadioXLRadioPowerEvent();
    e.receiver = receiver;
    e.on = on;
    return e;
  }
}

public class RadioXLCatalogRefreshedEvent extends CallbackSystemEvent {
  private let station: CName;
  private let added: Int32;
  public func Station() -> CName { return this.station; }
  public func Added() -> Int32 { return this.added; }
  public static func Create(station: CName, added: Int32) -> ref<RadioXLCatalogRefreshedEvent> {
    let e = new RadioXLCatalogRefreshedEvent();
    e.station = station;
    e.added = added;
    return e;
  }
}

public class RadioXLSongStateChangedEvent extends CallbackSystemEvent {
  private let track: CName;
  private let state: RadioXLSongState;
  public func Track() -> CName { return this.track; }
  public func State() -> RadioXLSongState { return this.state; }
  public static func Create(track: CName, state: RadioXLSongState) -> ref<RadioXLSongStateChangedEvent> {
    let e = new RadioXLSongStateChangedEvent();
    e.track = track;
    e.state = state;
    return e;
  }
}

public class RadioXLMutesChangedEvent extends CallbackSystemEvent {
  private let idents: Bool;
  private let news: Bool;
  public func Idents() -> Bool { return this.idents; }
  public func News() -> Bool { return this.news; }
  public static func Create(idents: Bool, news: Bool) -> ref<RadioXLMutesChangedEvent> {
    let e = new RadioXLMutesChangedEvent();
    e.idents = idents;
    e.news = news;
    return e;
  }
}

// `restriction` is the PocketRadioRestrictions member's name, `PhoneCall`. Only the Radioport has
// these, and the event fires only for a situation whose "Mute the radio when..." switch is on.
public class RadioXLSilencedEvent extends CallbackSystemEvent {
  private let restriction: CName;
  private let silenced: Bool;
  public func Restriction() -> CName { return this.restriction; }
  public func Silenced() -> Bool { return this.silenced; }
  public static func Create(restriction: CName, silenced: Bool) -> ref<RadioXLSilencedEvent> {
    let e = new RadioXLSilencedEvent();
    e.restriction = restriction;
    e.silenced = silenced;
    return e;
  }
}

public class RadioXLMyStationChangedEvent extends CallbackSystemEvent {
  private let station: CName;
  public func Station() -> CName { return this.station; }
  public static func Create(station: CName) -> ref<RadioXLMyStationChangedEvent> {
    let e = new RadioXLMyStationChangedEvent();
    e.station = station;
    return e;
  }
}

public class RadioXLStationSkipChangedEvent extends CallbackSystemEvent {
  private let station: CName;
  private let skipped: Bool;
  public func Station() -> CName { return this.station; }
  public func Skipped() -> Bool { return this.skipped; }
  public static func Create(station: CName, skipped: Bool) -> ref<RadioXLStationSkipChangedEvent> {
    let e = new RadioXLStationSkipChangedEvent();
    e.station = station;
    e.skipped = skipped;
    return e;
  }
}

public class RadioXLEvents extends ScriptableService {
  // What was last announced, so a receiver read that has not changed announces nothing.
  private let m_kind: RadioXLReceiverKind;
  private let m_station: CName;
  private let m_song: Uint64;

  public final static func Get() -> ref<RadioXLEvents> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLEvents") as RadioXLEvents;
  }

  private cb func OnLoad() {
    let cs = GameInstance.GetCallbackSystem();
    cs.RegisterEvent(n"RadioXL/Ready", n"RadioXL.RadioXLReadyEvent");
    cs.RegisterEvent(n"RadioXL/SongChanged", n"RadioXL.RadioXLSongChangedEvent");
    cs.RegisterEvent(n"RadioXL/StationChanged", n"RadioXL.RadioXLStationChangedEvent");
    cs.RegisterEvent(n"RadioXL/RadioPower", n"RadioXL.RadioXLRadioPowerEvent");
    cs.RegisterEvent(n"RadioXL/CatalogRefreshed", n"RadioXL.RadioXLCatalogRefreshedEvent");
    cs.RegisterEvent(n"RadioXL/SongStateChanged", n"RadioXL.RadioXLSongStateChangedEvent");
    cs.RegisterEvent(n"RadioXL/MutesChanged", n"RadioXL.RadioXLMutesChangedEvent");
    cs.RegisterEvent(n"RadioXL/Silenced", n"RadioXL.RadioXLSilencedEvent");
    cs.RegisterEvent(n"RadioXL/MyStationChanged", n"RadioXL.RadioXLMyStationChangedEvent");
    cs.RegisterEvent(n"RadioXL/StationSkipChanged", n"RadioXL.RadioXLStationSkipChangedEvent");
  }

  // --- for CET to Observe: each is called with the event's fields, and does nothing ---------------

  public func OnReady(version: Int32, stations: Int32) -> Void {}
  public func OnSongChanged(station: CName, track: CName, receiver: RadioXLReceiverKind, requested: Bool) -> Void {}
  public func OnStationChanged(station: CName, previous: CName, receiver: RadioXLReceiverKind) -> Void {}
  public func OnRadioPower(receiver: RadioXLReceiverKind, on: Bool) -> Void {}
  public func OnCatalogRefreshed(station: CName, added: Int32) -> Void {}
  public func OnSongStateChanged(track: CName, state: RadioXLSongState) -> Void {}
  public func OnMutesChanged(idents: Bool, news: Bool) -> Void {}
  public func OnSilenced(restriction: CName, silenced: Bool) -> Void {}
  public func OnMyStationChanged(station: CName) -> Void {}
  public func OnStationSkipChanged(station: CName, skipped: Bool) -> Void {}

  // --- dispatch --------------------------------------------------------------------------------

  public final static func Ready(stations: Int32) -> Void {
    let version: Int32 = RadioXLAPI.Version();
    GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/Ready", RadioXLReadyEvent.Create(version, stations));
    let self = RadioXLEvents.Get();
    if IsDefined(self) { self.OnReady(version, stations); }
  }

  public final static func CatalogRefreshed(station: CName, added: Int32) -> Void {
    GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/CatalogRefreshed", RadioXLCatalogRefreshedEvent.Create(station, added));
    let self = RadioXLEvents.Get();
    if IsDefined(self) { self.OnCatalogRefreshed(station, added); }
  }

  public final static func SongStateChanged(track: CName, state: Int32) -> Void {
    let kind: RadioXLSongState = IntEnum<RadioXLSongState>(state);
    GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/SongStateChanged", RadioXLSongStateChangedEvent.Create(track, kind));
    let self = RadioXLEvents.Get();
    if IsDefined(self) { self.OnSongStateChanged(track, kind); }
  }

  public final static func MutesChanged(idents: Bool, news: Bool) -> Void {
    GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/MutesChanged", RadioXLMutesChangedEvent.Create(idents, news));
    let self = RadioXLEvents.Get();
    if IsDefined(self) { self.OnMutesChanged(idents, news); }
  }

  public final static func Silenced(restriction: Int32, silenced: Bool) -> Void {
    let name: CName = EnumValueToName(n"PocketRadioRestrictions", Cast<Int64>(restriction));
    GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/Silenced", RadioXLSilencedEvent.Create(name, silenced));
    let self = RadioXLEvents.Get();
    if IsDefined(self) { self.OnSilenced(name, silenced); }
  }

  public final static func MyStationChanged(station: CName) -> Void {
    GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/MyStationChanged", RadioXLMyStationChangedEvent.Create(station));
    let self = RadioXLEvents.Get();
    if IsDefined(self) { self.OnMyStationChanged(station); }
  }

  public final static func StationSkipChanged(station: CName, skipped: Bool) -> Void {
    GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/StationSkipChanged", RadioXLStationSkipChangedEvent.Create(station, skipped));
    let self = RadioXLEvents.Get();
    if IsDefined(self) { self.OnStationSkipChanged(station, skipped); }
  }

  // --- the receiver -----------------------------------------------------------------------------
  // Power and station are read, not reported: the game raises no one event for either across both
  // receivers, so the receiver is compared with what was last announced. The Radioport poll calls
  // this every second and the vehicle's own station and toggle events call it at once.

  public func Observe(gi: GameInstance) -> Void {
    let deck = RadioXLDeck.Get();
    if !IsDefined(deck) { return; }
    let r = deck.Receiver(gi);
    let kind: RadioXLReceiverKind = RadioXLEvents.KindOf(gi, r);
    let station: CName = NotEquals(kind, RadioXLReceiverKind.None) && IsDefined(r.station) ? r.station.name : n"None";

    if NotEquals(kind, this.m_kind) {
      let was: RadioXLReceiverKind = this.m_kind;
      this.m_kind = kind;
      if NotEquals(was, RadioXLReceiverKind.None) { this.Power(was, false); }
      if NotEquals(kind, RadioXLReceiverKind.None) { this.Power(kind, true); }
    }
    if NotEquals(kind, RadioXLReceiverKind.None) && IsNameValid(station) && NotEquals(station, this.m_station) {
      let previous: CName = this.m_station;
      this.m_station = station;
      this.m_song = 0ul;
      GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/StationChanged", RadioXLStationChangedEvent.Create(station, previous, kind));
      this.OnStationChanged(station, previous, kind);
    }
  }

  // The radio the player hears. In a vehicle the Radioport shadows the car radio and takes the same
  // toggle a moment later, so while seated it never counts: a car switched off would otherwise read
  // as the Radioport coming on and going off again.
  public final static func KindOf(gi: GameInstance, r: ref<RadioXLReceiver>) -> RadioXLReceiverKind {
    if IsDefined(r.vehicle) { return RadioXLReceiverKind.Vehicle; }
    if !IsDefined(r.pocket) { return RadioXLReceiverKind.None; }
    let player = GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject() as PlayerPuppet;
    return IsDefined(player) && IsDefined(player.GetMountedVehicle()) ? RadioXLReceiverKind.None : RadioXLReceiverKind.Radioport;
  }

  private func Power(kind: RadioXLReceiverKind, on: Bool) -> Void {
    GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/RadioPower", RadioXLRadioPowerEvent.Create(kind, on));
    this.OnRadioPower(kind, on);
  }

  // The receiver has started the song with this key. Called before the deck acts on it, so
  // `requested` still reads the deck's pending requests.
  public func Song(gi: GameInstance, key: Uint64) -> Void {
    this.Observe(gi);
    if key == 0ul || key == this.m_song { return; }
    let deck = RadioXLDeck.Get();
    let catalog = RadioXLCatalog.Get();
    if !IsDefined(deck) || !IsDefined(catalog) { return; }
    let r = deck.Receiver(gi);
    if !r.IsValid() { return; }
    let index: Int32 = catalog.IndexOf(r.station, key);
    if index < 0 && catalog.Refresh(r.station.name) {
      index = catalog.IndexOf(r.station, key);
    }
    if index < 0 { return; }
    this.m_song = key;
    let track: CName = r.station.tracks[index].event;
    let requested: Bool = deck.IsPending(key);
    GameInstance.GetCallbackSystem().DispatchEventAs(n"RadioXL/SongChanged",
      RadioXLSongChangedEvent.Create(r.station.name, track, this.m_kind, requested));
    this.OnSongChanged(r.station.name, track, this.m_kind, requested);
  }
}
