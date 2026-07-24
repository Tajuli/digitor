enum ClipFilterType { none, warm, cool, cinematic, vintage, blackAndWhite }

enum ClipEffectType { none, glitch, vignette, shake, blur }

class ClipColorAdjustments {
  const ClipColorAdjustments({this.exposure = 0, this.contrast = 0, this.saturation = 0, this.temperature = 0, this.tint = 0, this.highlights = 0, this.shadows = 0});
  final double exposure, contrast, saturation, temperature, tint, highlights, shadows;
  ClipColorAdjustments copyWith({double? exposure, double? contrast, double? saturation, double? temperature, double? tint, double? highlights, double? shadows}) => ClipColorAdjustments(exposure: exposure ?? this.exposure, contrast: contrast ?? this.contrast, saturation: saturation ?? this.saturation, temperature: temperature ?? this.temperature, tint: tint ?? this.tint, highlights: highlights ?? this.highlights, shadows: shadows ?? this.shadows);
}
