import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';
import 'package:web/web.dart' as web;

import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';

/// Derives the guest portal URL from the current window origin.
/// Flutter web uses hash routing so the path is `/#/guest`.
String guestPortalUrl() {
  final base = Uri.base;
  final port = (base.port == 80 || base.port == 443) ? '' : ':${base.port}';
  return '${base.scheme}://${base.host}$port/#/guest';
}

/// Shows the guest QR bottom sheet with a preview + PDF download button.
/// [label] appears as the subtitle (location or operator name) on the sheet.
void showQrSheet(BuildContext context, String label) {
  final url = guestPortalUrl();
  // Single normalization point for every caller (driver displayName, facility
  // owner / location names): empty or whitespace-only falls back so no blank
  // label or `guest-qr-.pdf` filename can leak through downstream.
  final safe = label.trim().isEmpty ? 'Guest Portal' : label.trim();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _QrSheetContent(url: url, label: safe),
  );
}

/// Builds a 4×8 A4 PDF of identical QR codes, each labelled with [label].
Future<Uint8List> buildQrPdfBytes(String url, String label) async {
  final qrImg = QrImage(QrCode.fromData(
    data: url,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  ));
  final moduleCount = qrImg.moduleCount;

  const cols = 4;
  const rows = 8;
  const pageMargin = 20.0;
  const labelHeight = 14.0;

  final pageW = PdfPageFormat.a4.width - pageMargin * 2;
  final pageH = PdfPageFormat.a4.height - pageMargin * 2;
  final cellW = pageW / cols;
  final cellH = pageH / rows;
  final qrSize = min(cellW, cellH - labelHeight) * 0.80;

  void paintQr(PdfGraphics canvas, PdfPoint size) {
    final mod = size.x / moduleCount;
    canvas.setFillColor(PdfColors.black);
    for (int row = 0; row < moduleCount; row++) {
      for (int col = 0; col < moduleCount; col++) {
        if (qrImg.isDark(row, col)) {
          final x = col * mod;
          final y = size.y - (row + 1) * mod;
          canvas
            ..drawRect(x, y, mod, mod)
            ..fillPath();
        }
      }
    }
  }

  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(pageMargin),
    build: (_) => pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
      children: List.generate(
        rows,
        (r) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: List.generate(
            cols,
            (_) => pw.SizedBox(
              width: cellW,
              height: cellH,
              child: pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.CustomPaint(
                      size: PdfPoint(qrSize, qrSize),
                      painter: paintQr,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      label.length > 25 ? '${label.substring(0, 24)}…' : label,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));

  return doc.save();
}

/// Triggers a browser download of the QR PDF.
Future<void> downloadQrPdf(String url, String label) async {
  final bytes = await buildQrPdfBytes(url, label);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final dlUrl = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = dlUrl;
  // Sanitise label for use in filename (fall back if it strips to nothing).
  final stripped = label.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '-').toLowerCase();
  final safeName = stripped.isEmpty ? 'location' : stripped;
  anchor.download = 'guest-qr-$safeName.pdf';
  anchor.click();
  web.URL.revokeObjectURL(dlUrl);
}

// ---------------------------------------------------------------------------
// Bottom sheet widget
// ---------------------------------------------------------------------------

class _QrSheetContent extends StatelessWidget {
  const _QrSheetContent({required this.url, required this.label});
  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VColors.surface900,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(VRadius.xl)),
        border: Border(top: BorderSide(color: VColors.surface700)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(VSpace.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: VSpace.x5),
                decoration: BoxDecoration(
                  color: VColors.surface600,
                  borderRadius: BorderRadius.circular(VRadius.full),
                ),
              ),
              Text('Guest Portal QR',
                  style: VType.title.copyWith(color: VColors.contentStrong)),
              const SizedBox(height: 4),
              Text(label,
                  style: VType.caption.copyWith(color: VColors.brand400)),
              const SizedBox(height: 4),
              Text('Show this to your guest — they scan to track their car.',
                  style: VType.caption, textAlign: TextAlign.center),
              const SizedBox(height: VSpace.x5),
              Container(
                padding: const EdgeInsets.all(VSpace.x3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(VRadius.md),
                ),
                child: _QrWidget(data: url, size: 220),
              ),
              const SizedBox(height: VSpace.x4),
              Text(url, style: VType.caption, textAlign: TextAlign.center),
              const SizedBox(height: VSpace.x2),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await downloadQrPdf(url, label);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Could not generate the PDF.')),
                      );
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: VColors.contentStrong,
                  side: BorderSide(color: VColors.surface600),
                  padding: const EdgeInsets.symmetric(
                      horizontal: VSpace.x5, vertical: VSpace.x3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(VRadius.md)),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('Download PDF (4 × 8 codes)',
                    style: VType.label),
              ),
              const SizedBox(height: VSpace.x2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the QR code using CustomPainter so we don't depend on qr_flutter
/// widgets in this utility file (qr_flutter is already in operator_floor_screen
/// but we import the lower-level `qr` package here directly).
class _QrWidget extends StatelessWidget {
  const _QrWidget({required this.data, required this.size});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final qr = QrCode.fromData(
        data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
    final img = QrImage(qr);
    return CustomPaint(
      size: Size(size, size),
      painter: _QrPainter(img),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.img);
  final QrImage img;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final mod = size.width / img.moduleCount;
    for (int r = 0; r < img.moduleCount; r++) {
      for (int c = 0; c < img.moduleCount; c++) {
        if (img.isDark(r, c)) {
          canvas.drawRect(
            Rect.fromLTWH(c * mod, r * mod, mod, mod),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => false;
}
