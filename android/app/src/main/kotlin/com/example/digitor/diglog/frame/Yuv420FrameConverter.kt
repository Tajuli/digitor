package com.example.digitor.diglog.frame

import android.media.Image
import java.nio.ByteBuffer

/** Copies arbitrary-stride YUV_420_888 planes into tightly packed reusable GPU-upload buffers. */
object Yuv420FrameConverter {
    fun copyPlane(plane: Image.Plane, width: Int, height: Int): ByteBuffer {
        val source = plane.buffer.duplicate()
        val result = ByteBuffer.allocateDirect(width * height)
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        for (row in 0 until height) for (column in 0 until width) {
            val offset = row * rowStride + column * pixelStride
            result.put(if (offset in 0 until source.limit()) source.get(offset) else 0)
        }
        result.flip()
        return result
    }
}
