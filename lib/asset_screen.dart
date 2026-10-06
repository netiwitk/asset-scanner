import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';

/// One scanned asset: what it is, where it is, who has it, and the buttons the server allows.
class AssetScreen extends StatefulWidget {
  const AssetScreen({super.key, required this.api, required this.tag, required this.onSignOut});

  final AssetApi api;
  final String tag;
  final Future<void> Function({bool expired}) onSignOut;

  @override
  State<AssetScreen> createState() => _AssetScreenState();
}

class _AssetScreenState extends State<AssetScreen> {
  ScannedAsset? _asset;
  ApiError? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load(() => widget.api.fetch(widget.tag));
  }

  Future<void> _load(Future<ScannedAsset> Function() request, {String? done}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final asset = await request();
      if (!mounted) return;
      setState(() => _asset = asset);
      if (done != null) _say(done);
    } on SignedOut catch (error) {
      _say(error.message);
      await widget.onSignOut(expired: true);
    } on ApiError catch (error) {
      if (!mounted) return;
      // Before the first load there is nothing to show but the error; after it, keep the page and say why.
      if (_asset == null) {
        setState(() => _error = error);
      } else {
        _say(error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _press(ScannedAsset asset, AssetAction action) async {
    final body = switch (action) {
      AssetAction.handOver => await _confirmHandOver(asset),
      AssetAction.receiveReturn => await _askReturnCondition(),
    };
    if (body == null) return;
    await _load(() => widget.api.perform(asset.tag, action, body), done: '${action.label}แล้ว');
  }

  Future<Map<String, Object?>?> _confirmHandOver(ScannedAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ส่งมอบให้ ${asset.loan?.borrower}?'),
        content: Text('${asset.name} จะเปลี่ยนเป็น "ถูกยืม" นับจากตอนนี้'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ส่งมอบ')),
        ],
      ),
    );
    return confirmed == true ? const {} : null;
  }

  Future<Map<String, Object?>?> _askReturnCondition() {
    return showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReturnSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    return Scaffold(
      appBar: AppBar(
        bottom: _busy && asset != null
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator())
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: asset != null
                ? _details(asset)
                : _error != null
                ? _failed(_error!)
                : const Padding(padding: EdgeInsets.all(24), child: SlowHint()),
          ),
        ),
      ),
    );
  }

  Widget _details(ScannedAsset asset) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final loan = asset.loan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text(asset.tag, style: muted.copyWith(fontSize: 13, letterSpacing: .5)),
        const SizedBox(height: 4),
        Text(asset.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(spacing: 20, runSpacing: 8, children: [StatusDot(asset.condition), StatusDot(asset.availability)]),
        const SizedBox(height: 28),
        const Divider(),
        _row('หมวดหมู่', asset.category),
        _row('หน่วยงาน', asset.department),
        if (asset.location != null) _row('ที่ตั้ง', asset.location!),
        if (asset.custodian != null) _row('ผู้ดูแล', asset.custodian!),
        if (asset.bookValue != null) _row('มูลค่าตามบัญชี', baht(asset.bookValue!)),
        if (loan != null) ...[
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Text('การยืม', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              StatusDot(loan.status),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          _row('ผู้ยืม', loan.borrower),
          if (loan.dueOn != null)
            _row(
              'กำหนดคืน',
              loan.dueOn!,
              trailing: loan.isOverdue ? const StatusDot(Labelled('overdue', 'เกินกำหนด', 'danger')) : null,
            ),
          if (loan.purpose != null) _row('ใช้ทำอะไร', loan.purpose!),
        ],
        const SizedBox(height: 32),
        for (final action in asset.actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilledButton(onPressed: _busy ? null : () => _press(asset, action), child: Text(action.label)),
          ),
        if (asset.actions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'ตอนนี้ไม่มีรายการที่คุณทำกับชิ้นนี้ได้',
              style: muted.copyWith(fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('สแกนชิ้นต่อไป')),
      ],
    );
  }

  Widget _failed(ApiError error) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ListView(
      padding: const EdgeInsets.all(24),
      shrinkWrap: true,
      children: [
        Text(widget.tag, textAlign: TextAlign.center, style: muted.copyWith(fontSize: 13, letterSpacing: .5)),
        const SizedBox(height: 8),
        Text(error.message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 28),
        if (error is Unreachable) ...[
          FilledButton(onPressed: () => _load(() => widget.api.fetch(widget.tag)), child: const Text('ลองอีกครั้ง')),
          const SizedBox(height: 10),
        ],
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('กลับไปสแกน')),
      ],
    );
  }

  /// One fact per line, hairline below, label on the left.
  Widget _row(String label, String value, {Widget? trailing}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 116,
                child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              Expanded(child: Text(value)),
              ?trailing,
            ],
          ),
        ),
        const Divider(),
      ],
    );
  }
}

/// Asks how the asset came back. Returns the request body, or null if dismissed.
class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet();

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  var _condition = 'usable';
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('สภาพตอนรับคืน', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'usable', label: Text('ใช้งานได้')),
              ButtonSegment(value: 'damaged', label: Text('ชำรุด')),
            ],
            selected: {_condition},
            onSelectionChanged: (picked) => setState(() => _condition = picked.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'บันทึก (ถ้ามี)', hintText: 'เช่น จอมีรอยขีดข่วน'),
            maxLength: 1000,
          ),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: () {
              final note = _note.text.trim();
              Navigator.pop(context, {'condition': _condition, 'note': note.isEmpty ? null : note});
            },
            child: const Text('ยืนยันรับคืน'),
          ),
        ],
      ),
    );
  }
}
