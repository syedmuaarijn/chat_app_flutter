import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat_app_flutter/providers/call_provider.dart';
import 'package:chat_app_flutter/services/agora_call_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Dedicated 1-to-1 video-call UI. Voice calls continue using CallScreen.
class VideoCallScreen extends StatelessWidget {
  const VideoCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.read<CallProvider>().endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Consumer<CallProvider>(
            builder: (context, call, _) => Stack(
              fit: StackFit.expand,
              children: [
                _RemoteVideo(call: call),
                if (!call.isEnded) _Header(call: call),
                if (!call.isEnded) _LocalPreview(call: call),
                if (!call.isEnded) _Controls(call: call),
                if (call.isEnded)
                  const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Text(
                        'Call Ended',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteVideo extends StatelessWidget {
  const _RemoteVideo({required this.call});
  final CallProvider call;

  @override
  Widget build(BuildContext context) {
    final engine = AgoraCallService.instance.engine;
    final uid = call.remoteUid;
    if (engine != null && uid != null) {
      return Stack(
        children: [
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(
                uid: uid,
                renderMode: RenderModeType.renderModeHidden,
              ),
              connection: RtcConnection(channelId: call.agoraChannelName),
            ),
          ),
          if (call.isRemoteVideoPaused)
            const ColoredBox(
              color: Colors.black,
              child: Center(
                child: Text(
                  'Video paused',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
        ],
      );
    }
    final avatar = call.remoteUserAvatarUrl;
    return Container(
      color: const Color(0xFF111827),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 64,
              backgroundImage: avatar != null && avatar.isNotEmpty
                  ? CachedNetworkImageProvider(avatar)
                  : null,
              child: avatar == null || avatar.isEmpty
                  ? const Icon(Icons.person, size: 64)
                  : null,
            ),
            const SizedBox(height: 20),
            Text(
              call.isRinging ? 'Ringing…' : 'Waiting for video…',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.call});
  final CallProvider call;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 12,
    left: 0,
    right: 0,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          call.remoteUserName ?? 'Video call',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          call.isActive ? call.formattedDuration : 'Connecting…',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );
}

class _LocalPreview extends StatelessWidget {
  const _LocalPreview({required this.call});
  final CallProvider call;

  @override
  Widget build(BuildContext context) {
    final engine = AgoraCallService.instance.engine;
    return Positioned(
      top: 100,
      right: 16,
      width: 112,
      height: 156,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: const Color(0xFF1F2937),
          child: call.isCameraMuted || engine == null
              ? const Icon(Icons.videocam_off, color: Colors.white70, size: 36)
              : AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: engine,
                    canvas: const VideoCanvas(
                      uid: 0,
                      mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.call});
  final CallProvider call;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _button(
            context,
            call.isMicMuted ? Icons.mic_off : Icons.mic,
            () => context.read<CallProvider>().toggleMute(),
          ),
          _button(
            context,
            call.isCameraMuted ? Icons.videocam_off : Icons.videocam,
            () => context.read<CallProvider>().toggleCamera(),
          ),
          _button(
            context,
            Icons.cameraswitch,
            () => context.read<CallProvider>().switchCamera(),
          ),
          _button(
            context,
            Icons.call_end,
            () => context.read<CallProvider>().endCall(),
            red: true,
          ),
        ],
      ),
    ),
  );

  Widget _button(
    BuildContext context,
    IconData icon,
    VoidCallback action, {
    bool red = false,
  }) => Material(
    color: red ? Colors.redAccent : Colors.black54,
    shape: const CircleBorder(),
    child: IconButton(
      onPressed: action,
      icon: Icon(icon, color: Colors.white),
      iconSize: 28,
    ),
  );
}
