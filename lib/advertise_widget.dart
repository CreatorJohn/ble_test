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
    return LayoutBuilder(
      builder: (context, constrains) {
        return SizedBox(
          width: constrains.maxWidth * 0.9,
          child: Row(
            spacing: 12.0,
            children: [
              Expanded(
                child: TextField(
                  enabled: !widget.advertising,
                  decoration: InputDecoration(
                    labelText: 'Local Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  maxLength: 11,
                  controller: _controller,
                ),
              ),
              if (!widget.advertising)
                ElevatedButton(
                  onPressed: () => widget.onStart(_controller.text.trim()),
                  child: const Text('Advertise'),
                )
              else
                ElevatedButton(
                  onPressed: widget.onStop,
                  child: const Text('Stop'),
                ),
            ],
          ),
        );
      },
    );
  }
}
