import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class AvatarHelper {
  static ImageProvider getAvatarProvider(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.trim().isEmpty) {
      return const AssetImage('assets/avatars/avatar_1.png');
    }
    if (avatarUrl.startsWith('assets/')) {
      return AssetImage(avatarUrl);
    }
    return CachedNetworkImageProvider(avatarUrl);
  }
}
