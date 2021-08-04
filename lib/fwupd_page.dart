import 'package:flutter/material.dart';
import 'package:fwupd/fwupd.dart';
import 'package:provider/provider.dart';

import 'fwupd_models.dart';
import 'fwupd_widgets.dart';

class FwupdPage extends StatefulWidget {
  const FwupdPage({Key? key}) : super(key: key);

  static Widget create(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FwupdModel(context.read<FwupdClient>()),
      child: const FwupdPage(),
    );
  }

  @override
  State<FwupdPage> createState() => _FwupdPageState();
}

class _FwupdPageState extends State<FwupdPage> {
  @override
  void initState() {
    super.initState();
    context.read<FwupdModel>().init();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<FwupdModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firmware Updater'),
        actions: <Widget>[
          Checkbox(
            splashRadius: 24,
            value: model.showAllDevices,
            onChanged: (value) => model.showAllDevices = value,
          ),
          const SizedBox(width: 16),
          IconButton(
            splashRadius: 24,
            icon: const Icon(Icons.refresh),
            onPressed: model.refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 100, vertical: 20),
        children: model.devices.map((device) {
          return Provider.value(
            value: device,
            child: DeviceWidget.create(context, device: device),
          );
        }).toList(),
      ),
    );
  }
}
