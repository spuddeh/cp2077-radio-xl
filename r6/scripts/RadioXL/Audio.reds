// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The AudioXL bridge - the one place this framework talks about sound.
// File Version: 0.3.0
// Credits: AudioXL by DigitalVixen.
// ======================================================================================
//
// **This framework does not decode, stream or mix anything.** AudioXL registers a file and becomes
// the authority on it: the length the station schedules against, and the Wwise id the engine posts.
// Neither is written in a station manifest, so neither can disagree with the file on disk.
//
// AudioXL is a hard requirement. Without it this file does not compile, so redscript reports the
// missing dependency before the game starts.

module RadioXL

import AudioXL.*

// **`mod_sfx_radio` is the GAME's own radio routing, and a station must use it.** An `axl_*` type is
// a 2D sound on a mixer: nothing owns it, so the radio system cannot stop it, a car cannot take it
// over from the Radioport, and it is audible at a world device whether or not that device plays.
// A station is a voice on the radio's own emitter, never a sound played alongside it.
public class RadioXLAudio {

  public final static func Register(event: CName, file: String, type: CName) -> Bool {
    // pitch default, distance 30: the row's attenuation reach at a world device. 0 is the engine's
    // default for the mod_sfx_radio object, which is tuned for a broadcast effect and plays a
    // station audibly quieter at a device than a vanilla one. `stream` is read for WAV only.
    // The gain argument here is stored in the engine's registry entry and never reaches the
    // samples; the level is set through SetGain below once the row exists.
    return AudioXLNative.RegisterSoundEx(event, type, file, 1.0, 0.0, 30.0,
                                         false, 0.0, 0.0, 0.0, 0.0, 0.0, true);
  }

  // **A custom sound is played by posting its TYPE's event, and a type is whatever a loaded bank
  // defines.** This framework's own bank defines `radioxl_radio`, a clone of the game's `mod_sfx_radio`
  // that cites a vanilla station's pair of Broadcast Send objects instead of that type's own, which
  // are trimmed above every station on the dial. Loading it is what makes the type postable.
  //
  // 1 is AudioXL's success and 69 is a bank already loaded; both mean the type resolves.
  public final static func LoadBankResult(path: String) -> Int32 {
    return AudioXLNative.LoadBank(path);
  }

  // True when a token for the resource already exists, so taking another starts no new load.
  public final static func IsResourceRequested(path: ResRef) -> Bool {
    return AudioXLNative.IsResourceRequested(path);
  }

  // The level trim on a row's samples. False when the row does not exist yet: AudioXL queues a
  // registration made before the engine's audio system is up, and a queued row has no gain to set.
  public final static func SetGain(event: CName, gain: Float) -> Bool {
    return AudioXLNative.SetGain(event, gain);
  }

  // A stream track's file is its URL. AudioXL accepts the row at once and probes the stream on a
  // worker thread, so the row appears a moment later and SetGain waits for it.
  public final static func IsStream(file: String) -> Bool {
    let lower: String = StrLower(file);
    return StrBeginsWith(lower, "http://") || StrBeginsWith(lower, "https://");
  }

  public final static func RegisterStream(event: CName, url: String, type: CName) -> Bool {
    return AudioXLNative.RegisterSound(event, type, url, 1.0, 0.0, 30.0);
  }

  // A URL row appears once AudioXL has probed its station, which can take seconds or minutes. The
  // answer is how many URL rows are still waiting.
  public final static func PollStreams() -> Int32 {
    AudioXLNative.Poll();
    return AudioXLNative.PendingRemote();
  }

  // False means every URL row is refused: AudioXL.ini, which only the player edits, turns http on
  // and lists the hosts allowed.
  public final static func HttpAllowed() -> Bool {
    return AudioXLNative.HttpAllowed();
  }

  public final static func HttpStatus() -> String {
    return AudioXLNative.HttpStatus();
  }

  public final static func Has(event: CName) -> Bool {
    return AudioXLNative.Has(event);
  }

  public final static func Duration(event: CName) -> Float {
    return AudioXLNative.Duration(event);
  }

  public final static func WwiseId(event: CName) -> Uint32 {
    return AudioXLNative.WwiseId(event);
  }

  public final static func Available() -> Bool {
    return AudioXLNative.Available();
  }
}
