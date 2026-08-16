package com.matrimpathak.ledger

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Process-wide holder for the Dart-side [EventChannel.EventSink]. Also
 * buffers events (bounded, TTL'd — same shape as the Dart-side ring buffer
 * in NotificationListenerBridge) for the common case where a notification
 * posts *before* any Dart listener has attached — e.g. the app is
 * foregrounded on some other screen, or was just reopened, when the
 * transaction-detail suggestion chip's listener starts. Without this,
 * every such event was silently dropped rather than merely delayed.
 * Buffered events flush to the sink the moment one attaches. Still nothing
 * is ever persisted — this is in-memory only, for the lifetime of the
 * process.
 */
object NotificationEventBridge {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private const val MAX_BUFFERED_EVENTS = 20
    private const val EVENT_TTL_MS = 10 * 60 * 1000L

    private data class Buffered(val data: Map<String, Any?>, val postTimeMs: Long)

    private val buffer = ArrayDeque<Buffered>()

    @Synchronized
    fun attach(newSink: EventChannel.EventSink?) {
        sink = newSink
        if (newSink != null) flushBuffer(newSink)
    }

    @Synchronized
    private fun flushBuffer(target: EventChannel.EventSink) {
        prune()
        if (buffer.isEmpty()) return
        val events = buffer.toList()
        buffer.clear()
        mainHandler.post {
            // Only deliver to the sink that was active when we flushed —
            // if a newer listener has since attached, let it get fresh
            // events instead of this stale batch.
            if (sink === target) {
                for (event in events) target.success(event.data)
            }
        }
    }

    @Synchronized
    private fun prune() {
        val cutoff = System.currentTimeMillis() - EVENT_TTL_MS
        while (buffer.isNotEmpty() && buffer.first().postTimeMs < cutoff) {
            buffer.removeFirst()
        }
    }

    @Synchronized
    fun emit(event: Map<String, Any?>) {
        val currentSink = sink
        if (currentSink == null) {
            prune()
            buffer.addLast(
                Buffered(event, (event["postTime"] as? Long) ?: System.currentTimeMillis())
            )
            while (buffer.size > MAX_BUFFERED_EVENTS) buffer.removeFirst()
            return
        }
        // Bind this callback to the sink instance active right now — if a
        // new listener replaces it before the main-thread post runs, the
        // event must not be delivered to the new (unrelated) listener.
        mainHandler.post {
            if (sink === currentSink) currentSink.success(event)
        }
    }
}
