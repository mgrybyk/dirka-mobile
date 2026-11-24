package com.mgrybyk.dirka

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mgrybyk.dirka/app_info",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "appVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success(
                        mapOf(
                            "version" to info.versionName,
                            "buildNumber" to buildNumber(info).toString(),
                        ),
                    )
                }
                "openUpstreamRepository" -> {
                    try {
                        startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/mgrybyk/node-tunnel")),
                        )
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun buildNumber(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) {
        info.longVersionCode
    } else {
        info.versionCode.toLong()
    }
}
