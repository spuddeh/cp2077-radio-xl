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
// File Version: 0.8.1
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL

// One clickable control: the panel is told which one.
public class RadioXLEqClick extends IScriptable {
  public let panel: wref<RadioXLEqPanel>;
  public let action: Int32;
  public let widget: wref<inkWidget>;
  // The control is exactly where the keys rest the cursor (a toggle, a fader arrow): it keeps taking the
  // cursor with the keys or the pad in charge, and the d-pad outline is drawn only around a widget that does.
  public let keep: Bool;

  protected cb func OnRelease(e: ref<inkPointerEvent>) -> Bool {
    // One press raises a release for each action bound to the button; only "click" acts, or every
    // control steps twice. While the station list has the focus the press is the list's: the cursor can
    // still rest on the panel, since a snap away from a spot the stick left the cursor on does not move it.
    if e.IsAction(n"click") && IsDefined(this.panel) && this.panel.IsFocused() {
      this.panel.Click(this.action);
    }
    return true;
  }

  protected cb func OnHoverOver(e: ref<inkPointerEvent>) -> Bool {
    if IsDefined(this.panel) { this.panel.OverControl(true); }
    return false;
  }

  protected cb func OnHoverOut(e: ref<inkPointerEvent>) -> Bool {
    if IsDefined(this.panel) { this.panel.OverControl(false); }
    return false;
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
  private let m_actStage: Int32 = 10;  // + the stage, 0 to 2
  private let m_actBandUp: Int32 = 20; // + the band
  private let m_actBandDown: Int32 = 40;
  private let m_actBoostDown: Int32 = 60;
  private let m_actBoostUp: Int32 = 61;
  private let m_actReset: Int32 = 70;

  private let m_root: wref<inkCompoundWidget>;
  private let m_station: wref<inkText>;
  private let m_preset: wref<inkText>;
  private let m_sliders: array<ref<RadioXLEqSlider>>;
  private let m_boost: ref<RadioXLEqSlider>;
  private let m_clicks: array<ref<RadioXLEqClick>>;
  private let m_hovers: array<ref<RadioXLEqHover>>;
  private let m_bandHovers: array<ref<RadioXLEqHover>>;
  // The sliders' tracks: a click on one sets the value where it lands.
  private let m_tracks: array<wref<inkWidget>>;
  // True while the panel sets its own sliders, so their change callbacks write nothing back.
  private let m_drawing: Bool;

  // Keys and pad move the cursor, as the game's menus do: the rows it moves through, top to bottom, one
  // hover each. The bands are two rows, their up arrows and their down arrows.
  private let m_owner: wref<inkGameController>;
  private let m_rows: array<String>;
  // Each fader's frame, and its opacity as drawn; the frame of the fader under the cursor is drawn whole.
  private let m_bandFrames: array<wref<inkWidget>>;
  private let m_bandFrameOpacity: Float;
  private let m_focusHint: wref<inkText>;
  // The cursor is on the panel (else on the station list), on which row, and on which fader.
  private let m_focused: Bool;
  // The popup's pointer mode: a row under the cursor takes the focus only after the mouse or the stick
  // moved it, so the panel never takes the focus from a cursor resting on it as the popup opens.
  private let m_pointer: Bool;
  private let m_row: Int32;
  private let m_band: Int32;
  // The cursor is over one of the panel's controls. Proceed shares its buttons with the pointer's click
  // (pad A, Enter, F), so while this is set the press is the click's alone.
  private let m_overControl: Bool;

  public func Build(owner: ref<inkGameController>) -> Void {
    // Inside containerRoot, after the popup's own frame: it draws over the vignette as the frame does, and
    // the popup's animations, which find their widgets by child index from its root, still find them.
    let host = owner.GetRootCompoundWidget().GetWidget(n"containerRoot") as inkCompoundWidget;
    if !IsDefined(host) { return; }
    let root = owner.SpawnFromExternal(host, r"radioxl\\gui\\eq_panel.inkwidget", n"panel") as inkCompoundWidget;
    if !IsDefined(root) { return; }
    root.SetAnchor(inkEAnchor.Centered);
    root.SetAnchorPoint(0.5, 0.5);
    // The popup's frame is 1170 wide in the middle; the panel sits 60 to its right.
    root.SetTranslation(new Vector2(585.0 + 60.0 + 450.0, 0.0));
    this.m_root = root;
    this.m_owner = owner;

    let content: String = "setup/content/";
    this.SetText(this.At("setup/top_holder/title"), RadioXLText("RadioXL.eqTitle"));
    this.SetText(this.At(content + "station/caption"), RadioXLText("RadioXL.eqStation"));
    this.m_station = this.At(content + "station/name") as inkText;

    this.SwitchRow(content + "scope", RadioXLText("RadioXL.eqPerStation"), this.m_actScope);
    this.m_rows = ["scope", "preset", "bandsUp", "bandsDown", "stage0", "stage1", "stage2", "boost"];
    for row in this.m_rows {
      this.Hover(content + row);
    }
    this.m_preset = this.Selector(content + "preset", RadioXLText("RadioXL.optEqPreset"), this.m_actPrevPreset, this.m_actNextPreset);

    let band: Int32 = 0;
    while band < RadioXL_EqBandCount() {
      let fader: String = content + s"bands/fader\(band)/";
      this.SetText(this.At(fader + "label"), RadioXLText(s"RadioXL.eqBand\(band)"));
      let cell: String = fader + s"band\(band)";
      ArrayPush(this.m_sliders, this.Slider(cell, band, -12.0, 12.0));
      let frame: wref<inkWidget> = this.At(cell + "/bk");
      if IsDefined(frame) { this.m_bandFrameOpacity = frame.GetOpacity(); }
      ArrayPush(this.m_bandFrames, frame);
      this.Clickable(this.At(cell + "/btnRight"), this.m_actBandUp + band, true);
      this.Clickable(this.At(cell + "/btnLeft"), this.m_actBandDown + band, true);
      this.BandHover(this.At(cell + "/btnRight"), ArrayFindFirst(this.m_rows, "bandsUp"), band);
      this.BandHover(this.At(cell + "/btnLeft"), ArrayFindFirst(this.m_rows, "bandsDown"), band);
      band += 1;
    }

    let keys: array<String> = ["RadioXL.optProcAgc", "RadioXL.optProcPeak", "RadioXL.optProcLimiter"];
    let i: Int32 = 0;
    while i < 3 {
      this.SwitchRow(content + s"stage\(i)", RadioXLText(keys[i]), this.m_actStage + i);
      i += 1;
    }

    let boost: String = content + "boost";
    this.SetText(this.At(boost + "/layout/labels/label"), RadioXLText("RadioXL.eqBoost"));
    this.m_boost = this.Slider(boost + "/layout/container", -1, 0.0, Cast<Float>(RadioXL_MaxBoost()));
    this.Clickable(this.At(boost + "/layout/container/btnLeft"), this.m_actBoostDown);
    this.Clickable(this.At(boost + "/layout/container/btnRight"), this.m_actBoostUp);

    // Save as preset is not offered; its hint shows the key that moves the focus between list and panel.
    let display: wref<inkWidget> = this.At(content + "inputHints/hintSave/inputDisplayController");
    let input: wref<inkInputDisplayController> = IsDefined(display) ? display.GetController() as inkInputDisplayController : null;
    if IsDefined(input) { input.SetInputAction(n"secondaryAction"); }
    this.m_focusHint = this.At(content + "inputHints/hintSave/text") as inkText;
    this.SetText(this.At(content + "inputHints/hintReset/text"), RadioXLText("RadioXL.eqReset"));
    this.Clickable(this.At(content + "inputHints/hintReset"), this.m_actReset);

    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/EqChanged", this, n"OnEqChanged");
    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/StationChanged", this, n"OnStationChanged");
    this.Focus(false, false);
    this.SetPointer(false);
    this.Draw();
    RadioXLEqAnim.Open(root);
  }

  public func Close() -> Void {
    RadioXLEqAnim.Close(this.m_root);
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

  private func Clickable(widget: wref<inkWidget>, action: Int32, opt keep: Bool) -> Void {
    if !IsDefined(widget) { return; }
    let click = new RadioXLEqClick();
    click.keep = keep;
    click.panel = this;
    click.action = action;
    click.widget = widget;
    ArrayPush(this.m_clicks, click);
    widget.SetInteractive(true);
    widget.RegisterToCallback(n"OnRelease", click, n"OnRelease");
    widget.RegisterToCallback(n"OnHoverOver", click, n"OnHoverOver");
    widget.RegisterToCallback(n"OnHoverOut", click, n"OnHoverOut");
  }

  // A settings row's hover: its highlight starts hidden, as the settings menu's row controller hides it.
  // Every row gets one, so a hover's index is its row's; the two band rows have no layout, and their
  // arrows take the pointer through BandHover.
  private func Hover(row: String) -> Void {
    let hover = new RadioXLEqHover();
    hover.panel = this;
    hover.row = ArraySize(this.m_hovers);
    hover.band = -1;
    hover.label = this.At(row + "/layout/labels/label");
    hover.highlight = this.At(row + "/bk");
    if IsDefined(hover.highlight) { hover.highlight.SetVisible(false); }
    ArrayPush(this.m_hovers, hover);
    let layout: wref<inkWidget> = this.At(row + "/layout");
    if !IsDefined(layout) { return; }
    layout.SetInteractive(true);
    layout.RegisterToCallback(n"OnHoverOver", hover, n"OnHoverOver");
  }

  // A fader's arrow: the pointer over it puts the focus on that band row and that fader.
  private func BandHover(widget: wref<inkWidget>, row: Int32, band: Int32) -> Void {
    if !IsDefined(widget) { return; }
    let hover = new RadioXLEqHover();
    hover.panel = this;
    hover.row = row;
    hover.band = band;
    ArrayPush(this.m_bandHovers, hover);
    widget.RegisterToCallback(n"OnHoverOver", hover, n"OnHoverOver");
  }

  // A settings menu on/off switch row: its label and On / Off texts. Only the toggle takes the click; the
  // switch widget around it also spans the text.
  private func SwitchRow(row: String, label: String, action: Int32) -> Void {
    this.SetText(this.At(row + "/layout/labels/label"), label);
    this.SetText(this.At(row + "/layout/container/onState/body/txtValue"), RadioXLText("RadioXL.songOn"));
    this.SetText(this.At(row + "/layout/container/offState/body/txtValue"), RadioXLText("RadioXL.songOff"));
    // The copied On and Off layers take the cursor and sit over the toggle, so they would catch its click.
    for part in ["", "/onState/body", "/offState/body"] {
      let w: wref<inkWidget> = this.At(row + "/layout/container" + part);
      if IsDefined(w) { w.SetInteractive(false); }
    }
    this.Clickable(this.At(row + "/layout/container/bk_border"), action, true);
  }

  private func Switch(row: String, on: Bool) -> Void {
    let onState: wref<inkWidget> = this.At(row + "/layout/container/onState");
    let offState: wref<inkWidget> = this.At(row + "/layout/container/offState");
    if IsDefined(onState) { onState.SetVisible(on); }
    if IsDefined(offState) { offState.SetVisible(!on); }
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
      ArrayPush(this.m_tracks, this.At(cell + "/slidingArea"));
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

  // The panel edits the playing station's own equaliser while per-station is on, else the global one.
  private func Own() -> Bool {
    return RadioXLAPI.PerStationEq() && NotEquals(this.Station(), n"None");
  }

  // The choices the preset arrows step through: every preset, then Custom.
  private func Choices() -> array<String> {
    let names: array<String> = RadioXLAPI.EqPresets();
    ArrayPush(names, RadioXL_EqCustom());
    return names;
  }

  public func Click(action: Int32) -> Void {
    let station: CName = this.Station();
    if action == this.m_actScope {
      RadioXLAPI.SetPerStationEq(!RadioXLAPI.PerStationEq());
    } else if action == this.m_actPrevPreset || action == this.m_actNextPreset {
      this.StepPreset(action == this.m_actNextPreset ? 1 : -1);
    } else if action >= this.m_actStage && action < this.m_actStage + 3 {
      let stage: Int32 = action - this.m_actStage;
      RadioXLEqualiser.SetStageOn(stage, !RadioXLEqualiser.StageOn(stage));
      RadioXLConfig.Persist();
    } else if action >= this.m_actBandUp && action < this.m_actBandUp + 9 {
      // Indexing the call's result directly read 0; the array goes into a local first.
      let up: array<Int32> = RadioXLEqualiser.Bands(station);
      this.SetBand(action - this.m_actBandUp, up[action - this.m_actBandUp] + 1);
    } else if action >= this.m_actBandDown && action < this.m_actBandDown + 9 {
      let down: array<Int32> = RadioXLEqualiser.Bands(station);
      this.SetBand(action - this.m_actBandDown, down[action - this.m_actBandDown] - 1);
    } else if action == this.m_actBoostDown {
      RadioXLAPI.SetBoost(RadioXLAPI.Boost() - 1);
    } else if action == this.m_actBoostUp {
      RadioXLAPI.SetBoost(RadioXLAPI.Boost() + 1);
    } else if action == this.m_actReset {
      this.Reset();
    }
    this.Draw();
  }

  public func PressReset() -> Void {
    this.Click(this.m_actReset);
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

  // A band moved: the station's own bands while per-station is on, else the global Custom bands.
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

  // Per-station: the station's saved choice is cleared, so it plays RadioXL's suggestion, else Flat.
  // Global: back to Flat.
  private func Reset() -> Void {
    let station: CName = this.Station();
    if this.Own() {
      RadioXLAPI.SetStationEqPreset(station, "");
    } else {
      RadioXLAPI.SetEqPreset("Flat");
    }
  }

  // --- keys and pad ------------------------------------------------------------------------------

  // An action the popup heard; true when the panel took it, so the station list does not move too.
  // Keys and the pad move the cursor, as the game's menus do, and the pointer's click (pad A, Enter, F)
  // presses what it is on. R / pad X moves the cursor between the station list and the panel. On the
  // panel, up and down move it between rows, left and right between faders on the band rows and change
  // the value on the others. The left stick moves the cursor freely, so its scroll actions reach neither
  // the list nor the panel.
  public func Act(name: CName, type: gameinputActionType) -> Bool {
    let press: Bool = Equals(type, gameinputActionType.BUTTON_PRESSED);
    let step: Bool = press || Equals(type, gameinputActionType.REPEAT);
    if Equals(name, n"popup_moveUp_left_stick_up") || Equals(name, n"popup_moveUp_left_stick_down") {
      return true;
    }
    if Equals(name, n"secondaryAction") {
      if press { this.Focus(!this.m_focused, true); }
      return true;
    }
    // Proceed shares its buttons with the pointer's click: over a panel control, while the panel has the
    // focus, the press is the click's alone.
    if Equals(name, n"proceed") && this.m_overControl && this.m_focused { return true; }
    if !this.m_focused { return false; }
    switch name {
      case n"popup_moveUp":
        if step { this.Vertical(-1); }
        return true;
      case n"popup_moveDown":
        if step { this.Vertical(1); }
        return true;
      case n"radio_volume_down":
        if step { this.Horizontal(-1); }
        return true;
      case n"radio_volume_up":
        if step { this.Horizontal(1); }
        return true;
      case n"proceed":
        // The list acts on both the press and the release; neither may reach it.
        if press { this.Proceed(); }
        return true;
    }
    return false;
  }

  // The focus moves to the panel or back to the list; with `move`, the cursor goes with it.
  private func Focus(on: Bool, move: Bool) -> Void {
    this.m_focused = on;
    if IsDefined(this.m_focusHint) {
      this.m_focusHint.SetText(RadioXLText(on ? "RadioXL.eqFocusList" : "RadioXL.eqFocusPanel"));
    }
    this.Light();
    if !move { return; }
    if on {
      this.MoveCursor();
    } else {
      let popup = this.m_owner as VehicleRadioPopupGameController;
      if IsDefined(popup) { popup.RadioXLCursorToStation(); }
    }
  }

  // The pointer and the keys share one focus: a panel row under the cursor takes it, and a station row
  // under the cursor gives it back to the list.
  public func Hovered(row: Int32, band: Int32) -> Void {
    if !this.m_pointer { return; }
    this.m_row = row;
    if band >= 0 { this.m_band = band; }
    this.Focus(true, false);
  }

  // Off, the keys or the pad are in charge: the controls stop taking the cursor, so the one it rests on does
  // not light up or take the press, and proceed does the row's own action. On, the mouse or the stick moved
  // the cursor, and every control takes it.
  public func SetPointer(on: Bool) -> Void {
    this.m_pointer = on;
    if !on { this.m_overControl = false; }
    for click in this.m_clicks {
      if IsDefined(click.widget) && !click.keep { click.widget.SetInteractive(on); }
    }
    for track in this.m_tracks {
      if IsDefined(track) { track.SetInteractive(on); }
    }
  }

  public func IsFocused() -> Bool {
    return this.m_focused;
  }

  public func OverControl(over: Bool) -> Void {
    this.m_overControl = over;
  }

  public func ListHovered() -> Void {
    if this.m_focused { this.Focus(false, false); }
  }

  private func Row() -> String {
    return this.m_rows[this.m_row];
  }

  private func OnBands() -> Bool {
    return StrBeginsWith(this.Row(), "bands");
  }

  // What the cursor rests on in the focused row: the row's control, or the focused fader's arrow.
  private func Target() -> wref<inkWidget> {
    let content: String = "setup/content/";
    let row: String = this.Row();
    if this.OnBands() {
      let arrow: String = Equals(row, "bandsUp") ? "btnRight" : "btnLeft";
      return this.At(content + s"bands/fader\(this.m_band)/band\(this.m_band)/" + arrow);
    }
    // A switch's widget also holds its On / Off text; the outline wraps the toggle alone.
    if Equals(row, "scope") || StrBeginsWith(row, "stage") {
      return this.At(content + row + "/layout/container/bk_border");
    }
    return this.At(content + row + "/layout/container");
  }

  // Snapped, as the game's lists move the cursor to their selection; the cursor then draws as the outline.
  private func MoveCursor() -> Void {
    let target: wref<inkWidget> = this.Target();
    if IsDefined(target) && IsDefined(this.m_owner) {
      this.m_owner.SetCursorOverWidget(target, 0.0, true);
    }
  }

  private func Vertical(step: Int32) -> Void {
    this.m_row = Clamp(this.m_row + step, 0, ArraySize(this.m_rows) - 1);
    this.Light();
    this.MoveCursor();
  }

  private func Horizontal(step: Int32) -> Void {
    let row: String = this.Row();
    if this.OnBands() {
      this.m_band = Clamp(this.m_band + step, 0, RadioXL_EqBandCount() - 1);
      this.Light();
      this.MoveCursor();
    } else if Equals(row, "preset") {
      this.Click(step < 0 ? this.m_actPrevPreset : this.m_actNextPreset);
    } else if Equals(row, "boost") {
      this.Click(step < 0 ? this.m_actBoostDown : this.m_actBoostUp);
    } else {
      this.Toggle(row);
    }
  }

  // Proceed does the row's own action: a switch flips, the preset steps on, a fader arrow moves its band.
  // The Volume boost has none; left and right set it.
  private func Proceed() -> Void {
    let row: String = this.Row();
    if Equals(row, "preset") {
      this.Click(this.m_actNextPreset);
    } else if Equals(row, "bandsUp") {
      this.Click(this.m_actBandUp + this.m_band);
    } else if Equals(row, "bandsDown") {
      this.Click(this.m_actBandDown + this.m_band);
    } else if !Equals(row, "boost") {
      this.Toggle(row);
    }
  }

  // A switch row: Per-station EQ or one of the three stages.
  private func Toggle(row: String) -> Void {
    if Equals(row, "scope") {
      this.Click(this.m_actScope);
    } else if StrBeginsWith(row, "stage") {
      this.Click(this.m_actStage + StringToInt(StrAfterFirst(row, "stage")));
    }
  }

  // The focused row is lit. A fader has no hover look of its own, so the focused fader draws its frame
  // whole.
  private func Light() -> Void {
    let i: Int32 = 0;
    while i < ArraySize(this.m_hovers) {
      this.m_hovers[i].Show(this.m_focused && this.m_row == i);
      i += 1;
    }
    let bands: Bool = this.m_focused && this.OnBands();
    let b: Int32 = 0;
    while b < ArraySize(this.m_bandFrames) {
      if IsDefined(this.m_bandFrames[b]) {
        this.m_bandFrames[b].SetOpacity(bands && this.m_band == b ? 1.0 : this.m_bandFrameOpacity);
      }
      b += 1;
    }
  }

  // --- drawing -----------------------------------------------------------------------------------

  public func Draw() -> Void {
    let station: CName = this.Station();
    let own: Bool = this.Own();
    if IsDefined(this.m_station) {
      this.m_station.SetText(Equals(station, n"None") ? RadioXLText("RadioXL.eqNoStation") : RadioXLAPI.StationName(station));
    }
    this.Switch("setup/content/scope", RadioXLAPI.PerStationEq());

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

    let i: Int32 = 0;
    while i < 3 {
      this.Switch(s"setup/content/stage\(i)", RadioXLEqualiser.StageOn(i));
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
  // The popup hears only the actions it listens for; the base class drops every listener on detach.
  this.GetPlayerControlledObject().RegisterInputListener(this, n"showAll");
  this.GetPlayerControlledObject().RegisterInputListener(this, n"secondaryAction");
  for moved in [n"mouse_x", n"mouse_y", n"popup_axisX", n"popup_axisY"] {
    this.GetPlayerControlledObject().RegisterInputListener(this, moved);
  }
  this.RadioXLMouseSetup();
  return result;
}

// A station picked in the popup reaches the panel here, at once; RadioXL/StationChanged can arrive later.
@wrapMethod(VehicleRadioPopupGameController)
protected cb func OnVehicleRadioEvent(evt: ref<UIVehicleRadioEvent>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  if IsDefined(this.m_radioXLEq) { this.m_radioXLEq.Draw(); }
  return result;
}

@wrapMethod(VehicleRadioPopupGameController)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
  this.RadioXLPointerInput(action);
  if this.RadioXLWheel(action) { return true; }
  if IsDefined(this.m_radioXLEq) && this.m_radioXLEq.Act(ListenerAction.GetName(action), ListenerAction.GetType(action)) {
    return true;
  }
  let result: Bool = wrappedMethod(action, consumer);
  if Equals(ListenerAction.GetName(action), n"showAll")
    && Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_RELEASED)
    && IsDefined(this.m_radioXLEq) {
    this.m_radioXLEq.PressReset();
  }
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
