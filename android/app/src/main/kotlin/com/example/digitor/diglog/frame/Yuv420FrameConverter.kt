package com.example.digitor.diglog.frame

import android.media.Image
import java.nio.ByteBuffer

/** Fast stride-aware YUV_420_888 plane copy into reusable direct buffers. */
object Yuv420FrameConverter {
    fun copyPlaneInto(
        plane: Image.Plane,
        width: Int,
        height: Int,
        destination: ByteBuffer,
    ): ByteBuffer {
        require(destination.capacity() >= width * height)
        val source = plane.buffer.duplicate()
        val base = source.position()
        val limit = source.limit()
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        destination.clear()

        if (pixelStride == 1) {
            // The Y plane is normally tightly packed per pixel. Copy one complete
            // row at a time instead of doing ~2 million indexed JNI-backed gets.
            for (row in 0 until height) {
                val rowStart = base + row * rowStride
                if (rowStart >= limit) {
                    repeat(width) { destination.put(0) }
                    continue
                }
                val count = minOf(width, limit - rowStart)
                source.position(rowStart)
                source.limit(rowStart + count)
                destination.put(source)
                repeat(width - count) { destination.put(0) }
                source.limit(limit)
            }
        } else {
            // Chroma planes are commonly interleaved with pixelStride=2.
            for (row in 0 until height) {
                var offset = base + row * rowStride
                for (column in 0 until width) {
                    destination.put(if (offset in base until limit) source.get(offset) else 0)
                    offset += pixelStride
                }
            }
        }
        destination.flip()
        return destination
    }

    fun copyPlane(plane: Image.Plane, width: Int, height: Int): ByteBuffer =
        copyPlaneInto(plane, width, height, ByteBuffer.allocateDirect(width * height))
}
