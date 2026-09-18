package com.metrichours.metric_hours

import android.content.ContentUris
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "metric_hours/log_writer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler {
            call, result ->
            if (call.method == "writeLog") {
                val fileName = call.argument<String>("fileName") ?: "metric_hours_log.txt"
                val content = call.argument<String>("content") ?: ""
                try {
                    val path = writeLogToDownloads(fileName, content)
                    result.success(path)
                } catch (error: Exception) {
                    result.error("WRITE_FAILED", error.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun writeLogToDownloads(fileName: String, content: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val existingUri = findExistingDownload(collection, fileName)
            val uri = existingUri ?: run {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                }
                resolver.insert(collection, values)
                    ?: throw IllegalStateException("No se pudo crear el archivo en Descargas")
            }
            resolver.openOutputStream(uri, "wt")?.use { it.write(content.toByteArray()) }
                ?: throw IllegalStateException("No se pudo abrir el archivo en Descargas")
            return "Download/$fileName"
        } else {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            if (!downloadsDir.exists()) downloadsDir.mkdirs()
            val file = File(downloadsDir, fileName)
            file.writeText(content)
            return file.absolutePath
        }
    }

    private fun findExistingDownload(collection: Uri, fileName: String): Uri? {
        val projection = arrayOf(MediaStore.Downloads._ID)
        val selection = "${MediaStore.Downloads.DISPLAY_NAME} = ?"
        val selectionArgs = arrayOf(fileName)
        contentResolver.query(collection, projection, selection, selectionArgs, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID))
                return ContentUris.withAppendedId(collection, id)
            }
        }
        return null
    }
}
