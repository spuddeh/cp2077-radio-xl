// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Reports every broadcast channel the loaded audio metadata uses, so the plugin
//              gives no custom station one of them. World playlists and gunshot reflections take
//              channels from the same space of 256 the stations play on, and a station sharing a
//              channel with one bleeds into it while both play.
//
//              Every audioCookedMetadataResource is watched, not only the base one: Phantom
//              Liberty and other mods load their own. The plugin starts from the game's own list
//              and only moves a station when a channel reported here is one it had.
// File Version: 0.8.0
// Credits: psiberx (Codeware)
// ======================================================================================

module RadioXL

public class RadioXLChannels extends ScriptableService {

  private cb func OnLoad() {
    GameInstance.GetCallbackSystem().RegisterCallback(n"Resource/Load", this, n"OnAudioMetadata")
      .AddTarget(ResourceTarget.Type(n"audioCookedMetadataResource"));
  }

  private cb func OnAudioMetadata(event: ref<ResourceEvent>) {
    let cooked = event.GetResource() as audioCookedMetadataResource;
    if !IsDefined(cooked) { return; }
    let added: Int32 = 0;
    for entry in cooked.entries {
      let playlist = entry as audioPlaylistMetadata;
      if IsDefined(playlist) && RadioXL_ReserveChannel(Cast<Int32>(playlist.broadcastChannel)) {
        added += 1;
      }
      let reflection = entry as audioReflectionEmitterSettings;
      if IsDefined(reflection) && RadioXL_ReserveChannel(Cast<Int32>(reflection.broadcastChannel)) {
        added += 1;
      }
    }
    if added > 0 {
      RadioXLLog(s"channels: \(added) broadcast channel(s) newly reserved from \(ResRef.ToString(event.GetPath()))");
    }
  }
}
