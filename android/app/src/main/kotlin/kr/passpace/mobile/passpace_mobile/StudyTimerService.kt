package kr.passpace.mobile.passpace_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock

class StudyTimerService : Service() {
    companion object {
        const val CHANNEL = "study-timer-running-v1"
        const val ID = 17041
        private const val PAUSE = "kr.passpace.mobile.study-timer.PAUSE"
        private const val RESUME = "kr.passpace.mobile.study-timer.RESUME"
        var actionHandler: ((String, Boolean) -> Unit)? = null
        private var current: StudyTimerService? = null
        private val retired = mutableSetOf<String>()
        private var lastOwner: String? = null
        private var lastElapsed = 0L
        fun stopOwner(owner: String) {
            retired.add(owner)
            if (current?.owner == owner) current?.stopNow()
        }
        fun attachClient() { current?.let { stopOwner(it.owner) } }
        fun elapsed(owner: String): Long? =
            current?.takeIf { it.owner == owner }?.elapsedMillis()
                ?: if (lastOwner == owner) lastElapsed else null
    }
    private var owner = ""
    private var initial = 0L
    private var startedElapsed = 0L
    private var startedWall = 0L
    private var endWall = 0L
    private var running = false
    private var actionVersion = 0
    private val handler = Handler(Looper.getMainLooper())
    private val deadline = Runnable { stopNow() }
    private val screen = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (System.currentTimeMillis() >= endWall) stopNow()
        }
    }
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL, "진행 중인 학습", NotificationManager.IMPORTANCE_LOW)
            channel.description = "측정 중인 공부시간을 표시합니다."
            channel.setSound(null, null)
            channel.enableVibration(false)
            manager.createNotificationChannel(channel)
        }
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON).apply { addAction(Intent.ACTION_TIME_CHANGED) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(screen, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(screen, filter)
    }
    private fun elapsedMillis(): Long = if (!running) initial else
        (initial + (SystemClock.elapsedRealtime() - startedElapsed)
            .coerceIn(0L, (endWall - startedWall).coerceAtLeast(0L))).coerceIn(0L, 86400000L)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nextOwner = intent?.getStringExtra("owner")
        val action = intent?.action
        if (action == PAUSE || action == RESUME) {
            if (current !== this) {
                stopSelf(startId)
            } else if (nextOwner == owner && actionVersion == intent?.getIntExtra("version", -1) &&
                System.currentTimeMillis() < endWall && running == (action == PAUSE)) {
                actionHandler?.invoke(owner, action == RESUME)
            }
            return START_NOT_STICKY
        }
        val elapsed = intent?.getLongExtra("elapsedMs", -1L) ?: -1L
        val end = intent?.getLongExtra("endUtcMs", -1L) ?: -1L
        val wall = System.currentTimeMillis()
        if (nextOwner.isNullOrBlank() || nextOwner.length > 128 || nextOwner in retired ||
            elapsed !in 0L..86400000L || end <= wall || end - wall > 86400000L) {
            if (current == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        owner = nextOwner; initial = elapsed; startedElapsed = SystemClock.elapsedRealtime()
        startedWall = wall; endWall = end; current = this
        running = intent?.getBooleanExtra("running", true) ?: true
        val open = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("open_study_timer", true)
        val pending = PendingIntent.getActivity(this, ID, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        actionVersion++
        val control = Intent(this, StudyTimerService::class.java)
            .setAction(if (running) PAUSE else RESUME)
            .setData(Uri.Builder().scheme("passpace-timer").authority("control").appendPath(owner).build())
            .putExtra("owner", owner)
            .putExtra("version", actionVersion)
        val controlPending = PendingIntent.getService(this, ID, control,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        builder.setSmallIcon(R.drawable.ic_study_timer)
            .setContentTitle(if (running) "집중 타이머 · 측정 중" else "집중 타이머 · 일시정지")
            .setContentText(intent?.getStringExtra("subject")?.take(120) ?: "과목 연결 없음")
            .setContentIntent(pending).setOngoing(true).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE).setVisibility(Notification.VISIBILITY_PRIVATE)
            .setWhen(wall - elapsed).setShowWhen(running).setUsesChronometer(running)
            .addAction(Notification.Action.Builder(
                android.graphics.drawable.Icon.createWithResource(this,
                    if (running) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play),
                if (running) "일시정지" else "재개", controlPending).build())
        if (!running) {
            val seconds = elapsed / 1000L
            builder.setSubText(String.format(java.util.Locale.ROOT, "%02d:%02d:%02d",
                seconds / 3600L, seconds / 60L % 60L, seconds % 60L))
        }
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(end - wall)
        if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        if (Build.VERSION.SDK_INT >= 34) startForeground(ID, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(ID, builder.build())
        handler.removeCallbacks(deadline)
        handler.postDelayed(deadline, end - wall)
        return START_NOT_STICKY
    }
    private fun finishNotification() {
        if (current === this) {
            lastOwner = owner; lastElapsed = elapsedMillis(); current = null
        }
        handler.removeCallbacks(deadline)
        stopForeground(STOP_FOREGROUND_REMOVE)
    }
    private fun stopNow() { finishNotification(); stopSelf() }
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopNow()
        super.onTaskRemoved(rootIntent)
    }
    override fun onDestroy() {
        finishNotification()
        unregisterReceiver(screen)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
