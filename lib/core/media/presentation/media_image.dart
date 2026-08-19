import 'dart:io';

import 'package:flutter/material.dart';

import '../media_service.dart';

/// Displays a stored media reference. Resolves the (relative or legacy
/// absolute) [ref] to a file via the [MediaService] and renders it, showing
/// [placeholder] while resolving and if the file is missing.
///
/// This is the read-side counterpart to [MediaService.capture]: features hold
/// an opaque string ref and never build a [File] themselves, so the store owns
/// how a ref maps to bytes on disk.
class MediaImage extends StatefulWidget {
  const MediaImage({
    required this.service,
    required this.ref,
    this.fit = BoxFit.cover,
    this.placeholder,
    super.key,
  });

  final MediaService service;
  final String? ref;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  State<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<MediaImage> {
  late Future<File?> _resolved;

  @override
  void initState() {
    super.initState();
    _resolved = widget.service.resolve(widget.ref);
  }

  @override
  void didUpdateWidget(MediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref != widget.ref || oldWidget.service != widget.service) {
      _resolved = widget.service.resolve(widget.ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.placeholder ?? const SizedBox.shrink();
    return FutureBuilder<File?>(
      future: _resolved,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null || !file.existsSync()) return placeholder;
        return Image.file(file, fit: widget.fit);
      },
    );
  }
}
