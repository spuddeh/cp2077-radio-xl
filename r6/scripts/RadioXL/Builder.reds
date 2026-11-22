// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The shard builder: a full-screen screen over the station selection UI where a shard
//              is made and changed. The shards are tabs along the top; under them three columns read
//              left to right: the sources (All songs and every station), that source's songs with the
//              filter box and a checkbox per song, and the shard itself in play order.
//
//              The screen is radioxl\gui\shard_builder.inkwidget, item "builder", made by
//              tools/shard-builder-ink.py from the game's own widgets. It is spawned on the popup's
//              root and shown in place of the popup's frame; the Library opens it on a shard (R) or on
//              a new one (+ NEW), and Back returns to the Library. Every change is saved at once. A
//              shard left with no songs is deleted when the builder or the popup closes.
// File Version: 0.11.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL
import Codeware.UI.*

// One clickable part of the builder.
public class RadioXLBuilderClick extends IScriptable {
  public let builder: wref<RadioXLShardBuilder>;
  public let action: Int32;

  protected cb func OnRelease(e: ref<inkPointerEvent>) -> Bool {
    // A click arrives twice, as "click" and as "mouse_left"; one of them acts.
    if e.IsAction(n"click") && IsDefined(this.builder) { this.builder.Click(this.action); }
    return true;
  }

  protected cb func OnHoverOver(e: ref<inkPointerEvent>) -> Bool {
    if IsDefined(this.builder) { this.builder.Hovered(this.action); }
    return false;
  }

  protected cb func OnHoverOut(e: ref<inkPointerEvent>) -> Bool {
    if IsDefined(this.builder) { this.builder.Unhovered(this.action); }
    return false;
  }
}

// One logo fitting pass.
public class RadioXLBuilderFitIcons extends DelayCallback {
  public let builder: wref<RadioXLShardBuilder>;
  public let tries: Int32;

  public func Call() -> Void {
    if IsDefined(this.builder) { this.builder.FitIcons(this.tries); }
  }
}

// Half a second of real time: the popup slows the game, and on foot no event says the song changed.
public class RadioXLBuilderTrackCheck extends DelayCallback {
  public let builder: wref<RadioXLShardBuilder>;

  public func Call() -> Void {
    if IsDefined(this.builder) { this.builder.CheckTrack(); }
  }
}

public class RadioXLShardBuilder extends IScriptable {
  // Click actions: a base per kind, plus the row, cartridge or tab.
  private let m_actChip: Int32 = 0;
  private let m_actSong: Int32 = 100;
  private let m_actCheck: Int32 = 200;
  private let m_actShardRow: Int32 = 300;
  private let m_actUp: Int32 = 400;
  private let m_actDown: Int32 = 500;
  private let m_actTab: Int32 = 600;
  private let m_actNew: Int32 = 700;
  private let m_actOrder: Int32 = 701;
  private let m_actRename: Int32 = 702;
  private let m_actBack: Int32 = 703;
  private let m_actAdd: Int32 = 704;
  private let m_actPrevCol: Int32 = 705;
  private let m_actNextCol: Int32 = 706;
  private let m_actRenameCancel: Int32 = 707;
  private let m_actRenameSave: Int32 = 708;
  private let m_actDelete: Int32 = 709;
  private let m_actDeleteYes: Int32 = 710;
  private let m_actDeleteNo: Int32 = 711;
  private let m_actModalBox: Int32 = 712;
  private let m_actColumn: Int32 = 800;   // + the column, for a hover anywhere on it

  private let m_owner: wref<VehicleRadioPopupGameController>;
  private let m_root: wref<inkCompoundWidget>;
  private let m_clicks: array<ref<RadioXLBuilderClick>>;

  // The tabs: one block per shard shown, from m_tabTop, and + NEW.
  private let m_tabs: array<wref<inkWidget>>;
  private let m_tabLabels: array<wref<inkText>>;
  private let m_tabNew: wref<inkWidget>;
  private let m_tabSlider: wref<inkWidget>;
  private let m_tabTop: Int32;

  private let m_chips: array<wref<inkWidget>>;
  private let m_chipLabels: array<wref<inkText>>;
  private let m_chipCounts: array<wref<inkText>>;
  private let m_chipBars: array<wref<inkWidget>>;
  private let m_chipHovers: array<wref<inkWidget>>;
  private let m_chipIcons: array<wref<inkImage>>;
  // The source each cartridge's logo was asked for: a logo is asked for again only when that changes.
  private let m_chipSources: array<Int32>;
  private let m_fitting: Bool;
  private let m_sourceBar: wref<inkWidget>;
  private let m_sourceSlider: wref<inkSliderController>;

  private let m_songRows: array<wref<inkWidget>>;
  private let m_songLabels: array<wref<inkText>>;
  private let m_songBars: array<wref<inkWidget>>;
  private let m_songIdle: array<wref<inkWidget>>;
  private let m_songFills: array<wref<inkWidget>>;
  private let m_songBar: wref<inkWidget>;
  private let m_songSlider: wref<inkSliderController>;

  private let m_shardRows: array<wref<inkWidget>>;
  private let m_shardLabels: array<wref<inkText>>;
  private let m_shardNums: array<wref<inkText>>;
  private let m_shardBars: array<wref<inkWidget>>;
  private let m_shardIdle: array<wref<inkWidget>>;
  private let m_shardUps: array<wref<inkWidget>>;
  private let m_shardDowns: array<wref<inkWidget>>;
  private let m_shardUpFills: array<wref<inkWidget>>;
  private let m_shardDownFills: array<wref<inkWidget>>;
  private let m_shardBar: wref<inkWidget>;
  private let m_shardSlider: wref<inkSliderController>;
  private let m_drawingBar: Bool;
  // Which rows scroll a long title: the cursor's and the song playing. The others stand still at the start.
  private let m_songBouncing: array<Bool>;
  private let m_shardBouncing: array<Bool>;
  private let m_scrollSpeed: Float;

  private let m_songsTitle: wref<inkText>;
  private let m_shardTitle: wref<inkText>;
  private let m_songsCaption: wref<inkText>;
  private let m_shardCaption: wref<inkText>;
  private let m_focusText: wref<inkText>;
  private let m_hintPlay: wref<inkWidget>;
  private let m_hintAdd: wref<inkWidget>;
  private let m_hintUp: wref<inkWidget>;
  private let m_hintDown: wref<inkWidget>;
  private let m_hintRename: wref<inkWidget>;

  private let m_filter: ref<HubTextInput>;
  private let m_filterText: String;
  private let m_renameWindow: wref<inkWidget>;
  private let m_renameInput: ref<HubTextInput>;
  private let m_renaming: Bool;
  // The delete confirmation is open.
  private let m_confirming: Bool;
  private let m_deleteWindow: wref<inkWidget>;
  private let m_deleteText: wref<inkText>;
  // The frame a text box let the keyboard go: the key that did it reaches the popup's actions too.
  private let m_releasedFrame: Uint64;

  // The shards, the one being built, its songs and its order.
  private let m_names: array<String>;
  private let m_shard: Int32;
  private let m_songs: array<CName>;
  private let m_ordered: Bool;

  // The sources: 0 All songs, then every station but the shard slot in dial order.
  private let m_stations: array<CName>;
  private let m_source: Int32;
  private let m_sourceTop: Int32;
  // The source's songs by title, after the filter, and the list before it, kept per source.
  private let m_listed: array<CName>;
  private let m_listedFor: String;
  private let m_lists: array<ref<RadioXLSongList>>;

  // The column with the keys (0 sources, 1 songs, 2 shard), and each column's cursor and first row shown.
  private let m_focus: Int32;
  private let m_cursor: array<Int32>;
  private let m_top: array<Int32>;
  private let m_pointer: Bool;
  private let m_leftHeld: Bool;
  private let m_rightHeld: Bool;
  // The move arrow showing its hover fill, 0 for none (no arrow's action is 0).
  private let m_fillArrow: Int32;
  // The frame the fill was set in: the same hover then reaches the row under the arrow.
  private let m_fillFrame: Uint64;
  // When proceed was last pressed, in engine seconds: proceed also clicks whatever the pointer rests on,
  // and that click is the same press, not a second one.
  private let m_proceedAt: Float;
  // The frame a checkbox or an arrow took a click: the same click then reaches the row under it.
  private let m_partFrame: Uint64;

  // Open, as the builder's own flag: a widget made visible this frame still reports itself hidden.
  private let m_open: Bool;
  private let m_lastTrack: CName;
  // The song just asked for and the source it was asked from (-1 the shard), shown as playing until the
  // radio reports a song: with the popup open game time runs slow, and the radio reports late.
  private let m_requested: CName;
  private let m_requestedSource: Int32;
  // A song asked for on a station the radio was still tuning to: asked again once the radio is on it,
  // as the tune's own first pick can win over a request made mid-tune.
  private let m_pendingStation: CName;
  private let m_pendingSong: CName;
  private let m_trackCheck: DelayID;
  private let m_checking: Bool;

  public func Build(owner: ref<VehicleRadioPopupGameController>) -> Void {
    let host = owner.GetRootCompoundWidget();
    if !IsDefined(host) { return; }
    let root = owner.SpawnFromExternal(host, r"radioxl\\gui\\shard_builder.inkwidget", n"builder") as inkCompoundWidget;
    if !IsDefined(root) { return; }
    // The popup's root draws its first child on top: first, the builder covers the vignette too.
    host.ReorderChild(root, 0);
    root.SetAnchor(inkEAnchor.Fill);
    root.SetVisible(false);
    this.m_root = root;
    this.m_owner = owner;
    this.m_cursor = [0, 0, 0];
    this.m_top = [0, 0, 0];

    let tabs: String = "header/lineContainer/center_holder/inkFlexWidget2/tabs/";
    let i: Int32 = 0;
    while true {
      let tab: wref<inkWidget> = this.At(tabs + s"tab\(i)");
      if !IsDefined(tab) { break; }
      ArrayPush(this.m_tabs, tab);
      ArrayPush(this.m_tabLabels, this.At(tabs + s"tab\(i)/inkVerticalPanelWidget2/center/txtValue") as inkText);
      this.Clickable(tab, this.m_actTab + i);
      i += 1;
    }
    this.m_tabNew = this.At(tabs + "tabNew");
    this.SetText(this.At(tabs + "tabNew/inkVerticalPanelWidget2/center/txtValue"), RadioXLText("RadioXL.bldNewTab"));
    this.Clickable(this.m_tabNew, this.m_actNew);
    this.m_tabSlider = this.At("header/lineContainer/center_holder/inkFlexWidget2/zero_size_holder/slider");

    this.SetText(this.At("sources/content/top_holder/title"), RadioXLText("RadioXL.bldSources"));
    this.Clickable(this.At("sources"), this.m_actColumn + 0);
    i = 0;
    while true {
      let path: String = s"sources/content/box/chips/chip\(i)";
      let chip: wref<inkWidget> = this.At(path);
      if !IsDefined(chip) { break; }
      ArrayPush(this.m_chips, chip);
      ArrayPush(this.m_chipLabels, this.At(path + "/frame/label") as inkText);
      ArrayPush(this.m_chipCounts, this.At(path + "/frame/count") as inkText);
      ArrayPush(this.m_chipBars, this.At(path + "/frame/bars"));
      ArrayPush(this.m_chipHovers, this.At(path + "/frame/hoverFrames"));
      ArrayPush(this.m_chipIcons, this.At(path + "/frame/icon") as inkImage);
      ArrayPush(this.m_chipSources, -1);
      this.TextAfterIcons(i);
      let strip: wref<inkWidget> = this.At(path + "/frame/background_leftBg");
      if IsDefined(strip) {
        strip.BindProperty(n"tintColor", n"MainColors.Red");
        strip.SetOpacity(0.61);
      }
      this.Clickable(chip, this.m_actChip + i);
      i += 1;
    }

    this.m_sourceBar = this.At("sources/content/box/scrollbar");
    this.m_sourceSlider = this.SliderOf("sources/content/box/scrollbar/slider", n"OnSourceBarMoved");

    this.m_songsTitle = this.At("songs/content/top_holder/title") as inkText;
    this.m_songsCaption = this.At("songs/content/caption") as inkText;
    this.Clickable(this.At("songs"), this.m_actColumn + 1);
    let slot = this.At("songs/content/filterSlot") as inkCompoundWidget;
    if IsDefined(slot) {
      this.m_filter = HubTextInput.Create();
      this.m_filter.SetName(n"filter");
      this.m_filter.SetDefaultText(RadioXLText("RadioXL.libFilter"));
      this.m_filter.SetWidth(slot.GetWidth());
      this.m_filter.Reparent(slot);
      this.m_filter.RegisterToCallback(n"OnInput", this, n"OnFilterInput");
      this.m_filter.RegisterToCallback(n"OnInputKey", this, n"OnFilterKey");
    }
    i = 0;
    while true {
      let path: String = s"songs/content/box/list/row\(i)";
      let row: wref<inkWidget> = this.At(path);
      if !IsDefined(row) { break; }
      ArrayPush(this.m_songRows, row);
      ArrayPush(this.m_songLabels, this.At(path + "/flexLayout/label") as inkText);
      ArrayPush(this.m_songBars, this.At(path + "/flexLayout/sizeProvider/Icon"));
      ArrayPush(this.m_songIdle, this.At(path + "/flexLayout/Code_TL"));
      ArrayPush(this.m_songFills, this.At(path + "/flexLayout/checkFill"));
      ArrayPush(this.m_songBouncing, true);
      this.Clickable(row, this.m_actSong + i);
      this.Clickable(this.At(path + "/flexLayout/checkFrame"), this.m_actCheck + i);
      i += 1;
    }
    this.m_songBar = this.At("songs/content/box/scrollbar");
    this.m_songSlider = this.SliderOf("songs/content/box/scrollbar/slider", n"OnSongBarMoved");

    this.m_shardTitle = this.At("shard/content/top_holder/title") as inkText;
    this.Clickable(this.At("shard/content/top_holder"), this.m_actRename);
    this.m_shardCaption = this.At("shard/content/caption") as inkText;
    this.Clickable(this.At("shard"), this.m_actColumn + 2);
    let order: String = "shard/content/order/layout/";
    this.SetText(this.At(order + "labels/label"), RadioXLText("RadioXL.bldOrder"));
    this.SetText(this.At(order + "container/onState/body/txtValue"), RadioXLText("RadioXL.bldInOrder"));
    this.SetText(this.At(order + "container/offState/body/txtValue"), RadioXLText("RadioXL.libShuffled"));
    for part in ["container", "container/onState/body", "container/offState/body"] {
      let w: wref<inkWidget> = this.At(order + part);
      if IsDefined(w) { w.SetInteractive(false); }
    }
    this.Clickable(this.At(order + "container/bk_border"), this.m_actOrder);
    this.m_renameWindow = this.At("renameWindow");
    this.SetText(this.At("renameWindow/renameBox/renameContent/top_holder/renameTitle"), RadioXLText("RadioXL.bldRenameTitle"));
    this.SetText(this.At("renameWindow/renameBox/renameContent/renameHint"), RadioXLText("RadioXL.bldRenameHint"));
    this.Clickable(this.At("renameWindow/renameDim"), this.m_actRenameCancel);
    // The popup itself takes its clicks, so one inside it does not reach the dimmed screen behind.
    this.Clickable(this.At("renameWindow/renameBox"), this.m_actRename);
    this.SetText(this.At("renameWindow/renameKeys/hintSave/text"), RadioXLText("RadioXL.bldSave"));
    this.SetText(this.At("renameWindow/renameKeys/hintCancel/text"), RadioXLText("RadioXL.bldCancel"));
    this.Clickable(this.At("renameWindow/renameKeys/hintSave"), this.m_actRenameSave);
    this.Clickable(this.At("renameWindow/renameKeys/hintCancel"), this.m_actRenameCancel);
    let nameSlot = this.At("renameWindow/renameBox/renameContent/renameSlot") as inkCompoundWidget;
    if IsDefined(nameSlot) {
      this.m_renameInput = HubTextInput.Create();
      this.m_renameInput.SetName(n"renameInput");
      this.m_renameInput.SetMaxLength(40);
      this.m_renameInput.SetWidth(nameSlot.GetWidth());
      this.m_renameInput.Reparent(nameSlot);
      this.m_renameInput.RegisterToCallback(n"OnInputKey", this, n"OnRenameKey");
    }
    // The frame's side strip is filled as on the cartridges; its own binding resolves to near black here.
    let renameStrip: wref<inkWidget> = this.At("renameWindow/renameBox/renameFrame/frame/background_leftBg");
    if IsDefined(renameStrip) {
      renameStrip.BindProperty(n"tintColor", n"MainColors.Red");
      renameStrip.SetOpacity(0.61);
    }
    this.m_deleteWindow = this.At("deleteWindow");
    this.m_deleteText = this.At("deleteWindow/deleteBox/deleteContent/deleteText") as inkText;
    this.SetText(this.At("deleteWindow/deleteBox/deleteContent/top_holder/deleteTitle"), RadioXLText("RadioXL.bldDeleteTitle"));
    this.SetText(this.At("deleteWindow/deleteBox/deleteContent/deleteHint"), RadioXLText("RadioXL.bldDeleteHint"));
    this.SetText(this.At("deleteWindow/deleteKeys/hintYes/text"), RadioXLText("RadioXL.bldDelete"));
    this.SetText(this.At("deleteWindow/deleteKeys/hintNo/text"), RadioXLText("RadioXL.bldCancel"));
    this.Clickable(this.At("deleteWindow/deleteDim"), this.m_actDeleteNo);
    this.Clickable(this.At("deleteWindow/deleteBox"), this.m_actModalBox);
    this.Clickable(this.At("deleteWindow/deleteKeys/hintYes"), this.m_actDeleteYes);
    this.Clickable(this.At("deleteWindow/deleteKeys/hintNo"), this.m_actDeleteNo);
    let deleteStrip: wref<inkWidget> = this.At("deleteWindow/deleteBox/deleteFrame/frame/background_leftBg");
    if IsDefined(deleteStrip) {
      deleteStrip.BindProperty(n"tintColor", n"MainColors.Red");
      deleteStrip.SetOpacity(0.61);
    }
    // Inside the builder the columns drew over the popups, so they move to the popup's root, above the builder.
    for window in [this.m_renameWindow, this.m_deleteWindow] {
      if IsDefined(window) {
        window.Reparent(host, -1);
        host.ReorderChild(window, 0);
      }
    }
    i = 0;
    while true {
      let path: String = s"shard/content/box/list/row\(i)";
      let row: wref<inkWidget> = this.At(path);
      if !IsDefined(row) { break; }
      ArrayPush(this.m_shardRows, row);
      ArrayPush(this.m_shardLabels, this.At(path + "/flexLayout/label") as inkText);
      ArrayPush(this.m_shardNums, this.At(path + "/flexLayout/num") as inkText);
      ArrayPush(this.m_shardBars, this.At(path + "/flexLayout/sizeProvider/Icon"));
      ArrayPush(this.m_shardIdle, this.At(path + "/flexLayout/Code_TL"));
      ArrayPush(this.m_shardBouncing, true);
      let up: wref<inkWidget> = this.At(path + "/flexLayout/up");
      let down: wref<inkWidget> = this.At(path + "/flexLayout/down");
      ArrayPush(this.m_shardUps, up);
      ArrayPush(this.m_shardDowns, down);
      ArrayPush(this.m_shardUpFills, this.At(path + "/flexLayout/upFill"));
      ArrayPush(this.m_shardDownFills, this.At(path + "/flexLayout/downFill"));
      this.Clickable(row, this.m_actShardRow + i);
      this.Clickable(up, this.m_actUp + i);
      this.Clickable(down, this.m_actDown + i);
      i += 1;
    }
    this.m_shardBar = this.At("shard/content/box/scrollbar");
    this.m_shardSlider = this.SliderOf("shard/content/box/scrollbar/slider", n"OnShardBarMoved");

    this.m_focusText = this.At("columnKeys/focus") as inkText;
    this.Clickable(this.At("columnKeys/keyPrev"), this.m_actPrevCol);
    this.Clickable(this.At("columnKeys/keyNext"), this.m_actNextCol);
    this.m_hintPlay = this.At("inputHints/hintPlay");
    this.m_hintAdd = this.At("inputHints/hintAdd");
    this.m_hintUp = this.At("inputHints/hintUp");
    this.m_hintDown = this.At("inputHints/hintDown");
    this.m_hintRename = this.At("inputHints/hintRename");
    this.SetText(this.At("inputHints/hintPlay/text"), RadioXLText("RadioXL.songsPlay"));
    this.SetText(this.At("inputHints/hintUp/text"), RadioXLText("RadioXL.bldUp"));
    this.SetText(this.At("inputHints/hintDown/text"), RadioXLText("RadioXL.bldDown"));
    this.SetText(this.At("inputHints/hintOrder/text"), RadioXLText("RadioXL.bldOrder"));
    this.SetText(this.At("inputHints/hintRename/text"), RadioXLText("RadioXL.libRename"));
    this.SetText(this.At("inputHints/hintDelete/text"), RadioXLText("RadioXL.bldDelete"));
    this.SetText(this.At("inputHints/hintDeletePad/text"), RadioXLText("RadioXL.bldDelete"));
    this.Clickable(this.At("inputHints/hintDelete"), this.m_actDelete);
    this.Clickable(this.At("inputHints/hintDeletePad"), this.m_actDelete);
    this.SetText(this.At("inputHints/hintClose/text"), RadioXLText("RadioXL.bldBack"));
    this.Clickable(this.m_hintAdd, this.m_actAdd);
    this.Clickable(this.At("inputHints/hintOrder"), this.m_actOrder);
    this.Clickable(this.m_hintRename, this.m_actRename);
    this.Clickable(this.At("inputHints/hintClose"), this.m_actBack);

    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/SongChanged", this, n"OnRadio");
    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/StationChanged", this, n"OnRadio");
    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/SongStateChanged", this, n"OnSongState");
  }

  // --- opening and closing -----------------------------------------------------------------------

  public func Shown() -> Bool {
    return IsDefined(this.m_root) && this.m_open;
  }

  // Shows the builder on the shard named, in place of the popup's frame.
  public func Open(name: String) -> Void {
    let shards = RadioXLShards.Get();
    if !IsDefined(this.m_root) || !IsDefined(shards) { return; }
    this.m_names = shards.Names();
    let at: Int32 = ArrayFindFirst(this.m_names, name);
    if at < 0 { return; }
    this.LoadShard(at);
    this.ListStations();
    let c: Int32 = 0;
    while c < ArraySize(this.m_chipSources) {
      this.m_chipSources[c] = -1;
      c += 1;
    }
    this.m_source = 0;
    this.m_sourceTop = 0;
    this.m_focus = 1;
    this.m_cursor = [0, 0, 0];
    this.m_top = [0, 0, 0];
    this.m_listedFor = "";
    this.m_filterText = "";
    if IsDefined(this.m_filter) { this.m_filter.SetText(""); }
    this.Frame(false);
    this.m_open = true;
    // The key that opened the builder (E on + NEW in the Library) also clicks whatever the pointer rests on,
    // which is now a builder widget: that click is dropped as proceed's own.
    this.m_proceedAt = EngineTime.ToFloat(GameInstance.GetEngineTime(GetGameInstance()));
    this.m_root.SetVisible(true);
    let open = new inkAnimDef();
    let fade = new inkAnimTransparency();
    fade.SetStartTransparency(0.0);
    fade.SetEndTransparency(1.0);
    fade.SetDuration(0.18);
    fade.SetType(inkanimInterpolationType.Sinusoidal);
    fade.SetMode(inkanimInterpolationMode.EasyOut);
    open.AddInterpolator(fade);
    this.m_root.SetOpacity(0.0);
    this.m_root.PlayAnimation(open);
    this.Sound();
    this.m_lastTrack = RadioXLAPI.CurrentTrack();
    if !this.m_checking {
      this.m_checking = true;
      this.ScheduleTrackCheck();
    }
    this.Draw();
    this.MoveCursor();
  }

  // Back to the Library. A shard left with no songs is deleted.
  public func Close() -> Void {
    if !this.Shown() { return; }
    if this.m_renaming { this.CloseRename(false); }
    if this.m_confirming { this.CloseDelete(); }
    let name: String = this.Name();
    this.DropIfEmpty();
    this.m_open = false;
    this.m_root.SetVisible(false);
    this.StopChecking();
    this.Frame(true);
    this.Sound();
    if IsDefined(this.m_owner) { this.m_owner.RadioXLBuilderClosed(name); }
  }

  // The popup is closing.
  public func Shutdown() -> Void {
    if this.Shown() {
      this.DropIfEmpty();
      this.m_open = false;
      this.m_root.SetVisible(false);
    }
    this.StopChecking();
    let cs = GameInstance.GetCallbackSystem();
    cs.UnregisterCallback(n"RadioXL/SongChanged", this);
    cs.UnregisterCallback(n"RadioXL/StationChanged", this);
    cs.UnregisterCallback(n"RadioXL/SongStateChanged", this);
  }

  private func DropIfEmpty() -> Void {
    let shards = RadioXLShards.Get();
    if ArraySize(this.m_songs) == 0 && StrLen(this.Name()) > 0 && IsDefined(shards) { shards.Delete(this.Name()); }
  }

  // The popup's own frame, with the Radioport, the Library and the tabs, steps aside while the builder shows.
  private func Frame(shown: Bool) -> Void {
    if !IsDefined(this.m_owner) { return; }
    let frame: wref<inkWidget> = this.m_owner.GetRootCompoundWidget().GetWidget(n"containerRoot");
    if IsDefined(frame) { frame.SetVisible(shown); }
  }

  private func StopChecking() -> Void {
    if !this.m_checking { return; }
    this.m_checking = false;
    GameInstance.GetDelaySystem(GetGameInstance()).CancelCallback(this.m_trackCheck);
  }

  public func CheckTrack() -> Void {
    if !this.m_checking { return; }
    this.KeepPending();
    let track: CName = RadioXLAPI.CurrentTrack();
    if NotEquals(track, this.m_lastTrack) {
      this.m_lastTrack = track;
      this.m_requested = n"";
      this.Draw();
    }
    this.ScheduleTrackCheck();
  }

  private func ScheduleTrackCheck() -> Void {
    let check = new RadioXLBuilderTrackCheck();
    check.builder = this;
    this.m_trackCheck = GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(check, 0.5, false);
  }

  private cb func OnRadio(e: ref<CallbackSystemEvent>) {
    this.KeepPending();
    if this.Shown() { this.Draw(); }
  }

  // Once the radio is on the station a song was asked for mid-tune, that song is asked for again unless
  // it is already playing.
  private func KeepPending() -> Void {
    if !IsNameValid(this.m_pendingStation) || NotEquals(RadioXLAPI.CurrentStation(), this.m_pendingStation) { return; }
    let song: CName = this.m_pendingSong;
    let station: CName = this.m_pendingStation;
    this.m_pendingStation = n"";
    if NotEquals(RadioXLAPI.CurrentTrack(), song) { RadioXLAPI.PlaySong(station, song); }
  }

  // A song switched on or off while the popup is open: the source lists are made again.
  private cb func OnSongState(e: ref<CallbackSystemEvent>) {
    ArrayClear(this.m_lists);
    this.m_listedFor = "";
    if this.Shown() { this.Draw(); }
  }

  // --- the shard ---------------------------------------------------------------------------------

  private func Name() -> String {
    return this.m_shard >= 0 && this.m_shard < ArraySize(this.m_names) ? this.m_names[this.m_shard] : "";
  }

  private func LoadShard(at: Int32) -> Void {
    let shards = RadioXLShards.Get();
    this.m_shard = at;
    this.m_songs = shards.Songs(this.Name());
    this.m_ordered = shards.IsOrdered(this.Name());
    this.m_cursor[2] = 0;
    this.m_top[2] = 0;
    this.KeepTabShown();
  }

  // Another shard's tab. The shard left behind is deleted if it has no songs.
  private func SelectShard(at: Int32) -> Void {
    if at == this.m_shard || at < 0 || at >= ArraySize(this.m_names) { return; }
    if this.m_renaming { this.CloseRename(false); }
    let next: String = this.m_names[at];
    this.DropIfEmpty();
    this.m_names = RadioXLShards.Get().Names();
    this.LoadShard(Max(ArrayFindFirst(this.m_names, next), 0));
    this.Sound();
    this.Draw();
    this.MoveCursor();
  }

  // + NEW: a shard named "Shard <n>" with no songs.
  private func CreateShard() -> Void {
    let shards = RadioXLShards.Get();
    if !IsDefined(shards) { return; }
    if this.m_renaming { this.CloseRename(false); }
    this.DropIfEmpty();
    let name: String = RadioXLShardBuilder.FreeName(shards.Names());
    let none: array<CName>;
    if !shards.Save(name, none, false) { return; }
    this.m_names = shards.Names();
    this.LoadShard(Max(ArrayFindFirst(this.m_names, name), 0));
    this.m_focus = 1;
    this.Sound();
    this.Draw();
    this.MoveCursor();
  }

  public final static func FreeName(names: array<String>) -> String {
    let n: Int32 = ArraySize(names) + 1;
    let name: String = StrReplace(RadioXLText("RadioXL.libNewName"), "{n}", IntToString(n));
    while ArrayContains(names, name) {
      n += 1;
      name = StrReplace(RadioXLText("RadioXL.libNewName"), "{n}", IntToString(n));
    }
    return name;
  }

  private func Save() -> Void {
    let shards = RadioXLShards.Get();
    if IsDefined(shards) { shards.Save(this.Name(), this.m_songs, this.m_ordered); }
    this.Sound();
    this.Draw();
  }

  // The song goes on the shard, at its end, or comes off it.
  private func Toggle(song: CName) -> Void {
    if !IsNameValid(song) { return; }
    if ArrayContains(this.m_songs, song) { ArrayRemove(this.m_songs, song); } else { ArrayPush(this.m_songs, song); }
    this.m_cursor[2] = Clamp(this.m_cursor[2], 0, Max(ArraySize(this.m_songs) - 1, 0));
    this.Save();
  }

  // The shard's song at 'index' moves one place; the cursor goes with it.
  private func Move(index: Int32, dir: Int32) -> Void {
    let to: Int32 = index + dir;
    if index < 0 || to < 0 || to >= ArraySize(this.m_songs) { return; }
    let song: CName = this.m_songs[index];
    this.m_songs[index] = this.m_songs[to];
    this.m_songs[to] = song;
    this.m_cursor[2] = to;
    this.KeepShown(2);
    this.Save();
    this.MoveCursor();
  }

  private func ToggleOrder() -> Void {
    this.m_ordered = !this.m_ordered;
    this.Save();
  }

  // --- the sources -------------------------------------------------------------------------------

  private func ListStations() -> Void {
    ArrayClear(this.m_stations);
    let slot: CName = RadioXLAPI.ShardStation();
    let all: array<CName> = RadioXLAPI.Stations();
    // A stream station plays one endless track, which a shard cannot use.
    for station in all {
      if NotEquals(station, slot) && !RadioXLAPI.IsStreamStation(station) { ArrayPush(this.m_stations, station); }
    }
  }

  private func Sources() -> Int32 {
    return 1 + ArraySize(this.m_stations);
  }

  private func StationOf(source: Int32) -> CName {
    return source >= 1 && source <= ArraySize(this.m_stations) ? this.m_stations[source - 1] : n"None";
  }

  private func Label(source: Int32) -> String {
    return source == 0 ? RadioXLText("RadioXL.libAll") : RadioXLAPI.StationName(this.StationOf(source));
  }

  private func PickSource(source: Int32) -> Void {
    if source < 0 || source >= this.Sources() { return; }
    if source != this.m_source {
      this.m_source = source;
      this.m_cursor[1] = 0;
      this.m_top[1] = 0;
      this.m_listedFor = "";
      this.Sound();
    }
    this.m_cursor[0] = source;
    this.KeepShown(0);
    this.Draw();
  }

  // A source's songs by title; All songs is every song once, a station its playable songs.
  private func ListFor(source: Int32) -> array<CName> {
    if source == 0 { return RadioXLShardBuilder.ByTitle(RadioXLAPI.ShardSongs(""), false); }
    return RadioXLShardBuilder.ByTitle(RadioXLAPI.Tracks(this.StationOf(source)), true);
  }

  public final static func ByTitle(tracks: array<CName>, playableOnly: Bool) -> array<CName> {
    let out: array<CName>;
    let titles: array<String>;
    for track in tracks {
      if !playableOnly || RadioXLAPI.IsSongPlayable(track) {
        let title: String = StrLower(RadioXLAPI.TrackTitle(track));
        let at: Int32 = ArraySize(out);
        while at > 0 && UnicodeStringLessThan(title, titles[at - 1]) { at -= 1; }
        ArrayInsert(out, at, track);
        ArrayInsert(titles, at, title);
      }
    }
    return out;
  }

  private func Listed(source: Int32) -> array<CName> {
    let key: String = IntToString(source);
    for list in this.m_lists {
      if Equals(list.key, key) { return list.songs; }
    }
    let list = new RadioXLSongList();
    list.key = key;
    list.songs = this.ListFor(source);
    ArrayPush(this.m_lists, list);
    return list.songs;
  }

  private func Refresh() -> Void {
    let key: String = s"\(this.m_source)|\(this.m_filterText)";
    if Equals(key, this.m_listedFor) { return; }
    this.m_listedFor = key;
    let songs: array<CName> = this.Listed(this.m_source);
    ArrayClear(this.m_listed);
    for song in songs {
      if StrLen(this.m_filterText) == 0 || StrFindFirst(StrLower(RadioXLAPI.TrackTitle(song)), this.m_filterText) >= 0 {
        ArrayPush(this.m_listed, song);
      }
    }
    this.m_cursor[1] = Clamp(this.m_cursor[1], 0, Max(ArraySize(this.m_listed) - 1, 0));
    this.m_top[1] = Clamp(this.m_top[1], 0, Max(ArraySize(this.m_listed) - ArraySize(this.m_songRows), 0));
  }

  protected cb func OnFilterInput(widget: wref<inkWidget>) {
    this.m_filterText = StrLower(this.m_filter.GetText());
    this.m_cursor[1] = 0;
    this.m_top[1] = 0;
    this.m_focus = 1;
    this.Draw();
  }

  // Esc or Enter gives the keyboard back to the popup.
  protected cb func OnFilterKey(event: ref<inkKeyInputEvent>) {
    if !Equals(event.GetAction(), EInputAction.IACT_Press) { return; }
    let key: EInputKey = event.GetKey();
    if Equals(key, EInputKey.IK_Escape) || Equals(key, EInputKey.IK_Enter) {
      this.m_releasedFrame = GameInstance.GetFrameNumber(GetGameInstance());
      GameInstance.GetInkSystem().ResetFocus();
    }
  }

  // True while a text box has the keyboard: the popup's own keys stand down.
  public func Typing() -> Bool {
    if !this.Shown() { return false; }
    if this.m_renaming { return true; }
    if IsDefined(this.m_filter) && this.m_filter.IsFocused() { return true; }
    return GameInstance.GetFrameNumber(GetGameInstance()) <= this.m_releasedFrame + 2ul;
  }

  // --- rename ------------------------------------------------------------------------------------

  // The rename popup opens over the screen with the name in its box. Enter keeps the new name; Esc or a
  // click outside the popup does not.
  private func OpenRename() -> Void {
    if !IsDefined(this.m_renameInput) || this.m_renaming { return; }
    this.m_renaming = true;
    this.m_renameWindow.SetVisible(true);
    this.m_renameInput.SetText(this.Name());
    this.m_renameInput.RequestSetFocus();
    this.m_renameInput.SelectAll();
    this.Sound();
  }

  private func CloseRename(keep: Bool) -> Void {
    if !this.m_renaming { return; }
    this.m_renaming = false;
    // Enter is proceed too, and clicks whatever the pointer rests on: that click is dropped.
    this.m_proceedAt = EngineTime.ToFloat(GameInstance.GetEngineTime(GetGameInstance()));
    this.m_releasedFrame = GameInstance.GetFrameNumber(GetGameInstance());
    GameInstance.GetInkSystem().ResetFocus();
    this.m_renameWindow.SetVisible(false);
    let name: String = this.m_renameInput.GetText();
    let shards = RadioXLShards.Get();
    if keep && StrLen(name) > 0 && NotEquals(name, this.Name()) && !ArrayContains(this.m_names, name)
      && IsDefined(shards) && shards.RenameShard(this.Name(), name) {
      this.m_names = shards.Names();
      this.m_shard = Max(ArrayFindFirst(this.m_names, name), 0);
    }
    this.Draw();
  }

  protected cb func OnRenameKey(event: ref<inkKeyInputEvent>) {
    if !Equals(event.GetAction(), EInputAction.IACT_Press) { return; }
    let key: EInputKey = event.GetKey();
    if Equals(key, EInputKey.IK_Escape) || Equals(key, EInputKey.IK_Enter) { this.CloseRename(Equals(key, EInputKey.IK_Enter)); }
  }

  // --- delete ----------------------------------------------------------------------------------

  // The confirmation names the shard and how many songs it holds.
  private func OpenDelete() -> Void {
    if !IsDefined(this.m_deleteWindow) || this.m_confirming || this.m_renaming || StrLen(this.Name()) == 0 { return; }
    this.m_confirming = true;
    let text: String = StrReplace(RadioXLText("RadioXL.bldDeleteText"), "{name}", this.Name());
    this.SetText(this.m_deleteText, StrReplace(text, "{n}", IntToString(ArraySize(this.m_songs))));
    this.m_deleteWindow.SetVisible(true);
    this.Sound();
  }

  private func CloseDelete() -> Void {
    if !this.m_confirming { return; }
    this.m_confirming = false;
    this.m_deleteWindow.SetVisible(false);
    this.Sound();
  }

  // The shard goes. The builder moves to the shard that took its place, or back to the Library when it was
  // the last.
  private func ConfirmDelete() -> Void {
    if !this.m_confirming { return; }
    let shards = RadioXLShards.Get();
    let name: String = this.Name();
    this.m_confirming = false;
    this.m_deleteWindow.SetVisible(false);
    if !IsDefined(shards) || !shards.Delete(name) { return; }
    this.m_names = shards.Names();
    if ArraySize(this.m_names) == 0 {
      this.m_shard = -1;
      ArrayClear(this.m_songs);
      this.Close();
      return;
    }
    this.LoadShard(Clamp(this.m_shard, 0, ArraySize(this.m_names) - 1));
    this.Sound();
    this.Draw();
    this.MoveCursor();
  }

  // --- playing -----------------------------------------------------------------------------------

  // A song from the songs column plays from its source: a station is tuned, All songs is slotted.
  private func PlayListed(index: Int32) -> Void {
    if index < 0 || index >= ArraySize(this.m_listed) { return; }
    let song: CName = this.m_listed[index];
    if this.m_source == 0 {
      RadioXLShards.Get().Slot("", song);
    } else {
      let station: CName = this.StationOf(this.m_source);
      this.m_pendingStation = n"";
      if NotEquals(station, RadioXLAPI.CurrentStation()) {
        RadioXLAPI.TuneStation(station);
        this.m_pendingStation = station;
        this.m_pendingSong = song;
      }
      RadioXLAPI.PlaySong(station, song);
    }
    this.Requested(song, this.m_source);
  }

  // A song from the shard column plays from the shard.
  private func PlayOwn(index: Int32) -> Void {
    if index < 0 || index >= ArraySize(this.m_songs) { return; }
    this.m_pendingStation = n"";
    RadioXLShards.Get().Slot(this.Name(), this.m_songs[index]);
    this.Requested(this.m_songs[index], -1);
  }

  private func Requested(song: CName, source: Int32) -> Void {
    this.m_requested = song;
    this.m_requestedSource = source;
    this.m_lastTrack = RadioXLAPI.CurrentTrack();
    this.Draw();
  }

  // The song shown as playing: the one just asked for until the radio reports a song.
  private func ShownTrack() -> CName {
    return IsNameValid(this.m_requested) ? this.m_requested : RadioXLAPI.CurrentTrack();
  }

  // --- input -------------------------------------------------------------------------------------

  public func SetPointer(on: Bool) -> Void {
    this.m_pointer = on;
  }

  private func Rows(column: Int32) -> Int32 {
    if column == 0 { return ArraySize(this.m_chips); }
    if column == 1 { return ArraySize(this.m_songRows); }
    return ArraySize(this.m_shardRows);
  }

  private func Count(column: Int32) -> Int32 {
    if column == 0 { return this.Sources(); }
    if column == 1 { return ArraySize(this.m_listed); }
    return ArraySize(this.m_songs);
  }

  private func KeepShown(column: Int32) -> Void {
    let rows: Int32 = this.Rows(column);
    let cursor: Int32 = this.m_cursor[column];
    if column == 0 {
      if cursor < this.m_sourceTop { this.m_sourceTop = cursor; }
      if cursor >= this.m_sourceTop + rows { this.m_sourceTop = cursor - rows + 1; }
      return;
    }
    if cursor < this.m_top[column] { this.m_top[column] = cursor; }
    if cursor >= this.m_top[column] + rows { this.m_top[column] = cursor - rows + 1; }
  }

  private func Step(step: Int32) -> Void {
    let n: Int32 = this.Count(this.m_focus);
    if n == 0 { return; }
    let was: Int32 = this.m_cursor[this.m_focus];
    this.m_cursor[this.m_focus] = Clamp(was + step, 0, n - 1);
    this.KeepShown(this.m_focus);
    if was != this.m_cursor[this.m_focus] { this.Sound(); }
    this.Draw();
    this.MoveCursor();
  }

  private func FocusColumn(column: Int32) -> Void {
    let next: Int32 = Clamp(column, 0, 2);
    if next == this.m_focus { return; }
    this.m_focus = next;
    if next == 0 { this.m_cursor[0] = this.m_source; }
    this.KeepShown(next);
    this.Sound();
    this.Draw();
    this.MoveCursor();
  }

  // The wheel moves the column under the pointer a row at a time.
  public func Scroll(up: Bool) -> Void {
    let column: Int32 = this.m_focus;
    if column == 0 {
      this.m_sourceTop = Clamp(this.m_sourceTop + (up ? -1 : 1), 0, Max(this.Sources() - this.Rows(0), 0));
    } else {
      this.m_top[column] = Clamp(this.m_top[column] + (up ? -1 : 1), 0, Max(this.Count(column) - this.Rows(column), 0));
    }
    this.Draw();
  }

  // The pad's triggers move the shard's song under its cursor, once each time a trigger passes half its
  // travel. They are axes, so a press is never sent.
  public func Trigger(name: CName, value: Float) -> Void {
    let left: Bool = Equals(name, n"left_trigger");
    let held: Bool = value > 0.5;
    let was: Bool = left ? this.m_leftHeld : this.m_rightHeld;
    if left { this.m_leftHeld = held; } else { this.m_rightHeld = held; }
    if held && !was {
      this.m_focus = 2;
      this.Move(this.m_cursor[2], left ? -1 : 1);
    }
  }

  // Every action the popup hears while the builder shows comes here, and none goes on to the popup.
  public func Act(action: ListenerAction) -> Void {
    let name: CName = ListenerAction.GetName(action);
    let type: gameinputActionType = ListenerAction.GetType(action);
    if this.Typing() { return; }
    if Equals(name, n"proceed") && Equals(type, gameinputActionType.BUTTON_PRESSED) {
      this.m_proceedAt = EngineTime.ToFloat(GameInstance.GetEngineTime(GetGameInstance()));
    }
    // The confirmation takes every key: proceed deletes, cancel keeps the shard. On the press, as proceed
    // also clicks whatever the pointer rests on (the dimmed screen cancels), and on the release, as a press
    // can be lost after a click; whichever comes first acts.
    if this.m_confirming {
      if Equals(type, gameinputActionType.BUTTON_PRESSED) || Equals(type, gameinputActionType.BUTTON_RELEASED) {
        if Equals(name, n"proceed") { this.ConfirmDelete(); }
        if Equals(name, n"cancel") { this.CloseDelete(); }
      }
      return;
    }
    if Equals(name, n"left_trigger") || Equals(name, n"right_trigger") {
      this.Trigger(name, ListenerAction.GetValue(action));
      return;
    }
    if Equals(name, n"mouse_wheel") {
      if ListenerAction.GetValue(action) != 0.0 { this.Scroll(ListenerAction.GetValue(action) > 0.0); }
      return;
    }
    let press: Bool = Equals(type, gameinputActionType.BUTTON_PRESSED);
    let step: Bool = press || Equals(type, gameinputActionType.REPEAT);
    switch name {
      case n"popup_moveUp":
        if step { this.Step(-1); }
        break;
      case n"popup_moveDown":
        if step { this.Step(1); }
        break;
      case n"radio_volume_down":
        if step { this.FocusColumn(this.m_focus - 1); }
        break;
      case n"radio_volume_up":
        if step { this.FocusColumn(this.m_focus + 1); }
        break;
      case n"prior_menu":
        if press { this.SelectShard(this.m_shard - 1); }
        break;
      case n"next_menu":
        if press { this.SelectShard(this.m_shard + 1); }
        break;
      case n"proceed":
        if press { this.Proceed(); }
        break;
      case n"secondaryAction":
        if press { this.AddKey(); }
        break;
      case n"showAll":
        if Equals(type, gameinputActionType.BUTTON_RELEASED) { this.ToggleOrder(); }
        break;
      case n"call":
        // On the release: after a click on a source the key's press never arrives, its release does.
        if Equals(type, gameinputActionType.BUTTON_RELEASED) && !this.Pad() { this.OpenRename(); }
        break;
      case n"cancel":
        if press { this.Close(); }
        break;
      // Delete: X on a keyboard, L3 on a pad. The pad's X is also Add, and some setups give
      // popup_goto_messenger the rename key, so each action answers only on its own device.
      case n"mod_notification_confirm":
        if Equals(type, gameinputActionType.BUTTON_RELEASED) && !this.Pad() { this.OpenDelete(); }
        break;
      case n"popup_goto_messenger":
        if Equals(type, gameinputActionType.BUTTON_RELEASED) && this.Pad() { this.OpenDelete(); }
        break;
    }
  }

  // Proceed (E, pad A) acts on the focused column's cursor.
  private func Proceed() -> Void {
    let cursor: Int32 = this.m_cursor[this.m_focus];
    if this.m_focus == 0 { this.PickSource(cursor); }
    if this.m_focus == 1 { this.PlayListed(cursor); }
    if this.m_focus == 2 { this.PlayOwn(cursor); }
  }

  // R, pad X: the song under the cursor goes on the shard or comes off it.
  private func AddKey() -> Void {
    let cursor: Int32 = this.m_cursor[this.m_focus];
    if this.m_focus == 1 && cursor < ArraySize(this.m_listed) { this.Toggle(this.m_listed[cursor]); }
    if this.m_focus == 2 && cursor < ArraySize(this.m_songs) { this.Toggle(this.m_songs[cursor]); }
  }

  public func Click(action: Int32) -> Void {
    // A click anywhere on a column also reaches the column: the filter box takes the keyboard on that
    // same click, so the column's own click does nothing.
    if action >= this.m_actColumn { return; }
    // The click proceed (E, pad A) makes on whatever the pointer rests on: proceed has already acted.
    let now: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(GetGameInstance()));
    if this.m_proceedAt > 0.0 && now - this.m_proceedAt < 0.5 {
      this.m_proceedAt = 0.0;
      return;
    }
    if this.m_renaming {
      if action == this.m_actRenameCancel { this.CloseRename(false); }
      if action == this.m_actRenameSave { this.CloseRename(true); }
      return;
    }
    if this.m_confirming {
      if action == this.m_actDeleteYes { this.ConfirmDelete(); }
      if action == this.m_actDeleteNo { this.CloseDelete(); }
      return;
    }
    if action == this.m_actDelete {
      this.OpenDelete();
      return;
    }
    if IsDefined(this.m_filter) && this.m_filter.IsFocused() { GameInstance.GetInkSystem().ResetFocus(); }
    let frame: Uint64 = GameInstance.GetFrameNumber(GetGameInstance());
    let onPart: Bool = (action >= this.m_actCheck && action < this.m_actShardRow) || (action >= this.m_actUp && action < this.m_actTab);
    if onPart { this.m_partFrame = frame; }
    let onRow: Bool = (action >= this.m_actSong && action < this.m_actCheck) || (action >= this.m_actShardRow && action < this.m_actUp);
    if onRow && frame == this.m_partFrame { return; }
    if action == this.m_actPrevCol || action == this.m_actNextCol {
      this.FocusColumn(this.m_focus + (action == this.m_actNextCol ? 1 : -1));
    } else if action == this.m_actAdd {
      this.AddKey();
    } else if action == this.m_actBack {
      this.Close();
    } else if action == this.m_actRename {
      if !this.m_renaming { this.OpenRename(); }
    } else if action == this.m_actOrder {
      this.ToggleOrder();
    } else if action == this.m_actNew {
      this.CreateShard();
    } else if action >= this.m_actTab {
      this.SelectShard(this.m_tabTop + action - this.m_actTab);
    } else if action >= this.m_actDown {
      this.Move(this.m_top[2] + action - this.m_actDown, 1);
    } else if action >= this.m_actUp {
      this.Move(this.m_top[2] + action - this.m_actUp, -1);
    } else if action >= this.m_actShardRow {
      this.m_focus = 2;
      this.m_cursor[2] = this.m_top[2] + action - this.m_actShardRow;
      this.PlayOwn(this.m_cursor[2]);
    } else if action >= this.m_actCheck {
      let index: Int32 = this.m_top[1] + action - this.m_actCheck;
      this.m_focus = 1;
      if index < ArraySize(this.m_listed) { this.Toggle(this.m_listed[index]); }
    } else if action >= this.m_actSong {
      this.m_focus = 1;
      this.m_cursor[1] = this.m_top[1] + action - this.m_actSong;
      this.PlayListed(this.m_cursor[1]);
    } else {
      this.m_focus = 0;
      this.PickSource(this.m_sourceTop + action - this.m_actChip);
    }
  }

  // The pointer over a column gives it the keys; over a row it puts that column's cursor there.
  public func Hovered(action: Int32) -> Void {
    // The screen behind a popup takes no pointer.
    if this.m_renaming || this.m_confirming { return; }
    // The pointer on anything else clears the last arrow's fill, as well as the arrow's own hover-out.
    let onArrow: Bool = action >= this.m_actUp && action < this.m_actTab;
    let frame: Uint64 = GameInstance.GetFrameNumber(GetGameInstance());
    if this.m_fillArrow > 0 && this.m_fillArrow != action && (onArrow || frame != this.m_fillFrame) {
      this.ArrowFill(this.m_fillArrow, false);
      this.m_fillArrow = 0;
    }
    if onArrow {
      this.ArrowFill(action, true);
      this.m_fillArrow = action;
      this.m_fillFrame = frame;
    }
    if !this.m_pointer { return; }
    let column: Int32 = -1;
    let row: Int32 = -1;
    if action >= this.m_actColumn { column = action - this.m_actColumn; }
    else if action >= this.m_actTab { return; }
    else if action >= this.m_actShardRow { column = 2; row = this.m_top[2] + (action - this.m_actShardRow) % 100; }
    else if action >= this.m_actSong { column = 1; row = this.m_top[1] + (action - this.m_actSong) % 100; }
    else { column = 0; row = this.m_sourceTop + action - this.m_actChip; }
    let changed: Bool = column != this.m_focus;
    this.m_focus = column;
    if row >= 0 && row < this.Count(column) && row != this.m_cursor[column] {
      this.m_cursor[column] = row;
      changed = true;
    }
    if changed { this.Draw(); }
  }

  public func Unhovered(action: Int32) -> Void {
    if this.m_fillArrow > 0 && action == this.m_fillArrow {
      this.ArrowFill(action, false);
      this.m_fillArrow = 0;
    }
  }

  // A move arrow fills while the pointer is on it.
  private func ArrowFill(action: Int32, on: Bool) -> Void {
    let down: Bool = action >= this.m_actDown;
    let i: Int32 = action - (down ? this.m_actDown : this.m_actUp);
    let fills: array<wref<inkWidget>> = down ? this.m_shardDownFills : this.m_shardUpFills;
    if i >= 0 && i < ArraySize(fills) && IsDefined(fills[i]) { fills[i].SetVisible(on); }
  }

  private func Pad() -> Bool {
    return IsDefined(this.m_owner) && this.m_owner.GetPlayerControlledObject().PlayerLastUsedPad();
  }

  // The pad steers the game's cursor, so it follows the selection; keys leave the mouse cursor where it is.
  private func MoveCursor() -> Void {
    if this.m_pointer || !this.Pad() { return; }
    let target: wref<inkWidget>;
    if this.m_focus == 0 {
      let i: Int32 = this.m_cursor[0] - this.m_sourceTop;
      if i >= 0 && i < ArraySize(this.m_chips) { target = this.m_chips[i]; }
    } else if this.m_focus == 1 {
      let i: Int32 = this.m_cursor[1] - this.m_top[1];
      if i >= 0 && i < ArraySize(this.m_songRows) { target = this.m_songRows[i]; }
    } else {
      let i: Int32 = this.m_cursor[2] - this.m_top[2];
      if i >= 0 && i < ArraySize(this.m_shardRows) { target = this.m_shardRows[i]; }
    }
    if IsDefined(target) { this.m_owner.SetCursorOverWidget(target, 0.0, true); }
  }

  private func Sound() -> Void {
    if IsDefined(this.m_owner) { this.m_owner.PlaySound(n"Holocall", n"Navigation"); }
  }

  // --- drawing -----------------------------------------------------------------------------------

  private func KeepTabShown() -> Void {
    let shown: Int32 = ArraySize(this.m_tabs);
    if this.m_shard < this.m_tabTop { this.m_tabTop = this.m_shard; }
    if this.m_shard >= this.m_tabTop + shown { this.m_tabTop = this.m_shard - shown + 1; }
    this.m_tabTop = Clamp(this.m_tabTop, 0, Max(ArraySize(this.m_names) - shown, 0));
  }

  public func Draw() -> Void {
    if !this.Shown() { return; }
    this.DrawTabs();
    this.DrawSources();
    this.Refresh();
    this.DrawSongs();
    this.DrawShard();
    this.DrawFoot();
  }

  // The hub menu's bar: the shard shown in its Selected state, and the blue line slid under it.
  private func DrawTabs() -> Void {
    let i: Int32 = 0;
    let place: Int32 = 0;
    while i < ArraySize(this.m_tabs) {
      let at: Int32 = this.m_tabTop + i;
      let shown: Bool = at < ArraySize(this.m_names);
      this.m_tabs[i].SetVisible(shown);
      if shown {
        this.SetText(this.m_tabLabels[i], this.m_names[at]);
        this.m_tabs[i].SetState(at == this.m_shard ? n"Selected" : n"Default");
        if at == this.m_shard { place = i; }
      }
      i += 1;
    }
    if !IsDefined(this.m_tabSlider) { return; }
    // Each label is 300 wide with 10 between them (tools/shard-builder-ink.py TAB_W, the hub bar's gap).
    let target: Float = Cast<Float>(place) * 310.0;
    let slide = new inkAnimTranslation();
    slide.SetStartTranslation(this.m_tabSlider.GetTranslation());
    slide.SetEndTranslation(new Vector2(target, 0.0));
    slide.SetDuration(0.2);
    slide.SetType(inkanimInterpolationType.Quadratic);
    slide.SetMode(inkanimInterpolationMode.EasyOut);
    let def = new inkAnimDef();
    def.AddInterpolator(slide);
    this.m_tabSlider.PlayAnimation(def);
  }

  private func DrawSources() -> Void {
    let playing: CName = RadioXLAPI.CurrentStation();
    let onSlot: Bool = Equals(playing, RadioXLAPI.ShardStation()) && StrLen(RadioXLAPI.SlottedShard()) == 0;
    let n: Int32 = this.Sources();
    let i: Int32 = 0;
    while i < ArraySize(this.m_chips) {
      let source: Int32 = this.m_sourceTop + i;
      let chip: wref<inkWidget> = this.m_chips[i];
      let shown: Bool = source < n;
      chip.SetVisible(shown);
      if shown {
        let picked: Bool = source == this.m_source;
        let cursor: Bool = this.m_focus == 0 && source == this.m_cursor[0];
        chip.SetOpacity(picked || cursor ? 1.0 : 0.6);
        if IsDefined(this.m_chipHovers[i]) { this.m_chipHovers[i].SetVisible(picked || cursor); }
        this.DrawChipIcon(i, source);
        this.SetText(this.m_chipLabels[i], this.Label(source));
        let songs: array<CName> = this.Listed(source);
        this.SetText(this.m_chipCounts[i], StrReplace(RadioXLText("RadioXL.libCount"), "{n}", IntToString(ArraySize(songs))));
        let isPlaying: Bool = source == 0 ? onSlot : Equals(this.StationOf(source), playing);
        if IsNameValid(this.m_requested) { isPlaying = source == this.m_requestedSource; }
        if IsDefined(this.m_chipBars[i]) { this.m_chipBars[i].SetVisible(isPlaying); }
      }
      i += 1;
    }
    this.DrawBar(this.m_sourceBar, this.m_sourceSlider, n, ArraySize(this.m_chips), this.m_sourceTop);
  }

  private func DrawSongs() -> Void {
    this.SetText(this.m_songsTitle, this.Label(this.m_source));
    let count: Int32 = ArraySize(this.m_listed);
    let caption: String = StrReplace(RadioXLText("RadioXL.bldSongCount"), "{n}", IntToString(count));
    if StrLen(this.m_filterText) > 0 && count == 0 { caption = RadioXLText("RadioXL.libNoMatch"); }
    this.SetText(this.m_songsCaption, caption);
    let track: CName = this.ShownTrack();
    let i: Int32 = 0;
    while i < ArraySize(this.m_songRows) {
      let index: Int32 = this.m_top[1] + i;
      let row: wref<inkWidget> = this.m_songRows[i];
      row.SetVisible(index < count);
      if index < count {
        let song: CName = this.m_listed[index];
        let isPlaying: Bool = Equals(song, track);
        this.SetText(this.m_songLabels[i], RadioXLAPI.TrackTitle(song));
        let scrolls: Bool = isPlaying || (this.m_focus == 1 && index == this.m_cursor[1]);
        if NotEquals(scrolls, this.m_songBouncing[i]) {
          this.m_songBouncing[i] = scrolls;
          this.Stopped(this.m_songLabels[i], !scrolls);
        }
        if IsDefined(this.m_songBars[i]) { this.m_songBars[i].SetVisible(isPlaying); }
        if IsDefined(this.m_songIdle[i]) { this.m_songIdle[i].SetVisible(!isPlaying); }
        if IsDefined(this.m_songFills[i]) { this.m_songFills[i].SetVisible(ArrayContains(this.m_songs, song)); }
        row.SetState(this.m_focus == 1 && index == this.m_cursor[1] ? n"Active" : n"Default");
      }
      i += 1;
    }
    this.DrawBar(this.m_songBar, this.m_songSlider, count, ArraySize(this.m_songRows), this.m_top[1]);
  }

  private func DrawShard() -> Void {
    this.SetText(this.m_shardTitle, this.Name());
    let count: Int32 = ArraySize(this.m_songs);
    let caption: String = StrReplace(RadioXLText("RadioXL.bldSongCount"), "{n}", IntToString(count));
    if count == 0 { caption = RadioXLText("RadioXL.bldEmpty"); }
    this.SetText(this.m_shardCaption, caption);
    let onState: wref<inkWidget> = this.At("shard/content/order/layout/container/onState");
    let offState: wref<inkWidget> = this.At("shard/content/order/layout/container/offState");
    if IsDefined(onState) { onState.SetVisible(this.m_ordered); }
    if IsDefined(offState) { offState.SetVisible(!this.m_ordered); }
    let track: CName = this.ShownTrack();
    let i: Int32 = 0;
    while i < ArraySize(this.m_shardRows) {
      let index: Int32 = this.m_top[2] + i;
      let row: wref<inkWidget> = this.m_shardRows[i];
      row.SetVisible(index < count);
      if index < count {
        let song: CName = this.m_songs[index];
        let isPlaying: Bool = Equals(song, track);
        this.SetText(this.m_shardNums[i], IntToString(index + 1));
        this.SetText(this.m_shardLabels[i], RadioXLAPI.TrackTitle(song));
        let scrolls: Bool = isPlaying || (this.m_focus == 2 && index == this.m_cursor[2]);
        if NotEquals(scrolls, this.m_shardBouncing[i]) {
          this.m_shardBouncing[i] = scrolls;
          this.Stopped(this.m_shardLabels[i], !scrolls);
        }
        if IsDefined(this.m_shardBars[i]) { this.m_shardBars[i].SetVisible(isPlaying); }
        if IsDefined(this.m_shardIdle[i]) { this.m_shardIdle[i].SetVisible(false); }
        if IsDefined(this.m_shardUps[i]) { this.m_shardUps[i].SetVisible(index > 0); }
        if IsDefined(this.m_shardDowns[i]) { this.m_shardDowns[i].SetVisible(index < count - 1); }
        if index == 0 && IsDefined(this.m_shardUpFills[i]) { this.m_shardUpFills[i].SetVisible(false); }
        if index == count - 1 && IsDefined(this.m_shardDownFills[i]) { this.m_shardDownFills[i].SetVisible(false); }
        row.SetState(this.m_focus == 2 && index == this.m_cursor[2] ? n"Active" : n"Default");
      }
      i += 1;
    }
    this.DrawBar(this.m_shardBar, this.m_shardSlider, count, ArraySize(this.m_shardRows), this.m_top[2]);
  }

  // The footer names the column with the keys and shows only the keys that act in it.
  private func DrawFoot() -> Void {
    let names: array<String> = ["RadioXL.bldSources", "RadioXL.bldSongs", "RadioXL.bldShard"];
    this.SetText(this.m_focusText, RadioXLText(names[this.m_focus]));
    let pad: Bool = this.Pad();
    let songs: Int32 = this.Count(this.m_focus);
    if IsDefined(this.m_hintPlay) { this.m_hintPlay.SetVisible(this.m_focus > 0 && songs > 0); }
    if IsDefined(this.m_hintAdd) {
      this.m_hintAdd.SetVisible(this.m_focus > 0 && songs > 0);
      let on: Bool = false;
      let cursor: Int32 = this.m_cursor[this.m_focus];
      if this.m_focus == 1 && cursor < ArraySize(this.m_listed) { on = ArrayContains(this.m_songs, this.m_listed[cursor]); }
      if this.m_focus == 2 { on = true; }
      this.SetText(this.At("inputHints/hintAdd/text"), RadioXLText(on ? "RadioXL.libRemove" : "RadioXL.bldAdd"));
    }
    // The triggers move a song on the pad; with keys and mouse the row's arrows do.
    let moving: Bool = pad && this.m_focus == 2 && ArraySize(this.m_songs) > 1;
    if IsDefined(this.m_hintUp) { this.m_hintUp.SetVisible(moving); }
    if IsDefined(this.m_hintDown) { this.m_hintDown.SetVisible(moving); }
    // Renaming takes a keyboard, so a pad player is not offered it.
    if IsDefined(this.m_hintRename) { this.m_hintRename.SetVisible(!pad); }
    let hintDelete: wref<inkWidget> = this.At("inputHints/hintDelete");
    let hintDeletePad: wref<inkWidget> = this.At("inputHints/hintDeletePad");
    if IsDefined(hintDelete) { hintDelete.SetVisible(!pad); }
    if IsDefined(hintDeletePad) { hintDeletePad.SetVisible(pad); }
  }

  // A long title scrolls, or stands still at its start, clipped as a scrolling one is.
  private func Stopped(label: wref<inkText>, stopped: Bool) -> Void {
    if !IsDefined(label) { return; }
    if this.m_scrollSpeed <= 0.0 { this.m_scrollSpeed = label.GetScrollTextSpeed(); }
    let speed: Float = stopped ? 0.0 : this.m_scrollSpeed;
    if label.GetScrollTextSpeed() == speed { return; }
    label.SetScrollTextSpeed(speed);
    // Setting the text again puts a stopped text back at its start.
    let text: String = label.GetText();
    label.SetText("");
    label.SetText(text);
  }

  // The handle is as long as the share of the songs on screen, and sits where they are in the list.
  private func DrawBar(bar: wref<inkWidget>, slider: wref<inkSliderController>, count: Int32, rows: Int32, top: Int32) -> Void {
    if !IsDefined(bar) { return; }
    bar.SetVisible(count > rows);
    if count <= rows || !IsDefined(slider) { return; }
    this.m_drawingBar = true;
    slider.SetPercentageHandleSize(Cast<Float>(rows) / Cast<Float>(count));
    slider.ChangeProgress(Cast<Float>(top) / Cast<Float>(count - rows));
    this.m_drawingBar = false;
  }

  protected cb func OnSourceBarMoved(slider: wref<inkSliderController>, progress: Float, value: Float) -> Bool {
    if this.m_drawingBar { return false; }
    let most: Int32 = Max(this.Sources() - ArraySize(this.m_chips), 0);
    let top: Int32 = Clamp(RoundF(progress * Cast<Float>(most)), 0, most);
    if top != this.m_sourceTop {
      this.m_sourceTop = top;
      this.Draw();
    }
    return false;
  }

  protected cb func OnSongBarMoved(slider: wref<inkSliderController>, progress: Float, value: Float) -> Bool {
    if this.m_drawingBar { return false; }
    let most: Int32 = Max(ArraySize(this.m_listed) - ArraySize(this.m_songRows), 0);
    let top: Int32 = Clamp(RoundF(progress * Cast<Float>(most)), 0, most);
    if top != this.m_top[1] {
      this.m_top[1] = top;
      this.Draw();
    }
    return false;
  }

  protected cb func OnShardBarMoved(slider: wref<inkSliderController>, progress: Float, value: Float) -> Bool {
    if this.m_drawingBar { return false; }
    let most: Int32 = Max(ArraySize(this.m_songs) - ArraySize(this.m_shardRows), 0);
    let top: Int32 = Clamp(RoundF(progress * Cast<Float>(most)), 0, most);
    if top != this.m_top[2] {
      this.m_top[2] = top;
      this.Draw();
    }
    return false;
  }

  // Every logo sits in the same box, 110 x 60, scaled to fit it whole and centred in it, so the names after
  // it all start at one line. All songs shows the shard.
  private func DrawChipIcon(i: Int32, source: Int32) -> Void {
    let icon: wref<inkImage> = this.m_chipIcons[i];
    if !IsDefined(icon) || this.m_chipSources[i] == source { return; }
    this.m_chipSources[i] = source;
    let stationIcon: TweakDBID = source > 0 ? RadioXLAPI.StationIcon(this.StationOf(source)) : TDBID.None();
    if TDBID.IsValid(stationIcon) {
      // The logo takes its atlas part's size and is scaled into the box once it has loaded, in FitIcons. It
      // stays visible meanwhile: a widget at opacity 0 is never measured.
      icon.SetFitToContent(true);
      icon.SetRenderTransformPivot(0.0, 0.5);
      InkImageUtils.RequestSetImage(this.m_owner, icon, stationIcon);
      this.StartFitting();
    } else {
      icon.SetFitToContent(false);
      icon.SetScale(new Vector2(1.0, 1.0));
      icon.SetSize(new Vector2(66.0, 60.0));
      this.PlaceIcon(icon, 66.0);
      InkImageUtils.RequestSetImage(this.m_owner, icon, TDBID.Create(RadioXLDial.IconName(RadioXL_ShardSlot())));
    }
  }

  private func PlaceIcon(icon: wref<inkImage>, shownWidth: Float) -> Void {
    let m: inkMargin = icon.GetMargin();
    m.left = 16.0 + (110.0 - shownWidth) / 2.0;
    icon.SetMargin(m);
  }

  private func StartFitting() -> Void {
    if this.m_fitting { return; }
    this.m_fitting = true;
    this.FitIcons(0);
  }

  // A logo loads a frame or more after it is asked for, and its size is known only then.
  public func FitIcons(tries: Int32) -> Void {
    let i: Int32 = 0;
    while i < ArraySize(this.m_chipIcons) {
      let icon: wref<inkImage> = this.m_chipIcons[i];
      if IsDefined(icon) && icon.GetFitToContent() {
        let native: Vector2 = icon.GetDesiredSize();
        if native.X > 0.0 && native.Y > 0.0 {
          let scale: Float = MinF(110.0 / native.X, 60.0 / native.Y);
          icon.SetScale(new Vector2(scale, scale));
          this.PlaceIcon(icon, native.X * scale);
        }
      }
      i += 1;
    }
    if tries >= 10 {
      this.m_fitting = false;
    } else {
      let again = new RadioXLBuilderFitIcons();
      again.builder = this;
      again.tries = tries + 1;
      GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(again, 0.05, false);
    }
  }

  // The name and count start after the logo box, the same on every cartridge.
  private func TextAfterIcons(i: Int32) -> Void {
    let left: Float = 16.0 + 110.0 + 16.0;
    let label: wref<inkText> = this.m_chipLabels[i];
    if IsDefined(label) {
      let m: inkMargin = label.GetMargin();
      m.left = left;
      label.SetMargin(m);
      label.SetWidth(this.m_chips[i].GetWidth() - left - 32.0);
    }
    let count: wref<inkText> = this.m_chipCounts[i];
    if IsDefined(count) {
      let m: inkMargin = count.GetMargin();
      m.left = left;
      count.SetMargin(m);
    }
  }

  // --- the copied widgets ------------------------------------------------------------------------

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

  private func SliderOf(path: String, callback: CName) -> wref<inkSliderController> {
    let widget: wref<inkWidget> = this.At(path);
    let slider: wref<inkSliderController> = IsDefined(widget) ? widget.GetController() as inkSliderController : null;
    if IsDefined(slider) {
      slider.Setup(0.0, 1.0, 0.0, 0.0);
      slider.RegisterToCallback(n"OnSliderValueChanged", this, callback);
    }
    return slider;
  }

  private func Clickable(widget: wref<inkWidget>, action: Int32) -> Void {
    if !IsDefined(widget) { return; }
    let click = new RadioXLBuilderClick();
    click.builder = this;
    click.action = action;
    ArrayPush(this.m_clicks, click);
    widget.SetInteractive(true);
    widget.RegisterToCallback(n"OnRelease", click, n"OnRelease");
    widget.RegisterToCallback(n"OnHoverOver", click, n"OnHoverOver");
    widget.RegisterToCallback(n"OnHoverOut", click, n"OnHoverOut");
  }
}

// --- the popup ----------------------------------------------------------------------------------

@addField(VehicleRadioPopupGameController)
private let m_radioXLBuilder: ref<RadioXLShardBuilder>;

@wrapMethod(VehicleRadioPopupGameController)
protected cb func OnPlayerAttach(playerPuppet: ref<GameObject>) -> Bool {
  let result: Bool = wrappedMethod(playerPuppet);
  let builder = new RadioXLShardBuilder();
  builder.Build(this);
  builder.SetPointer(this.m_radioXLPointer);
  this.m_radioXLBuilder = builder;
  // The popup hears only the actions it listens for: the builder's delete keys.
  this.GetPlayerControlledObject().RegisterInputListener(this, n"mod_notification_confirm");
  this.GetPlayerControlledObject().RegisterInputListener(this, n"popup_goto_messenger");
  return result;
}

// The builder on the shard named, from the Library.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLOpenBuilder(name: String) -> Void {
  if IsDefined(this.m_radioXLBuilder) { this.m_radioXLBuilder.Open(name); }
}

// True while the builder shows: it takes every action.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLBuilderAct(action: ListenerAction) -> Bool {
  if !IsDefined(this.m_radioXLBuilder) || !this.m_radioXLBuilder.Shown() { return false; }
  this.m_radioXLBuilder.Act(action);
  return true;
}

// Back in the Library, on the shard just built.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLBuilderClosed(name: String) -> Void {
  if IsDefined(this.m_radioXLLibrary) { this.m_radioXLLibrary.ShowShard(name); }
}
