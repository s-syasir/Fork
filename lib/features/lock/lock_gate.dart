import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../../data/app_lock.dart';

/// Gates [child] behind a biometric/PIN check when app lock is enabled -
/// on cold start, and again every time the app returns from background
/// (not just first launch), so backgrounding the app is a real lock, not
/// a one-time login.
class LockGate extends ConsumerStatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _unlocked = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeUnlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (ref.read(appLockEnabledProvider) && mounted) setState(() => _unlocked = false);
    } else if (state == AppLifecycleState.resumed) {
      _maybeUnlock();
    }
  }

  Future<void> _maybeUnlock() async {
    if (!mounted || !ref.read(appLockEnabledProvider) || _unlocked) return;
    await _tryUnlock();
  }

  Future<void> _tryUnlock() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        // Nothing to authenticate against on this device - don't lock the
        // user out of an app they can't unlock.
        if (mounted) setState(() => _unlocked = true);
        return;
      }
      final result = await _auth.authenticate(
        localizedReason: 'Unlock to continue',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (mounted) setState(() => _unlocked = result);
    } catch (_) {
      // Leave locked - user can retry via the button.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(appLockEnabledProvider);
    if (!enabled || _unlocked) return widget.child;

    // Sits inside the app's own MaterialApp/Navigator (built by LockGate's
    // caller) - just a Scaffold, not a nested MaterialApp.
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              const Text('App locked'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _checking ? null : _tryUnlock,
                child: _checking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
