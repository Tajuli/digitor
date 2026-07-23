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
import java.nio.ShortBuffer
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/**
 * True 10-bit DigLog path.
 *
 * Camera2 YCBCR_P010 -> RGBA16F GPU texture -> DigLog shader ->
 * MediaCodec HEVC Main10 input surface -> MP4.
 *
 * It deliberately does not use an HDR/HLG transfer function. The shader writes
 * DigLog Gamma v1 code values into a 10-bit Main10 stream.
 */
class DigLog10Engine(
    private val camera: CameraDevice,
    private val cameraId: String,
    private val size: Size,
    private val fps: Int,
    private val bitrate: Int,
    private val output: File,
    private val previewSurface: Surface?,
    private val background: Handler,
    private val onReady: () -> Unit,
    private val onError: (String) -> Unit,
) {
    private var imageReader: ImageReader? = null
    private var session: CameraCaptureSession? = null
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var encoderSurface: Surface? = null
    private var egl: EglRenderer? = null
    private var trackIndex = -1
    private var muxerStarted = false
    private val running = AtomicBoolean(false)
    private var firstTimestampNs = -1L

    fun start() {
        try {
            configureEncoder()
            val reader = ImageReader.newInstance(size.width, size.height, ImageFormat.YCBCR_P010, 4)
            imageReader = reader
            egl = EglRenderer(encoderSurface!!, size.width, size.height)
            reader.setOnImageAvailableListener({ source ->
                val image = source.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    if (!running.get()) return@setOnImageAvailableListener
                    val pts = if (firstTimestampNs < 0) {
                        firstTimestampNs = image.timestamp
                        0L
                    } else image.timestamp - firstTimestampNs
                    val frame = P010Frame.from(image)
                    egl?.draw(frame, pts)
                    drainEncoder(false)
                } catch (t: Throwable) {
                    onError("DigLog 10 frame processing failed: ${t.message}")
                } finally {
                    image.close()
                }
            }, background)

            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(reader.surface)
                previewSurface?.let { addTarget(it) }
                set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                set(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AE_LOCK, true)
                set(CaptureRequest.CONTROL_AWB_MODE, CameraMetadata.CONTROL_AWB_MODE_AUTO)
                set(CaptureRequest.CONTROL_AWB_LOCK, true)
                set(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                set(CaptureRequest.NOISE_REDUCTION_MODE, CameraMetadata.NOISE_REDUCTION_MODE_MINIMAL)
                set(CaptureRequest.EDGE_MODE, CameraMetadata.EDGE_MODE_OFF)
                set(CaptureRequest.COLOR_CORRECTION_ABERRATION_MODE, CameraMetadata.COLOR_CORRECTION_ABERRATION_MODE_OFF)
                // No public Camera2 TONEMAP_MODE_BYPASS constant exists.
                // The custom DigLog transfer curve is applied later in the 10-bit GPU shader.
                set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF)
            }
            val outputs = mutableListOf(reader.surface).apply { previewSurface?.let { add(it) } }
            camera.createCaptureSession(outputs, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(value: CameraCaptureSession) {
                    session = value
                    running.set(true)
                    codec?.start()
                    value.setRepeatingRequest(request.build(), null, background)
                    onReady()
                }
                override fun onConfigureFailed(value: CameraCaptureSession) {
                    onError("P010 camera session could not be configured")
                }
            }, background)
        } catch (t: Throwable) {
            release()
            onError("DigLog 10 could not start: ${t.message}")
        }
    }

    fun stop(): Boolean {
        if (!running.getAndSet(false)) return false
        return try {
            runCatching { session?.stopRepeating() }
            runCatching { session?.abortCaptures() }
            codec?.signalEndOfInputStream()
            var attempts = 0
            while (attempts++ < 100 && drainEncoder(true)) Unit
            true
        } catch (_: Throwable) {
            false
        } finally {
            release()
        }
    }

    private fun configureEncoder() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_HEVC, size.width, size.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10)
            if (android.os.Build.VERSION.SDK_INT >= 24) {
                // Full-range, unspecified/custom transfer: not HLG or PQ.
                setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_FULL)
                setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT2020)
                setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_LINEAR)
            }
        }
        codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_HEVC).also {
            it.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoderSurface = it.createInputSurface()
        }
        muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    }

    /** Returns true while more EOS draining may be required. */
    private fun drainEncoder(end: Boolean): Boolean {
        val encoder = codec ?: return false
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, if (end) 10_000 else 0)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> return end
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (muxerStarted) throw IllegalStateException("Encoder format changed twice")
                    trackIndex = muxer!!.addTrack(encoder.outputFormat)
                    muxer!!.start()
                    muxerStarted = true
                }
                index >= 0 -> {
                    val data = encoder.getOutputBuffer(index) ?: throw IllegalStateException("Null encoder buffer")
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0) {
                        if (!muxerStarted) throw IllegalStateException("Muxer has not started")
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

    private fun release() {
        running.set(false)
        runCatching { session?.close() }; session = null
        runCatching { imageReader?.close() }; imageReader = null
        runCatching { egl?.release() }; egl = null
        runCatching { codec?.stop() }
        runCatching { codec?.release() }; codec = null
        if (muxerStarted) runCatching { muxer?.stop() }
        runCatching { muxer?.release() }; muxer = null
        runCatching { encoderSurface?.release() }; encoderSurface = null
    }

    private data class P010Frame(val y: ShortBuffer, val uv: ShortBuffer, val width: Int, val height: Int) {
        companion object {
            fun from(image: Image): P010Frame {
                require(image.format == ImageFormat.YCBCR_P010)
                return P010Frame(
                    copyPlane(image.planes[0], image.width, image.height, 1),
                    copyPlane(image.planes[1], image.width / 2, image.height / 2, 2),
                    image.width, image.height
                )
            }

            /** Removes OEM row padding and preserves the high 10 valid bits per component. */
            private fun copyPlane(plane: Image.Plane, width: Int, height: Int, components: Int): ShortBuffer {
                val src = plane.buffer.duplicate().order(ByteOrder.nativeOrder())
                val out = ByteBuffer.allocateDirect(width * height * components * 2).order(ByteOrder.nativeOrder()).asShortBuffer()
                val rowStride = plane.rowStride
                val pixelStride = plane.pixelStride
                for (row in 0 until height) {
                    val rowStart = row * rowStride
                    for (col in 0 until width) {
                        val pixelStart = rowStart + col * pixelStride
                        for (component in 0 until components) {
                            val offset = pixelStart + component * 2
                            if (offset + 1 < src.limit()) out.put(src.getShort(offset)) else out.put(0)
                        }
                    }
                }
                out.flip()
                return out
            }
        }
    }

    /** OpenGL ES 3 renderer. P010 planes are uploaded as 16-bit integer textures. */
    private class EglRenderer(surface: Surface, private val width: Int, private val height: Int) {
        private val display: EGLDisplay
        private val context: EGLContext
        private val eglSurface: EGLSurface
        private val program: Int
        private val yTexture: Int
        private val uvTexture: Int
        private val vertices: FloatBuffer = ByteBuffer.allocateDirect(16 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
            put(floatArrayOf(-1f,-1f,0f,1f, 1f,-1f,1f,1f, -1f,1f,0f,0f, 1f,1f,1f,0f)); flip()
        }

        init {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            check(display != EGL14.EGL_NO_DISPLAY)
            val versions = IntArray(2)
            check(EGL14.eglInitialize(display, versions, 0, versions, 1))
            val configAttrs = intArrayOf(
                EGL14.EGL_RED_SIZE, 10, EGL14.EGL_GREEN_SIZE, 10, EGL14.EGL_BLUE_SIZE, 10,
                EGL14.EGL_ALPHA_SIZE, 2, EGL14.EGL_RENDERABLE_TYPE, EGLExt.EGL_OPENGL_ES3_BIT_KHR,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT, EGL14.EGL_NONE
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            check(EGL14.eglChooseConfig(display, configAttrs, 0, configs, 0, 1, count, 0) && count[0] > 0)
            val config = configs[0]!!
            context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT, intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE), 0)
            check(context != EGL14.EGL_NO_CONTEXT)
            eglSurface = EGL14.eglCreateWindowSurface(display, config, surface, intArrayOf(EGL14.EGL_NONE), 0)
            check(eglSurface != EGL14.EGL_NO_SURFACE)
            check(EGL14.eglMakeCurrent(display, eglSurface, eglSurface, context))
            program = createProgram(VERTEX, FRAGMENT)
            yTexture = makeTexture()
            uvTexture = makeTexture()
        }

        fun draw(frame: P010Frame, timestampNs: Long) {
            EGL14.eglMakeCurrent(display, eglSurface, eglSurface, context)
            GLES30.glViewport(0, 0, width, height)
            GLES30.glUseProgram(program)
            upload(frame)
            val pos = GLES30.glGetAttribLocation(program, "aPos")
            val tex = GLES30.glGetAttribLocation(program, "aTex")
            vertices.position(0); GLES30.glVertexAttribPointer(pos, 2, GLES30.GL_FLOAT, false, 16, vertices); GLES30.glEnableVertexAttribArray(pos)
            vertices.position(2); GLES30.glVertexAttribPointer(tex, 2, GLES30.GL_FLOAT, false, 16, vertices); GLES30.glEnableVertexAttribArray(tex)
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0); GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, yTexture)
            GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uY"), 0)
            GLES30.glActiveTexture(GLES30.GL_TEXTURE1); GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, uvTexture)
            GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uUV"), 1)
            GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
            EGLExt.eglPresentationTimeANDROID(display, eglSurface, timestampNs)
            check(EGL14.eglSwapBuffers(display, eglSurface))
        }

        private fun upload(frame: P010Frame) {
            GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 2)
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, yTexture)
            GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_R16UI, frame.width, frame.height, 0, GLES30.GL_RED_INTEGER, GLES30.GL_UNSIGNED_SHORT, frame.y)
            GLES30.glActiveTexture(GLES30.GL_TEXTURE1)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, uvTexture)
            GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RG16UI, frame.width / 2, frame.height / 2, 0, GLES30.GL_RG_INTEGER, GLES30.GL_UNSIGNED_SHORT, frame.uv)
        }

        fun release() {
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(display, eglSurface)
            EGL14.eglDestroyContext(display, context)
            EGL14.eglTerminate(display)
        }

        private fun makeTexture(): Int {
            val id = IntArray(1); GLES30.glGenTextures(1, id, 0)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, id[0])
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
            return id[0]
        }

        private fun createProgram(vs: String, fs: String): Int {
            fun shader(type: Int, source: String): Int = GLES30.glCreateShader(type).also {
                GLES30.glShaderSource(it, source); GLES30.glCompileShader(it)
                val ok = IntArray(1); GLES30.glGetShaderiv(it, GLES30.GL_COMPILE_STATUS, ok, 0)
                check(ok[0] != 0) { GLES30.glGetShaderInfoLog(it) }
            }
            val v = shader(GLES30.GL_VERTEX_SHADER, vs); val f = shader(GLES30.GL_FRAGMENT_SHADER, fs)
            return GLES30.glCreateProgram().also {
                GLES30.glAttachShader(it, v); GLES30.glAttachShader(it, f); GLES30.glLinkProgram(it)
                val ok = IntArray(1); GLES30.glGetProgramiv(it, GLES30.GL_LINK_STATUS, ok, 0)
                check(ok[0] != 0) { GLES30.glGetProgramInfoLog(it) }
                GLES30.glDeleteShader(v); GLES30.glDeleteShader(f)
            }
        }

        companion object {
            private const val VERTEX = """#version 300 es
                in vec2 aPos; in vec2 aTex; out vec2 vTex;
                void main(){ gl_Position=vec4(aPos,0.0,1.0); vTex=aTex; }
            """
            private const val FRAGMENT = """#version 300 es
                precision highp float; precision highp usampler2D;
                uniform usampler2D uY; uniform usampler2D uUV; in vec2 vTex; out vec4 outColor;
                vec3 diglog(vec3 x){
                    x=max(x,vec3(0.0));
                    vec3 y=log(vec3(1.0)+18.0*x)/log(19.0);
                    return clamp(vec3(0.035)+0.91*y,0.0,0.965);
                }
                void main(){
                    // P010 stores valid 10 bits in the high bits of each 16-bit word.
                    float y=float(texture(uY,vTex).r >> 6u)/1023.0;
                    uvec2 uv10=texture(uUV,vTex).rg >> 6u;
                    float u=float(uv10.r)/1023.0-0.5;
                    float v=float(uv10.g)/1023.0-0.5;
                    vec3 rgb=vec3(y+1.5748*v, y-0.1873*u-0.4681*v, y+1.8556*u);
                    outColor=vec4(diglog(rgb),1.0);
                }
            """
        }
    }
}
