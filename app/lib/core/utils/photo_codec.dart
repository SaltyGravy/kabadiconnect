import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Compresses a captured photo down to a small JPEG and base64-encodes it,
/// so it can be stored directly on the lot's Firestore document instead of
/// in Cloud Storage (this project deliberately doesn't use Cloud Storage --
/// see docs/dataset_documentation.md). Firestore caps a document at 1MB;
/// resizing to 480px wide at moderate JPEG quality typically lands well
/// under 60KB, leaving comfortable headroom.
String compressPhotoToBase64(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return '';
  final resized = decoded.width > 480 ? img.copyResize(decoded, width: 480) : decoded;
  final jpeg = img.encodeJpg(resized, quality: 55);
  return base64Encode(jpeg);
}

Uint8List decodeBase64Photo(String base64Str) {
  if (base64Str.isEmpty) return Uint8List(0);
  return base64Decode(base64Str);
}
