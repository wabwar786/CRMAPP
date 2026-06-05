// lib/webview_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:smartcrm_project/dashboard.dart';

class WebViewScreen extends StatefulWidget {
  final String userId;
  final String cCode;
  final String username;
  final String password;

  const WebViewScreen({
    super.key,
    required this.userId,
    required this.cCode,
    required this.username,
    required this.password,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with TickerProviderStateMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  double _loadProgress = 0.0;

  // ── Design Tokens ──────────────────────────────────────────────────────────
  static const Color _ink = Color(0xFF0A1628);        // deep navy
  static const Color _teal = Color(0xFF0E637A);       // brand teal
  static const Color _tealLight = Color(0xFF14899E);  // lighter teal
  static const Color _tealGlow = Color(0xFF0BE0FF);   // neon teal glow
  static const Color _amber = Color(0xFFF59E0B);      // warm amber
  static const Color _amberDeep = Color(0xFFEF7C00);  // amber deep
  static const Color _surface = Color(0xFF0F1E35);    // card surface
  static const Color _surfaceElevated = Color(0xFF162840); // elevated surface
  static const Color _border = Color(0xFF1E3A52);     // subtle border
  static const Color _textPrimary = Color(0xFFEDF2F7);
  static const Color _textSecondary = Color(0xFF8BAFC7);

  // ── Animation Controllers ──────────────────────────────────────────────────
  late AnimationController _appBarController;
  late AnimationController _switchButtonController;
  late AnimationController _shimmerController;
  late AnimationController _errorController;
  late AnimationController _progressController;

  late Animation<double> _appBarFade;
  late Animation<Offset> _appBarSlide;
  late Animation<double> _switchButtonScale;
  late Animation<double> _switchButtonGlow;
  late Animation<double> _shimmer;
  late Animation<double> _errorFade;
  late Animation<Offset> _errorSlide;
  late Animation<double> _progressValue;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initWebView();

    // Trigger entrance animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appBarController.forward();
    });
  }

  void _setupAnimations() {
    // AppBar entrance
    _appBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _appBarFade = CurvedAnimation(
      parent: _appBarController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _appBarSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _appBarController,
      curve: Curves.easeOutCubic,
    ));

    // Switch button idle pulse + glow
    _switchButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _switchButtonScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _switchButtonController, curve: Curves.easeInOut),
    );
    _switchButtonGlow = Tween<double>(begin: 0.35, end: 0.75).animate(
      CurvedAnimation(parent: _switchButtonController, curve: Curves.easeInOut),
    );

    // Shimmer for loading skeleton
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _shimmer = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    // Error panel
    _errorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _errorFade = CurvedAnimation(parent: _errorController, curve: Curves.easeOut);
    _errorSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _errorController, curve: Curves.easeOutCubic));

    // Smooth progress bar
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _progressValue = Tween<double>(begin: 0, end: 1).animate(_progressController);
  }

  @override
  void dispose() {
    _appBarController.dispose();
    _switchButtonController.dispose();
    _shimmerController.dispose();
    _errorController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _initWebView() {
    final uri = Uri.https(
      'smartcrm.pk',
      '/login.aspx',
      {'UN': widget.username, 'PS': widget.password},
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _loadProgress = progress / 100.0);
              _progressController.animateTo(
                _loadProgress,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
                _loadProgress = 0.0;
              });
              _progressController.reset();
              _shimmerController.repeat();
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _loadProgress = 1.0;
              });
              _shimmerController.stop();
              _progressController.animateTo(1.0).then((_) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _progressController.reset();
                });
              });
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
              _shimmerController.stop();
              _errorController.forward(from: 0);
            }
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(uri);
  }

  void _switchToAppView() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => DashboardScreen(
          userId: widget.userId,
          cCode: widget.cCode,
          username: widget.username,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _reload() {
    HapticFeedback.lightImpact();
    _errorController.reverse().then((_) {
      setState(() {
        _hasError = false;
        _isLoading = true;
        _loadProgress = 0.0;
      });
      _shimmerController.repeat();
      _controller.reload();
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        children: [
          // ── Background mesh ──
          _buildBackground(),

          // ── Main content column ──
          Column(
            children: [
              SlideTransition(
                position: _appBarSlide,
                child: FadeTransition(
                  opacity: _appBarFade,
                  child: _buildAppBar(),
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ],
      ),
    );
  }

  // ── Atmospheric background ─────────────────────────────────────────────────
  Widget _buildBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Radial blob top-left
          Positioned(
            top: -80,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _teal.withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Radial blob bottom-right
          Positioned(
            bottom: -100,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _tealGlow.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            colors: [
  Color(0xFF0E637A),
  Color(0xFF0E637A),
], ),
            border: Border(
              bottom: BorderSide(color: _border.withOpacity(0.8), width: 1),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    // ── Brand mark ──
                    _BrandMark(),

                    const SizedBox(width: 14),

                    // ── Title ──
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SmartCRM',
                          style: GoogleFonts.spaceGroteskTextTheme().apply().bodyMedium?.copyWith(
                                color: _textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: 0.2,
                              ) ??
                              TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                        ),
                        Text(
                          'Web Portal',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: _textSecondary,
                            fontSize: 10.5,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // ── Loading indicator (compact dot) ──
                    if (_isLoading && !_hasError)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: _LoadingDots(),
                      ),

                    // ── Switch to App button ──
                    AnimatedBuilder(
                      animation: _switchButtonController,
                      builder: (_, child) => Transform.scale(
                        scale: _switchButtonScale.value,
                        child: child,
                      ),
                      child: AnimatedBuilder(
                        animation: _switchButtonController,
                        builder: (_, __) => GestureDetector(
                          onTap: _switchToAppView,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF59E0B), Color(0xFFEF7C00)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: _amber.withOpacity(
                                      _switchButtonGlow.value),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.grid_view_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'App',
                                  style: GoogleFonts.dmSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return Stack(
      children: [
        // WebView — always in tree so it loads
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(0),
            topRight: Radius.circular(0),
          ),
          child: Opacity(
            opacity: (!_hasError) ? 1.0 : 0.0,
            child: WebViewWidget(controller: _controller),
          ),
        ),

        // Error overlay
        if (_hasError)
          FadeTransition(
            opacity: _errorFade,
            child: SlideTransition(
              position: _errorSlide,
              child: _buildErrorState(),
            ),
          ),

        // Progress bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: _progressController,
            builder: (_, __) {
              final v = _progressValue.value;
              if (v <= 0 || v >= 1) return const SizedBox.shrink();
              return SizedBox(
                height: 2,
                child: Stack(
                  children: [
                    // Track
                    Container(color: _border),
                    // Fill
                    FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_teal, _tealGlow],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _tealGlow.withOpacity(0.7),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Error State ────────────────────────────────────────────────────────────
  Widget _buildErrorState() {
    return Container(
      color: _ink,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing icon container
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _surface,
                  border: Border.all(color: _border, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: _teal.withOpacity(0.15),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
                  size: 38,
                  color: _teal.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Connection Lost',
                style: GoogleFonts.dmSans(
                  color: _textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'The portal couldn\'t be reached.\nCheck your network and try again.',
                style: GoogleFonts.dmSans(
                  color: _textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Retry
                  _GlowButton(
                    label: 'Retry',
                    icon: Icons.refresh_rounded,
                    onTap: _reload,
                    color: _teal,
                    glowColor: _teal,
                  ),
                  const SizedBox(width: 14),
                  // Switch to App
                  _GlowButton(
                    label: 'Use App View',
                    icon: Icons.grid_view_rounded,
                    onTap: _switchToAppView,
                    color: _amberDeep,
                    glowColor: _amber,
                    outlined: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Brand Mark Widget ──────────────────────────────────────────────────────
class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E637A), Color(0xFF0BE0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E637A).withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.language_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

// ── Animated Loading Dots ──────────────────────────────────────────────────
class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final phase = ((_c.value * 3) - i).clamp(0.0, 1.0);
            final opacity = (phase < 0.5)
                ? phase * 2
                : (1 - phase) * 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity.clamp(0.2, 1.0),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0BE0FF),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ── Reusable Glow Button ───────────────────────────────────────────────────
class _GlowButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color glowColor;
  final bool outlined;

  const _GlowButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
    required this.glowColor,
    this.outlined = false,
  });

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _press;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) {
        _press.reverse();
        widget.onTap();
      },
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
            color: widget.outlined ? Colors.transparent : widget.color,
            gradient: widget.outlined
                ? null
                : LinearGradient(
                    colors: [
                      widget.color,
                      widget.color.withOpacity(0.75),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(14),
            border: widget.outlined
                ? Border.all(color: widget.color, width: 1.5)
                : null,
            boxShadow: widget.outlined
                ? []
                : [
                    BoxShadow(
                      color: widget.glowColor.withOpacity(0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: widget.outlined ? widget.color : Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: GoogleFonts.dmSans(
                  color: widget.outlined ? widget.color : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}