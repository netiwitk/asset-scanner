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
    if (_cameraOn) await _camera.stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssetScreen(api: widget.api, tag: tag, onSignOut: widget.onSignOut),
      ),
    );
    _showingAsset = false;
    if (_cameraOn && mounted) await _camera.start();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    final tag = raw == null ? null : tagFromScan(raw);
    if (tag != null) _open(tag);
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('สแกนทรัพย์สิน'),
            Text(
              '${widget.session.name} · ${widget.session.role}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'ออกจากระบบ', icon: const Icon(Icons.logout), onPressed: () => widget.onSignOut()),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ColoredBox(color: const Color(0xFF0F172A), child: _cameraOn ? _viewfinder() : _cameraOff()),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    SizedBox(
                      height: 56,
                      child: FilledButton(onPressed: _openTyped, child: const Text('ดู')),
                    ),
                  ],
                ),
                if (isDemo) ...[
                  const SizedBox(height: 20),
                  Text('ไม่มีป้าย QR อยู่ใกล้ๆ? ลองรหัสตัวอย่าง', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final sample in _sampleTags)
                        ActionChip(label: Text('${sample.tag} ${sample.name}'), onPressed: () => _open(sample.tag)),
                    ],
                  ),
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
            Icons.no_photography_outlined,
            error.errorCode == MobileScannerErrorCode.permissionDenied
                ? 'ไม่ได้รับอนุญาตให้ใช้กล้อง เปิดสิทธิ์ในการตั้งค่า หรือพิมพ์รหัสด้านล่างแทน'
                : 'เปิดกล้องไม่ได้ พิมพ์รหัสด้านล่างแทน',
          ),
        ),
        IgnorePointer(
          child: Center(
            child: FractionallySizedBox(
              widthFactor: .62,
              heightFactor: .62,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: .9), width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: Text(
            'ส่องคิวอาร์โค้ดบนป้ายทรัพย์สิน',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _cameraOff() {
    return Center(
      child: FilledButton.icon(
        onPressed: _turnCameraOn,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('เปิดกล้องสแกน'),
      ),
    );
  }

  Widget _cameraMessage(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
