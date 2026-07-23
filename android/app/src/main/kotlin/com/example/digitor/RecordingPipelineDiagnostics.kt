package com.example.digitor

import android.os.Handler
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

/** Logs recording progress and fails the recording at the first stage that stalls. */
internal class RecordingPipelineDiagnostics(
    private val name: String,
    private val handler: Handler,
    private val onStalled: (String) -> Unit,
) {
    private val closed = AtomicBoolean(false)
    private val completed = BooleanArray(STAGES.size)
    private var deadlineToken = 0

    fun begin() = expect(0)

    fun mark(stage: Int, detail: String = "") {
        if (closed.get() || completed[stage]) return
        completed[stage] = true
        Log.i(TAG, "$name: ${STAGES[stage]}${if (detail.isEmpty()) "" else " ($detail)"}")
        if (stage == STAGES.lastIndex) {
            close()
        }
        expectNext()
    }

    fun imageTimestamp(timestampNs: Long) {
        Log.d(TAG, "$name: ImageReader image timestamp=$timestampNs ns")
    }

    fun expect(stage: Int) {
        if (closed.get() || completed[stage] || stage > STAGES.lastIndex) return
        val token = ++deadlineToken
        handler.postDelayed({
            if (!closed.get() && token == deadlineToken && !completed[stage]) {
                closed.set(true)
                val message = "$name recording pipeline stopped at stage: ${STAGES[stage]}"
                Log.e(TAG, message)
                onStalled(message)
            }
        }, STAGE_TIMEOUT_MS)
    }

    fun close() {
        closed.set(true)
        deadlineToken++
    }

    fun stopped(detail: String): String {
        closed.set(true)
        deadlineToken++
        val stage = completed.indexOfFirst { !it }.let { if (it >= 0) it else STAGES.lastIndex }
        return "$name recording pipeline stopped at stage: ${STAGES[stage]}; $detail"
    }

    fun completed(stage: Int): Boolean = completed[stage]

    private fun expectNext() {
        val next = completed.indexOfFirst { !it }
        if (next >= 0) expect(next)
    }

    companion object {
        private const val TAG = "DigLogPipeline"
        private const val STAGE_TIMEOUT_MS = 3_000L
        private val STAGES = listOf(
            "Camera session configured",
            "ImageReader surface attached",
            "First ImageReader frame received",
            "Frame copied into renderer",
            "Texture upload completed",
            "Shader draw completed",
            "eglSwapBuffers completed",
            "Frame submitted to encoder surface",
            "MediaCodec start",
            "INFO_OUTPUT_FORMAT_CHANGED",
            "MediaMuxer start",
            "First encoded buffer received",
            "Encoded sample written",
            "EOS received",
            "Muxer stopped",
        )
    }
}
