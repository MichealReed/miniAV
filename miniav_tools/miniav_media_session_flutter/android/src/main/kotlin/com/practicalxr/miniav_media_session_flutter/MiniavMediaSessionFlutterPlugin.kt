package com.practicalxr.miniav_media_session_flutter

import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android half of miniav_media_session.
 *
 * Android is the one platform whose media-session API cannot be reached from
 * the package's code asset: [MediaSession] needs a [Context], and the media
 * notification needs a foreground Service. Both are JVM-only. Everything else
 * (Windows SMTC, Apple Now Playing) lives in native/ and is called over
 * dart:ffi; only this one goes through a MethodChannel.
 *
 * Uses the FRAMEWORK MediaSession rather than androidx.media3, deliberately: a
 * now-playing card should not drag a media-playback library into every app that
 * wants one. The framework class has been available since API 21.
 *
 * SCOPE (phase 1): session, metadata, playback state and transport callbacks.
 * That is enough for hardware and Bluetooth media buttons to route here, and
 * for lock-screen controls while the app holds audio focus. It is NOT enough
 * for the persistent panel in the notification shade, which additionally needs
 * a MediaStyle notification posted from a foreground service — and that needs
 * manifest entries and a runtime notification permission only the host app can
 * declare. Same shape as the Windows case: buttons work, the panel needs more.
 */
class MiniavMediaSessionFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private var session: MediaSession? = null
    private var declaredActions: Long = 0

    /**
     * Whether to run the foreground service that carries the shade panel.
     *
     * On by default, but an opt-out exists because the service pulls in a
     * user-visible ongoing notification and, on Android 14+, a
     * FOREGROUND_SERVICE_MEDIA_PLAYBACK declaration that some Play Store
     * reviews ask about. An app that only wants media buttons and lock-screen
     * controls can turn it off and keep phase-1 behaviour.
     */
    private var showNotification = true

    private var lastState = PlaybackState.STATE_NONE
    private var lastPositionMs = 0L
    private var lastSpeed = 1.0f

    private val main = Handler(Looper.getMainLooper())

    private companion object {
        const val CHANNEL = "com.practicalxr.miniav_media_session"

        // Must track MiniAVMediaSessionAction in miniav_media_session.h.
        const val ACTION_PLAY = 1L shl 0
        const val ACTION_PAUSE = 1L shl 1
        const val ACTION_PLAY_PAUSE = 1L shl 2
        const val ACTION_STOP = 1L shl 3
        const val ACTION_NEXT = 1L shl 4
        const val ACTION_PREVIOUS = 1L shl 5
        const val ACTION_SEEK_TO = 1L shl 6
        const val ACTION_SEEK_FORWARD = 1L shl 7
        const val ACTION_SEEK_BACKWARD = 1L shl 8
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        releaseSession()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> result.success(initialize(call))
            "setMetadata" -> { setMetadata(call); result.success(null) }
            "setPlaybackState" -> { setPlaybackState(call); result.success(null) }
            "setPosition" -> { setPosition(call); result.success(null) }
            "setActions" -> { setActions(call); result.success(null) }
            "describe" -> result.success(describe())
            "dispose" -> { releaseSession(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    /** Returns null on success, or a reason string the Dart side reports. */
    private fun initialize(call: MethodCall): String? {
        releaseSession()
        return try {
            declaredActions = actionsFrom(call.argument<List<String>>("actions"))
            showNotification =
                call.argument<Boolean>("showNotification") ?: true
            MiniavMediaSessionService.channelName =
                call.argument<String>("notificationChannelName") ?: "Playback"

            val created = MediaSession(context, "miniav_media_session")
            created.setCallback(SessionCallback())
            created.isActive = true
            session = created
            MiniavMediaSessionService.session = created
            applyPlaybackState()
            null
        } catch (e: Exception) {
            "MediaSession unavailable: ${e.message}"
        }
    }

    private fun describe(): String = when {
        session == null -> ""
        showNotification ->
            "androidsession: framework MediaSession, active, with a MediaStyle " +
                "notification from a foreground service (shade panel + lock " +
                "screen + media buttons)"
        else ->
            "androidsession: framework MediaSession, active, notification " +
                "DISABLED (media buttons and lock screen only, no shade panel)"
    }

    private fun actionsFrom(names: List<String>?): Long {
        if (names == null) return 0
        var mask = 0L
        for (name in names) {
            mask = mask or when (name) {
                "play" -> ACTION_PLAY
                "pause" -> ACTION_PAUSE
                "playPause" -> ACTION_PLAY_PAUSE
                "stop" -> ACTION_STOP
                "next" -> ACTION_NEXT
                "previous" -> ACTION_PREVIOUS
                "seekTo" -> ACTION_SEEK_TO
                "seekForward" -> ACTION_SEEK_FORWARD
                "seekBackward" -> ACTION_SEEK_BACKWARD
                else -> 0L
            }
        }
        return mask
    }

    /** Our bitmask translated into PlaybackState's own action constants. */
    private fun platformActions(mask: Long): Long {
        var out = 0L
        if (mask and ACTION_PLAY != 0L) out = out or PlaybackState.ACTION_PLAY
        if (mask and ACTION_PAUSE != 0L) out = out or PlaybackState.ACTION_PAUSE
        if (mask and ACTION_PLAY_PAUSE != 0L) {
            out = out or PlaybackState.ACTION_PLAY_PAUSE
        }
        if (mask and ACTION_STOP != 0L) out = out or PlaybackState.ACTION_STOP
        if (mask and ACTION_NEXT != 0L) {
            out = out or PlaybackState.ACTION_SKIP_TO_NEXT
        }
        if (mask and ACTION_PREVIOUS != 0L) {
            out = out or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        }
        if (mask and ACTION_SEEK_TO != 0L) {
            out = out or PlaybackState.ACTION_SEEK_TO
        }
        if (mask and ACTION_SEEK_FORWARD != 0L) {
            out = out or PlaybackState.ACTION_FAST_FORWARD
        }
        if (mask and ACTION_SEEK_BACKWARD != 0L) {
            out = out or PlaybackState.ACTION_REWIND
        }
        return out
    }

    private fun setMetadata(call: MethodCall) {
        val builder = MediaMetadata.Builder()
        call.argument<String>("title")?.let {
            builder.putString(MediaMetadata.METADATA_KEY_TITLE, it)
        }
        call.argument<String>("artist")?.let {
            builder.putString(MediaMetadata.METADATA_KEY_ARTIST, it)
        }
        call.argument<String>("album")?.let {
            builder.putString(MediaMetadata.METADATA_KEY_ALBUM, it)
        }
        call.argument<Number>("durationUs")?.let {
            val us = it.toLong()
            if (us >= 0) {
                builder.putLong(MediaMetadata.METADATA_KEY_DURATION, us / 1000)
            }
        }
        call.argument<Number>("trackNumber")?.let {
            val n = it.toLong()
            if (n > 0) {
                builder.putLong(MediaMetadata.METADATA_KEY_TRACK_NUMBER, n)
            }
        }

        // Artwork. Bytes are the common case for mp3 (an ID3 APIC frame);
        // a local path is decoded from disk. A remote URL is not fetched —
        // silently downloading on the platform thread would be worse than
        // showing no art.
        val bytes = call.argument<ByteArray>("artworkBytes")
        val path = call.argument<String>("artworkPath")
        val bitmap = when {
            bytes != null && bytes.isNotEmpty() ->
                runCatching {
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }.getOrNull()
            path != null && !path.contains("://") ->
                runCatching { BitmapFactory.decodeFile(path) }.getOrNull()
            else -> null
        }
        if (bitmap != null) {
            builder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bitmap)
        }

        session?.setMetadata(builder.build())
        // The notification draws its title, artist and album art from the
        // session, so a track change has to redraw it or the panel keeps
        // showing the previous song.
        refreshNotification()
    }

    private fun setPlaybackState(call: MethodCall) {
        lastState = when (call.argument<String>("state")) {
            "playing" -> PlaybackState.STATE_PLAYING
            "paused" -> PlaybackState.STATE_PAUSED
            "stopped" -> PlaybackState.STATE_STOPPED
            else -> PlaybackState.STATE_NONE
        }
        // A paused session that still reports rate 1.0 makes the system
        // extrapolate a playhead that is not moving.
        lastSpeed = if (lastState == PlaybackState.STATE_PLAYING) 1.0f else 0.0f
        applyPlaybackState()
    }

    private fun setPosition(call: MethodCall) {
        call.argument<Number>("positionUs")?.let {
            lastPositionMs = it.toLong() / 1000
        }
        call.argument<Number>("speed")?.let { lastSpeed = it.toFloat() }
        applyPlaybackState()
    }

    private fun setActions(call: MethodCall) {
        declaredActions = actionsFrom(call.argument<List<String>>("actions"))
        applyPlaybackState()
    }

    private fun applyPlaybackState() {
        val active = session ?: return
        val state = PlaybackState.Builder()
            .setActions(platformActions(declaredActions))
            .setState(lastState, lastPositionMs, lastSpeed)
            .build()
        active.setPlaybackState(state)
        refreshNotification()
    }

    /**
     * Bring the shade notification in line with the session.
     *
     * Position pushes land here several times a second, which is deliberate and
     * cheap: the service rebuilds from the session's own metadata and playback
     * state, so a repeat start is an update rather than a new notification.
     */
    private fun refreshNotification() {
        if (!showNotification || session == null) return
        if (lastState == PlaybackState.STATE_NONE) {
            // Nothing is loaded; a panel for a session with no track is worse
            // than no panel.
            MiniavMediaSessionService.stop(context)
        } else {
            MiniavMediaSessionService.start(context)
        }
    }

    private fun releaseSession() {
        // Drop the static handoff FIRST: a stale MediaSession on the service's
        // companion would keep the whole session graph alive after the engine
        // detaches, and the service would happily rebuild a notification for a
        // session that is being torn down.
        MiniavMediaSessionService.session = null
        MiniavMediaSessionService.stop(context)
        session?.let {
            it.isActive = false
            it.release()
        }
        session = null
    }

    private fun emit(action: Long, positionUs: Long = -1, offsetUs: Long = -1) {
        // MediaSession callbacks already arrive on the main looper, but the
        // channel must be touched from it regardless, and a future handler
        // thread would otherwise break that silently.
        main.post {
            channel.invokeMethod(
                "onCommand",
                mapOf(
                    "action" to nameFor(action),
                    "positionUs" to positionUs,
                    "offsetUs" to offsetUs,
                ),
            )
        }
    }

    private fun nameFor(action: Long): String = when (action) {
        ACTION_PLAY -> "play"
        ACTION_PAUSE -> "pause"
        ACTION_PLAY_PAUSE -> "playPause"
        ACTION_STOP -> "stop"
        ACTION_NEXT -> "next"
        ACTION_PREVIOUS -> "previous"
        ACTION_SEEK_TO -> "seekTo"
        ACTION_SEEK_FORWARD -> "seekForward"
        ACTION_SEEK_BACKWARD -> "seekBackward"
        else -> ""
    }

    private inner class SessionCallback : MediaSession.Callback() {
        override fun onPlay() {
            // Android has no combined toggle callback: a headset play/pause key
            // arrives as onPlay or onPause depending on the reported state. An
            // app that declared only playPause is served by reporting the
            // toggle — but only when it did not also declare the discrete
            // actions, or one press would emit two commands. Same rule as the
            // SMTC and web backends.
            emit(if (togglesOnly()) ACTION_PLAY_PAUSE else ACTION_PLAY)
        }

        override fun onPause() {
            emit(if (togglesOnly()) ACTION_PLAY_PAUSE else ACTION_PAUSE)
        }

        override fun onStop() = emit(ACTION_STOP)

        override fun onSkipToNext() = emit(ACTION_NEXT)

        override fun onSkipToPrevious() = emit(ACTION_PREVIOUS)

        override fun onSeekTo(pos: Long) =
            emit(ACTION_SEEK_TO, positionUs = pos * 1000)

        override fun onFastForward() = emit(ACTION_SEEK_FORWARD)

        override fun onRewind() = emit(ACTION_SEEK_BACKWARD)

        private fun togglesOnly(): Boolean =
            declaredActions and ACTION_PLAY_PAUSE != 0L &&
                declaredActions and ACTION_PLAY == 0L &&
                declaredActions and ACTION_PAUSE == 0L
    }
}
