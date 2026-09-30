// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Registers the station name and song titles through Codeware's localization system.
// File Version: 0.6.0
// Credits: Codeware by psiberx.
// ======================================================================================
//
// A row inserted into onscreens.json as it loads resolves by numeric hash, which is how a song title
// is looked up, and does not resolve by key STRING, which is how `GetLocalizedTextByKey` and
// `inkText.SetLocalizedTextString` look a station name up - the dashboard and every world device.
// Codeware merges provider text at the engine's own text-loading hook, and text registered there
// resolves both ways. The keys are the same ones the plugin mints, so the two routes agree.

module RadioXL

// Codeware is a hard dependency of the framework (the callback system, the resource depot,
// ScriptableService), so this import is unconditional.
import Codeware.Localization.*

// One of the panel's own strings, by key. Reads go through Codeware's LocalizationSystem, which
// is where a ModLocalizationProvider's texts live; the game's GetLocalizedText does not see
// them. A missing key renders as the key, so a fault names itself on screen.
public func RadioXLText(key: String) -> String {
  let loc = LocalizationSystem.GetInstance(GetGameInstance());
  if !IsDefined(loc) { return key; }
  let text = loc.GetText(key);
  return StrLen(text) > 0 ? text : key;
}

// A station's name and titles are the modder's text as written, the same in every language. Its
// description may be written per language, so each package carries the one for its language.
// Codeware asks for the fallback and the current language and merges both.
public class RadioXLLocalizationProvider extends ModLocalizationProvider {
  public func GetPackage(language: CName) -> ref<ModLocalizationPackage> {
    let package = new RadioXLTexts();
    package.language = NameToString(language);
    return package;
  }

  public func GetFallback() -> CName {
    return n"en-us";
  }
}

// The key a station's description is registered under: its name key with `-desc` after it.
public func RadioXL_DescriptionKey(station: Int32) -> String {
  return NameToString(RadioXL_StationKey(station)) + "-desc";
}

public class RadioXLTexts extends ModLocalizationPackage {
  public let language: String;

  protected func DefineTexts() -> Void {
    let added: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = RadioXL_StationCount();
    while station < count {
      let name: String = RadioXL_StationDisplayName(station);
      if StrLen(name) > 0 {
        this.Text(NameToString(RadioXL_StationKey(station)), name);
        added += 1;
      }
      let description: String = RadioXL_StationDescription(station, this.language);
      if StrLen(description) > 0 {
        this.Text(RadioXL_DescriptionKey(station), description);
        added += 1;
      }
      let tracks: Int32 = RadioXL_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        let title: String = RadioXL_StationTrackTitle(station, t);
        if StrLen(title) > 0 {
          this.Text(NameToString(RadioXL_StationTrackKey(station, t)), title);
          added += 1;
        }
        t += 1;
      }
      station += 1;
    }
    RadioXLLog(s"handed \(added) string(s) to Codeware's localization system");
  }
}
