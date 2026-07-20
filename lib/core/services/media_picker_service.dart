import 'package:image_picker/image_picker.dart';

class MediaPickerService {
  MediaPickerService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  Future<XFile?> pickVideo() {
    return _imagePicker.pickVideo(source: ImageSource.gallery);
  }

  Future<XFile?> pickImage() {
    return _imagePicker.pickImage(source: ImageSource.gallery);
  }

  /// image_picker has no audio-only platform picker. This keeps the picker
  /// access centralized while rejecting selections with an unsupported suffix.
  Future<XFile?> pickAudio() async {
    final file = await _imagePicker.pickMedia();
    if (file == null) return null;
    const audioExtensions = {'.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac'};
    final lower = file.path.toLowerCase();
    return audioExtensions.any(lower.endsWith) ? file : null;
  }
}
