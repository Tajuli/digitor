package com.example.digitor

import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CaptureRequest
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.opengl.*
import android.os.Handler
import android.os.HandlerThread
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

/** Grafika-style, zero-copy Camera2/OES/MediaCodec recorder. */
class DigLogV4Engine(
    private val camera: CameraDevice, private val size: Size, private val fps: Int,
    private val bitrate: Int, private val output: File, private val previewSurface: Surface,
    private val background: Handler, private val configureRequest: (CaptureRequest.Builder) -> Unit,
    private val onReady: (String) -> Unit, private val onError: (String) -> Unit,
) : DigLogEngine {
    companion object { private const val TAG = "DigLogV4" }
    override val actualBitDepth = 8
    override val codecName get() = codecLabel
    private val glThread = HandlerThread("DigLogV4-GL").apply { start() }
    private val codecThread = HandlerThread("DigLogV4-Codec").apply { start() }
    private val gl = Handler(glThread.looper)
    private val codecHandler = Handler(codecThread.looper)
    private val started = AtomicBoolean(false); private val stopping = AtomicBoolean(false)
    private val released = AtomicBoolean(false); private val framePending = AtomicBoolean(false)
    @Volatile private var failed = false; @Volatile private var session: CameraCaptureSession? = null
    @Volatile private var codec: MediaCodec? = null; @Volatile private var muxer: MediaMuxer? = null
    @Volatile private var encoderSurface: Surface? = null; @Volatile private var renderer: Renderer? = null
    @Volatile private var muxerStarted = false; @Volatile private var muxerStopped = false
    @Volatile private var eosReceived = false; @Volatile private var samples = 0; @Volatile private var frames = 0
    private var track = -1; private var codecLabel = "HEVC"
    private val continuousDrain = object : Runnable { override fun run() {
        try { if (started.get() && !stopping.get()) { codec?.let { drain(it, MediaCodec.BufferInfo(), 0) }; codecHandler.postDelayed(this, 8) } }
        catch (t: Throwable) { fail("continuous encoder drain failed", t) }
    } }

    override fun start() { background.post { initialize() } }
    private fun initialize() {
        try {
            configureEncoder()
            val ready = CountDownLatch(1); var error: Throwable? = null
            gl.post {
                try { renderer = Renderer(requireNotNull(encoderSurface), previewSurface, size) } catch (t: Throwable) { error = t }
                ready.countDown()
            }
            check(ready.await(5, TimeUnit.SECONDS)) { "GL initialization timed out" }
            error?.let { throw it }
            val cameraTarget = requireNotNull(renderer).cameraSurface
            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply { addTarget(cameraTarget); configureRequest(this) }
            camera.createCaptureSession(listOf(cameraTarget), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(value: CameraCaptureSession) {
                    if (stopping.get()) { value.close(); return }
                    session = value
                    try {
                        val codecStarted = CountDownLatch(1); var codecStartError: Throwable? = null
                        codecHandler.post { try { codec?.start() } catch (t: Throwable) { codecStartError = t } finally { codecStarted.countDown() } }
                        check(codecStarted.await(2, TimeUnit.SECONDS)) { "encoder start timed out" }
                        codecStartError?.let { throw it }
                        started.set(true)
                        codecHandler.post(continuousDrain)
                        value.setRepeatingRequest(request.build(), null, background)
                        Log.d(TAG, "Camera2 session configured")
                        onReady(codecLabel)
                    } catch (t: Throwable) { fail("camera session start failed", t) }
                }
                override fun onConfigureFailed(value: CameraCaptureSession) { value.close(); fail("Camera2 session configuration failed", null) }
            }, background)
        } catch (t: Throwable) { fail("V4 initialization failed", t) }
    }

    private fun configureEncoder() {
        var last: Throwable? = null
        for ((mime, label) in listOf(MediaFormat.MIMETYPE_VIDEO_HEVC to "HEVC", MediaFormat.MIMETYPE_VIDEO_AVC to "H.264")) try {
            val format = MediaFormat.createVideoFormat(mime, size.width, size.height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate); setInteger(MediaFormat.KEY_FRAME_RATE, fps); setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                if (android.os.Build.VERSION.SDK_INT >= 24) { setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_FULL); setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709); setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO) }
            }
            codec = MediaCodec.createEncoderByType(mime).also { it.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE); encoderSurface = it.createInputSurface() }
            muxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4); codecLabel = label; return
        } catch (t: Throwable) { last = t; runCatching { encoderSurface?.release() }; runCatching { codec?.release() }; encoderSurface = null; codec = null }
        throw IllegalStateException("No supported surface encoder", last)
    }

    override fun stop(): Boolean {
        // Lifecycle callers may invoke this from main. Never wait there.
        if (Thread.currentThread() == android.os.Looper.getMainLooper().thread) { Thread({ stopBlocking() }, "DigLogV4-stop").start(); return false }
        return stopBlocking()
    }
    private fun stopBlocking(): Boolean {
        if (!stopping.compareAndSet(false, true)) return outputIsValid()
        val cameraDone = CountDownLatch(1)
        background.post { runCatching { session?.stopRepeating(); session?.abortCaptures(); session?.close() }; session = null; cameraDone.countDown() }
        cameraDone.await(2, TimeUnit.SECONDS)
        val done = CountDownLatch(1)
        codecHandler.post {
            try {
                if (started.get()) { codec?.signalEndOfInputStream(); Log.d(TAG, "EOS submitted"); drainUntilEos() }
            } catch (t: Throwable) { fail("encoder finalization failed", t) } finally { done.countDown() }
        }
        done.await(12, TimeUnit.SECONDS)
        release()
        return outputIsValid()
    }
    private fun drainUntilEos() {
        val info = MediaCodec.BufferInfo(); val encoder = codec ?: return
        val deadline = android.os.SystemClock.elapsedRealtime() + 10_000
        while (!eosReceived && android.os.SystemClock.elapsedRealtime() < deadline) drain(encoder, info, 10_000)
    }
    private fun drain(encoder: MediaCodec, info: MediaCodec.BufferInfo, timeoutUs: Long) {
        while (true) when (val index = encoder.dequeueOutputBuffer(info, timeoutUs)) {
            MediaCodec.INFO_TRY_AGAIN_LATER -> return
            MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> { check(!muxerStarted); track = requireNotNull(muxer).addTrack(encoder.outputFormat); Log.d(TAG, "encoder output format changed"); requireNotNull(muxer).start(); muxerStarted = true; Log.d(TAG, "muxer started") }
            else -> if (index >= 0) {
                val data = encoder.getOutputBuffer(index)
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                if (info.size > 0 && muxerStarted && data != null) { data.position(info.offset); data.limit(info.offset + info.size); requireNotNull(muxer).writeSampleData(track, data, info); if (++samples % 30 == 0) Log.d(TAG, "encoded sample count=$samples") }
                val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0; encoder.releaseOutputBuffer(index, false)
                if (eos) { eosReceived = true; Log.d(TAG, "EOS received"); return }
            }
        }
    }
    private fun fail(message: String, cause: Throwable?) { if (failed) return; failed = true; Log.e(TAG, message, cause); onError("$message${cause?.message?.let { ": $it" } ?: ""}"); Thread({ stopBlocking() }, "DigLogV4-fail-stop").start() }
    override fun outputIsValid() = muxerStarted && muxerStopped && samples > 0 && frames > 0 && !failed && output.length() > 1024
    private fun release() {
        if (!released.compareAndSet(false, true)) return
        codecHandler.removeCallbacks(continuousDrain)
        val eglDone = CountDownLatch(1); gl.post { runCatching { renderer?.release() }; renderer = null; eglDone.countDown() }; eglDone.await(3, TimeUnit.SECONDS)
        val codecDone = CountDownLatch(1)
        codecHandler.post {
            muxer?.let { if (muxerStarted && !muxerStopped && eosReceived) { runCatching { it.stop(); muxerStopped = true }; Log.d(TAG, "final output size=${output.length()}") }; runCatching { it.release() } }; muxer = null
            codec?.let { runCatching { it.stop() }; runCatching { it.release() } }; codec = null; encoderSurface?.release(); encoderSurface = null
            codecDone.countDown()
        }
        codecDone.await(3, TimeUnit.SECONDS)
        glThread.quitSafely(); codecThread.quitSafely(); previewSurface.release(); Log.d(TAG, "release completed")
    }

    private inner class Renderer(encoder: Surface, preview: Surface, recordingSize: Size) {
        private val egl = EglCore(); private val encoderWindow = WindowSurface(egl, encoder); private val previewWindow = WindowSurface(egl, preview)
        private val rect: FullFrameRect; private val texture: Int
        private val textureMatrix = FloatArray(16); private val st: SurfaceTexture
        val cameraSurface: Surface
        init {
            encoderWindow.makeCurrent()
            rect = FullFrameRect(Texture2dProgram()); texture = rect.createTextureObject()
            st = SurfaceTexture(texture).apply { setDefaultBufferSize(recordingSize.width, recordingSize.height) }
            cameraSurface = Surface(st)
            Log.d(TAG, "EGL context created"); Log.d(TAG, "preview EGLSurface created"); Log.d(TAG, "encoder EGLSurface created"); Log.d(TAG, "camera OES SurfaceTexture created")
            st.setOnFrameAvailableListener({
                if (started.get() && framePending.compareAndSet(false, true)) gl.post { try { render() } catch (t: Throwable) { fail("GL rendering failed", t) } finally { framePending.set(false) } }
            }, gl)
        }
        private fun render() {
            st.updateTexImage(); st.getTransformMatrix(textureMatrix); val timestamp = st.timestamp
            if (frames++ == 0) Log.d(TAG, "first camera frame received")
            encoderWindow.makeCurrent(); GLES30.glViewport(0, 0, size.width, size.height); rect.drawFrame(texture, textureMatrix); EGLExt.eglPresentationTimeANDROID(egl.display, encoderWindow.surface, timestamp); encoderWindow.swapBuffers()
            if (frames == 1) Log.d(TAG, "first encoder frame rendered")
            previewWindow.makeCurrent(); GLES30.glViewport(0, 0, previewWindow.width(), previewWindow.height()); rect.drawFrame(texture, textureMatrix); previewWindow.swapBuffers()
            if (frames == 1) Log.d(TAG, "first preview frame rendered")
        }
        fun release() { st.setOnFrameAvailableListener(null); cameraSurface.release(); st.release(); rect.release(); encoderWindow.release(); previewWindow.release(); egl.release() }
    }
}

private class EglCore {
    val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY); private val config: EGLConfig; val context: EGLContext
    init { check(display != EGL14.EGL_NO_DISPLAY); check(EGL14.eglInitialize(display, IntArray(1), 0, IntArray(1), 0)); val configs = arrayOfNulls<EGLConfig>(1); val n = IntArray(1); check(EGL14.eglChooseConfig(display, intArrayOf(EGL14.EGL_RED_SIZE,8,EGL14.EGL_GREEN_SIZE,8,EGL14.EGL_BLUE_SIZE,8,EGL14.EGL_ALPHA_SIZE,8,EGL14.EGL_RENDERABLE_TYPE,EGLExt.EGL_OPENGL_ES3_BIT_KHR,EGL14.EGL_SURFACE_TYPE,EGL14.EGL_WINDOW_BIT,0x3142,1,EGL14.EGL_NONE),0,configs,0,1,n,0) && n[0] > 0); config=configs[0]!!; context=EGL14.eglCreateContext(display,config,EGL14.EGL_NO_CONTEXT,intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION,3,EGL14.EGL_NONE),0); check(context != EGL14.EGL_NO_CONTEXT) }
    fun window(surface: Surface) = EGL14.eglCreateWindowSurface(display, config, surface, intArrayOf(EGL14.EGL_NONE), 0).also { check(it != EGL14.EGL_NO_SURFACE) }
    fun release() { EGL14.eglMakeCurrent(display,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_CONTEXT); EGL14.eglDestroyContext(display,context); EGL14.eglTerminate(display) }
}
private class WindowSurface(private val egl: EglCore, window: Surface) { val surface=egl.window(window); fun makeCurrent() { check(EGL14.eglMakeCurrent(egl.display,surface,surface,egl.context)) }; fun swapBuffers() { check(EGL14.eglSwapBuffers(egl.display,surface)) }; fun width()=query(EGL14.EGL_WIDTH); fun height()=query(EGL14.EGL_HEIGHT); private fun query(a:Int):Int { val v=IntArray(1); EGL14.eglQuerySurface(egl.display,surface,a,v,0); return v[0] }; fun release(){ EGL14.eglDestroySurface(egl.display,surface) } }
private class FullFrameRect(private val program: Texture2dProgram) { private val vertex: FloatBuffer=ByteBuffer.allocateDirect(64).order(ByteOrder.nativeOrder()).asFloatBuffer().apply{put(floatArrayOf(-1f,-1f,0f,0f,1f,-1f,1f,0f,-1f,1f,0f,1f,1f,1f,1f,1f));position(0)}; fun createTextureObject():Int { val a=IntArray(1); GLES30.glGenTextures(1,a,0); GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,a[0]); for (p in intArrayOf(GLES30.GL_TEXTURE_MIN_FILTER,GLES30.GL_TEXTURE_MAG_FILTER)) GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,p,GLES30.GL_LINEAR); GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,GLES30.GL_TEXTURE_WRAP_S,GLES30.GL_CLAMP_TO_EDGE); GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,GLES30.GL_TEXTURE_WRAP_T,GLES30.GL_CLAMP_TO_EDGE); return a[0] }; fun drawFrame(t:Int,m:FloatArray){ program.draw(t,m,vertex) }; fun release(){program.release()} }
private class Texture2dProgram { private val p=GlUtil.program("#version 300 es\nin vec2 aPosition; in vec2 aTexCoord; uniform mat4 uTextureMatrix; out vec2 vTexCoord; void main(){gl_Position=vec4(aPosition,0.,1.);vTexCoord=(uTextureMatrix*vec4(aTexCoord,0.,1.)).xy;}","#version 300 es\n#extension GL_OES_EGL_image_external_essl3 : require\nprecision highp float; uniform samplerExternalOES uCameraTexture; in vec2 vTexCoord; out vec4 fragColor; float digLog(float x){x=max(x,0.);const float gray=.18;const float toeAtGray=.28*(1.-exp(-gray/.18));float encoded=x<=gray?.28*(1.-exp(-x/.18)):toeAtGray+.28+.38*log(1.+2.4*(x-gray));return clamp(encoded,0.,1.);} void main(){vec3 rgb=clamp(texture(uCameraTexture,vTexCoord).rgb,0.,1.);float luma=dot(rgb,vec3(.2126,.7152,.0722));vec3 softened=vec3(luma)+(rgb-vec3(luma))*.82;fragColor=vec4(digLog(softened.r),digLog(softened.g),digLog(softened.b),1.);}"); private val pos=GLES30.glGetAttribLocation(p,"aPosition"); private val tex=GLES30.glGetAttribLocation(p,"aTexCoord"); private val matrix=GLES30.glGetUniformLocation(p,"uTextureMatrix"); fun draw(t:Int,m:FloatArray,v:FloatBuffer){GLES30.glUseProgram(p);v.position(0);GLES30.glVertexAttribPointer(pos,2,GLES30.GL_FLOAT,false,16,v);GLES30.glEnableVertexAttribArray(pos);v.position(2);GLES30.glVertexAttribPointer(tex,2,GLES30.GL_FLOAT,false,16,v);GLES30.glEnableVertexAttribArray(tex);GLES30.glActiveTexture(GLES30.GL_TEXTURE0);GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,t);GLES30.glUniform1i(GLES30.glGetUniformLocation(p,"uCameraTexture"),0);GLES30.glUniformMatrix4fv(matrix,1,false,m,0);GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP,0,4)}; fun release(){GLES30.glDeleteProgram(p)} }
private object GlUtil {
    fun program(vertexSource: String, fragmentSource: String): Int {
        fun compileShader(type: Int, source: String): Int {
            val shader = GLES30.glCreateShader(type)
            check(shader != 0) { "glCreateShader failed for type=$type" }

            GLES30.glShaderSource(shader, source)
            GLES30.glCompileShader(shader)

            val status = IntArray(1)
            GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
            if (status[0] == 0) {
                val log = GLES30.glGetShaderInfoLog(shader)
                GLES30.glDeleteShader(shader)
                error("Shader compilation failed: $log")
            }
            return shader
        }

        val vertexShader = compileShader(GLES30.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = compileShader(GLES30.GL_FRAGMENT_SHADER, fragmentSource)
        val program = GLES30.glCreateProgram()
        check(program != 0) { "glCreateProgram failed" }

        GLES30.glAttachShader(program, vertexShader)
        GLES30.glAttachShader(program, fragmentShader)
        GLES30.glLinkProgram(program)

        val status = IntArray(1)
        GLES30.glGetProgramiv(program, GLES30.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES30.glGetProgramInfoLog(program)
            GLES30.glDeleteProgram(program)
            GLES30.glDeleteShader(vertexShader)
            GLES30.glDeleteShader(fragmentShader)
            error("Program link failed: $log")
        }

        GLES30.glDeleteShader(vertexShader)
        GLES30.glDeleteShader(fragmentShader)
        return program
    }
}
