import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'faces.dart';

class MlKitFaceFinder implements FaceFinder {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      minFaceSize: 0.12,
    ),
  );

  @override
  Future<List<FaceBox>> locate(String imagePath) async {
    final faces = await _detector.processImage(
      InputImage.fromFilePath(imagePath),
    );
    return [
      for (final face in faces)
        FaceBox(
          left: face.boundingBox.left.round(),
          top: face.boundingBox.top.round(),
          width: face.boundingBox.width.round(),
          height: face.boundingBox.height.round(),
          leftEyeX: face.landmarks[FaceLandmarkType.leftEye]?.position.x
              .toDouble(),
          leftEyeY: face.landmarks[FaceLandmarkType.leftEye]?.position.y
              .toDouble(),
          rightEyeX: face.landmarks[FaceLandmarkType.rightEye]?.position.x
              .toDouble(),
          rightEyeY: face.landmarks[FaceLandmarkType.rightEye]?.position.y
              .toDouble(),
        ),
    ];
  }

  @override
  Future<void> close() => _detector.close();
}
