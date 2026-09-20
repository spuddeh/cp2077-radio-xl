// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The radio comes on to the player's station. When a vehicle radio powers on, when
//              the player gets into the driver's seat, or when the Radioport switches on, the
//              receiver is tuned to the remembered station a moment later.
//
//              A CAR RESUMES ITS LAST STATION AFTER THE SEAT IS TAKEN, so the pass made on
//              sitting down finds the receiver off and tunes nothing. The resume is caught through
//              OnVehicleRadioStationChanged instead, which arrives when it happens rather than at
//              a time guessed in advance. Sitting down arms that catch and the first change
//              disarms it, so a station the player picks by hand afterwards is left alone.
//
//              THE STATION IS REMEMBERED BY ITS EVENT NAME, never by enum value or dial
//              position: both numbers move when a station mod is installed or removed, and the
//              name is the one thing a station keeps. It is resolved to the enum at the moment
//              of tuning, through RadioStationDataProvider, which this framework extends.
//
//              TWO CALLS, TWO NUMBERS. A vehicle receiver takes the ENUM
//              (SetRadioReceiverStation); the Radioport is tuned through the quick-slots
//              manager, which takes the DIAL POSITION (SendRadioEvent). Mixing them plays the
//              wrong station one slot away.
// File Version: 0.4.1
// Credits: psiberx (Codeware), Always My Radio Station by Krakhel (the behaviour)
// ======================================================================================

module RadioXL

public class RadioXLMyStationTick extends DelayCallback {
  public let pocket: Bool;

  public func Call() -> Void {
    let memory = RadioXLMyStation.Get();
    if IsDefined(memory) {
      memory.Apply(this.pocket);
    }
  }
}

public class RadioXLMyStation extends ScriptableService {
  public final static func Get() -> ref<RadioXLMyStation> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLMyStation") as RadioXLMyStation;
  }

  // Whether a car is expected to resume its station, and the engine second the seat was taken.
  //
  // THE CAR RESUMES ITS LAST STATION AFTER THE SEAT IS TAKEN, NOT BEFORE. Measured at 200 to 320 ms
  // past `DriveEvents.OnEnter`, so a receiver read at that moment is still off and no timer set
  // there can be trusted to outlast it. The resume announces itself through
  // `OnVehicleRadioStationChanged`, and the FIRST such change after the seat is taken is that
  // resume. A change after it is the player choosing a station by hand and is left alone.
  private let m_armed: Bool;
  private let m_armedAt: Float;

  // Five seconds is a backstop for a car whose radio is off, which never resumes and so never
  // disarms. The window is not a race: the first change closes it.
  private let m_armWindow: Float = 5.0;

  public func Arm(gi: GameInstance) -> Void {
    this.m_armed = true;
    this.m_armedAt = EngineTime.ToFloat(GameInstance.GetEngineTime(gi));
  }

  private func IsArmed(gi: GameInstance) -> Bool {
    if !this.m_armed { return false; }
    let now: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(gi));
    return now - this.m_armedAt <= this.m_armWindow;
  }

  // The receiver's station has changed. Only the resume is acted on, and acting disarms, so the
  // tune this schedules cannot come back through here as a second pass.
  public func OnStationChanged() -> Void {
    let gi = GetGameInstance();
    if !this.IsArmed(gi) { return; }
    this.m_armed = false;
    this.Schedule(false, "the vehicle radio resumed its station");
  }

  // The remembered station's enum value on the current dial, or -1 when it is not installed.
  public func StationIndex() -> Int32 {
    let state = RadioXLState.Get();
    if !IsDefined(state) || !IsNameValid(state.rememberStation) { return -1; }
    let count: Int32 = RadioStationDataProvider.GetStationsCount();
    let i: Int32 = 0;
    while i < count {
      if Equals(RadioStationDataProvider.GetStationName(IntEnum<ERadioStationList>(i)), state.rememberStation) {
        return i;
      }
      i += 1;
    }
    return -1;
  }

  // The receiver has just come on or the player has just sat down; the game finishes its own
  // tuning first, so the switch waits a tenth of a second.
  //
  // EVERY PATH THROUGH SCHEDULE AND APPLY LOGS, the refusals included. A receiver that stays on the
  // wrong station is one of a dozen conditions, and a silent return leaves the log looking exactly
  // like a hook that never fired. `source` names the moment that asked, so a log with no line at
  // all means none of the four wraps ran.
  public func Schedule(pocket: Bool, source: String) -> Void {
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) || !controls.rememberEnabled {
      RadioXLLog(s"my station: \(source) - tuning is switched off");
      return;
    }
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) {
      RadioXLLog(s"my station: \(source) - no delay system");
      return;
    }
    let tick = new RadioXLMyStationTick();
    tick.pocket = pocket;
    delay.DelayCallback(tick, 0.1);
    RadioXLLog(s"my station: \(source) - scheduled");
  }

  public func Apply(pocket: Bool) -> Void {
    let gi = GetGameInstance();
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) || !controls.rememberEnabled {
      RadioXLLog("my station: not tuned - tuning is switched off");
      return;
    }
    let player = GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) {
      RadioXLLog("my station: not tuned - there is no player");
      return;
    }
    let blocked: String = this.RadioBlockReason(gi, player);
    if StrLen(blocked) > 0 {
      RadioXLLog(s"my station: not tuned - \(blocked)");
      return;
    }
    let station = this.StationIndex();
    if station < 0 {
      RadioXLLog(s"my station: not tuned - \(RadioXLState.Get().rememberStation) is not installed");
      return;
    }
    if pocket {
      let radio = player.GetPocketRadio();
      if !IsDefined(radio) || !radio.IsActive() || radio.IsRestricted() {
        RadioXLLog("my station: not tuned - the Radioport is not playing");
        return;
      }
      if IsDefined(player.GetMountedVehicle()) {
        RadioXLLog("my station: not tuned - the player is in a vehicle");
        return;
      }
      if radio.GetStation() == station {
        RadioXLLog(s"my station: the Radioport is already on \(RadioXLState.Get().rememberStation)");
        return;
      }
      let position: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(station);
      player.GetQuickSlotsManager().SendRadioEvent(true, true, position);
      RadioXLLog(s"Radioport tuned to \(RadioXLState.Get().rememberStation) (enum \(station), dial \(position))");
      return;
    }
    let vehicle = player.GetMountedVehicle();
    if !IsDefined(vehicle) {
      RadioXLLog("my station: not tuned - the player is not in a vehicle");
      return;
    }
    if !vehicle.IsPlayerDriver() {
      RadioXLLog("my station: not tuned - the player is not the driver");
      return;
    }
    if !vehicle.IsRadioReceiverActive() {
      RadioXLLog("my station: not tuned - the vehicle receiver is off");
      return;
    }
    let radio = player.GetPocketRadio();
    if !controls.ignorePocketRadio && IsDefined(radio) && radio.IsActive() {
      RadioXLLog("my station: not tuned - the Radioport is playing and it holds the receiver");
      return;
    }
    let current: Int32 = Cast<Int32>(vehicle.GetCurrentRadioIndex());
    if current == station {
      RadioXLLog(s"my station: the vehicle radio is already on \(RadioXLState.Get().rememberStation)");
      return;
    }
    // An index past the provider's count is a station the game cannot name: a RadioExt station,
    // which plays through its own player and re-asserts itself if the receiver is moved. Left alone.
    if current >= RadioStationDataProvider.GetStationsCount() {
      RadioXLLog(s"vehicle radio is on station \(current), outside the dial - not tuned");
      return;
    }
    // The same call the radio popup makes when the player picks a station. It goes through the
    // vehicle component, which also writes the station name the in-car board reads and tells the
    // UI; setting the receiver directly leaves the board on the old name.
    let position: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(station);
    player.GetQuickSlotsManager().SendRadioEvent(true, true, position);
    RadioXLLog(s"vehicle radio tuned to \(RadioXLState.Get().rememberStation) (enum \(station), dial \(position))");
  }

  // The same five conditions the game's own radio input honours. An empty string is allowed; any
  // other value names the one condition that refused, and goes straight into the log.
  private func RadioBlockReason(gi: GameInstance, player: ref<PlayerPuppet>) -> String {
    if StatusEffectSystem.ObjectHasStatusEffectWithTag(player, n"VehicleBlockRadioInput") {
      return "the player carries the VehicleBlockRadioInput status effect";
    }
    if StatusEffectSystem.ObjectHasStatusEffectWithTag(player, n"VehicleScene") {
      return "the player carries the VehicleScene status effect";
    }
    if GameInstance.GetQuestsSystem(gi).GetFact(n"unlock_car_hud_dpad") == 0 {
      return "the unlock_car_hud_dpad fact is 0";
    }
    if player.IsInPoliceVehicle() { return "the player is in a police vehicle"; }
    if player.IsJohnnyReplacer() { return "the player is Johnny"; }
    return "";
  }
}

// --- the four moments a receiver comes on ------------------------------------------------------

@wrapMethod(VehicleComponent)
protected cb func OnVehicleRadioStationInitialized(evt: ref<VehicleRadioStationInitialized>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let controls = RadioXLControls.Get();
  RadioXLLog("my station: the vehicle radio reports initialized");
  if IsDefined(controls) && controls.playOnVehiclePowerOn {
    let vehicle = this.GetVehicle();
    if IsDefined(vehicle) && vehicle.IsPlayerMounted() && vehicle.IsPlayerDriver() {
      RadioXLMyStation.Get().Schedule(false, "the vehicle radio came on");
    }
  }
  return result;
}

// The engine raises this whenever the receiver's station changes, whoever changed it, so it is the
// one signal that arrives when the car resumes its station rather than a fixed time before it. The
// arming window is what separates that resume from the player's own pick.
@wrapMethod(PlayerPuppet)
protected cb func OnVehicleRadioStationChanged(evt: ref<VehicleRadioStationChanged>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let memory = RadioXLMyStation.Get();
  if IsDefined(memory) {
    memory.OnStationChanged();
  }
  return result;
}

@wrapMethod(VehicleComponent)
protected cb func OnRadioToggleEvent(evt: ref<RadioToggleEvent>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let controls = RadioXLControls.Get();
  if IsDefined(controls) && controls.playOnVehiclePowerOn {
    let vehicle = this.GetVehicle();
    if IsDefined(vehicle) && vehicle.IsPlayerMounted() && vehicle.IsPlayerDriver() && vehicle.IsRadioReceiverActive() {
      RadioXLMyStation.Get().Schedule(false, "the vehicle radio was toggled");
    }
  }
  return result;
}

@wrapMethod(DriveEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
  wrappedMethod(stateContext, scriptInterface);
  let controls = RadioXLControls.Get();
  if IsDefined(controls) && controls.playOnEnter {
    let vehicle = this.GetVehicleObject(scriptInterface);
    if IsDefined(vehicle) && vehicle.IsPlayerMounted() && vehicle.IsPlayerDriver() {
      let memory = RadioXLMyStation.Get();
      // The receiver is already on when the Radioport handed its station over, and the immediate
      // pass tunes it now. Arming covers the other case, where the car has yet to resume.
      memory.Arm(scriptInterface.GetGame());
      memory.Schedule(false, "the player sat down");
    }
  }
}

// The Radioport's own toggle handler turns it on or off; only the off-to-on edge tunes it.
@wrapMethod(PocketRadio)
public final func HandleRadioToggleEvent(evt: ref<RadioToggleEvent>) -> Void {
  let wasOn: Bool = this.m_isOn;
  wrappedMethod(evt);
  let controls = RadioXLControls.Get();
  if IsDefined(controls) && controls.playOnPocketPowerOn && !wasOn && this.m_isOn {
    RadioXLMyStation.Get().Schedule(true, "the Radioport came on");
  }
}
