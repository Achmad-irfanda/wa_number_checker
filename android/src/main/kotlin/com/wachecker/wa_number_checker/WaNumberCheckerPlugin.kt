package com.wachecker.wa_number_checker

import android.accounts.Account
import android.accounts.AccountManager
import android.content.ContentProviderOperation
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
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

    companion object {
        const val TEMP_ACCOUNT_TYPE = "com.wa_checker.temp"
        const val TEMP_ACCOUNT_NAME = "wa_temp"
        val WA_ACCOUNT_TYPES = setOf("com.whatsapp", "com.whatsapp.w4b")
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
                io.launch { reply(result) { insertTemp(normalize(raw), tag) } }
            }
            "deleteContact" -> {
                val id = (call.argument<Number>("contactId") ?: 0).toLong()
                io.launch {
                    reply(result) {
                        val n = appContext.contentResolver.delete(
                            ContactsContract.Contacts.CONTENT_URI,
                            "${ContactsContract.Contacts._ID}=?",
                            arrayOf(id.toString()),
                        )
                        n
                    }
                }
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
        var contactId: Long? = null
        cr.query(lookup, arrayOf(ContactsContract.PhoneLookup._ID), null, null, null)?.use {
            if (it.moveToFirst()) contactId = it.getLong(0)
        }
        if (contactId == null) {
            return mapOf("found" to false, "detectedBy" to emptyList<String>())
        }
        val detected = mutableSetOf<String>()
        cr.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(ContactsContract.RawContacts.ACCOUNT_TYPE),
            "${ContactsContract.RawContacts.CONTACT_ID}=?",
            arrayOf(contactId.toString()),
            null,
        )?.use {
            val idx = it.getColumnIndex(ContactsContract.RawContacts.ACCOUNT_TYPE)
            while (it.moveToNext()) {
                when (if (idx >= 0) it.getString(idx) else null) {
                    "com.whatsapp" -> detected.add("whatsapp")
                    "com.whatsapp.w4b" -> detected.add("whatsappBusiness")
                }
            }
        }
        return mapOf(
            "found" to detected.isNotEmpty(),
            "detectedBy" to detected.toList(),
            "contactId" to (contactId ?: -1L),
        )
    }

    private fun insertTemp(normalized: String, tag: String): Map<String, Any> {
        val cr = appContext.contentResolver
        val acc = ensureTempAccount()
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
                .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, normalized)
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
