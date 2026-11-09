package com.huyphan.flutter_paddle_ocr

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.baidu.paddle.lite.demo.ocr.OcrResultModel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class FlutterPaddleOcrPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    private val instances = ConcurrentHashMap<Int, PaddleOcrEngine>()
    private val nextId = AtomicInteger(1)
    // Native inference is hundreds of ms; keeping it off the platform thread prevents
    // MethodChannel backpressure from blocking unrelated plugin calls.
    private val worker: Executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "flutter_paddle_ocr")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        instances.values.forEach { it.dispose() }
        instances.clear()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "create" -> runOnWorker(result) { handleCreate(call) }
            "recognize" -> runOnWorker(result) { handleRecognize(call) }
            "dispose" -> runOnWorker(result) { handleDispose(call) }
            else -> result.notImplemented()
        }
    }

    private fun handleCreate(call: MethodCall): Int {
        val detPath = call.requireArg<String>("detModelPath")
        val recPath = call.requireArg<String>("recModelPath")
        val clsPath = call.argument<String>("clsModelPath").orEmpty()
        val labelPath = call.requireArg<String>("labelPath")
        val cpuThreadNum = call.argument<Int>("cpuThreadNum") ?: 4
        val cpuPower = call.argument<String>("cpuPower") ?: "LITE_POWER_HIGH"
        val useOpenCL = call.argument<Boolean>("useOpenCL") == true
        val useSpaceChar = call.argument<Boolean>("useSpaceChar") != false
        val useDilation = call.argument<Boolean>("useDilation") == true
        val detDbThresh = call.argument<Double>("detDbThresh") ?: 0.3
        val detDbBoxThresh = call.argument<Double>("detDbBoxThresh") ?: 0.6
        val detDbUnclipRatio = call.argument<Double>("detDbUnclipRatio") ?: 1.5

        requireFile(detPath, "detModelPath")
        requireFile(recPath, "recModelPath")
        if (clsPath.isNotEmpty()) requireFile(clsPath, "clsModelPath")
        requireFile(labelPath, "labelPath")

        val engine = PaddleOcrEngine(
            detPath = detPath,
            recPath = recPath,
            clsPath = clsPath,
            labelPath = labelPath,
            cpuThreadNum = cpuThreadNum,
            cpuPower = cpuPower,
            useOpenCL = if (useOpenCL) 1 else 0,
            useSpaceChar = useSpaceChar,
            useDilation = if (useDilation) 1 else 0,
            detDbThresh = detDbThresh.toFloat(),
            detDbBoxThresh = detDbBoxThresh.toFloat(),
            detDbUnclipRatio = detDbUnclipRatio.toFloat(),
        )
        val id = nextId.getAndIncrement()
        instances[id] = engine
        return id
    }

    private fun handleRecognize(call: MethodCall): List<Map<String, Any?>> {
        val id = call.requireArg<Int>("instanceId")
        val engine = instances[id]
            ?: throw IllegalStateException("No engine for id=$id (was it disposed?)")
        val bytes = call.requireArg<ByteArray>("imageBytes")
        val maxSideLen = call.argument<Int>("maxSideLen") ?: 960
        val runDet = call.argument<Boolean>("runDetection") != false
        val runCls = call.argument<Boolean>("runClassification") == true
        val runRec = call.argument<Boolean>("runRecognition") != false

        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IllegalArgumentException("Failed to decode image bytes")
        // OCRPredictorNative reads via AndroidBitmap_lockPixels and expects ARGB_8888.
        // BitmapFactory usually returns exactly that, so the copy is only needed for
        // oddball sources (e.g. hardware bitmaps in HARDWARE config).
        val argb = if (decoded.config == Bitmap.Config.ARGB_8888) decoded
        else decoded.copy(Bitmap.Config.ARGB_8888, false).also { decoded.recycle() }

        try {
            return engine.recognize(argb, maxSideLen, runDet, runCls, runRec)
                .map { it.toMap() }
        } finally {
            argb.recycle()
        }
    }

    private fun handleDispose(call: MethodCall) {
        val id = call.requireArg<Int>("instanceId")
        instances.remove(id)?.dispose()
    }

    private fun runOnWorker(result: Result, block: () -> Any?) {
        worker.execute {
            val outcome = runCatching(block)
            mainHandler.post {
                outcome
                    .onSuccess { data -> if (data is Unit) result.success(emptyMap<String, Any>()) else result.success(data) }
                    .onFailure { t ->
                        Log.e(TAG, "method call failed", t)
                        result.error(t.errorCode(), t.message, t.stackTraceToString())
                    }
            }
        }
    }

    private fun Throwable.errorCode(): String = when (this) {
        is IllegalArgumentException -> "ARG"
        is IllegalStateException -> "STATE"
        else -> "PADDLE_OCR_ERROR"
    }

    private inline fun <reified T> MethodCall.requireArg(name: String): T =
        argument<T>(name) ?: throw IllegalArgumentException("$name is required")

    private fun requireFile(path: String, name: String) {
        if (!File(path).exists()) {
            throw IllegalArgumentException("$name not found: $path")
        }
    }

    private fun OcrResultModel.toMap(): Map<String, Any?> = mapOf(
        "text" to (label ?: ""),
        "confidence" to confidence.toDouble(),
        "points" to points.map { listOf(it.x, it.y) },
        // cls_idx from native is -1 when classification was skipped.
        "isUpsideDown" to if (clsIdx < 0) null else (clsIdx.toInt() == 1),
        "angleConfidence" to if (clsIdx < 0) null else clsConfidence.toDouble(),
    )

    companion object {
        private const val TAG = "FlutterPaddleOcr"
    }
}
