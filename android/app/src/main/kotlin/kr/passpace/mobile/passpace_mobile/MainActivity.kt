package kr.passpace.mobile.passpace_mobile

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var studyTimer: StudyTimerBridge? = null
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        studyTimer?.close()
        studyTimer = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        studyTimer?.onIntent(intent)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        studyTimer?.onPermission(requestCode)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        studyTimer = StudyTimerBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kr.passpace.mobile/navigation")
            .setMethodCallHandler { call, result ->
                if (call.method != "openAdminPage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val raw = (call.arguments as? Map<*, *>)?.get("url") as? String
                val uri = raw?.let { Uri.parse(it) }
                val debug = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                val localHttp = debug && uri?.scheme == "http" &&
                    uri.host in setOf("10.0.2.2", "127.0.0.1", "localhost")
                if (uri == null || uri.host.isNullOrEmpty() ||
                    (uri.scheme != "https" && !localHttp) ||
                    !uri.userInfo.isNullOrEmpty() || uri.path != "/admin/collect" ||
                    uri.encodedQuery != null || uri.encodedFragment != null ||
                    (uri.port != -1 && uri.port !in 1..65535)) {
                    result.error("invalid_admin_url", "Invalid admin page address", null)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                    result.success(null)
                } catch (_: ActivityNotFoundException) {
                    result.error("browser_unavailable", "No browser is available", null)
                } catch (_: SecurityException) {
                    result.error("browser_unavailable", "The browser could not be opened", null)
                }
            }
    }
}
