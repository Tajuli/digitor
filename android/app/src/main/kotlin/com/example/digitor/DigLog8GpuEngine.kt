package com.example.digitor

import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.media.*
import android.opengl.*
import android.os.Handler
import android.util.Size
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Real-time 8-bit DigLog pipeline.
 *
 * Camera2 -> external OES texture -> GLSL DigLog transfer/gamut transform ->
 * AVC/HEVC encoder surface -> MP4. The transform is applied before encoding.
 * Camera ISP processing still precedes the public SurfaceTexture output on normal
 * Android devices; this class does not claim RAW sensor access.
 */
class DigLog8GpuEngine(
    private val camera: CameraDevice,
    private val size: Size,
    private val fps: Int,
    private val bitrate: Int,
    private val output: File,
    private val previewSurface: Surface?,
    private val background: Handler,
    private val configureRequest: (CaptureRequest.Builder) -> Unit,
    private val onReady: (codec: String) -> Unit,
    private val onError: (String) -> Unit,
) {
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var encoderInput: Surface? = null
    private var cameraTexture: SurfaceTexture? = null
    private var cameraInput: Surface? = null
    private var session: CameraCaptureSession? = null
    private var renderer: Renderer? = null
    private var track = -1
    private var muxerStarted = false
    private val running = AtomicBoolean(false)
    private var firstTimestamp = -1L
    private var codecLabel = "H.264"

    fun start() {
        try {
            configureEncoder()
            val r = Renderer(encoderInput!!, previewSurface, size.width, size.height)
            renderer = r
            cameraTexture = r.cameraTexture.apply {
                setDefaultBufferSize(size.width, size.height)
                setOnFrameAvailableListener({ renderFrame() }, background)
            }
            cameraInput = Surface(cameraTexture)

            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(cameraInput!!)
                configureRequest(this)
            }
            camera.createCaptureSession(listOf(cameraInput!!), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(value: CameraCaptureSession) {
                    session = value
                    codec?.start()
                    running.set(true)
                    value.setRepeatingRequest(request.build(), null, background)
                    onReady(codecLabel)
                }

                override fun onConfigureFailed(value: CameraCaptureSession) {
                    fail("GPU camera session could not be configured")
                }
            }, background)
        } catch (t: Throwable) {
            fail("DigLog GPU engine could not start: ${t.message}")
        }
    }

    private fun renderFrame() {
        if (!running.get()) return
        try {
            val texture = cameraTexture ?: return
            val timestamp = System.nanoTime()
            if (firstTimestamp < 0) firstTimestamp = timestamp
            renderer?.draw(texture, timestamp - firstTimestamp)
            drain(false)
        } catch (t: Throwable) {
            fail("DigLog GPU frame failed: ${t.message}")
        }
    }

    fun stop(): Boolean {
        if (!running.getAndSet(false)) return false
        return try {
            runCatching { session?.stopRepeating() }
            runCatching { session?.abortCaptures() }
            codec?.signalEndOfInputStream()
            var loops = 0
            while (loops++ < 150 && drain(true)) Unit
            true
        } catch (_: Throwable) {
            false
        } finally {
            release()
        }
    }

    private fun configureEncoder() {
        val choices = listOf(
            MediaFormat.MIMETYPE_VIDEO_HEVC to "HEVC",
            MediaFormat.MIMETYPE_VIDEO_AVC to "H.264",
        )
        var last: Throwable? = null
        for ((mime, label) in choices) {
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
                    encoderInput = it.createInputSurface()
                }
                codecLabel = label
                muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                return
            } catch (t: Throwable) {
                last = t
                runCatching { encoderInput?.release() }; encoderInput = null
                runCatching { codec?.release() }; codec = null
            }
        }
        throw IllegalStateException("No compatible surface video encoder", last)
    }

    private fun drain(end: Boolean): Boolean {
        val c = codec ?: return false
        val info = MediaCodec.BufferInfo()
        while (true) {
            when (val index = c.dequeueOutputBuffer(info, if (end) 10_000 else 0)) {
                MediaCodec.INFO_TRY_AGAIN_LATER -> return end
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer!!.addTrack(c.outputFormat)
                    muxer!!.start()
                    muxerStarted = true
                }
                else -> if (index >= 0) {
                    val data = c.getOutputBuffer(index)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0 && data != null && muxerStarted) {
                        data.position(info.offset)
                        data.limit(info.offset + info.size)
                        muxer!!.writeSampleData(track, data, info)
                    }
                    val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    c.releaseOutputBuffer(index, false)
                    if (eos) return false
                }
            }
        }
    }

    private fun fail(message: String) {
        if (running.getAndSet(false)) release() else release()
        onError(message)
    }

    private fun release() {
        runCatching { session?.close() }; session = null
        runCatching { cameraInput?.release() }; cameraInput = null
        runCatching { renderer?.release() }; renderer = null
        runCatching { cameraTexture?.release() }; cameraTexture = null
        runCatching { codec?.stop() }
        runCatching { codec?.release() }; codec = null
        if (muxerStarted) runCatching { muxer?.stop() }
        runCatching { muxer?.release() }; muxer = null
        runCatching { encoderInput?.release() }; encoderInput = null
    }

    private class Renderer(
        encoderSurface: Surface,
        previewSurface: Surface?,
        private val width: Int,
        private val height: Int,
    ) {
        private val display: EGLDisplay
        private val context: EGLContext
        private val encoderEgl: EGLSurface
        private val previewEgl: EGLSurface?
        private val program: Int
        private val textureId: Int
        val cameraTexture: SurfaceTexture
        private val matrix = FloatArray(16)
        private val vertexBuffer: FloatBuffer

        init {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            check(display != EGL14.EGL_NO_DISPLAY)
            val version = IntArray(2)
            check(EGL14.eglInitialize(display, version, 0, version, 1))
            val configAttrs = intArrayOf(
                EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL_RECORDABLE_ANDROID, 1, EGL14.EGL_NONE,
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            check(EGL14.eglChooseConfig(display, configAttrs, 0, configs, 0, 1, count, 0))
            val config = configs[0] ?: error("No recordable EGL config")
            context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
            encoderEgl = EGL14.eglCreateWindowSurface(display, config, encoderSurface,
                intArrayOf(EGL14.EGL_NONE), 0)
            previewEgl = previewSurface?.let {
                EGL14.eglCreateWindowSurface(display, config, it, intArrayOf(EGL14.EGL_NONE), 0)
            }
            makeCurrent(encoderEgl)
            program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            textureId = createExternalTexture()
            cameraTexture = SurfaceTexture(textureId)
            vertexBuffer = ByteBuffer.allocateDirect(VERTICES.size * 4)
                .order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(VERTICES); position(0) }
        }

        fun draw(texture: SurfaceTexture, presentationNs: Long) {
            makeCurrent(encoderEgl)
            texture.updateTexImage()
            texture.getTransformMatrix(matrix)
            render(width, height)
            EGLExt.eglPresentationTimeANDROID(display, encoderEgl, presentationNs)
            check(EGL14.eglSwapBuffers(display, encoderEgl))

            previewEgl?.let {
                makeCurrent(it)
                render(width, height)
                EGL14.eglSwapBuffers(display, it)
            }
        }

        private fun render(w: Int, h: Int) {
            GLES20.glViewport(0, 0, w, h)
            GLES20.glUseProgram(program)
            val pos = GLES20.glGetAttribLocation(program, "aPosition")
            val tex = GLES20.glGetAttribLocation(program, "aTexCoord")
            vertexBuffer.position(0)
            GLES20.glEnableVertexAttribArray(pos)
            GLES20.glVertexAttribPointer(pos, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
            vertexBuffer.position(2)
            GLES20.glEnableVertexAttribArray(tex)
            GLES20.glVertexAttribPointer(tex, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
            GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(program, "uTexMatrix"), 1, false, matrix, 0)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
            GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "uTexture"), 0)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }

        private fun makeCurrent(surface: EGLSurface) {
            check(EGL14.eglMakeCurrent(display, surface, surface, context))
        }

        fun release() {
            runCatching { cameraTexture.detachFromGLContext() }
            GLES20.glDeleteProgram(program)
            GLES20.glDeleteTextures(1, intArrayOf(textureId), 0)
            previewEgl?.let { EGL14.eglDestroySurface(display, it) }
            EGL14.eglDestroySurface(display, encoderEgl)
            EGL14.eglDestroyContext(display, context)
            EGL14.eglReleaseThread()
            EGL14.eglTerminate(display)
        }

        companion object {
            private const val EGL_RECORDABLE_ANDROID = 0x3142
            private val VERTICES = floatArrayOf(
                -1f, -1f, 0f, 0f,
                 1f, -1f, 1f, 0f,
                -1f,  1f, 0f, 1f,
                 1f,  1f, 1f, 1f,
            )
            private const val VERTEX_SHADER = """
                attribute vec4 aPosition;
                attribute vec4 aTexCoord;
                uniform mat4 uTexMatrix;
                varying vec2 vTexCoord;
                void main() {
                    gl_Position = aPosition;
                    vTexCoord = (uTexMatrix * aTexCoord).xy;
                }
            """
            private const val FRAGMENT_SHADER = """
                #extension GL_OES_EGL_image_external : require
                precision highp float;
                uniform samplerExternalOES uTexture;
                varying vec2 vTexCoord;

                float linearize(float x) {
                    return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4);
                }
                float diglog(float x) {
                    x = max(x, 0.0);
                    // Raised toe + logarithmic shoulder, mapped into legal grading room.
                    float y = log2(1.0 + 15.0 * x) / 4.0;
                    return 0.075 + 0.82 * y;
                }
                void main() {
                    vec3 srgb = texture2D(uTexture, vTexCoord).rgb;
                    vec3 linear = vec3(linearize(srgb.r), linearize(srgb.g), linearize(srgb.b));
                    // Gentle saturation reduction protects channels during later grading.
                    float luma = dot(linear, vec3(0.2126, 0.7152, 0.0722));
                    linear = mix(vec3(luma), linear, 0.78);
                    vec3 encoded = vec3(diglog(linear.r), diglog(linear.g), diglog(linear.b));
                    gl_FragColor = vec4(clamp(encoded, 0.0, 1.0), 1.0);
                }
            """

            private fun createExternalTexture(): Int {
                val ids = IntArray(1)
                GLES20.glGenTextures(1, ids, 0)
                GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, ids[0])
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
                return ids[0]
            }

            private fun createProgram(vertex: String, fragment: String): Int {
                val v = compile(GLES20.GL_VERTEX_SHADER, vertex)
                val f = compile(GLES20.GL_FRAGMENT_SHADER, fragment)
                return GLES20.glCreateProgram().also {
                    GLES20.glAttachShader(it, v); GLES20.glAttachShader(it, f); GLES20.glLinkProgram(it)
                    val ok = IntArray(1); GLES20.glGetProgramiv(it, GLES20.GL_LINK_STATUS, ok, 0)
                    if (ok[0] == 0) error("GL program link failed: ${GLES20.glGetProgramInfoLog(it)}")
                    GLES20.glDeleteShader(v); GLES20.glDeleteShader(f)
                }
            }

            private fun compile(type: Int, source: String): Int = GLES20.glCreateShader(type).also {
                GLES20.glShaderSource(it, source); GLES20.glCompileShader(it)
                val ok = IntArray(1); GLES20.glGetShaderiv(it, GLES20.GL_COMPILE_STATUS, ok, 0)
                if (ok[0] == 0) error("GL shader failed: ${GLES20.glGetShaderInfoLog(it)}")
            }
        }
    }
}
