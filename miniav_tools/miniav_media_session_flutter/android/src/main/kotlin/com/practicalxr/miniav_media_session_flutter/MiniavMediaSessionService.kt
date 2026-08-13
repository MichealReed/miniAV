package com.practicalxr.miniav_media_session_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder

/**
 * Foreground service that carries the MediaStyle notification.
 *
 * WHY A SERVICE AT ALL. Phase 1 (the MediaSession alone) is enough for media
 * buttons and lock-screen transport, but the persistent panel in the
 * notification shade is drawn from an ongoing notification, and an ongoing
 * media notification has to be owned by a foreground service or Android kills
 * it as soon as the app leaves the foreground. That is the whole reason this
 * class exists.
 *
 * TRANSPORT DISPATCH. The notification's buttons do not carry their own command
 * path. They fire PendingIntents back into this service, which forwards them to
 * the session's own transport controls — so they land in the exact same
 * [MediaSession.Callback] as a hardware key, and there is only ever one route
 * from "user pressed something" to Dart. A second path would drift.
 *
 * COMPILE STATUS: written on Windows, never compiled or run on a device.
 */
class MiniavMediaSessionService : Service() {

    companion object {
        const val CHANNEL_ID = "miniav_media_session"
        const val NOTIFICATION_ID = 1000

        const val ACTION_PLAY = "com.practicalxr.miniav_media_session.PLAY"
        const val ACTION_PAUSE = "com.practicalxr.miniav_media_session.PAUSE"
        const val ACTION_STOP = "com.practicalxr.miniav_media_session.STOP"
        const val ACTION_NEXT = "com.practicalxr.miniav_media_session.NEXT"
        const val ACTION_PREVIOUS = "com.practicalxr.miniav_media_session.PREV"
        const val ACTION_REFRESH = "com.practicalxr.miniav_media_session.REFRESH"

        /**
         * FLAG_IMMUTABLE is mandatory from API 31 — without it the
         * PendingIntent constructor throws and every notification button is
         * dead. It has existed since API 23, below this module's minSdk 24, so
         * it needs no version guard.
         */
        private const val PI_FLAGS =
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        /**
         * The live session, published by the plugin.
         *
         * A static handoff because the plugin and the service share a process
         * and a lifetime, and binding would add an async hop to every metadata
         * push for nothing. The plugin MUST null this in releaseSession() —
         * a stale MediaSession here would keep the whole session graph alive
         * after the engine detaches.
         */
        @Volatile
        internal var session: MediaSession? = null

        /** Channel name shown in Android's per-app notification settings. */
        @Volatile
        internal var channelName: String = "Playback"

        fun start(context: Context) {
            val intent = Intent(context, MiniavMediaSessionService::class.java)
                .setAction(ACTION_REFRESH)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Android 12+ throws ForegroundServiceStartNotAllowedException
                // when the app is in the background. Losing the shade panel is
                // survivable; crashing the app that was only trying to show a
                // now-playing card is not.
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(
                    Intent(context, MiniavMediaSessionService::class.java),
                )
            } catch (e: Exception) {
                // Nothing to do; the service is already gone.
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val active = session
        if (active == null) {
            stopSelfSafely()
            return START_NOT_STICKY
        }

        when (intent?.action) {
            ACTION_PLAY -> active.controller.transportControls.play()
            ACTION_PAUSE -> active.controller.transportControls.pause()
            ACTION_NEXT -> active.controller.transportControls.skipToNext()
            ACTION_PREVIOUS ->
                active.controller.transportControls.skipToPrevious()
            ACTION_STOP -> {
                active.controller.transportControls.stop()
                stopSelfSafely()
                return START_NOT_STICKY
            }
        }

        showNotification(active)
        return START_NOT_STICKY
    }

    private fun showNotification(active: MediaSession) {
        createChannel()
        val notification = buildNotification(active)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // API 34 throws when the mediaPlayback type is not permitted. The
            // session itself keeps working; only the shade panel is lost.
            stopSelfSafely()
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
            ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            channelName,
            // LOW: a media notification must never buzz or make a sound. It is
            // a control surface, not an alert.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(active: MediaSession): Notification {
        val controller = active.controller
        val metadata: MediaMetadata? = controller.metadata
        val state: PlaybackState? = controller.playbackState
        val isPlaying = state?.state == PlaybackState.STATE_PLAYING
        val actions = state?.actions ?: 0L

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(smallIconRes())
            .setContentTitle(
                metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
                    ?: "",
            )
            .setContentText(
                metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    ?: "",
            )
            .setSubText(
                metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            )
            .setLargeIcon(
                metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART),
            )
            // Tapping the notification returns to the app. Without this the
            // panel is a dead end.
            .setContentIntent(launchAppIntent())
            .setDeleteIntent(servicePendingIntent(ACTION_STOP, 5))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            // Ongoing only while playing: a paused media notification must be
            // dismissible, or the user cannot get rid of it without killing
            // the app.
            .setOngoing(isPlaying)

        val compact = mutableListOf<Int>()
        var index = 0

        if (actions and PlaybackState.ACTION_SKIP_TO_PREVIOUS != 0L) {
            builder.addAction(
                action(
                    android.R.drawable.ic_media_previous,
                    "Previous",
                    ACTION_PREVIOUS,
                    1,
                ),
            )
            compact.add(index++)
        }

        // Show pause while playing and play while paused — the button is the
        // action, not the state.
        val canPlayPause = actions and
            (
                PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                    PlaybackState.ACTION_PLAY_PAUSE
                ) != 0L
        if (canPlayPause) {
            builder.addAction(
                if (isPlaying) {
                    action(
                        android.R.drawable.ic_media_pause,
                        "Pause",
                        ACTION_PAUSE,
                        2,
                    )
                } else {
                    action(
                        android.R.drawable.ic_media_play,
                        "Play",
                        ACTION_PLAY,
                        3,
                    )
                },
            )
            compact.add(index++)
        }

        if (actions and PlaybackState.ACTION_SKIP_TO_NEXT != 0L) {
            builder.addAction(
                action(
                    android.R.drawable.ic_media_next,
                    "Next",
                    ACTION_NEXT,
                    4,
                ),
            )
            compact.add(index++)
        }

        val style = Notification.MediaStyle()
            // Binding the token is what lets the system draw the rich media
            // panel (and, on API 33+, derive the controls from PlaybackState
            // rather than from the actions added above).
            .setMediaSession(active.sessionToken)
        if (compact.isNotEmpty()) {
            style.setShowActionsInCompactView(*compact.toIntArray())
        }
        builder.style = style

        return builder.build()
    }

    private fun action(
        icon: Int,
        title: String,
        intentAction: String,
        requestCode: Int,
    ): Notification.Action =
        Notification.Action.Builder(
            android.graphics.drawable.Icon.createWithResource(this, icon),
            title,
            servicePendingIntent(intentAction, requestCode),
        ).build()

    private fun servicePendingIntent(
        intentAction: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(this, MiniavMediaSessionService::class.java)
            .setAction(intentAction)
        return PendingIntent.getService(this, requestCode, intent, PI_FLAGS)
    }

    private fun launchAppIntent(): PendingIntent? {
        val launch = packageManager
            .getLaunchIntentForPackage(packageName)
            ?: return null
        return PendingIntent.getActivity(this, 6, launch, PI_FLAGS)
    }

    private fun smallIconRes(): Int {
        val icon = applicationInfo.icon
        // An adaptive launcher icon is a valid small icon on modern Android and
        // keeps the notification looking like the app rather than like a
        // generic system play glyph.
        return if (icon != 0) icon else android.R.drawable.ic_media_play
    }

    private fun stopSelfSafely() {
        // stopForeground(int) and STOP_FOREGROUND_REMOVE both landed in API 24,
        // this module's minSdk, so the deprecated boolean overload is never
        // needed here.
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopSelfSafely()
        super.onDestroy()
    }
}
