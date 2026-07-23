package com.example.digitor

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Color
import android.hardware.camera2.*
import android.hardware.camera2.params.TonemapCurve
import android.media.MediaCodecList
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Range
import android.util.Size
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.widget.*
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/**
 * Minimal, strict DigLog recorder.
 * Uses Camera2's programmable TONEMAP_MODE_CONTRAST_CURVE before encoding,
 * rather than applying a flat filter after recording.
 */
class DigLogCaptureActivity : Activity() {
    companion object {
        const val EXTRA_CAMERA_ID = "cameraId"
        const val EXTRA_BIT_DEPTH = "bitDepth"
        const val EXTRA_OUTPUT_PATH = "outputPath"
        private const val REQUEST_PERMISSIONS = 6001
    }

    private lateinit var preview: TextureView
    private lateinit var status: TextView
    private lateinit var record: Button
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var recorder: MediaRecorder? = null
    private var digLog10: DigLog10Engine? = null
    private var usingTenBit = false
    private var backgroundThread: HandlerThread? = null
    private var background: Handler? = null
    private var recording = false
    private var outputFile: File? = null
    private lateinit var cameraId: String
    private var internalBitDepth = 8
    private var videoSize = Size(1920, 1080)
    private var previewSize = Size(1920, 1080)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cameraId = intent.getStringExtra(EXTRA_CAMERA_ID) ?: run { finishCanceled("Camera unavailable"); return }
        internalBitDepth = intent.getIntExtra(EXTRA_BIT_DEPTH, 8)
        buildUi()
        if (hasPermissions()) startWhenReady() else ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO), REQUEST_PERMISSIONS
        )
    }

    private fun buildUi() {
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        preview = TextureView(this)
        root.addView(preview, FrameLayout.LayoutParams(-1, -1))

        status = TextView(this).apply {
            text = "DigLog"
            setTextColor(Color.WHITE)
            textSize = 17f
            setPadding(28, 18, 28, 18)
            setBackgroundColor(0x66000000)
        }
        root.addView(status, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = 42 })

        record = Button(this).apply {
            text = "RECORD"
            isEnabled = false
            setOnClickListener { if (recording) stopRecording() else startRecording() }
        }
        root.addView(record, FrameLayout.LayoutParams(240, 120, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = 64 })
        setContentView(root)
    }

    private fun hasPermissions() = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED &&
        ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_PERMISSIONS && hasPermissions()) startWhenReady() else finishCanceled("Camera and microphone permissions are required")
    }

    private fun startWhenReady() {
        startBackground()
        preview.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: android.graphics.SurfaceTexture, width: Int, height: Int) { openCamera() }
            override fun onSurfaceTextureSizeChanged(surface: android.graphics.SurfaceTexture, width: Int, height: Int) = Unit
            override fun onSurfaceTextureDestroyed(surface: android.graphics.SurfaceTexture) = true
            override fun onSurfaceTextureUpdated(surface: android.graphics.SurfaceTexture) = Unit
        }
        if (preview.isAvailable) openCamera()
    }

    private fun chooseSizes() {
        val manager = getSystemService(CAMERA_SERVICE) as CameraManager
        val c = manager.getCameraCharacteristics(cameraId)
        val map = c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return
        val candidates = map.getOutputSizes(MediaRecorder::class.java).orEmpty()
            .filter { it.width * 9 == it.height * 16 && it.width <= 3840 && it.height <= 2160 }
            .sortedByDescending { it.width * it.height }
        videoSize = candidates.firstOrNull() ?: Size(1920, 1080)
        previewSize = map.getOutputSizes(android.graphics.SurfaceTexture::class.java).orEmpty()
            .filter { it.width * videoSize.height == it.height * videoSize.width }
            .minByOrNull { kotlin.math.abs(it.width - videoSize.width) } ?: videoSize
    }

    private fun openCamera() {
        chooseSizes()
        val manager = getSystemService(CAMERA_SERVICE) as CameraManager
        if (!hasPermissions()) return
        try {
            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) { camera = device; createPreviewSession() }
                override fun onDisconnected(device: CameraDevice) { device.close(); finishCanceled("Camera disconnected") }
                override fun onError(device: CameraDevice, error: Int) { device.close(); finishCanceled("Camera error: $error") }
            }, background)
        } catch (e: Exception) { finishCanceled(e.message ?: "Could not open camera") }
    }

    private fun createPreviewSession() {
        val device = camera ?: return
        val texture = preview.surfaceTexture ?: return
        texture.setDefaultBufferSize(previewSize.width, previewSize.height)
        val surface = Surface(texture)
        val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
            addTarget(surface)
            applyDigLogControls(this)
        }
        device.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(s: CameraCaptureSession) {
                session = s
                s.setRepeatingRequest(builder.build(), null, background)
                runOnUiThread { record.isEnabled = true; status.text = "DigLog Ready" }
            }
            override fun onConfigureFailed(s: CameraCaptureSession) { finishCanceled("Preview configuration failed") }
        }, background)
    }

    private fun startRecording() {
        if (internalBitDepth == 10 && android.os.Build.VERSION.SDK_INT >= 33) {
            startTenBitRecording()
        } else {
            startEightBitRecording()
        }
    }

    private fun startTenBitRecording() {
        val device = camera ?: return
        closeSession()
        outputFile = createOutputFile()
        usingTenBit = true
        record.isEnabled = false
        status.text = "DigLog preparing"
        val engine = DigLog10Engine(
            camera = device,
            cameraId = cameraId,
            size = videoSize,
            fps = 30,
            bitrate = calculateTenBitBitrate(),
            output = outputFile!!,
            previewSurface = preview.surfaceTexture?.let { texture ->
                texture.setDefaultBufferSize(previewSize.width, previewSize.height)
                Surface(texture)
            },
            background = background ?: return,
            onReady = {
                recording = true
                runOnUiThread { record.isEnabled = true; record.text = "STOP"; status.text = "DigLog • REC" }
            },
            onError = { message ->
                // Some OEMs advertise P010/Main10 but reject the combined stream at runtime.
                // Remove the incomplete file and transparently use verified DigLog 8.
                digLog10?.stop(); digLog10 = null
                outputFile?.delete()
                usingTenBit = false
                internalBitDepth = 8
                runOnUiThread {
                    Toast.makeText(this, "$message. Using compatible DigLog engine.", Toast.LENGTH_LONG).show()
                    startEightBitRecording()
                }
            }
        )
        digLog10 = engine
        engine.start()
    }

    private fun startEightBitRecording() {
        val device = camera ?: return
        try {
            closeSession()
            outputFile = createOutputFile()
            recorder = createRecorder(outputFile!!)
            val texture = preview.surfaceTexture ?: return
            texture.setDefaultBufferSize(previewSize.width, previewSize.height)
            val previewSurface = Surface(texture)
            val recorderSurface = recorder!!.surface
            val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(previewSurface)
                addTarget(recorderSurface)
                applyDigLogControls(this)
            }
            device.createCaptureSession(listOf(previewSurface, recorderSurface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    session = s
                    s.setRepeatingRequest(builder.build(), null, background)
                    recorder!!.start()
                    recording = true
                    runOnUiThread { record.isEnabled = true; record.text = "STOP"; status.text = "DigLog • REC" }
                }
                override fun onConfigureFailed(s: CameraCaptureSession) { finishCanceled("Recording configuration failed") }
            }, background)
        } catch (e: Exception) { finishCanceled(e.message ?: "Recording could not start") }
    }

    private fun stopRecording() {
        if (!recording) return
        recording = false
        val success = if (usingTenBit) {
            val ok = digLog10?.stop() == true
            digLog10 = null
            ok
        } else {
            runCatching { session?.stopRepeating() }
            val ok = runCatching { recorder?.stop(); true }.getOrElse { false }
            recorder?.reset(); recorder?.release(); recorder = null
            ok
        }
        val file = outputFile
        if (!success || file == null || !file.exists() || file.length() == 0L) {
            file?.delete(); finishCanceled("Recording failed"); return
        }
        writeMetadata(file)
        setResult(RESULT_OK, intent.apply { putExtra(EXTRA_OUTPUT_PATH, file.absolutePath) })
        finish()
    }

    private fun applyDigLogControls(builder: CaptureRequest.Builder) {
        val manager = getSystemService(CAMERA_SERVICE) as CameraManager
        val characteristics = runCatching { manager.getCameraCharacteristics(cameraId) }.getOrNull()
        val requestKeys = characteristics?.availableCaptureRequestKeys?.toSet().orEmpty()

        fun <T> setIfSupported(key: CaptureRequest.Key<T>, value: T) {
            if (requestKeys.contains(key)) runCatching { builder.set(key, value) }
        }

        setIfSupported(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
        setIfSupported(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
        setIfSupported(CaptureRequest.CONTROL_AE_LOCK, true)
        setIfSupported(CaptureRequest.CONTROL_AWB_MODE, CameraMetadata.CONTROL_AWB_MODE_AUTO)
        setIfSupported(CaptureRequest.CONTROL_AWB_LOCK, true)
        setIfSupported(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO)

        val noiseModes = characteristics?.get(CameraCharacteristics.NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES)?.toSet().orEmpty()
        when {
            noiseModes.contains(CameraMetadata.NOISE_REDUCTION_MODE_MINIMAL) ->
                setIfSupported(CaptureRequest.NOISE_REDUCTION_MODE, CameraMetadata.NOISE_REDUCTION_MODE_MINIMAL)
            noiseModes.contains(CameraMetadata.NOISE_REDUCTION_MODE_FAST) ->
                setIfSupported(CaptureRequest.NOISE_REDUCTION_MODE, CameraMetadata.NOISE_REDUCTION_MODE_FAST)
        }

        val edgeModes = characteristics?.get(CameraCharacteristics.EDGE_AVAILABLE_EDGE_MODES)?.toSet().orEmpty()
        when {
            edgeModes.contains(CameraMetadata.EDGE_MODE_OFF) ->
                setIfSupported(CaptureRequest.EDGE_MODE, CameraMetadata.EDGE_MODE_OFF)
            edgeModes.contains(CameraMetadata.EDGE_MODE_FAST) ->
                setIfSupported(CaptureRequest.EDGE_MODE, CameraMetadata.EDGE_MODE_FAST)
        }

        val aberrationModes = characteristics?.get(CameraCharacteristics.COLOR_CORRECTION_AVAILABLE_ABERRATION_MODES)?.toSet().orEmpty()
        if (aberrationModes.contains(CameraMetadata.COLOR_CORRECTION_ABERRATION_MODE_OFF)) {
            setIfSupported(CaptureRequest.COLOR_CORRECTION_ABERRATION_MODE, CameraMetadata.COLOR_CORRECTION_ABERRATION_MODE_OFF)
        }

        val toneModes = characteristics?.get(CameraCharacteristics.TONEMAP_AVAILABLE_TONE_MAP_MODES)?.toSet().orEmpty()
        if (toneModes.contains(CameraMetadata.TONEMAP_MODE_CONTRAST_CURVE) &&
            requestKeys.contains(CaptureRequest.TONEMAP_CURVE)) {
            setIfSupported(CaptureRequest.TONEMAP_MODE, CameraMetadata.TONEMAP_MODE_CONTRAST_CURVE)
            setIfSupported(CaptureRequest.TONEMAP_CURVE, buildDigLogCurve())
        } else if (toneModes.contains(CameraMetadata.TONEMAP_MODE_FAST)) {
            setIfSupported(CaptureRequest.TONEMAP_MODE, CameraMetadata.TONEMAP_MODE_FAST)
        }

        setIfSupported(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF)
        val fpsRanges = characteristics?.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES).orEmpty()
        val fps = fpsRanges.firstOrNull { it.lower <= 30 && it.upper >= 30 }
            ?: fpsRanges.maxByOrNull { it.upper }
        if (fps != null) setIfSupported(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fps)
    }

    /** Mobile-optimized logarithmic curve with a protected toe and soft highlight shoulder. */
    private fun buildDigLogCurve(): TonemapCurve {
        val points = 64
        val curve = FloatArray(points * 2)
        val a = 18.0
        val norm = ln(1.0 + a)
        for (i in 0 until points) {
            val x = i.toDouble() / (points - 1)
            var y = ln(1.0 + a * x) / norm
            // Keep black noise from being lifted excessively; reserve code values for highlights.
            y = 0.035 + y * 0.91
            y = min(0.965, max(0.0, y))
            curve[i * 2] = x.toFloat()
            curve[i * 2 + 1] = y.toFloat()
        }
        return TonemapCurve(curve, curve, curve)
    }

    private fun createRecorder(file: File): MediaRecorder {
        @Suppress("DEPRECATION")
        val r = if (android.os.Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else MediaRecorder()
        r.setAudioSource(MediaRecorder.AudioSource.MIC)
        r.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        r.setOutputFile(file.absolutePath)
        r.setVideoEncodingBitRate(calculateBitrate())
        r.setVideoFrameRate(30)
        r.setVideoSize(videoSize.width, videoSize.height)
        r.setVideoEncoder(
            if (hasEncoder("video/hevc")) MediaRecorder.VideoEncoder.HEVC
            else MediaRecorder.VideoEncoder.H264
        )
        r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        r.setAudioEncodingBitRate(192_000)
        r.setAudioSamplingRate(48_000)
        r.prepare()
        return r
    }


    private fun hasEncoder(mime: String): Boolean =
        MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.any { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
        }

    private fun calculateTenBitBitrate(): Int {
        val pixels = videoSize.width.toLong() * videoSize.height
        return when {
            pixels >= 3840L * 2160L -> 200_000_000
            pixels >= 2560L * 1440L -> 120_000_000
            else -> 80_000_000
        }
    }

    private fun calculateBitrate(): Int {
        val pixels = videoSize.width.toLong() * videoSize.height
        return when {
            pixels >= 3840L * 2160L -> 120_000_000
            pixels >= 2560L * 1440L -> 70_000_000
            else -> if (videoSize.width >= 1920) 24_000_000 else 12_000_000
        }
    }

    private fun createOutputFile(): File {
        val dir = File(getExternalFilesDir(null) ?: filesDir, "DigLog").apply { mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        return File(dir, "DIGLOG_$stamp.mp4")
    }

    private fun writeMetadata(file: File) {
        val json = JSONObject().apply {
            put("profile", "DigLog")
            put("engineBitDepth", internalBitDepth)
            put("gamma", "DigLog Gamma v1")
            put("capture", if (usingTenBit) "Camera2 P010 → OpenGL ES 16-bit DigLog transform → HEVC Main10" else "Camera2 programmable pre-encode tone curve")
            put("codec", if (usingTenBit) "HEVC Main10" else "HEVC Main")
            put("bitrate", if (usingTenBit) calculateTenBitBitrate() else calculateBitrate())
            put("width", videoSize.width)
            put("height", videoSize.height)
            put("fps", 30)
            put("cameraId", cameraId)
            put("noiseReduction", "MINIMAL")
            put("edgeEnhancement", "OFF")
            put("stabilization", "OFF")
            put("createdAt", System.currentTimeMillis())
        }
        File(file.parentFile, file.nameWithoutExtension + ".diglog.json").writeText(json.toString(2))
    }

    private fun closeSession() { session?.close(); session = null }
    private fun finishCanceled(message: String) {
        setResult(RESULT_CANCELED, intent.apply { putExtra("error", message) })
        runOnUiThread { Toast.makeText(this, message, Toast.LENGTH_LONG).show(); finish() }
    }

    override fun onPause() {
        if (recording) stopRecording() else { closeSession(); camera?.close(); camera = null }
        super.onPause()
    }

    override fun onDestroy() {
        digLog10?.stop(); digLog10 = null; closeSession(); camera?.close(); recorder?.release(); stopBackground(); super.onDestroy()
    }

    private fun startBackground() { backgroundThread = HandlerThread("DigLogCamera").also { it.start() }; background = Handler(backgroundThread!!.looper) }
    private fun stopBackground() { backgroundThread?.quitSafely(); runCatching { backgroundThread?.join() }; backgroundThread = null; background = null }
}
