package com.sconl.isconl

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity (not FlutterActivity) so local_auth's biometric
// prompt, which requires a FragmentActivity host, works.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "isconl/platform"
    private var pendingSharedText: String? = null
    // BI26100159: files shared into the app, already copied into the cache folder.
    private var pendingSharedFiles: List<Map<String, Any?>>? = null
    // BI26100138: "capture", "voice" or "today", from the widget or a shortcut.
    private var pendingWidgetAction: String? = null

    private fun widgetActionOf(intent: Intent?): String? = when (intent?.action) {
        "com.sconl.isconl.CAPTURE" -> "capture"
        "com.sconl.isconl.VOICE" -> "voice"
        "com.sconl.isconl.TODAY" -> "today"
        else -> null
    }
    private var pickResult: MethodChannel.Result? = null
    private val pickRequestCode = 7301
    private val smsRequestCode = 7302
    // An update waiting for "Install unknown apps" to be allowed: installed
    // automatically in onResume once Sconl comes back from that settings page.
    private var pendingInstall: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSharedText = extractSharedText(intent)
        pendingSharedFiles = extractSharedFiles(intent)
        pendingWidgetAction = widgetActionOf(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedText" -> {
                    result.success(pendingSharedText)
                    pendingSharedText = null
                }
                // BI26100138: the widget and the icon shortcuts ask the app to open something.
                "getWidgetAction" -> {
                    result.success(pendingWidgetAction)
                    pendingWidgetAction = null
                }
                "updateWidget" -> {
                    val json = call.argument<String>("json")
                    if (json == null) {
                        result.error("ARG", "json required", null)
                    } else {
                        IsconlWidgetProvider.save(applicationContext, json)
                        result.success(true)
                    }
                }
                "getSharedFiles" -> {
                    result.success(pendingSharedFiles)
                    pendingSharedFiles = null
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("ARG", "path required", null)
                    } else {
                        try {
                            // "installing" or "needs_permission" (Settings opened; the
                            // install resumes by itself in onResume once allowed).
                            result.success(installApk(File(path)))
                        } catch (e: Exception) {
                            result.error("INSTALL", e.message, null)
                        }
                    }
                }
                "openFile" -> {
                    val path = call.argument<String>("path")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    if (path == null) {
                        result.error("ARG", "path required", null)
                    } else {
                        try {
                            // false, not an error: "no app can open this" is an
                            // answer the caller can show him, not a crash.
                            result.success(openFile(File(path), mime))
                        } catch (e: Exception) {
                            result.error("OPEN", e.message, null)
                        }
                    }
                }
                "pickImage" -> {
                    if (pickResult != null) {
                        result.error("BUSY", "picker already open", null)
                    } else {
                        pickResult = result
                        val pick = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "image/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        try {
                            startActivityForResult(Intent.createChooser(pick, "Choose image"), pickRequestCode)
                        } catch (e: Exception) {
                            pickResult = null
                            result.error("PICK", e.message, null)
                        }
                    }
                }

                // ── SMS ────────────────────────────────────────────────────
                // Three calls, deliberately small: is it granted, ask for it,
                // and read the inbox since a timestamp. Parsing happens in Dart
                // where it can be tested; this side only fetches bytes.
                "smsGranted" -> result.success(smsGranted())

                "requestSms" -> {
                    // Android shows the sheet; the answer arrives on the next
                    // smsGranted() call rather than through a callback, which
                    // keeps this side free of result bookkeeping that can leak.
                    if (!smsGranted()) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
                            smsRequestCode
                        )
                    }
                    result.success(smsGranted())
                }

                "readSms" -> {
                    if (!smsGranted()) {
                        // Not an error: it is a state the UI must be able to show.
                        result.success(mapOf("granted" to false, "messages" to emptyList<Any>()))
                    } else {
                        try {
                            val since = (call.argument<Number>("since")?.toLong()) ?: 0L
                            val limit = (call.argument<Number>("limit")?.toInt()) ?: 500
                            result.success(mapOf("granted" to true, "messages" to readSms(since, limit)))
                        } catch (e: Exception) {
                            result.error("SMS", e.message, null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun smsGranted(): Boolean =
        checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    /**
     * The inbox since a timestamp, newest first.
     *
     * Only the four columns Dart needs are selected. Reading the whole row would
     * pull the thread id, read state, subject and service centre for no purpose,
     * and the less of his message store crosses the channel the better.
     *
     * Filtered to M-Pesa at the query level so ordinary conversations are never
     * even loaded into memory, let alone forwarded. The Dart side checks the
     * sender again - two gates, because this one is an optimisation and that one
     * is the guarantee.
     */
    private fun readSms(since: Long, limit: Int): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val cols = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE
        )
        val where = "${Telephony.Sms.DATE} > ? AND (${Telephony.Sms.ADDRESS} LIKE ? OR ${Telephony.Sms.ADDRESS} LIKE ?)"
        val args = arrayOf(since.toString(), "MPESA", "M-PESA")
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI, cols, where, args,
            "${Telephony.Sms.DATE} DESC LIMIT $limit"
        )?.use { c ->
            val iId = c.getColumnIndex(Telephony.Sms._ID)
            val iAddr = c.getColumnIndex(Telephony.Sms.ADDRESS)
            val iBody = c.getColumnIndex(Telephony.Sms.BODY)
            val iDate = c.getColumnIndex(Telephony.Sms.DATE)
            while (c.moveToNext()) {
                out.add(mapOf(
                    "id" to (if (iId >= 0) c.getString(iId) else null),
                    "sender" to (if (iAddr >= 0) c.getString(iAddr) else null),
                    "body" to (if (iBody >= 0) c.getString(iBody) else null),
                    "date" to (if (iDate >= 0) c.getLong(iDate) else 0L)
                ))
            }
        }
        return out
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = widgetActionOf(intent)
        if (action != null) {
            pendingWidgetAction = action
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, channelName).invokeMethod("widgetAction", action)
            }
        }
        val files = extractSharedFiles(intent)
        if (files != null) {
            pendingSharedFiles = files
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, channelName).invokeMethod("sharedFiles", files)
            }
        }
        val shared = extractSharedText(intent)
        if (shared != null) {
            pendingSharedText = shared
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, channelName).invokeMethod("sharedText", shared)
            }
        }
    }

    /**
     * Images and PDFs shared in through SEND or SEND_MULTIPLE, copied out of the sender's
     * content provider into `cache/shared` at once: the grant to read the sender's uri ends
     * with this activity, and the reader may save it offline long after. A file over 25 MB
     * is reported with its size and no path so the sheet can say it is too big, rather than
     * the phone reading it all into memory.
     */
    @Suppress("DEPRECATION")
    private fun extractSharedFiles(intent: Intent?): List<Map<String, Any?>>? {
        val action = intent?.action ?: return null
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return null
        val uris = ArrayList<Uri>()
        if (action == Intent.ACTION_SEND) {
            val one = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (one != null) uris.add(one)
        } else {
            val many = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (many != null) uris.addAll(many)
        }
        if (uris.isEmpty()) return null
        val dir = File(cacheDir, "shared")
        dir.mkdirs()
        val maxBytes = 25L * 1024 * 1024
        val out = ArrayList<Map<String, Any?>>()
        for (uri in uris) {
            try {
                val mime = contentResolver.getType(uri) ?: intent.type ?: "application/octet-stream"
                var name = "shared"
                var size = -1L
                contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME, android.provider.OpenableColumns.SIZE), null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val n = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        val s = c.getColumnIndex(android.provider.OpenableColumns.SIZE)
                        if (n >= 0 && !c.isNull(n)) name = c.getString(n)
                        if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
                    }
                }
                if (size > maxBytes) {
                    out.add(mapOf("name" to name, "mime" to mime, "size" to size, "path" to null))
                    continue
                }
                val safe = name.replace(Regex("[^A-Za-z0-9._ -]"), "_")
                val target = File(dir, "${System.currentTimeMillis()}_$safe")
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { input.copyTo(it) }
                }
                out.add(mapOf("name" to name, "mime" to mime, "size" to target.length(), "path" to target.absolutePath))
            } catch (e: Exception) {
                // One unreadable file does not drop the rest.
            }
        }
        return if (out.isEmpty()) null else out
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            return when {
                text == null -> subject
                subject != null && !text.contains(subject) -> "$subject\n$text"
                else -> text
            }
        }
        return null
    }

    /**
     * Hand any downloaded file to whatever app on the phone opens that type.
     *
     * Same FileProvider mechanism installApk already relies on, generalised: an
     * exported PDF goes to the system PDF viewer, from which he can share, mail
     * or print it. Building a viewer inside this app would be a worse copy of
     * something every phone already has.
     *
     * ACTION_VIEW is wrapped in a chooser so a phone with two PDF readers asks
     * rather than silently picking, and a phone with none reports it instead of
     * throwing ActivityNotFoundException up the channel as a crash.
     */
    private fun openFile(file: File, mime: String): Boolean {
        val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val chooser = Intent.createChooser(view, "Open with").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(chooser)
            true
        } catch (e: android.content.ActivityNotFoundException) {
            false
        }
    }

    override fun onResume() {
        super.onResume()
        val f = pendingInstall ?: return
        if (canInstall()) {
            pendingInstall = null
            if (f.exists()) launchInstaller(f)
        }
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    /** Hands [file] to the system installer, first asking for "Install unknown
     *  apps" when Android hasn't granted it to iSconl yet (the silent failure
     *  behind "v0.3.54 available" with no install, 4 Oct 2026). */
    private fun installApk(file: File): String {
        if (!canInstall()) {
            pendingInstall = file
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return "needs_permission"
        }
        launchInstaller(file)
        return "installing"
    }

    private fun launchInstaller(file: File) {
        val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val install = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(install)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickRequestCode) {
            val result = pickResult
            pickResult = null
            if (result == null) return
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                try {
                    contentResolver.openInputStream(data.data!!).use { input ->
                        result.success(input?.readBytes())
                    }
                } catch (e: Exception) {
                    result.error("READ", e.message, null)
                }
            } else {
                result.success(null)
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
