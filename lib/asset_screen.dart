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
        title: const Text('ข้อมูลทรัพย์สิน'),
        bottom: _busy && asset != null
            ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator())
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
      padding: const EdgeInsets.all(16),
      children: [
        Text(asset.tag, style: muted.copyWith(letterSpacing: .5)),
        const SizedBox(height: 4),
        Text(asset.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [StatusChip(asset.condition), StatusChip(asset.availability)]),
        const SizedBox(height: 16),
        _section([
          _row('หมวดหมู่', asset.category),
          _row('หน่วยงาน', asset.department),
          if (asset.location != null) _row('ที่ตั้ง', asset.location!),
          if (asset.custodian != null) _row('ผู้ดูแล', asset.custodian!),
          if (asset.bookValue != null) _row('มูลค่าตามบัญชี', baht(asset.bookValue!)),
        ]),
        if (loan != null) ...[
          const SizedBox(height: 16),
          _section([
            Row(
              children: [
                Expanded(child: Text('การยืม', style: theme.textTheme.titleMedium)),
                StatusChip(loan.status),
              ],
            ),
            const SizedBox(height: 4),
            _row('ผู้ยืม', loan.borrower),
            if (loan.dueOn != null)
              _row(
                'กำหนดคืน',
                loan.dueOn!,
                trailing: loan.isOverdue ? const StatusChip(Labelled('overdue', 'เกินกำหนด', 'danger')) : null,
              ),
            if (loan.purpose != null) _row('ใช้ทำอะไร', loan.purpose!),
          ]),
        ],
        const SizedBox(height: 20),
        for (final action in asset.actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : () => _press(asset, action),
              icon: Icon(action == AssetAction.handOver ? Icons.outbox_outlined : Icons.move_to_inbox_outlined),
              label: Text(action.label),
            ),
          ),
        if (asset.actions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('ตอนนี้ไม่มีรายการที่คุณทำกับชิ้นนี้ได้', style: muted, textAlign: TextAlign.center),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('สแกนชิ้นต่อไป'),
        ),
      ],
    );
  }

  Widget _failed(ApiError error) {
    return ListView(
      padding: const EdgeInsets.all(24),
      shrinkWrap: true,
      children: [
        Icon(
          error is NotFound ? Icons.search_off : Icons.cloud_off,
          size: 48,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 12),
        Text(widget.tag, textAlign: TextAlign.center, style: const TextStyle(letterSpacing: .5)),
        const SizedBox(height: 4),
        Text(error.message, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        if (error is Unreachable)
          FilledButton(onPressed: () => _load(() => widget.api.fetch(widget.tag)), child: const Text('ลองอีกครั้ง')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('กลับไปสแกน')),
      ],
    );
  }

  Widget _section(List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _row(String label, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
          ?trailing,
        ],
      ),
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
          Text('สภาพตอนรับคืน', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'usable', label: Text('ใช้งานได้'), icon: Icon(Icons.check_circle_outline)),
              ButtonSegment(value: 'damaged', label: Text('ชำรุด'), icon: Icon(Icons.report_problem_outlined)),
            ],
            selected: {_condition},
            onSelectionChanged: (picked) => setState(() => _condition = picked.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'บันทึก (ถ้ามี)', hintText: 'เช่น จอมีรอยขีดข่วน'),
            maxLength: 1000,
          ),
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
