package com.example.digitor

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.view.Display
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

@OptIn(UnstableApi::class)
class MainActivity : FlutterActivity() {
    private val channelName = "digitor/mobile_export"
    private val digLogChannelName = "digitor/diglog"
    private val digLogCaptureRequest = 4208
    private var pendingDigLogResult: MethodChannel.Result? = null
    private val createDocumentRequest = 4107
    private var pendingLocationResult: MethodChannel.Result? = null
    private var transformer: Transformer? = null
    private var exportResult: MethodChannel.Result? = null
    private var destinationUri: Uri? = null
    private var temporaryOutput: File? = null
    private val progressHolder = ProgressHolder()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handleMethod(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, digLogChannelName)
            .setMethodCallHandler { call, result -> handleDigLogMethod(call, result) }
    }

    private fun handleDigLogMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(DigLogCapabilityDetector(this).detect().asMap())
            "openCapture" -> {
                if (pendingDigLogResult != null) {
                    result.error("capture_busy", "DigLog capture is already open.", null)
                    return
                }
                val capability = DigLogCapabilityDetector(this).detect()
                if (!capability.available || capability.cameraId == null) {
                    result.error("not_available", capability.reason, capability.asMap())
                    return
                }
                pendingDigLogResult = result
                val intent = Intent(this, DigLogCaptureActivity::class.java).apply {
                    putExtra(DigLogCaptureActivity.EXTRA_CAMERA_ID, capability.cameraId)
                    putExtra(DigLogCaptureActivity.EXTRA_BIT_DEPTH, capability.internalBitDepth)
                }
                startActivityForResult(intent, digLogCaptureRequest)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "chooseLocation" -> chooseLocation(call, result)
            "startExport" -> startExport(call, result)
            "getProgress" -> getProgress(result)
            "getExportCapabilities" -> result.success(getExportCapabilities())
            "cancelExport" -> {
                transformer?.cancel()
                cleanupExport()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }


    private fun getExportCapabilities(): Map<String, Any> {
        val codecs = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
        var h264Encoder = false
        var hevcEncoder = false
        var hevc10BitEncoder = false
        var dolbyVisionEncoder = false
        var supports4k60 = false

        codecs.filter { it.isEncoder }.forEach { codec ->
            codec.supportedTypes.forEach { type ->
                when (type.lowercase()) {
                    MimeTypes.VIDEO_H264 -> {
                        h264Encoder = true
                        runCatching {
                            val caps = codec.getCapabilitiesForType(type).videoCapabilities
                            if (caps != null && caps.areSizeAndRateSupported(3840, 2160, 60.0)) {
                                supports4k60 = true
                            }
                        }
                    }
                    MimeTypes.VIDEO_H265 -> {
                        hevcEncoder = true
                        runCatching {
                            val capabilities = codec.getCapabilitiesForType(type)
                            val profileLevels = capabilities.profileLevels
                            hevc10BitEncoder = hevc10BitEncoder || profileLevels.any {
                                it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 ||
                                    it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10 ||
                                    it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus
                            }
                            val videoCaps = capabilities.videoCapabilities
                            if (videoCaps != null && videoCaps.areSizeAndRateSupported(3840, 2160, 60.0)) {
                                supports4k60 = true
                            }
                        }
                    }
                    "video/dolby-vision" -> dolbyVisionEncoder = true
                }
            }
        }

        val hdrTypes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.hdrCapabilities.supportedHdrTypes.toSet()
        } else {
            emptySet()
        }

        val displayHdr10 = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_HDR10)
        } else false
        val displayDolbyVision = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION)
        } else false
        val displayHlg = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_HLG)
        } else false

        return mapOf(
            "h264Encoder" to h264Encoder,
            "hevcEncoder" to hevcEncoder,
            "hevc10BitEncoder" to hevc10BitEncoder,
            "dolbyVisionEncoder" to dolbyVisionEncoder,
            "supports4k60" to supports4k60,
            "displayHdr10" to displayHdr10,
            "displayDolbyVision" to displayDolbyVision,
            "displayHlg" to displayHlg,
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
        )
    }

    private fun chooseLocation(call: MethodCall, result: MethodChannel.Result) {
        if (pendingLocationResult != null) {
            result.error("picker_busy", "The export location browser is already open.", null)
            return
        }
        pendingLocationResult = result
        val fileName = call.argument<String>("fileName") ?: "Digitor Export.mp4"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/mp4"
            putExtra(Intent.EXTRA_TITLE, fileName)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, createDocumentRequest)
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == digLogCaptureRequest) {
            val pending = pendingDigLogResult
            pendingDigLogResult = null
            if (resultCode == Activity.RESULT_OK) {
                pending?.success(data?.getStringExtra(DigLogCaptureActivity.EXTRA_OUTPUT_PATH))
            } else {
                val error = data?.getStringExtra("error")
                if (error.isNullOrBlank()) pending?.success(null) else pending?.error("capture_failed", error, null)
            }
            return
        }
        if (requestCode != createDocumentRequest) return
        val pending = pendingLocationResult
        pendingLocationResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending?.success(null)
            return
        }
        val uri = data.data!!
        contentResolver.takePersistableUriPermission(
            uri,
            data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION),
        )
        pending?.success(
            mapOf(
                "uri" to uri.toString(),
                "label" to (uri.lastPathSegment ?: "Selected export location"),
            ),
        )
    }

    private fun startExport(call: MethodCall, result: MethodChannel.Result) {
        if (transformer != null) {
            result.error("export_busy", "Another export is already running.", null)
            return
        }

        val outputUri = call.argument<String>("outputUri")
        val clips = call.argument<List<Map<String, Any?>>>("clips")
        if (outputUri.isNullOrBlank() || clips.isNullOrEmpty()) {
            result.error("invalid_export", "Output location or timeline clips are missing.", null)
            return
        }

        try {
            destinationUri = Uri.parse(outputUri)
            exportResult = result
            val width = call.argument<Int>("width") ?: 1920
            val height = call.argument<Int>("height") ?: 1080
            val frameRate = call.argument<Int>("frameRate") ?: 30
            val bitrate = call.argument<Int>("videoBitrate") ?: 8_000_000
            val codec = call.argument<String>("videoCodec") ?: "h264"

            val items = clips.map { clip ->
                createEditedMediaItem(clip, width, height, frameRate)
            }
            val sequence = EditedMediaItemSequence.Builder(items).build()
            val composition = Composition.Builder(sequence).build()
            val temp = File(cacheDir, "digitor_export_${System.currentTimeMillis()}.mp4")
            temporaryOutput = temp

            val encoderFactory = DefaultEncoderFactory.Builder(this)
                .setEnableFallback(true)
                .setRequestedVideoEncoderSettings(
                    VideoEncoderSettings.Builder().setBitrate(bitrate).build(),
                )
                .build()

            transformer = Transformer.Builder(this)
                .setEncoderFactory(encoderFactory)
                .setVideoMimeType(if (codec == "h265") MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResultValue: ExportResult) {
                        try {
                            copyToDestination(temp, destinationUri!!)
                            exportResult?.success(destinationUri.toString())
                        } catch (error: Throwable) {
                            exportResult?.error("save_failed", error.message, null)
                        } finally {
                            cleanupExport()
                        }
                    }

                    override fun onError(
                        composition: Composition,
                        exportResultValue: ExportResult,
                        exportException: ExportException,
                    ) {
                        exportResult?.error("export_failed", exportException.message, exportException.errorCode)
                        cleanupExport()
                    }
                })
                .build()

            transformer!!.start(composition, temp.absolutePath)
        } catch (error: Throwable) {
            cleanupExport()
            result.error("export_setup_failed", error.message, null)
        }
    }

    private fun createEditedMediaItem(
        clip: Map<String, Any?>,
        width: Int,
        height: Int,
        frameRate: Int,
    ): EditedMediaItem {
        val path = clip["path"] as String
        val type = clip["type"] as String
        val durationMs = (clip["durationMs"] as Number).toLong().coerceAtLeast(1L)
        val sourceStartMs = (clip["sourceStartMs"] as Number).toLong().coerceAtLeast(0L)
        val sourceEndMs = (clip["sourceEndMs"] as Number).toLong().coerceAtLeast(sourceStartMs + 1)
        val removeAudio = clip["removeAudio"] as? Boolean ?: false
        val uri = if (path.startsWith("content://")) Uri.parse(path) else Uri.fromFile(File(path))

        val mediaBuilder = MediaItem.Builder().setUri(uri)
        if (type == "image") {
            mediaBuilder.setImageDurationMs(durationMs)
        } else {
            mediaBuilder.setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(sourceStartMs)
                    .setEndPositionMs(sourceEndMs)
                    .build(),
            )
        }

        val presentation = Presentation.createForWidthAndHeight(
            width,
            height,
            Presentation.LAYOUT_SCALE_TO_FIT,
        )
        return EditedMediaItem.Builder(mediaBuilder.build())
            .setDurationUs(durationMs * 1000)
            .setFrameRate(frameRate)
            .setRemoveAudio(removeAudio)
            .setEffects(
                Effects(
                    ImmutableList.of(),
                    ImmutableList.of<Effect>(presentation),
                ),
            )
            .build()
    }

    private fun getProgress(result: MethodChannel.Result) {
        val current = transformer
        if (current == null) {
            result.success(mapOf("state" to "idle", "percent" to 0))
            return
        }
        val state = current.getProgress(progressHolder)
        val label = when (state) {
            Transformer.PROGRESS_STATE_AVAILABLE -> "running"
            Transformer.PROGRESS_STATE_WAITING_FOR_AVAILABILITY -> "waiting"
            Transformer.PROGRESS_STATE_NOT_STARTED -> "waiting"
            else -> "idle"
        }
        result.success(mapOf("state" to label, "percent" to progressHolder.progress))
    }

    private fun copyToDestination(source: File, destination: Uri) {
        contentResolver.openFileDescriptor(destination, "w")?.use { descriptor ->
            FileInputStream(source).use { input ->
                FileOutputStream(descriptor.fileDescriptor).use { output -> input.copyTo(output) }
            }
        } ?: error("The selected export location could not be opened.")
    }

    private fun cleanupExport() {
        transformer = null
        exportResult = null
        destinationUri = null
        temporaryOutput?.delete()
        temporaryOutput = null
    }
}
