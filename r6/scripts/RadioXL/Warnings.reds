// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: A red warning in game when a stream station cannot play, naming what AudioXL.ini
//              needs. Shown once per station per game launch.
// File Version: 0.7.0
// ======================================================================================
//
// A stream needs the player to allow it in AudioXL.ini, and a station that is not allowed is
// silent with nothing on screen to say why. Three causes, told apart without asking AudioXL:
//
//   http is off        RadioXL checks it before registering the stream
//   the host is not    AudioXL refuses the registration at once; the host is the URL's own
//   allowed
//   no connection      the row never appears: a redirect to a host that is not allowed, or a
//                      station that did not answer. AudioXL's log names a refused host
//
// The last is known only once AudioXL has given up on the stream, so the check repeats until every
// stream station has an answer.

module RadioXL

public class RadioXLWarningTick extends DelayCallback {
  public let warnings: wref<RadioXLWarnings>;

  public func Call() -> Void {
    if IsDefined(this.warnings) { this.warnings.Check(); }
  }
}

public class RadioXLWarnings extends ScriptableService {
  // Stations already warned about, for this game launch.
  private let m_warned: array<CName>;
  private let m_queue: array<String>;
  private let m_showing: Bool;
  private let m_checks: Int32;
  private let m_armed: Bool;

  public final static func Get() -> ref<RadioXLWarnings> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(n"RadioXL.RadioXLWarnings") as RadioXLWarnings;
  }

  // Whether a station has been warned about this game launch; the API test reads it.
  public func Warned(station: CName) -> Bool {
    return ArrayContains(this.m_warned, station);
  }

  // The HUD is up and can show an alert. Called on every load; the stations warned about stay warned.
  public func OnHudReady() -> Void {
    this.m_checks = 0;
    if !this.m_armed {
      this.m_armed = true;
      this.Later(3.0);
    }
  }

  private func Later(seconds: Float) -> Void {
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) {
      this.m_armed = false;
      return;
    }
    let tick = new RadioXLWarningTick();
    tick.warnings = this;
    delay.DelayCallback(tick, seconds);
  }

  public func Check() -> Void {
    this.m_armed = false;
    let waiting: Bool = false;
    let stations: array<CName> = RadioXLAPI.Stations();
    for station in stations {
      if RadioXLAPI.IsStreamStation(station) && !ArrayContains(this.m_warned, station) {
        let text: String = this.Warning(station);
        if StrLen(text) > 0 {
          ArrayPush(this.m_warned, station);
          RadioXLLog(s"stream warning shown for \(station)");
          this.Show(text);
        } else if Equals(RadioXLAPI.StreamState(station), RadioXLStreamState.Connecting) {
          waiting = true;
        }
      }
    }
    // AudioXL can take minutes to give up on a stream; checked every 15 seconds for five minutes.
    this.m_checks += 1;
    if waiting && this.m_checks < 20 {
      this.m_armed = true;
      this.Later(15.0);
    }
  }

  // The warning for a stream station that cannot play, or "" while it can or is still connecting.
  private func Warning(station: CName) -> String {
    let state: RadioXLStreamState = RadioXLAPI.StreamState(station);
    let name: String = RadioXLAPI.StationName(station);
    if Equals(state, RadioXLStreamState.Blocked) {
      return StrReplace(RadioXLText("RadioXL.warnStreamOff"), "{station}", name);
    }
    if !Equals(state, RadioXLStreamState.Failed) { return ""; }
    let service = RadioXLService.Get();
    let slot: Int32 = RadioXLWarnings.Slot(station);
    if slot >= 0 && IsDefined(service) && service.IsRefused(RadioXL_StationTrack(slot, 0)) {
      let text: String = StrReplace(RadioXLText("RadioXL.warnStreamHost"), "{station}", name);
      return StrReplace(text, "{host}", RadioXLWarnings.Host(RadioXL_StationTrackFile(slot, 0)));
    }
    return StrReplace(RadioXLText("RadioXL.warnStreamFailed"), "{station}", name);
  }

  private final static func Slot(station: CName) -> Int32 {
    let count: Int32 = RadioXL_StationCount();
    let i: Int32 = 0;
    while i < count {
      if Equals(RadioXL_StationName(i), station) { return i; }
      i += 1;
    }
    return -1;
  }

  // The host part of a URL: between "://" and the next "/", ":" or "?".
  private final static func Host(url: String) -> String {
    let start: Int32 = StrFindFirst(url, "://");
    let rest: String = start >= 0 ? StrMid(url, start + 3) : url;
    let end: Int32 = StrLen(rest);
    let i: Int32 = 0;
    while i < StrLen(rest) {
      let c: String = StrMid(rest, i, 1);
      if Equals(c, "/") || Equals(c, ":") || Equals(c, "?") {
        end = i;
        break;
      }
      i += 1;
    }
    return StrLeft(rest, end);
  }

  // One alert at a time: the warning slot shows the newest message, so a second waits for the first.
  private func Show(text: String) -> Void {
    ArrayPush(this.m_queue, text);
    if !this.m_showing { this.Next(); }
  }

  public func Next() -> Void {
    if ArraySize(this.m_queue) == 0 {
      this.m_showing = false;
      return;
    }
    this.m_showing = true;
    let text: String = this.m_queue[0];
    ArrayErase(this.m_queue, 0);
    let msg: SimpleScreenMessage;
    msg.isShown = true;
    msg.duration = 10.0;
    msg.message = text;
    msg.type = SimpleMessageType.Negative;
    GameInstance.GetBlackboardSystem(GetGameInstance())
      .Get(GetAllBlackboardDefs().UI_Notifications)
      .SetVariant(GetAllBlackboardDefs().UI_Notifications.WarningMessage, ToVariant(msg), true);
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if IsDefined(delay) {
      let tick = new RadioXLWarningNext();
      tick.warnings = this;
      delay.DelayCallback(tick, 11.0);
    } else {
      this.m_showing = false;
    }
  }
}

public class RadioXLWarningNext extends DelayCallback {
  public let warnings: wref<RadioXLWarnings>;

  public func Call() -> Void {
    if IsDefined(this.warnings) { this.warnings.Next(); }
  }
}

// The HUD is up. The warning slot drops a message sent before its controller is listening, so the
// check starts here rather than on a timer.
@wrapMethod(QuestTrackerGameController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  let warnings = RadioXLWarnings.Get();
  if IsDefined(warnings) { warnings.OnHudReady(); }
  return result;
}
