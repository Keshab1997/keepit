import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'app_colors.dart';

class MindToast {
  static void showDuplicateToast(
    BuildContext context, {
    String title = 'Already in your mind!',
  }) {
    _showFloatingToast(
      context: context,
      icon: LucideIcons.bookmark,
      accentColor: AppColors.primary,
      iconBgColor: const Color(0x26FF5B37),
      borderColor: const Color(0x66FF5B37),
      title: title,
      subtitle: "This link has already been saved to your mind.",
    );
  }

  static void showSuccessToast(
    BuildContext context, {
    String title = 'Saved to KeepIt!',
  }) {
    _showFloatingToast(
      context: context,
      icon: LucideIcons.sparkles,
      accentColor: AppColors.success,
      iconBgColor: const Color(0x2610B981),
      borderColor: const Color(0x6610B981),
      title: title,
      subtitle: "Added to your visual second brain.",
    );
  }

  static void showDeleteToast(
    BuildContext context, {
    String title = 'Item removed',
  }) {
    _showFloatingToast(
      context: context,
      icon: LucideIcons.trash2,
      accentColor: AppColors.danger,
      iconBgColor: const Color(0x26FF3B30),
      borderColor: const Color(0x66FF3B30),
      title: title,
      subtitle: "Permanently deleted from your mind.",
      duration: const Duration(milliseconds: 2400),
    );
  }

  /// Neutral "here is what just happened" toast (used by Check for update).
  static void showInfoToast(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    _showFloatingToast(
      context: context,
      icon: LucideIcons.info,
      accentColor: AppColors.primary,
      iconBgColor: const Color(0x26FF5B37),
      borderColor: const Color(0x66FF5B37),
      title: title,
      subtitle: subtitle,
    );
  }

  static void _showFloatingToast({
    required BuildContext context,
    required IconData icon,
    required Color accentColor,
    required Color iconBgColor,
    required Color borderColor,
    required String title,
    required String subtitle,
    Duration duration = const Duration(milliseconds: 2600),
  }) {
    // Fallback to the navigator's overlay so toasts also work when called
    // with the Navigator's own context (e.g. navigatorKey.currentContext from
    // share-intent or notification handlers), which has no Overlay ancestor.
    final overlay =
        Overlay.maybeOf(context) ?? Navigator.maybeOf(context)?.overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    bool isRemoved = false;

    void safeRemove() {
      if (!isRemoved && entry.mounted) {
        isRemoved = true;
        entry.remove();
      }
    }

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, -20 * (1.0 - value)),
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xF8FFFFFF),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: borderColor, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                            const BoxShadow(
                              color: Color(0x0F000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: iconBgColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, color: accentColor, size: 19),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      letterSpacing: -0.2,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(duration, safeRemove);
  }
}
