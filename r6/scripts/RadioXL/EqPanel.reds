// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The equaliser panel to the right of the station selection UI.
//
//              The panel is radioxl\gui\eq_panel.inkwidget, item "panel": copies of the game's own
//              widgets (the popup's title bar and hints, the settings menu's selector, slider and
//              switch), made by tools/eq-panel-ink.py. This file places it, fills its text and
//              wires its controls. It is spawned inside the popup's root, so it opens and closes
//              with it. Every control writes through RadioXLAPI, so a change is heard at once, and
//              the panel redraws on RadioXL/EqChanged and on a station change.
// File Version: 0.8.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL

// One clickable control: the panel is told which one.
public class RadioXLEqClick extends IScriptable {
  public let panel: wref<RadioXLEqPanel>;
  public let action: Int32;

  protected cb func OnRelease(e: ref<inkPointerEvent>) -> Bool {
    if (e.IsAction(n"click") || e.IsAction(n"mouse_left")) && IsDefined(this.panel) {
      this.panel.Click(this.action);
    }
    return true;
  }
}

// One slider: a band (0 to 8) or the boost (-1).
public class RadioXLEqSlider extends IScriptable {
  public let panel: wref<RadioXLEqPanel>;
  public let band: Int32;
  public let controller: wref<inkSliderController>;
  public let value: wref<inkText>;

  protected cb func OnSliderValueChanged(slider: wref<inkSliderController>, progress: Float, value: Float) -> Bool {
    if IsDefined(this.panel) {
      // A vertical slider's minimum is at the top, so a band slider holds the negated gain.
      this.panel.Slid(this.band, this.band < 0 ? RoundMath(value) : -RoundMath(value));
    }
    return true;
  }
}

public class RadioXLEqPanel extends IScriptable {
  // Click actions.
  private let m_actScope: Int32 = 1;
  private let m_actPrevPreset: Int32 = 3;
  private let m_actNextPreset: Int32 = 4;
  private let m_actPrevProcessing: Int32 = 5;
  private let m_actNextProcessing: Int32 = 6;
  private let m_actStage: Int32 = 10;  // + the stage, 0 to 2
  private let m_actBandUp: Int32 = 20; // + the band
  private let m_actBandDown: Int32 = 40;
  private let m_actBoostDown: Int32 = 60;
  private let m_actBoostUp: Int32 = 61;
  private let m_actReset: Int32 = 70;

  private let m_root: wref<inkCompoundWidget>;
  private let m_scope: wref<inkText>;
  private let m_preset: wref<inkText>;
  private let m_processing: wref<inkText>;
  private let m_stages: array<wref<inkWidget>>;
  private let m_sliders: array<ref<RadioXLEqSlider>>;
  private let m_boost: ref<RadioXLEqSlider>;
  private let m_clicks: array<ref<RadioXLEqClick>>;
  // True while the panel sets its own sliders, so their change callbacks write nothing back.
  private let m_drawing: Bool;

  public func Build(owner: ref<inkGameController>) -> Void {
    let root = owner.SpawnFromExternal(owner.GetRootCompoundWidget(), r"radioxl\\gui\\eq_panel.inkwidget", n"panel") as inkCompoundWidget;
    if !IsDefined(root) { return; }
    root.SetAnchor(inkEAnchor.Centered);
    root.SetAnchorPoint(0.5, 0.5);
    // The popup's frame is 1170 wide in the middle; the panel sits 60 to its right.
    root.SetTranslation(new Vector2(585.0 + 60.0 + 450.0, 0.0));
    this.m_root = root;

    let content: String = "containerRoot/wrapper/setup/content/";
    this.SetText(this.At("containerRoot/wrapper/setup/top_holder/title"), RadioXLText("RadioXL.eqTitle"));

    this.m_scope = this.Selector(content + "scope", RadioXLText("RadioXL.eqScope"), this.m_actScope, this.m_actScope);
    this.m_preset = this.Selector(content + "preset", RadioXLText("RadioXL.optEqPreset"), this.m_actPrevPreset, this.m_actNextPreset);
    this.m_processing = this.Selector(content + "processing", RadioXLText("RadioXL.optProcessing"), this.m_actPrevProcessing, this.m_actNextProcessing);

    let band: Int32 = 0;
    while band < RadioXL_EqBandCount() {
      let fader: String = content + s"bands/fader\(band)/";
      this.SetText(this.At(fader + "label"), RadioXLText(s"RadioXL.eqBand\(band)"));
      let cell: String = fader + s"band\(band)";
      ArrayPush(this.m_sliders, this.Slider(cell, band, -12.0, 12.0));
      this.Clickable(this.At(cell + "/btnRight"), this.m_actBandUp + band);
      this.Clickable(this.At(cell + "/btnLeft"), this.m_actBandDown + band);
      band += 1;
    }

    let keys: array<String> = ["RadioXL.optProcAgc", "RadioXL.optProcPeak", "RadioXL.optProcLimiter"];
    let i: Int32 = 0;
    while i < 3 {
      let row: String = content + s"stage\(i)";
      this.SetText(this.At(row + "/layout/labels/label"), RadioXLText(keys[i]));
      this.SetText(this.At(row + "/layout/container/onState/body/txtValue"), RadioXLText("RadioXL.songOn"));
      this.SetText(this.At(row + "/layout/container/offState/body/txtValue"), RadioXLText("RadioXL.songOff"));
      this.Clickable(this.At(row + "/layout/container"), this.m_actStage + i);
      ArrayPush(this.m_stages, this.At(row));
      i += 1;
    }

    let boost: String = content + "boost";
    this.SetText(this.At(boost + "/layout/labels/label"), RadioXLText("RadioXL.eqBoost"));
    this.m_boost = this.Slider(boost + "/layout/container", -1, 0.0, Cast<Float>(RadioXL_MaxBoost()));
    this.Clickable(this.At(boost + "/layout/container/btnLeft"), this.m_actBoostDown);
    this.Clickable(this.At(boost + "/layout/container/btnRight"), this.m_actBoostUp);

    // Save as preset waits on keyboard naming; its hint stays hidden until then.
    let save: wref<inkWidget> = this.At(content + "inputHints/hintSave");
    if IsDefined(save) { save.SetVisible(false); }
    this.SetText(this.At(content + "inputHints/hintReset/text"), RadioXLText("RadioXL.eqReset"));
    this.Clickable(this.At(content + "inputHints/hintReset"), this.m_actReset);

    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/EqChanged", this, n"OnEqChanged");
    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/StationChanged", this, n"OnStationChanged");
    this.Draw();
  }

  public func Close() -> Void {
    GameInstance.GetCallbackSystem().UnregisterCallback(n"RadioXL/EqChanged", this);
    GameInstance.GetCallbackSystem().UnregisterCallback(n"RadioXL/StationChanged", this);
  }

  private cb func OnEqChanged(e: ref<RadioXLEqChangedEvent>) { this.Draw(); }
  private cb func OnStationChanged(e: ref<RadioXLStationChangedEvent>) { this.Draw(); }

  // --- the copied widgets ------------------------------------------------------------------------

  // A widget by its path below the panel, one name at a time.
  private func At(path: String) -> wref<inkWidget> {
    let parts: array<String> = StrSplit(path, "/");
    let widget: wref<inkWidget> = this.m_root;
    let i: Int32 = 0;
    while i < ArraySize(parts) && IsDefined(widget) {
      let compound: wref<inkCompoundWidget> = widget as inkCompoundWidget;
      widget = IsDefined(compound) ? compound.GetWidget(StringToName(parts[i])) : null;
      i += 1;
    }
    return widget;
  }

  private func SetText(widget: wref<inkWidget>, text: String) -> Void {
    let t: wref<inkText> = widget as inkText;
    if IsDefined(t) { t.SetText(text); }
  }

  private func Clickable(widget: wref<inkWidget>, action: Int32) -> Void {
    if !IsDefined(widget) { return; }
    let click = new RadioXLEqClick();
    click.panel = this;
    click.action = action;
    ArrayPush(this.m_clicks, click);
    widget.SetInteractive(true);
    widget.RegisterToCallback(n"OnRelease", click, n"OnRelease");
  }

  // A settings menu selector row: its label and two arrows; returns its value text.
  private func Selector(row: String, label: String, prev: Int32, next: Int32) -> wref<inkText> {
    this.SetText(this.At(row + "/layout/labels/label"), label);
    let dots: wref<inkWidget> = this.At(row + "/layout/container/dots");
    if IsDefined(dots) { dots.SetVisible(false); }
    this.Clickable(this.At(row + "/layout/container/btnLeft"), prev);
    this.Clickable(this.At(row + "/layout/container/btnRight"), next);
    return this.At(row + "/layout/container/txtValue") as inkText;
  }

  // The settings slider's own controller, set to this slider's range.
  private func Slider(cell: String, band: Int32, min: Float, max: Float) -> ref<RadioXLEqSlider> {
    let slider = new RadioXLEqSlider();
    slider.panel = this;
    slider.band = band;
    let widget: wref<inkWidget> = this.At(cell);
    if IsDefined(widget) {
      slider.controller = widget.GetControllerByType(n"inkSliderController") as inkSliderController;
      slider.value = this.At(cell + "/slidingArea/knob/txtValue") as inkText;
    }
    if IsDefined(slider.controller) {
      slider.controller.Setup(min, max, 0.0, 1.0);
      slider.controller.RegisterToCallback(n"OnSliderValueChanged", slider, n"OnSliderValueChanged");
    }
    return slider;
  }

  // --- what the controls do ----------------------------------------------------------------------

  private func Station() -> CName {
    return RadioXLAPI.CurrentStation();
  }

  private func Own() -> Bool {
    return StrLen(RadioXLAPI.StationEqPreset(this.Station())) > 0;
  }

  // The choices the preset arrows step through: every preset, then Custom.
  private func Choices() -> array<String> {
    let names: array<String> = RadioXLAPI.EqPresets();
    ArrayPush(names, RadioXL_EqCustom());
    return names;
  }

  public func Click(action: Int32) -> Void {
    let station: CName = this.Station();
    if Equals(station, n"None") { return; }
    if action == this.m_actScope {
      if this.Own() {
        RadioXLAPI.SetStationEqPreset(station, "");
      } else {
        // The station takes what it plays now, so the switch changes nothing that is heard.
        let global: String = RadioXLAPI.EqPreset();
        RadioXLAPI.SetStationEqPreset(station, global);
      }
    } else if action == this.m_actPrevPreset || action == this.m_actNextPreset {
      this.StepPreset(action == this.m_actNextPreset ? 1 : -1);
    } else if action == this.m_actPrevProcessing || action == this.m_actNextProcessing {
      let mode: Int32 = EnumInt(RadioXLAPI.Processing()) + (action == this.m_actNextProcessing ? 1 : 2);
      RadioXLAPI.SetProcessing(IntEnum<RadioXLProcessing>(mode % 3));
    } else if action >= this.m_actStage && action < this.m_actStage + 3 {
      if Equals(RadioXLAPI.Processing(), RadioXLProcessing.Custom) {
        let stage: RadioXLProcessingStage = IntEnum<RadioXLProcessingStage>(action - this.m_actStage);
        RadioXLAPI.SetProcessingStage(stage, !RadioXLAPI.ProcessingStage(stage));
      }
    } else if action >= this.m_actBandUp && action < this.m_actBandUp + 9 {
      let band: Int32 = action - this.m_actBandUp;
      this.SetBand(band, RadioXLEqualiser.Bands(station)[band] + 1);
    } else if action >= this.m_actBandDown && action < this.m_actBandDown + 9 {
      let band: Int32 = action - this.m_actBandDown;
      this.SetBand(band, RadioXLEqualiser.Bands(station)[band] - 1);
    } else if action == this.m_actBoostDown {
      RadioXLAPI.SetBoost(RadioXLAPI.Boost() - 1);
    } else if action == this.m_actBoostUp {
      RadioXLAPI.SetBoost(RadioXLAPI.Boost() + 1);
    } else if action == this.m_actReset {
      this.Reset();
    }
    this.Draw();
  }

  public func Slid(band: Int32, value: Int32) -> Void {
    if this.m_drawing { return; }
    if band < 0 {
      RadioXLAPI.SetBoost(value);
    } else {
      this.SetBand(band, value);
    }
    this.Draw();
  }

  private func StepPreset(step: Int32) -> Void {
    let station: CName = this.Station();
    let choices: array<String> = this.Choices();
    let current: String = RadioXLEqualiser.Active(station);
    let i: Int32 = 0;
    let at: Int32 = 0;
    while i < ArraySize(choices) {
      if Equals(StrLower(choices[i]), StrLower(current)) { at = i; }
      i += 1;
    }
    let next: String = choices[(at + step + ArraySize(choices)) % ArraySize(choices)];
    if this.Own() {
      RadioXLAPI.SetStationEqPreset(station, next);
    } else {
      RadioXLAPI.SetEqPreset(next);
    }
  }

  // A band moved: the station's own bands under This station, the global Custom bands under Global.
  // Either way the side that was on a preset starts its custom bands from what it played.
  private func SetBand(band: Int32, value: Int32) -> Void {
    let station: CName = this.Station();
    if this.Own() {
      RadioXLAPI.SetStationEqBand(station, band, value);
      return;
    }
    if !Equals(RadioXLAPI.EqPreset(), RadioXL_EqCustom()) {
      let playing: array<Int32> = RadioXLEqualiser.Bands(station);
      let b: Int32 = 0;
      while b < RadioXL_EqBandCount() {
        RadioXLAPI.SetEqBand(b, playing[b]);
        b += 1;
      }
      RadioXLAPI.SetEqPreset(RadioXL_EqCustom());
    }
    RadioXLAPI.SetEqBand(band, value);
  }

  // This station: back to RadioXL's suggestion, else the global equaliser. Global: back to Flat.
  private func Reset() -> Void {
    let station: CName = this.Station();
    if this.Own() {
      RadioXLAPI.SetStationEqPreset(station, RadioXLAPI.SuggestedEqPreset(station));
    } else {
      RadioXLAPI.SetEqPreset("Flat");
    }
  }

  // --- drawing -----------------------------------------------------------------------------------

  public func Draw() -> Void {
    let station: CName = this.Station();
    let own: Bool = this.Own();
    if IsDefined(this.m_scope) { this.m_scope.SetText(RadioXLText(own ? "RadioXL.eqThisStation" : "RadioXL.eqGlobal")); }

    let active: String = RadioXLEqualiser.Active(station);
    let shown: String = Equals(active, RadioXL_EqCustom()) ? RadioXLText("RadioXL.eqCustom") : active;
    if own && StrLen(RadioXLAPI.SuggestedEqPreset(station)) > 0 && Equals(active, RadioXLAPI.SuggestedEqPreset(station)) {
      shown = StrReplace(RadioXLText("RadioXL.eqSuggested"), "{preset}", active);
    }
    if IsDefined(this.m_preset) { this.m_preset.SetText(shown); }

    this.m_drawing = true;
    let bands: array<Int32> = RadioXLEqualiser.Bands(station);
    let b: Int32 = 0;
    while b < ArraySize(this.m_sliders) && b < ArraySize(bands) {
      if IsDefined(this.m_sliders[b].controller) { this.m_sliders[b].controller.ChangeValue(Cast<Float>(-bands[b])); }
      if IsDefined(this.m_sliders[b].value) {
        this.m_sliders[b].value.SetText(bands[b] > 0 ? s"+\(bands[b])" : s"\(bands[b])");
      }
      b += 1;
    }
    if IsDefined(this.m_boost) {
      if IsDefined(this.m_boost.controller) { this.m_boost.controller.ChangeValue(Cast<Float>(RadioXLAPI.Boost())); }
      if IsDefined(this.m_boost.value) { this.m_boost.value.SetText(s"+\(RadioXLAPI.Boost()) dB"); }
    }
    this.m_drawing = false;

    let mode: RadioXLProcessing = RadioXLAPI.Processing();
    let names: array<String> = ["RadioXL.procOff", "RadioXL.procBroadcast", "RadioXL.procCustom"];
    if IsDefined(this.m_processing) { this.m_processing.SetText(RadioXLText(names[EnumInt(mode)])); }
    let i: Int32 = 0;
    while i < ArraySize(this.m_stages) {
      let on: Bool = Equals(mode, RadioXLProcessing.Broadcast)
        || (Equals(mode, RadioXLProcessing.Custom) && RadioXLAPI.ProcessingStage(IntEnum<RadioXLProcessingStage>(i)));
      let row: String = s"containerRoot/wrapper/setup/content/stage\(i)/layout/container/";
      let onState: wref<inkWidget> = this.At(row + "onState");
      let offState: wref<inkWidget> = this.At(row + "offState");
      if IsDefined(onState) { onState.SetVisible(on); }
      if IsDefined(offState) { offState.SetVisible(!on); }
      // The switches take a click only on Custom.
      if IsDefined(this.m_stages[i]) { this.m_stages[i].SetOpacity(Equals(mode, RadioXLProcessing.Custom) ? 1.0 : 0.35); }
      i += 1;
    }
  }
}

@addField(VehicleRadioPopupGameController)
private let m_radioXLEq: ref<RadioXLEqPanel>;

@wrapMethod(VehicleRadioPopupGameController)
protected cb func OnPlayerAttach(playerPuppet: ref<GameObject>) -> Bool {
  let result: Bool = wrappedMethod(playerPuppet);
  let panel = new RadioXLEqPanel();
  panel.Build(this);
  this.m_radioXLEq = panel;
  return result;
}

@wrapMethod(VehicleRadioPopupGameController)
protected func OnClose() -> Void {
  if IsDefined(this.m_radioXLEq) { this.m_radioXLEq.Close(); }
  wrappedMethod();
}

// The station popup opens with the cursor, so the panel can be used with the mouse. The game's own body, with
// isBlocking and useCursor set as the game's own cursor popups have them. ShowGameNotification is native and
// the notification data is built inside this function, so there is nothing to wrap.
@replaceMethod(PopupsManager)
private final func SpawnVehicleRadioPopup() -> Void {
  let data: ref<inkGameNotificationData>;
  if !this.CanShowExclusivePopUp() {
    return;
  }
  this.m_isBlockingPopupOpened = true;
  data = new inkGameNotificationData();
  data.notificationName = n"base\\gameplay\\gui\\widgets\\vehicle_control\\vehicles_radio.inkwidget";
  data.queueName = n"VehiclesRadio";
  // A cursor moves only over a blocking notification; without it the mouse stays with the camera.
  data.isBlocking = true;
  data.useCursor = true;
  this.m_vehicleRadioToken = this.ShowGameNotification(data);
  this.m_vehicleRadioToken.RegisterListener(this, n"OnVehicleRadioCloseRequest");
  this.m_blackboard.SetBool(this.m_bbDefinition.Popup_Radio_IsShown, true);
}
