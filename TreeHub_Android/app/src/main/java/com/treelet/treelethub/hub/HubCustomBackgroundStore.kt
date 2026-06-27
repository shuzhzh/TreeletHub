package com.treelet.treelethub.hub

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

class HubCustomBackgroundStore(private val context: Context) {
    private val dir: File by lazy {
        File(context.filesDir, "TreeletHub").also { if (!it.exists()) it.mkdirs() }
    }
    private val file = File(dir, "custom-background.jpg")

    var bitmap: ImageBitmap? by mutableStateOf(null)
        private set

    init {
        reloadFromDisk()
    }

    fun reloadFromDisk() {
        if (!file.exists()) {
            bitmap = null
            return
        }
        val decoded = BitmapFactory.decodeFile(file.absolutePath) ?: run {
            file.delete()
            bitmap = null
            return
        }
        bitmap = decoded.asImageBitmap()
    }

    fun saveJpeg(bytes: ByteArray) {
        val src = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return
        val scaled = resizeIfNeeded(src, 2048)
        try {
            FileOutputStream(file).use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 88, out)
            }
        } catch (_: Exception) {
            bitmap = null
            return
        } finally {
            if (scaled != src) {
                if (!scaled.isRecycled) scaled.recycle()
                if (!src.isRecycled) src.recycle()
            } else {
                if (!src.isRecycled) src.recycle()
            }
        }
        reloadFromDisk()
    }

    fun deleteCustomFile() {
        if (file.exists()) file.delete()
        bitmap = null
    }

    private fun resizeIfNeeded(image: Bitmap, maxSide: Int): Bitmap {
        val w = image.width.toFloat()
        val h = image.height.toFloat()
        val longest = max(w, h)
        if (longest <= maxSide || longest <= 0f) return image
        val scale = maxSide / longest
        val nw = (w * scale).roundToInt().coerceAtLeast(1)
        val nh = (h * scale).roundToInt().coerceAtLeast(1)
        val out = Bitmap.createScaledBitmap(image, nw, nh, true)
        if (out != image) {
            image.recycle()
        }
        return out
    }
}
