import 'package:ble_test/extensions.dart';
import 'package:ble_test/log_viewer.dart';
import 'package:flutter/material.dart';

class ScaffoldWrapper extends StatelessWidget {
  const ScaffoldWrapper({
    super.key,
    this.body,
    this.actions = const [],
    this.subPage,
    this.withLog = false,
  });

  final Widget? body;
  final List<Widget> actions;
  final String? subPage;
  final bool withLog;

  @override
  Widget build(BuildContext context) {
    final extra = subPage != null ? " - ${subPage!.title()}" : "";

    return SafeArea(
      maintainBottomViewPadding: true,
      minimum: const EdgeInsets.all(8.0),
      child: Scaffold(
        appBar: AppBar(
          title: Text("BLE Test App$extra"),
          centerTitle: true,
          actions: [
            ...actions,
            if (withLog)
              IconButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => LogViewer(),
                ),
                icon: const Icon(Icons.list),
              ),
          ],
        ),
        body: body,
      ),
    );
  }
}
