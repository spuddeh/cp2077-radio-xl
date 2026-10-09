// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The station selection UI with the mouse: the wheel scrolls the station list,
//              hovering a station highlights it, clicking a station plays it, and the volume
//              arrows take a click. Keys and the pad's d-pad move the selection as the game made
//              them; the left stick moves the cursor. The pointer acts only after the mouse or the
//              stick moves it, so a cursor resting on the popup takes nothing from the keys.
// File Version: 0.8.0
// ======================================================================================

module RadioXL

// A station row takes the pointer only while its root is interactive; the game's row has nothing that is.
// An interactive row selects itself under the cursor, so a key step that scrolls the list would land a
// second row on a resting cursor: rows are interactive only in pointer mode (RadioXLPointer).

// One volume arrow.
public class RadioXLVolumeClick extends IScriptable {
  public let popup: wref<VehicleRadioPopupGameController>;
  public let up: Bool;

  protected cb func OnRelease(e: ref<inkPointerEvent>) -> Bool {
    if e.IsAction(n"click") && IsDefined(this.popup) {
      this.popup.RadioXLVolume(this.up);
    }
    return true;
  }
}

@addField(VehicleRadioPopupGameController)
private let m_radioXLVolumeClicks: array<ref<RadioXLVolumeClick>>;

// Pointer mode: the mouse or the stick moved the cursor since the popup opened or since the last key or
// d-pad step. Only then do the station rows and the panel act on what is under the cursor.
@addField(VehicleRadioPopupGameController)
private let m_radioXLPointer: Bool;

// The last station the list selected. A row the cursor leaves deselects itself, and the list would be left
// with nothing selected for the keys to step from or proceed to play.
@addField(VehicleRadioPopupGameController)
private let m_radioXLLastIndex: Int32;

public class RadioXLKeepSelection extends DelayCallback {
  public let popup: wref<VehicleRadioPopupGameController>;

  public func Call() -> Void {
    if IsDefined(this.popup) { this.popup.RadioXLKeepSelection(); }
  }
}

@wrapMethod(VehicleRadioPopupGameController)
protected func Select(previous: ref<inkVirtualCompoundItemController>, next: ref<inkVirtualCompoundItemController>) -> Void {
  wrappedMethod(previous, next);
  if IsDefined(next) { this.m_radioXLLastIndex = Cast<Int32>(next.GetIndex()); }
}

// Checked a frame after the cursor leaves a row, once the row has deselected itself.
@addMethod(VehicleRadioPopupGameController)
protected cb func OnRadioXLRowHoverOut(e: ref<inkPointerEvent>) -> Bool {
  let keep = new RadioXLKeepSelection();
  keep.popup = this;
  GameInstance.GetDelaySystem(this.GetPlayerControlledObject().GetGame()).DelayCallbackNextFrame(keep);
  return false;
}

@addMethod(VehicleRadioPopupGameController)
public func RadioXLKeepSelection() -> Void {
  if !IsDefined(this.m_listController) || this.m_radioXLLastIndex < 0 { return; }
  if IsDefined(this.m_listController.GetSelectedItem()) { return; }
  this.m_listController.SelectItem(Cast<Uint32>(this.m_radioXLLastIndex), false);
}

@addMethod(VehicleRadioPopupGameController)
private func RadioXLMouseSetup() -> Void {
  // A row's pointer events reach the list that holds it.
  inkWidgetRef.RegisterToCallback(this.m_content, n"OnHoverOver", this, n"OnRadioXLRowHover");
  inkWidgetRef.RegisterToCallback(this.m_content, n"OnHoverOut", this, n"OnRadioXLRowHoverOut");
  inkWidgetRef.RegisterToCallback(this.m_content, n"OnRelease", this, n"OnRadioXLRowRelease");
  let volume = inkWidgetRef.Get(this.m_radioVolumeSettings) as inkCompoundWidget;
  if !IsDefined(volume) { return; }
  let controls = volume.GetWidget(n"controls") as inkCompoundWidget;
  if !IsDefined(controls) { return; }
  this.RadioXLVolumeArrow(controls.GetWidget(n"inputVolumeDown"), false);
  this.RadioXLVolumeArrow(controls.GetWidget(n"inputVolumeUp"), true);
}

@addMethod(VehicleRadioPopupGameController)
private func RadioXLVolumeArrow(widget: wref<inkWidget>, up: Bool) -> Void {
  if !IsDefined(widget) { return; }
  let click = new RadioXLVolumeClick();
  click.popup = this;
  click.up = up;
  ArrayPush(this.m_radioXLVolumeClicks, click);
  widget.SetInteractive(true);
  widget.RegisterToCallback(n"OnRelease", click, n"OnRelease");
}

@addMethod(VehicleRadioPopupGameController)
public func RadioXLVolume(up: Bool) -> Void {
  if !IsDefined(this.m_radioVolumeSettingsController) { return; }
  if up { this.m_radioVolumeSettingsController.VolumeUp(); } else { this.m_radioVolumeSettingsController.VolumeDown(); }
}

@addMethod(VehicleRadioPopupGameController)
private func RadioXLRowAt(e: ref<inkPointerEvent>) -> wref<RadioStationListItemController> {
  let target: wref<inkWidget> = e.GetTarget();
  return IsDefined(target) ? target.GetController() as RadioStationListItemController : null;
}

@addMethod(VehicleRadioPopupGameController)
protected cb func OnRadioXLRowHover(e: ref<inkPointerEvent>) -> Bool {
  let row = this.RadioXLRowAt(e);
  if IsDefined(row) && IsDefined(this.m_listController) {
    this.m_listController.SelectItem(row.GetIndex(), false);
    if IsDefined(this.m_radioXLEq) { this.m_radioXLEq.ListHovered(); }
  }
  return false;
}

@addMethod(VehicleRadioPopupGameController)
protected cb func OnRadioXLRowRelease(e: ref<inkPointerEvent>) -> Bool {
  if !e.IsAction(n"click") { return false; }
  let row = this.RadioXLRowAt(e);
  if IsDefined(row) && IsDefined(this.m_listController) {
    this.m_listController.SelectItem(row.GetIndex(), false);
    this.Activate();
  }
  return false;
}

// The cursor onto the selected station when the focus comes back from the panel. A step through the list
// leaves the cursor where it is: the list shows its own selection.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLCursorToStation() -> Void {
  let row: wref<inkVirtualCompoundItemController> = IsDefined(this.m_listController) ? this.m_listController.GetSelectedItem() : null;
  if IsDefined(row) { this.SetCursorOverWidget(row.GetRootWidget(), 0.0, true); }
}

// Pointer mode on or off: the station rows take the pointer, and the panel follows the cursor.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLPointer(on: Bool) -> Void {
  if Equals(this.m_radioXLPointer, on) { return; }
  this.m_radioXLPointer = on;
  this.RadioXLRowsInteractive(inkWidgetRef.Get(this.m_content), on, 0);
  if IsDefined(this.m_radioXLEq) { this.m_radioXLEq.SetPointer(on); }
}

// The list's rows are a few levels down; the walk stops at each row.
@addMethod(VehicleRadioPopupGameController)
private func RadioXLRowsInteractive(widget: wref<inkWidget>, on: Bool, depth: Int32) -> Void {
  if !IsDefined(widget) || depth > 4 { return; }
  if IsDefined(widget.GetController() as RadioStationListItemController) {
    widget.SetInteractive(on);
    return;
  }
  let compound = widget as inkCompoundWidget;
  if !IsDefined(compound) { return; }
  let i: Int32 = 0;
  while i < compound.GetNumChildren() {
    this.RadioXLRowsInteractive(compound.GetWidgetByIndex(i), on, depth + 1);
    i += 1;
  }
}

// The mouse or the stick moved the cursor: pointer mode. A key or d-pad step, or R / pad X: not.
@addMethod(VehicleRadioPopupGameController)
private func RadioXLPointerInput(action: ListenerAction) -> Void {
  let name: CName = ListenerAction.GetName(action);
  if Equals(name, n"mouse_x") || Equals(name, n"mouse_y") {
    if ListenerAction.GetValue(action) != 0.0 { this.RadioXLPointer(true); }
  } else if Equals(name, n"popup_axisX") || Equals(name, n"popup_axisY") {
    // Above the stick's rest, which reports small values without being touched.
    if AbsF(ListenerAction.GetValue(action)) > 0.1 { this.RadioXLPointer(true); }
  } else if Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_PRESSED) {
    // The wheel arrives as up and down too; it leaves the mode as it is.
    let keys: array<Int32> = ListenerAction.GetKey(action);
    if ArrayContains(keys, EnumInt(EInputKey.IK_MouseWheelUp)) || ArrayContains(keys, EnumInt(EInputKey.IK_MouseWheelDown)) {
      return;
    }
    switch name {
      case n"popup_moveUp":
      case n"popup_moveDown":
      case n"radio_volume_down":
      case n"radio_volume_up":
      case n"secondaryAction":
        this.RadioXLPointer(false);
    }
  }
}

// The wheel is bound to the popup's own up and down, which move the selection. A wheel notch scrolls the
// list instead; the same actions from a key or the pad go on to the game.
@addMethod(VehicleRadioPopupGameController)
private func RadioXLWheel(action: ListenerAction) -> Bool {
  let name: CName = ListenerAction.GetName(action);
  if !Equals(name, n"popup_moveUp") && !Equals(name, n"popup_moveDown") { return false; }
  let keys: array<Int32> = ListenerAction.GetKey(action);
  if !ArrayContains(keys, EnumInt(EInputKey.IK_MouseWheelUp)) && !ArrayContains(keys, EnumInt(EInputKey.IK_MouseWheelDown)) {
    return false;
  }
  if Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_PRESSED) && IsDefined(this.m_scrollController) {
    this.m_scrollController.Scroll(Equals(name, n"popup_moveUp") ? 1.0 : -1.0, true);
  }
  return true;
}
