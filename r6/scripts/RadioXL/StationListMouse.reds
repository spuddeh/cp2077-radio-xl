// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The station selection UI with the mouse: the wheel scrolls the station list,
//              hovering a station highlights it, clicking a station plays it, and the volume
//              arrows take a click. Keys and the pad's d-pad move the selection as the game made
//              them; the left stick moves the cursor. The pointer acts only after the mouse or the
//              stick moves it, so a cursor resting on the popup takes nothing from the keys.
// File Version: 0.11.0
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

// Set by the wheel and cleared when the mouse moves: rows sliding under a still pointer are not picked, and
// the rows ignore the pointer until then.
@addField(VehicleRadioPopupGameController)
private let m_radioXLWheelHold: Bool;

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
  // The shard image is 165 high and a station's logo about 200, and the logo is drawn at its own size.
  let row = next as RadioStationListItemController;
  let shard: Bool = IsDefined(row) && row.RadioXLIsShard();
  // The logo widget carries a scale of its own, kept as found.
  if !this.m_radioXLIconScaleKept {
    this.m_radioXLIconScale = inkWidgetRef.GetScale(this.m_icon);
    this.m_radioXLIconScaleKept = true;
  }
  let factor: Float = shard ? 1.2 : 1.0;
  inkWidgetRef.SetScale(this.m_icon, new Vector2(this.m_radioXLIconScale.X * factor, this.m_radioXLIconScale.Y * factor));
}

@addField(VehicleRadioPopupGameController)
private let m_radioXLIconScale: Vector2;

@addField(VehicleRadioPopupGameController)
private let m_radioXLIconScaleKept: Bool;

// The shard slot's row names the slotted shard; it is redrawn when a shard is slotted or ejected.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLDrawShardRow() -> Void {
  this.RadioXLDrawShardRowIn(inkWidgetRef.Get(this.m_content), 0);
}

@addMethod(VehicleRadioPopupGameController)
private func RadioXLDrawShardRowIn(widget: wref<inkWidget>, depth: Int32) -> Void {
  if !IsDefined(widget) || depth > 4 { return; }
  let row = widget.GetController() as RadioStationListItemController;
  if IsDefined(row) {
    row.RadioXLDrawShard();
    return;
  }
  let compound = widget as inkCompoundWidget;
  if !IsDefined(compound) { return; }
  let i: Int32 = 0;
  while i < compound.GetNumChildren() {
    this.RadioXLDrawShardRowIn(compound.GetWidgetByIndex(i), depth + 1);
    i += 1;
  }
}

// --- the shard slot's row ----------------------------------------------------------------------
// The slot has no frequency: the Library's shard icon stands where a station's frequency is, and the name
// is the shard slotted. The list reuses its row widgets, so every row draws either way.

@addField(RadioStationListItemController)
private let m_radioXLShardIcon: wref<inkImage>;

@addField(RadioStationListItemController)
private let m_radioXLKept: Bool;

@addField(RadioStationListItemController)
private let m_radioXLLabelMargin: inkMargin;

// The popup tells its rows which station plays once, as its list fills; a row the list makes later, as it
// scrolls, never hears it and shows no bars. Each row reads the station playing as it takes its data.
@wrapMethod(RadioStationListItemController)
protected cb func OnDataChanged(value: Variant) -> Bool {
  let deck = RadioXLDeck.Get();
  if IsDefined(deck) {
    let r = deck.Receiver(GetGameInstance());
    if r.stationIndex >= 0 { this.m_currentRadioStationId = RadioStationDataProvider.GetRadioStationUIIndex(r.stationIndex); }
  }
  let result: Bool = wrappedMethod(value);
  this.RadioXLDrawShard();
  return result;
}

@addMethod(RadioStationListItemController)
public func RadioXLIsShard() -> Bool {
  if !IsDefined(this.m_stationData) || !IsDefined(this.m_stationData.m_record) { return false; }
  return this.m_stationData.m_record.GetID() == TDBID.Create(RadioXLDial.RecordName(RadioXL_ShardSlot()));
}

@addMethod(RadioStationListItemController)
public func RadioXLDrawShard() -> Void {
  let label: wref<inkText> = inkTextRef.Get(this.m_label) as inkText;
  if !IsDefined(label) { return; }
  if !this.m_radioXLKept {
    this.m_radioXLLabelMargin = label.GetMargin();
    this.m_radioXLKept = true;
  }
  let shard: Bool = this.RadioXLIsShard();
  if shard && !IsDefined(this.m_radioXLShardIcon) {
    // In the canvas that holds the playing bars: in the row's flex, after the label, it is clipped to the
    // label's box and never shows.
    let bars: wref<inkWidget> = inkWidgetRef.Get(this.m_equilizerIcon);
    let parent = IsDefined(bars) ? bars.GetParentWidget() as inkCompoundWidget : null;
    if IsDefined(parent) {
      let icon = new inkImage();
      icon.SetName(n"radioXLShard");
      icon.Reparent(parent, -1);
      icon.SetAtlasResource(ResRef.FromString("base\\gameplay\\gui\\widgets\\notifications\\notification_assets.inkatlas"));
      icon.SetTexturePart(n"shard");
      icon.SetSize(new Vector2(55.0, 50.0));
      icon.SetAnchor(inkEAnchor.CenterLeft);
      icon.SetAnchorPoint(new Vector2(0.0, 0.5));
      icon.SetMargin(new inkMargin(this.m_radioXLLabelMargin.left, 0.0, 0.0, 0.0));
      // The row's own colour, which follows its state as its label and icons do.
      icon.BindProperty(n"tintColor", n"ContactListItem.fontColor");
      this.m_radioXLShardIcon = icon;
    }
  }
  if IsDefined(this.m_radioXLShardIcon) { this.m_radioXLShardIcon.SetVisible(shard); }
  let margin: inkMargin = this.m_radioXLLabelMargin;
  if shard { margin.left += 70.0; }
  label.SetMargin(margin);
  if shard {
    let name: String = RadioXLAPI.SlottedShard();
    label.SetText(StrLen(name) > 0 ? name : RadioXLText("RadioXL.libAll"));
  }
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
  if !IsDefined(this.m_listController) || this.m_radioXLLastIndex < 0 || this.m_radioXLWheelHold { return; }
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
  if this.m_radioXLWheelHold { return false; }
  let row = this.RadioXLRowAt(e);
  if IsDefined(row) && IsDefined(this.m_listController) {
    this.m_listController.SelectItem(row.GetIndex(), false);
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
  if !IsDefined(row) || !this.GetPlayerControlledObject().PlayerLastUsedPad() { return; }
  // The wheel may have scrolled the selected row out of the list's view; the cursor is put where it shows.
  if IsDefined(this.m_scrollController) { this.m_scrollController.EnsureVisible(row.GetRootWidget()); }
  this.SetCursorOverWidget(row.GetRootWidget(), 0.0, true);
}

// Pointer mode on or off: the station rows take the pointer, and the panel follows the cursor.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLPointer(on: Bool) -> Void {
  if Equals(this.m_radioXLPointer, on) { return; }
  this.m_radioXLPointer = on;
  this.RadioXLRowsInteractive(inkWidgetRef.Get(this.m_content), on, 0);
  if IsDefined(this.m_radioXLEq) { this.m_radioXLEq.SetPointer(on); }
  if IsDefined(this.m_radioXLLibrary) { this.m_radioXLLibrary.SetPointer(on); }
  if IsDefined(this.m_radioXLBuilder) { this.m_radioXLBuilder.SetPointer(on); }
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
    if ListenerAction.GetValue(action) != 0.0 {
      if this.m_radioXLWheelHold {
        this.m_radioXLWheelHold = false;
        this.RadioXLRowsInteractive(inkWidgetRef.Get(this.m_content), true, 0);
      }
      this.RadioXLPointer(true);
    }
  } else if Equals(name, n"popup_axisX") || Equals(name, n"popup_axisY") {
    // Above the stick's rest, which reports small values without being touched.
    if AbsF(ListenerAction.GetValue(action)) > 0.1 { this.RadioXLPointer(true); }
  } else if Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_RELEASED)
    && (Equals(name, n"popup_moveUp") || Equals(name, n"popup_moveDown")) {
    // A key's release comes frames after its press; a wheel notch's comes in the same frame.
    let gi: GameInstance = this.GetPlayerControlledObject().GetGame();
    if GameInstance.GetFrameNumber(gi) > this.m_radioXLMoveFrame + 1ul { this.RadioXLPointer(false); }
  } else if Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_PRESSED) {
    // The wheel arrives as up and down too; it leaves the mode as it is.
    let keys: array<Int32> = ListenerAction.GetKey(action);
    if ArrayContains(keys, EnumInt(EInputKey.IK_MouseWheelUp)) || ArrayContains(keys, EnumInt(EInputKey.IK_MouseWheelDown)) {
      return;
    }
    switch name {
      case n"radio_volume_down":
      case n"radio_volume_up":
      case n"prior_menu":
      case n"next_menu":
        this.RadioXLPointer(false);
    }
  }
}

// A wheel notch reaches the popup as its own up or down, pressed and released in one frame, and then
// as `mouse_wheel`; no key comes with either, so the move cannot be told from an arrow key until the
// `mouse_wheel` arrives. The move goes ahead, and a `mouse_wheel` in the same or the next frame takes
// back every move of its burst (several notches can share one `mouse_wheel`) and scrolls the panel shown
// once per move instead: the selection stays where it was, and the pointer can move over the rows while
// the list scrolls.
@addField(VehicleRadioPopupGameController)
private let m_radioXLMoveFrame: Uint64;

@addField(VehicleRadioPopupGameController)
private let m_radioXLMoveIndex: Int32;

@addField(VehicleRadioPopupGameController)
private let m_radioXLMoves: Int32;

// The station list's up and down wait a frame: the list acts on its own selection in ways
// a later undo races, so a wheel notch must never reach it. The rows still to step, and whether the step is
// queued.
@addField(VehicleRadioPopupGameController)
private let m_radioXLDeferred: Int32;

@addField(VehicleRadioPopupGameController)
private let m_radioXLDeferQueued: Bool;

public class RadioXLDeferredMove extends DelayCallback {
  public let popup: wref<VehicleRadioPopupGameController>;

  public func Call() -> Void {
    if IsDefined(this.popup) { this.popup.RadioXLDeferredMove(); }
  }
}

// No wheel came with the up or down: it was a key, and the selection steps.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLDeferredMove() -> Void {
  this.m_radioXLDeferQueued = false;
  let step: Int32 = this.m_radioXLDeferred;
  this.m_radioXLDeferred = 0;
  if step == 0 || !IsDefined(this.m_listController) || !IsDefined(this.m_dataSource) { return; }
  let n: Int32 = Cast<Int32>(this.m_dataSource.GetArraySize());
  if n == 0 { return; }
  let target: Int32 = Clamp(this.m_radioXLLastIndex + step, 0, n - 1);
  this.m_listController.SelectItem(Cast<Uint32>(target), true);
  let row: wref<inkVirtualCompoundItemController> = this.m_listController.GetSelectedItem();
  if IsDefined(row) && IsDefined(this.m_scrollController) { this.m_scrollController.EnsureVisible(row.GetRootWidget()); }
}

@addMethod(VehicleRadioPopupGameController)
private func RadioXLWheel(action: ListenerAction) -> Bool {
  let name: CName = ListenerAction.GetName(action);
  let gi: GameInstance = this.GetPlayerControlledObject().GetGame();
  if Equals(name, n"popup_moveUp") || Equals(name, n"popup_moveDown") {
    if Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_PRESSED) {
      let frame: Uint64 = GameInstance.GetFrameNumber(gi);
      if frame > this.m_radioXLMoveFrame + 1ul {
        // A new burst: where everything stood before it.
        this.m_radioXLMoves = 0;
        this.m_radioXLMoveIndex = this.m_radioXLLastIndex;
        if IsDefined(this.m_radioXLLibrary) { this.m_radioXLLibrary.Snapshot(); }
      }
      this.m_radioXLMoves += 1;
      this.m_radioXLMoveFrame = frame;
    }
    let type: gameinputActionType = ListenerAction.GetType(action);
    let step: Bool = Equals(type, gameinputActionType.BUTTON_PRESSED) || Equals(type, gameinputActionType.REPEAT);
    if this.RadioXLTabShown() == 0 {
      if step {
        this.m_radioXLDeferred += Equals(name, n"popup_moveUp") ? -1 : 1;
        if !this.m_radioXLDeferQueued {
          this.m_radioXLDeferQueued = true;
          let later = new RadioXLDeferredMove();
          later.popup = this;
          GameInstance.GetDelaySystem(gi).DelayCallbackNextFrame(later);
        }
      }
      return true;
    }
    return false;
  }
  if !Equals(name, n"mouse_wheel") || ListenerAction.GetValue(action) == 0.0 { return false; }
  let up: Bool = ListenerAction.GetValue(action) > 0.0;
  let notches: Int32 = 1;
  if this.m_radioXLDeferred != 0 {
    // The waiting step was this wheel: it never reaches the list.
    notches = Max(this.m_radioXLDeferred < 0 ? -this.m_radioXLDeferred : this.m_radioXLDeferred, 1);
    this.m_radioXLDeferred = 0;
    this.m_radioXLMoveFrame = 0ul;
    this.m_radioXLMoves = 0;
  } else if GameInstance.GetFrameNumber(gi) <= this.m_radioXLMoveFrame + 1ul && this.m_radioXLMoves > 0 {
    // The moves just made were these notches: back them out.
    notches = this.m_radioXLMoves;
    let tab: Int32 = this.RadioXLTabShown();
    if tab == 0 && IsDefined(this.m_listController) && this.m_radioXLMoveIndex >= 0 {
      this.m_listController.SelectItem(Cast<Uint32>(this.m_radioXLMoveIndex), false);
      this.m_radioXLLastIndex = this.m_radioXLMoveIndex;
    } else if tab == 1 && IsDefined(this.m_radioXLLibrary) {
      this.m_radioXLLibrary.Restore();
    } else if tab == 2 && IsDefined(this.m_radioXLEq) {
      this.m_radioXLEq.UndoSteps(up, notches);
    }
    this.m_radioXLMoveFrame = 0ul;
    this.m_radioXLMoves = 0;
  }
  this.RadioXLPointer(true);
  // The list selects the row under the pointer by itself; rows sliding under a still pointer take nothing.
  if !this.m_radioXLWheelHold {
    this.m_radioXLWheelHold = true;
    this.RadioXLRowsInteractive(inkWidgetRef.Get(this.m_content), false, 0);
  }
  let shown: Int32 = this.RadioXLTabShown();
  let i: Int32 = 0;
  while i < notches {
    if shown == 0 && IsDefined(this.m_scrollController) {
      this.m_scrollController.Scroll(up ? 1.0 : -1.0, true);
    } else if shown == 1 && IsDefined(this.m_radioXLLibrary) {
      this.m_radioXLLibrary.Scroll(up);
    }
    i += 1;
  }
  return true;
}
