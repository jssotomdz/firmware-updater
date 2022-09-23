import 'package:fwupd/fwupd.dart';
import 'package:safe_change_notifier/safe_change_notifier.dart';

import 'firmware_model.dart';

class DeviceModel extends SafeChangeNotifier {
  DeviceModel(this._firmwareModel, this._device)
      : _releases = _firmwareModel.state.getReleases(_device);
  final FirmwareModel _firmwareModel;
  final FwupdDevice _device;
  final List<FwupdRelease>? _releases;

  FwupdRelease? _selectedRelease;
  FwupdRelease? get selectedRelease => _selectedRelease;
  set selectedRelease(FwupdRelease? release) {
    _selectedRelease = release;
    notifyListeners();
  }

  FwupdDevice get device => _device;
  List<FwupdRelease>? get releases => _releases;

  Future<void> verify() => _firmwareModel.verify(_device);
  Future<void> verifyUpdate() => _firmwareModel.verifyUpdate(_device);
  Future<void> install(FwupdRelease release) =>
      _firmwareModel.install(_device, release);
  bool hasUpgrade() => _firmwareModel.state.hasUpgrade(_device);
}