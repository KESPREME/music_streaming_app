import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/audio_output_service.dart';
import 'package:music_streaming_app/widgets/audio_output_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  group('AudioOutputDevice.displayName', () {
    test('keeps the product name for named outputs', () {
      const d = AudioOutputDevice(
          id: 1, kind: 'bluetooth', name: 'Galaxy Buds2 Pro', isActive: true);
      expect(d.displayName, 'Galaxy Buds2 Pro');
    });

    test('labels the nameless kinds instead of a phone model', () {
      expect(
        const AudioOutputDevice(id: 1, kind: 'phone', name: '', isActive: true)
            .displayName,
        'This phone',
      );
      expect(
        const AudioOutputDevice(id: 2, kind: 'wired', name: '', isActive: false)
            .displayName,
        'Wired headphones',
      );
      expect(
        const AudioOutputDevice(id: 3, kind: 'usb', name: '', isActive: false)
            .displayName,
        'USB audio',
      );
    });

    test('fromMap tolerates missing keys', () {
      const d = AudioOutputDevice(id: 0, kind: 'other', name: '', isActive: false);
      expect(d.displayName, isNotEmpty);
      final parsed = AudioOutputDevice.fromMap(const {});
      expect(parsed.id, 0);
      expect(parsed.isActive, isFalse);
    });
  });

  group('AudioOutputService without a native channel', () {
    test('init degrades instead of throwing', () async {
      final service = AudioOutputService();
      await service.init();
      expect(service.outputs, isEmpty);
      expect(service.active, isNull);
      expect(service.activeName, 'This phone');
      service.dispose();
    });

    test('setDeviceVolume is optimistic and local', () async {
      final service = AudioOutputService();
      await service.setDeviceVolume(0.4);
      expect(service.volume, closeTo(0.4, 0.001));
      await service.setDeviceVolume(2.0);
      expect(service.volume, 1.0);
      await service.setDeviceVolume(-1.0);
      expect(service.volume, 0.0);
      service.dispose();
    });

    test('silent writes skip notify for drag ticks', () async {
      final service = AudioOutputService();
      var notifications = 0;
      service.addListener(() => notifications++);
      await service.setDeviceVolume(0.4, notify: false);
      expect(service.volume, closeTo(0.4, 0.001));
      expect(notifications, 0);
      await service.setDeviceVolume(0.5);
      expect(notifications, 1);
      service.dispose();
    });

    test('openSoundSettings degrades instead of throwing', () async {
      final service = AudioOutputService();
      await service.openSoundSettings();
      service.dispose();
    });
  });

  group('AudioOutputSheet', () {
    testWidgets('shows empty state with no outputs', (tester) async {
      final service = AudioOutputService();
      await tester.pumpWidget(
        ChangeNotifierProvider<AudioOutputService>.value(
          value: service,
          child: const MaterialApp(
            home: Scaffold(body: AudioOutputSheet()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Audio output'), findsOneWidget);
      expect(find.text('No outputs found'), findsOneWidget);
      service.dispose();
    });

    testWidgets('marks the active route with Playing here and a check',
        (tester) async {
      final service = AudioOutputService()
        ..outputs = const [
          AudioOutputDevice(
              id: 1, kind: 'phone', name: '', isActive: false),
          AudioOutputDevice(
              id: 2,
              kind: 'bluetooth',
              name: 'Galaxy Buds2 Pro',
              isActive: true),
        ];
      await tester.pumpWidget(
        ChangeNotifierProvider<AudioOutputService>.value(
          value: service,
          child: const MaterialApp(
            home: Scaffold(body: AudioOutputSheet()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Galaxy Buds2 Pro'), findsOneWidget);
      expect(find.text('Playing here'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('This phone'), findsOneWidget);
      service.dispose();
    });
  });
}
