import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:lottie/lottie.dart';
import '../widgets/common/abstract_background.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  bool isLastPage = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch', false);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          const AbstractBackground(),
          PageView(
            controller: _controller,
            onPageChanged: (index) {
              setState(() => isLastPage = index == 2);
            },
            children: [
              _buildPage(
                subtitle: 'Yapp: because silence is overrated.',
                visual: Lottie.asset('assets/animations/chat-animation.json', fit: BoxFit.contain),
              ),
              _buildPage(
                subtitle: 'Chat, call, and make new friends.',
                visual: Lottie.asset('assets/animations/make-new-friends-animation.json', fit: BoxFit.contain),
              ),
              _buildPage(
                subtitle: 'Meet Yapp AI, your smart chat companion.',
                visual: Image.asset('assets/yapp_ai_full.png', fit: BoxFit.contain),
              ),
            ],
          ),
          Container(
            alignment: const Alignment(0, 0.85),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: () => _controller.jumpToPage(2),
                  child: Text('Skip', style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70)),
                ),
                SmoothPageIndicator(
                  controller: _controller,
                  count: 3,
                  effect: ExpandingDotsEffect(
                    activeDotColor: accent,
                    dotColor: Colors.white24,
                    dotHeight: 8,
                    dotWidth: 8,
                  ),
                ),
                isLastPage
                    ? GestureDetector(
                        onTap: _finishOnboarding,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Text('Get Started', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                        ),
                      )
                    : GestureDetector(
                        onTap: () => _controller.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut),
                        child: Text('Next', style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage({required String subtitle, required Widget visual}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/yapp-logo.png', height: 45),
          const SizedBox(height: 60),
          SizedBox(
            height: 300,
            child: Center(child: visual),
          ),
          const SizedBox(height: 50),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white70,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 60), 
        ],
      ),
    );
  }
}
