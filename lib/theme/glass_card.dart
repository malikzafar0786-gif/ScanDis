import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// A frosted-glass panel: blurred translucent background, faint cyan
/// border, soft glow. Used throughout the dark theme for cards, search
/// bars, and action buttons to match the glassmorphism design brief.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool glow;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.glow = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.surfaceGlass,
            borderRadius: borderRadius,
            border: Border.all(color: AppColors.glassBorder, width: 1),
            boxShadow: glow
                ? [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.18),
                      blurRadius: 24,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(borderRadius: borderRadius, onTap: onTap, child: content),
    );
  }
}
