import 'package:flutter_test/flutter_test.dart';

import 'package:tri_flash/app/app.dart';

void main() {
  test('the app root can be constructed', () {
    const app = TriFlashApp();

    expect(app, isA<TriFlashApp>());
  });
}
