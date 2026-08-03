import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat_app_flutter/providers/call_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Active / outgoing call screen.
/// Shown for both the caller (status=ringing → active) and the recipient
/// (status=active after acceptCall navigates here).
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
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
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen for call ending to auto-pop
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onCallStateChanged(); // Check immediately
      _callProvider.addListener(_onCallStateChanged);
    });
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    final status = _callProvider.status;
    if (status == CallStatus.idle) {
      // Already cleaned up — pop this screen
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

  Future<void> _onEndCall() async {
    await context.read<CallProvider>().endCall();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Intercept back gesture — it ends the call instead of just popping
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _onEndCall();
        }
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0D1117),
                Color(0xFF161B22),
                Color(0xFF0D1117),
              ],
            ),
          ),
          child: SafeArea(
            child: Consumer<CallProvider>(
              builder: (context, callProvider, _) {
                final isActive = callProvider.isActive;
                final isEnded = callProvider.isEnded;

                return Column(
                  children: [
                    _buildTopBar(callProvider),
                    Expanded(child: _buildCenterContent(callProvider, isActive)),
                    if (!isEnded) _buildBottomControls(callProvider),
                    if (isEnded) _buildEndedLabel(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(CallProvider callProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white, size: 32),
            tooltip: 'Minimise',
            onPressed: () {
              // Minimise without ending — same as going back in the stack
              // We do NOT end the call here; user must press End Call button
              Navigator.of(context).pop();
            },
          ),
          const Spacer(),
          Column(
            children: [
              Text(
                callProvider.remoteUserName ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              _buildStatusLabel(callProvider),
            ],
          ),
          const Spacer(),
          // Placeholder to balance the row
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildStatusLabel(CallProvider callProvider) {
    String label;
    Color color;

    if (callProvider.isEnded) {
      label = 'Call Ended';
      color = Colors.redAccent;
    } else if (callProvider.isActive) {
      label = callProvider.formattedDuration;
      color = Colors.greenAccent;
    } else if (callProvider.isRinging && !callProvider.isIncoming) {
      label = 'Ringing…';
      color = Colors.white70;
    } else {
      label = 'Connecting…';
      color = Colors.white70;
    }

    return Text(
      label,
      style: TextStyle(color: color, fontSize: 14),
    );
  }

  Widget _buildCenterContent(CallProvider callProvider, bool isActive) {
    final hasAvatar = (callProvider.remoteUserAvatarUrl ?? '').isNotEmpty;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Avatar with pulse when active
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, child) {
            return Transform.scale(
              scale: isActive ? _pulseAnim.value : 1.0,
              child: child,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isActive ? Colors.blueAccent : Colors.white)
                      .withValues(alpha: 0.15),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 72,
              backgroundColor: const Color(0xFF21262D),
              backgroundImage: hasAvatar
                  ? CachedNetworkImageProvider(
                      callProvider.remoteUserAvatarUrl!)
                  : null,
              child: hasAvatar
                  ? null
                  : const Icon(Icons.person_rounded,
                      size: 72, color: Colors.white38),
            ),
          ),
        ),
        const SizedBox(height: 28),
        if (!isActive && !callProvider.isEnded)
          const _AnimatedEllipsis(),
      ],
    );
  }

  Widget _buildBottomControls(CallProvider callProvider) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 56, left: 32, right: 32),
      child: Column(
        children: [
          // Mic + Speaker row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _controlButton(
                icon: callProvider.isMicMuted
                    ? Icons.mic_off_rounded
                    : Icons.mic_rounded,
                label: callProvider.isMicMuted ? 'Unmute' : 'Mute',
                bgColor: callProvider.isMicMuted
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.12),
                iconColor:
                    callProvider.isMicMuted ? Colors.black : Colors.white,
                onTap: () => context.read<CallProvider>().toggleMute(),
              ),
              // End call — centre, larger
              _endCallButton(),
              _controlButton(
                icon: callProvider.isSpeakerphone
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                label: callProvider.isSpeakerphone ? 'Speaker' : 'Earpiece',
                bgColor: callProvider.isSpeakerphone
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.12),
                iconColor:
                    callProvider.isSpeakerphone ? Colors.black : Colors.white,
                onTap: () => context.read<CallProvider>().toggleSpeaker(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEndedLabel() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 80),
      child: Text(
        'Call Ended',
        style: TextStyle(color: Colors.redAccent, fontSize: 16),
      ),
    );
  }

  Widget _endCallButton() {
    return Column(
      children: [
        GestureDetector(
          onTap: _onEndCall,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.call_end_rounded,
                color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 8),
        const Text('End Call',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}

// ── Animated ellipsis (Connecting… / Ringing…) ───────────────────────────────
class _AnimatedEllipsis extends StatefulWidget {
  const _AnimatedEllipsis();

  @override
  State<_AnimatedEllipsis> createState() => _AnimatedEllipsisState();
}

class _AnimatedEllipsisState extends State<_AnimatedEllipsis>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _count = (_count + 1) % 4);
          _ctrl.reset();
          _ctrl.forward();
        }
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '.' * _count + '\u00A0' * (3 - _count), // nbsp to keep width stable
      style: const TextStyle(color: Colors.white38, fontSize: 20),
    );
  }
}