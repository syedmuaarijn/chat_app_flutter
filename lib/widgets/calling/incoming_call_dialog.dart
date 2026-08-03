
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat_app_flutter/providers/call_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Full-screen incoming call page — pushed as a named route '/incoming-call'.
/// This replaces the previous Dialog/overlay approach that blocked touches.
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late CallProvider _callProvider;

  @override
  void initState() {
    super.initState();
    _callProvider = context.read<CallProvider>();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen for call state changes to auto-pop when caller cancels
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onCallStateChanged(); // Check immediately in case status changed during transition
      _callProvider.addListener(_onCallStateChanged);
    });
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    final status = _callProvider.status;
    // If the call ends or is accepted (and we navigated to /call), pop this screen
    if (status == CallStatus.ended || status == CallStatus.idle) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _callProvider.removeListener(_onCallStateChanged);
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _onAccept() async {
    final callProvider = context.read<CallProvider>();
    // Pop incoming screen first, then push call screen
    if (mounted) Navigator.of(context).pop();
    await callProvider.acceptCall();
    // Navigate to active call screen
    callProvider.navigatorKey?.currentState?.pushNamed('/call');
  }

  Future<void> _onDecline() async {
    final callProvider = context.read<CallProvider>();
    if (mounted) Navigator.of(context).pop();
    await callProvider.declineCall();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Prevent back button from accidentally dismissing without declining
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _onDecline();
        }
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0A0A1A),
                Color(0xFF0D1B2A),
                Color(0xFF1A1035),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTopSection(),
                _buildBottomControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          // Incoming call label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Incoming Voice Call',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 40),
          // Pulsing avatar
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnim.value,
                child: child,
              );
            },
            child: Consumer<CallProvider>(
              builder: (context, callProvider, _) {
                return _buildAvatar(callProvider.remoteUserAvatarUrl);
              },
            ),
          ),
          const SizedBox(height: 24),
          // Caller name
          Consumer<CallProvider>(
            builder: (context, callProvider, _) {
              return Text(
                callProvider.remoteUserName ?? 'Unknown Caller',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Animated dots
          const _RingingDots(),
        ],
      ),
    );
  }

  Widget _buildAvatar(String? avatarUrl) {
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.3),
            blurRadius: 40,
            spreadRadius: 10,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 60,
        backgroundColor: const Color(0xFF2A2A4A),
        backgroundImage: hasAvatar ? CachedNetworkImageProvider(avatarUrl) : null,
        child: hasAvatar
            ? null
            : const Icon(Icons.person, size: 60, color: Colors.white54),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 64),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline button
          _buildCallButton(
            icon: Icons.call_end_rounded,
            color: const Color(0xFFFF3B30),
            label: 'Decline',
            onTap: _onDecline,
          ),
          // Accept button
          _buildCallButton(
            icon: Icons.call_rounded,
            color: const Color(0xFF34C759),
            label: 'Accept',
            onTap: _onAccept,
          ),
        ],
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ── Animated ringing dots ─────────────────────────────────────────────────────
class _RingingDots extends StatefulWidget {
  const _RingingDots();

  @override
  State<_RingingDots> createState() => _RingingDotsState();
}

class _RingingDotsState extends State<_RingingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _dotCount = 1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _dotCount = (_dotCount % 3) + 1);
          _controller.reset();
          _controller.forward();
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * _dotCount + ' ' * (3 - _dotCount);
    return Text(
      'Ringing$dots',
      style: const TextStyle(color: Colors.white54, fontSize: 15),
    );
  }
}