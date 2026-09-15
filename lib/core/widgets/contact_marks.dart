import 'package:flutter/material.dart';

/// Brand marks for the "About" page's contact rows — WhatsApp and Gmail —
/// rendered from the official transparent PNG logos in `assets/brands/`, the
/// same way the Spotify and Google marks elsewhere are bundled images.
///
/// Both logos keep their own aspect ratio inside a square [size] box
/// (WhatsApp's bubble is ~square, Gmail's envelope is wider than tall), so the
/// marks are never stretched. `filterQuality: medium` keeps the down-scaled
/// edges clean at row size.

/// WhatsApp's official green speech-bubble mark.
class WhatsAppMark extends StatelessWidget {
  const WhatsAppMark({this.size = 24, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/brands/whatsapp.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// Gmail's official four-colour "M" mark.
class GmailMark extends StatelessWidget {
  const GmailMark({this.size = 24, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/brands/gmail.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
