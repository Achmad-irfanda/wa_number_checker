package com.wachecker.wa_number_checker

import android.accounts.Account
import android.accounts.AccountManager
import android.animation.ObjectAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentProviderOperation
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.PixelFormat
import android.graphics.drawable.Icon
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.ContactsContract
import android.provider.Settings
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ProgressBar
import android.widget.RemoteViews
import android.widget.TextView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Native side of `wa_number_checker`.
 *
 * Thin primitives only — orchestration (check-then-insert, timeout, cleanup,
 * cancel) lives in Dart so it stays testable and identical across consumers.
 * Proven in the `wa_poc` field test incl. Samsung cloud-default + power-save.
 */
class WaNumberCheckerPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var eventChannel: EventChannel? = null
    private lateinit var appContext: Context
    private val io = CoroutineScope(Dispatchers.IO)
    private val main = Handler(Looper.getMainLooper())
    private var observer: ContentObserver? = null
    private var sink: EventChannel.EventSink? = null
    private var progressTick: Runnable? = null
    private var overlayView: View? = null
    private var overlayProgress: ObjectAnimator? = null

    companion object {
        const val TEMP_ACCOUNT_TYPE = "com.wa_checker.temp"
        const val TEMP_ACCOUNT_NAME = "wa_temp"
        val WA_ACCOUNT_TYPES = setOf("com.whatsapp", "com.whatsapp.w4b")
        const val RETURN_CHANNEL_ID = "wa_number_checker_return"
        const val RETURN_NOTICE_ID = 0x57A1
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "wa_number_checker/methods")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "wa_number_checker/events")
        eventChannel?.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(a: Any?, s: EventChannel.EventSink?) {
                    sink = s
                }
                override fun onCancel(a: Any?) {
                    sink = null
                }
            },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        unregisterObserver()
        stopProgress()
        hideOverlay()
        channel.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
    }

    // ---- dispatch ----
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "normalize" -> {
                result.success(normalize(call.argument<String>("phone") ?: ""))
            }
            "getDeviceInfo" -> io.launch { reply(result) { getDeviceInfo() } }
            "checkExisting" -> {
                val raw = call.argument<String>("phone") ?: ""
                io.launch { reply(result) { checkExisting(normalize(raw)) } }
            }
            "insertTemp" -> {
                val raw = call.argument<String>("phone") ?: ""
                val tag = call.argument<String>("tag") ?: "WA_CHECK"
                val maxStored = call.argument<Number>("maxStored")?.toInt() ?: 100
                io.launch {
                    reply(result) { insertTemp(normalize(raw), dialable(raw), tag, maxStored) }
                }
            }
            "deleteContact" -> {
                val id = (call.argument<Number>("contactId") ?: 0).toLong()
                io.launch { reply(result) { deleteTemp(id) } }
            }
            "ensureTempAccount" -> io.launch { reply(result) { ensureTempAccount(); true } }
            "startObserver" -> {
                unregisterObserver()
                observer = object : ContentObserver(main) {
                    override fun onChange(selfChange: Boolean, uri: Uri?) {
                        main.post {
                            sink?.success(
                                mapOf(
                                    "at" to System.currentTimeMillis(),
                                    "uri" to (uri?.toString() ?: ""),
                                ),
                            )
                        }
                    }
                }
                appContext.contentResolver.registerContentObserver(
                    ContactsContract.RawContacts.CONTENT_URI,
                    true,
                    observer!!,
                )
                result.success(true)
            }
            "stopObserver" -> {
                unregisterObserver()
                result.success(true)
            }
            "openWhatsApp" -> io.launch { reply(result) { openWhatsApp() } }
            "showReturnNotice" -> {
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""
                val actionText = call.argument<String>("actionText") ?: "Kembali ke aplikasi"
                val style = call.argument<String>("style") ?: "standard"
                result.success(showReturnNotice(title, body, actionText, style))
            }
            "showProgressNotice" -> {
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""
                val durationMs = (call.argument<Number>("durationMs") ?: 0).toLong()
                val actionText = call.argument<String>("actionText") ?: "Kembali ke aplikasi"
                val style = call.argument<String>("style") ?: "standard"
                result.success(showProgressNotice(title, body, durationMs, actionText, style))
            }
            "cancelReturnNotice" -> {
                stopProgress()
                notifications().cancel(RETURN_NOTICE_ID)
                result.success(true)
            }
            "setNoticeActionVisible" -> {
                val visible = call.argument<Boolean>("visible") ?: true
                setNoticeActionVisible(visible)
                result.success(true)
            }
            "bringAppToForeground" -> {
                result.success(bringAppToForeground())
            }
            "canDrawOverlays" -> {
                result.success(Settings.canDrawOverlays(appContext))
            }
            "openOverlaySettings" -> {
                result.success(openOverlaySettings())
            }
            "showOverlay" -> {
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""
                val durationMs = (call.argument<Number>("durationMs") ?: 0).toLong()
                val actionText = call.argument<String>("actionText") ?: "Kembali ke aplikasi"
                result.success(showOverlay(title, body, durationMs, actionText))
            }
            "hideOverlay" -> {
                hideOverlay()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun reply(result: Result, block: () -> Any?) {
        try {
            val v = block()
            main.post { result.success(v) }
        } catch (e: Exception) {
            main.post { result.error("NATIVE_FAIL", e.message, null) }
        }
    }

    private fun unregisterObserver() {
        observer?.let {
            try {
                appContext.contentResolver.unregisterContentObserver(it)
            } catch (_: Exception) {
            }
        }
        observer = null
    }

    // ---- helpers ----

    private fun normalize(raw: String): String {
        var d = raw.filter { it.isDigit() }
        if (d.startsWith("08")) d = "62" + d.substring(1)
        return d
    }

    /**
     * Bentuk nomor yang disimpan ke kontak. Wajib ber-"+": tanpa itu WA
     * menafsirkan nomor pendek sebagai nomor lokal, mis. `62811460943`
     * dibaca `+6262811460943` sehingga nomor yang terdaftar tidak ketemu.
     */
    private fun dialable(raw: String): String {
        val d = normalize(raw)
        return if (raw.trim().startsWith("+") || d.startsWith("62")) "+$d" else d
    }

    private fun ensureTempAccount(): Account {
        val am = AccountManager.get(appContext)
        val acc = Account(TEMP_ACCOUNT_NAME, TEMP_ACCOUNT_TYPE)
        val exists = am.getAccountsByType(TEMP_ACCOUNT_TYPE).any { it.name == TEMP_ACCOUNT_NAME }
        if (!exists) {
            val ok = am.addAccountExplicitly(acc, null, null)
            if (!ok) throw IllegalStateException("gagal bikin akun temp $TEMP_ACCOUNT_TYPE")
        }
        return acc
    }

    /**
     * Buka WA ke layar. WA baru mengecek kontak baru ke servernya saat
     * tampil di depan; di background ia tidak bereaksi pada perubahan kontak.
     */
    private fun openWhatsApp(): Boolean {
        val cr = appContext.contentResolver
        val installed = WA_ACCOUNT_TYPES.filter { isInstalled(it) }
        val pkg = installed.firstOrNull { isActive(cr, it) } ?: installed.firstOrNull()
            ?: return false
        val intent = appContext.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return true
    }

    private var isActionVisible: Boolean = true
    private var currentBigViews: RemoteViews? = null
    private var currentNoticeBuilder: Notification.Builder? = null
    private var lastProgressTitle: String = ""
    private var lastProgressBody: String = ""
    private var lastProgressActionText: String = "Kembali ke aplikasi"
    private var lastProgressDurationMs: Long = 0
    private var lastProgressStyle: String = "standard"
    private var lastStartElapsed: Long = 0

    private fun notifications(): NotificationManager =
        appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun stopProgress() {
        progressTick?.let { main.removeCallbacks(it) }
        progressTick = null
        currentBigViews = null
        currentNoticeBuilder = null
        isActionVisible = true
    }

    /**
     * Tampilkan atau sembunyikan tombol "kembali ke aplikasi" secara dinamis.
     * Tombol hanya ditampilkan saat user berada di luar app (mis. di WhatsApp).
     */
    private fun setNoticeActionVisible(visible: Boolean) {
        if (isActionVisible == visible) return
        isActionVisible = visible
        if (progressTick != null) {
            updateProgressNotification()
        }
    }

    private fun updateProgressNotification() {
        val nm = notifications()
        if (!nm.areNotificationsEnabled()) return
        val total = lastProgressDurationMs.coerceAtLeast(1)
        val elapsed = SystemClock.elapsedRealtime() - lastStartElapsed
        val progress = (elapsed * 100 / total).toInt().coerceIn(0, 100)

        if (lastProgressStyle == "custom" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val bigViews = currentBigViews ?: return
            val builder = currentNoticeBuilder ?: return

            bigViews.setViewVisibility(
                R.id.wa_notice_btn_action,
                if (isActionVisible) View.VISIBLE else View.GONE,
            )
            builder.setCustomContentView(bigViews)
            builder.setCustomBigContentView(bigViews)
            builder.setCustomHeadsUpContentView(bigViews)
            nm.notify(RETURN_NOTICE_ID, builder.build())
        } else {
            val tap = getReturnPendingIntent() ?: return
            val builder = baseBuilder() ?: return
            builder.setOngoing(true).setOnlyAlertOnce(true)
            builder.setContentTitle(lastProgressTitle)
            builder.setContentText(lastProgressBody)
            builder.setStyle(Notification.BigTextStyle().bigText(lastProgressBody))
            builder.setUsesChronometer(true)
            builder.setWhen(System.currentTimeMillis() - elapsed)
            builder.setProgress(100, progress, false)

            if (isActionVisible) {
                val icon = Icon.createWithResource(appContext, appContext.applicationInfo.icon)
                val action = Notification.Action.Builder(
                    icon,
                    lastProgressActionText,
                    tap,
                ).build()
                builder.addAction(action)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setTimeoutAfter((total - elapsed).coerceAtLeast(0) + 5_000)
            }
            currentNoticeBuilder = builder
            nm.notify(RETURN_NOTICE_ID, builder.build())
        }
    }

    private fun getReturnPendingIntent(): PendingIntent? {
        val launch = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        } ?: return null
        return PendingIntent.getActivity(
            appContext,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Kerangka dasar notifikasi (channel IMPORTANCE_HIGH untuk heads-up banner
     * + tap intent kembali ke app consumer).
     */
    private fun baseBuilder(): Notification.Builder? {
        val nm = notifications()
        if (!nm.areNotificationsEnabled()) return null
        val tap = getReturnPendingIntent() ?: return null

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    RETURN_CHANNEL_ID,
                    "Verifikasi WhatsApp",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Status verifikasi nomor WhatsApp"
                    enableVibration(true)
                }
                nm.createNotificationChannel(channel)
                Notification.Builder(appContext, RETURN_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(appContext)
            }
        @Suppress("DEPRECATION")
        builder.setPriority(Notification.PRIORITY_MAX)
        builder.setCategory(Notification.CATEGORY_CALL)
        builder.setFullScreenIntent(tap, false)
        return builder
            .setSmallIcon(appContext.applicationInfo.icon)
            .setContentIntent(tap)
    }

    /**
     * Bawa app consumer kembali ke foreground saat verifikasi selesai.
     * Notifikasi hasil tidak ditutup di sini: `startActivity` bisa diblokir
     * Android tanpa error, dan notifikasi itu satu-satunya jalan kembali.
     */
    private fun bringAppToForeground(): Boolean {
        stopProgress()
        val pm = appContext.packageManager
        val launch = pm.getLaunchIntentForPackage(appContext.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        } ?: return false
        return try {
            appContext.startActivity(launch)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Izin overlay tidak punya dialog runtime: user mengaktifkannya sendiri
     * di Settings. Permission-nya dideklarasikan app consumer, bukan library.
     */
    private fun openOverlaySettings(): Boolean {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${appContext.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            appContext.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun windowManager(): WindowManager =
        appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    /**
     * Kartu status di atas WA. Dipanggil ulang untuk mengganti isi kartu yang
     * sudah tampil; [durationMs] 0 berarti tanpa progress (kartu hasil).
     */
    private fun showOverlay(
        title: String,
        body: String,
        durationMs: Long,
        actionText: String,
    ): Boolean {
        if (!Settings.canDrawOverlays(appContext)) return false
        return try {
            val view = overlayView ?: createOverlay()
            view.findViewById<TextView>(R.id.wa_overlay_title).text = title
            view.findViewById<TextView>(R.id.wa_overlay_body).text = body
            view.findViewById<Button>(R.id.wa_overlay_btn_action).text = actionText
            val progress = view.findViewById<ProgressBar>(R.id.wa_overlay_progress)
            overlayProgress?.cancel()
            overlayProgress = null
            progress.visibility = if (durationMs > 0) View.VISIBLE else View.GONE
            if (durationMs > 0) {
                overlayProgress = ObjectAnimator.ofInt(progress, "progress", 0, 100).apply {
                    duration = durationMs
                    start()
                }
            }
            true
        } catch (_: Exception) {
            hideOverlay()
            false
        }
    }

    private fun createOverlay(): View {
        val themed = ContextThemeWrapper(appContext, android.R.style.Theme_Material_Light)
        val view = LayoutInflater.from(themed).inflate(R.layout.wa_overlay_card, null)
        // Kartu ditutup `onResume` di Dart, jadi tetap ada kalau kembali gagal.
        view.findViewById<Button>(R.id.wa_overlay_btn_action)
            .setOnClickListener { bringAppToForeground() }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP }
        windowManager().addView(view, params)
        overlayView = view
        return view
    }

    private fun hideOverlay() {
        overlayProgress?.cancel()
        overlayProgress = null
        overlayView?.let {
            try {
                windowManager().removeView(it)
            } catch (_: Exception) {
            }
        }
        overlayView = null
    }

    /**
     * Notifikasi hasil ("ketuk untuk kembali" / "kembali ke aplikasi").
     * Mendukung [style]:
     * - "standard": Pendekatan A (BigTextStyle + Action Button).
     * - "custom": Pendekatan B (Custom RemoteViews layout + Action Button).
     */
    private fun showReturnNotice(
        title: String,
        body: String,
        actionText: String = "Kembali ke aplikasi",
        style: String = "standard",
    ): Boolean {
        stopProgress()
        // Dibatalkan dulu: update di ID yang sama tidak selalu memunculkan
        // heads-up baru bila banner progress sudah turun ke shade.
        notifications().cancel(RETURN_NOTICE_ID)
        val builder = baseBuilder() ?: return false
        val tap = getReturnPendingIntent() ?: return false
        builder.setAutoCancel(true)

        if (style == "custom" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val remoteViews = RemoteViews(appContext.packageName, R.layout.wa_notification_custom)
                remoteViews.setTextViewText(R.id.wa_notice_title, title)
                remoteViews.setTextViewText(R.id.wa_notice_body, body)
                remoteViews.setTextViewText(R.id.wa_notice_btn_action, actionText)
                remoteViews.setViewVisibility(R.id.wa_notice_chronometer, View.GONE)
                remoteViews.setViewVisibility(R.id.wa_notice_progress, View.GONE)
                remoteViews.setOnClickPendingIntent(R.id.wa_notice_btn_action, tap)
                remoteViews.setOnClickPendingIntent(R.id.wa_notice_container, tap)

                builder.setStyle(Notification.DecoratedCustomViewStyle())
                builder.setCustomContentView(remoteViews)
                builder.setCustomBigContentView(remoteViews)
                builder.setCustomHeadsUpContentView(remoteViews)
            } catch (_: Exception) {
                // Fallback to standard style if RemoteViews fails
                applyStandardReturnStyle(builder, title, body, actionText, tap)
            }
        } else {
            applyStandardReturnStyle(builder, title, body, actionText, tap)
        }

        notifications().notify(RETURN_NOTICE_ID, builder.build())
        return true
    }

    private fun applyStandardReturnStyle(
        builder: Notification.Builder,
        title: String,
        body: String,
        actionText: String,
        tap: PendingIntent,
    ) {
        builder.setContentTitle(title)
        builder.setContentText(body)
        builder.setStyle(Notification.BigTextStyle().bigText(body))
        val icon = Icon.createWithResource(appContext, appContext.applicationInfo.icon)
        val action = Notification.Action.Builder(
            icon,
            actionText,
            tap,
        ).build()
        builder.addAction(action)
    }

    /**
     * Notifikasi progress selama menunggu WA:
     * - "standard": Pendekatan A (BigTextStyle, real-time Chronometer timer,
     *   progress bar, dan action button [Kembali ke aplikasi]).
     * - "custom": Pendekatan B (Custom RemoteViews layout dengan layout lebih
     *   luas, title, timer, body, progress bar, dan button kembali).
     */
    private fun showProgressNotice(
        title: String,
        body: String,
        durationMs: Long,
        actionText: String = "Kembali ke aplikasi",
        style: String = "standard",
    ): Boolean {
        stopProgress()
        val builder = baseBuilder() ?: return false
        val tap = getReturnPendingIntent() ?: return false
        val total = durationMs.coerceAtLeast(1)
        val startElapsed = SystemClock.elapsedRealtime()

        lastProgressTitle = title
        lastProgressBody = body
        lastProgressActionText = actionText
        lastProgressDurationMs = durationMs
        lastProgressStyle = style
        lastStartElapsed = startElapsed
        isActionVisible = true

        builder.setOngoing(true).setOnlyAlertOnce(true)

        if (style == "custom" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val bigViews = RemoteViews(appContext.packageName, R.layout.wa_notification_custom)
                bigViews.setTextViewText(R.id.wa_notice_title, title)
                bigViews.setTextViewText(R.id.wa_notice_body, body)
                bigViews.setTextViewText(R.id.wa_notice_btn_action, actionText)
                bigViews.setChronometer(R.id.wa_notice_chronometer, startElapsed, null, true)
                bigViews.setViewVisibility(
                    R.id.wa_notice_btn_action,
                    if (isActionVisible) View.VISIBLE else View.GONE,
                )
                bigViews.setOnClickPendingIntent(R.id.wa_notice_btn_action, tap)
                bigViews.setOnClickPendingIntent(R.id.wa_notice_container, tap)

                builder.setStyle(Notification.DecoratedCustomViewStyle())
                builder.setCustomContentView(bigViews)
                builder.setCustomBigContentView(bigViews)
                builder.setCustomHeadsUpContentView(bigViews)

                currentBigViews = bigViews
                currentNoticeBuilder = builder

                val tick = object : Runnable {
                    override fun run() {
                        val elapsed = SystemClock.elapsedRealtime() - startElapsed
                        val progress = (elapsed * 100 / total).toInt().coerceIn(0, 100)
                        bigViews.setProgressBar(R.id.wa_notice_progress, 100, progress, false)
                        bigViews.setViewVisibility(
                            R.id.wa_notice_btn_action,
                            if (isActionVisible) View.VISIBLE else View.GONE,
                        )
                        builder.setCustomContentView(bigViews)
                        builder.setCustomBigContentView(bigViews)
                        builder.setCustomHeadsUpContentView(bigViews)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            builder.setTimeoutAfter((total - elapsed).coerceAtLeast(0) + 5_000)
                        }
                        notifications().notify(RETURN_NOTICE_ID, builder.build())
                        if (elapsed < total) main.postDelayed(this, 500)
                    }
                }
                progressTick = tick
                tick.run()
                return true
            } catch (_: Exception) {
                // Fallback to standard
            }
        }

        // Standard Rich Notification (Pendekatan A)
        builder.setContentTitle(title)
        builder.setContentText(body)
        builder.setStyle(Notification.BigTextStyle().bigText(body))
        builder.setUsesChronometer(true)
        builder.setWhen(System.currentTimeMillis())

        if (isActionVisible) {
            val icon = Icon.createWithResource(appContext, appContext.applicationInfo.icon)
            val action = Notification.Action.Builder(
                icon,
                actionText,
                tap,
            ).build()
            builder.addAction(action)
        }
        currentNoticeBuilder = builder

        val tick = object : Runnable {
            override fun run() {
                val elapsed = SystemClock.elapsedRealtime() - startElapsed
                val progress = (elapsed * 100 / total).toInt().coerceIn(0, 100)
                // setNoticeActionVisible membuat builder baru; pakai yang terkini.
                val current = currentNoticeBuilder ?: builder
                current.setProgress(100, progress, false)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    current.setTimeoutAfter((total - elapsed).coerceAtLeast(0) + 5_000)
                }
                notifications().notify(RETURN_NOTICE_ID, current.build())
                if (elapsed < total) main.postDelayed(this, 500)
            }
        }
        progressTick = tick
        tick.run()
        return true
    }

    private fun isInstalled(pkg: String): Boolean =
        try {
            appContext.packageManager.getPackageInfo(pkg, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }

    private fun isActive(cr: ContentResolver, type: String): Boolean {
        return try {
            cr.query(
                ContactsContract.RawContacts.CONTENT_URI,
                arrayOf(ContactsContract.RawContacts._ID),
                "${ContactsContract.RawContacts.ACCOUNT_TYPE}=?",
                arrayOf(type),
                "${ContactsContract.RawContacts._ID} ASC LIMIT 1",
            )?.use { it.moveToFirst() } ?: false
        } catch (_: Exception) {
            try {
                cr.query(
                    ContactsContract.RawContacts.CONTENT_URI,
                    arrayOf(ContactsContract.RawContacts._ID),
                    "${ContactsContract.RawContacts.ACCOUNT_TYPE}=?",
                    arrayOf(type),
                    null,
                )?.use { it.moveToFirst() } ?: false
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun hasValidatedInternet(): Boolean {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork ?: return false
        val cap = cm.getNetworkCapabilities(net) ?: return false
        return cap.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            cap.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private fun getDeviceInfo(): Map<String, Any> {
        val cr = appContext.contentResolver
        val waIn = isInstalled("com.whatsapp")
        val w4bIn = isInstalled("com.whatsapp.w4b")
        val pm = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
        val tempReady = try {
            ensureTempAccount()
            true
        } catch (_: Exception) {
            false
        }
        return mapOf(
            "waInstalled" to waIn,
            "w4bInstalled" to w4bIn,
            "waActive" to (waIn && isActive(cr, "com.whatsapp")),
            "w4bActive" to (w4bIn && isActive(cr, "com.whatsapp.w4b")),
            "online" to hasValidatedInternet(),
            "powerSave" to pm.isPowerSaveMode,
            "tempAccountType" to TEMP_ACCOUNT_TYPE,
            "tempAccountReady" to tempReady,
        )
    }

    private fun checkExisting(normalized: String): Map<String, Any> {
        val cr = appContext.contentResolver
        val lookup = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(normalized),
        )
        // Satu nomor bisa ada di beberapa kontak; raw contact WA cukup
        // menempel di salah satunya, jadi semua hasil lookup diperiksa.
        val contactIds = linkedSetOf<Long>()
        cr.query(lookup, arrayOf(ContactsContract.PhoneLookup._ID), null, null, null)?.use {
            while (it.moveToNext()) contactIds.add(it.getLong(0))
        }
        // WA menyimpan JID di SYNC1 raw contact-nya. Raw contact itu bisa
        // tertinggal di kontak lain yang sudah tidak punya nomor, sehingga
        // tidak terjangkau PhoneLookup — cocokkan juga langsung lewat JID.
        val byContact =
            if (contactIds.isEmpty()) {
                ""
            } else {
                "${ContactsContract.RawContacts.CONTACT_ID} IN (${contactIds.joinToString(",")}) OR "
            }
        val detected = mutableSetOf<String>()
        var waContactId: Long? = null
        cr.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(
                ContactsContract.RawContacts.CONTACT_ID,
                ContactsContract.RawContacts.ACCOUNT_TYPE,
            ),
            "($byContact${ContactsContract.RawContacts.SYNC1}=?) AND " +
                "${ContactsContract.RawContacts.DELETED}=0",
            arrayOf("$normalized@s.whatsapp.net"),
            null,
        )?.use {
            while (it.moveToNext()) {
                when (it.getString(1)) {
                    "com.whatsapp" -> detected.add("whatsapp")
                    "com.whatsapp.w4b" -> detected.add("whatsappBusiness")
                    else -> continue
                }
                if (waContactId == null) waContactId = it.getLong(0)
            }
        }
        val contactId = waContactId ?: contactIds.firstOrNull()
        return buildMap {
            put("found", detected.isNotEmpty())
            put("detectedBy", detected.toList())
            if (contactId != null) put("contactId", contactId)
        }
    }

    /**
     * Hapus raw contact akun temp milik [contactId]. Sengaja tidak menghapus
     * lewat `Contacts.CONTENT_URI`: delete ber-selection di URI itu selalu
     * mengembalikan 0, dan menghapus seluruh kontak bisa ikut membuang kontak
     * asli user yang ter-agregasi. `CALLER_IS_SYNCADAPTER` → hapus permanen,
     * bukan sekadar ditandai `deleted=1`.
     */
    private fun deleteTemp(contactId: Long): Int {
        return appContext.contentResolver.delete(
            tempRawContactsUri(),
            "${ContactsContract.RawContacts.CONTACT_ID}=? AND " +
                "${ContactsContract.RawContacts.ACCOUNT_TYPE}=?",
            arrayOf(contactId.toString(), TEMP_ACCOUNT_TYPE),
        )
    }

    private fun tempRawContactsUri(): Uri =
        ContactsContract.RawContacts.CONTENT_URI.buildUpon()
            .appendQueryParameter(ContactsContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(ContactsContract.RawContacts.ACCOUNT_NAME, TEMP_ACCOUNT_NAME)
            .appendQueryParameter(ContactsContract.RawContacts.ACCOUNT_TYPE, TEMP_ACCOUNT_TYPE)
            .build()

    /**
     * Kontak temp disimpan sebagai cache: selama masih ada, WA mempertahankan
     * tandanya sehingga cek ulang nomor yang sama selesai di fast-path tanpa
     * membuka WA. Nomor yang sudah tersimpan dipakai ulang; begitu isi akun
     * temp mencapai [maxStored], semuanya dibuang sebelum insert baru.
     */
    private fun insertTemp(
        normalized: String,
        dialable: String,
        tag: String,
        maxStored: Int,
    ): Map<String, Any> {
        val cr = appContext.contentResolver
        val acc = ensureTempAccount()
        cr.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(ContactsContract.Data.RAW_CONTACT_ID, ContactsContract.Data.CONTACT_ID),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE}=? AND " +
                "${ContactsContract.Data.MIMETYPE}=? AND " +
                "${ContactsContract.CommonDataKinds.Phone.NUMBER} IN (?,?)",
            arrayOf(
                TEMP_ACCOUNT_TYPE,
                ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
                dialable,
                normalized,
            ),
            null,
        )?.use {
            if (it.moveToFirst()) {
                return mapOf(
                    "contactId" to it.getLong(1),
                    "rawContactId" to it.getLong(0),
                    "normalized" to normalized,
                    "reused" to true,
                    "at" to System.currentTimeMillis(),
                )
            }
        }
        val stored = cr.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(ContactsContract.RawContacts._ID),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE}=? AND " +
                "${ContactsContract.RawContacts.DELETED}=0",
            arrayOf(TEMP_ACCOUNT_TYPE),
            null,
        )?.use { it.count } ?: 0
        if (stored >= maxStored) {
            cr.delete(
                tempRawContactsUri(),
                "${ContactsContract.RawContacts.ACCOUNT_TYPE}=?",
                arrayOf(TEMP_ACCOUNT_TYPE),
            )
        }
        val ops = arrayListOf<ContentProviderOperation>()
        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, acc.type)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, acc.name)
                .build(),
        )
        val name = "$tag ${System.currentTimeMillis() % 100000}"
        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(
                    ContactsContract.Data.MIMETYPE,
                    ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE,
                )
                .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, name)
                .build(),
        )
        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(
                    ContactsContract.Data.MIMETYPE,
                    ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
                )
                .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, dialable)
                .withValue(
                    ContactsContract.CommonDataKinds.Phone.TYPE,
                    ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE,
                )
                .build(),
        )
        val res = cr.applyBatch(ContactsContract.AUTHORITY, ops)
        val rawUri = res[0].uri ?: throw IllegalStateException("insert gagal: uri null")
        val rawId = rawUri.lastPathSegment?.toLong() ?: -1L
        var contactId = -1L
        var storedType: String? = null
        var storedName: String? = null
        cr.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(
                ContactsContract.RawContacts.CONTACT_ID,
                ContactsContract.RawContacts.ACCOUNT_TYPE,
                ContactsContract.RawContacts.ACCOUNT_NAME,
            ),
            "${ContactsContract.RawContacts._ID}=?",
            arrayOf(rawId.toString()),
            null,
        )?.use {
            if (it.moveToFirst()) {
                contactId = it.getLong(0)
                storedType = it.getString(1)
                storedName = it.getString(2)
            }
        }
        return mapOf(
            "contactId" to contactId,
            "rawContactId" to rawId,
            "name" to name,
            "normalized" to normalized,
            "storedAccountType" to (storedType ?: "null(???)"),
            "storedAccountName" to (storedName ?: "null(???)"),
            "isTempAccount" to (storedType == TEMP_ACCOUNT_TYPE),
            "at" to System.currentTimeMillis(),
        )
    }
}
