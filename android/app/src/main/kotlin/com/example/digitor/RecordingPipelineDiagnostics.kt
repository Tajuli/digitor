package com.example.digitor

import android.os.Handler
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A fail-fast, ordered trace of the camera-to-MP4 path.  Keep this deliberately
 * small: its purpose is to identify the first missing stage, not hide it.
 */
internal class RecordingPipelineDiagnostics(
    private val name: String,
    private val handler: Handler,
    private val onStalled: (String) -> Unit,
) {
    private val closed = AtomicBoolean(false)
    private val completed = BooleanArray(STAGES.size)
    private var deadlineToken = 0

    fun begin() = expect(CAMERA_OPENED)

    fun mark(stage: Int, detail: String = "") {
        check(stage in STAGES.indices) { "Unknown recording diagnostic stage: $stage" }
        if (closed.get() || completed[stage]) return
        completed[stage] = true
        Log.d(TAG, "$name: ${STAGES[stage]}${detail.takeIf { it.isNotEmpty() }?.let { " ($it)" } ?: ""}")
        if (stage == FINAL_FILE_SIZE) close() else expectNext()
    }

    fun image(timestampNs: Long, count: Int) {
        if (count <= 3 || count % 30 == 0) {
            Log.d(TAG, "$name: Image count=$count, timestamp=$timestampNs ns")
        }
    }

    fun imageClosed() = Unit

    fun encodedFrame(count: Int) {
        if (count <= 3 || count % 30 == 0) {
            Log.d(TAG, "$name: Encoded frame count=$count")
        }
    }

    fun finalFileSize(bytes: Long) = mark(FINAL_FILE_SIZE, "$bytes bytes")

    fun expect(stage: Int) {
        if (closed.get() || completed[stage] || stage !in STAGES.indices) return
        val token = ++deadlineToken
        handler.postDelayed({
            if (!closed.get() && token == deadlineToken && !completed[stage]) {
                closed.set(true)
                val message = "$name recording pipeline stopped at stage: ${STAGES[stage]}"
                Log.d(TAG, "$message; failing immediately")
                onStalled(message)
            }
        }, STAGE_TIMEOUT_MS)
    }

    fun close() { closed.set(true); deadlineToken++ }

    fun stopped(detail: String): String {
        closed.set(true); deadlineToken++
        val stage = completed.indexOfFirst { !it }.let { if (it >= 0) it else FINAL_FILE_SIZE }
        val message = "$name recording pipeline stopped at stage: ${STAGES[stage]}; $detail"
        Log.d(TAG, message)
        return message
    }

    fun completed(stage: Int): Boolean = completed[stage]

    private fun expectNext() {
        // Encoder shutdown is driven explicitly by the engine and can legitimately
        // take up to its EOS drain timeout. Never arm the normal short watchdog
        // for either asynchronous shutdown stage.
        val next = completed.indexOfFirst { !it }
        if (next < 0 || next == EOS_SUBMITTED || next == EOS_RECEIVED) return
        expect(next)
    }

    companion object {
        const val CAMERA_OPENED = 0
        const val CAPTURE_SESSION_CONFIGURED = 1
        const val PREVIEW_SURFACE_ATTACHED = 2
        const val IMAGE_READER_SURFACE_ATTACHED = 3
        const val FIRST_IMAGE_CALLBACK = 4
        const val YUV_COPY_COMPLETE = 5
        const val TEXTURE_UPLOAD_COMPLETE = 6
        const val SHADER_RENDER_COMPLETE = 7
        const val EGL_SWAP_BUFFERS_COMPLETE = 8
        const val ENCODER_INPUT_FRAME_SUBMITTED = 9
        const val OUTPUT_FORMAT_CHANGED = 10
        const val MUXER_STARTED = 11
        const val FIRST_ENCODED_OUTPUT_BUFFER = 12
        const val FIRST_MUXED_SAMPLE = 13
        const val EOS_SUBMITTED = 14
        const val EOS_RECEIVED = 15
        const val MUXER_STOPPED = 16
        const val FINAL_FILE_SIZE = 17
        private const val TAG = "DigLogV3"
        private const val STAGE_TIMEOUT_MS = 3_000L
        private val STAGES = listOf(
            "Camera opened", "CaptureSession configured", "Preview surface attached",
            "ImageReader surface attached", "First ImageReader callback", "YUV copy complete",
            "Texture upload complete", "Shader render complete", "eglSwapBuffers complete",
            "Encoder input frame submitted", "MediaCodec INFO_OUTPUT_FORMAT_CHANGED",
            "MediaMuxer started", "First encoded output buffer", "First muxed sample",
            "EOS submitted", "EOS received", "Muxer stopped", "Final file size",
        )
    }
}
