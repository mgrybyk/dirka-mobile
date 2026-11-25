package com.mgrybyk.dirka

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONObject
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal data class TunnelState(
    val status: String = "connecting",
    val active: Boolean = true,
    val stopping: Boolean = false,
    val error: String? = null,
) {
    fun toMessage() = mapOf(
        "status" to status, "active" to active, "stopping" to stopping, "error" to error,
    )
}

class TunnelService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val worker = ScheduledThreadPoolExecutor(1) { task -> Thread(task, "Dirka tunnels") }
    // Handles are accessed only on the worker. Service and registry state live on the main thread.
    private val handles = mutableMapOf<Long, Long>()
    private val owned = mutableSetOf<Long>()
    private val connectivity by lazy { getSystemService(ConnectivityManager::class.java) }
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private var networkRegistered = false
    private var foreground = false
    private var shownCount = 0
    private var latestStart = 0
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            main.post {
                if (foreground) worker.execute {
                    handles.values.forEach(TunnelNative::networkAvailable)
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        worker.scheduleWithFixedDelay(::pollHandles, 0, 200, TimeUnit.MILLISECONDS)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStart = startId
        launchRequested = false
        val starts = pending.toMap()
        pending.clear()
        if (starts.isEmpty() && !foreground) {
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        try {
            if (!foreground) enterForeground()
        } catch (_: RuntimeException) {
            for ((id, config) in starts) {
                config.fill(0)
                setState(id, stopped("Android could not start the tunnel service. Reopen Dirka and try again."))
            }
            leaveForeground()
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        instance = this
        for ((id, config) in starts) {
            if (states[id]?.stopping == true) {
                config.fill(0)
                setState(id, null)
            } else {
                submitStart(id, config)
            }
        }
        refreshNotification()
        return START_NOT_STICKY
    }

    private fun enterForeground() {
        notifications.createNotificationChannel(
            NotificationChannel(
                CHANNEL, getString(R.string.tunnel_notification_channel),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        val count = activeCount()
        val notification = notification(count)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foreground = true
        shownCount = count
        connectivity.registerDefaultNetworkCallback(networkCallback)
        networkRegistered = true
    }

    private fun submitStart(id: Long, config: ByteArray) {
        owned.add(id)
        worker.execute {
            try {
                val handle = TunnelNative.start(config)
                if (handle == 0L) {
                    report(id, stopped("The native tunnel could not start. Check the client configuration."))
                } else {
                    handles[id] = handle
                }
            } catch (_: LinkageError) {
                report(id, stopped("Could not load the native tunnel engine. Reinstall Dirka."))
            } finally {
                config.fill(0)
            }
        }
    }

    private fun submitStop(id: Long) {
        worker.execute { handles[id]?.let(TunnelNative::stop) }
    }

    private fun pollHandles() {
        val iterator = handles.iterator()
        while (iterator.hasNext()) {
            val (id, handle) = iterator.next()
            val state = try {
                val data = TunnelNative.pollSnapshot(handle) ?: continue
                val json = JSONObject(data.decodeToString())
                val status = json.getString("status")
                val problem = if (json.isNull("error")) null else json.getString("error")
                if (status == "stopped") stopped(problem)
                else TunnelState(status = status, error = problem)
            } catch (_: Exception) {
                stopped("Could not read the native tunnel state.")
            }
            if (!state.active) {
                TunnelNative.destroy(handle)
                iterator.remove()
            }
            report(id, state)
        }
    }

    private fun report(id: Long, state: TunnelState) {
        main.post {
            if (!owned.contains(id)) return@post
            if (!state.active) {
                owned.remove(id)
                setState(id, state.takeIf { it.error != null })
                refreshNotification()
            } else if (states[id]?.stopping != true) {
                setState(id, state)
            }
        }
    }

    private fun refreshNotification(force: Boolean = false) {
        if (!foreground) return
        val count = activeCount()
        if (count == 0) {
            leaveForeground()
            stopSelfResult(latestStart)
        } else if (shownCount != count || force) {
            shownCount = count
            notifications.notify(NOTIFICATION_ID, notification(count))
        }
    }

    private fun leaveForeground() {
        if (networkRegistered) {
            connectivity.unregisterNetworkCallback(networkCallback)
            networkRegistered = false
        }
        if (foreground) {
            foreground = false
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    private fun notification(count: Int): Notification {
        val open = Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pendingOpen = PendingIntent.getActivity(
            this, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL)
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .setSmallIcon(R.drawable.ic_tunnel_status)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(resources.getQuantityString(R.plurals.tunnel_active_clients, count, count))
            .setContentIntent(pendingOpen)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .build()
    }

    override fun onDestroy() {
        leaveForeground()
        if (instance === this) instance = null
        for (id in owned) setState(id, stopped("Android stopped the tunnel service. Connect again to resume."))
        owned.clear()
        worker.execute {
            handles.values.forEach(TunnelNative::destroy)
            handles.clear()
        }
        worker.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "tunnels"
        private const val NOTIFICATION_ID = 1
        private var instance: TunnelService? = null
        private var launchRequested = false
        private val pending = mutableMapOf<Long, ByteArray>()
        private val states = mutableMapOf<Long, TunnelState>()
        private val observers = mutableSetOf<(Map<Long, Map<String, Any?>>) -> Unit>()

        internal fun observe(observer: (Map<Long, Map<String, Any?>>) -> Unit) {
            observers.add(observer)
            observer(snapshot())
        }

        internal fun unobserve(observer: (Map<Long, Map<String, Any?>>) -> Unit) {
            observers.remove(observer)
        }

        internal fun start(context: Context, id: Long, config: ByteArray) {
            if (states[id]?.active == true) {
                config.fill(0)
                return
            }
            setState(id, TunnelState())
            val running = instance?.takeIf { it.foreground }
            if (running != null) {
                running.submitStart(id, config)
                running.refreshNotification()
                return
            }

            pending[id] = config
            if (launchRequested) return
            try {
                val intent = Intent(context, TunnelService::class.java)
                context.startForegroundService(intent)
                launchRequested = true
            } catch (_: RuntimeException) {
                pending.remove(id)?.fill(0)
                setState(id, stopped("Could not start forwarding. Keep Dirka visible and try again."))
            }
        }

        internal fun stop(id: Long) {
            val state = states[id] ?: return
            if (!state.active || state.stopping) return
            setState(id, state.copy(stopping = true))
            instance?.submitStop(id)
        }

        internal fun clearStopped(id: Long) {
            if (states[id]?.active == false) setState(id, null)
        }

        internal fun notificationPermissionChanged() {
            instance?.refreshNotification(force = true)
        }

        private fun activeCount() = states.values.count { it.active }
        internal fun snapshot() = states.mapValues { (_, state) -> state.toMessage() }
        private fun stopped(error: String?) = TunnelState(status = "stopped", active = false, error = error)

        private fun setState(id: Long, state: TunnelState?) {
            if (states[id] == state) return
            if (state == null) states.remove(id) else states[id] = state
            val update = snapshot()
            observers.toList().forEach { it(update) }
        }
    }
}
