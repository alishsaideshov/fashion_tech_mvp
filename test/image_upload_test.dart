import 'package:fashion_tech_mvp/ai/ai_validation_models.dart';
import 'package:fashion_tech_mvp/image_upload.dart';
import 'package:flutter_test/flutter_test.dart';

AiImageInput photo(int index) => AiImageInput(
  name: 'garment-$index.jpg',
  mimeType: 'image/jpeg',
  base64Data: 'photo-$index',
);

void main() {
  test('adding photos preserves all existing and new wardrobe images', () {
    final selected = mergeWardrobeImages([photo(1), photo(2)], [photo(3)]);
    expect(selected.map((image) => image.name), [
      'garment-1.jpg',
      'garment-2.jpg',
      'garment-3.jpg',
    ]);
  });

  test('reselecting a photo does not duplicate it or discard other photos', () {
    final selected = mergeWardrobeImages([photo(1)], [photo(1), photo(2)]);
    expect(selected.map((image) => image.base64Data), ['photo-1', 'photo-2']);
  });

  test('cancel preserves the selection', () {
    expect(mergeWardrobeImages([photo(1)], []).single.name, 'garment-1.jpg');
  });

  test(
    'overflow is rejected without silently truncating or mutating inputs',
    () {
      final existing = [photo(1), photo(2)];
      expect(
        () => mergeWardrobeImages(existing, [
          photo(3),
          photo(4),
          photo(5),
          photo(6),
        ]),
        throwsStateError,
      );
      expect(existing.length, 2);
      expect(
        mergeWardrobeImages(existing, [photo(3), photo(4), photo(5)]).length,
        5,
      );
    },
  );
}
