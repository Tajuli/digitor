package com.example.digitor

import android.graphics.ImageFormat
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
 * DigLog V3 8-bit engine.
 *
 * Camera preview is a normal, independent Camera2 output. Processing uses a
 * separate YUV_420_888 ImageReader. Only the encoder's own Surface is attached
 * to EGL, so no SurfaceTexture is connected to two producers/APIs.
 */
class DigLogV3Engine(
    private val camera: CameraDevice,
    private val size: Size,
    private val fps: Int,
    private val bitrate: Int,
    private val output: File,
    private val previewSurface: Surface?,
    private val background: Handler,
    private val configureRequest: (CaptureRequest.Builder) -> Unit,
    private val onReady: (String) -> Unit,
    private val onError: (String) -> Unit,
) {
    private var imageReader: ImageReader? = null
    private var session: CameraCaptureSession? = null
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var encoderSurface: Surface? = null
    private var renderer: YuvEglRenderer? = null
    private var trackIndex = -1
    private var muxerStarted = false
    private val running = AtomicBoolean(false)
    private val failed = AtomicBoolean(false)
    private var firstTimestampNs = -1L
    private var codecLabel = "H.264"

    fun start() {
        try {
            configureEncoderWithFallback()
            val reader = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 3)
            imageReader = reader
            renderer = YuvEglRenderer(encoderSurface!!, size.width, size.height)

            reader.setOnImageAvailableListener({ source ->
                val image = source.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    if (!running.get()) return@setOnImageAvailableListener
                    val pts = if (firstTimestampNs < 0L) {
                        firstTimestampNs = image.timestamp
                        0L
                    } else image.timestamp - firstTimestampNs
                    renderer?.draw(YuvFrame.from(image), pts)
                    drainEncoder(false)
                } catch (t: Throwable) {
                    failOnce("DigLog V3 frame processing failed: ${t.message ?: t.javaClass.simpleName}")
                } finally {
                    image.close()
                }
            }, background)

            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(reader.surface)
                previewSurface?.let(::addTarget)
                configureRequest(this)
            }
            val outputs = mutableListOf(reader.surface).apply { previewSurface?.let(::add) }
            camera.createCaptureSession(outputs, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(value: CameraCaptureSession) {
                    if (failed.get()) { value.close(); return }
                    try {
                        session = value
                        codec?.start()
                        running.set(true)
                        value.setRepeatingRequest(request.build(), null, background)
                        onReady(codecLabel)
                    } catch (t: Throwable) {
                        failOnce("DigLog V3 session start failed: ${t.message}")
                    }
                }

                override fun onConfigureFailed(value: CameraCaptureSession) {
                    value.close()
                    failOnce("DigLog V3 camera session could not be configured")
                }
            }, background)
        } catch (t: Throwable) {
            release()
            failOnce("DigLog V3 could not start: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    fun stop(): Boolean {
        if (!running.getAndSet(false)) { release(); return false }
        return try {
            runCatching { session?.stopRepeating() }
            runCatching { session?.abortCaptures() }
            codec?.signalEndOfInputStream()
            var loops = 0
            while (loops++ < 150 && drainEncoder(true)) Unit
            true
        } catch (_: Throwable) {
            false
        } finally {
            release()
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
                runCatching { encoderSurface?.release() }; encoderSurface = null
                runCatching { codec?.release() }; codec = null
                runCatching { muxer?.release() }; muxer = null
            }
        }
        throw IllegalStateException("No compatible surface encoder: ${last?.message}")
    }

    /** Returns true while an EOS drain may need another poll. */
    private fun drainEncoder(end: Boolean): Boolean {
        val encoder = codec ?: return false
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, if (end) 10_000 else 0)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> return end
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    check(!muxerStarted) { "Encoder format changed twice" }
                    trackIndex = muxer!!.addTrack(encoder.outputFormat)
                    muxer!!.start()
                    muxerStarted = true
                }
                index >= 0 -> {
                    val data = encoder.getOutputBuffer(index)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (data != null && info.size > 0 && muxerStarted) {
                        data.position(info.offset)
                        data.limit(info.offset + info.size)
                        muxer!!.writeSampleData(trackIndex, data, info)
                    }
                    val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    encoder.releaseOutputBuffer(index, false)
                    if (eos) return false
                }
            }
        }
    }

    private fun failOnce(message: String) {
        if (!failed.compareAndSet(false, true)) return
        running.set(false)
        release()
        onError(message)
    }

    private fun release() {
        running.set(false)
        runCatching { session?.close() }; session = null
        runCatching { imageReader?.close() }; imageReader = null
        runCatching { renderer?.release() }; renderer = null
        runCatching { codec?.stop() }
        runCatching { codec?.release() }; codec = null
        if (muxerStarted) runCatching { muxer?.stop() }
        muxerStarted = false
        runCatching { muxer?.release() }; muxer = null
        runCatching { encoderSurface?.release() }; encoderSurface = null
    }

    private data class YuvFrame(
        val y: ByteBuffer,
        val u: ByteBuffer,
        val v: ByteBuffer,
        val width: Int,
        val height: Int,
    ) {
        companion object {
            fun from(image: Image): YuvFrame {
                require(image.format == ImageFormat.YUV_420_888)
                return YuvFrame(
                    copyPlane(image.planes[0], image.width, image.height),
                    copyPlane(image.planes[1], image.width / 2, image.height / 2),
                    copyPlane(image.planes[2], image.width / 2, image.height / 2),
                    image.width,
                    image.height,
                )
            }

            private fun copyPlane(plane: Image.Plane, width: Int, height: Int): ByteBuffer {
                val src = plane.buffer.duplicate()
                val out = ByteBuffer.allocateDirect(width * height).order(ByteOrder.nativeOrder())
                val rowStride = plane.rowStride
                val pixelStride = plane.pixelStride
                for (row in 0 until height) {
                    val rowStart = row * rowStride
                    for (col in 0 until width) {
                        val offset = rowStart + col * pixelStride
                        out.put(if (offset < src.limit()) src.get(offset) else 0)
                    }
                }
                out.flip()
                return out
            }
        }
    }

    private class YuvEglRenderer(surface: Surface, private val width: Int, private val height: Int) {
        private val display: EGLDisplay
        private val context: EGLContext
        private val eglSurface: EGLSurface
        private val program: Int
        private val textures = IntArray(3)
        private val vertices: FloatBuffer = ByteBuffer.allocateDirect(16 * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
                put(floatArrayOf(
                    -1f, -1f, 0f, 1f,
                     1f, -1f, 1f, 1f,
                    -1f,  1f, 0f, 0f,
                     1f,  1f, 1f, 0f,
                )); flip()
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
                EGL14.EGL_NONE,
            )
            check(EGL14.eglChooseConfig(display, attrs, 0, configs, 0, 1, count, 0) && count[0] > 0) { "No EGL8888 config" }
            val config = configs[0]!!
            context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE), 0)
            check(context != EGL14.EGL_NO_CONTEXT) { "EGL context failed" }
            eglSurface = EGL14.eglCreateWindowSurface(display, config, surface, intArrayOf(EGL14.EGL_NONE), 0)
            check(eglSurface != EGL14.EGL_NO_SURFACE) { "Encoder EGL surface failed: 0x${Integer.toHexString(EGL14.eglGetError())}" }
            check(EGL14.eglMakeCurrent(display, eglSurface, eglSurface, context)) { "EGL makeCurrent failed" }
            program = createProgram(VERTEX, FRAGMENT)
            GLES30.glGenTextures(3, textures, 0)
            textures.forEach { id ->
                GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, id)
                GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
                GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
                GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
                GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
            }
        }

        fun draw(frame: YuvFrame, timestampNs: Long) {
            check(EGL14.eglMakeCurrent(display, eglSurface, eglSurface, context))
            GLES30.glViewport(0, 0, width, height)
            GLES30.glUseProgram(program)
            upload(0, frame.width, frame.height, frame.y)
            upload(1, frame.width / 2, frame.height / 2, frame.u)
            upload(2, frame.width / 2, frame.height / 2, frame.v)

            val pos = GLES30.glGetAttribLocation(program, "aPos")
            val tex = GLES30.glGetAttribLocation(program, "aTex")
            vertices.position(0)
            GLES30.glVertexAttribPointer(pos, 2, GLES30.GL_FLOAT, false, 16, vertices)
            GLES30.glEnableVertexAttribArray(pos)
            vertices.position(2)
            GLES30.glVertexAttribPointer(tex, 2, GLES30.GL_FLOAT, false, 16, vertices)
            GLES30.glEnableVertexAttribArray(tex)
            for (i in 0..2) {
                GLES30.glActiveTexture(GLES30.GL_TEXTURE0 + i)
                GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, textures[i])
                GLES30.glUniform1i(GLES30.glGetUniformLocation(program, arrayOf("uY", "uU", "uV")[i]), i)
            }
            GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
            EGLExt.eglPresentationTimeANDROID(display, eglSurface, timestampNs)
            check(EGL14.eglSwapBuffers(display, eglSurface)) { "Encoder swap failed: 0x${Integer.toHexString(EGL14.eglGetError())}" }
        }

        private fun upload(index: Int, w: Int, h: Int, data: ByteBuffer) {
            data.position(0)
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0 + index)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, textures[index])
            GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 1)
            GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_R8, w, h, 0, GLES30.GL_RED, GLES30.GL_UNSIGNED_BYTE, data)
        }

        fun release() {
            if (display == EGL14.EGL_NO_DISPLAY) return
            runCatching { EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT) }
            runCatching { EGL14.eglDestroySurface(display, eglSurface) }
            runCatching { EGL14.eglDestroyContext(display, context) }
            runCatching { EGL14.eglTerminate(display) }
        }

        private fun createProgram(vertex: String, fragment: String): Int {
            fun compile(type: Int, source: String): Int {
                val shader = GLES30.glCreateShader(type)
                GLES30.glShaderSource(shader, source)
                GLES30.glCompileShader(shader)
                val status = IntArray(1)
                GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
                check(status[0] != 0) { GLES30.glGetShaderInfoLog(shader) }
                return shader
            }
            val vs = compile(GLES30.GL_VERTEX_SHADER, vertex)
            val fs = compile(GLES30.GL_FRAGMENT_SHADER, fragment)
            return GLES30.glCreateProgram().also { p ->
                GLES30.glAttachShader(p, vs)
                GLES30.glAttachShader(p, fs)
                GLES30.glLinkProgram(p)
                val status = IntArray(1)
                GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, status, 0)
                check(status[0] != 0) { GLES30.glGetProgramInfoLog(p) }
                GLES30.glDeleteShader(vs)
                GLES30.glDeleteShader(fs)
            }
        }

        companion object {
            private const val VERTEX = """
                #version 300 es
                in vec2 aPos;
                in vec2 aTex;
                out vec2 vTex;
                void main() { gl_Position = vec4(aPos, 0.0, 1.0); vTex = aTex; }
            """

            private const val FRAGMENT = """
                #version 300 es
                precision highp float;
                uniform sampler2D uY;
                uniform sampler2D uU;
                uniform sampler2D uV;
                in vec2 vTex;
                out vec4 fragColor;

                vec3 yuvToRgb(float y, float u, float v) {
                    y = clamp((y - 16.0/255.0) * (255.0/219.0), 0.0, 1.0);
                    u = (u - 0.5) * (255.0/224.0);
                    v = (v - 0.5) * (255.0/224.0);
                    return clamp(vec3(
                        y + 1.5748 * v,
                        y - 0.1873 * u - 0.4681 * v,
                        y + 1.8556 * u
                    ), 0.0, 1.0);
                }

                float digLog(float x) {
                    // A grading-oriented SDR log encoding: lifted toe, compressed
                    // upper mids, and a soft highlight shoulder. It does not claim
                    // extra sensor dynamic range; it preserves more of the ISP output.
                    x = max(x, 0.0);
                    float toe = 0.055 + 0.19 * sqrt(clamp(x, 0.0, 0.18) / 0.18);
                    float logPart = 0.245 + 0.52 * log2(1.0 + 7.5 * x) / log2(8.5);
                    float y = mix(toe, logPart, smoothstep(0.06, 0.22, x));
                    float shoulder = 1.0 - exp(-2.0 * max(x - 0.68, 0.0));
                    y -= shoulder * 0.08;
                    return clamp(y, 0.0, 0.94);
                }

                void main() {
                    float y = texture(uY, vTex).r;
                    float u = texture(uU, vTex).r;
                    float v = texture(uV, vTex).r;
                    vec3 rgb = yuvToRgb(y, u, v);
                    float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
                    vec3 chroma = rgb - vec3(luma);
                    vec3 linearSoft = vec3(luma) + chroma * 0.82;
                    vec3 encoded = vec3(digLog(linearSoft.r), digLog(linearSoft.g), digLog(linearSoft.b));
                    fragColor = vec4(encoded, 1.0);
                }
            """
        }
    }
}
