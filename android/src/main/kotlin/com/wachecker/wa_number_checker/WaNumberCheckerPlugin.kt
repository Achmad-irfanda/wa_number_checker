package com.wachecker.wa_number_checker

import android.accounts.Account
import android.accounts.AccountManager
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
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.ContactsContract
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
                result.success(showReturnNotice(title, body))
            }
            "showProgressNotice" -> {
                val title = call.argument<String>("title") ?: ""
                val body = call.argument<String>("body") ?: ""
                val durationMs = (call.argument<Number>("durationMs") ?: 0).toLong()
                result.success(showProgressNotice(title, body, durationMs))
            }
            "cancelReturnNotice" -> {
                stopProgress()
                notifications().cancel(RETURN_NOTICE_ID)
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

    private fun notifications(): NotificationManager =
        appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun stopProgress() {
        progressTick?.let { main.removeCallbacks(it) }
        progressTick = null
    }

    /** Kerangka notifikasi yang membawa user kembali ke app consumer saat diketuk. */
    private fun noticeBuilder(title: String, body: String): Notification.Builder? {
        val nm = notifications()
        if (!nm.areNotificationsEnabled()) return null
        val launch = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)
            ?: return null
        val tap = PendingIntent.getActivity(
            appContext,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        RETURN_CHANNEL_ID,
                        "Verifikasi WhatsApp",
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                )
                Notification.Builder(appContext, RETURN_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(appContext).setPriority(Notification.PRIORITY_HIGH)
            }
        return builder
            .setSmallIcon(appContext.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(tap)
    }

    /** Notifikasi hasil ("ketuk untuk kembali"). False jika notifikasi diblokir. */
    private fun showReturnNotice(title: String, body: String): Boolean {
        stopProgress()
        val builder = noticeBuilder(title, body) ?: return false
        notifications().notify(RETURN_NOTICE_ID, builder.setAutoCancel(true).build())
        return true
    }

    /**
     * Notifikasi progress selama menunggu WA: bar terisi sampai [durationMs]
     * (batas timeout), lalu digantikan notifikasi hasil dengan ID yang sama.
     */
    private fun showProgressNotice(title: String, body: String, durationMs: Long): Boolean {
        stopProgress()
        val builder = noticeBuilder(title, body) ?: return false
        builder.setOngoing(true).setOnlyAlertOnce(true)
        val total = durationMs.coerceAtLeast(1)
        val start = SystemClock.elapsedRealtime()
        val tick = object : Runnable {
            override fun run() {
                val elapsed = SystemClock.elapsedRealtime() - start
                builder.setProgress(100, (elapsed * 100 / total).toInt().coerceIn(0, 100), false)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    // Bila proses app mati di tengah jalan, sistem yang menutupnya.
                    builder.setTimeoutAfter((total - elapsed).coerceAtLeast(0) + 5_000)
                }
                notifications().notify(RETURN_NOTICE_ID, builder.build())
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
