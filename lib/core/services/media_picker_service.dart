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
}
