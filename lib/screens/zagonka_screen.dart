import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ZagonkaScreen extends StatefulWidget {
  const ZagonkaScreen({super.key, required this.title});

  final String title;

  @override
  State<ZagonkaScreen> createState() => _ZagonkaScreenState();
}

class _ZagonkaScreenState extends State<ZagonkaScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String? _pageError;
  String _pageTitle = 'Zagonka';

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _goForward() async {
    final controller = _controller;
    if (controller != null && await controller.canGoForward()) {
      await controller.goForward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: 'Вперёд',
            onPressed: _goForward,
            icon: const Icon(Icons.arrow_forward),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: () => _controller?.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: _progress > 0 && _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('https://8.zagonka.xyz/')),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              useShouldOverrideUrlLoading: true,
              supportMultipleWindows: false,
              transparentBackground: false,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                _pageError = null;
                _progress = 0;
              });
            },
            onProgressChanged: (controller, progress) {
              if (mounted) setState(() => _progress = progress / 100);
            },
            onLoadStop: (controller, url) async {
              final title = await controller.getTitle();
              if (!mounted) return;
              setState(() {
                _progress = 1;
                _pageTitle = title?.trim().isNotEmpty == true ? title! : 'Zagonka';
              });
            },
            onReceivedError: (controller, request, error) {
              if (!request.isForMainFrame || !mounted) return;
              setState(() {
                _pageError = 'Не удалось загрузить страницу Zagonka. Проверь подключение и нажми «Обновить».';
              });
            },
            onCreateWindow: (controller, action) async => false,
          ),
          if (_pageError != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_pageError!)),
                      IconButton(
                        tooltip: 'Повторить',
                        onPressed: () {
                          setState(() => _pageError = null);
                          _controller?.reload();
                        },
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
