import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api.dart';
import 'asset_screen.dart';
import 'common.dart';

/// Tags from the demo server's seed data. They are the same after every nightly reset.
const _sampleTags = [
  (tag: 'AV-67-0037', name: 'กล้องถ่ายภาพ'),
  (tag: 'AV-67-0034', name: 'โปรเจกเตอร์'),
  (tag: 'COM-65-0010', name: 'จอภาพ'),
];

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.api,
    required this.session,
    required this.onSignOut,
    this.openTag,
    this.onOpened,
  });

  final AssetApi api;
  final Session session;
  final Future<void> Function({bool expired}) onSignOut;

  /// A tag from the link the app was opened with, shown as soon as the user is signed in.
  final String? openTag;
  final VoidCallback? onOpened;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // On the web the camera waits for a tap, so a desktop visitor is not met by a permission prompt.
  late final _camera = MobileScannerController(autoStart: !kIsWeb, formats: const [BarcodeFormat.qrCode]);
  late bool _cameraOn = !kIsWeb;
  final _tagField = TextEditingController();

  /// One asset at a time: the camera keeps reporting the same code while the asset page opens.
  bool _showingAsset = false;

  /// Back from an asset, the camera is usually still pointing at its label. Ignore that code for a moment,
  /// or "scan the next one" would reopen the same asset straight away.
  String? _lastTag;
  DateTime _backAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    final tag = widget.openTag;
    if (tag != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onOpened?.call();
        _open(tag);
      });
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    _tagField.dispose();
    super.dispose();
  }

  Future<void> _open(String tag) async {
    if (_showingAsset) return;
    _showingAsset = true;
    _lastTag = tag;
    if (_cameraOn) await _camera.stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssetScreen(api: widget.api, tag: tag, onSignOut: widget.onSignOut),
      ),
    );
    _showingAsset = false;
    _backAt = DateTime.now();
    if (_cameraOn && mounted) await _camera.start();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    final tag = raw == null ? null : tagFromScan(raw);
    if (tag == null) return;
    if (tag == _lastTag && DateTime.now().difference(_backAt) < const Duration(seconds: 3)) return;
    _open(tag);
  }

  void _openTyped() {
    // Tags are printed in capitals; people type them in lower case.
    final tag = tagFromScan(_tagField.text.toUpperCase());
    if (tag != null) _open(tag);
  }

  Future<void> _turnCameraOn() async {
    setState(() => _cameraOn = true);
    await _camera.start();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('สแกนทรัพย์สิน'),
            Text('${widget.session.name} · ${widget.session.role}', style: muted.copyWith(fontSize: 13)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'ออกจากระบบ',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => widget.onSignOut(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(color: const Color(0xFF0F172A), child: _cameraOn ? _viewfinder() : _cameraOff()),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagField,
                        decoration: const InputDecoration(
                          labelText: 'หรือพิมพ์รหัสทรัพย์สิน',
                          hintText: 'เช่น AV-67-0037',
                        ),
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _openTyped(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _openTyped, child: const Text('ดู')),
                  ],
                ),
                if (isDemo) ...[
                  const SizedBox(height: 32),
                  Text('ไม่มีป้าย QR อยู่ใกล้ๆ? ลองรหัสตัวอย่าง', style: muted.copyWith(fontSize: 13)),
                  const SizedBox(height: 8),
                  const Divider(),
                  for (final sample in _sampleTags) ...[
                    ListTile(
                      title: Text(sample.tag, style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: .3)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(sample.name, style: muted.copyWith(fontSize: 14)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => _open(sample.tag),
                    ),
                    const Divider(),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewfinder() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _camera,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _cameraMessage(
            error.errorCode == MobileScannerErrorCode.permissionDenied
                ? 'ไม่ได้รับอนุญาตให้ใช้กล้อง เปิดสิทธิ์ในการตั้งค่า หรือพิมพ์รหัสด้านล่างแทน'
                : 'เปิดกล้องไม่ได้ พิมพ์รหัสด้านล่างแทน',
          ),
        ),
        const IgnorePointer(
          child: Center(
            child: FractionallySizedBox(widthFactor: .6, heightFactor: .6, child: CustomPaint(painter: _Corners())),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: Text(
            'ส่องคิวอาร์โค้ดบนป้ายทรัพย์สิน',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _cameraOff() {
    return Center(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white38),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        onPressed: _turnCameraOn,
        icon: const Icon(Icons.qr_code_scanner, size: 20),
        label: const Text('เปิดกล้องสแกน'),
      ),
    );
  }

  Widget _cameraMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

/// Four corner marks around the area to aim at, instead of a full frame.
class _Corners extends CustomPainter {
  const _Corners();

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 28.0;
    final pen = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final (w, h) = (size.width, size.height);
    final corners = Path()
      ..moveTo(0, arm)
      ..lineTo(0, 0)
      ..lineTo(arm, 0)
      ..moveTo(w - arm, 0)
      ..lineTo(w, 0)
      ..lineTo(w, arm)
      ..moveTo(w, h - arm)
      ..lineTo(w, h)
      ..lineTo(w - arm, h)
      ..moveTo(arm, h)
      ..lineTo(0, h)
      ..lineTo(0, h - arm);
    canvas.drawPath(corners, pen);
  }

  @override
  bool shouldRepaint(_Corners oldDelegate) => false;
}
