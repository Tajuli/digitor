package com.example.digitor.diglog.color

import kotlin.math.exp
import kotlin.math.ln

/**
 * Digitor's own scene-referred-ish display encoding, not a camera tonemap.
 *
 * Input is normalized linear RGB.  The curve has a smooth exponential toe below
 * 18% gray and a logarithmic body/shoulder above it:
 *   f(x) = A * (1 - exp(-x / T))                    x <= 0.18
 *   f(x) = B + C * ln(1 + D * (x - 0.18))           x >  0.18
 * Constants make f continuous at 18% and reserve code values above diffuse
 * white for highlight headroom.  This is monotonic and has an analytic inverse.
 */
object DigLogTransferFunction {
    const val REFERENCE_BLACK = 0.0f
    const val REFERENCE_NEUTRAL_GRAY = 0.18f
    const val REFERENCE_DIFFUSE_WHITE = 1.0f
    const val HIGHLIGHT_HEADROOM_STOPS = 2.0f
    private const val TOE_SCALE = 0.18f
    private const val TOE_GAIN = 0.28f
    private const val BODY_OFFSET = 0.28f
    private const val BODY_GAIN = 0.38f
    private const val BODY_SCALE = 2.4f
    private val toeAtGray = TOE_GAIN * (1f - exp(-REFERENCE_NEUTRAL_GRAY / TOE_SCALE))

    fun encode(value: Float): Float {
        val x = value.takeIf { it.isFinite() }?.coerceAtLeast(0f) ?: 0f
        return if (x <= REFERENCE_NEUTRAL_GRAY) {
            TOE_GAIN * (1f - exp(-x / TOE_SCALE))
        } else {
            toeAtGray + BODY_OFFSET + BODY_GAIN * ln(1f + BODY_SCALE * (x - REFERENCE_NEUTRAL_GRAY))
        }
    }

    fun decode(code: Float): Float {
        val y = code.takeIf { it.isFinite() }?.coerceAtLeast(0f) ?: 0f
        return if (y <= toeAtGray) {
            -TOE_SCALE * ln((1f - y / TOE_GAIN).coerceAtLeast(1e-6f))
        } else {
            REFERENCE_NEUTRAL_GRAY + (exp((y - toeAtGray - BODY_OFFSET) / BODY_GAIN) - 1f) / BODY_SCALE
        }
    }
}
