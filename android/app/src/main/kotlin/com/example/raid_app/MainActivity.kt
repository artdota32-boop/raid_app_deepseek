package com.example.raid_app

import android.content.Intent
import android.app.Activity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "raid_scanner/diagnostics"
    private val requestCodeSave = 7319

    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            if (call.method == "saveTensor") {

                if (pendingResult != null) {
                    result.error("BUSY", "Предыдущий экспорт ещё выполняется", null)
                    return@setMethodCallHandler
                }

                val bytes = call.argument<ByteArray>("bytes")

                if (bytes == null) {
                    result.error("INVALID_DATA", "Тензор не передан", null)
                    return@setMethodCallHandler
                }

                pendingBytes = bytes
                pendingResult = result

                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, "dart_tensor.bin")
                }

                try {
                    startActivityForResult(intent, requestCodeSave)
                } catch (e: Exception) {
                    pendingResult?.error("SAVE_DIALOG", e.message, null)
                    pendingResult = null
                    pendingBytes = null
                }

            } else {
                result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Android API, retained for FlutterActivity compatibility")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != requestCodeSave) return

        val result = pendingResult
        val bytes = pendingBytes

        pendingResult = null
        pendingBytes = null

        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(false)
            return
        }

        try {
            contentResolver.openOutputStream(data.data!!).use { stream ->
                if (stream == null) {
                    throw IllegalStateException("Не удалось открыть файл")
                }
                stream.write(bytes!!)
                stream.flush()
            }

            result.success(true)
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message, null)
        }
    }
}
