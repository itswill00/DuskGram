package tw.nekomimi.nekogram.utils

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.util.TypedValue
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import org.json.JSONObject
import org.telegram.messenger.AndroidUtilities
import org.telegram.messenger.ApplicationLoader
import org.telegram.messenger.BuildConfig
import org.telegram.messenger.FileLog
import org.telegram.messenger.LocaleController
import org.telegram.messenger.R
import org.telegram.ui.ActionBar.Theme
import tw.nekomimi.nekogram.helpers.ApkInstaller
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * In-app updater backed by GitHub Releases.
 *
 * Release tags look like `v1.0.1-2` (version name + version code) and every
 * release carries one APK per ABI. We read /releases/latest, pick the asset
 * that matches a supported ABI, download it and hand it to [ApkInstaller].
 */
object GithubUpdater {

    private const val RELEASES_API =
        "https://api.github.com/repos/itswill00/DuskGram/releases/latest"

    private const val CONNECT_TIMEOUT = 15_000
    private const val READ_TIMEOUT = 30_000

    data class Release(
        val version: String,
        val versionCode: Int,
        val url: String,
        val fileName: String,
        val size: Long,
        val notes: String
    )

    /** ABI markers used in the asset file names, most preferred first. */
    private val ABI_MARKERS = arrayOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")

    @Volatile
    private var checking = false

    /**
     * Checks GitHub for a newer build.
     *
     * @param silent when true, an up-to-date result or a network error stays
     *               invisible; only an actual update is surfaced.
     * @param onDone invoked on the UI thread once the check is over.
     */
    fun checkForUpdates(activity: Activity?, silent: Boolean, onDone: Runnable? = null) {
        if (checking) {
            onDone?.run()
            return
        }
        checking = true

        Thread {
            var release: Release? = null
            var error: String? = null
            try {
                release = fetchLatest()
            } catch (e: Exception) {
                FileLog.e(e)
                error = e.message
            }

            AndroidUtilities.runOnUIThread {
                checking = false
                onDone?.run()
                if (activity == null || activity.isFinishing) return@runOnUIThread

                when {
                    release != null -> showUpdateAvailable(activity, release)
                    !silent && error != null -> showInfo(activity, R.string.DuskGramUpdateCheckFailed)
                    !silent -> showInfo(activity, R.string.YourVersionIsLatest)
                }
            }
        }.start()
    }

    // ------------------------------------------------------------------ network

    private fun fetchLatest(): Release? {
        val body = httpGet(RELEASES_API) ?: return null
        val json = JSONObject(body)

        val tag = json.optString("tag_name", "")
        val parsed = parseTag(tag) ?: return null
        val (version, versionCode) = parsed

        // Nothing to do when this build is the published one or newer.
        if (versionCode <= BuildConfig.VERSION_CODE) {
            return null
        }

        val assets = json.optJSONArray("assets") ?: return null
        val byName = HashMap<String, JSONObject>()
        for (i in 0 until assets.length()) {
            val asset = assets.optJSONObject(i) ?: continue
            val name = asset.optString("name", "")
            if (name.endsWith(".apk", ignoreCase = true)) {
                byName[name] = asset
            }
        }
        if (byName.isEmpty()) return null

        val asset = pickAsset(byName) ?: return null
        return Release(
            version = version,
            versionCode = versionCode,
            url = asset.optString("browser_download_url", ""),
            fileName = asset.optString("name", "update.apk"),
            size = asset.optLong("size", 0L),
            notes = json.optString("body", "")
        )
    }

    /** Matches the APK against the device ABIs, most preferred first. */
    private fun pickAsset(byName: Map<String, JSONObject>): JSONObject? {
        for (abi in android.os.Build.SUPPORTED_ABIS) {
            byName.entries.firstOrNull { it.key.contains(abi, ignoreCase = true) }
                ?.let { return it.value }
        }
        // Fall back to any arm build so the update still reaches odd devices.
        for (marker in ABI_MARKERS) {
            byName.entries.firstOrNull { it.key.contains(marker, ignoreCase = true) }
                ?.let { return it.value }
        }
        return byName.values.firstOrNull()
    }

    private fun httpGet(url: String): String? {
        val connection = URL(url).openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "GET"
            connection.connectTimeout = CONNECT_TIMEOUT
            connection.readTimeout = READ_TIMEOUT
            connection.setRequestProperty("Accept", "application/vnd.github+json")
            connection.setRequestProperty("User-Agent", "DuskGram/" + BuildConfig.BUILD_VERSION_STRING)
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                return null
            }
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    /** Parses a `v<name>-<code>` tag; returns null when it does not match. */
    private fun parseTag(tag: String): Pair<String, Int>? {
        val cleaned = tag.trim().removePrefix("v").removePrefix("V")
        val separator = cleaned.lastIndexOf('-')
        if (separator <= 0 || separator == cleaned.length - 1) return null
        val version = cleaned.substring(0, separator)
        val code = cleaned.substring(separator + 1).toIntOrNull() ?: return null
        return version to code
    }

    // ----------------------------------------------------------------------- ui

    private fun showInfo(activity: Activity, resId: Int) {
        try {
            AlertDialog.Builder(activity)
                .setTitle(LocaleController.getString(R.string.AppName))
                .setMessage(LocaleController.getString(resId))
                .setPositiveButton(LocaleController.getString(R.string.OK), null)
                .show()
        } catch (ignored: Exception) {
        }
    }

    private fun showUpdateAvailable(activity: Activity, release: Release) {
        val sizeText = if (release.size > 0) {
            " (" + AndroidUtilities.formatFileSize(release.size) + ")"
        } else {
            ""
        }
        val message = LocaleController.formatString(
            R.string.DuskGramUpdateMessage,
            release.version,
            BuildConfig.BUILD_VERSION_STRING
        ) + sizeText

        AlertDialog.Builder(activity)
            .setTitle(LocaleController.getString(R.string.DuskGramUpdateAvailable))
            .setMessage(message)
            .setPositiveButton(LocaleController.getString(R.string.DuskGramUpdateDownload)) { _, _ ->
                download(activity, release)
            }
            .setNegativeButton(LocaleController.getString(R.string.Cancel), null)
            .show()
    }

    private fun download(activity: Activity, release: Release) {
        val progressBar = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal)
        progressBar.max = 100
        progressBar.isIndeterminate = release.size <= 0

        val label = TextView(activity)
        label.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 14f)
        label.setTextColor(Theme.getColor(Theme.key_dialogTextBlack))
        label.text = LocaleController.getString(R.string.DuskGramUpdateDownloading)

        val container = LinearLayout(activity)
        container.orientation = LinearLayout.VERTICAL
        val pad = AndroidUtilities.dp(20f)
        container.setPadding(pad, pad, pad, pad)
        container.gravity = Gravity.CENTER_HORIZONTAL
        container.addView(label, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))
        container.addView(progressBar, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = AndroidUtilities.dp(12f) })

        val dialog = AlertDialog.Builder(activity)
            .setTitle(LocaleController.getString(R.string.DuskGramUpdateAvailable))
            .setView(container)
            .setNegativeButton(LocaleController.getString(R.string.Cancel), null)
            .setCancelable(false)
            .create()
        dialog.show()

        Thread {
            var file: File? = null
            var error: String? = null
            try {
                file = downloadToCache(release) { percent ->
                    AndroidUtilities.runOnUIThread {
                        if (!progressBar.isIndeterminate) progressBar.setProgress(percent)
                    }
                }
            } catch (e: Exception) {
                FileLog.e(e)
                error = e.message
            }

            val result = file
            AndroidUtilities.runOnUIThread {
                dialog.dismiss()
                if (activity.isFinishing) return@runOnUIThread
                if (result != null) {
                    ApkInstaller.installUpdate(activity, result)
                } else {
                    showInfo(activity, R.string.DuskGramUpdateDownloadFailed)
                }
            }
        }.start()
    }

    private fun downloadToCache(release: Release, onProgress: (Int) -> Unit): File {
        val dir = File(ApplicationLoader.applicationContext.cacheDir, "updates")
        if (!dir.exists()) dir.mkdirs()

        val target = File(dir, release.fileName)
        if (target.exists()) target.delete()

        val connection = URL(release.url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = CONNECT_TIMEOUT
            connection.readTimeout = READ_TIMEOUT
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", "DuskGram/" + BuildConfig.BUILD_VERSION_STRING)

            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                throw IllegalStateException("HTTP " + connection.responseCode)
            }

            val total = connection.contentLength.toLong()
            var downloaded = 0L
            var lastPercent = -1

            connection.inputStream.use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        downloaded += read
                        if (total > 0) {
                            val percent = (downloaded * 100 / total).toInt()
                            if (percent != lastPercent) {
                                lastPercent = percent
                                onProgress(percent)
                            }
                        }
                    }
                }
            }
            return target
        } finally {
            connection.disconnect()
        }
    }
}
