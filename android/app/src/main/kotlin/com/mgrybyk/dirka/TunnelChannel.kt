package com.mgrybyk.dirka

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

internal class TunnelChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val commands = MethodChannel(messenger, "com.mgrybyk.dirka/tunnels")
    private val events = EventChannel(messenger, "com.mgrybyk.dirka/tunnel_states")
    private var observer: ((Map<Long, Map<String, Any?>>) -> Unit)? = null

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                detachObserver()
                val callback: (Map<Long, Map<String, Any?>>) -> Unit = { sink.success(it) }
                observer = callback
                TunnelService.observe(callback)
            }

            override fun onCancel(arguments: Any?) {
                detachObserver()
            }
        })
        commands.setMethodCallHandler { call, result ->
            if (call.method == "snapshot") {
                result.success(TunnelService.snapshot())
                return@setMethodCallHandler
            }
            val id = call.argument<Number>("id")?.toLong()
            if (id == null || id < 1) {
                result.error("bad_id", "Invalid saved client ID.", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "start" -> {
                    val config = call.argument<ByteArray>("config")
                    if (config == null || config.isEmpty() || config.size > 4096) {
                        result.error("bad_config", "Invalid tunnel configuration.", null)
                    } else {
                        TunnelService.start(activity, id, config)
                        if (call.argument<Boolean>("requestNotifications") == true) requestNotifications()
                        result.success(null)
                    }
                }
                "stop" -> {
                    TunnelService.stop(id)
                    result.success(null)
                }
                "clearStopped" -> {
                    TunnelService.clearStopped(id)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotifications() {
        if (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) return

        val preferences = activity.getSharedPreferences("notification_prompt", Activity.MODE_PRIVATE)
        if (preferences.getBoolean("requested", false)) return
        preferences.edit().putBoolean("requested", true).apply()
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    private fun detachObserver() {
        observer?.let(TunnelService::unobserve)
        observer = null
    }

    fun detach() {
        detachObserver()
        events.setStreamHandler(null)
        commands.setMethodCallHandler(null)
    }

    companion object {
        const val NOTIFICATION_REQUEST = 1_001
    }
}
