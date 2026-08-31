import 'package:flutter/material.dart';

class ThemeRippleOverlay extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;
  final Offset center;
  final bool isDarkTarget;

  const ThemeRippleOverlay({
    super.key,
    required this.child,
    required this.animation,
    required this.center,
    required this.isDarkTarget,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return ClipPath(
          clipper: _CircleRevealClipper(
            fraction: animation.value,
            center: center,
          ),
          child: child,
        );
      },
    );
  }
}

class _CircleRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Offset center;

  const _CircleRevealClipper({required this.fraction, required this.center});

  @override
  Path getClip(Size size) {
    final distances = [
      (center - Offset.zero).distance,
      (center - Offset(size.width, 0)).distance,
      (center - Offset(0, size.height)).distance,
      (center - Offset(size.width, size.height)).distance,
    ];
    final maxRadius = distances.reduce((a, b) => a > b ? a : b);
    final radius = maxRadius * fraction;
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(_CircleRevealClipper oldClipper) =>
      oldClipper.fraction != fraction || oldClipper.center != center;
}
