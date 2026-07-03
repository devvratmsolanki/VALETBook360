import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../models/lifecycle_status.dart';
import '../models/transaction.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_status_rail.dart';

/// Public guest portal — no auth required.
/// State machine: lookup → found (poll) → done.
class GuestPortalScreen extends StatefulWidget {
  const GuestPortalScreen({super.key});

  @override
  State<GuestPortalScreen> createState() => _GuestPortalScreenState();
}

class _GuestPortalScreenState extends State<GuestPortalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _platCtrl = TextEditingController();
  final _last4Ctrl = TextEditingController();

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.coreBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Transaction? _tx;
  String? _error;
  bool _busy = false;
  bool _requested = false;
  Timer? _poll;
  int _pollFailures = 0;
  bool _pollStale = false;

  @override
  void dispose() {
    _poll?.cancel();
    _platCtrl.dispose();
    _last4Ctrl.dispose();
    _dio.close();
    super.dispose();
  }

  String get _normalizedPhone => _last4Ctrl.text.replaceAll(RegExp(r'[\s\-\+]'), '');

  Future<void> _lookup() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _busy = true; _error = null; });
    try {
      final res = await _dio.post(ApiConfig.guestLookupPath, data: {
        'plate': _platCtrl.text.trim().toUpperCase(),
        'last4': _normalizedPhone,
      });
      if (!mounted) return;
      final tx = Transaction.fromJson(res.data as Map<String, dynamic>);
      setState(() { _tx = tx; _busy = false; _pollFailures = 0; _pollStale = false; });
      _startPoll();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.response?.data?['userMessage']
            ?? e.response?.data?['detail']
            ?? 'No active booking found. Check your plate and last 4 digits.';
        _busy = false;
      });
    }
  }

  Future<void> _requestCar() async {
    setState(() { _busy = true; _error = null; });
    try {
      final res = await _dio.post(ApiConfig.guestRequestPath, data: {
        'plate': _platCtrl.text.trim().toUpperCase(),
        'last4': _normalizedPhone,
      });
      if (!mounted) return;
      setState(() {
        _tx = Transaction.fromJson(res.data as Map<String, dynamic>);
        _requested = true;
        _busy = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.response?.data?['userMessage'] ?? 'Could not send request. Try again.';
        _busy = false;
      });
    }
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _pollStatus());
  }

  Future<void> _pollStatus() async {
    try {
      final res = await _dio.post(ApiConfig.guestStatusPath, data: {
        'plate': _platCtrl.text.trim().toUpperCase(),
        'last4': _normalizedPhone,
      });
      final tx = Transaction.fromJson(res.data as Map<String, dynamic>);
      if (!mounted) return;
      setState(() { _tx = tx; _pollFailures = 0; _pollStale = false; });
      if (tx.status == LifecycleStatus.delivered || tx.status == LifecycleStatus.cancelled) {
        _poll?.cancel();
      }
    } catch (_) {
      // Silent poll failures — show a staleness hint after 3 consecutive misses.
      if (!mounted) return;
      _pollFailures++;
      if (_pollFailures >= 3 && !_pollStale) {
        setState(() => _pollStale = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VColors.surface950,
      body: SafeArea(
        child: _tx == null ? _buildLookup() : _buildStatus(),
      ),
    );
  }

  Widget _buildLookup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(VSpace.x6),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: VSpace.x8),
            // Logo / brand row.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.directions_car_rounded, color: VColors.brand400, size: 32),
                const SizedBox(width: VSpace.x2),
                Text('Vālet', style: VType.title.copyWith(color: VColors.brand400, fontSize: 24)),
              ],
            ),
            const SizedBox(height: VSpace.x3),
            Text(
              'Track your car',
              style: VType.titleLg.copyWith(color: VColors.contentStrong),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VSpace.x2),
            Text(
              'Enter the details given at check-in to see your car\'s status.',
              style: VType.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VSpace.x8),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(VSpace.x3),
                decoration: BoxDecoration(
                  color: VColors.dangerTint,
                  borderRadius: BorderRadius.circular(VRadius.md),
                ),
                child: Text(_error!, style: VType.body.copyWith(color: VColors.alertDanger)),
              ),
              const SizedBox(height: VSpace.x4),
            ],
            _label('License plate'),
            const SizedBox(height: VSpace.x2),
            TextFormField(
              controller: _platCtrl,
              textCapitalization: TextCapitalization.characters,
              style: VType.bodyLg.copyWith(color: VColors.contentStrong),
              decoration: const InputDecoration(hintText: 'MH12AB1234'),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Required';
                if (!RegExp(r'^[A-Za-z0-9]{2,15}$').hasMatch(s)) return 'Letters and numbers only';
                return null;
              },
            ),
            const SizedBox(height: VSpace.x4),
            _label('Last 4 digits of your phone'),
            const SizedBox(height: VSpace.x2),
            TextFormField(
              controller: _last4Ctrl,
              keyboardType: TextInputType.phone,
              style: VType.bodyLg.copyWith(color: VColors.contentStrong),
              decoration: const InputDecoration(hintText: '9876 or full number'),
              validator: (v) {
                final s = (v ?? '').replaceAll(RegExp(r'[\s\-\+]'), '');
                if (s.isEmpty) return 'Required';
                if (!RegExp(r'^\d{4,15}$').hasMatch(s)) return 'Enter last 4 digits or full phone number';
                return null;
              },
            ),
            const SizedBox(height: VSpace.x6),
            FilledButton.icon(
              onPressed: _busy ? null : _lookup,
              style: FilledButton.styleFrom(
                backgroundColor: VColors.brand500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: VSpace.x4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VRadius.md)),
              ),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search_rounded),
              label: Text(_busy ? 'Looking up...' : 'Find my car', style: VType.label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus() {
    final tx = _tx!;
    final status = tx.status;
    final isDone = status == LifecycleStatus.delivered;
    final isCancelled = status == LifecycleStatus.cancelled;
    final canRequest = !_requested &&
        (status == LifecycleStatus.parked || status == LifecycleStatus.keyIn);
    final inProgress = status == LifecycleStatus.requested ||
        status == LifecycleStatus.driverAssigned ||
        status == LifecycleStatus.enRoute ||
        status == LifecycleStatus.arrived;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(VSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: VSpace.x4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.directions_car_rounded, color: VColors.brand400, size: 28),
              const SizedBox(width: VSpace.x2),
              Text('Vālet', style: VType.title.copyWith(color: VColors.brand400, fontSize: 20)),
            ],
          ),
          const SizedBox(height: VSpace.x5),

          // Car info card.
          Container(
            padding: const EdgeInsets.all(VSpace.x4),
            decoration: BoxDecoration(
              color: VColors.surface800,
              borderRadius: BorderRadius.circular(VRadius.lg),
              border: Border.all(color: VColors.surface600),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tx.carPlate,
                        style: VType.title.copyWith(color: VColors.contentStrong, fontSize: 22),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: VSpace.x2, vertical: 3),
                      decoration: BoxDecoration(
                        color: status.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(VRadius.sm),
                      ),
                      child: Text(status.label, style: VType.caption.copyWith(color: status.color)),
                    ),
                  ],
                ),
                if (tx.carMake != null || tx.carModel != null || tx.carColor != null) ...[
                  const SizedBox(height: VSpace.x1),
                  Text(
                    [tx.carColor, tx.carMake, tx.carModel].where((v) => v != null && v.isNotEmpty).join(' '),
                    style: VType.body,
                  ),
                ],
                const SizedBox(height: VSpace.x4),
                VStatusRail(status: status, labeled: true),
              ],
            ),
          ),
          const SizedBox(height: VSpace.x5),

          // Main action / message.
          if (isDone) ...[
            _successBanner(
              icon: Icons.check_circle_rounded,
              title: 'Car delivered!',
              subtitle: 'Your car has been brought to you. Thank you for using Vālet.',
            ),
            const SizedBox(height: VSpace.x4),
            OutlinedButton.icon(
              onPressed: () { _poll?.cancel(); _poll = null; setState(() { _tx = null; _error = null; _requested = false; _platCtrl.clear(); _last4Ctrl.clear(); }); },
              style: OutlinedButton.styleFrom(
                foregroundColor: VColors.contentMuted,
                side: BorderSide(color: VColors.surface600),
                padding: const EdgeInsets.symmetric(vertical: VSpace.x3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VRadius.md)),
              ),
              icon: const Icon(Icons.search_rounded, size: 18),
              label: Text('Look up another car', style: VType.caption),
            ),
          ] else if (isCancelled) ...[
            _successBanner(
              icon: Icons.cancel_rounded,
              title: 'Booking cancelled',
              subtitle: 'Please contact the valet desk for assistance.',
              isError: true,
            ),
            const SizedBox(height: VSpace.x4),
            OutlinedButton.icon(
              onPressed: () { _poll?.cancel(); _poll = null; setState(() { _tx = null; _error = null; _requested = false; _platCtrl.clear(); _last4Ctrl.clear(); }); },
              style: OutlinedButton.styleFrom(
                foregroundColor: VColors.contentMuted,
                side: BorderSide(color: VColors.surface600),
                padding: const EdgeInsets.symmetric(vertical: VSpace.x3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VRadius.md)),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text('Go back', style: VType.caption),
            ),
          ] else if (inProgress) ...[
            Container(
              padding: const EdgeInsets.all(VSpace.x4),
              decoration: BoxDecoration(
                color: VColors.brand900,
                borderRadius: BorderRadius.circular(VRadius.md),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VColors.brand400,
                    ),
                  ),
                  const SizedBox(width: VSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_statusMessage(status), style: VType.label.copyWith(color: VColors.brand300)),
                        Text('This page updates automatically.', style: VType.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (canRequest) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _requestCar,
              style: FilledButton.styleFrom(
                backgroundColor: VColors.brand500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: VSpace.x4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VRadius.md)),
              ),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.directions_car_rounded),
              label: Text(_busy ? 'Sending request...' : 'Request my car back', style: VType.label),
            ),
            if (_error != null) ...[
              const SizedBox(height: VSpace.x3),
              Text(_error!, style: VType.caption.copyWith(color: VColors.alertDanger)),
            ],
          ],

          // Refresh nudge — upgrade to a warning banner when poll is stale.
          if (!isDone && !isCancelled) ...[
            const SizedBox(height: VSpace.x5),
            if (_pollStale)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: VSpace.x3, vertical: VSpace.x2),
                decoration: BoxDecoration(
                  color: VColors.dangerTint,
                  borderRadius: BorderRadius.circular(VRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 14, color: VColors.alertDanger),
                    const SizedBox(width: VSpace.x2),
                    Expanded(child: Text('Status may be outdated. Tap refresh.', style: VType.caption.copyWith(color: VColors.alertDanger))),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: _pollStatus,
              style: TextButton.styleFrom(foregroundColor: VColors.contentMuted),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text('Refresh now', style: VType.caption),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text, style: VType.caption);

  Widget _successBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    bool isError = false,
  }) {
    final color = isError ? VColors.alertDanger : VColors.statusDone;
    return Container(
      padding: const EdgeInsets.all(VSpace.x4),
      decoration: BoxDecoration(
        color: isError ? VColors.dangerTint : VColors.successTint,
        borderRadius: BorderRadius.circular(VRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: VSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: VType.label.copyWith(color: color)),
                const SizedBox(height: VSpace.x1),
                Text(subtitle, style: VType.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusMessage(LifecycleStatus status) => switch (status) {
    LifecycleStatus.requested => 'Request received — a driver is being assigned.',
    LifecycleStatus.driverAssigned => 'Driver assigned — on the way to your car.',
    LifecycleStatus.enRoute => 'Driver is on the way with your car.',
    LifecycleStatus.arrived => 'Your car has arrived! Head to the pickup zone.',
    _ => 'Processing your request…',
  };
}
