package kr.passpace.mobile.passpace_mobile

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class StudyTimerBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "kr.passpace.mobile/study-timer")
    private var permission: MethodChannel.Result? = null
    private var pendingOpen = activity.intent?.getBooleanExtra("open_study_timer", false) == true
    companion object { const val PERMISSION = 17042 }
    init {
        StudyTimerService.attachClient()
        activity.intent?.removeExtra("open_study_timer")
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "attach" -> { StudyTimerService.attachClient(); result.success(null) }
                    "takePendingOpen" -> { val open = pendingOpen; pendingOpen = false; result.success(open) }
                    "notificationAllowed" -> result.success(allowed())
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (permission != null) result.error("request_pending", "Permission request pending", null)
                            else { permission = result; activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION) }
                        } else result.success(allowed())
                    }
                    "start" -> {
                        val owner = call.argument<String>("owner") ?: error("Missing owner")
                        val intent = Intent(activity, StudyTimerService::class.java)
                            .putExtra("owner", owner).putExtra("subject", call.argument<String>("subject"))
                            .putExtra("elapsedMs", call.argument<Number>("elapsedMs")?.toLong() ?: -1L)
                            .putExtra("endUtcMs", call.argument<Number>("endUtcMs")?.toLong() ?: -1L)
                        if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(intent) else activity.startService(intent)
                        result.success(null)
                    }
                    "stop" -> { StudyTimerService.stopOwner(call.argument<String>("owner") ?: ""); result.success(null) }
                    "elapsed" -> result.success(StudyTimerService.elapsed(call.argument<String>("owner") ?: ""))
                    "openSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("timer_notification", "Study notification unavailable", null) }
        }
    }
    private fun allowed(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val manager = activity.getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(StudyTimerService.CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
    }
    fun onPermission(requestCode: Int) {
        if (requestCode != PERMISSION) return
        val result = permission; permission = null; result?.success(allowed())
    }
    fun onIntent(intent: Intent) {
        if (!intent.getBooleanExtra("open_study_timer", false)) return
        intent.removeExtra("open_study_timer"); pendingOpen = true
        channel.invokeMethod("openTimer", null)
    }
}
