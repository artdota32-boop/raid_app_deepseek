package com.huyphan.flutter_paddle_ocr

import android.graphics.Bitmap
import com.baidu.paddle.lite.demo.ocr.OCRPredictorNative
import com.baidu.paddle.lite.demo.ocr.OcrResultModel
import java.io.File
import java.nio.charset.StandardCharsets

internal class PaddleOcrEngine(
    detPath: String,
    recPath: String,
    clsPath: String,
    labelPath: String,
    cpuThreadNum: Int,
    cpuPower: String,
    useOpenCL: Int,
    useSpaceChar: Boolean,
    useDilation: Int,
    detDbThresh: Float,
    detDbBoxThresh: Float,
    detDbUnclipRatio: Float,
) {
    private val native: OCRPredictorNative
    private val wordLabels: List<String> = loadLabels(labelPath, useSpaceChar)

    init {
        val config = OCRPredictorNative.Config().apply {
            this.detModelFilename = detPath
            this.recModelFilename = recPath
            this.clsModelFilename = clsPath
            this.cpuThreadNum = cpuThreadNum
            this.cpuPower = cpuPower
            this.useOpencl = useOpenCL
            this.useDilation = useDilation
            this.detDbThresh = detDbThresh
            this.detDbBoxThresh = detDbBoxThresh
            this.detDbUnclipRatio = detDbUnclipRatio
        }
        native = OCRPredictorNative(config)
    }

    fun recognize(
        bitmap: Bitmap,
        maxSideLen: Int,
        runDet: Boolean,
        runCls: Boolean,
        runRec: Boolean,
    ): List<OcrResultModel> {
        val results = native.runImage(bitmap, maxSideLen, runDet.toInt(), runCls.toInt(), runRec.toInt())
        for (r in results) {
            val text = StringBuilder()
            for (i in r.wordIndex) {
                text.append(if (i in wordLabels.indices) wordLabels[i] else "×")
            }
            r.label = text.toString()
        }
        return results
    }

    fun dispose() {
        native.destroy()
    }

    private fun Boolean.toInt() = if (this) 1 else 0

    // Leading "black" matches upstream PaddleOCR Predictor.java: the recognition CTC
    // output uses index 0 as the blank token, so the dictionary list is shifted by one.
    private fun loadLabels(path: String, useSpaceChar: Boolean): List<String> {
        val labels = mutableListOf("black")
        labels.addAll(File(path).readLines(StandardCharsets.UTF_8))
        if (useSpaceChar) labels.add(" ")
        return labels
    }
}
