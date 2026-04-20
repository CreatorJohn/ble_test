import 'dart:async';

import 'package:ble_test/advertise_widget.dart';
import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/ble_discoverer.dart';
import 'package:ble_test/discovery_widget.dart';
import 'package:ble_test/log_viewer.dart';
import 'package:ble_test/status_indicator.dart';
import 'package:ble_test/watch_log.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WatchLog.initialize();
  runApp(MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

enum AppMode { advertising, discovery, unknown }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BLEAdvertiser _bleAdvertiser = BLEAdvertiser();
  final BleDiscoverer _bleDiscoverer = BleDiscoverer();
  late final StreamSubscription<bool> _advertisingStatusSubscription;
  late final StreamSubscription<bool> _discoveringStatusSubscription;
  late Stream<List<DiscoveredDevice>> _discoveredStream;
  late List<DiscoveredDevice> _initialDiscovered;
  AppMode _mode = AppMode.unknown;
  bool _advertising = false;
  bool _discovering = false;

  void _updateDiscoveryState([
    Stream<List<DiscoveredDevice>>? stream,
    List<DiscoveredDevice>? initial,
  ]) {
    _discoveredStream = stream ?? _bleDiscoverer.resultsStream;
    _initialDiscovered = initial ?? _bleDiscoverer.prevResults;
  }

  @override
  void initState() {
    super.initState();

    _updateDiscoveryState();

    _advertisingStatusSubscription = _bleAdvertiser.advertisingStatusStream
        .listen(
          (isAdvertising) => setState(() => _advertising = isAdvertising),
        );

    _discoveringStatusSubscription = _bleDiscoverer.isDiscoveringStream.listen(
      (isDiscovering) => setState(() => _discovering = isDiscovering),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('BLE Test'),
        leading: StatusIndicator(
          isActive: switch (_mode) {
            AppMode.advertising => _advertising,
            AppMode.discovery => _discovering,
            AppMode.unknown => null,
          },
          icon: switch (_mode) {
            AppMode.advertising => Icons.broadcast_on_personal,
            AppMode.discovery => Icons.bluetooth_searching,
            AppMode.unknown => Icons.question_mark,
          },
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 8.0),
        actions: [
          if (_mode == AppMode.discovery && !_discovering)
            IconButton(
              onPressed: () => _bleDiscoverer.discover(
                freshCb: (stream, initial) {
                  setState(() => _updateDiscoveryState(stream, initial));
                },
              ),
              icon: const Icon(Icons.refresh),
            )
          else if (_mode == AppMode.discovery)
            IconButton(
              onPressed: () => _bleDiscoverer.stopDiscovering(),
              icon: const Icon(Icons.stop, color: Colors.red),
            ),
          IconButton(
            onPressed: () =>
                showDialog(context: context, builder: (context) => LogViewer()),
            icon: const Icon(Icons.list),
            tooltip: 'View logs',
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 16.0,
          children: [
            if (_mode == AppMode.advertising)
              Text(
                'BLE Advertising is ${_advertising ? 'ON' : 'OFF'}',
                style: const TextStyle(fontSize: 18),
              )
            else if (_mode == AppMode.discovery)
              Text(
                'BLE Discovery is ${_discovering ? 'ON' : 'OFF'}',
                style: const TextStyle(fontSize: 18),
              )
            else
              const Text(
                'Select a mode to start',
                style: TextStyle(fontSize: 18),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12.0,
              children: [
                ElevatedButton(
                  onPressed: () => _handleAppMode(AppMode.advertising),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text('BLE Advertiser'),
                ),
                ElevatedButton(
                  onPressed: () => _handleAppMode(AppMode.discovery),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text('BLE Discovery'),
                ),
              ],
            ),
            if (_mode == AppMode.advertising)
              AdvertiseWidget(
                advertising: _advertising,
                onStart: (localName) async {
                  await _bleAdvertiser.startAdvertising(localName: localName);
                  setState(() => _advertising = true);
                },
                onStop: () async {
                  await _bleAdvertiser.stopAdvertising();
                  setState(() => _advertising = false);
                },
              )
            else if (_mode == AppMode.discovery)
              DiscoveryWidget(
                resultsStream: _discoveredStream,
                initialResults: _initialDiscovered,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAppMode(AppMode mode) async {
    if (mode == _mode) {
      setState(() => _mode = AppMode.unknown);
      return;
    }

    setState(() => _mode = mode);

    if (mode == AppMode.advertising) {
      await _bleAdvertiser.initialize();
    } else if (mode == AppMode.discovery) {
      await _bleDiscoverer.initialize();
    }
  }

  @override
  void dispose() {
    _advertisingStatusSubscription.cancel();
    _discoveringStatusSubscription.cancel();
    super.dispose();
  }
}
