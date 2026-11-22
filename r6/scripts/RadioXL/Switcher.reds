// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The station selection UI shows one panel at a time in the popup's frame: the
//              Radioport (the game's own contents), the Library or the Equalizer. A tab header on
//              the frame's top edge names them; LB / RB or a click on a tab switch.
//
//              THE SWITCH IS A SHARD SWAP: the panel going out slides to one side and fades, the one
//              coming in slides in from the other, in the direction of the step. The game's own
//              contents stay alive while hidden, so the station list is as it was on the way back.
// File Version: 0.11.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL

public class RadioXLTabClick extends IScriptable {
  public let popup: wref<VehicleRadioPopupGameController>;
  public let tab: Int32;

  protected cb func OnRelease(e: ref<inkPointerEvent>) -> Bool {
    if e.IsAction(n"click") && IsDefined(this.popup) { this.popup.RadioXLTabClicked(this.tab); }
    return true;
  }
}

// Puts the panel that slid out back as it was, hidden, once its slide ends.
public class RadioXLSwapDone extends IScriptable {
  public let widget: wref<inkWidget>;

  protected cb func OnFinished(proxy: ref<inkAnimProxy>) -> Bool {
    this.Finish();
    return true;
  }

  public func Finish() -> Void {
    if IsDefined(this.widget) {
      this.widget.SetVisible(false);
      this.widget.SetTranslation(new Vector2(0.0, 0.0));
      this.widget.SetOpacity(1.0);
    }
    this.widget = null;
  }
}

// Moves the cursor onto the panel that came in, once it has stopped sliding: snapped earlier, the pad's
// outline is drawn where the widget was mid-slide.
public class RadioXLSwapInDone extends IScriptable {
  public let popup: wref<VehicleRadioPopupGameController>;

  protected cb func OnFinished(proxy: ref<inkAnimProxy>) -> Bool {
    if IsDefined(this.popup) { this.popup.RadioXLAfterSwap(); }
    return true;
  }
}

public abstract class RadioXLSwapAnim {
  public final static func Distance() -> Float { return 260.0; }

  private final static func Def(fromX: Float, toX: Float, fromAlpha: Float, toAlpha: Float, delay: Float,
                                duration: Float, mode: inkanimInterpolationMode) -> ref<inkAnimDef> {
    let def = new inkAnimDef();
    let slide = new inkAnimTranslation();
    slide.SetStartTranslation(new Vector2(fromX, 0.0));
    slide.SetEndTranslation(new Vector2(toX, 0.0));
    slide.SetStartDelay(delay);
    slide.SetDuration(duration);
    slide.SetType(inkanimInterpolationType.Quadratic);
    slide.SetMode(mode);
    def.AddInterpolator(slide);
    let fade = new inkAnimTransparency();
    fade.SetStartTransparency(fromAlpha);
    fade.SetEndTransparency(toAlpha);
    fade.SetStartDelay(delay);
    fade.SetDuration(duration);
    fade.SetType(inkanimInterpolationType.Linear);
    fade.SetMode(mode);
    def.AddInterpolator(fade);
    return def;
  }

  // `dir` is the step: 1 slides the old panel out to the left and the new one in from the right.
  public final static func Out(widget: wref<inkWidget>, dir: Int32, done: ref<RadioXLSwapDone>) -> ref<inkAnimProxy> {
    let def = RadioXLSwapAnim.Def(0.0, -Cast<Float>(dir) * RadioXLSwapAnim.Distance(), 1.0, 0.0, 0.0, 0.16, inkanimInterpolationMode.EasyIn);
    let proxy = widget.PlayAnimation(def);
    if IsDefined(proxy) { proxy.RegisterToCallback(inkanimEventType.OnFinish, done, n"OnFinished"); }
    return proxy;
  }

  public final static func In(widget: wref<inkWidget>, dir: Int32) -> ref<inkAnimProxy> {
    widget.SetOpacity(0.0);
    widget.SetTranslation(new Vector2(Cast<Float>(dir) * RadioXLSwapAnim.Distance(), 0.0));
    widget.SetVisible(true);
    let def = RadioXLSwapAnim.Def(Cast<Float>(dir) * RadioXLSwapAnim.Distance(), 0.0, 0.0, 1.0, 0.07, 0.2, inkanimInterpolationMode.EasyOut);
    return widget.PlayAnimation(def);
  }
}

// --- the popup ----------------------------------------------------------------------------------

// The panel shown: 0 the Radioport, 1 the Library, 2 the Equalizer.
@addField(VehicleRadioPopupGameController)
private let m_radioXLTab: Int32;

@addField(VehicleRadioPopupGameController)
private let m_radioXLTabsBuilt: Bool;

@addField(VehicleRadioPopupGameController)
private let m_radioXLTabRoot: wref<inkCompoundWidget>;

@addField(VehicleRadioPopupGameController)
private let m_radioXLTabClicks: array<ref<RadioXLTabClick>>;

@addField(VehicleRadioPopupGameController)
private let m_radioXLSwapOut: ref<inkAnimProxy>;

@addField(VehicleRadioPopupGameController)
private let m_radioXLSwapIn: ref<inkAnimProxy>;

@addField(VehicleRadioPopupGameController)
private let m_radioXLSwapDone: ref<RadioXLSwapDone>;

@addField(VehicleRadioPopupGameController)
private let m_radioXLSwapInDone: ref<RadioXLSwapInDone>;

// Called once both panels exist: the two wraps that build them run in no promised order.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLSwitcherSetup() -> Void {
  if this.m_radioXLTabsBuilt || !IsDefined(this.m_radioXLEq) || !IsDefined(this.m_radioXLLibrary) { return; }
  this.m_radioXLTabsBuilt = true;
  this.m_radioXLTab = 0;
  let host = this.GetRootCompoundWidget().GetWidget(n"containerRoot") as inkCompoundWidget;
  if !IsDefined(host) { return; }
  let tabs = this.SpawnFromExternal(host, r"radioxl\\gui\\tabs.inkwidget", n"tabs") as inkCompoundWidget;
  if IsDefined(tabs) {
    tabs.SetAnchor(inkEAnchor.TopCenter);
    tabs.SetAnchorPoint(0.5, 1.0);
    tabs.SetTranslation(new Vector2(0.0, -130.0));
    this.m_radioXLTabRoot = tabs;
    let keys: array<String> = ["RadioXL.tabRadio", "RadioXL.libTitle", "RadioXL.eqTitle"];
    let i: Int32 = 0;
    while i < 3 {
      let tab = this.RadioXLTab(i);
      if IsDefined(tab) {
        let label = tab.GetWidgetByPathName(n"inkVerticalPanelWidget2/center/txtValue") as inkText;
        if IsDefined(label) { label.SetText(RadioXLText(keys[i])); }
        let click = new RadioXLTabClick();
        click.popup = this;
        click.tab = i;
        ArrayPush(this.m_radioXLTabClicks, click);
        tab.SetInteractive(true);
        tab.RegisterToCallback(n"OnRelease", click, n"OnRelease");
      }
      i += 1;
    }
  }
  this.RadioXLDrawTabs();
}

@addMethod(VehicleRadioPopupGameController)
private func RadioXLTab(i: Int32) -> wref<inkCompoundWidget> {
  if !IsDefined(this.m_radioXLTabRoot) { return null; }
  let holder = this.m_radioXLTabRoot.GetWidgetByPathName(n"lineContainer/center_holder/inkFlexWidget2/tabs") as inkCompoundWidget;
  if !IsDefined(holder) { return null; }
  let names: array<CName> = [n"tabRadio", n"tabLibrary", n"tabEq"];
  return holder.GetWidget(names[i]) as inkCompoundWidget;
}

// The hub menu's bar: the shown panel's label in its Selected state, and the blue line slid under it.
@addMethod(VehicleRadioPopupGameController)
private func RadioXLDrawTabs() -> Void {
  let i: Int32 = 0;
  let place: Int32 = 0;
  let selectedPlace: Int32 = 0;
  while i < 3 {
    let tab = this.RadioXLTab(i);
    if IsDefined(tab) {
      tab.SetState(i == this.m_radioXLTab ? n"Selected" : n"Default");
      if i == this.m_radioXLTab { selectedPlace = place; }
      place += 1;
    }
    i += 1;
  }
  let slider: wref<inkWidget> = IsDefined(this.m_radioXLTabRoot)
    ? this.m_radioXLTabRoot.GetWidgetByPathName(n"lineContainer/center_holder/inkFlexWidget2/zero_size_holder/slider") : null;
  if !IsDefined(slider) { return; }
  // Each label is 300 wide with 10 between them (tools/library-panel-ink.py TAB_W, the hub bar's gap).
  let step: Float = 310.0;
  let target: Float = Cast<Float>(selectedPlace) * step;
  let slide = new inkAnimTranslation();
  slide.SetStartTranslation(slider.GetTranslation());
  slide.SetEndTranslation(new Vector2(target, 0.0));
  slide.SetDuration(0.2);
  slide.SetType(inkanimInterpolationType.Quadratic);
  slide.SetMode(inkanimInterpolationMode.EasyOut);
  let def = new inkAnimDef();
  def.AddInterpolator(slide);
  slider.PlayAnimation(def);
}

@addMethod(VehicleRadioPopupGameController)
private func RadioXLPanelWidget(i: Int32) -> wref<inkWidget> {
  if i == 1 { return IsDefined(this.m_radioXLLibrary) ? this.m_radioXLLibrary.Root() : null; }
  if i == 2 { return IsDefined(this.m_radioXLEq) ? this.m_radioXLEq.Root() : null; }
  let host = this.GetRootCompoundWidget().GetWidget(n"containerRoot") as inkCompoundWidget;
  return IsDefined(host) ? host.GetWidget(n"wrapper") : null;
}

@addMethod(VehicleRadioPopupGameController)
public func RadioXLTabClicked(tab: Int32) -> Void {
  if tab == this.m_radioXLTab { return; }
  this.RadioXLShowTab(tab, tab > this.m_radioXLTab ? 1 : -1);
}

// LB / RB: the next or previous panel, round in a ring.
@addMethod(VehicleRadioPopupGameController)
private func RadioXLRing(action: ListenerAction) -> Bool {
  let name: CName = ListenerAction.GetName(action);
  if !Equals(name, n"prior_menu") && !Equals(name, n"next_menu") { return false; }
  if !Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_PRESSED) { return true; }
  let step: Int32 = Equals(name, n"next_menu") ? 1 : -1;
  this.RadioXLShowTab((this.m_radioXLTab + step + 3) % 3, step);
  return true;
}

@addMethod(VehicleRadioPopupGameController)
public func RadioXLShowTab(next: Int32, dir: Int32) -> Void {
  if next == this.m_radioXLTab || !this.m_radioXLTabsBuilt { return; }
  let leaving: wref<inkWidget> = this.RadioXLPanelWidget(this.m_radioXLTab);
  let coming: wref<inkWidget> = this.RadioXLPanelWidget(next);
  if !IsDefined(coming) { return; }
  // A switch made while the last one still slides: that one jumps to its end.
  if IsDefined(this.m_radioXLSwapOut) && this.m_radioXLSwapOut.IsPlaying() { this.m_radioXLSwapOut.GotoEndAndStop(true); }
  if IsDefined(this.m_radioXLSwapDone) { this.m_radioXLSwapDone.Finish(); }
  if IsDefined(this.m_radioXLSwapIn) && this.m_radioXLSwapIn.IsPlaying() { this.m_radioXLSwapIn.GotoEndAndStop(true); }
  if IsDefined(leaving) {
    this.m_radioXLSwapDone = new RadioXLSwapDone();
    this.m_radioXLSwapDone.widget = leaving;
    this.m_radioXLSwapOut = RadioXLSwapAnim.Out(leaving, dir, this.m_radioXLSwapDone);
  }
  this.m_radioXLSwapIn = RadioXLSwapAnim.In(coming, dir);
  if IsDefined(this.m_radioXLSwapIn) {
    this.m_radioXLSwapInDone = new RadioXLSwapInDone();
    this.m_radioXLSwapInDone.popup = this;
    this.m_radioXLSwapIn.RegisterToCallback(inkanimEventType.OnFinish, this.m_radioXLSwapInDone, n"OnFinished");
  }
  this.m_radioXLTab = next;
  this.PlaySound(n"Holocall", n"Navigation");
  this.RadioXLDrawTabs();
  // The panel shown has the keys; the others let go of them.
  if next != 1 && IsDefined(this.m_radioXLLibrary) { this.m_radioXLLibrary.Blur(); }
  if next != 2 && IsDefined(this.m_radioXLEq) { this.m_radioXLEq.Blur(); }
  if next == 1 {
    this.m_radioXLLibrary.ShowPlaying();
    this.m_radioXLLibrary.Focus(true, false);
  }
  if next == 2 { this.m_radioXLEq.FocusPanel(false); }
}

// The panel has stopped sliding: with the keys or the pad in charge, the cursor goes onto it.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLAfterSwap() -> Void {
  if this.m_radioXLPointer || !this.GetPlayerControlledObject().PlayerLastUsedPad() { return; }
  if this.m_radioXLTab == 1 && IsDefined(this.m_radioXLLibrary) { this.m_radioXLLibrary.MoveCursorNow(); }
  if this.m_radioXLTab == 2 && IsDefined(this.m_radioXLEq) { this.m_radioXLEq.MoveCursorNow(); }
  if this.m_radioXLTab == 0 { this.RadioXLCursorToStation(); }
}

@addMethod(VehicleRadioPopupGameController)
public func RadioXLTabShown() -> Int32 {
  return this.m_radioXLTab;
}
