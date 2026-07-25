import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Cross-platform media picker for Android, iOS, Windows and macOS.
///
/// Mobile uses the native photo library for photos/videos. Desktop uses the
/// operating-system file picker because `image_picker` is not consistently
/// available for every desktop workflow. Audio always uses a file picker.
class MediaPickerService {
  MediaPickerService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<XFile?> pickVideo() async {
    if (!_isDesktop) {
      return _imagePicker.pickVideo(source: ImageSource.gallery);
    }

    return _pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'mp4',
        'mov',
        'm4v',
        'avi',
        'mkv',
        'webm',
        'wmv',
      ],
    );
  }

  Future<XFile?> pickImage() async {
    if (!_isDesktop) {
      return _imagePicker.pickImage(source: ImageSource.gallery);
    }

    return _pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'bmp',
        'gif',
        'heic',
        'heif',
      ],
    );
  }

  Future<XFile?> pickAudio() {
    return _pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'mp3',
        'm4a',
        'aac',
        'wav',
        'ogg',
        'flac',
        'opus',
      ],
    );
  }

  Future<XFile?> _pickFile({
    required FileType type,
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      lockParentWindow: true,
    );

    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return null;
    return XFile(path);
  }
}
