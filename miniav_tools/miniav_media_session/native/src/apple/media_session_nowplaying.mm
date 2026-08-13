/*
 * macOS + iOS backend: MPNowPlayingInfoCenter (publish) and
 * MPRemoteCommandCenter (receive).
 *
 * One file serves both platforms — the APIs are identical. The differences are
 * environmental, not code:
 *   - macOS: the process must be a real app bundle. A bare executable (a
 *     `dart test` run, a CLI) has no bundle identity, so Now Playing has
 *     nothing to attribute the session to and the Control Center tile stays
 *     empty. Same class of problem as a windowless process on Windows.
 *   - iOS: the app must own an active AVAudioSession with a playback category,
 *     and needs `UIBackgroundModes: audio` in Info.plist for the controls to
 *     survive backgrounding. Both are app-level configuration this library
 *     deliberately does not perform — taking over an app's audio session from
 *     a library is how you break every other sound it makes.
 *
 * THREADING
 * ---------
 * MPRemoteCommandCenter delivers handlers on the main thread and expects its
 * command objects to be mutated there. The Dart isolate is NOT the main thread
 * (in Flutter it is the UI thread), so every touch of MediaPlayer state is
 * marshalled onto the main queue.
 *
 * COMPILE STATUS: written on Windows, never compiled. CI must gate this.
 */
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#define MS_IMAGE UIImage
#else
#import <AppKit/AppKit.h>
#define MS_IMAGE NSImage
#endif

#include <cstring>
#include <new>

#include "media_session_internal.h"

namespace {

/* Run a block on the main queue and wait. Safe to call from the main thread
 * itself — dispatch_sync onto the current queue would deadlock. */
void RunOnMainSync(void (^block)(void)) {
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
}

void RunOnMainAsync(void (^block)(void)) {
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

NSString *Str(const char *utf8) {
  if (utf8 == nullptr || *utf8 == '\0') return nil;
  return [NSString stringWithUTF8String:utf8];
}

struct AppleBackend {
  MiniAVMediaSession *session = nullptr;
  /* Accumulated now-playing dictionary. MPNowPlayingInfoCenter replaces the
   * whole dictionary on assignment, so a partial update would silently erase
   * every field it does not mention — the position push would wipe the title.
   * Keeping the full dictionary here and re-assigning it is what prevents
   * that. */
  NSMutableDictionary *info = nil;
  /* Targets returned by addTargetWithHandler:, kept so destroy can remove
   * them. Without removal the blocks outlive the session and fire into freed
   * memory. */
  NSMutableArray *targets = nil;
  uint32_t actions = 0;
};

MPRemoteCommandCenter *Center() {
  return [MPRemoteCommandCenter sharedCommandCenter];
}

MPNowPlayingInfoCenter *InfoCenter() {
  return [MPNowPlayingInfoCenter defaultCenter];
}

void AddHandler(AppleBackend *backend, MPRemoteCommand *command, BOOL enabled,
                uint32_t action) {
  command.enabled = enabled;
  if (!enabled) return;
  id target = [command addTargetWithHandler:^MPRemoteCommandHandlerStatus(
                            MPRemoteCommandEvent *event) {
    int64_t position_us = -1;
    int64_t offset_us = -1;
    if ([event isKindOfClass:[MPChangePlaybackPositionCommandEvent class]]) {
      const NSTimeInterval t =
          ((MPChangePlaybackPositionCommandEvent *)event).positionTime;
      position_us = (int64_t)(t * 1e6);
    } else if ([event isKindOfClass:[MPSkipIntervalCommandEvent class]]) {
      const NSTimeInterval t = ((MPSkipIntervalCommandEvent *)event).interval;
      offset_us = (int64_t)(t * 1e6);
    }
    ms_emit_command(backend->session, action, position_us, offset_us);
    return MPRemoteCommandHandlerStatusSuccess;
  }];
  if (target != nil) {
    [backend->targets addObject:@[ command, target ]];
  }
}

void ApplyCommands(AppleBackend *backend, uint32_t actions) {
  MPRemoteCommandCenter *center = Center();

  /* Drop the previous set first: targets accumulate on the shared singleton,
   * so re-registering without removing would fire a command twice. */
  for (NSArray *pair in backend->targets) {
    [(MPRemoteCommand *)pair[0] removeTarget:pair[1]];
  }
  [backend->targets removeAllObjects];

  const bool has_play = (actions & MINIAV_MS_ACTION_PLAY) != 0;
  const bool has_pause = (actions & MINIAV_MS_ACTION_PAUSE) != 0;
  const bool has_toggle = (actions & MINIAV_MS_ACTION_PLAY_PAUSE) != 0;

  AddHandler(backend, center.playCommand, has_play, MINIAV_MS_ACTION_PLAY);
  AddHandler(backend, center.pauseCommand, has_pause, MINIAV_MS_ACTION_PAUSE);
  /* Apple models the toggle natively, so unlike SMTC and the web there is
   * nothing to synthesise — headphone play/pause lands here directly. */
  AddHandler(backend, center.togglePlayPauseCommand, has_toggle,
             MINIAV_MS_ACTION_PLAY_PAUSE);
  AddHandler(backend, center.stopCommand,
             (actions & MINIAV_MS_ACTION_STOP) != 0, MINIAV_MS_ACTION_STOP);
  AddHandler(backend, center.nextTrackCommand,
             (actions & MINIAV_MS_ACTION_NEXT) != 0, MINIAV_MS_ACTION_NEXT);
  AddHandler(backend, center.previousTrackCommand,
             (actions & MINIAV_MS_ACTION_PREVIOUS) != 0,
             MINIAV_MS_ACTION_PREVIOUS);
  AddHandler(backend, center.changePlaybackPositionCommand,
             (actions & MINIAV_MS_ACTION_SEEK_TO) != 0,
             MINIAV_MS_ACTION_SEEK_TO);
  AddHandler(backend, center.skipForwardCommand,
             (actions & MINIAV_MS_ACTION_SEEK_FORWARD) != 0,
             MINIAV_MS_ACTION_SEEK_FORWARD);
  AddHandler(backend, center.skipBackwardCommand,
             (actions & MINIAV_MS_ACTION_SEEK_BACKWARD) != 0,
             MINIAV_MS_ACTION_SEEK_BACKWARD);
}

void PublishInfo(AppleBackend *backend) {
  InfoCenter().nowPlayingInfo = backend->info;
}

MPMediaItemArtwork *ArtworkFromImage(MS_IMAGE *image) {
  if (image == nil) return nil;
  return [[MPMediaItemArtwork alloc]
      initWithBoundsSize:image.size
          requestHandler:^MS_IMAGE *(CGSize size) { return image; }];
}

}  // namespace

extern "C" {

void ms_platform_set_host_window(void *hwnd) { (void)hwnd; /* Windows only. */ }

int ms_platform_is_supported(void) {
#if TARGET_OS_IPHONE
  return 1;
#else
  /* No bundle identity means Now Playing has nothing to attribute a session
   * to. Reporting that up front is better than publishing into a void. */
  return [[NSBundle mainBundle] bundleIdentifier] != nil ? 1 : 0;
#endif
}

size_t ms_platform_describe(char *buf, size_t buf_len) {
  const char *text =
#if TARGET_OS_IPHONE
      "nowplaying: MPNowPlayingInfoCenter (iOS); needs an active "
      "AVAudioSession and UIBackgroundModes: audio";
#else
      "nowplaying: MPNowPlayingInfoCenter (macOS app bundle)";
#endif
  const size_t n = strlen(text);
  if (buf != NULL && buf_len > 0) {
    const size_t copy = (n < buf_len - 1) ? n : buf_len - 1;
    memcpy(buf, text, copy);
    buf[copy] = '\0';
  }
  return n;
}

MiniAVMediaSessionResult ms_platform_create(MiniAVMediaSession *session,
                                            const char *app_name) {
  (void)app_name; /* Apple takes the app identity from the bundle. */

#if !TARGET_OS_IPHONE
  if ([[NSBundle mainBundle] bundleIdentifier] == nil) {
    ms_set_last_error(
        "no bundle identifier: this process is not an app bundle, so macOS "
        "Now Playing has no app to attribute the session to");
    return MINIAV_MS_ERROR_UNSUPPORTED;
  }
#endif

  auto *backend = new (std::nothrow) AppleBackend();
  if (backend == nullptr) {
    ms_set_last_error("out of memory");
    return MINIAV_MS_ERROR_INTERNAL;
  }
  backend->session = session;
  backend->actions = session->actions;

  RunOnMainSync(^{
    backend->info = [[NSMutableDictionary alloc] init];
    backend->targets = [[NSMutableArray alloc] init];
    ApplyCommands(backend, backend->actions);
  });

  session->platform = backend;
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_destroy(MiniAVMediaSession *session) {
  auto *backend = static_cast<AppleBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_OK;
  session->platform = nullptr;

  /* Synchronous: after this returns the caller is free to close the Dart
   * NativeCallable, so no handler block may still be able to run. Removing the
   * targets on the thread that raises them is what makes that true. */
  RunOnMainSync(^{
    for (NSArray *pair in backend->targets) {
      [(MPRemoteCommand *)pair[0] removeTarget:pair[1]];
    }
    [backend->targets removeAllObjects];
    InfoCenter().nowPlayingInfo = nil;
#if !TARGET_OS_IPHONE
    if (@available(macOS 10.12.2, *)) {
      InfoCenter().playbackState = MPNowPlayingPlaybackStateStopped;
    }
#endif
    backend->info = nil;
    backend->targets = nil;
  });

  delete backend;
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_set_metadata(
    MiniAVMediaSession *session, const MiniAVMediaSessionMetadata *metadata) {
  auto *backend = static_cast<AppleBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_ERROR_UNSUPPORTED;

  NSString *title = Str(metadata->title);
  NSString *artist = Str(metadata->artist);
  NSString *album = Str(metadata->album);
  const int64_t duration_us = metadata->duration_us;
  const int32_t track_number = metadata->track_number;

  /* Decode artwork off the main thread — a multi-megabyte cover would
   * otherwise stall the UI on every track change. */
  MS_IMAGE *image = nil;
  if (metadata->artwork_path != nullptr && metadata->artwork_path[0] != '\0') {
    NSString *path = Str(metadata->artwork_path);
    if ([path hasPrefix:@"file://"] || [path containsString:@"://"]) {
      NSURL *url = [NSURL URLWithString:path];
      if (url != nil) image = [[MS_IMAGE alloc] initWithContentsOfURL:url];
    } else {
      image = [[MS_IMAGE alloc] initWithContentsOfFile:path];
    }
  } else if (metadata->artwork_bytes != nullptr &&
             metadata->artwork_bytes_len > 0) {
    NSData *data = [NSData dataWithBytes:metadata->artwork_bytes
                                  length:metadata->artwork_bytes_len];
    image = [[MS_IMAGE alloc] initWithData:data];
  }

  RunOnMainAsync(^{
    if (title != nil) backend->info[MPMediaItemPropertyTitle] = title;
    if (artist != nil) backend->info[MPMediaItemPropertyArtist] = artist;
    if (album != nil) backend->info[MPMediaItemPropertyAlbumTitle] = album;
    if (duration_us >= 0) {
      backend->info[MPMediaItemPropertyPlaybackDuration] =
          @((double)duration_us / 1e6);
    } else {
      [backend->info removeObjectForKey:MPMediaItemPropertyPlaybackDuration];
    }
    if (track_number > 0) {
      backend->info[MPMediaItemPropertyAlbumTrackNumber] = @(track_number);
    } else {
      [backend->info removeObjectForKey:MPMediaItemPropertyAlbumTrackNumber];
    }

    MPMediaItemArtwork *art = ArtworkFromImage(image);
    if (art != nil) {
      backend->info[MPMediaItemPropertyArtwork] = art;
    } else {
      /* Clear stale art rather than leaving the previous track's cover on a
       * new track that has none. */
      [backend->info removeObjectForKey:MPMediaItemPropertyArtwork];
    }
    PublishInfo(backend);
  });
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_set_state(MiniAVMediaSession *session,
                                               MiniAVMediaSessionState state) {
  auto *backend = static_cast<AppleBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_ERROR_UNSUPPORTED;

  RunOnMainAsync(^{
    if (@available(macOS 10.12.2, iOS 13.0, *)) {
      MPNowPlayingPlaybackState mapped = MPNowPlayingPlaybackStateUnknown;
      switch (state) {
        case MINIAV_MS_STATE_PLAYING:
          mapped = MPNowPlayingPlaybackStatePlaying;
          break;
        case MINIAV_MS_STATE_PAUSED:
          mapped = MPNowPlayingPlaybackStatePaused;
          break;
        case MINIAV_MS_STATE_STOPPED:
          mapped = MPNowPlayingPlaybackStateStopped;
          break;
        case MINIAV_MS_STATE_NONE:
        default:
          mapped = MPNowPlayingPlaybackStateStopped;
          break;
      }
      InfoCenter().playbackState = mapped;
    }
    /* The rate in nowPlayingInfo is what drives the scrubber's extrapolation;
     * playbackState alone does not stop it creeping. */
    backend->info[MPNowPlayingInfoPropertyPlaybackRate] =
        @(state == MINIAV_MS_STATE_PLAYING ? 1.0 : 0.0);
    PublishInfo(backend);
  });
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_set_position(
    MiniAVMediaSession *session, const MiniAVMediaSessionPosition *position) {
  auto *backend = static_cast<AppleBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_ERROR_UNSUPPORTED;

  const double elapsed = (double)position->position_us / 1e6;
  const double duration = (double)position->duration_us / 1e6;
  const double speed = position->speed;
  const bool has_duration = position->duration_us > 0;

  RunOnMainAsync(^{
    backend->info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
    backend->info[MPNowPlayingInfoPropertyPlaybackRate] = @(speed);
    if (has_duration) {
      backend->info[MPMediaItemPropertyPlaybackDuration] = @(duration);
    }
    PublishInfo(backend);
  });
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_set_actions(MiniAVMediaSession *session,
                                                 uint32_t actions) {
  auto *backend = static_cast<AppleBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_ERROR_UNSUPPORTED;
  backend->actions = actions;
  RunOnMainAsync(^{ ApplyCommands(backend, actions); });
  return MINIAV_MS_OK;
}

}  // extern "C"
