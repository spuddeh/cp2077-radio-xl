// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The English strings of the settings panel, and the fallback for every other
//              language. The key is the first text on each line and never changes; the second is
//              what the player reads. Station names and song titles are not here: those are the
//              station author's text and go through RadioXLTexts unchanged.
// File Version: 0.3.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL.Translations

import Codeware.Localization.*

public class RadioXLEnglish extends ModLocalizationPackage {
  protected func DefineTexts() -> Void {
    this.Text("RadioXL.modName", "RadioXL");
    this.Text("RadioXL.modDesc", "Your own radio stations in Night City, as real stations of the game's own radio. Next and previous song, songs you can switch off, and the radio coming on to your station.");

    // --- tabs and sections ---
    this.Text("RadioXL.tabControls", "Controls");
    this.Text("RadioXL.tabMyStation", "My station");
    this.Text("RadioXL.tabStations", "Stations");
    this.Text("RadioXL.tabMute", "Mute");
    this.Text("RadioXL.secKeys", "Keys");
    this.Text("RadioXL.secOnScreen", "On screen");
    this.Text("RadioXL.secMyStation", "My station");
    this.Text("RadioXL.secTalk", "Station talk");
    this.Text("RadioXL.secMuteWhen", "Mute the radio when...");
    this.Text("RadioXL.secRadioport", "Radioport keys");
    this.Text("RadioXL.grpRadioport", "Radioport keys");
    this.Text("RadioXL.grpModifiers", "Modifiers");

    // --- keys ---
    this.Text("RadioXL.labKeys1", "One set of keys for both radios.");
    this.Text("RadioXL.labKeys2", "In a vehicle they act on the vehicle radio. On foot, on the Radioport.");
    this.Text("RadioXL.labKeys3", "Press a key or a controller button to bind one. Escape clears it.");
    this.Text("RadioXL.labKeys4", "A key the game already uses keeps doing what the game says.");
    this.Text("RadioXL.keyNext", "Next song");
    this.Text("RadioXL.keyPrevious", "Previous song");
    this.Text("RadioXL.keyNextStation", "Next station");
    this.Text("RadioXL.keyPreviousStation", "Previous station");
    this.Text("RadioXL.keyShowPopup", "Show what's playing");
    this.Text("RadioXL.keyNever", "Never play this song again");
    this.Text("RadioXL.keyMyStation", "Jump to my station");
    this.Text("RadioXL.tipStationKeys", "Moves along the dial in the same order the radio does, skipping the stations set aside on the Stations tab. Unbound by default.");
    this.Text("RadioXL.tipShowPopup", "Puts the radio popup on screen for the song playing now. Unbound by default.");
    this.Text("RadioXL.tipNever", "Switches the song that is playing off and moves on, so you never have to find it on the Stations tab. Unbound by default.");
    this.Text("RadioXL.tipMyStation", "Tunes to the station set on the My station tab, whether or not the automatic tuning is switched on. Unbound by default.");
    this.Text("RadioXL.optUseModifiers", "Hold a modifier with the keys");
    this.Text("RadioXL.tipUseModifiers", "Gives every key a second row: a key that must be held down with it. A key with its modifier held wins over the same key bound on its own, so F3 can be the next song and Shift+F3 the next station.");
    this.Text("RadioXL.modNext", "Next song modifier");
    this.Text("RadioXL.modPrevious", "Previous song modifier");
    this.Text("RadioXL.modNextStation", "Next station modifier");
    this.Text("RadioXL.modPreviousStation", "Previous station modifier");
    this.Text("RadioXL.modShowPopup", "Show what's playing modifier");
    this.Text("RadioXL.modNever", "Never play this song again modifier");
    this.Text("RadioXL.modMyStation", "Jump to my station modifier");
    this.Text("RadioXL.tipModifier", "Held down with the key above.");
    this.Text("RadioXL.optSeparateRadioport", "Separate keys for the Radioport");
    this.Text("RadioXL.tipSeparateRadioport", "Gives the Radioport its own set of keys, used on foot instead of the set above.");
    this.Text("RadioXL.labRadioport", "Off, the keys above serve the Radioport too.");

    // --- on screen ---
    this.Text("RadioXL.optNotifyRadioport", "Show the song on the Radioport");
    this.Text("RadioXL.tipNotifyRadioport", "Shows the vehicle radio's song popup when a song changes on the Radioport.");
    this.Text("RadioXL.optNotifyOnscreen", "Show the song as an on-screen message");
    this.Text("RadioXL.tipNotifyOnscreen", "Shows the station and song at the left of the screen when a song changes.");

    // --- my station ---
    this.Text("RadioXL.optRemember", "Tune to my station");
    this.Text("RadioXL.tipRemember", "When the radio comes on, tune it to the station below.");
    this.Text("RadioXL.optStation", "Station");
    this.Text("RadioXL.tipStation", "Remembered by name, so it stays the same station when station mods are added or removed.");
    this.Text("RadioXL.dropNone", "None");
    this.Text("RadioXL.optPlayOnEnter", "When getting into a car");
    this.Text("RadioXL.tipPlayOnEnter", "Tune when you sit in the driver's seat and the radio is on.");
    this.Text("RadioXL.optPlayOnVehiclePowerOn", "When the car radio is switched on");
    this.Text("RadioXL.tipPlayOnVehiclePowerOn", "Tune when you turn the vehicle radio on.");
    this.Text("RadioXL.optPlayOnPocketPowerOn", "When the Radioport is switched on");
    this.Text("RadioXL.tipPlayOnPocketPowerOn", "Tune when you turn the Radioport on.");
    this.Text("RadioXL.optIgnorePocket", "Even if the Radioport is on");
    this.Text("RadioXL.tipIgnorePocket", "Tune the car radio even when the Radioport is already playing another station.");

    // --- stations ---
    this.Text("RadioXL.labStations1", "One section per station, in dial order.");
    this.Text("RadioXL.labStations2", "A song set to Off is skipped whenever it comes up.");
    this.Text("RadioXL.labStations3", "Off while streaming is skipped only while the game's Streamer Mode is on.");
    this.Text("RadioXL.labStations4", "Songs the game marks as not streamer friendly start there. A station mod's songs start On.");
    this.Text("RadioXL.labStations5", "A station with every song off plays as normal.");
    this.Text("RadioXL.noteStreamerOn", "Streamer Mode is ON. Songs set to Off while streaming are marked and are being skipped.");
    this.Text("RadioXL.noteStreamerOff", "Streamer Mode is off. Songs set to Off while streaming are playing normally.");
    this.Text("RadioXL.noteNoCatalog", "The station list is read when a game is loaded. Load a save and open this panel again.");
    this.Text("RadioXL.optSkipStation", "Keys step over this station");
    this.Text("RadioXL.tipSkipStation", "The next and previous station keys skip it. It can still be picked from the radio itself.");
    this.Text("RadioXL.songOn", "On");
    this.Text("RadioXL.songOff", "Off");
    this.Text("RadioXL.songStreamerOff", "Off while streaming");
    this.Text("RadioXL.noteHidden", "hidden now");
    this.Text("RadioXL.noteNeverAgain", "Switched off:");

    // --- mute ---
    this.Text("RadioXL.optMuteIdents", "Mute station idents");
    this.Text("RadioXL.tipMuteIdents", "The station's own spot between songs: its name, its frequency and whatever its host says over them. Applies from the next song.");
    this.Text("RadioXL.optMuteNews", "Mute DJ announcements");
    this.Text("RadioXL.tipMuteNews", "Everything that takes a slot between your songs: Stanley's news, Maximum Mike's song intros and Growl FM's Ash. Kurt Hansen's Dogtown broadcasts are left alone. Takes effect straight away, and switching it back puts the sound in place exactly as it was.");
    this.Text("RadioXL.labMuteWhen1", "Every switch is on by default.");
    this.Text("RadioXL.labMuteWhen2", "ON: the Radioport goes quiet in that situation, exactly as the game does.");
    this.Text("RadioXL.labMuteWhen3", "OFF: it keeps playing through it, on every station, the game's own included.");
    this.Text("RadioXL.labMuteCombat", "Combat and police heat have no switch. They are the game's own mix rules and apply to every station.");
    this.Text("RadioXL.muteSceneTier", "A scene is playing");
    this.Text("RadioXL.tipMuteSceneTier", "Default: on. Any scripted scene, from a conversation that takes some control away up to a full cutscene. Off also lifts the hands-empty lock and the skip prompt a scene raises with it, for the length of the scene.");
    this.Text("RadioXL.mutePhoneCall", "A holo call is in progress");
    this.Text("RadioXL.tipMutePhoneCall", "Default: on. From the moment a call connects until it ends. Off also lifts the quest lock and the fast-travel block a call raises with it, for the length of the call.");
    this.Text("RadioXL.muteQuestContentLock", "A quest has blocked the radio");
    this.Text("RadioXL.tipMuteQuestContentLock", "Default: on. A story moment in which the quest switches the radio off outright.");
    this.Text("RadioXL.muteInDaClub", "You are inside a club");
    this.Text("RadioXL.tipMuteInDaClub", "Default: on. Clubs play their own music.");
    this.Text("RadioXL.muteVehicleScene", "A vehicle scene is playing");
    this.Text("RadioXL.tipMuteVehicleScene", "Default: on. A scripted scene inside a vehicle, such as a Delamain ride or a drive where a character talks to you. Off also lifts the hands-empty and calling locks and the skip prompt a vehicle scene raises with it, for the length of the scene.");
    this.Text("RadioXL.muteVehicleBlockPocketRadio", "The vehicle blocks the Radioport");
    this.Text("RadioXL.tipMuteVehicleBlockPocketRadio", "Default: on. A vehicle set to switch the Radioport off during its ride.");
    this.Text("RadioXL.muteUpperBodyState", "Your hands are forced empty");
    this.Text("RadioXL.tipMuteUpperBodyState", "Default: on. Carrying a body, or a scripted moment that takes your weapons away.");
    this.Text("RadioXL.muteBlockFastTravel", "Fast travel is blocked");
    this.Text("RadioXL.tipMuteBlockFastTravel", "Default: on. A quest state in which the game also disables fast travel.");
    this.Text("RadioXL.mutePhoneNoTexting", "Texting is blocked");
    this.Text("RadioXL.tipMutePhoneNoTexting", "Default: on. A story moment in which the game has disabled text messages.");
    this.Text("RadioXL.mutePhoneNoCalling", "Calling is blocked");
    this.Text("RadioXL.tipMutePhoneNoCalling", "Default: on. A story moment in which the game has disabled holo calls.");
    this.Text("RadioXL.muteFastForward", "A scene is being skipped");
    this.Text("RadioXL.tipMuteFastForward", "Default: on. A scene or ride is being fast-forwarded with the hold-to-skip control.");
    this.Text("RadioXL.muteFastForwardHintActive", "The skip prompt is on screen");
    this.Text("RadioXL.tipMuteFastForwardHintActive", "Default: on. The game is offering to skip a scene or ride: the hold-to-skip prompt is showing.");
  }
}
