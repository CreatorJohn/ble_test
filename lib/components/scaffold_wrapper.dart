import 'package:ble_test/extensions.dart';
import 'package:ble_test/log_viewer.dart';
import 'package:flutter/material.dart';

class ScaffoldWrapper extends StatelessWidget {
  const ScaffoldWrapper({
    super.key,
    this.body,
    this.actions = const [],
    this.padding,
    this.screen,
    this.withLog = false,
    this.centered = false,
  });

  final Widget? body;
  final List<Widget> actions;
  final EdgeInsets? padding;
  final String? screen;
  final bool withLog;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final String title;

    if (screen == null || screen == "/") {
      title = "BLE Test App";
    } else if (!screen!.startsWith("/")) {
      throw Exception("Invalid screen route!");
    } else {
      title = screen!.substring(1).title();
    }

    Widget? widget = body;

    if (centered) widget = Center(child: widget);
    if (padding != null) widget = Padding(padding: padding!, child: widget);

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
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
        body: widget,
      ),
    );
  }
}
