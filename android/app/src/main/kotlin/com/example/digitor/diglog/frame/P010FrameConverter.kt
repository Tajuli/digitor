package com.example.digitor.diglog.frame

import android.media.Image
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.ShortBuffer

/** Copies Android YCBCR_P010 without reducing it to 8-bit. Values stay 10-bit in 16-bit containers. */
object P010FrameConverter {
    data class Frame(val y: ShortBuffer, val uv: ShortBuffer, val width: Int, val height: Int)

    fun copy(image: Image): Frame {
        require(image.planes.size >= 2) { "P010 requires Y and interleaved UV planes" }
        val y = copyPlane(image.planes[0], image.width, image.height, 1)
        val uv = copyPlane(image.planes[1], image.width / 2, image.height / 2, 2)
        return Frame(y, uv, image.width, image.height)
    }

    private fun copyPlane(plane: Image.Plane, width: Int, height: Int, components: Int): ShortBuffer {
        val out = ByteBuffer.allocateDirect(width * height * components * 2)
            .order(ByteOrder.nativeOrder()).asShortBuffer()
        val src = plane.buffer.duplicate().order(ByteOrder.nativeOrder())
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride.coerceAtLeast(components * 2)
        for (row in 0 until height) {
            val rowBase = row * rowStride
            for (col in 0 until width) {
                val base = rowBase + col * pixelStride
                for (c in 0 until components) {
                    val offset = base + c * 2
                    require(offset + 1 < src.limit()) { "P010 plane buffer is smaller than its strides describe" }
                    // P010 stores each 10-bit sample in the high bits of a 16-bit word.
                    val packed = src.getShort(offset).toInt() and 0xffff
                    out.put((packed ushr 6).coerceIn(0, 1023).toShort())
                }
            }
        }
        out.flip()
        return out
    }
}
