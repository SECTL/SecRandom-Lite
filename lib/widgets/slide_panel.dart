import 'package:flutter/material.dart';

class SlidePanel extends StatefulWidget {
  final Widget child;
  final VoidCallback? onClose;

  const SlidePanel({
    super.key,
    required this.child,
    this.onClose,
  });

  @override
  State<SlidePanel> createState() => _SlidePanelState();
}

class _SlidePanelState extends State<SlidePanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward();
  }

  void close() {
    _controller.reverse().then((_) {
      widget.onClose?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: close,
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        child: GestureDetector(
          onTap: () {},
          child: Align(
            alignment: Alignment.centerRight,
            child: SlideTransition(
              position: _offsetAnimation,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(-4, 0),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: close,
                            tooltip: '返回',
                          ),
                          Expanded(
                            child: Text(
                              '控制面板',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: widget.child,
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
}

class SlidePanelButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;

  const SlidePanelButton({
    super.key,
    required this.onTap,
    this.tooltip = '打开控制面板',
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 80,
      child: FloatingActionButton(
        heroTag: 'slide_panel_fab',
        onPressed: onTap,
        tooltip: tooltip,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.settings),
      ),
    );
  }
}

class SlidePanelOverlay {
  static OverlayEntry? _overlayEntry;

  static void show({
    required BuildContext context,
    required Widget child,
  }) {
    _overlayEntry = OverlayEntry(
      builder: (context) => _SlidePanelOverlay(
        onClose: hide,
        child: child,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  static bool get isShowing => _overlayEntry != null;
}

class _SlidePanelOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback onClose;

  const _SlidePanelOverlay({
    required this.child,
    required this.onClose,
  });

  @override
  State<_SlidePanelOverlay> createState() => _SlidePanelOverlayState();
}

class _SlidePanelOverlayState extends State<_SlidePanelOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward();
  }

  void close() {
    _controller.reverse().then((_) {
      widget.onClose();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth * 0.85;

    return Positioned.fill(
      child: GestureDetector(
        onTap: close,
        child: Material(
          color: Colors.black.withValues(alpha: 0.5),
          child: GestureDetector(
            onTap: () {},
            child: Align(
              alignment: Alignment.centerRight,
              child: SlideTransition(
                position: _offsetAnimation,
                child: Container(
                  width: panelWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(-4, 0),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, size: 20),
                              onPressed: close,
                              tooltip: '返回',
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '控制面板',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: widget.child,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
