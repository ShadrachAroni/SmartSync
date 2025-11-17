import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../auth/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _floatingController;
  late AnimationController _rotationController;
  late AnimationController _pulseController;

  int _currentPage = 0;

  final List<OnboardingPageData> _pages = [
    OnboardingPageData(
      title: 'Clean at\nYour Command',
      subtitle: 'Smart Home for Elderly Care',
      description:
          'Seamlessly manage lights, locks, and more—right from your phone with voice commands',
      color: const Color(0xFF00BFA5),
      icon: Icons.home_rounded,
      accentIcon: Icons.wifi_rounded,
    ),
    OnboardingPageData(
      title: 'Monitor Your\nLoved Ones',
      subtitle: 'Real-time Health Tracking',
      description:
          'Keep track of elderly family members with real-time sensors and intelligent alerts',
      color: const Color(0xFF7C4DFF),
      icon: Icons.favorite_rounded,
      accentIcon: Icons.sensors_rounded,
    ),
    OnboardingPageData(
      title: 'Smart Energy\nManagement',
      subtitle: 'Save Money & Environment',
      description:
          'Track and optimize your energy consumption with AI-powered insights and recommendations',
      color: const Color(0xFFFF6B6B),
      icon: Icons.bolt_rounded,
      accentIcon: Icons.eco_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // Floating animation
    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Rotation animation
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _floatingController.dispose();
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _skipToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Animated Background
            AnimatedBuilder(
              animation: _pageController,
              builder: (context, child) {
                double page = 0;
                if (_pageController.hasClients &&
                    _pageController.position.hasContentDimensions) {
                  page = _pageController.page ?? 0;
                } else {
                  page = _currentPage.toDouble();
                }

                final index = page.floor();
                final progress = page - index;
                final currentColor = _pages[index % _pages.length].color;
                final nextColor = _pages[(index + 1) % _pages.length].color;

                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(currentColor, nextColor, progress)!
                            .withOpacity(0.08),
                        Color.lerp(currentColor, nextColor, progress)!
                            .withOpacity(0.03),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Main Content
            Column(
              children: [
                // Skip Button
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _skipToLogin,
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),

                // Page View
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      return _buildPage(_pages[index], index);
                    },
                  ),
                ),

                // Bottom Section
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Page Indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _pages.length,
                          (index) => _buildPageIndicator(index),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Action Button
                      _buildActionButton(),

                      // Login Link (only on last page)
                      if (_currentPage == _pages.length - 1) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Already have an account? ',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            TextButton(
                              onPressed: _skipToLogin,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Login',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _pages[_currentPage].color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Progress Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double page = 0;
                  if (_pageController.hasClients &&
                      _pageController.position.hasContentDimensions) {
                    page = _pageController.page ?? 0;
                  } else {
                    page = _currentPage.toDouble();
                  }

                  return Container(
                    height: 3,
                    color: Colors.grey.shade100,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (page + 1) / _pages.length,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _pages[_currentPage].color,
                              _pages[_currentPage].color.withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPageData page, int index) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Illustration
        SizedBox(
          height: 320,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Radial Gradient Background
              Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      page.color.withOpacity(0.2),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),

              // Floating Elements
              AnimatedBuilder(
                animation: _floatingController,
                builder: (context, child) {
                  return Positioned(
                    top: 30 + (_floatingController.value * 20),
                    left: 40,
                    child: Transform.rotate(
                      angle: _floatingController.value * 0.1,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: page.color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  );
                },
              ),

              AnimatedBuilder(
                animation: _floatingController,
                builder: (context, child) {
                  return Positioned(
                    bottom: 50 + (_floatingController.value * 15),
                    right: 60,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: page.color.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),

              // Main Circle
              AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationController.value *
                        2 *
                        math.pi *
                        (index % 2 == 0 ? 1 : -1) *
                        0.05,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            page.color,
                            page.color.withOpacity(0.8),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: page.color.withOpacity(0.3),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Icon(
                        page.icon,
                        size: 110,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),

              // Accent Circle
              Positioned(
                top: 50,
                right: 50,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: page.color.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: page.color.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: _pulseController.value * 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          page.accentIcon,
                          size: 28,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 48),

        // Text Content
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: page.color,
                  height: 1.2,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                page.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                page.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageIndicator(int index) {
    final isActive = index == _currentPage;
    final page = _pages[_currentPage];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 32 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? page.color : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildActionButton() {
    final page = _pages[_currentPage];
    final isLastPage = _currentPage == _pages.length - 1;

    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: isLastPage ? _skipToLogin : _nextPage,
        style: ElevatedButton.styleFrom(
          backgroundColor: page.color,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: page.color.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isLastPage ? 'Get Started' : 'Next',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isLastPage ? Icons.arrow_forward_rounded : Icons.chevron_right,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingPageData {
  final String title;
  final String subtitle;
  final String description;
  final Color color;
  final IconData icon;
  final IconData accentIcon;

  OnboardingPageData({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.color,
    required this.icon,
    required this.accentIcon,
  });
}
