package com.example.digitor

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CameraManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaRecorder
import android.os.Build

/**
 * Flexible capability detector.
 *
 * DigLog 10 is selected only when the complete P010/Main10 path exists.
 * Low-end devices can still use the compatible 8-bit engine when a rear
 * Camera2 stream and at least AVC/HEVC hardware encoding are available.
 */
class DigLogCapabilityDetector(private val context: Context) {
    data class Result(
        val available: Boolean,
        val cameraId: String?,
        val internalBitDepth: Int,
        val reason: String,
        val hardwareLevel: String,
        val supportsManualSensor: Boolean,
        val supportsManualPost: Boolean,
        val supportsToneCurve: Boolean,
        val supportsHevc: Boolean,
        val supportsMain10: Boolean,
        val supportsP010: Boolean,
    ) {
        fun asMap(): Map<String, Any?> = mapOf(
            "available" to available,
            "cameraId" to cameraId,
            "internalBitDepth" to internalBitDepth,
            "reason" to reason,
            "hardwareLevel" to hardwareLevel,
            "manualSensor" to supportsManualSensor,
            "manualPostProcessing" to supportsManualPost,
            "toneCurve" to supportsToneCurve,
            "hevc" to supportsHevc,
            "main10" to supportsMain10,
            "p010" to supportsP010,
        )
    }

    fun detect(): Result {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val hevc = hasEncoder("video/hevc")
        val avc = hasEncoder("video/avc")
        val main10 = hasHevcMain10Encoder()

        var fallback: Result? = null
        for (id in manager.cameraIdList) {
            val c = runCatching { manager.getCameraCharacteristics(id) }.getOrNull() ?: continue
            if (c.get(CameraCharacteristics.LENS_FACING) != CameraCharacteristics.LENS_FACING_BACK) continue

            val level = c.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)
            val levelName = hardwareLevelName(level)
            val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)?.toSet().orEmpty()
            val manualSensor = caps.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)
            val manualPost = caps.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_POST_PROCESSING)
            val toneModes = c.get(CameraCharacteristics.TONEMAP_AVAILABLE_TONE_MAP_MODES)?.toSet().orEmpty()
            val toneCurve = toneModes.contains(CameraMetadata.TONEMAP_MODE_CONTRAST_CURVE)
            val p010 = Build.VERSION.SDK_INT >= 33 &&
                c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                    ?.outputFormats?.contains(ImageFormat.YCBCR_P010) == true

            val hasRecordSize = c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(MediaRecorder::class.java)
                ?.isNotEmpty() == true

            val professionalLevel = level == CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_FULL ||
                level == CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_3
            val supportsTenBit = professionalLevel && manualSensor && manualPost &&
                toneCurve && p010 && main10

            if (supportsTenBit) {
                return Result(
                    true, id, 10, "DigLog 10 ready", levelName,
                    manualSensor, manualPost, toneCurve, hevc, main10, p010,
                )
            }

            // Flexible low-end path: LEGACY/LIMITED cameras are accepted when they can
            // create a normal video stream and the device has AVC or HEVC encoding.
            if (hasRecordSize && (hevc || avc) && fallback == null) {
                fallback = Result(
                    true, id, 8, "Compatible DigLog engine ready", levelName,
                    manualSensor, manualPost, toneCurve, hevc, main10, p010,
                )
            }
        }

        return fallback ?: Result(
            false,
            null,
            0,
            "No rear camera with a compatible video encoder is available.",
            "Unavailable",
            false,
            false,
            false,
            hevc,
            main10,
            false,
        )
    }

    private fun hasEncoder(mime: String): Boolean =
        MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.any { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
        }

    private fun hasHevcMain10Encoder(): Boolean =
        MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.any { info ->
            if (!info.isEncoder) return@any false
            val type = info.supportedTypes.firstOrNull { it.equals("video/hevc", true) } ?: return@any false
            runCatching {
                info.getCapabilitiesForType(type).profileLevels.any { p ->
                    p.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 ||
                        (Build.VERSION.SDK_INT >= 24 && p.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10) ||
                        (Build.VERSION.SDK_INT >= 24 && p.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus)
                }
            }.getOrDefault(false)
        }

    private fun hardwareLevelName(level: Int?): String = when (level) {
        CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_3 -> "LEVEL_3"
        CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_FULL -> "FULL"
        CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED -> "LIMITED"
        CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY -> "LEGACY"
        CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL -> "EXTERNAL"
        else -> "UNKNOWN"
    }
}
