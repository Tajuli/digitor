package com.example.digitor

import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CaptureRequest
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES30
import android.os.Handler
import android.os.SystemClock
import android.util.Log
import android.util.Size
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * DigLog V4 zero-copy 8-bit recording engine.
 *
 * Camera2 writes directly into one external-OES SurfaceTexture. The same GPU
 * texture is drawn by the DigLog shader to both the TextureView preview surface
 * and MediaCodec's input surface. No ImageReader, YUV plane copy, CPU colour
 * conversion, or per-frame texture upload is involved.
 *
 * Pipeline:
 * Camera2 -> SurfaceTexture/OES -> DigLog GLSL -> preview + encoder EGL surfaces
 * -> MediaCodec -> MediaMuxer.
 */
class DigLogV4Engine(
    private val camera: CameraDevice,
    private val size: Size,
    private val fps: Int,
    private val bitrate: Int,
    private val output: File,
    private val previewSurface: Surface,
    private val background: Handler,
    private val configureRequest: (CaptureRequest.Builder) -> Unit,
    private val onReady: (String) -> Unit,
    private val onError: (String) -> Unit,
) : DigLogEngine {
    private companion object {
        const val TAG = "DigLogV4"
        const val EOS_DRAIN_TIMEOUT_MS = 5_000L
    }

    override val actualBitDepth: Int = 8
    override val codecName: String get() = codecLabel

    private var session: CameraCaptureSession? = null
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var encoderSurface: Surface? = null
    private var renderer: OesDigLogRenderer? = null
    private var cameraInputSurface: Surface? = null

    private var trackIndex = -1
    private var codecLabel = "H.264"
    private var encodedSamples = 0
    private var renderedFrames = 0
    private var muxerStarted = false
    private var muxerStopped = false
    private var eosSubmitted = false
    private var eosReceived = false
    private var eosTimedOut = false
    private var fatalError = false

    private val running = AtomicBoolean(false)
    private val stopping = AtomicBoolean(false)
    private val failed = AtomicBoolean(false)
    private val resourcesReleased = AtomicBoolean(false)
    private val frameScheduled = AtomicBoolean(false)

    private val codecDrain = object : Runnable {
        override fun run() {
            if (!running.get() || failed.get()) return
            try {
                drainEncoder(false)
                background.postDelayed(this, 8L)
            } catch (t: Throwable) {
                failOnce("continuous encoder drain failed: ${t.message ?: t.javaClass.simpleName}")
            }
        }
    }

    override fun start() {
        background.post { startOnWorker() }
    }

    private fun startOnWorker() {
        try {
            configureEncoderWithFallback()
            val activeRenderer = OesDigLogRenderer(
                encoderWindow = requireNotNull(encoderSurface),
                previewWindow = previewSurface,
                bufferWidth = size.width,
                bufferHeight = size.height,
            )
            renderer = activeRenderer
            cameraInputSurface = activeRenderer.cameraSurface

            activeRenderer.setFrameListener(background) {
                // Some devices can deliver callbacks faster than a frame can be
                // rendered. Coalesce callbacks while always consuming the newest
                // SurfaceTexture image, preventing an unbounded handler backlog.
                if (!running.get() || !frameScheduled.compareAndSet(false, true)) return@setFrameListener
                background.post {
                    try {
                        if (!running.get()) return@post
                        val timestampNs = activeRenderer.drawLatestFrame()
                        renderedFrames++
                        if (renderedFrames <= 3 || renderedFrames % 30 == 0) {
                            Log.d(TAG, "Rendered frame count=$renderedFrames, timestamp=$timestampNs")
                        }
                        drainEncoder(false)
                    } catch (t: Throwable) {
                        failOnce("frame render failed: ${t.message ?: t.javaClass.simpleName}")
                    } finally {
                        frameScheduled.set(false)
                    }
                }
            }

            val cameraSurface = requireNotNull(cameraInputSurface)
            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(cameraSurface)
                configureRequest(this)
            }

            camera.createCaptureSession(listOf(cameraSurface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(value: CameraCaptureSession) {
                    if (failed.get()) {
                        value.close()
                        return
                    }
                    try {
                        session = value
                        codec?.start()
                        running.set(true)
                        background.post(codecDrain)
                        value.setRepeatingRequest(request.build(), null, background)
                        Log.d(TAG, "V4 zero-copy capture session configured")
                        onReady(codecLabel)
                    } catch (t: Throwable) {
                        failOnce("session start failed: ${t.message ?: t.javaClass.simpleName}")
                    }
                }

                override fun onConfigureFailed(value: CameraCaptureSession) {
                    value.close()
                    failOnce("camera session could not be configured")
                }
            }, background)
        } catch (t: Throwable) {
            failOnce("could not start: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    override fun outputIsValid(): Boolean =
        muxerStarted && muxerStopped && encodedSamples > 0 && renderedFrames > 0 &&
            !fatalError && !eosTimedOut && output.isFile && output.length() > 1_024L

    override fun stop(): Boolean {
        if (Thread.currentThread() == background.looper.thread) return stopOnWorker()
        val finished = CountDownLatch(1)
        var success = false
        background.removeCallbacks(codecDrain)
        background.postAtFrontOfQueue {
            try {
                success = stopOnWorker()
            } finally {
                finished.countDown()
            }
        }
        return finished.await(8, TimeUnit.SECONDS) && success
    }

    private fun stopOnWorker(): Boolean {
        if (!stopping.compareAndSet(false, true)) return outputIsValid()
        if (!running.getAndSet(false)) {
            releaseResources()
            return false
        }

        return try {
            session?.let { activeSession ->
                runCatching { activeSession.stopRepeating() }
                runCatching { activeSession.abortCaptures() }
                runCatching { activeSession.close() }
            }
            session = null

            if (!eosSubmitted) {
                codec?.signalEndOfInputStream()
                eosSubmitted = true
                Log.d(TAG, "EOS submitted")
            }

            val deadline = SystemClock.elapsedRealtime() + EOS_DRAIN_TIMEOUT_MS
            while (!eosReceived && SystemClock.elapsedRealtime() < deadline) {
                drainEncoder(true)
            }
            if (!eosReceived) eosTimedOut = true
            check(eosReceived) { "timed out waiting for encoder EOS" }
            check(encodedSamples > 0) { "no encoded frames were written" }

            releaseResources()
            val valid = outputIsValid()
            Log.d(
                TAG,
                "Output validation: rendered=$renderedFrames, samples=$encodedSamples, " +
                    "bytes=${output.length()}, success=$valid",
            )
            check(valid) { "final output verification failed" }
            true
        } catch (t: Throwable) {
            fatalError = true
            Log.e(TAG, "Recording finalization failed", t)
            releaseResources()
            false
        }
    }

    private fun configureEncoderWithFallback() {
        val options = listOf(
            MediaFormat.MIMETYPE_VIDEO_HEVC to "HEVC",
            MediaFormat.MIMETYPE_VIDEO_AVC to "H.264",
        )
        var last: Throwable? = null
        for ((mime, label) in options) {
            try {
                val format = MediaFormat.createVideoFormat(mime, size.width, size.height).apply {
                    setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                    setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                    setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                    if (android.os.Build.VERSION.SDK_INT >= 24) {
                        setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_FULL)
                        setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                        setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
                    }
                }
                codec = MediaCodec.createEncoderByType(mime).also {
                    it.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    encoderSurface = it.createInputSurface()
                }
                muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                codecLabel = label
                return
            } catch (t: Throwable) {
                last = t
                runCatching { encoderSurface?.release() }
                encoderSurface = null
                runCatching { codec?.release() }
                codec = null
                runCatching { muxer?.release() }
                muxer = null
            }
        }
        throw IllegalStateException("No compatible surface encoder: ${last?.message}")
    }

    private fun drainEncoder(end: Boolean): Boolean {
        val encoder = codec ?: return false
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, if (end) 10_000 else 0)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> return false
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    check(!muxerStarted) { "Encoder format changed twice" }
                    trackIndex = requireNotNull(muxer).addTrack(encoder.outputFormat)
                    requireNotNull(muxer).start()
                    muxerStarted = true
                    Log.d(TAG, "MediaMuxer started")
                }
                index >= 0 -> {
                    val data = encoder.getOutputBuffer(index)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (data != null && info.size > 0 && muxerStarted) {
                        data.position(info.offset)
                        data.limit(info.offset + info.size)
                        requireNotNull(muxer).writeSampleData(trackIndex, data, info)
                        encodedSamples++
                        if (encodedSamples <= 3 || encodedSamples % 30 == 0) {
                            Log.d(TAG, "Encoded frame count=$encodedSamples")
                        }
                    }
                    val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    encoder.releaseOutputBuffer(index, false)
                    if (eos) {
                        eosReceived = true
                        Log.d(TAG, "Encoder EOS received")
                        return true
                    }
                }
            }
        }
    }

    private fun failOnce(message: String) {
        if (!failed.compareAndSet(false, true)) return
        fatalError = true
        running.set(false)
        Log.e(TAG, "Recording failed: $message")
        releaseResources()
        onError(message)
    }

    private fun releaseResources() {
        if (!resourcesReleased.compareAndSet(false, true)) return
        running.set(false)
        background.removeCallbacks(codecDrain)

        session?.let { runCatching { it.close() } }
        session = null

        muxer?.let { activeMuxer ->
            if (eosReceived && muxerStarted && !muxerStopped) {
                muxerStopped = true
                try {
                    activeMuxer.stop()
                    Log.d(TAG, "Muxer stopped; final file size=${output.length()}")
                } catch (t: Throwable) {
                    fatalError = true
                    Log.e(TAG, "Muxer stop failed", t)
                }
            }
            runCatching { activeMuxer.release() }
        }
        muxer = null

        codec?.let {
            runCatching { it.stop() }
            runCatching { it.release() }
        }
        codec = null

        cameraInputSurface?.let { runCatching { it.release() } }
        cameraInputSurface = null
        renderer?.let { runCatching { it.release() } }
        renderer = null
        encoderSurface?.let { runCatching { it.release() } }
        encoderSurface = null
        runCatching { previewSurface.release() }
    }

    /** Owns the shared EGL context, external camera texture and both windows. */
    private class OesDigLogRenderer(
        encoderWindow: Surface,
        previewWindow: Surface,
        bufferWidth: Int,
        bufferHeight: Int,
    ) {
        private val display: EGLDisplay
        private val context: EGLContext
        private val config: EGLConfig
        private val encoderEglSurface: EGLSurface
        private val previewEglSurface: EGLSurface
        private val oesTexture: Int
        private val surfaceTexture: SurfaceTexture
        val cameraSurface: Surface

        private val program: Int
        private val positionLocation: Int
        private val texCoordLocation: Int
        private val textureMatrixLocation: Int
        private val samplerLocation: Int
        private val textureMatrix = FloatArray(16)
        private val vertices: FloatBuffer = ByteBuffer.allocateDirect(16 * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
                put(
                    floatArrayOf(
                        -1f, -1f, 0f, 0f,
                         1f, -1f, 1f, 0f,
                        -1f,  1f, 0f, 1f,
                         1f,  1f, 1f, 1f,
                    ),
                )
                flip()
            }

        init {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            check(display != EGL14.EGL_NO_DISPLAY) { "No EGL display" }
            val versions = IntArray(2)
            check(EGL14.eglInitialize(display, versions, 0, versions, 1)) { "EGL init failed" }

            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            val attrs = intArrayOf(
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_RENDERABLE_TYPE, EGLExt.EGL_OPENGL_ES3_BIT_KHR,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
                EGL_RECORDABLE_ANDROID, 1,
                EGL14.EGL_NONE,
            )
            check(EGL14.eglChooseConfig(display, attrs, 0, configs, 0, 1, count, 0) && count[0] > 0) {
                "No recordable EGL config"
            }
            config = configs[0]!!
            context = EGL14.eglCreateContext(
                display,
                config,
                EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE),
                0,
            )
            check(context != EGL14.EGL_NO_CONTEXT) { "EGL context creation failed" }

            encoderEglSurface = createWindowSurface(encoderWindow, "encoder")
            previewEglSurface = createWindowSurface(previewWindow, "preview")
            makeCurrent(encoderEglSurface)

            val textures = IntArray(1)
            GLES30.glGenTextures(1, textures, 0)
            oesTexture = textures[0]
            GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTexture)
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)

            surfaceTexture = SurfaceTexture(oesTexture).apply {
                setDefaultBufferSize(bufferWidth, bufferHeight)
            }
            cameraSurface = Surface(surfaceTexture)

            program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            positionLocation = GLES30.glGetAttribLocation(program, "aPosition")
            texCoordLocation = GLES30.glGetAttribLocation(program, "aTexCoord")
            textureMatrixLocation = GLES30.glGetUniformLocation(program, "uTextureMatrix")
            samplerLocation = GLES30.glGetUniformLocation(program, "uCameraTexture")
            checkGl("renderer initialization")
        }

        fun setFrameListener(handler: Handler, callback: () -> Unit) {
            surfaceTexture.setOnFrameAvailableListener({ callback() }, handler)
        }

        /** Consumes the newest camera buffer and returns its nanosecond timestamp. */
        fun drawLatestFrame(): Long {
            makeCurrent(encoderEglSurface)
            surfaceTexture.updateTexImage()
            surfaceTexture.getTransformMatrix(textureMatrix)
            val timestampNs = surfaceTexture.timestamp

            drawTo(encoderEglSurface, timestampNs, setPresentationTime = true)
            drawTo(previewEglSurface, timestampNs, setPresentationTime = false)
            return timestampNs
        }

        private fun drawTo(target: EGLSurface, timestampNs: Long, setPresentationTime: Boolean) {
            makeCurrent(target)
            val width = querySurface(target, EGL14.EGL_WIDTH)
            val height = querySurface(target, EGL14.EGL_HEIGHT)
            GLES30.glViewport(0, 0, width, height)
            GLES30.glUseProgram(program)

            vertices.position(0)
            GLES30.glVertexAttribPointer(positionLocation, 2, GLES30.GL_FLOAT, false, 16, vertices)
            GLES30.glEnableVertexAttribArray(positionLocation)
            vertices.position(2)
            GLES30.glVertexAttribPointer(texCoordLocation, 2, GLES30.GL_FLOAT, false, 16, vertices)
            GLES30.glEnableVertexAttribArray(texCoordLocation)

            GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
            GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTexture)
            GLES30.glUniform1i(samplerLocation, 0)
            GLES30.glUniformMatrix4fv(textureMatrixLocation, 1, false, textureMatrix, 0)
            GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
            checkGl("DigLog shader draw")

            if (setPresentationTime) {
                EGLExt.eglPresentationTimeANDROID(display, target, timestampNs)
            }
            check(EGL14.eglSwapBuffers(display, target)) {
                "eglSwapBuffers failed: 0x${Integer.toHexString(EGL14.eglGetError())}"
            }
        }

        private fun querySurface(surface: EGLSurface, attribute: Int): Int {
            val value = IntArray(1)
            check(EGL14.eglQuerySurface(display, surface, attribute, value, 0)) { "eglQuerySurface failed" }
            return value[0]
        }

        private fun createWindowSurface(window: Surface, label: String): EGLSurface {
            val result = EGL14.eglCreateWindowSurface(display, config, window, intArrayOf(EGL14.EGL_NONE), 0)
            check(result != EGL14.EGL_NO_SURFACE) {
                "$label EGL surface failed: 0x${Integer.toHexString(EGL14.eglGetError())}"
            }
            return result
        }

        private fun makeCurrent(surface: EGLSurface) {
            check(EGL14.eglMakeCurrent(display, surface, surface, context)) {
                "eglMakeCurrent failed: 0x${Integer.toHexString(EGL14.eglGetError())}"
            }
        }

        fun release() {
            surfaceTexture.setOnFrameAvailableListener(null)
            runCatching { cameraSurface.release() }
            runCatching { surfaceTexture.release() }
            runCatching { makeCurrent(encoderEglSurface); GLES30.glDeleteProgram(program) }
            runCatching { GLES30.glDeleteTextures(1, intArrayOf(oesTexture), 0) }
            runCatching {
                EGL14.eglMakeCurrent(
                    display,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_CONTEXT,
                )
            }
            runCatching { EGL14.eglDestroySurface(display, previewEglSurface) }
            runCatching { EGL14.eglDestroySurface(display, encoderEglSurface) }
            runCatching { EGL14.eglDestroyContext(display, context) }
            runCatching { EGL14.eglTerminate(display) }
        }

        private fun checkGl(operation: String) {
            val error = GLES30.glGetError()
            check(error == GLES30.GL_NO_ERROR) { "$operation failed: 0x${Integer.toHexString(error)}" }
        }

        private fun createProgram(vertexSource: String, fragmentSource: String): Int {
            fun compile(type: Int, source: String): Int {
                val shader = GLES30.glCreateShader(type)
                GLES30.glShaderSource(shader, source.trimStart('\uFEFF', '\n', '\r', ' ', '\t'))
                GLES30.glCompileShader(shader)
                val status = IntArray(1)
                GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
                if (status[0] == 0) {
                    val log = GLES30.glGetShaderInfoLog(shader)
                    GLES30.glDeleteShader(shader)
                    throw IllegalStateException("Shader compilation failed: $log")
                }
                return shader
            }

            val vertex = compile(GLES30.GL_VERTEX_SHADER, vertexSource)
            val fragment = compile(GLES30.GL_FRAGMENT_SHADER, fragmentSource)
            val result = GLES30.glCreateProgram()
            GLES30.glAttachShader(result, vertex)
            GLES30.glAttachShader(result, fragment)
            GLES30.glLinkProgram(result)
            val status = IntArray(1)
            GLES30.glGetProgramiv(result, GLES30.GL_LINK_STATUS, status, 0)
            val log = GLES30.glGetProgramInfoLog(result)
            GLES30.glDeleteShader(vertex)
            GLES30.glDeleteShader(fragment)
            check(status[0] != 0) { "Program link failed: $log" }
            return result
        }

        companion object {
            private const val EGL_RECORDABLE_ANDROID = 0x3142

            private const val VERTEX_SHADER = """#version 300 es
                in vec2 aPosition;
                in vec2 aTexCoord;
                uniform mat4 uTextureMatrix;
                out vec2 vTexCoord;
                void main() {
                    gl_Position = vec4(aPosition, 0.0, 1.0);
                    vTexCoord = (uTextureMatrix * vec4(aTexCoord, 0.0, 1.0)).xy;
                }
            """

            private const val FRAGMENT_SHADER = """#version 300 es
                #extension GL_OES_EGL_image_external_essl3 : require
                precision highp float;
                uniform samplerExternalOES uCameraTexture;
                in vec2 vTexCoord;
                out vec4 fragColor;

                float digLog(float x) {
                    x = max(x, 0.0);
                    const float gray = 0.18;
                    const float toeAtGray = 0.28 * (1.0 - exp(-gray / 0.18));
                    float encoded = x <= gray
                        ? 0.28 * (1.0 - exp(-x / 0.18))
                        : toeAtGray + 0.28 + 0.38 * log(1.0 + 2.4 * (x - gray));
                    return clamp(encoded, 0.0, 1.0);
                }

                void main() {
                    vec3 rgb = clamp(texture(uCameraTexture, vTexCoord).rgb, 0.0, 1.0);
                    float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
                    vec3 chroma = rgb - vec3(luma);
                    vec3 softened = vec3(luma) + chroma * 0.82;
                    fragColor = vec4(
                        digLog(softened.r),
                        digLog(softened.g),
                        digLog(softened.b),
                        1.0
                    );
                }
            """
        }
    }
}
