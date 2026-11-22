// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The Library panel to the left of the station selection UI: the shard cartridges and
//              the songs of the one picked.
//
//              The panel is radioxl\gui\library_panel.inkwidget, item "panel", made by
//              tools/library-panel-ink.py from the game's own widgets. The cartridge strip lists ALL
//              SONGS, the player's shards and + NEW, or every station; showAll swaps the two. Up and
//              down move through the songs, the volume keys step the cartridges, the filter box
//              narrows the list, and Play starts the song: on a shard or All songs it slots that
//              shard first. R on a shard opens the shard builder on it, and + NEW makes a shard and
//              opens it there (Builder.reds). The rows are a fixed set re-labelled as the list
//              scrolls. Focus and the pointer are shared with the station list and the equalizer
//              through the popup.
// File Version: 0.11.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL
import Codeware.UI.*

// One clickable part of the panel: a cartridge, a pager arrow or a song row.
public class RadioXLLibClick extends IScriptable {
  public let panel: wref<RadioXLLibraryPanel>;
  public let action: Int32;

  protected cb func OnRelease(e: ref<inkPointerEvent>) -> Bool {
    if e.IsAction(n"click") && IsDefined(this.panel) { this.panel.Click(this.action); }
    return true;
  }

  protected cb func OnHoverOver(e: ref<inkPointerEvent>) -> Bool {
    if IsDefined(this.panel) { this.panel.Hovered(this.action); }
    return false;
  }

  protected cb func OnHoverOut(e: ref<inkPointerEvent>) -> Bool {
    if IsDefined(this.panel) { this.panel.Unhovered(this.action); }
    return false;
  }
}

// Half a second of real time: the popup slows the game, and on foot no event says the song changed.
public class RadioXLLibTrackCheck extends DelayCallback {
  public let panel: wref<RadioXLLibraryPanel>;

  public func Call() -> Void {
    if IsDefined(this.panel) { this.panel.CheckTrack(); }
  }
}

// One cartridge's songs as listed, kept so changing cartridge does not sort them again.
public class RadioXLSongList extends IScriptable {
  public let key: String;
  public let songs: array<CName>;
}

// After the popup's open animation: All songs is the longest list to sort, so it is sorted while nothing moves.
public class RadioXLLibPrepare extends DelayCallback {
  public let panel: wref<RadioXLLibraryPanel>;

  public func Call() -> Void {
    if IsDefined(this.panel) { this.panel.Prepare(); }
  }
}

// One logo fitting pass.
public class RadioXLLibFitIcons extends DelayCallback {
  public let panel: wref<RadioXLLibraryPanel>;
  public let tries: Int32;

  public func Call() -> Void {
    if IsDefined(this.panel) { this.panel.FitIcons(this.tries); }
  }
}

public class RadioXLLibraryPanel extends IScriptable {
  private let m_actChip: Int32 = 0;   // + the cartridge on screen
  private let m_actPrev: Int32 = 20;
  private let m_actNext: Int32 = 21;
  private let m_actMode: Int32 = 22;
  private let m_actEdit: Int32 = 24;
  private let m_actRow: Int32 = 100;  // + the row

  private let m_root: wref<inkCompoundWidget>;
  private let m_owner: wref<inkGameController>;
  private let m_clicks: array<ref<RadioXLLibClick>>;

  // The cartridge picked in the middle, its neighbours either side, round in a ring.
  private let m_chipRow: wref<inkWidget>;
  private let m_chips: array<wref<inkWidget>>;
  private let m_chipLabels: array<wref<inkText>>;
  private let m_chipCounts: array<wref<inkText>>;
  // The station list's playing bars on each cartridge, shown on the one playing.
  private let m_chipBars: array<wref<inkWidget>>;
  private let m_position: wref<inkText>;
  private let m_caption: wref<inkText>;
  private let m_rows: array<wref<inkWidget>>;
  private let m_rowLabels: array<wref<inkText>>;
  private let m_rowBars: array<wref<inkWidget>>;
  // The station list's still icon, shown on the rows that are not playing.
  private let m_rowIdle: array<wref<inkWidget>>;
  // Which rows scroll a long title: the song under the cursor and the song playing. The others stand still
  // at the start, clipped as the scrolling ones are.
  private let m_rowBouncing: array<Bool>;
  private let m_scrollSpeed: Float;
  // The cartridge slot under the pointer, -1 for none: E plays it. The slots stay where they are when the strip
  // changes, so it holds while the mouse rests.
  private let m_pointerChip: Int32;
  // The slot whose frame shows the pointer on it, -1 for none. A strip that changed under a still pointer shows
  // no frame until the mouse moves.
  private let m_hoverChip: Int32;
  // When proceed was last pressed, in engine seconds: the click its release makes on whatever the pointer
  // rests on is the same press, not a second one.
  private let m_proceedAt: Float;
  private let m_chipHovers: array<wref<inkWidget>>;
  private let m_chipIcons: array<wref<inkImage>>;
  // A cartridge being played, step by step: pressed where it is, slid to the middle, seated. While it runs
  // a redraw changes no cartridge's look, or it would cut into the animation.
  private let m_animating: Bool;
  // Logo fitting passes are running.
  private let m_fitting: Bool;
  private let m_lists: array<ref<RadioXLSongList>>;
  private let m_playSource: Int32;
  private let m_playDir: Int32;
  // The song last drawn as playing, and the pending real-time check for it changing.
  private let m_lastTrack: CName;
  private let m_trackCheck: DelayID;
  private let m_checking: Bool;
  // The scroll bar beside the songs, and the game's slider that sizes, places and drags its handle.
  private let m_bar: wref<inkWidget>;
  private let m_slider: wref<inkSliderController>;
  // True while the panel moves the slider itself, so its change callback does not scroll the list back.
  private let m_drawingBar: Bool;

  // The cartridge picked: 1 All songs, then the shards; a station is m_stationBase + its place in m_stationList.
  private let m_source: Int32;
  private let m_stationBase: Int32 = 1000;
  // The strip lists the stations in place of the shards.
  private let m_stationsMode: Bool;
  // Every station but the shard slot, in dial order.
  private let m_stationList: array<CName>;
  private let m_hintPlay: wref<inkText>;
  private let m_hintEdit: wref<inkWidget>;
  private let m_hintEditText: wref<inkText>;
  private let m_hintClose: wref<inkText>;
  private let m_closeText: String;
  // The title bar names what the strip lists; the footer hint, what its key swaps to.
  private let m_title: wref<inkText>;
  private let m_hintMode: wref<inkText>;
  // The typed filter: the hub menus' filter box. A list shows only the songs whose title holds its text.
  private let m_filter: ref<HubTextInput>;
  private let m_filterText: String;
  // The frame the filter let the keyboard go: the key that did it reaches the popup's actions too, and
  // must not close the popup or play a song.
  private let m_releasedFrame: Uint64;
  // The songs listed, which source and station they were listed for, the first on screen and the cursor.
  private let m_songs: array<CName>;
  // The same list before the filter: a song in an in-order shard keeps its place number when filtered.
  private let m_unfiltered: array<CName>;
  private let m_listedFor: String;
  private let m_top: Int32;
  private let m_cursor: Int32;

  // The song just asked for, shown as playing until the radio reports a song: with the popup open on foot
  // game time runs slow, and RadioXL's own song events wait for it.
  private let m_requested: CName;
  // The cartridge that song was asked for from.
  private let m_requestedFrom: Int32;
  // The Library tuned the radio to the shard slot, so the popup's next station event selects that row.
  private let m_tuned: Bool;

  private let m_focused: Bool;
  private let m_pointer: Bool;
  // Where the cursor and the list stood before a burst of ups and downs, for the wheel to take back.
  private let m_undoCursor: Int32;
  private let m_undoTop: Int32;

  public func Build(owner: ref<inkGameController>) -> Void {
    let host = owner.GetRootCompoundWidget().GetWidget(n"containerRoot") as inkCompoundWidget;
    if !IsDefined(host) { return; }
    let root = owner.SpawnFromExternal(host, r"radioxl\\gui\\library_panel.inkwidget", n"panel") as inkCompoundWidget;
    if !IsDefined(root) { return; }
    root.SetAnchor(inkEAnchor.Centered);
    root.SetAnchorPoint(0.5, 0.5);
    // Shown in the popup's frame in place of the Radioport, when the switcher brings it forward.
    this.m_root = root;
    this.m_owner = owner;

    this.m_title = this.At("setup/top_holder/title") as inkText;
    this.m_hintMode = this.At("setup/content/inputHints/hintMode/text") as inkText;
    let slot = this.At("setup/content/filterSlot") as inkCompoundWidget;
    if IsDefined(slot) {
      this.m_filter = HubTextInput.Create();
      this.m_filter.SetName(n"filter");
      this.m_filter.SetDefaultText(RadioXLText("RadioXL.libFilter"));
      this.m_filter.SetWidth(slot.GetWidth());
      this.m_filter.Reparent(slot);
      this.m_filter.RegisterToCallback(n"OnInput", this, n"OnFilterInput");
      this.m_filter.RegisterToCallback(n"OnInputKey", this, n"OnFilterKey");
    }
    this.Clickable(this.At("setup/content/inputHints/hintMode"), this.m_actMode);
    this.m_hoverChip = -1;
    this.m_pointerChip = -1;
    this.m_chipRow = this.At("setup/content/chips");
    let i: Int32 = 0;
    while true {
      let chip: wref<inkWidget> = this.At(s"setup/content/chips/chip\(i)");
      if !IsDefined(chip) { break; }
      ArrayPush(this.m_chips, chip);
      ArrayPush(this.m_chipLabels, this.At(s"setup/content/chips/chip\(i)/frame/label") as inkText);
      ArrayPush(this.m_chipCounts, this.At(s"setup/content/chips/chip\(i)/frame/count") as inkText);
      ArrayPush(this.m_chipBars, this.At(s"setup/content/chips/chip\(i)/frame/bars"));
      ArrayPush(this.m_chipHovers, this.At(s"setup/content/chips/chip\(i)/frame/hoverFrames"));
      ArrayPush(this.m_chipIcons, this.At(s"setup/content/chips/chip\(i)/frame/icon") as inkImage);
      // The side strip is filled as on the hub menu's buttons; its own binding resolves to near black here.
      let strip: wref<inkWidget> = this.At(s"setup/content/chips/chip\(i)/frame/background_leftBg");
      if IsDefined(strip) {
        strip.BindProperty(n"tintColor", n"MainColors.Red");
        // As bright as the title bar's own accent above it.
        strip.SetOpacity(0.61);
      }
      this.Clickable(chip, this.m_actChip + i);
      i += 1;
    }
    this.m_position = this.At("setup/content/pager/controls/position") as inkText;
    this.Clickable(this.At("setup/content/pager/controls/keyPrev"), this.m_actPrev);
    this.Clickable(this.At("setup/content/pager/controls/keyNext"), this.m_actNext);
    this.m_caption = this.At("setup/content/caption") as inkText;
    this.m_bar = this.At("setup/content/box/scrollbar");
    let slider: wref<inkWidget> = this.At("setup/content/box/scrollbar/slider");
    this.m_slider = IsDefined(slider) ? slider.GetController() as inkSliderController : null;
    if IsDefined(this.m_slider) {
      this.m_slider.Setup(0.0, 1.0, 0.0, 0.0);
      this.m_slider.RegisterToCallback(n"OnSliderValueChanged", this, n"OnBarMoved");
    }
    i = 0;
    while true {
      let path: String = s"setup/content/box/list/row\(i)";
      let row: wref<inkWidget> = this.At(path);
      if !IsDefined(row) { break; }
      ArrayPush(this.m_rows, row);
      ArrayPush(this.m_rowLabels, this.At(path + "/flexLayout/label") as inkText);
      ArrayPush(this.m_rowBars, this.At(path + "/flexLayout/sizeProvider/Icon"));
      ArrayPush(this.m_rowIdle, this.At(path + "/flexLayout/Code_TL"));
      ArrayPush(this.m_rowBouncing, true);
      this.Clickable(row, this.m_actRow + i);
      i += 1;
    }
    this.m_hintPlay = this.At("setup/content/inputHints/hintPlay/text") as inkText;
    this.m_hintEdit = this.At("setup/content/inputHints/hintEdit");
    this.m_hintEditText = this.At("setup/content/inputHints/hintEdit/text") as inkText;
    this.m_hintClose = this.At("setup/content/inputHints/hintClose/text") as inkText;
    this.Clickable(this.m_hintEdit, this.m_actEdit);
    // Close reads as the Radioport's own hint does.
    let close = owner.GetRootCompoundWidget().GetWidgetByPathName(n"containerRoot/wrapper/setup/list/inputHints/inputClose/text") as inkText;
    this.m_closeText = IsDefined(close) && StrLen(close.GetText()) > 0 ? close.GetText() : RadioXLText("RadioXL.libClose");

    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/SongChanged", this, n"OnSongChanged");
    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/StationChanged", this, n"OnStationChanged");
    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/ShardSlotted", this, n"OnShards");
    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/ShardEjected", this, n"OnShards");
    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/ShardsChanged", this, n"OnShards");
    GameInstance.GetCallbackSystem().RegisterCallback(n"RadioXL/SongStateChanged", this, n"OnSongState");

    this.ListStations();
    this.m_source = this.DefaultSource();
    this.m_stationsMode = this.IsStation(this.m_source);
    this.SetPointer(false);
    this.Draw();
    root.SetVisible(false);
    let prepare = new RadioXLLibPrepare();
    prepare.panel = this;
    GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(prepare, 0.6, false);
    this.m_lastTrack = RadioXLAPI.CurrentTrack();
    this.m_checking = true;
    this.ScheduleTrackCheck();
  }

  public func Root() -> wref<inkWidget> {
    return this.m_root;
  }


  public func CheckTrack() -> Void {
    if !this.m_checking { return; }
    let track: CName = RadioXLAPI.CurrentTrack();
    if NotEquals(track, this.m_lastTrack) {
      this.m_lastTrack = track;
      this.m_requested = n"";
      this.m_listedFor = "";
      this.Draw();
    }
    this.ScheduleTrackCheck();
  }

  private func ScheduleTrackCheck() -> Void {
    let check = new RadioXLLibTrackCheck();
    check.panel = this;
    this.m_trackCheck = GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(check, 0.5, false);
  }

  public func Close() -> Void {
    if this.m_checking {
      this.m_checking = false;
      GameInstance.GetDelaySystem(GetGameInstance()).CancelCallback(this.m_trackCheck);
    }
    RadioXLEqAnim.Close(this.m_root);
    let cs = GameInstance.GetCallbackSystem();
    cs.UnregisterCallback(n"RadioXL/SongChanged", this);
    cs.UnregisterCallback(n"RadioXL/StationChanged", this);
    cs.UnregisterCallback(n"RadioXL/ShardSlotted", this);
    cs.UnregisterCallback(n"RadioXL/ShardEjected", this);
    cs.UnregisterCallback(n"RadioXL/ShardsChanged", this);
    cs.UnregisterCallback(n"RadioXL/SongStateChanged", this);
  }

  private cb func OnSongChanged(e: ref<RadioXLSongChangedEvent>) { this.Draw(); }
  private cb func OnStationChanged(e: ref<RadioXLStationChangedEvent>) {
    // The popup works out its selected row only as it opens; a station the Library tuned is selected here.
    let popup = this.m_owner as VehicleRadioPopupGameController;
    if IsDefined(popup) && this.TakeTuned() { popup.RadioXLSelectPlaying(); }
    this.Draw();
  }
  private cb func OnShards(e: ref<CallbackSystemEvent>) {
    ArrayClear(this.m_lists);
    this.m_listedFor = "";
    this.Draw();
    let popup = this.m_owner as VehicleRadioPopupGameController;
    if IsDefined(popup) { popup.RadioXLDrawShardRow(); }
  }

  // A song switched on or off while the popup is open: every list is made again.
  private cb func OnSongState(e: ref<CallbackSystemEvent>) {
    ArrayClear(this.m_lists);
    this.m_listedFor = "";
    this.Draw();
  }

  protected cb func OnFilterInput(widget: wref<inkWidget>) {
    this.m_filterText = StrLower(this.m_filter.GetText());
    this.m_listedFor = "";
    this.m_top = 0;
    this.m_cursor = 0;
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

  // True while the filter box has the keyboard: the popup's own keys stand down.
  public func Typing() -> Bool {
    if !this.Shown() || !IsDefined(this.m_filter) { return false; }
    return this.m_filter.IsFocused() || GameInstance.GetFrameNumber(GetGameInstance()) <= this.m_releasedFrame + 2ul;
  }

  public func Shown() -> Bool {
    return IsDefined(this.m_root) && this.m_root.IsVisible();
  }

  // The radio reported a song or a station change through the popup's own events, which arrive while the
  // popup slows game time.
  public func TakeTuned() -> Bool {
    let tuned: Bool = this.m_tuned;
    this.m_tuned = false;
    return tuned;
  }

  public func RadioReported(song: Bool) -> Void {
    if song { this.m_requested = n""; }
    this.m_listedFor = "";
    this.Draw();
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

  private func Clickable(widget: wref<inkWidget>, action: Int32) -> Void {
    if !IsDefined(widget) { return; }
    let click = new RadioXLLibClick();
    click.panel = this;
    click.action = action;
    ArrayPush(this.m_clicks, click);
    widget.SetInteractive(true);
    widget.RegisterToCallback(n"OnRelease", click, n"OnRelease");
    widget.RegisterToCallback(n"OnHoverOver", click, n"OnHoverOver");
    widget.RegisterToCallback(n"OnHoverOut", click, n"OnHoverOut");
  }

  // --- the cartridges ----------------------------------------------------------------------------

  private func Sources() -> Int32 {
    let shards = RadioXLShards.Get();
    if !IsDefined(shards) { return 2; }
    let names: array<String> = shards.Names();
    return 2 + ArraySize(names);
  }

  // The + NEW cartridge at the end of the shards. Negative, as no other cartridge is.
  private func NewShard() -> Int32 { return -3; }

  private func ListStations() -> Void {
    ArrayClear(this.m_stationList);
    let shard: CName = RadioXLAPI.ShardStation();
    let all: array<CName> = RadioXLAPI.Stations();
    for station in all {
      if NotEquals(station, shard) { ArrayPush(this.m_stationList, station); }
    }
  }

  private func IsStation(source: Int32) -> Bool {
    return source >= this.m_stationBase;
  }

  private func StationOf(source: Int32) -> CName {
    let i: Int32 = source - this.m_stationBase;
    return i >= 0 && i < ArraySize(this.m_stationList) ? this.m_stationList[i] : n"None";
  }

  private func SourceOf(station: CName) -> Int32 {
    let i: Int32 = ArrayFindFirst(this.m_stationList, station);
    return i >= 0 ? this.m_stationBase + i : -1;
  }

  // The shard a cartridge is: "" for All songs; a station cartridge is none.
  private func ShardOf(source: Int32) -> String {
    if source < 2 || this.IsStation(source) { return ""; }
    let names: array<String> = RadioXLShards.Get().Names();
    return source - 2 < ArraySize(names) ? names[source - 2] : "";
  }

  private func Label(source: Int32) -> String {
    if source == this.NewShard() { return RadioXLText("RadioXL.libNew"); }
    if this.IsStation(source) { return RadioXLAPI.StationName(this.StationOf(source)); }
    if source == 1 { return RadioXLText("RadioXL.libAll"); }
    return this.ShardOf(source);
  }

  private func OnSlot() -> Bool {
    return Equals(RadioXLAPI.CurrentStation(), RadioXLAPI.ShardStation());
  }

  // The cartridge that is playing: the slotted shard while the radio is on the shard slot, else the station's;
  // -1 with the radio off.
  private func PlayingSource() -> Int32 {
    if !this.OnSlot() {
      let station: CName = RadioXLAPI.CurrentStation();
      return Equals(station, n"None") ? -1 : this.SourceOf(station);
    }
    let slotted: String = RadioXLAPI.SlottedShard();
    if StrLen(slotted) == 0 { return 1; }
    let names: array<String> = RadioXLShards.Get().Names();
    let i: Int32 = ArrayFindFirst(names, slotted);
    return i >= 0 ? i + 2 : 1;
  }

  private func DefaultSource() -> Int32 {
    let playing: Int32 = this.PlayingSource();
    return playing >= 0 ? playing : 1;
  }

  // The cartridges offered, round in a ring: All songs and the shards, or every station.
  private func Ring() -> array<Int32> {
    let out: array<Int32>;
    let i: Int32 = 0;
    if this.m_stationsMode {
      while i < ArraySize(this.m_stationList) {
        ArrayPush(out, this.m_stationBase + i);
        i += 1;
      }
      return out;
    }
    let n: Int32 = this.Sources();
    i = 1;
    while i < n {
      ArrayPush(out, i);
      i += 1;
    }
    ArrayPush(out, this.NewShard());
    return out;
  }

  // The cartridge `dir` along the ring from `source`.
  private func Along(source: Int32, dir: Int32) -> Int32 {
    let ring: array<Int32> = this.Ring();
    let count: Int32 = ArraySize(ring);
    if count == 0 { return source; }
    let at: Int32 = Max(ArrayFindFirst(ring, source), 0);
    return ring[((at + dir) % count + count) % count];
  }

  // The cartridge is picked; `dir` is how far along the ring it was, so the strip slides the way they move.
  private func Pick(source: Int32, dir: Int32) -> Void {
    let next: Int32 = source;
    // Array built-ins see a function's returned array as empty; it is held in a local first.
    let ring: array<Int32> = this.Ring();
    if next == this.m_source || !ArrayContains(ring, next) { return; }
    this.m_source = next;
    this.m_top = 0;
    this.m_cursor = 0;
    if IsDefined(this.m_owner) { this.m_owner.PlaySound(n"Holocall", n"Navigation"); }
    this.Draw();
    this.SlideChips(dir);
  }

  private func SlideChips(dir: Int32, opt duration: Float) -> ref<inkAnimProxy> {
    if dir == 0 || !IsDefined(this.m_chipRow) || ArraySize(this.m_chips) < 2 { return null; }
    if duration <= 0.0 { duration = 0.18; }
    let step: Float = this.m_chips[1].GetWidth() + 12.0;
    let slide = new inkAnimTranslation();
    slide.SetStartTranslation(new Vector2(Cast<Float>(dir) * step, 0.0));
    slide.SetEndTranslation(new Vector2(0.0, 0.0));
    slide.SetDuration(duration);
    slide.SetType(inkanimInterpolationType.Sinusoidal);
    slide.SetMode(inkanimInterpolationMode.EasyInOut);
    let def = new inkAnimDef();
    def.AddInterpolator(slide);
    this.m_chipRow.SetTranslation(new Vector2(Cast<Float>(dir) * step, 0.0));
    return this.m_chipRow.PlayAnimation(def);
  }

  // --- the songs ---------------------------------------------------------------------------------

  // The songs a cartridge lists. A station's songs and All songs are by title; a shard lists its own order.
  private func ListFor(source: Int32) -> array<CName> {
    let out: array<CName>;
    if source < 1 { return out; }
    if this.IsStation(source) {
      let tracks: array<CName> = RadioXLAPI.Tracks(this.StationOf(source));
      return this.ByTitle(tracks, true);
    }
    let songs: array<CName> = RadioXLAPI.ShardSongs(this.ShardOf(source));
    if source == 1 { return this.ByTitle(songs, false); }
    for song in songs {
      if RadioXLAPI.IsSongPlayable(song) { ArrayPush(out, song); }
    }
    return out;
  }

  private func ByTitle(tracks: array<CName>, playableOnly: Bool) -> array<CName> {
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

  // Listed again only when the cartridge or the station changes; a song change only moves the bars.
  private func Refresh() -> Void {
    let key: String = s"\(this.m_source)|\(RadioXLAPI.CurrentStation())";
    if Equals(key + "|" + this.m_filterText, this.m_listedFor) { return; }
    this.m_listedFor = key + "|" + this.m_filterText;
    this.m_unfiltered = this.Listed(this.m_source, key);
    this.m_songs = this.Filtered(this.m_unfiltered);
    this.m_cursor = Clamp(this.m_cursor, 0, Max(ArraySize(this.m_songs) - 1, 0));
    this.m_top = Clamp(this.m_top, 0, Max(ArraySize(this.m_songs) - ArraySize(this.m_rows), 0));
  }

  private func Filtered(songs: array<CName>) -> array<CName> {
    if StrLen(this.m_filterText) == 0 { return songs; }
    let out: array<CName>;
    for song in songs {
      if StrFindFirst(StrLower(RadioXLAPI.TrackTitle(song)), this.m_filterText) >= 0 { ArrayPush(out, song); }
    }
    return out;
  }

  private func Listed(source: Int32, key: String) -> array<CName> {
    for list in this.m_lists {
      if Equals(list.key, key) { return list.songs; }
    }
    let list = new RadioXLSongList();
    list.key = key;
    list.songs = this.ListFor(source);
    ArrayPush(this.m_lists, list);
    return list.songs;
  }

  public func Prepare() -> Void {
    this.Listed(1, s"1|\(RadioXLAPI.CurrentStation())");
  }

  private func Step(step: Int32) -> Void {
    let n: Int32 = ArraySize(this.m_songs);
    if n == 0 { return; }
    let was: Int32 = this.m_cursor;
    this.m_cursor = Clamp(this.m_cursor + step, 0, n - 1);
    this.KeepCursorShown();
    if was != this.m_cursor && IsDefined(this.m_owner) { this.m_owner.PlaySound(n"Holocall", n"Navigation"); }
    this.Draw();
    this.MoveCursor();
  }

  private func KeepCursorShown() -> Void {
    let rows: Int32 = ArraySize(this.m_rows);
    if this.m_cursor < this.m_top { this.m_top = this.m_cursor; }
    if this.m_cursor >= this.m_top + rows { this.m_top = this.m_cursor - rows + 1; }
  }

  // The wheel moves the list a row at a time; the cursor stays on its song while it is on screen.
  public func Scroll(up: Bool) -> Void {
    let most: Int32 = Max(ArraySize(this.m_songs) - ArraySize(this.m_rows), 0);
    this.m_top = Clamp(this.m_top + (up ? -1 : 1), 0, most);
    this.Draw();
  }

  private func Play(index: Int32) -> Void {
    if index < 0 || index >= ArraySize(this.m_songs) { return; }
    this.m_cursor = index;
    let song: CName = this.m_songs[index];
    let source: Int32 = this.m_source;
    if this.IsStation(source) {
      let station: CName = this.StationOf(source);
      if NotEquals(station, RadioXLAPI.CurrentStation()) {
        this.m_tuned = true;
        if !this.m_animating {
          this.m_animating = true;
          this.m_playSource = -1;
          this.Seat(0.3);
        }
        RadioXLAPI.TuneStation(station);
      }
      RadioXLAPI.PlaySong(station, song);
    } else {
      this.m_tuned = !this.OnSlot();
      if (!Equals(RadioXLAPI.SlottedShard(), this.ShardOf(source)) || !this.OnSlot()) && !this.m_animating {
        this.m_animating = true;
        this.m_playSource = -1;
        this.Seat(0.3);
      }
      RadioXLShards.Get().Slot(this.ShardOf(source), song);
    }
    this.m_requested = song;
    this.m_requestedFrom = source;
    this.Draw();
  }

  // A cartridge played with E: a shard is slotted, All songs puts the slot back on every song, and the
  // station cartridge plays the station it lists.
  private func PlaySource(source: Int32, dir: Int32) -> Void {
    if source == this.NewShard() {
      this.CreateShard();
      return;
    }
    // The pointer's cartridge is about to change under it; the frame waits for it to move again.
    this.m_hoverChip = -1;
    if this.m_animating { return; }
    this.m_animating = true;
    this.m_playSource = source;
    this.m_playDir = dir;
    if source == this.m_source || dir == 0 {
      this.Seat(0.3);
    } else {
      this.PressAside(dir);
    }
  }

  // The cartridge goes into the slot as it seats: writing the slot costs a frame or two, which is not felt
  // once nothing is moving.
  private func SlotSource(source: Int32) -> Void {
    if source < 1 { return; }
    if this.IsStation(source) {
      let station: CName = this.StationOf(source);
      if NotEquals(station, RadioXLAPI.CurrentStation()) {
        this.m_tuned = true;
        RadioXLAPI.TuneStation(station);
      }
      this.Draw();
      return;
    }
    this.m_tuned = !this.OnSlot();
    if source == 1 {
      if this.OnSlot() { RadioXLShards.Get().Eject(); } else { RadioXLShards.Get().Slot(""); }
    } else {
      RadioXLShards.Get().Slot(this.ShardOf(source));
    }
    this.Draw();
  }

  private func Ease(def: ref<inkAnimDef>, from: Vector2, to: Vector2, duration: Float, mode: inkanimInterpolationMode) -> Void {
    let scale = new inkAnimScale();
    scale.SetStartScale(from);
    scale.SetEndScale(to);
    scale.SetDuration(duration);
    scale.SetType(inkanimInterpolationType.Sinusoidal);
    scale.SetMode(mode);
    def.AddInterpolator(scale);
  }

  private func Fade(def: ref<inkAnimDef>, from: Float, to: Float, duration: Float, mode: inkanimInterpolationMode) -> Void {
    let fade = new inkAnimTransparency();
    fade.SetStartTransparency(from);
    fade.SetEndTransparency(to);
    fade.SetDuration(duration);
    fade.SetType(inkanimInterpolationType.Sinusoidal);
    fade.SetMode(mode);
    def.AddInterpolator(fade);
  }

  // Step 1: the cartridge played presses in where it is, and the one about to leave fades.
  private func PressAside(dir: Int32) -> Void {
    let pressed: wref<inkWidget> = this.m_chips[1 + dir];
    let leaving: wref<inkWidget> = this.m_chips[1 - dir];
    if IsDefined(leaving) {
      let out = new inkAnimDef();
      this.Fade(out, leaving.GetOpacity(), 0.0, 0.12, inkanimInterpolationMode.EasyIn);
      leaving.PlayAnimation(out);
    }
    // The middle one steps back to a side cartridge's look, so nothing jumps when the strip changes.
    let middle: wref<inkWidget> = this.m_chips[1];
    if IsDefined(middle) {
      let back = new inkAnimDef();
      this.Fade(back, middle.GetOpacity(), 0.6, 0.12, inkanimInterpolationMode.EasyInOut);
      middle.PlayAnimation(back);
    }
    let frame: wref<inkWidget> = this.m_chipHovers[1];
    if IsDefined(frame) && frame.IsVisible() {
      let dim = new inkAnimDef();
      this.Fade(dim, frame.GetOpacity(), 0.3, 0.12, inkanimInterpolationMode.EasyInOut);
      frame.PlayAnimation(dim);
    }
    if !IsDefined(pressed) {
      this.OnPressed(null);
      return;
    }
    pressed.SetRenderTransformPivot(0.5, 0.5);
    let press = new inkAnimDef();
    this.Ease(press, new Vector2(1.0, 1.0), new Vector2(0.95, 0.9), 0.12, inkanimInterpolationMode.EasyInOut);
    let proxy = pressed.PlayAnimation(press);
    proxy.RegisterToCallback(inkanimEventType.OnFinish, this, n"OnPressed");
  }

  // Step 2: the strip slides it to the middle, letting it out as it goes; the new one fades in at the far side.
  protected cb func OnPressed(proxy: ref<inkAnimProxy>) -> Bool {
    let dir: Int32 = this.m_playDir;
    let i: Int32 = 0;
    while i < ArraySize(this.m_chips) {
      this.m_chips[i].SetScale(new Vector2(1.0, 1.0));
      this.m_chips[i].SetOpacity(i == 1 ? 1.0 : 0.6);
      i += 1;
    }
    this.Pick(this.m_playSource, dir);
    let middle: wref<inkWidget> = this.m_chips[1];
    middle.SetRenderTransformPivot(0.5, 0.5);
    middle.SetScale(new Vector2(0.95, 0.9));
    // It comes forward as it travels: out of the press, and from a side cartridge's look to the middle's.
    middle.SetOpacity(0.6);
    let release = new inkAnimDef();
    this.Ease(release, new Vector2(0.95, 0.9), new Vector2(1.0, 1.0), 0.26, inkanimInterpolationMode.EasyOut);
    this.Fade(release, 0.6, 1.0, 0.26, inkanimInterpolationMode.EasyOut);
    middle.PlayAnimation(release);
    let incoming: wref<inkWidget> = this.m_chips[1 + dir];
    if IsDefined(incoming) {
      incoming.SetOpacity(0.0);
      let fadeIn = new inkAnimDef();
      this.Fade(fadeIn, 0.0, 0.6, 0.26, inkanimInterpolationMode.EasyOut);
      incoming.PlayAnimation(fadeIn);
    }
    this.SlideChips(dir, 0.26);
    // It lights as it travels and is full when it stops.
    this.Seat(0.4);
    return true;
  }

  // Step 3: it seats: its frame lights from dim to full; then it plays, and the bars show with the redraw.
  private func Seat(duration: Float) -> Void {
    let frame: wref<inkWidget> = this.m_chipHovers[1];
    if !IsDefined(frame) {
      this.OnSeated(null);
      return;
    }
    frame.SetVisible(true);
    let glow = new inkAnimDef();
    frame.SetOpacity(0.3);
    this.Fade(glow, 0.3, 1.0, duration, inkanimInterpolationMode.EasyOut);
    let proxy = frame.PlayAnimation(glow);
    proxy.RegisterToCallback(inkanimEventType.OnFinish, this, n"OnSeated");
    if IsDefined(this.m_owner) { this.m_owner.PlaySound(n"Holocall", n"Navigation"); }
  }

  protected cb func OnSeated(proxy: ref<inkAnimProxy>) -> Bool {
    this.m_animating = false;
    if this.m_playSource >= 0 {
      let source: Int32 = this.m_playSource;
      this.m_playSource = -1;
      this.SlotSource(source);
    }
    this.Draw();
    return true;
  }




  // --- input -------------------------------------------------------------------------------------

  private func Now() -> Float {
    return EngineTime.ToFloat(GameInstance.GetEngineTime(GetGameInstance()));
  }

  // A mouse click. Proceed (E, F, pad A) also makes one on whatever the pointer rests on; Act has already
  // acted on that press, so its click is dropped.
  public func Click(action: Int32) -> Void {
    // A click while the box has the keyboard, or the click Enter makes on whatever the pointer rests on,
    // only gives the keyboard back.
    if this.Typing() {
      GameInstance.GetInkSystem().ResetFocus();
      return;
    }
    if this.Now() - this.m_proceedAt < 0.5 {
      this.m_proceedAt = 0.0;
      return;
    }
    if action >= this.m_actRow {
      this.Play(this.m_top + action - this.m_actRow);
    } else if action == this.m_actMode {
      this.SwapMode();
    } else if action == this.m_actEdit {
      this.EditKey();
    } else if action == this.m_actPrev || action == this.m_actNext {
      let dir: Int32 = action == this.m_actNext ? 1 : -1;
      this.Pick(this.Along(this.m_source, dir), dir);
    } else if action >= this.m_actChip && action < this.m_actChip + ArraySize(this.m_chips) {
      // A click brings a cartridge to the middle; E over one plays it. A click on + NEW makes a shard.
      let slot: Int32 = action - this.m_actChip;
      let source: Int32 = this.Along(this.m_source, slot - 1);
      if source == this.NewShard() {
        this.CreateShard();
      } else if slot != 1 {
        this.Pick(source, slot - 1);
      }
    }
  }

  // The pointer over a row puts the cursor there, over a cartridge picks that cartridge's frame; over any part
  // of the panel it takes the focus.
  public func Hovered(action: Int32) -> Void {
    if !this.m_pointer { return; }
    if action >= this.m_actChip && action < this.m_actChip + ArraySize(this.m_chips) {
      this.m_hoverChip = action - this.m_actChip;
      this.m_pointerChip = this.m_hoverChip;
    }
    if action >= this.m_actRow {
      let index: Int32 = this.m_top + (action - this.m_actRow) % 100;
      if index < ArraySize(this.m_songs) { this.m_cursor = index; }
    }
    this.Focus(true, false);
  }

  public func Unhovered(action: Int32) -> Void {
    if action - this.m_actChip == this.m_pointerChip { this.m_pointerChip = -1; }
    if action - this.m_actChip == this.m_hoverChip {
      this.m_hoverChip = -1;
      this.Draw();
    }
  }

  public func SetPointer(on: Bool) -> Void {
    this.m_pointer = on;
    if !on {
      this.m_hoverChip = -1;
      this.m_pointerChip = -1;
    }
  }

  public func IsFocused() -> Bool {
    return this.m_focused;
  }

  // The focus comes to the panel or leaves it; with `move`, the cursor goes with it.
  public func Focus(on: Bool, move: Bool) -> Void {
    this.m_focused = on;
    this.Draw();
    if on && move { this.MoveCursor(); }
  }

  public func Blur() -> Void {
    if this.m_focused { this.Focus(false, false); }
  }

  public func Snapshot() -> Void {
    this.m_undoCursor = this.m_cursor;
    this.m_undoTop = this.m_top;
  }

  public func Restore() -> Void {
    this.m_cursor = this.m_undoCursor;
    this.m_top = this.m_undoTop;
    this.Draw();
  }

  public func MoveCursorNow() -> Void {
    if this.m_focused { this.MoveCursor(); }
  }

  // Opens on what is playing: the cartridge that plays it, scrolled to the song, the cursor on it.
  public func ShowPlaying() -> Void {
    this.m_source = this.DefaultSource();
    this.m_stationsMode = this.IsStation(this.m_source);
    this.ToPlayingSong();
    this.Draw();
  }

  // The list shows from its start, or around the song playing when it is in it.
  private func ToPlayingSong() -> Void {
    this.m_top = 0;
    this.m_cursor = 0;
    this.m_listedFor = "";
    this.Refresh();
    let track: CName = this.ShownTrack();
    let at: Int32 = ArrayFindFirst(this.m_songs, track);
    if at >= 0 {
      this.m_cursor = at;
      this.m_top = Clamp(at - ArraySize(this.m_rows) / 2, 0, Max(ArraySize(this.m_songs) - ArraySize(this.m_rows), 0));
    }
  }

  // The strip changes between the shards and the stations, on the cartridge playing when it has one.
  private func SwapMode() -> Void {
    if this.m_animating { return; }
    this.m_stationsMode = !this.m_stationsMode;
    if this.m_stationsMode { this.ListStations(); }
    let playing: Int32 = this.PlayingSource();
    let ring: array<Int32> = this.Ring();
    this.m_source = ArrayContains(ring, playing) ? playing : (ArraySize(ring) > 0 ? ring[0] : 1);
    this.m_hoverChip = -1;
    this.ToPlayingSong();
    if IsDefined(this.m_owner) { this.m_owner.PlaySound(n"Holocall", n"Navigation"); }
    this.Draw();
    this.MoveCursor();
    if IsDefined(this.m_chipRow) {
      let show = new inkAnimDef();
      this.Fade(show, 0.0, 1.0, 0.2, inkanimInterpolationMode.EasyOut);
      this.m_chipRow.SetOpacity(0.0);
      this.m_chipRow.PlayAnimation(show);
    }
  }

  // The pad steers the game's cursor, so it follows the selection; keys leave the mouse cursor where it is.
  private func MoveCursor() -> Void {
    if this.m_pointer || !IsDefined(this.m_owner) || !this.m_owner.GetPlayerControlledObject().PlayerLastUsedPad() { return; }
    let row: Int32 = this.m_cursor - this.m_top;
    let target: wref<inkWidget> = row >= 0 && row < ArraySize(this.m_rows) ? this.m_rows[row] : null;
    if !IsDefined(target) && ArraySize(this.m_chips) > 1 { target = this.m_chips[1]; }
    if IsDefined(target) && IsDefined(this.m_owner) { this.m_owner.SetCursorOverWidget(target, 0.0, true); }
  }

  // An action the popup heard; true when the panel took it. Up and down move through the songs, the
  // volume keys step the cartridges, proceed plays.
  public func Act(name: CName, type: gameinputActionType) -> Bool {
    if !this.Shown() { return false; }
    // The swap answers wherever the focus is, as its key is always shown.
    if Equals(name, n"showAll") {
      if Equals(type, gameinputActionType.BUTTON_RELEASED) { this.SwapMode(); }
      return true;
    }
    if Equals(name, n"secondaryAction") {
      if Equals(type, gameinputActionType.BUTTON_PRESSED) { this.EditKey(); }
      return true;
    }
    if !this.m_focused { return false; }
    let press: Bool = Equals(type, gameinputActionType.BUTTON_PRESSED);
    let step: Bool = press || Equals(type, gameinputActionType.REPEAT);
    switch name {
      case n"popup_moveUp":
        if step { this.Step(-1); }
        return true;
      case n"popup_moveDown":
        if step { this.Step(1); }
        return true;
      case n"radio_volume_down":
        if step { this.Pick(this.Along(this.m_source, -1), -1); }
        return true;
      case n"radio_volume_up":
        if step { this.Pick(this.Along(this.m_source, 1), 1); }
        return true;
      case n"proceed":
        // The station list acts on both the press and the release; neither may reach it. With the mouse in
        // charge the press is the click's alone.
        if press {
          this.m_proceedAt = this.Now();
          if this.m_pointer && this.m_pointerChip >= 0 {
            // E over a cartridge plays it.
            this.PlaySource(this.Along(this.m_source, this.m_pointerChip - 1), this.m_pointerChip - 1);
          } else if this.m_source == this.NewShard() {
            this.CreateShard();
          } else {
            // The pointer over a song puts the cursor on it, so this is the song under it too.
            this.Play(this.m_cursor);
          }
        }
        return true;
    }
    return false;
  }

  // --- the shard builder -------------------------------------------------------------------------

  // R: on a shard, the builder opens on it; on + NEW, on a new one.
  private func EditKey() -> Void {
    if this.m_stationsMode { return; }
    if this.m_source == this.NewShard() {
      this.CreateShard();
    } else if this.m_source >= 2 {
      let popup = this.m_owner as VehicleRadioPopupGameController;
      if IsDefined(popup) { popup.RadioXLOpenBuilder(this.ShardOf(this.m_source)); }
    }
  }

  // + NEW: a shard named "Shard <n>" with no songs, opened in the builder.
  private func CreateShard() -> Void {
    let shards = RadioXLShards.Get();
    let popup = this.m_owner as VehicleRadioPopupGameController;
    if !IsDefined(shards) || !IsDefined(popup) || this.m_animating { return; }
    let name: String = RadioXLShardBuilder.FreeName(shards.Names());
    let none: array<CName>;
    if !shards.Save(name, none, false) { return; }
    popup.RadioXLOpenBuilder(name);
  }

  // Back from the builder: the strip on the shard just built, or on All songs when it was deleted.
  public func ShowShard(name: String) -> Void {
    ArrayClear(this.m_lists);
    let names: array<String> = RadioXLShards.Get().Names();
    let at: Int32 = ArrayFindFirst(names, name);
    this.m_stationsMode = false;
    this.m_source = at >= 0 ? at + 2 : 1;
    this.m_top = 0;
    this.m_cursor = 0;
    this.m_listedFor = "";
    this.Draw();
    this.Focus(true, true);
  }

  // The title bar names what the strip lists; the footer, what the keys do on the cartridge picked.
  private func DrawHints() -> Void {
    this.SetText(this.m_title, RadioXLText(this.m_stationsMode ? "RadioXL.libStations" : "RadioXL.libShards"));
    if IsDefined(this.m_title) { this.m_title.BindProperty(n"tintColor", n"MainColors.Blue"); }
    this.SetText(this.m_hintMode, RadioXLText(this.m_stationsMode ? "RadioXL.libShards" : "RadioXL.libStations"));
    this.SetText(this.m_hintPlay, RadioXLText(this.m_source == this.NewShard() ? "RadioXL.libCreate" : "RadioXL.songsPlay"));
    this.SetText(this.m_hintClose, this.m_closeText);
    // + NEW makes a shard with E as well; its R would only say the same again.
    if IsDefined(this.m_hintEdit) { this.m_hintEdit.SetVisible(!this.m_stationsMode && this.m_source >= 2); }
    this.SetText(this.m_hintEditText, RadioXLText("RadioXL.libEdit"));
  }

  // --- drawing -----------------------------------------------------------------------------------

  public func Draw() -> Void {
    if !IsDefined(this.m_root) { return; }
    let ring: array<Int32> = this.Ring();
    let n: Int32 = ArraySize(ring);
    if n == 0 { return; }
    if !ArrayContains(ring, this.m_source) {
      this.m_source = ArrayContains(ring, this.PlayingSource()) ? this.PlayingSource() : ring[0];
    }
    let playing: Int32 = this.PlayingSource();
    let i: Int32 = 0;
    while i < ArraySize(this.m_chips) {
      let source: Int32 = this.Along(this.m_source, i - 1);
      let chip: wref<inkWidget> = this.m_chips[i];
      if IsDefined(chip) {
        // Two cartridges show the middle and the right; one shows the middle alone.
        let shown: Bool = n > 2 || (n == 2 && i > 0) || i == 1;
        chip.SetVisible(shown);
        if !this.m_animating {
          let picked: Bool = this.m_hoverChip >= 0 ? i == this.m_hoverChip : i == 1;
          chip.SetOpacity(picked || i == 1 ? 1.0 : 0.6);
          if IsDefined(this.m_chipHovers[i]) { this.m_chipHovers[i].SetVisible(picked); }
        }
        if shown {
          this.DrawChipIcon(i, source);
          this.SetText(this.m_chipLabels[i], this.Label(source));
          this.Stopped(this.m_chipLabels[i], source != this.m_source);
          let count: Int32 = this.CountOf(source);
          this.SetText(this.m_chipCounts[i], count < 0 ? "" : StrReplace(RadioXLText("RadioXL.libCount"), "{n}", IntToString(count)));
          let isPlaying: Bool = source == playing;
          if IsDefined(this.m_chipBars[i]) { this.m_chipBars[i].SetVisible(isPlaying); }
        }
      }
      i += 1;
    }
    if IsDefined(this.m_position) {
      let text: String = StrReplace(RadioXLText("RadioXL.libPosition"), "{i}", IntToString(ArrayFindFirst(ring, this.m_source) + 1));
      this.m_position.SetText(StrReplace(text, "{n}", IntToString(n)));
    }

    this.Refresh();
    let caption: String = this.Label(this.m_source);
    if !this.IsStation(this.m_source) && RadioXLAPI.IsShardInOrder(this.ShardOf(this.m_source)) {
      caption += " · " + RadioXLText("RadioXL.libInOrder");
    }
    if StrLen(this.m_filterText) > 0 && ArraySize(this.m_songs) == 0 { caption += " · " + RadioXLText("RadioXL.libNoMatch"); }
    this.SetText(this.m_caption, caption);
    this.DrawHints();

    let track: CName = this.ShownTrack();
    let ordered: Bool = this.m_source >= 2 && !this.IsStation(this.m_source) && RadioXLAPI.IsShardInOrder(this.ShardOf(this.m_source));
    let count: Int32 = ArraySize(this.m_songs);
    i = 0;
    while i < ArraySize(this.m_rows) {
      let index: Int32 = this.m_top + i;
      let row: wref<inkWidget> = this.m_rows[i];
      if IsDefined(row) {
        row.SetVisible(index < count);
        if index < count {
          let title: String = RadioXLAPI.TrackTitle(this.m_songs[index]);
          let isPlaying: Bool = Equals(this.m_songs[index], track);
          let place: Int32 = ArrayFindFirst(this.m_unfiltered, this.m_songs[index]) + 1;
          this.SetText(this.m_rowLabels[i], ordered ? s"\(place)  " + title : title);
          this.Bounce(i, index == this.m_cursor || isPlaying);
          if IsDefined(this.m_rowBars[i]) { this.m_rowBars[i].SetVisible(isPlaying); }
          if IsDefined(this.m_rowIdle[i]) { this.m_rowIdle[i].SetVisible(!isPlaying); }
          row.SetState(this.m_focused && index == this.m_cursor ? n"Active" : n"Default");
        }
      }
      i += 1;
    }
    this.DrawBar(count);
  }

  // The song shown as playing in the list: only in the list of the cartridge it plays from, so a song on a
  // station is not shown playing in All songs.
  private func ShownTrack() -> CName {
    if IsNameValid(this.m_requested) {
      return this.m_requestedFrom == this.m_source ? this.m_requested : n"";
    }
    return this.m_source == this.PlayingSource() ? RadioXLAPI.CurrentTrack() : n"";
  }

  private func Bounce(row: Int32, on: Bool) -> Void {
    if Equals(on, this.m_rowBouncing[row]) { return; }
    this.m_rowBouncing[row] = on;
    this.Stopped(this.m_rowLabels[row], !on);
  }

  // A long text scrolls, or stands still at its start, clipped as a scrolling one is.
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
  private func DrawBar(count: Int32) -> Void {
    if !IsDefined(this.m_bar) { return; }
    let rows: Int32 = ArraySize(this.m_rows);
    this.m_bar.SetVisible(count > rows);
    if count <= rows || !IsDefined(this.m_slider) { return; }
    this.m_drawingBar = true;
    this.m_slider.SetPercentageHandleSize(Cast<Float>(rows) / Cast<Float>(count));
    this.m_slider.ChangeProgress(Cast<Float>(this.m_top) / Cast<Float>(count - rows));
    this.m_drawingBar = false;
  }

  // The handle dragged: the list follows it.
  protected cb func OnBarMoved(slider: wref<inkSliderController>, progress: Float, value: Float) -> Bool {
    if this.m_drawingBar { return false; }
    let most: Int32 = Max(ArraySize(this.m_songs) - ArraySize(this.m_rows), 0);
    let top: Int32 = Clamp(RoundF(progress * Cast<Float>(most)), 0, most);
    if top != this.m_top {
      this.m_top = top;
      this.Draw();
    }
    return false;
  }

  // A shard shows the shard; the station shows its own logo, which is wider.
  private func DrawChipIcon(i: Int32, source: Int32) -> Void {
    let icon: wref<inkImage> = this.m_chipIcons[i];
    if !IsDefined(icon) { return; }
    let stationIcon: TweakDBID = this.IsStation(source) ? RadioXLAPI.StationIcon(this.StationOf(source)) : TDBID.None();
    if TDBID.IsValid(stationIcon) {
      // A logo keeps its own shape: the image takes its atlas part's size and is scaled into the box once
      // it has loaded, in FitIcon.
      icon.SetFitToContent(true);
      icon.SetRenderTransformPivot(0.0, 0.5);
      this.TextAfterIcon(i, 110.0);
      InkImageUtils.RequestSetImage(this.m_owner, icon, stationIcon);
      this.StartFitting();
    } else {
      icon.SetFitToContent(false);
      icon.SetScale(new Vector2(1.0, 1.0));
      icon.SetSize(new Vector2(66.0, 60.0));
      this.TextAfterIcon(i, 66.0);
      // Through the same request as the logo, so a logo still loading cannot land over the shard.
      InkImageUtils.RequestSetImage(this.m_owner, icon, TDBID.Create(RadioXLDial.IconName(RadioXL_ShardSlot())));
    }
  }

  // A logo loads a frame or more after it is asked for, and its size is known only then. Each pass scales
  // every logo on the strip to fit the logo box whole, with the name after it; passes run for half a
  // second of real time after a logo is asked for.
  private func StartFitting() -> Void {
    if this.m_fitting { return; }
    this.m_fitting = true;
    this.FitIcons(0);
  }

  public func FitIcons(tries: Int32) -> Void {
    let i: Int32 = 0;
    while i < ArraySize(this.m_chipIcons) {
      let icon: wref<inkImage> = this.m_chipIcons[i];
      if IsDefined(icon) && icon.GetFitToContent() {
        let native: Vector2 = icon.GetDesiredSize();
        if native.X > 0.0 && native.Y > 0.0 {
          let scale: Float = MinF(110.0 / native.X, 60.0 / native.Y);
          icon.SetScale(new Vector2(scale, scale));
          this.TextAfterIcon(i, native.X * scale);
        }
      }
      i += 1;
    }
    if tries >= 10 {
      this.m_fitting = false;
    } else {
      let again = new RadioXLLibFitIcons();
      again.panel = this;
      again.tries = tries + 1;
      GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(again, 0.05, false);
    }
  }

  // The name and count start after the icon, whichever it is.
  private func TextAfterIcon(i: Int32, iconWidth: Float) -> Void {
    let left: Float = 16.0 + iconWidth + 12.0;
    let label: wref<inkText> = this.m_chipLabels[i];
    if IsDefined(label) {
      let m: inkMargin = label.GetMargin();
      m.left = left;
      label.SetMargin(m);
      label.SetWidth(this.m_chips[i].GetWidth() - 16.0 - left - 16.0);
    }
    let count: wref<inkText> = this.m_chipCounts[i];
    if IsDefined(count) {
      let m: inkMargin = count.GetMargin();
      m.left = left;
      count.SetMargin(m);
    }
  }


  // As many as the cartridge lists: a song switched off is neither listed nor counted.
  private func CountOf(source: Int32) -> Int32 {
    if source == this.NewShard() { return -1; }
    // All songs holds only songs that can play, and counting it here does not sort its titles while the
    // popup opens.
    if source == 1 {
      let all: array<CName> = RadioXLAPI.ShardSongs("");
      return ArraySize(all);
    }
    let songs: array<CName> = this.Listed(source, s"\(source)|\(RadioXLAPI.CurrentStation())");
    return ArraySize(songs);
  }

}

// --- the popup ----------------------------------------------------------------------------------

@addField(VehicleRadioPopupGameController)
private let m_radioXLLibrary: ref<RadioXLLibraryPanel>;

@wrapMethod(VehicleRadioPopupGameController)
protected cb func OnPlayerAttach(playerPuppet: ref<GameObject>) -> Bool {
  let result: Bool = wrappedMethod(playerPuppet);
  let library = new RadioXLLibraryPanel();
  library.Build(this);
  library.SetPointer(this.m_radioXLPointer);
  this.m_radioXLLibrary = library;
  this.GetPlayerControlledObject().RegisterInputListener(this, n"prior_menu");
  this.GetPlayerControlledObject().RegisterInputListener(this, n"next_menu");
  this.GetPlayerControlledObject().RegisterInputListener(this, n"mouse_wheel");
  this.GetPlayerControlledObject().RegisterInputListener(this, n"secondaryAction");
  this.GetPlayerControlledObject().RegisterInputListener(this, n"call");
  this.GetPlayerControlledObject().RegisterInputListener(this, n"left_trigger");
  this.GetPlayerControlledObject().RegisterInputListener(this, n"right_trigger");
  this.RadioXLSwitcherSetup();
  return result;
}

// Selects the row of the station that is playing, by dial position, and moves the playing bars to it, as the
// popup does for itself as it opens.
@addMethod(VehicleRadioPopupGameController)
public func RadioXLSelectPlaying() -> Void {
  let deck = RadioXLDeck.Get();
  if !IsDefined(deck) || !IsDefined(this.m_listController) || !IsDefined(this.m_dataSource) { return; }
  let r = deck.Receiver(this.GetPlayerControlledObject().GetGame());
  if r.stationIndex < 0 { return; }
  let position: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(r.stationIndex);
  let n: Int32 = Cast<Int32>(this.m_dataSource.GetArraySize());
  let i: Int32 = 0;
  while i < n {
    let data = this.m_dataSource.GetItem(Cast<Uint32>(i)) as RadioListItemData;
    if IsDefined(data) && IsDefined(data.m_record) && data.m_record.Index() == position {
      this.m_listController.SelectItem(Cast<Uint32>(i), false);
      this.m_radioXLLastIndex = i;
      let changed = new RadioStationChangedEvent();
      changed.m_radioIndex = position;
      this.QueueEvent(changed);
      return;
    }
    i += 1;
  }
}

@wrapMethod(VehicleRadioPopupGameController)
protected cb func OnVehicleRadioSongChanged(evt: ref<VehicleRadioSongChanged>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  if IsDefined(this.m_radioXLLibrary) { this.m_radioXLLibrary.RadioReported(true); }
  return result;
}
