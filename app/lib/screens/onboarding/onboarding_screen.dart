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
  late AnimationController _fadeController;
  late AnimationController _slideController;

  int _currentPage = 0;

  final List<OnboardingPageData> _pages = [
    OnboardingPageData(
      title: 'Control at Your Fingertips',
      subtitle: 'Light, Fan & Security',
      description:
          'Seamlessly manage your lights, control fan speed, and secure your home with intelligent automation—all from your phone',
      imagePath: 'assets/images/Onboarding_1.png',
      color: const Color(0xFF00BFA5),
    ),
    OnboardingPageData(
      title: 'Wireless Connection',
      subtitle: 'Bluetooth Smart Hub',
      description:
          'Connect effortlessly via Bluetooth to your SmartSync hub. No WiFi required—just pair and control your entire smart home',
      imagePath: 'assets/images/Onboarding_2.png',
      color: const Color(0xFF7C4DFF),
    ),
    OnboardingPageData(
      title: 'Smart Monitoring',
      subtitle: 'Real-time Sensors',
      description:
          'Monitor temperature, humidity, motion, and proximity with advanced sensors. Get instant alerts and insights for a safer home',
      imagePath: 'assets/images/Onboarding_3.png',
      color: const Color(0xFFFF6B6B),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // Fade animation for smooth transitions
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Slide animation for text
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _fadeController.reset();
      _slideController.reset();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      ).then((_) {
        _fadeController.forward();
        _slideController.forward();
      });
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Page View with Images
            PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
                _fadeController.reset();
                _slideController.reset();
                _fadeController.forward();
                _slideController.forward();
              },
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                return _buildPage(_pages[index], index);
              },
            ),

            // Top Skip Button
            Positioned(
              top: 20,
              right: 20,
              child: TextButton(
                onPressed: _skipToLogin,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  backgroundColor: Colors.black.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // Bottom Section
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.8),
                      Colors.black,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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

                      // Text Content
                      AnimatedBuilder(
                        animation: _slideController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(
                              0,
                              30 * (1 - _slideController.value),
                            ),
                            child: Opacity(
                              opacity: _slideController.value,
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            Text(
                              _pages[_currentPage].title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.2,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _pages[_currentPage].subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: _pages[_currentPage].color,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _pages[_currentPage].description,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withOpacity(0.8),
                                height: 1.5,
                              ),
                            ),
                          ],
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
                            Text(
                              'Already have an account? ',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.7),
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
              ),
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
                    color: Colors.white.withOpacity(0.1),
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
    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeController.value,
          child: child,
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image with Overlay
          Positioned.fill(
            child: Image.asset(
              page.imagePath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // Fallback to gradient if image fails
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        page.color.withOpacity(0.3),
                        page.color.withOpacity(0.1),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Dark Overlay for better text readability
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.2),
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Accent Color Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    page.color.withOpacity(0.1),
                    Colors.transparent,
                    page.color.withOpacity(0.05),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
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
        color: isActive ? page.color : Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildActionButton() {
    final page = _pages[_currentPage];
    final isLastPage = _currentPage == _pages.length - 1;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLastPage ? _skipToLogin : _nextPage,
        style: ElevatedButton.styleFrom(
          backgroundColor: page.color,
          foregroundColor: Colors.white,
          elevation: 8,
          shadowColor: page.color.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
  final String imagePath;
  final Color color;

  OnboardingPageData({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.imagePath,
    required this.color,
  });
}
