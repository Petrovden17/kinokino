import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

class ZagonkaScreen extends StatefulWidget {
  const ZagonkaScreen({super.key, this.searchTitle});

  final String? searchTitle;

  @override
  State<ZagonkaScreen> createState() => _ZagonkaScreenState();
}

class _ZagonkaScreenState extends State<ZagonkaScreen> {
  final WebviewController _controller = WebviewController();
  StreamSubscription<LoadingState>? _loadingSubscription;
  bool _initialized = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final runtime = await WebviewController.getWebViewVersion();
      if (runtime == null) {
        throw Exception(
          'На этом компьютере не найден Microsoft Edge WebView2 Runtime. '
          'Установи WebView2 Runtime и перезапусти KinoKino.',
        );
      }

      _loadingSubscription = _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() => _loading = state == LoadingState.loading);
      });

      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
      await _controller.setBackgroundColor(const Color(0xFF080D19));
      await _controller.loadUrl('https://8.zagonka.xyz/');

      if (mounted) {
        setState(() {
          _initialized = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _goBack() async {
    try {
      await _controller.goBack();
    } catch (_) {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _reload() async {
    try {
      setState(() => _loading = true);
      await _controller.reload();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Не удалось обновить страницу: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _loadingSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zagonka'),
        actions: [
          IconButton(
            tooltip: 'Назад',
            onPressed: _initialized ? _goBack : null,
            icon: const Icon(Icons.arrow_back),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _initialized ? _reload : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_initialized)
            Positioned.fill(
              child: Webview(
                _controller,
                permissionRequested: (url, kind, isUserInitiated) async =>
                    WebviewPermissionDecision.deny,
              ),
            ),
          if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.public_off, size: 48),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        _initialize();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
