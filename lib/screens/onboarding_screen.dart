import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardPageData {
  final String title;
  final String subtitle;
  final String imageAsset;
  final List<Color> gradient;

  const _OnboardPageData({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.gradient,
  });
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _pulseController;
  int _page = 0;

  final List<_OnboardPageData> _pages = const [
    _OnboardPageData(
      title: 'Welcome to SmartSync',
      subtitle:
          'Smart, adaptive control for lights, fans and sensors. Let the system learn and schedule for you.',
      imageAsset: 'assets/images/onboarding1.png',
      gradient: [Color(0xFFEEF2FF), Color(0xFFDDE9FF)],
    ),
    _OnboardPageData(
      title: 'Control Fans & Lights',
      subtitle:
          'Fine-grained control with schedules and automatic rules — save energy and simplify routines.',
      imageAsset: 'assets/images/onboarding2.png',
      gradient: [Color(0xFFFFF6E6), Color(0xFFFFE6D6)],
    ),
    _OnboardPageData(
      title: 'Connect Devices',
      subtitle:
          'Quickly pair via Bluetooth and manage all your devices from a single place.',
      imageAsset: 'assets/images/onboarding3.png',
      gradient: [Color(0xFFE8FFF6), Color(0xFFD7FFF0)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pageController.addListener(() {
      final newPage = (_pageController.page ?? 0).round();
      if (newPage != _page) setState(() => _page = newPage);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goToAuth() => GoRouter.of(context).go('/login');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // background per page — animate by reading _page index
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _pages[_page].gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top row: Skip
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: _goToAuth,
                        child: const Text('Skip'),
                      )
                    ],
                  ),
                ),

                // PageView (fills available space)
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      final isActive = index == _page;

                      // subtle scale/rotation based on controller
                      final scaleAnim = Tween<double>(begin: 0.96, end: 1.04)
                          .animate(CurvedAnimation(
                              parent: _pulseController,
                              curve: Curves.easeInOut));
                      final rotationAnim =
                          Tween<double>(begin: -0.015, end: 0.015).animate(
                              CurvedAnimation(
                                  parent: _pulseController,
                                  curve: Curves.easeInOut));

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Decorative art area
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                final scale = isActive ? scaleAnim.value : 0.98;
                                final rotation =
                                    isActive ? rotationAnim.value : 0.0;

                                return Transform.rotate(
                                  angle: rotation,
                                  child: Transform.scale(
                                    scale: scale,
                                    child: SizedBox(
                                      height: 280,
                                      width: 280,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            height: 260,
                                            width: 260,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: RadialGradient(
                                                colors: [
                                                  page.gradient.first
                                                      .withOpacity(0.48),
                                                  page.gradient.last
                                                      .withOpacity(0.12)
                                                ],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.06),
                                                  blurRadius: 30,
                                                  offset: const Offset(0, 12),
                                                )
                                              ],
                                            ),
                                          ),
                                          Positioned(
                                            left: 8,
                                            top: 18,
                                            child: Transform.rotate(
                                              angle: -0.06,
                                              child: Opacity(
                                                opacity: 0.18,
                                                child: Image.asset(
                                                  page.imageAsset,
                                                  width: 180,
                                                  height: 180,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                          ),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(28),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(
                                                  sigmaX: 8, sigmaY: 8),
                                              child: Container(
                                                height: 200,
                                                width: 200,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.14),
                                                  borderRadius:
                                                      BorderRadius.circular(28),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withOpacity(0.12),
                                                  ),
                                                ),
                                                child: Container(
                                                  height: 160,
                                                  width: 160,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            20),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.12),
                                                        blurRadius: 18,
                                                        offset:
                                                            const Offset(0, 8),
                                                      )
                                                    ],
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16),
                                                    child: Image.asset(
                                                      page.imageAsset,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 400),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(
                                                    isActive ? 0.18 : 0.06),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Step ${index + 1}',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 28),

                            // Title
                            Text(
                              page.title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Subtitle
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: Text(
                                page.subtitle,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.black87,
                                  fontSize: 15,
                                ),
                              ),
                            ),

                            const SizedBox(height: 28),

                            // Single Get Started button
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _goToAuth,
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text(
                                          'Get Started',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Bottom dots
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    children: [
                      _buildDots(),
                      const SizedBox(height: 8),
                      Text('Swipe → to continue',
                          style: theme.textTheme.bodySmall),
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

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pages.length, (i) {
        final active = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: active ? 20 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6C6CE5) : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
        );
      }),
    );
  }

  Color _iconColorForGradient(List<Color> g) {
    final base = g.last;
    return base.computeLuminance() > 0.6 ? Colors.deepPurple : Colors.white;
  }
}
