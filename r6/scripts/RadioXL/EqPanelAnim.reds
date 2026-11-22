// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The panels' close as the popup closes, and the equaliser rows' hover.
//
//              Close matches the station selection UI as it draws, sampled per frame in game. The
//              popup plays fadeOut (vehicles_radio_animations.inkanim), and its picture area shrinks
//              with it, which moves its list. A panel has no picture area, so its content takes that
//              movement as a slide of its own. A row's hover
//              is what the settings menu's row controller does: the label's Hover state and the row's
//              highlight.
// File Version: 0.11.0
// ======================================================================================

module RadioXL

public abstract class RadioXLEqAnim {
  public final static func Fade(def: ref<inkAnimDef>, from: Float, to: Float, delay: Float, duration: Float) -> Void {
    let fade = new inkAnimTransparency();
    fade.SetStartTransparency(from);
    fade.SetEndTransparency(to);
    fade.SetStartDelay(delay);
    fade.SetDuration(duration);
    fade.SetType(inkanimInterpolationType.Linear);
    fade.SetMode(inkanimInterpolationMode.EasyIn);
    def.AddInterpolator(fade);
  }

  public final static func Slide(def: ref<inkAnimDef>, fromY: Float, toY: Float, delay: Float, duration: Float,
                                 curve: inkanimInterpolationType, mode: inkanimInterpolationMode) -> Void {
    let slide = new inkAnimTranslation();
    slide.SetStartTranslation(new Vector2(0.0, fromY));
    slide.SetEndTranslation(new Vector2(0.0, toY));
    slide.SetStartDelay(delay);
    slide.SetDuration(duration);
    slide.SetType(curve);
    slide.SetMode(mode);
    def.AddInterpolator(slide);
  }

  public final static func Squash(def: ref<inkAnimDef>, toY: Float, delay: Float, duration: Float,
                                  curve: inkanimInterpolationType, mode: inkanimInterpolationMode) -> Void {
    let squash = new inkAnimScale();
    squash.SetStartScale(new Vector2(1.0, 1.0));
    squash.SetEndScale(new Vector2(1.0, toY));
    squash.SetStartDelay(delay);
    squash.SetDuration(duration);
    squash.SetType(curve);
    squash.SetMode(mode);
    def.AddInterpolator(squash);
  }

  // The fluff's flicker: each value in turn, `step` apart from `delay`, ending on the last.
  public final static func Flicker(def: ref<inkAnimDef>, values: array<Float>, delay: Float, step: Float) -> Void {
    let i: Int32 = 1;
    while i < ArraySize(values) {
      RadioXLEqAnim.Fade(def, values[i - 1], values[i], delay + Cast<Float>(i - 1) * step, 0.001);
      i += 1;
    }
  }

  // Finishes inside the popup's own 0.5 s fadeOut, which ends by destroying the popup.
  public final static func Close(root: wref<inkCompoundWidget>) -> Void {
    if !IsDefined(root) { return; }
    let setup = root.GetWidget(n"setup") as inkCompoundWidget;
    if !IsDefined(setup) { return; }
    let into: inkanimInterpolationMode = inkanimInterpolationMode.EasyIn;

    // The title bar: down 100 while it fades out.
    let top = setup.GetWidget(n"top_holder") as inkCompoundWidget;
    if IsDefined(top) {
      let def = new inkAnimDef();
      RadioXLEqAnim.Slide(def, 0.0, 100.0, 0.096, 0.231, inkanimInterpolationType.Quadratic, into);
      RadioXLEqAnim.Fade(def, 1.0, 0.0, 0.1, 0.25);
      top.PlayAnimation(def);
      let title: wref<inkWidget> = top.GetWidget(n"title");
      if IsDefined(title) {
        def = new inkAnimDef();
        RadioXLEqAnim.Fade(def, 1.0, 0.0, 0.067, 0.25);
        title.PlayAnimation(def);
      }
      let fluff: wref<inkWidget> = top.GetWidget(n"fluff_name-l");
      if IsDefined(fluff) {
        def = new inkAnimDef();
        RadioXLEqAnim.Flicker(def, [0.0, 0.3, 0.0], 0.367, 0.067);
        fluff.PlayAnimation(def);
      }
    }

    // The content folds up under the title bar as the popup does: the popup's picture area drops with
    // the title while it shrinks, and its list rises 340 into the space. The content's top drops 60 and
    // it squashes from the top to 70%, which takes its foot up the same 340; the footer line and hints
    // rise a further 200 of their own.
    let content = setup.GetWidget(n"content") as inkCompoundWidget;
    if IsDefined(content) {
      let def = new inkAnimDef();
      RadioXLEqAnim.Slide(def, 0.0, 60.0, 0.06, 0.29, inkanimInterpolationType.Qubic, into);
      RadioXLEqAnim.Squash(def, 0.70, 0.06, 0.29, inkanimInterpolationType.Qubic, into);
      content.SetRenderTransformPivot(0.5, 0.0);
      content.PlayAnimation(def);
      let i: Int32 = 0;
      while i < content.GetNumChildren() {
        let row: wref<inkWidget> = content.GetWidgetByIndex(i);
        let name: CName = row.GetName();
        def = new inkAnimDef();
        if Equals(name, n"horizontalLine") || Equals(name, n"inputHints") {
          RadioXLEqAnim.Slide(def, 0.0, -200.0, 0.067, 0.3, inkanimInterpolationType.Quartic, into);
          RadioXLEqAnim.Fade(def, row.GetOpacity(), 0.0, 0.267, 0.1);
        } else {
          // With the footer: a row at no opacity drops out of the panel's layout, and the line still
          // showing below it would jump.
          RadioXLEqAnim.Fade(def, row.GetOpacity(), 0.0, 0.267, 0.1);
        }
        row.PlayAnimation(def);
        i += 1;
      }
    }

    let fluffBottom: wref<inkWidget> = root.GetWidget(n"fluffBottom2");
    if IsDefined(fluffBottom) {
      let def = new inkAnimDef();
      RadioXLEqAnim.Fade(def, fluffBottom.GetOpacity(), 0.0, 0.233, 0.067);
      fluffBottom.PlayAnimation(def);
    }
  }
}

// One settings row's hover. The pointer and the keys share one focus: a row under the pointer takes it,
// and the panel lights the focused row.
public class RadioXLEqHover extends IScriptable {
  public let panel: wref<RadioXLEqPanel>;
  public let row: Int32;
  // A fader's arrow names its fader; a row's hover has -1.
  public let band: Int32;
  public let label: wref<inkWidget>;
  public let highlight: wref<inkWidget>;

  public func Show(on: Bool) -> Void {
    if IsDefined(this.label) { this.label.SetState(on ? n"Hover" : n"Default"); }
    if IsDefined(this.highlight) { this.highlight.SetVisible(on); }
  }

  protected cb func OnHoverOver(e: ref<inkPointerEvent>) -> Bool {
    if IsDefined(this.panel) { this.panel.Hovered(this.row, this.band); }
    return false;
  }
}
