package com.example.digitor

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
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
import android.view.View
import android.view.WindowInsets
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
        private const val REQUEST_OUTPUT_FOLDER = 6002
        private const val PREFS = "diglog_capture"
        private const val PREF_OUTPUT_TREE = "output_tree_uri"
    }

    private lateinit var preview: TextureView
    private lateinit var status: TextView
    private lateinit var record: Button
    private lateinit var locationButton: Button
    private lateinit var locationLabel: TextView
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var recorder: MediaRecorder? = null
    private var digLog10: DigLog10Engine? = null
    private var digLog8Gpu: DigLog8GpuEngine? = null
    private var usingTenBit = false
    private var backgroundThread: HandlerThread? = null
    private var background: Handler? = null
    private var recording = false
    private var outputFile: File? = null
    private lateinit var cameraId: String
    private var internalBitDepth = 8
    private var videoSize = Size(1920, 1080)
    private var previewSize = Size(1920, 1080)
    private var activeCodec = "H.264"
    private var activeBitrate = 12_000_000
    private var activeAudio = true
    private var selectedOutputTree: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cameraId = intent.getStringExtra(EXTRA_CAMERA_ID) ?: run { finishCanceled("Camera unavailable"); return }
        internalBitDepth = intent.getIntExtra(EXTRA_BIT_DEPTH, 8)
        selectedOutputTree = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(PREF_OUTPUT_TREE, null)?.let(Uri::parse)
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

        val bottomPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(24, 16, 24, 24)
            setBackgroundColor(0x55000000)
        }

        locationLabel = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 13f
            gravity = Gravity.CENTER
            text = outputLocationText()
        }
        bottomPanel.addView(locationLabel, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = 10 })

        locationButton = Button(this).apply {
            text = "SELECT SAVE LOCATION"
            setOnClickListener { chooseOutputFolder() }
        }
        bottomPanel.addView(locationButton, LinearLayout.LayoutParams(-1, 88).apply { bottomMargin = 10 })

        record = Button(this).apply {
            text = "RECORD"
            isEnabled = false
            setOnClickListener { if (recording) stopRecording() else startRecording() }
        }
        bottomPanel.addView(record, LinearLayout.LayoutParams(240, 96))

        val bottomParams = FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM)
        root.addView(bottomPanel, bottomParams)

        // Keep all controls above gesture/navigation bars on edge-to-edge devices.
        root.setOnApplyWindowInsetsListener { _, insets ->
            val navBottom = if (android.os.Build.VERSION.SDK_INT >= 30) {
                insets.getInsets(WindowInsets.Type.navigationBars()).bottom
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetBottom
            }
            bottomPanel.setPadding(24, 16, 24, 24 + navBottom)
            insets
        }
        root.systemUiVisibility = root.systemUiVisibility or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        setContentView(root)
        root.requestApplyInsets()
    }


    private fun outputLocationText(): String {
        val uri = selectedOutputTree ?: return "Save location: App storage / DigLog"
        val name = uri.lastPathSegment?.substringAfterLast(':')?.ifBlank { null }
        return "Save location: ${name ?: "Selected folder"}"
    }

    private fun chooseOutputFolder() {
        if (recording) {
            Toast.makeText(this, "Stop recording before changing the save location.", Toast.LENGTH_SHORT).show()
            return
        }
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            selectedOutputTree?.let { putExtra("android.provider.extra.INITIAL_URI", it) }
        }
        startActivityForResult(picker, REQUEST_OUTPUT_FOLDER)
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_OUTPUT_FOLDER || resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        runCatching { contentResolver.takePersistableUriPermission(uri, flags) }
        selectedOutputTree = uri
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(PREF_OUTPUT_TREE, uri.toString()).apply()
        locationLabel.text = outputLocationText()
        Toast.makeText(this, "DigLog save location updated.", Toast.LENGTH_SHORT).show()
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
        val maxWidth = if (internalBitDepth >= 10) 3840 else 1920
        val maxHeight = if (internalBitDepth >= 10) 2160 else 1080
        val candidates = map.getOutputSizes(MediaRecorder::class.java).orEmpty()
            .filter { it.width * 9 == it.height * 16 && it.width <= maxWidth && it.height <= maxHeight }
            .sortedByDescending { it.width * it.height }
        videoSize = candidates.firstOrNull()
            ?: map.getOutputSizes(MediaRecorder::class.java).orEmpty()
                .filter { it.width <= maxWidth && it.height <= maxHeight }
                .maxByOrNull { it.width * it.height }
            ?: Size(1280, 720)
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
                runOnUiThread { record.isEnabled = true; status.text = if (internalBitDepth >= 10) "DigLog10 Ready" else "DigLog8 Flat Ready" }
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
            usingTenBit = false
            record.isEnabled = false
            status.text = "DigLog GPU preparing"

            val texture = preview.surfaceTexture ?: throw IllegalStateException("Preview surface unavailable")
            texture.setDefaultBufferSize(previewSize.width, previewSize.height)
            val previewSurface = Surface(texture)
            val engine = DigLog8GpuEngine(
                camera = device,
                size = videoSize,
                fps = 30,
                bitrate = if (videoSize.width >= 1920) 20_000_000 else 10_000_000,
                output = outputFile!!,
                previewSurface = previewSurface,
                background = background ?: throw IllegalStateException("Camera thread unavailable"),
                configureRequest = { builder -> applyDigLogControls(builder, applyToneCurve = false) },
                onReady = { codec ->
                    activeCodec = codec
                    activeAudio = false
                    activeBitrate = if (videoSize.width >= 1920) 20_000_000 else 10_000_000
                    recording = true
                    runOnUiThread {
                        record.isEnabled = true
                        record.text = "STOP"
                        status.text = "DigLog GPU • REC"
                    }
                },
                onError = { message ->
                    outputFile?.delete()
                    runOnUiThread { finishCanceled(message) }
                },
            )
            digLog8Gpu = engine
            engine.start()
        } catch (e: Exception) {
            finishCanceled(e.message ?: "Recording could not start")
        }
    }

    private fun stopRecording() {
        if (!recording) return
        recording = false
        val success = if (usingTenBit) {
            val ok = digLog10?.stop() == true
            digLog10 = null
            ok
        } else {
            val ok = digLog8Gpu?.stop() == true
            digLog8Gpu = null
            ok
        }
        val file = outputFile
        if (!success || file == null || !file.exists() || file.length() == 0L) {
            file?.delete(); finishCanceled("Recording failed"); return
        }
        val metadataFile = writeMetadata(file)
        val savedPath = runCatching { publishToSelectedFolder(file, metadataFile) }
            .getOrElse {
                Toast.makeText(this, "Selected folder could not be used. Saved in app storage.", Toast.LENGTH_LONG).show()
                file.absolutePath
            }
        setResult(RESULT_OK, intent.apply { putExtra(EXTRA_OUTPUT_PATH, savedPath) })
        finish()
    }

    private fun applyDigLogControls(builder: CaptureRequest.Builder, applyToneCurve: Boolean = true) {
        val manager = getSystemService(CAMERA_SERVICE) as CameraManager
        val characteristics = runCatching { manager.getCameraCharacteristics(cameraId) }.getOrNull()
        val requestKeys = characteristics?.availableCaptureRequestKeys?.toSet().orEmpty()

        fun <T> setIfSupported(key: CaptureRequest.Key<T>, value: T) {
            if (requestKeys.contains(key)) runCatching { builder.set(key, value) }
        }

        setIfSupported(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
        setIfSupported(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
        // Do not lock AE/AWB before they converge; that caused very dark clips on low-end phones.
        setIfSupported(CaptureRequest.CONTROL_AE_LOCK, false)
        setIfSupported(CaptureRequest.CONTROL_AWB_MODE, CameraMetadata.CONTROL_AWB_MODE_AUTO)
        setIfSupported(CaptureRequest.CONTROL_AWB_LOCK, false)
        setIfSupported(CaptureRequest.CONTROL_EFFECT_MODE, CameraMetadata.CONTROL_EFFECT_MODE_OFF)

        val compensationRange = characteristics?.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
        if (compensationRange != null && compensationRange.contains(1)) {
            setIfSupported(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, 1)
        }
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
        if (applyToneCurve && toneModes.contains(CameraMetadata.TONEMAP_MODE_CONTRAST_CURVE) &&
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

    /**
     * DigLog8 capture curve for devices without a true 10-bit pipeline.
     * The curve deliberately lifts the toe and compresses upper mids/highlights,
     * producing a visibly flatter file that leaves room for grading.
     */
    private fun buildDigLogCurve(): TonemapCurve {
        val anchors = arrayOf(
            0.000f to 0.000f,
            0.010f to 0.045f,
            0.025f to 0.085f,
            0.050f to 0.135f,
            0.100f to 0.215f,
            0.180f to 0.305f,
            0.300f to 0.420f,
            0.450f to 0.535f,
            0.600f to 0.635f,
            0.750f to 0.735f,
            0.880f to 0.830f,
            0.960f to 0.915f,
            1.000f to 1.000f,
        )
        val curve = FloatArray(anchors.size * 2)
        anchors.forEachIndexed { index, point ->
            curve[index * 2] = point.first
            curve[index * 2 + 1] = point.second
        }
        return TonemapCurve(curve, curve, curve)
    }

    private data class RecorderAttempt(
        val encoder: Int,
        val codecName: String,
        val size: Size,
        val bitrate: Int,
        val withAudio: Boolean,
    )

    private fun createRecorder(file: File): MediaRecorder {
        val sizes = linkedSetOf(videoSize, Size(1920, 1080), Size(1280, 720))
            .filter { it.width <= videoSize.width && it.height <= videoSize.height }
            .ifEmpty { listOf(Size(1280, 720)) }
        val attempts = mutableListOf<RecorderAttempt>()
        for (size in sizes) {
            val bitrate = when {
                size.width >= 1920 -> 20_000_000
                else -> 10_000_000
            }
            // HEVC is attempted first only when advertised, but many low-end OEMs
            // expose an unusable encoder. H.264 is the compatibility baseline.
            if (hasEncoder("video/hevc")) {
                attempts += RecorderAttempt(MediaRecorder.VideoEncoder.HEVC, "HEVC", size, bitrate, true)
            }
            attempts += RecorderAttempt(MediaRecorder.VideoEncoder.H264, "H.264", size, bitrate, true)
            attempts += RecorderAttempt(MediaRecorder.VideoEncoder.H264, "H.264", size, bitrate, false)
        }

        var lastError: Throwable? = null
        for (attempt in attempts) {
            val candidate = newMediaRecorder()
            try {
                if (attempt.withAudio) candidate.setAudioSource(MediaRecorder.AudioSource.MIC)
                candidate.setVideoSource(MediaRecorder.VideoSource.SURFACE)
                candidate.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                candidate.setOutputFile(file.absolutePath)
                candidate.setVideoEncodingBitRate(attempt.bitrate)
                candidate.setVideoFrameRate(30)
                candidate.setVideoSize(attempt.size.width, attempt.size.height)
                candidate.setVideoEncoder(attempt.encoder)
                if (attempt.withAudio) {
                    candidate.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    candidate.setAudioEncodingBitRate(128_000)
                    candidate.setAudioSamplingRate(44_100)
                }
                candidate.prepare()
                videoSize = attempt.size
                activeCodec = attempt.codecName
                activeBitrate = attempt.bitrate
                activeAudio = attempt.withAudio
                return candidate
            } catch (t: Throwable) {
                lastError = t
                runCatching { candidate.reset() }
                runCatching { candidate.release() }
                file.delete()
            }
        }
        throw IllegalStateException(
            "No compatible recorder configuration (HEVC/H.264, 1080p/720p) could be prepared",
            lastError,
        )
    }

    @Suppress("DEPRECATION")
    private fun newMediaRecorder(): MediaRecorder =
        if (android.os.Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else MediaRecorder()


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

    private fun calculateBitrate(): Int = activeBitrate

    private fun createOutputFile(): File {
        val dir = File(getExternalFilesDir(null) ?: filesDir, "DigLog").apply { mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        return File(dir, "DIGLOG_$stamp.mp4")
    }

    private fun writeMetadata(file: File): File {
        val json = JSONObject().apply {
            put("profile", "DigLog")
            put("engineBitDepth", internalBitDepth)
            put("gamma", if (usingTenBit) "DigLog10 Gamma v1" else "DigLog GPU Gamma v2")
            put("capture", if (usingTenBit) "Camera2 P010 → OpenGL ES 16-bit DigLog transform → HEVC Main10" else "Camera2 SurfaceTexture → OpenGL ES DigLog shader → encoder surface")
            put("codec", if (usingTenBit) "HEVC Main10" else activeCodec)
            put("audio", if (usingTenBit) false else activeAudio)
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
        return File(file.parentFile, file.nameWithoutExtension + ".diglog.json").apply {
            writeText(json.toString(2))
        }
    }

    private fun publishToSelectedFolder(video: File, metadata: File): String {
        val tree = selectedOutputTree ?: return video.absolutePath
        val parentDocument = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val videoUri = DocumentsContract.createDocument(
            contentResolver,
            parentDocument,
            "video/mp4",
            video.name,
        ) ?: throw IllegalStateException("Could not create the video in the selected folder")

        contentResolver.openOutputStream(videoUri, "w")?.use { output ->
            video.inputStream().use { input -> input.copyTo(output) }
        } ?: throw IllegalStateException("Could not write the video")

        runCatching {
            val metadataUri = DocumentsContract.createDocument(
                contentResolver,
                parentDocument,
                "application/json",
                metadata.name,
            )
            if (metadataUri != null) {
                contentResolver.openOutputStream(metadataUri, "w")?.use { output ->
                    metadata.inputStream().use { input -> input.copyTo(output) }
                }
            }
        }

        video.delete()
        metadata.delete()
        return videoUri.toString()
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
        digLog10?.stop(); digLog10 = null
        digLog8Gpu?.stop(); digLog8Gpu = null
        closeSession(); camera?.close(); recorder?.release(); stopBackground(); super.onDestroy()
    }

    private fun startBackground() { backgroundThread = HandlerThread("DigLogCamera").also { it.start() }; background = Handler(backgroundThread!!.looper) }
    private fun stopBackground() { backgroundThread?.quitSafely(); runCatching { backgroundThread?.join() }; backgroundThread = null; background = null }
}
