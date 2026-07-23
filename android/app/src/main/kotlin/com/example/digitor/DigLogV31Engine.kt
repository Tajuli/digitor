package com.example.digitor

import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.*
import android.opengl.*
import android.os.Build
import android.os.Handler
import android.util.Size
import android.view.Surface
import com.example.digitor.diglog.frame.P010FrameConverter
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * DigLog V3.1 candidate true-10-bit path.
 * P010 samples remain 10-bit in 16-bit containers, are sampled from integer GL textures,
 * transformed in highp float, rendered into an RGB10_A2 EGL encoder surface, and encoded
 * with HEVC Main10. Any initialization/runtime failure must fall back to DigLog V3 8-bit.
 */
class DigLogV31Engine(
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
) : DigLogEngine {
    override val actualBitDepth: Int = 10
    override val codecName: String get() = codecLabel

    private var reader: ImageReader? = null
    private var session: CameraCaptureSession? = null
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var inputSurface: Surface? = null
    private var renderer: P010Renderer? = null
    private var track = -1
    private var muxerStarted = false
    private var muxerStopped = false
    private var encodedSamples = 0
    private var firstTimestamp = -1L
    private var lastTimestamp = -1L
    private var codecLabel = "HEVC Main10"
    private val running = AtomicBoolean(false)
    private val failed = AtomicBoolean(false)

    override fun start() { background.post { startWorker() } }

    private fun startWorker() {
        try {
            require(Build.VERSION.SDK_INT >= 33) { "P010 ImageReader requires Android 13+" }
            configureMain10Encoder()
            renderer = P010Renderer(inputSurface!!, size.width, size.height)
            reader = ImageReader.newInstance(size.width, size.height, ImageFormat.YCBCR_P010, 3).also { r ->
                r.setOnImageAvailableListener({ source ->
                    val image = source.acquireLatestImage() ?: return@setOnImageAvailableListener
                    try {
                        if (!running.get()) return@setOnImageAvailableListener
                        val pts = if (firstTimestamp < 0L) {
                            firstTimestamp = image.timestamp
                            0L
                        } else (image.timestamp - firstTimestamp).coerceAtLeast(lastTimestamp + 1L)
                        lastTimestamp = pts
                        renderer!!.draw(P010FrameConverter.copy(image), pts)
                        drain(false)
                    } catch (t: Throwable) {
                        fail("10-bit frame path failed: ${t.message ?: t.javaClass.simpleName}")
                    } finally {
                        image.close()
                    }
                }, background)
            }
            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(reader!!.surface)
                previewSurface?.let(::addTarget)
                configureRequest(this)
            }
            val outputs = mutableListOf(reader!!.surface).apply { previewSurface?.let(::add) }
            camera.createCaptureSession(outputs, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(value: CameraCaptureSession) {
                    if (failed.get()) { value.close(); return }
                    try {
                        session = value
                        codec!!.start()
                        running.set(true)
                        value.setRepeatingRequest(request.build(), null, background)
                        onReady(codecLabel)
                    } catch (t: Throwable) { fail("10-bit session start failed: ${t.message}") }
                }
                override fun onConfigureFailed(value: CameraCaptureSession) {
                    value.close(); fail("Camera rejected the combined P010 + preview session")
                }
            }, background)
        } catch (t: Throwable) {
            release(); fail("DigLog V3.1 unavailable: ${t.message ?: t.javaClass.simpleName}")
        }
    }

    private fun configureMain10Encoder() {
        val infos = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.filter { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, true) } &&
                runCatching {
                    info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_HEVC).profileLevels.any {
                        it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 ||
                            it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10 ||
                            it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus
                    }
                }.getOrDefault(false)
        }
        var last: Throwable? = null
        for (info in infos) {
            try {
                val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_HEVC, size.width, size.height).apply {
                    setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                    setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10)
                    setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                    setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                    setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_FULL)
                    setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                    setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
                }
                codec = MediaCodec.createByCodecName(info.name).also {
                    it.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    inputSurface = it.createInputSurface()
                }
                muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                codecLabel = "HEVC Main10 (${info.name})"
                return
            } catch (t: Throwable) {
                last = t
                runCatching { inputSurface?.release() }; inputSurface = null
                runCatching { codec?.release() }; codec = null
            }
        }
        throw IllegalStateException("No usable HEVC Main10 surface encoder: ${last?.message ?: "not advertised"}")
    }

    override fun stop(): Boolean {
        if (Thread.currentThread() == background.looper.thread) return stopWorker()
        val latch = CountDownLatch(1); var result = false
        background.post { result = stopWorker(); latch.countDown() }
        return latch.await(8, TimeUnit.SECONDS) && result
    }

    private fun stopWorker(): Boolean {
        if (!running.getAndSet(false)) { release(); return false }
        return try {
            runCatching { session?.stopRepeating() }; runCatching { session?.abortCaptures() }
            codec?.signalEndOfInputStream()
            var polls = 0
            while (polls++ < 250 && drain(true)) Unit
            true
        } catch (_: Throwable) { false } finally { release() }
    }

    private fun drain(eos: Boolean): Boolean {
        val encoder = codec ?: return false
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, if (eos) 10_000 else 0)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> return eos
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    check(!muxerStarted)
                    val out = encoder.outputFormat
                    val profile = if (out.containsKey(MediaFormat.KEY_PROFILE)) out.getInteger(MediaFormat.KEY_PROFILE) else -1
                    check(profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 ||
                        profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10 ||
                        profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus) {
                        "Encoder output is not Main10 (profile=$profile)"
                    }
                    track = muxer!!.addTrack(out); muxer!!.start(); muxerStarted = true
                }
                index >= 0 -> {
                    val data = encoder.getOutputBuffer(index)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (data != null && info.size > 0 && muxerStarted) {
                        data.position(info.offset); data.limit(info.offset + info.size)
                        muxer!!.writeSampleData(track, data, info); encodedSamples++
                    }
                    val done = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    encoder.releaseOutputBuffer(index, false)
                    if (done) return false
                }
            }
        }
    }

    override fun outputIsValid(): Boolean = muxerStarted && muxerStopped && encodedSamples > 0 &&
        lastTimestamp > 0 && output.isFile && output.length() > 1024

    private fun fail(message: String) {
        if (!failed.compareAndSet(false, true)) return
        running.set(false); release(); onError(message)
    }

    private fun release() {
        running.set(false)
        runCatching { session?.close() }; session = null
        runCatching { reader?.close() }; reader = null
        runCatching { renderer?.release() }; renderer = null
        runCatching { codec?.stop() }; runCatching { codec?.release() }; codec = null
        if (muxerStarted) muxerStopped = runCatching { muxer?.stop() }.isSuccess
        runCatching { muxer?.release() }; muxer = null
        runCatching { inputSurface?.release() }; inputSurface = null
    }

    private class P010Renderer(surface: Surface, private val width: Int, private val height: Int) {
        private val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        private val context: EGLContext
        private val window: EGLSurface
        private val program: Int
        private val textures = IntArray(2)
        private val vertices: FloatBuffer = ByteBuffer.allocateDirect(64).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
            put(floatArrayOf(-1f,-1f,0f,1f, 1f,-1f,1f,1f, -1f,1f,0f,0f, 1f,1f,1f,0f)); flip()
        }
        init {
            check(display != EGL14.EGL_NO_DISPLAY)
            val versions = IntArray(2); check(EGL14.eglInitialize(display, versions,0,versions,1))
            val configs = arrayOfNulls<EGLConfig>(1); val count = IntArray(1)
            val attrs = intArrayOf(
                EGL14.EGL_RED_SIZE,10, EGL14.EGL_GREEN_SIZE,10, EGL14.EGL_BLUE_SIZE,10, EGL14.EGL_ALPHA_SIZE,2,
                EGL14.EGL_RENDERABLE_TYPE, EGLExt.EGL_OPENGL_ES3_BIT_KHR,
                EGL14.EGL_SURFACE_TYPE,EGL14.EGL_WINDOW_BIT, EGL14.EGL_NONE)
            check(EGL14.eglChooseConfig(display,attrs,0,configs,0,1,count,0) && count[0] > 0) { "No RGB10_A2 EGL config" }
            val cfg = configs[0]!!
            context = EGL14.eglCreateContext(display,cfg,EGL14.EGL_NO_CONTEXT,intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION,3,EGL14.EGL_NONE),0)
            check(context != EGL14.EGL_NO_CONTEXT) { "Could not create GLES3 context" }
            window = EGL14.eglCreateWindowSurface(display,cfg,surface,intArrayOf(EGL14.EGL_NONE),0)
            check(window != EGL14.EGL_NO_SURFACE) { "Could not create 10-bit encoder EGL surface: 0x${Integer.toHexString(EGL14.eglGetError())}" }
            check(EGL14.eglMakeCurrent(display,window,window,context))
            val ext = GLES30.glGetString(GLES30.GL_EXTENSIONS).orEmpty()
            check(ext.contains("GL_EXT_texture_norm16") || Build.VERSION.SDK_INT >= 24) { "16-bit texture path unavailable" }
            program = makeProgram(VERTEX, FRAGMENT)
            GLES30.glGenTextures(2,textures,0)
            textures.forEach { GLES30.glBindTexture(GLES30.GL_TEXTURE_2D,it); GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D,GLES30.GL_TEXTURE_MIN_FILTER,GLES30.GL_NEAREST); GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D,GLES30.GL_TEXTURE_MAG_FILTER,GLES30.GL_NEAREST) }
        }
        fun draw(frame: P010FrameConverter.Frame, pts: Long) {
            check(EGL14.eglMakeCurrent(display,window,window,context))
            GLES30.glViewport(0,0,width,height); GLES30.glUseProgram(program)
            frame.y.position(0); GLES30.glActiveTexture(GLES30.GL_TEXTURE0); GLES30.glBindTexture(GLES30.GL_TEXTURE_2D,textures[0])
            GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT,2)
            GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D,0,GLES30.GL_R16UI,frame.width,frame.height,0,GLES30.GL_RED_INTEGER,GLES30.GL_UNSIGNED_SHORT,frame.y)
            frame.uv.position(0); GLES30.glActiveTexture(GLES30.GL_TEXTURE1); GLES30.glBindTexture(GLES30.GL_TEXTURE_2D,textures[1])
            GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D,0,GLES30.GL_RG16UI,frame.width/2,frame.height/2,0,GLES30.GL_RG_INTEGER,GLES30.GL_UNSIGNED_SHORT,frame.uv)
            GLES30.glUniform1i(GLES30.glGetUniformLocation(program,"uY"),0); GLES30.glUniform1i(GLES30.glGetUniformLocation(program,"uUV"),1)
            val pos=GLES30.glGetAttribLocation(program,"aPos"); val tex=GLES30.glGetAttribLocation(program,"aTex")
            vertices.position(0); GLES30.glVertexAttribPointer(pos,2,GLES30.GL_FLOAT,false,16,vertices); GLES30.glEnableVertexAttribArray(pos)
            vertices.position(2); GLES30.glVertexAttribPointer(tex,2,GLES30.GL_FLOAT,false,16,vertices); GLES30.glEnableVertexAttribArray(tex)
            GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP,0,4)
            EGLExt.eglPresentationTimeANDROID(display,window,pts)
            check(EGL14.eglSwapBuffers(display,window)) { "10-bit encoder swap failed" }
        }
        fun release() {
            runCatching { EGL14.eglMakeCurrent(display,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_CONTEXT) }
            runCatching { EGL14.eglDestroySurface(display,window) }; runCatching { EGL14.eglDestroyContext(display,context) }; runCatching { EGL14.eglTerminate(display) }
        }
        private fun makeProgram(v:String,f:String):Int {
            fun shader(type:Int,src:String):Int { val s=GLES30.glCreateShader(type); GLES30.glShaderSource(s,src); GLES30.glCompileShader(s); val ok=IntArray(1); GLES30.glGetShaderiv(s,GLES30.GL_COMPILE_STATUS,ok,0); check(ok[0]!=0){GLES30.glGetShaderInfoLog(s)}; return s }
            val vs=shader(GLES30.GL_VERTEX_SHADER,v); val fs=shader(GLES30.GL_FRAGMENT_SHADER,f); val p=GLES30.glCreateProgram(); GLES30.glAttachShader(p,vs); GLES30.glAttachShader(p,fs); GLES30.glLinkProgram(p); val ok=IntArray(1); GLES30.glGetProgramiv(p,GLES30.GL_LINK_STATUS,ok,0); check(ok[0]!=0){GLES30.glGetProgramInfoLog(p)}; GLES30.glDeleteShader(vs); GLES30.glDeleteShader(fs); return p
        }
        companion object {
            const val VERTEX = """#version 300 es
in vec2 aPos; in vec2 aTex; out vec2 vTex; void main(){gl_Position=vec4(aPos,0.0,1.0);vTex=aTex;}"""
            const val FRAGMENT = """#version 300 es
precision highp float; precision highp usampler2D;
uniform usampler2D uY; uniform usampler2D uUV; in vec2 vTex; out vec4 outColor;
float diglog(float x){x=max(x,0.0); const float cut=0.018; const float toeSlope=4.0; const float a=0.22; const float b=0.78; float toe=x*toeSlope; float body=a+b*log2(1.0+7.5*x)/log2(8.5); return clamp(mix(toe,body,smoothstep(0.0,cut*2.0,x)),0.0,1.0);}
void main(){float y=float(texture(uY,vTex).r)/1023.0; uvec2 uv10=texture(uUV,vTex).rg; float u=float(uv10.r)/1023.0-0.5; float v=float(uv10.g)/1023.0-0.5; vec3 rgb=vec3(y+1.5748*v,y-0.1873*u-0.4681*v,y+1.8556*u); rgb=max(rgb,vec3(0.0)); outColor=vec4(diglog(rgb.r),diglog(rgb.g),diglog(rgb.b),1.0);}"""
        }
    }
}
