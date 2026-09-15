// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The radio comes on to the player's station. When a vehicle radio powers on, when
//              the player gets into the driver's seat, or when the Radioport switches on, the
//              receiver is tuned to the remembered station a moment later.
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
// File Version: 0.3.0
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
  public func Schedule(pocket: Bool) -> Void {
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) || !controls.rememberEnabled { return; }
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) { return; }
    let tick = new RadioXLMyStationTick();
    tick.pocket = pocket;
    delay.DelayCallback(tick, 0.1);
  }

  public func Apply(pocket: Bool) -> Void {
    let gi = GetGameInstance();
    let controls = RadioXLControls.Get();
    if !IsDefined(controls) || !controls.rememberEnabled { return; }
    let player = GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) || !this.IsRadioAllowed(gi, player) { return; }
    let station = this.StationIndex();
    if station < 0 { return; }
    if pocket {
      let radio = player.GetPocketRadio();
      if !IsDefined(radio) || !radio.IsActive() || radio.IsRestricted() { return; }
      if IsDefined(player.GetMountedVehicle()) { return; }
      if radio.GetStation() == station { return; }
      let position: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(station);
      player.GetQuickSlotsManager().SendRadioEvent(true, true, position);
      RadioXLLog(s"Radioport tuned to \(RadioXLState.Get().rememberStation) (enum \(station), dial \(position))");
      return;
    }
    let vehicle = player.GetMountedVehicle();
    if !IsDefined(vehicle) || !vehicle.IsPlayerDriver() || !vehicle.IsRadioReceiverActive() { return; }
    let radio = player.GetPocketRadio();
    if !controls.ignorePocketRadio && IsDefined(radio) && radio.IsActive() { return; }
    let current: Int32 = Cast<Int32>(vehicle.GetCurrentRadioIndex());
    if current == station { return; }
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

  // The same five conditions the game's own radio input honours.
  private func IsRadioAllowed(gi: GameInstance, player: ref<PlayerPuppet>) -> Bool {
    if StatusEffectSystem.ObjectHasStatusEffectWithTag(player, n"VehicleBlockRadioInput") { return false; }
    if StatusEffectSystem.ObjectHasStatusEffectWithTag(player, n"VehicleScene") { return false; }
    if GameInstance.GetQuestsSystem(gi).GetFact(n"unlock_car_hud_dpad") == 0 { return false; }
    if player.IsInPoliceVehicle() || player.IsJohnnyReplacer() { return false; }
    return true;
  }
}

// --- the three moments a receiver comes on -----------------------------------------------------

@wrapMethod(VehicleComponent)
protected cb func OnVehicleRadioStationInitialized(evt: ref<VehicleRadioStationInitialized>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let controls = RadioXLControls.Get();
  if IsDefined(controls) && controls.playOnVehiclePowerOn {
    let vehicle = this.GetVehicle();
    if IsDefined(vehicle) && vehicle.IsPlayerMounted() && vehicle.IsPlayerDriver() {
      RadioXLMyStation.Get().Schedule(false);
    }
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
      RadioXLMyStation.Get().Schedule(false);
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
      RadioXLMyStation.Get().Schedule(false);
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
    RadioXLMyStation.Get().Schedule(true);
  }
}
