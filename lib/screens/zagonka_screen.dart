import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_forge/flutter_inappwebview_forge.dart';
import 'package:url_launcher/url_launcher.dart';

class ZagonkaScreen extends StatefulWidget {
  const ZagonkaScreen({super.key, required this.title, this.kinopoiskId, this.isSeries = false});

  final String title;
  final int? kinopoiskId;
  final bool isSeries;

  @override
  State<ZagonkaScreen> createState() => _ZagonkaScreenState();
}

class _ZagonkaScreenState extends State<ZagonkaScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String? _pageError;
  bool _isFullscreen = false;

  WebUri get _primaryUrl {
    final id = widget.kinopoiskId;
    if (id == null || id <= 0) return WebUri('https://www.kinokino.win/');
    final kind = widget.isSeries ? 'series' : 'film';
    return WebUri('https://www.kinokino.win/$kind/$id/');
  }

  Future<void> _setFullscreen(bool enabled) async {
    if (!mounted || _isFullscreen == enabled) return;
    setState(() => _isFullscreen = enabled);
    if (enabled) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const []);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _openExternalBrowser() async {
    final opened = await launchUrl(_primaryUrl, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть страницу во внешнем браузере.')),
      );
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await _setFullscreen(false);
      return;
    }
    await _controller?.evaluateJavascript(source: r"""
      (() => {
        const video = document.querySelector('video');
        const frame = document.querySelector('iframe[allowfullscreen], iframe');
        const target = video || frame || document.documentElement;
        if (target && target.requestFullscreen) {
          const result = target.requestFullscreen();
          if (result && result.catch) result.catch(() => {});
        }
      })();
    """);
    await _setFullscreen(true);
  }

  Future<void> _goBack() async {
    if (_isFullscreen) {
      await _setFullscreen(false);
      return;
    }
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: _primaryUrl),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              hardwareAcceleration: true,
              enableEncryptedMedia: true,
              enableMedia: true,
              isElementFullscreenEnabled: true,
              useShouldOverrideUrlLoading: true,
              // Keep window.open navigations in the current WebView. Some video
              // providers create an about:blank popup and assign its URL later;
              // intercepting only the initial request leaves the player black.
              supportMultipleWindows: false,
              javaScriptCanOpenWindowsAutomatically: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              // Texture-layer composition avoids a known class of white WebView surfaces on some Android GPU builds.
              useHybridComposition: false,
              transparentBackground: false,
              supportZoom: false,
              useWideViewPort: false,
              loadWithOverviewMode: false,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onLoadStart: (controller, url) {
              debugPrint('[KinoKino WebView] load start: $url');
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
              if (!mounted) return;
              setState(() => _progress = 1);
              try {
                final probe = await controller.evaluateJavascript(source: r'''(() => JSON.stringify({ready:document.readyState,title:document.title,url:location.href,bodyText:(document.body?.innerText||'').slice(0,300),iframes:Array.from(document.querySelectorAll('iframe')).map(x=>x.src).slice(0,8),videos:Array.from(document.querySelectorAll('video')).map(x=>({src:x.currentSrc,ready:x.readyState,error:x.error?.code})).slice(0,4)}))()''');
                debugPrint('[KinoKino WebView] page probe: $probe');
              } catch (e) {
                debugPrint('[KinoKino WebView] page probe failed: $e');
              }
            },
            onConsoleMessage: (controller, message) {
              debugPrint('[KinoKino WebView console] ${message.message}');
            },
            onEnterFullscreen: (controller) => _setFullscreen(true),
            onExitFullscreen: (controller) => _setFullscreen(false),
            onReceivedError: (controller, request, error) {
              debugPrint('[KinoKino WebView] resource error main=${request.isForMainFrame}: ${error.description} (${error.type}) ${request.url}');
              if (request.isForMainFrame != true || !mounted) return;
              setState(() {
                _pageError = 'Не удалось загрузить страницу KinoKino. Проверь подключение и нажми «Обновить».';
              });
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              if ((errorResponse.statusCode ?? 0) >= 400) {
                debugPrint('[KinoKino WebView] HTTP resource ${errorResponse.statusCode} main=${request.isForMainFrame}: ${request.url}');
              }
              if (request.isForMainFrame != true || !mounted) return;
              if ((errorResponse.statusCode ?? 0) >= 400) {
                debugPrint('[KinoKino WebView] HTTP ${errorResponse.statusCode}: ${request.url}');
                setState(() => _pageError = 'KinoKino вернул ошибку HTTP ${errorResponse.statusCode}. Нажми «Обновить», чтобы попробовать снова.');
              }
            },
          ),
          if (_progress > 0 && _progress < 1)
            Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(value: _progress, minHeight: 2),
            ),
          if (!_isFullscreen)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _overlayButton(Icons.arrow_back, 'Назад', _goBack),
                      const SizedBox(width: 8),
                      Expanded(
                        child: IgnorePointer(
                          child: Container(
                            margin: const EdgeInsets.only(top: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.58),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${widget.title} · KinoKino',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _overlayButton(Icons.open_in_browser, 'Открыть в браузере', _openExternalBrowser),
                      const SizedBox(width: 4),
                      _overlayButton(Icons.fullscreen, 'На весь экран', _toggleFullscreen),
                    ],
                  ),
                ),
              ),
            )
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${widget.title} · KinoKino',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _overlayButton(Icons.fullscreen_exit, 'Выйти из полного экрана', _toggleFullscreen),
                  ],
                ),
              ),
            ),
          if (_pageError != null)
            Center(
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF202020),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_pageError!, style: const TextStyle(color: Colors.white))),
                    IconButton(
                      tooltip: 'Повторить',
                      onPressed: () {
                        setState(() => _pageError = null);
                        _controller?.loadUrl(urlRequest: URLRequest(url: _primaryUrl));
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _overlayButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}
