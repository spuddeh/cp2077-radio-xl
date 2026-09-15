// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Resolves a language code to a package of panel strings. Nothing registers this:
//              it extends ScriptableSystem, and Codeware queues the registration itself. Every
//              language falls through to English until a translation is dropped in. Station text
//              has its own provider in Localization.reds, because that text is never translated.
// File Version: 0.3.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL.Translations

import Codeware.Localization.*

public class RadioXLPanelLocalizationProvider extends ModLocalizationProvider {
  public func GetPackage(language: CName) -> ref<ModLocalizationPackage> {
    switch language {
      default: return new RadioXLEnglish();
    };
  }

  public func GetFallback() -> CName {
    return n"en-us";
  }
}
