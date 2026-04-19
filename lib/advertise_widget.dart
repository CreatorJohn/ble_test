import 'package:flutter/material.dart';

class AdvertiseWidget extends StatefulWidget {
  const AdvertiseWidget({
    super.key,
    required this.advertising,
    required this.onStart,
    required this.onStop,
  });

  final bool advertising;
  final void Function(String localName) onStart;
  final VoidCallback onStop;

  @override
  State<AdvertiseWidget> createState() => _AdvertiseWidgetState();
}

class _AdvertiseWidgetState extends State<AdvertiseWidget> {
  final TextEditingController _controller = TextEditingController.fromValue(
    TextEditingValue(text: 'Random User'),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 16.0,
      children: [
        TextField(
          enabled: !widget.advertising,
          decoration: const InputDecoration(
            labelText: 'Local Name',
            border: OutlineInputBorder(),
          ),
          maxLength: 11,
          controller: _controller,
        ),
        if (!widget.advertising)
          ElevatedButton(
            onPressed: () => widget.onStart(_controller.text.trim()),
            child: const Text('Advertise'),
          )
        else
          ElevatedButton(onPressed: widget.onStop, child: const Text('Stop')),
      ],
    );
  }
}
