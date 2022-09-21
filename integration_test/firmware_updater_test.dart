import 'package:collection/collection.dart';
import 'package:firmware_updater/device_page.dart';
import 'package:firmware_updater/fwupd_x.dart';
import 'package:firmware_updater/main.dart' as app;
import 'package:firmware_updater/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fwupd/fwupd.dart';
import 'package:integration_test/integration_test.dart';

import '../test/test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final client = FwupdClient();
  setUpAll(client.connect);
  tearDownAll(client.close);

  group('fake webcam', () {
    testWidgets('upgrade', (tester) async {
      final webcam = await client.findDevice((d) => d.summary == 'Fake webcam');
      expect(webcam, isNotNull, reason: 'Install fwupd-tests (Fake webcam).');

      final upgrade = await client.findRelease(webcam!, (r) => r.isUpgrade);
      expect(upgrade, isNotNull, reason: 'Fake webcam has no upgrades');
      expect(upgrade!.version, isNotEmpty);

      await app.main();
      await tester.pumpAndSettle();

      await tester.pumpAndTapDeviceHeader('Fake webcam');
      await tester.pumpAndSettle();

      expect(find.devicePage(upgrade.version), findsNothing);

      await tester.pumpAndTapButton(tester.lang.showUpdates);
      await tester.pumpAndSettle();

      await tester.pumpAndTapReleaseCard(upgrade.version);
      await tester.pumpAndSettle();

      await tester.pumpAndTapButton(tester.lang.upgrade);
      await tester.pumpAndSettle();

      await tester.pumpAndTapButton(tester.lang.ok);
      await client.testInstallation(webcam, upgrade);
    });

    testWidgets('reinstall', (tester) async {
      final webcam = await client.findDevice((d) => d.summary == 'Fake webcam');
      expect(webcam, isNotNull, reason: 'Install fwupd-tests (Fake webcam).');

      final reinstall = await client.findRelease(
        webcam!,
        (r) => !r.isDowngrade && !r.isUpgrade,
      );
      expect(reinstall, isNotNull, reason: 'Fake webcam has no reinstall');
      expect(reinstall!.version, isNotEmpty);

      await app.main();
      await tester.pumpAndSettle();

      await tester.pumpAndTapDeviceHeader('Fake webcam');
      await tester.pumpAndSettle();

      expect(find.devicePage(reinstall.version), findsOneWidget);

      await tester.pumpAndTapButton(tester.lang.showReleases);
      await tester.pumpAndSettle();

      await tester.pumpAndTapReleaseCard(reinstall.version);
      await tester.pumpAndSettle();

      await tester.pumpAndTapButton(tester.lang.reinstall);
      await tester.pumpAndSettle();

      await tester.pumpAndTapButton(tester.lang.ok);
      await client.testInstallation(webcam, reinstall);
    });

    testWidgets('downgrade', (tester) async {
      final webcam = await client.findDevice((d) => d.summary == 'Fake webcam');
      expect(webcam, isNotNull, reason: 'Install fwupd-tests (Fake webcam).');

      final downgrade = await client.findRelease(webcam!, (r) => r.isDowngrade);
      expect(downgrade, isNotNull, reason: 'Fake webcam has no downgrades');
      expect(downgrade!.version, isNotEmpty);

      await app.main();
      await tester.pumpAndSettle();

      await tester.pumpAndTapDeviceHeader('Fake webcam');
      await tester.pumpAndSettle();

      expect(find.devicePage(downgrade.version), findsNothing);

      await tester.pumpAndTapButton(tester.lang.showReleases);
      await tester.pumpAndSettle();

      await tester.pumpAndTapReleaseCard(downgrade.version);
      await tester.pumpAndSettle();

      await tester.pumpAndTapButton(tester.lang.downgrade);
      await tester.pumpAndSettle();

      await tester.pumpAndTapButton(tester.lang.ok);
      await client.testInstallation(webcam, downgrade);
    });
  });
}

extension IntegrationClient on FwupdClient {
  Future<FwupdDevice?> findDevice(bool Function(FwupdDevice) test) {
    return getDevices().then((d) => d.firstWhereOrNull(test));
  }

  Future<FwupdRelease?> findRelease(
    FwupdDevice device,
    bool Function(FwupdRelease) test,
  ) {
    return getReleases(device.deviceId).then((r) => r.firstWhereOrNull(test));
  }

  Future<void> testInstallation(
    FwupdDevice device,
    FwupdRelease release, [
    Duration timeout = const Duration(seconds: 60),
  ]) async {
    await expectLater(
      propertiesChanged
          .where((p) => p.contains('Status'))
          .map((_) => status)
          .timeout(timeout),
      emitsThrough(FwupdStatus.deviceWrite),
    );

    if (percentage < 100) {
      await expectLater(
        propertiesChanged
            .where((p) => p.contains('Percentage'))
            .map((_) => percentage)
            .timeout(timeout),
        emitsThrough(100),
      );
    }

    if (status.isBusy) {
      await expectLater(
        propertiesChanged
            .where((p) => p.contains('Status'))
            .map((_) => status.isBusy)
            .timeout(timeout),
        emitsThrough(false),
      );
    }

    final updateState = await findDevice((d) =>
            d.deviceId == device.deviceId && d.version == release.version)
        .then((d) => d?.updateState);
    if (updateState != FwupdUpdateState.success) {
      await expectLater(
        deviceChanged
            .where((d) =>
                d.deviceId == device.deviceId && d.version == release.version)
            .map((d) => d.updateState),
        emitsThrough(FwupdUpdateState.success),
      );
    }
  }
}

extension IntegrationTester on WidgetTester {
  Future<void> pumpAndTapDeviceHeader(String text) async {
    final header = find.deviceHeader(text);
    await pumpUntil(header);
    return tap(header);
  }

  Future<void> pumpAndTapButton(String text) async {
    final button = find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    if (button.evaluate().length > 1) {
      debugPrint('WARNING: Multiple "$text" buttons. Assuming the first.');
    }
    await pumpUntil(button.first);
    return tap(button.first);
  }

  Future<void> pumpAndTapReleaseCard(String version) async {
    final card = find.widgetWithText(ReleaseCard, version);
    await pumpUntil(card);
    return tap(card);
  }
}

extension IntegrationFinder on CommonFinders {
  Finder deviceHeader(String text) => find.widgetWithText(DeviceHeader, text);
  Finder devicePage(String text) => find.widgetWithText(DevicePage, text);
}
