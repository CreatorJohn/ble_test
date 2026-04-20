import 'package:flutter/material.dart';

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    this.isActive,
    this.label,
    this.icon = Icons.circle,
    this.padding = const EdgeInsetsGeometry.all(0.0),
  });

  final bool? isActive;
  final String? label;
  final EdgeInsetsGeometry padding;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        spacing: 8.0,
        children: [
          if (label != null) Text(label!),
          switch (isActive) {
            true => Icon(icon, color: Colors.green),
            false => Icon(icon, color: Colors.red),
            null => Icon(icon, color: Colors.grey),
          },
        ],
      ),
    );
  }
}
