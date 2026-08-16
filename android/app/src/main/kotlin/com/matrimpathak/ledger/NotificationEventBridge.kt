package com.matrimpathak.ledger

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Process-wide holder for the Dart-side [EventChannel.EventSink], set by
 * MainActivity while a Dart listener is attached and cleared when it
 * detaches. LedgerNotificationListenerService runs as its own Android
 * service instance (independent of whether MainActivity/the Flutter engine
 * is currently alive) and pushes extracted events through here — if no
 * sink is attached, events are simply dropped, never queued. Nothing here
 * is persisted; this is a live forwarding pipe only.
 */
object NotificationEventBridge {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(newSink: EventChannel.EventSink?) {
        sink = newSink
    }

    fun emit(event: Map<String, Any?>) {
        if (sink == null) return
        mainHandler.post {
            // Re-read the volatile field on the main thread in case it was
            // detached between the background post and this callback.
            sink?.success(event)
        }
    }
}
