import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// A 3D-styled animated launch screen shown immediately while KeepIt boots its
/// local database and background services.
///
/// Uses true 3D perspective transforms (`Matrix4` with perspective entry
/// `(3, 2)`), extruded 3D bevel layers, radial 3D-lit spheres, and orbiting
/// glassmorphic/claymorphic 3D cards so the launch feels instant and alive.
class KeepIt3DSplashScreen extends StatefulWidget {
  const KeepIt3DSplashScreen({super.key, this.forceDark});

  /// Optional override for dark/light mode; defaults to platform brightness.
  final bool? forceDark;

  @override
  State<KeepIt3DSplashScreen> createState() => _KeepIt3DSplashScreenState();
}

class _KeepIt3DSplashScreenState extends State<KeepIt3DSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _loopController;
  late final Animation<double> _introScale;
  late final Animation<double> _introFade;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _introScale = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutBack,
    );
    _introFade = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _introController.dispose();
    _loopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.forceDark ??
        (MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark);

    final bgTop = isDark ? const Color(0xFF0B0D13) : const Color(0xFFFFF8F5);
    final bgBottom = isDark ? const Color(0xFF141824) : const Color(0xFFF3F5FA);
    final textPrimary =
        isDark ? const Color(0xFFF3F5F9) : const Color(0xFF111827);
    final textSecondary =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bgTop,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_introController, _loopController]),
            builder: (context, _) {
              final t = _loopController.value * 2 * math.pi;
              final intro = _introScale.value.clamp(0.0, 1.25);
              final fade = _introFade.value.clamp(0.0, 1.0);

              return Opacity(
                opacity: fade,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),
                    SizedBox(
                      width: 290,
                      height: 290,
                      child: _Scene3D(
                        t: t,
                        intro: intro,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Transform.translate(
                      offset: Offset(0, (1 - fade) * 14),
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: isDark
                                  ? const [
                                      Color(0xFFFFFFFF),
                                      Color(0xFFFFB4A1),
                                    ]
                                  : const [
                                      Color(0xFF111827),
                                      Color(0xFFE03C1C),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: const Text(
                              'KeepIt',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.0,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your visual second brain',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _ProgressBar3D(
                            progress: _loopController.value,
                            isDark: isDark,
                            textPrimary: textPrimary,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(flex: 3),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Scene3D extends StatelessWidget {
  const _Scene3D({
    required this.t,
    required this.intro,
    required this.isDark,
  });

  final double t;
  final double intro;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final floatY = math.sin(t) * 7.0;
    final tiltX = math.sin(t) * 0.14;
    final tiltY = math.cos(t) * 0.18;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Soft 3D ambient volumetric glow behind the scene
        Container(
          width: 210,
          height: 210,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFFF5B37).withValues(alpha: isDark ? 0.28 : 0.20),
                const Color(0xFF7C3AED).withValues(alpha: isDark ? 0.14 : 0.08),
                Colors.transparent,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),

        // 3D Floor shadow that scales with the floating cube's height
        Positioned(
          bottom: 24,
          child: Transform.scale(
            scaleX: 1.0 - (math.sin(t) * 0.08),
            scaleY: 0.32,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5B37)
                        .withValues(alpha: isDark ? 0.32 : 0.24),
                    blurRadius: 34,
                    spreadRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Tilted 3D orbital rings around the cube
        CustomPaint(
          size: const Size(270, 270),
          painter: _OrbitalRing3DPainter(t: t, isDark: isDark),
        ),

        // 3D Lit Spheres floating in background depth
        Positioned(
          top: 26 + math.cos(t * 1.2) * 8,
          left: 38 + math.sin(t * 1.2) * 6,
          child: const _Sphere3D(
            size: 20,
            lightColor: Color(0xFFFFB199),
            midColor: Color(0xFFFF5B37),
            darkColor: Color(0xFF9E1F05),
          ),
        ),
        Positioned(
          bottom: 42 + math.sin(t * 1.3) * 9,
          left: 24 + math.cos(t * 1.3) * 6,
          child: const _Sphere3D(
            size: 15,
            lightColor: Color(0xFFC4B5FD),
            midColor: Color(0xFF7C3AED),
            darkColor: Color(0xFF3B0764),
          ),
        ),
        Positioned(
          top: 48 + math.sin(t + 1.5) * 7,
          right: 22 + math.cos(t + 1.5) * 6,
          child: const _Sphere3D(
            size: 16,
            lightColor: Color(0xFF93C5FD),
            midColor: Color(0xFF2563EB),
            darkColor: Color(0xFF1E3A8A),
          ),
        ),

        // Orbiting 3D Floating Card 1: Video / Reel (Top-Left)
        Transform.translate(
          offset: Offset(
            -78 * intro + math.cos(t + 0.5) * 5,
            -64 * intro + math.sin(t + 0.5) * 7,
          ),
          child: _FloatingCard3D(
            rotateX: 0.18 + tiltX * 0.5,
            rotateY: -0.24 + tiltY * 0.5,
            rotateZ: -0.14,
            icon: LucideIcons.play,
            accentStart: const Color(0xFFFF758C),
            accentEnd: const Color(0xFFFF3E6C),
            label: 'Reel',
            isDark: isDark,
          ),
        ),

        // Orbiting 3D Floating Card 2: Web Article / Link (Top-Right)
        Transform.translate(
          offset: Offset(
            82 * intro + math.sin(t + 2.0) * 6,
            -54 * intro + math.cos(t + 2.0) * 7,
          ),
          child: _FloatingCard3D(
            rotateX: 0.15 - tiltX * 0.4,
            rotateY: 0.25 + tiltY * 0.4,
            rotateZ: 0.12,
            icon: LucideIcons.globe,
            accentStart: const Color(0xFF60A5FA),
            accentEnd: const Color(0xFF2563EB),
            label: 'Article',
            isDark: isDark,
          ),
        ),

        // Orbiting 3D Floating Card 3: Quick Idea / Note (Bottom-Right)
        Transform.translate(
          offset: Offset(
            74 * intro + math.cos(t + 3.8) * 6,
            62 * intro + math.sin(t + 3.8) * 6,
          ),
          child: _FloatingCard3D(
            rotateX: -0.16 + tiltX * 0.4,
            rotateY: 0.22 - tiltY * 0.4,
            rotateZ: -0.09,
            icon: LucideIcons.lightbulb,
            accentStart: const Color(0xFFFBBF24),
            accentEnd: const Color(0xFFD97706),
            label: 'Idea',
            isDark: isDark,
          ),
        ),

        // Orbiting 3D Floating Card 4: Saved Space / Bookmark (Bottom-Left)
        Transform.translate(
          offset: Offset(
            -74 * intro + math.sin(t + 4.9) * 5,
            58 * intro + math.cos(t + 4.9) * 6,
          ),
          child: _FloatingCard3D(
            rotateX: -0.14 - tiltX * 0.4,
            rotateY: -0.22 + tiltY * 0.4,
            rotateZ: 0.10,
            icon: LucideIcons.bookmark,
            accentStart: const Color(0xFF34D399),
            accentEnd: const Color(0xFF059669),
            label: 'Saved',
            isDark: isDark,
          ),
        ),

        // Central 3D Extruded KeepIt Brain-Cube
        Transform.scale(
          scale: intro,
          child: Transform.translate(
            offset: Offset(0, floatY),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0016)
                ..rotateX(tiltX)
                ..rotateY(tiltY)
                ..rotateZ(math.sin(t * 0.5) * 0.04),
              child: _CentralCube3D(t: t, isDark: isDark),
            ),
          ),
        ),
      ],
    );
  }
}

/// Multi-layered extruded 3D block with specular rim lighting and inner depth.
class _CentralCube3D extends StatelessWidget {
  const _CentralCube3D({required this.t, required this.isDark});

  final double t;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final shiftX = math.cos(t) * 6.0;
    final shiftY = math.sin(t) * 5.0;

    return SizedBox(
      width: 122,
      height: 122,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Deep 3D extruded back bevel (simulates 3D block thickness)
          Transform.translate(
            offset: Offset(-shiftX * 1.1, 8 - shiftY * 0.6),
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: const LinearGradient(
                  colors: [Color(0xFF9E1F05), Color(0xFF5C0E00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),

          // Mid 3D bevel rim
          Transform.translate(
            offset: Offset(-shiftX * 0.55, 4 - shiftY * 0.3),
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: const LinearGradient(
                  colors: [Color(0xFFD63213), Color(0xFF8F1B04)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),

          // Main 3D sculpted front face with claymorphic highlights
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF9E80),
                  Color(0xFFFF5B37),
                  Color(0xFFD93111),
                ],
                stops: [0.0, 0.52, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF5B37)
                      .withValues(alpha: isDark ? 0.50 : 0.38),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Top-left 3D specular gloss dome
                Positioned(
                  top: 6,
                  left: 10,
                  right: 26,
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.42),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                // Inner recessed 3D glass chamber
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(23),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.26),
                        Colors.black.withValues(alpha: 0.14),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 3D Shadow behind icon
                      Transform.translate(
                        offset: const Offset(0, 3),
                        child: Icon(
                          LucideIcons.sparkles,
                          color: Colors.black.withValues(alpha: 0.25),
                          size: 38,
                        ),
                      ),
                      const Icon(
                        LucideIcons.sparkles,
                        color: Colors.white,
                        size: 38,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A miniature 3D-tilted card floating around the central core.
class _FloatingCard3D extends StatelessWidget {
  const _FloatingCard3D({
    required this.rotateX,
    required this.rotateY,
    required this.rotateZ,
    required this.icon,
    required this.accentStart,
    required this.accentEnd,
    required this.label,
    required this.isDark,
  });

  final double rotateX;
  final double rotateY;
  final double rotateZ;
  final IconData icon;
  final Color accentStart;
  final Color accentEnd;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cardSurface =
        isDark ? const Color(0xE61F2433) : const Color(0xF2FFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.85);
    final labelColor =
        isDark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937);

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateX(rotateX)
        ..rotateY(rotateY)
        ..rotateZ(rotateZ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.3),
          boxShadow: [
            BoxShadow(
              color: accentEnd.withValues(alpha: isDark ? 0.30 : 0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: LinearGradient(
                  colors: [accentStart, accentEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accentEnd.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 15),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a 3D shaded sphere using an off-center focal radial gradient.
class _Sphere3D extends StatelessWidget {
  const _Sphere3D({
    required this.size,
    required this.lightColor,
    required this.midColor,
    required this.darkColor,
  });

  final double size;
  final Color lightColor;
  final Color midColor;
  final Color darkColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: [lightColor, midColor, darkColor],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: midColor.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}

/// Paints a tilted 3D orbital ellipse with a moving comet highlight.
class _OrbitalRing3DPainter extends CustomPainter {
  _OrbitalRing3DPainter({required this.t, required this.isDark});

  final double t;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.38);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 0.92,
      height: size.height * 0.38,
    );

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = SweepGradient(
        colors: [
          const Color(0xFFFF5B37).withValues(alpha: 0.05),
          const Color(0xFFFF5B37).withValues(alpha: isDark ? 0.55 : 0.40),
          const Color(0xFF7C3AED).withValues(alpha: isDark ? 0.45 : 0.30),
          const Color(0xFFFF5B37).withValues(alpha: 0.05),
        ],
        transform: GradientRotation(t),
      ).createShader(rect);

    canvas.drawOval(rect, ringPaint);

    // Orbiting glowing node along the 3D ellipse
    final orbX = (rect.width / 2) * math.cos(t);
    final orbY = (rect.height / 2) * math.sin(t);
    final nodePaint = Paint()
      ..color = const Color(0xFFFF5B37)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(orbX, orbY), 4.5, nodePaint);
    canvas.drawCircle(
      Offset(orbX, orbY),
      2.5,
      Paint()..color = Colors.white,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OrbitalRing3DPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.isDark != isDark;
}

class _ProgressBar3D extends StatelessWidget {
  const _ProgressBar3D({
    required this.progress,
    required this.isDark,
    required this.textPrimary,
  });

  final double progress;
  final bool isDark;
  final Color textPrimary;

  @override
  Widget build(BuildContext context) {
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.07);
    final shimmerShift = (progress * 2.0) - 0.5;

    return Container(
      width: 148,
      height: 6,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(99),
      ),
      child: FractionallySizedBox(
        alignment: Alignment(math.sin(shimmerShift * math.pi), 0),
        widthFactor: 0.48,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFF8A65),
                Color(0xFFFF5B37),
                Color(0xFF7C3AED),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
