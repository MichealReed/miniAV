#ifndef SCREEN_CONTEXT_LINUX_PIPEWIRE_H
#define SCREEN_CONTEXT_LINUX_PIPEWIRE_H

#include "../../../include/miniav_types.h" // For MiniAV types, including MINIAV_VIDEO_FORMAT_MAX_PLANES
#include "../screen_context.h" // For MiniAVScreenContext

// Add these includes for PipeWire and GLib types
#include <gio/gio.h> // For GDBusConnection, GCancellable
#include <glib.h>    // For GVariant etc.
#include <pipewire/pipewire.h>
#include <pthread.h>                      // For pthread_t
#include <spa/param/audio/format-utils.h> // For spa_audio_info_raw
#include <spa/param/video/format-utils.h> // For spa_video_info_raw

#define PW_SCREEN_MAX_BUFFERS 16 // Max number of buffers for the stream

// Forward declarations for portal interaction (if using libportal or similar)
// struct OrgFreedesktopPortalRequest;
// struct OrgFreedesktopPortalScreenCast;

typedef enum {
  PORTAL_OP_STATE_NONE,
  PORTAL_OP_STATE_CREATING_SESSION,
  PORTAL_OP_STATE_SELECTING_SOURCES,
  PORTAL_OP_STATE_STARTING_STREAM
} PortalOperationState;

typedef struct {
  struct spa_video_info_raw
      spa_format; // Holds format, size, framerate, modifier
  uint64_t negotiated_modifier;
  bool is_dmabuf;
  uint32_t
      derived_num_planes; // Number of planes derived from spa_format.format
} PipeWireScreenVideoFormatDetails;

typedef struct PipeWireScreenPlatformContext {
  struct MiniAVScreenContext *parent_ctx;
  struct pw_main_loop *loop;
  struct pw_context *context;
  struct pw_core *core;
  struct spa_hook core_listener;
  bool core_connected;
  int core_sync_seq;

  GDBusConnection *dbus_conn;
  GCancellable *cancellable; // Used for all async portal calls

  char *portal_session_handle_str; // Actual D-Bus object path of the session
  // char *portal_request_handle_str; // This will be split and renamed
  char *current_portal_request_token_str; // The "handle_token" we send for the
                                          // current portal request
  char *current_portal_request_object_path_str; // D-Bus object path of the
                                                // current Request object

  PortalOperationState
      current_portal_op_state; // Tracks the current portal operation
  guint current_request_signal_subscription_id; // Subscription ID for the
                                                // Request "Response" signal
  guint session_closed_signal_subscription_id;  // Subscription ID for the
                                                // Session "Closed" signal

  MiniAVBufferCallback app_callback_pending;
  void *app_callback_user_data_pending;

  struct pw_stream *video_stream;
  struct spa_hook video_stream_listener;
  bool video_stream_active;
  uint32_t video_node_id;
  MiniAVVideoInfo requested_video_format;
  PipeWireScreenVideoFormatDetails current_video_format_details;
  struct pw_buffer *video_pw_buffers[PW_SCREEN_MAX_BUFFERS];
  long video_dmabuf_fds[PW_SCREEN_MAX_BUFFERS]; // Keep as long for FDs

  struct pw_stream *audio_stream;
  struct spa_hook audio_stream_listener;
  bool audio_stream_active;
  uint32_t audio_node_id;
  MiniAVAudioInfo requested_audio_format;
  struct spa_audio_info_raw current_audio_format;
  bool audio_requested_by_user;

  pthread_t loop_thread;
  bool loop_running;
  int wakeup_pipe[2];

  MiniAVCaptureType capture_type;
  char target_id_str[256];
  int region_x, region_y, region_width, region_height;

  MiniAVResultCode last_error;
} PipeWireScreenPlatformContext;

// Platform init function (called by screen_api.c)
MiniAVResultCode
miniav_screen_context_platform_init_linux_pipewire(MiniAVScreenContext *ctx);

#endif // SCREEN_CONTEXT_LINUX_PIPEWIRE_H
