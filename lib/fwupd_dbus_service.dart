import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:dio/dio.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:fwupd/fwupd.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:ubuntu_logger/ubuntu_logger.dart';
import 'package:upower/upower.dart';

import 'fwupd_service.dart';
import 'fwupd_x.dart';

final log = Logger('fwupd_service');

class FwupdDbusService extends FwupdService {
  FwupdDbusService({
    @visibleForTesting FwupdClient? fwupd,
    @visibleForTesting Dio? dio,
    @visibleForTesting FileSystem? fs,
    @visibleForTesting DBusClient? dbus,
    @visibleForTesting UPowerClient? upower,
  })  : _dio = dio ?? Dio(),
        _fs = fs ?? const LocalFileSystem(),
        _fwupd = fwupd ?? FwupdClient(),
        _dbus = dbus ?? DBusClient.system(),
        _upower = upower ?? UPowerClient();

  final Dio _dio;
  final FileSystem _fs;
  final FwupdClient _fwupd;
  final UPowerClient _upower;
  final DBusClient _dbus;
  int? _downloadProgress;
  final _propertiesChanged = StreamController<List<String>>();
  StreamSubscription<List<String>>? _fwupdPropertiesSubscription;
  StreamSubscription<List<String>>? _upowerPropertiesSubscription;

  @override
  FwupdStatus get status =>
      _downloadProgress != null ? FwupdStatus.downloading : _fwupd.status;
  @override
  int get percentage => _downloadProgress ?? _fwupd.percentage;
  @override
  String get daemonVersion => _fwupd.daemonVersion;

  @override
  Stream<FwupdDevice> get deviceAdded => _fwupd.deviceAdded;
  @override
  Stream<FwupdDevice> get deviceChanged => _fwupd.deviceChanged;
  @override
  Stream<FwupdDevice> get deviceRemoved => _fwupd.deviceRemoved;
  @override
  Stream<FwupdDevice> get deviceRequest => _fwupd.deviceRequest;
  @override
  Stream<List<String>> get propertiesChanged => _propertiesChanged.stream;

  Function(Exception)? _errorListener;
  Future<bool> Function()? _confirmationListener;

  @override
  void registerErrorListener(Function(Exception e) errorListener) {
    _errorListener = errorListener;
  }

  @override
  void registerConfirmationListener(
      Future<bool> Function() confirmationListener) {
    _confirmationListener = confirmationListener;
  }

  @override
  Future<void> init() async {
    await _fwupd.connect();
    _fwupdPropertiesSubscription ??=
        _fwupd.propertiesChanged.listen(_propertiesChanged.add);
    await _upower.connect();
    _upowerPropertiesSubscription ??=
        _upower.propertiesChanged.listen(_propertiesChanged.add);
    _propertiesChanged.add(['OnBattery']);
  }

  @override
  Future<void> dispose() async {
    _dio.close();
    await _fwupdPropertiesSubscription?.cancel();
    await _upowerPropertiesSubscription?.cancel();
    await _upower.close();
    return _fwupd.close();
  }

  @override
  Future<void> refreshProperties() => _fwupd.refreshPropertyCache();

  Future<File> _fetchRelease(FwupdRelease release) async {
    final remote = await _fwupd.getRemotes().then((remotes) {
      return remotes.firstWhere((remote) => remote.id == release.remoteId);
    });

    assert(release.locations.isNotEmpty, 'TODO: handle multiple locations');

    late final File file;
    switch (remote.kind) {
      case FwupdRemoteKind.download:
        // TODO:
        // - should the .cab be stored in the cache directory?
        file = await _downloadRelease(release.locations.first);
        break;
      case FwupdRemoteKind.local:
        final cache = p.dirname(remote.filenameCache ?? '');
        file = _fs.file(p.join(cache, release.locations.first));
        break;
      default:
        throw UnimplementedError('Remote kind ${remote.kind} not implemented');
    }
    return file;
  }

  Future<File> _downloadRelease(String url) async {
    final path = p.join(_fs.systemTempDirectory.path, p.basename(url));
    log.debug('download $url to $path');
    try {
      return await _dio.download(
        url,
        path,
        onReceiveProgress: (recvd, total) {
          _setDownloadProgress(100 * recvd ~/ total);
        },
        options:
            Options(headers: {HttpHeaders.userAgentHeader: 'firmware-updater'}),
      ).then((response) => _fs.file(path));
    } finally {
      _setDownloadProgress(null);
    }
  }

  void _setDownloadProgress(int? progress) {
    if (_downloadProgress == progress) return;
    _downloadProgress = progress;
    _propertiesChanged.add(['Percentage']);
  }

  @override
  Future<void> activate(FwupdDevice device) {
    log.debug('activate $device');
    return _fwupd.activate(device.id);
  }

  @override
  Future<void> clearResults(FwupdDevice device) {
    log.debug('clearResults $device');
    return _fwupd.clearResults(device.id);
  }

  @override
  Future<List<FwupdDevice>> getDevices() => _fwupd.getDevices();

  @override
  Future<List<FwupdRelease>> getDowngrades(FwupdDevice device) {
    return _fwupd.getDowngrades(device.id);
  }

  @override
  Future<List<FwupdPlugin>> getPlugins() => _fwupd.getPlugins();

  @override
  Future<List<FwupdRelease>> getReleases(FwupdDevice device) {
    return _fwupd.getReleases(device.id);
  }

  @override
  Future<List<FwupdRemote>> getRemotes() => _fwupd.getRemotes();

  @override
  Future<List<FwupdRelease>> getUpgrades(FwupdDevice device) {
    return _fwupd.getUpgrades(device.id);
  }

  @override
  Future<void> install(
    FwupdDevice device,
    FwupdRelease release, [
    @visibleForTesting
    ResourceHandle Function(RandomAccessFile file)? resourceHandleFromFile,
  ]) async {
    log.debug('install $release');
    log.debug('on $device');
    try {
      final file = await _fetchRelease(release);
      resourceHandleFromFile ??= ResourceHandle.fromFile;
      await _fwupd.install(
        device.id,
        resourceHandleFromFile(file.openSync()),
        flags: {
          if (release.isDowngrade) FwupdInstallFlag.allowOlder,
          if (!release.isDowngrade && !release.isUpgrade)
            FwupdInstallFlag.allowReinstall,
        },
      );
      if (device.flags.contains(FwupdDeviceFlag.needsReboot)) {
        if (await _confirmationListener?.call() == true) await reboot();
      }
    } on Exception catch (e) {
      _errorListener?.call(e);
      if (_errorListener == null) rethrow;
    }
  }

  @override
  bool get onBattery => _upower.onBattery;

  @override
  Future<void> unlock(FwupdDevice device) {
    log.debug('unlock $device');
    return _fwupd.unlock(device.id);
  }

  @override
  Future<void> verify(FwupdDevice device) {
    log.debug('verify $device');
    return _fwupd.verify(device.id);
  }

  @override
  Future<void> verifyUpdate(FwupdDevice device) {
    log.debug('verifyUpdate $device');
    return _fwupd.verifyUpdate(device.id);
  }

  @override
  Future<void> reboot() => _dbus.callMethod(
        destination: 'org.freedesktop.login1',
        path: DBusObjectPath('/org/freedesktop/login1'),
        interface: 'org.freedesktop.login1.Manager',
        name: 'Reboot',
        values: [const DBusBoolean(true)],
        replySignature: DBusSignature(''),
      );
}
