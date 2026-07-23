package com.example.digitor

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CameraManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build

/** Strict capability gate. DigLog is never exposed as a cosmetic flat filter. */
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
        val hevc = hasHevcEncoder(false)
        val main10 = hasHevcEncoder(true)

        var bestFailure = "No rear camera exposes the controls required by DigLog."
        for (id in manager.cameraIdList) {
            val c = manager.getCameraCharacteristics(id)
            if (c.get(CameraCharacteristics.LENS_FACING) != CameraCharacteristics.LENS_FACING_BACK) continue

            val level = c.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)
            val levelName = hardwareLevelName(level)
            val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)?.toSet().orEmpty()
            val manualSensor = caps.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)
            val manualPost = caps.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_POST_PROCESSING)
            val toneModes = c.get(CameraCharacteristics.TONEMAP_AVAILABLE_TONE_MAP_MODES)?.toSet().orEmpty()
            val toneCurve = toneModes.contains(CameraMetadata.TONEMAP_MODE_CONTRAST_CURVE)
            val suitableLevel = level == CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_FULL ||
                level == CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_3
            val p010 = if (Build.VERSION.SDK_INT >= 33) {
                c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                    ?.outputFormats?.contains(ImageFormat.YCBCR_P010) == true
            } else false

            val available = suitableLevel && manualSensor && manualPost && toneCurve && hevc
            if (available) {
                // Select the hidden 10-bit engine only when the complete public Android path exists.
                // Otherwise the same DigLog UI automatically uses the strict 8-bit engine.
                val depth = if (Build.VERSION.SDK_INT >= 33 && p010 && main10) 10 else 8
                return Result(true, id, depth, "DigLog ready", levelName, manualSensor, manualPost, toneCurve, hevc, main10, p010)
            }
            bestFailure = when {
                !suitableLevel -> "Camera hardware level $levelName cannot preserve enough controllable image data."
                !manualSensor -> "Manual sensor control is not exposed by this camera."
                !manualPost -> "Manual post-processing control is not exposed by this camera."
                !toneCurve -> "A programmable tone curve is not exposed by this camera."
                !hevc -> "A hardware HEVC encoder is not available."
                else -> bestFailure
            }
        }
        return Result(false, null, 0, bestFailure, "Unavailable", false, false, false, hevc, main10, false)
    }

    private fun hasHevcEncoder(requireMain10: Boolean): Boolean {
        return MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.any { info ->
            if (!info.isEncoder) return@any false
            val type = info.supportedTypes.firstOrNull { it.equals("video/hevc", true) } ?: return@any false
            if (!requireMain10) return@any true
            runCatching {
                info.getCapabilitiesForType(type).profileLevels.any { p ->
                    p.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 ||
                        (Build.VERSION.SDK_INT >= 24 && p.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10) ||
                        (Build.VERSION.SDK_INT >= 24 && p.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus)
                }
            }.getOrDefault(false)
        }
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
