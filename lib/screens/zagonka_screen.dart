import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_forge/flutter_inappwebview_forge.dart';

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
  bool _usingFallback = false;
  String _playerDiagnostics = 'Пока не проверено';

  WebUri get _primaryUrl {
    final id = widget.kinopoiskId;
    if (id == null || id <= 0) return WebUri('https://kinokino.win/');
    final kind = widget.isSeries ? 'series' : 'film';
    return WebUri('https://kinokino.win/$kind/$id/');
  }

  Future<void> _switchToFallback() async {
    if (_usingFallback || !mounted) return;
    setState(() {
      _usingFallback = true;
      _pageError = null;
      _progress = 0;
    });
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri('https://8.zagonka.xyz/')));
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

  Future<void> _inspectPlayers(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(source: r"""
        (() => {
          const found = [];
          const add = (kind, value) => {
            if (!value) return;
            try {
              const url = new URL(value, document.baseURI).href;
              if (!found.some(item => item.url === url)) found.push({kind, url});
            } catch (_) {}
          };
          document.querySelectorAll('iframe').forEach((el, i) => {
            add('iframe ' + (i + 1), el.getAttribute('src') || el.getAttribute('data-src') || el.getAttribute('data-lazy-src'));
          });
          document.querySelectorAll('video').forEach((el, i) => {
            add('video ' + (i + 1), el.currentSrc || el.getAttribute('src'));
            el.querySelectorAll('source').forEach(source => add('video source', source.getAttribute('src')));
          });
          document.querySelectorAll('embed, object').forEach((el, i) => add('media ' + (i + 1), el.getAttribute('src') || el.getAttribute('data')));
          return JSON.stringify(found);
        })();
      """);
      final value = result is String ? result : result?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _playerDiagnostics = value.isEmpty || value == '[]'
            ? 'Медиассылки пока не найдены. Нажми «Обновить поиск» после загрузки страницы или запуска видео.'
            : value;
      });
      debugPrint('KINOKINO_PLAYER_DIAGNOSTICS: $_playerDiagnostics');
    } catch (error) {
      if (mounted) setState(() => _playerDiagnostics = 'Ошибка чтения страницы: $error');
    }
  }

  Future<void> _hideSiteBranding(InAppWebViewController controller) async {
    // Hide only the small site-brand label; do not remove the player or its controls.
    await controller.evaluateJavascript(source: r"""
      (() => {
        let viewport = document.querySelector('meta[name="viewport"]');
        if (!viewport) {
          viewport = document.createElement('meta');
          viewport.name = 'viewport';
          document.head.appendChild(viewport);
        }
        viewport.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
        const mobileLayout = document.getElementById('kinokino-mobile-layout') || document.createElement('style');
        mobileLayout.id = 'kinokino-mobile-layout';
        mobileLayout.textContent = 'html,body{width:100%!important;max-width:100vw!important;overflow-x:hidden!important;margin:0!important} video,iframe,embed,object{max-width:100%!important}';
        if (!mobileLayout.parentNode) document.head.appendChild(mobileLayout);
        const hideBrand = () => {
          const nodes = Array.from(document.querySelectorAll('body *'));
          for (const node of nodes) {
            if (node.children.length > 2) continue;
            const label = (node.innerText || node.textContent || '').replace(/\s+/g, ' ').trim();
            if (!/^(?:az|аз)\s*фильм$/i.test(label)) continue;
            const rect = node.getBoundingClientRect();
            if (rect.width > 0 && rect.height > 0 && rect.height < 120) {
              node.style.setProperty('display', 'none', 'important');
              node.setAttribute('data-kinokino-hidden-brand', 'true');
            }
          }
        };
        hideBrand();
        if (!window.__kinokinoBrandObserver) {
          window.__kinokinoBrandObserver = new MutationObserver(hideBrand);
          window.__kinokinoBrandObserver.observe(document.documentElement, {
            childList: true, subtree: true, characterData: true
          });
        }
      })();
    """);
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
              isElementFullscreenEnabled: true,
              useShouldOverrideUrlLoading: true,
              supportMultipleWindows: false,
              transparentBackground: false,
              supportZoom: false,
              useWideViewPort: false,
              loadWithOverviewMode: false,
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
              await _hideSiteBranding(controller);
              await _inspectPlayers(controller);
              if (!mounted) return;
              setState(() => _progress = 1);
            },
            onEnterFullscreen: (controller) => _setFullscreen(true),
            onExitFullscreen: (controller) => _setFullscreen(false),
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame != true || !mounted) return;
              if (!_usingFallback) {
                _switchToFallback();
              } else {
                setState(() {
                  _pageError = 'Не удалось загрузить KinoKino и резервную Zagonka. Проверь подключение и нажми «Обновить».';
                });
              }
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              if (request.isForMainFrame != true || !mounted) return;
              if (!_usingFallback && (errorResponse.statusCode ?? 0) >= 400) {
                _switchToFallback();
              } else if (_usingFallback && (errorResponse.statusCode ?? 0) >= 400) {
                setState(() => _pageError = 'Оба источника вернули ошибку загрузки. Нажми «Обновить», чтобы попробовать снова.');
              }
            },
            onCreateWindow: (controller, action) async => false,
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
                              '${widget.title} · ${_usingFallback ? 'Zagonka' : 'KinoKino'}',
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
                            '${widget.title} · ${_usingFallback ? 'Zagonka' : 'FixtyFlux'}',
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
          if (!_isFullscreen)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Диагностика видеоплеера',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Обновить поиск',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              final controller = _controller;
                              if (controller != null) _inspectPlayers(controller);
                            },
                            icon: const Icon(Icons.refresh, color: Colors.white),
                          ),
                          IconButton(
                            tooltip: 'Скопировать результат',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Clipboard.setData(ClipboardData(text: _playerDiagnostics)),
                            icon: const Icon(Icons.copy, color: Colors.white),
                          ),
                        ],
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 92),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _playerDiagnostics,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                        if (_usingFallback) {
                          _controller?.loadUrl(urlRequest: URLRequest(url: WebUri('https://8.zagonka.xyz/')));
                        } else {
                          _controller?.loadUrl(urlRequest: URLRequest(url: _primaryUrl));
                        }
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
