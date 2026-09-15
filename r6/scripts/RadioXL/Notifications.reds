// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Where the game tells this mod a song changed, and the two notifications.
//
//              IN A VEHICLE the game raises VehicleRadioSongChanged on the HUD, carrying the
//              new track's key, and the summon widget shows its popup from it. That handler is
//              wrapped: the deck gets the key and skips past a switched-off track.
//
//              ON FOOT the Radioport raises nothing when its track changes, so it is polled once
//              a second while it is on. A change feeds the deck the same way and, when the
//              player asks for it, raises the same UI event so the vehicle popup shows for the
//              Radioport too. The poll runs only while the pocket radio is on and the player is
//              not in a vehicle; nothing here runs per frame.
//
//              THE WAY IN TO THE POPUP IS THE GAME'S OWN SONG-CHANGED EVENT. The controller's
//              show method is private, so a popup asked for by a key is a raised
//              VehicleRadioSongChanged carrying the track already playing; RadioXLPopup marks
//              that event as this mod's so it is not also read as a new song.
// File Version: 0.3.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL

// --- the popup ------------------------------------------------------------------------------

// Holds the widget and the two one-shot flags that tell the wrapped handlers a show came from
// this mod rather than from the game.
public class RadioXLPopup extends ScriptableService {
  private let m_widget: wref<VehicleSummonWidgetGameController>;
  private let m_force: Bool;
  private let m_suppress: Bool;

  public final static func Get() -> ref<RadioXLPopup> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLPopup") as RadioXLPopup;
  }

  public func Register(widget: ref<VehicleSummonWidgetGameController>) -> Void {
    this.m_widget = widget;
  }

  // Show what is playing now. `track` is only what the event carries; the widget reads the
  // receiver itself.
  public func Show(gi: GameInstance, track: CName) -> Void {
    this.m_force = true;
    this.m_suppress = true;
    let evt = new VehicleRadioSongChanged();
    evt.radioSongName = track;
    GameInstance.GetUISystem(gi).QueueEvent(evt);
  }

  public func ConsumeForce() -> Bool {
    let value: Bool = this.m_force;
    this.m_force = false;
    return value;
  }

  public func ConsumeSuppress() -> Bool {
    let value: Bool = this.m_suppress;
    this.m_suppress = false;
    return value;
  }
}

@wrapMethod(VehicleSummonWidgetGameController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  let popup = RadioXLPopup.Get();
  if IsDefined(popup) { popup.Register(this); }
  return result;
}

// --- the vehicle popup ---------------------------------------------------------------------

@wrapMethod(VehicleSummonWidgetGameController)
protected cb func OnVehicleRadioSongChanged(evt: ref<VehicleRadioSongChanged>) -> Bool {
  // The event carries the new track's key when a track starts. The game also raises it with no
  // key when a radio is switched on, and the track already playing may be one the player has
  // switched off, so that case reads the receiver instead.
  let popup = RadioXLPopup.Get();
  let ours: Bool = IsDefined(popup) && popup.ConsumeSuppress();
  let deck = RadioXLDeck.Get();
  if IsDefined(deck) && !ours {
    let gi = this.GetPlayerControlledObject().GetGame();
    if IsNameValid(evt.radioSongName) {
      deck.Arrived(gi, NameToHash(evt.radioSongName));
    } else {
      deck.ArrivedCurrent(gi);
    }
  }
  return wrappedMethod(evt);
}

// The vanilla popup reads the widget's last vehicle, which stays set after the player gets out,
// so on foot it would show that car's station. The receiver is decided here first: in a vehicle
// the vanilla path runs; on foot with the Radioport on, the same widget shows the Radioport's
// station and song. The on-screen line follows whichever receiver is playing.
@wrapMethod(VehicleSummonWidgetGameController)
private final func TryShowVehicleRadioNotification() -> Bool {
  let popup = RadioXLPopup.Get();
  let forced: Bool = IsDefined(popup) && popup.ConsumeForce();
  let controls = RadioXLControls.Get();
  let player = this.GetPlayerControlledObject() as PlayerPuppet;
  if !IsDefined(controls) || !IsDefined(player) {
    return wrappedMethod();
  }
  let vehicle = player.GetMountedVehicle();
  if IsDefined(vehicle) {
    let shown: Bool = wrappedMethod();
    if shown && controls.notifyOnscreen {
      RadioXLNotify.Onscreen(player.GetGame(), vehicle.GetRadioReceiverStationName(), vehicle.GetRadioReceiverTrackName());
    }
    return shown;
  }
  let pocket = player.GetPocketRadio();
  if !IsDefined(pocket) || !pocket.IsActive() { return false; }
  if controls.notifyOnscreen {
    RadioXLNotify.Onscreen(player.GetGame(), pocket.GetStationName(), pocket.GetTrackName());
  }
  if !controls.notifyRadioport && !forced { return false; }
  this.m_rootWidget.SetVisible(true);
  inkWidgetRef.SetVisible(this.m_radioStationName, true);
  inkWidgetRef.SetVisible(this.m_subText, true);
  inkTextRef.SetText(this.m_radioStationName, GetLocalizedTextByKey(pocket.GetStationName()));
  inkTextRef.SetText(this.m_subText, GetLocalizedTextByKey(pocket.GetTrackName()));
  this.PlayAnimation(n"OnSongChanged", new inkAnimOptions(), n"OnTimeOut");
  return true;
}

// The on-screen line at the left of the screen: the station, then the song. Sent through the
// notifications blackboard, which the HUD's on-screen message controller listens to.
//
// THE DURATION IS NOT OPTIONAL. The controller shows the message and schedules its own hide
// from `duration`; a message with none stays on screen until another message replaces it, and
// while it is there it displaces every other HUD element below it.
public class RadioXLNotify {
  public static func Onscreen(gi: GameInstance, station: CName, track: CName) -> Void {
    RadioXLNotify.Line(gi, GetLocalizedTextByKey(station) + "\n" + GetLocalizedTextByKey(track));
  }

  // Any text, the same way.
  public static func Line(gi: GameInstance, text: String) -> Void {
    let message: SimpleScreenMessage;
    message.isShown = true;
    message.duration = 4.0;
    message.message = text;
    let defs = GetAllBlackboardDefs();
    let board = GameInstance.GetBlackboardSystem(gi).Get(defs.UI_Notifications);
    if IsDefined(board) {
      board.SetVariant(defs.UI_Notifications.OnscreenMessage, ToVariant(message), true);
    }
  }
}

// --- the Radioport poll -----------------------------------------------------------------------

public class RadioXLPocketTick extends DelayCallback {
  public let watch: wref<RadioXLPocketWatch>;
  public let generation: Int32;

  public func Call() -> Void {
    if IsDefined(this.watch) {
      this.watch.Tick(this.generation);
    }
  }
}

// A session's delay callbacks do not survive that session, and Session/Ready fires for the main
// menu and again for a loaded save, so every session starts a new chain and a generation
// retires the old one.
public class RadioXLPocketWatch extends ScriptableService {
  private let m_generation: Int32;
  private let m_lastTrack: CName;

  private cb func OnLoad() {
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Session/Ready", this, n"OnSessionReady");
  }

  private cb func OnSessionReady(event: ref<GameSessionEvent>) {
    let reqs = GameInstance.GetSystemRequestsHandler();
    if IsDefined(reqs) && reqs.IsPreGame() { return; }
    this.m_generation += 1;
    this.m_lastTrack = n"None";
    this.Arm(this.m_generation);
  }

  public func Tick(generation: Int32) -> Void {
    if generation != this.m_generation { return; }
    this.Arm(generation);
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) { return; }
    let gi = GetGameInstance();
    let player = GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) { return; }
    if IsDefined(player.GetMountedVehicle()) {
      this.m_lastTrack = n"None";
      return;
    }
    let pocket = player.GetPocketRadio();
    if !IsDefined(pocket) || !pocket.IsActive() {
      this.m_lastTrack = n"None";
      return;
    }
    let track = pocket.GetTrackName();
    if Equals(track, this.m_lastTrack) { return; }
    let first: Bool = Equals(this.m_lastTrack, n"None");
    this.m_lastTrack = track;
    if !IsNameValid(track) || Equals(track, n"Gameplay-Devices-Radio-NoneTrack") { return; }
    let deck = RadioXLDeck.Get();
    if IsDefined(deck) {
      deck.Arrived(gi, NameToHash(track));
    }
    // The first read after the radio comes on is the track already playing, not a change, and
    // it is shown too: the Radioport switching on is when the player wants to know what is on.
    if controls.notifyRadioport || controls.notifyOnscreen {
      let evt = new VehicleRadioSongChanged();
      evt.radioSongName = track;
      GameInstance.GetUISystem(gi).QueueEvent(evt);
    }
  }

  private func Arm(generation: Int32) -> Void {
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) { return; }
    let tick = new RadioXLPocketTick();
    tick.watch = this;
    tick.generation = generation;
    delay.DelayCallback(tick, 1.0);
  }
}
