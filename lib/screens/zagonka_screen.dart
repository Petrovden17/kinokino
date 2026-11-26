import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_forge/flutter_inappwebview_forge.dart';

class ZagonkaScreen extends StatefulWidget {
  const ZagonkaScreen({
    super.key,
    required this.title,
    this.kinopoiskId,
    this.isSeries = false,
  });

  final String title;
  final int? kinopoiskId;
  final bool isSeries;

  @override
  State<ZagonkaScreen> createState() => _ZagonkaScreenState();
}

class _ZagonkaScreenState extends State<ZagonkaScreen> {
  InAppWebViewController? _bootstrapController;
  bool _pageLoaded = false;
  bool _playerWindowOpened = false;
  bool _isFullscreen = false;
  String? _error;
  final Set<String> _openedPlayerUrls = <String>{};

  WebUri get _pageUrl {
    final id = widget.kinopoiskId;
    if (id == null || id <= 0) return WebUri('https://www.kinokino.win/');
    final type = widget.isSeries ? 'series' : 'film';
    return WebUri('https://www.kinokino.win/$type/$id/');
  }

  InAppWebViewSettings get _webSettings => InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        hardwareAcceleration: true,
        enableEncryptedMedia: true,
        enableMedia: true,
        isElementFullscreenEnabled: true,
        supportMultipleWindows: true,
        useHybridComposition: defaultTargetPlatform == TargetPlatform.android,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        transparentBackground: false,
        supportZoom: false,
      );

  Future<void> _enterFullscreen() async {
    if (!mounted || _isFullscreen) return;
    _isFullscreen = true;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _leaveFullscreen() async {
    if (!_isFullscreen) return;
    _isFullscreen = false;
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // The catalogue page is only a hidden bootstrap. It is never presented to
  // the user. We ask it to activate the site's own "watch/play" control;
  // Android's onCreateWindow then hands the real player window to this screen.
  Future<void> _activateSitePlayer(InAppWebViewController controller) async {
    const script = r"""
      (() => {
        if (window.__kinoPlayerLauncherInstalled) return;
        window.__kinoPlayerLauncherInstalled = true;
        const activate = () => {
          if (window.__kinoPlayerWindowRequested) return;
          const nodes = Array.from(document.querySelectorAll(
            'a,button,[role="button"],input[type="button"],input[type="submit"]'
          ));
          const candidate = nodes.find((node) => {
            const text = ((node.innerText || node.value || node.getAttribute('aria-label') || '') + ' ' +
              (node.getAttribute('title') || '')).trim().toLowerCase();
            const rect = node.getBoundingClientRect();
            const visible = rect.width > 0 && rect.height > 0 &&
              getComputedStyle(node).visibility !== 'hidden' &&
              getComputedStyle(node).display !== 'none';
            return visible && /смотреть онлайн|смотреть фильм|смотреть сери|смотреть|watch online|watch now|play|воспроизвести|запустить/.test(text);
          });
          if (candidate) {
            window.__kinoPlayerWindowRequested = true;
            candidate.click();
            console.log('[KinoKino] activated site watch control');
            return true;
          }
          return false;
        };
        let attempts = 0;
        const timer = setInterval(() => {
          attempts += 1;
          if (activate() || attempts >= 40) clearInterval(timer);
        }, 500);
        activate();
      })();
    """;
    try {
      await controller.evaluateJavascript(source: script);
    } catch (e) {
      debugPrint('[KinoKino] player activation script failed: $e');
    }
  }

  // StreamBridge watches for an actual embedded player, not the catalogue UI.
  // Direct HLS/DASH URLs are logged only because they may require session headers or DRM.
  Future<void> _installStreamBridge(InAppWebViewController controller) async {
    const script = r"""
      (() => {
        if (window.__kinoStreamBridgeInstalled) return;
        window.__kinoStreamBridgeInstalled = true;
        const sent = new Set();
        const report = (url, hint) => {
          try {
            const parsed = new URL(url, location.href);
            if (!/^https?:$/.test(parsed.protocol) || parsed.href === location.href) return;
            const key = parsed.href;
            if (sent.has(key)) return;
            const text = (hint || '').toLowerCase();
            if (!/player|video|embed|stream|kodik|alloha|collaps|videocdn|kinogo|iframe|m3u8|mpd|mp4/i.test(key + ' ' + text)) return;
            sent.add(key);
            window.flutter_inappwebview.callHandler('streamBridge', {
              kind: /\.(m3u8|mpd|mp4)(?:$|[?#])/i.test(key) ? 'media' : 'player',
              url: key,
              hint: text
            });
          } catch (_) {}
        };
        const scan = () => {
          document.querySelectorAll('iframe').forEach((frame) => {
            const rect = frame.getBoundingClientRect();
            const style = getComputedStyle(frame);
            if (rect.width < 160 || rect.height < 90 || style.display === 'none' || style.visibility === 'hidden') return;
            report(frame.src, (frame.title || '') + ' ' + (frame.id || '') + ' ' + (frame.className || ''));
          });
          try {
            performance.getEntriesByType('resource').forEach((entry) => {
              if (/\.(m3u8|mpd|mp4)(?:$|[?#])/i.test(entry.name)) report(entry.name, 'media resource');
            });
          } catch (_) {}
        };
        new MutationObserver(scan).observe(document.documentElement, {
          childList: true, subtree: true, attributes: true, attributeFilter: ['src']
        });
        try { new PerformanceObserver(scan).observe({type:'resource', buffered:true}); } catch (_) {}
        scan();
        setInterval(scan, 1800);
      })();
    """;
    try {
      await controller.evaluateJavascript(source: script);
    } catch (e) {
      debugPrint('[StreamBridge] injection failed: $e');
    }
  }

  Future<void> _handleStreamBridgeCall(List<dynamic> args) async {
    if (!mounted || args.isEmpty || args.first is! Map) return;
    final data = Map<String, dynamic>.from(args.first as Map);
    final rawUrl = data['url']?.toString() ?? '';
    final kind = data['kind']?.toString() ?? '';
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme || !{'http', 'https'}.contains(uri.scheme)) return;
    debugPrint('[StreamBridge] detected $kind: $rawUrl');
    if (kind != 'player' || _playerWindowOpened || !_openedPlayerUrls.add(rawUrl)) return;
    await _showDetectedPlayer(rawUrl);
  }

  Future<void> _showDetectedPlayer(String url) async {
    if (!mounted || _playerWindowOpened) return;
    _playerWindowOpened = true;
    await _enterFullscreen();
    if (mounted) setState(() => _error = null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (dialogContext) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _playerWindowOpened = false;
            _leaveFullscreen();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: InAppWebView(
              key: const ValueKey('kino-streambridge-player'),
              initialUrlRequest: URLRequest(url: WebUri(url)),
              initialSettings: _webSettings,
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                  handlerName: 'streamBridge',
                  callback: (args) {
                    _handleStreamBridgeCall(args);
                    return {'accepted': true};
                  },
                );
                debugPrint('[StreamBridge] player view attached');
              },
              onLoadStart: (_, uri) => debugPrint('[StreamBridge] loading player: $uri'),
              onLoadStop: (controller, uri) {
                debugPrint('[StreamBridge] player loaded: $uri');
                _installStreamBridge(controller);
                _probePlayerWindow(controller);
              },
              onReceivedError: (_, request, error) => debugPrint(
                '[StreamBridge] error main=${request.isForMainFrame}: ${error.description}; ${request.url}',
              ),
              onCloseWindow: (_) {
                _playerWindowOpened = false;
                if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
                _leaveFullscreen();
              },
              onEnterFullscreen: (_) => _enterFullscreen(),
              onExitFullscreen: (_) => _leaveFullscreen(),
              onCreateWindow: (_, nestedAction) async {
                debugPrint('[StreamBridge] blocked nested popup: ${nestedAction.request.url}');
                return false;
              },
            ),
          ),
        ),
      ),
    ).then((_) {
      _playerWindowOpened = false;
      _leaveFullscreen();
      if (mounted) setState(() {});
    });
  }

  Future<void> _probePlayerWindow(InAppWebViewController controller) async {
    const script = r"""
      (() => {
        const videos = Array.from(document.querySelectorAll('video')).map((v) => ({
          src: v.currentSrc || v.src || '',
          readyState: v.readyState,
          networkState: v.networkState,
          paused: v.paused,
          width: v.videoWidth,
          height: v.videoHeight,
          visible: v.getBoundingClientRect().width > 0 &&
            v.getBoundingClientRect().height > 0
        }));
        const frames = Array.from(document.querySelectorAll('iframe')).map((f) => ({
          src: f.src || '',
          width: f.clientWidth,
          height: f.clientHeight
        }));
        const playerFrameCount = frames.filter((f) =>
          /player|video|embed|stream|kinogo|kodik|alloha|videocdn/i.test(f.src) && f.width > 0 && f.height > 0
        ).length;
        return JSON.stringify({
          url: location.href,
          title: document.title,
          readyState: document.readyState,
          videoCount: videos.length,
          videos,
          iframeCount: frames.length,
          playerFrameCount,
          frames
        });
      })();
    """;
    for (var attempt = 1; attempt <= 8 && mounted; attempt++) {
      try {
        final result = await controller.evaluateJavascript(source: script);
        debugPrint('[KinoKino PLAYER_PROBE] attempt=$attempt $result');
      } catch (e) {
        debugPrint('[KinoKino PLAYER_PROBE] attempt=$attempt error=$e');
      }
      if (attempt < 8) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<bool> _showPlayerWindow(CreateWindowAction action) async {
    if (!mounted || _playerWindowOpened) {
      debugPrint('[KinoKino] ignoring extra popup: ${action.request.url}');
      return false;
    }
    _playerWindowOpened = true;
    await _enterFullscreen();
    if (mounted) setState(() => _error = null);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (dialogContext) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _playerWindowOpened = false;
            _leaveFullscreen();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: InAppWebView(
              key: ValueKey('kino-player-window-${action.windowId}'),
              windowId: action.windowId,
              initialSettings: _webSettings,
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                  handlerName: 'streamBridge',
                  callback: (args) {
                    _handleStreamBridgeCall(args);
                    return {'accepted': true};
                  },
                );
                debugPrint('[KinoKino] actual player popup attached');
              },
              onLoadStart: (_, url) =>
                  debugPrint('[KinoKino player] loading: $url'),
              onLoadStop: (controller, url) async {
                debugPrint('[KinoKino player] loaded: $url');
                await _installStreamBridge(controller);
                _probePlayerWindow(controller);
              },
              onReceivedError: (_, request, error) => debugPrint(
                '[KinoKino player] error main=${request.isForMainFrame}: ${error.description}; ${request.url}',
              ),
              onReceivedHttpError: (_, request, response) => debugPrint(
                '[KinoKino player] HTTP ${response.statusCode} main=${request.isForMainFrame}: ${request.url}',
              ),
              onCloseWindow: (_) {
                debugPrint('[KinoKino] player popup closed');
                _playerWindowOpened = false;
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                }
                _leaveFullscreen();
              },
              onEnterFullscreen: (_) => _enterFullscreen(),
              onExitFullscreen: (_) => _leaveFullscreen(),
              // Block advertising popups spawned by the player itself.
              onCreateWindow: (_, nestedAction) async {
                debugPrint('[KinoKino] blocked nested popup: ${nestedAction.request.url}');
                return false;
              },
            ),
          ),
        ),
      ),
    ).then((_) {
      _playerWindowOpened = false;
      _leaveFullscreen();
      if (mounted) setState(() {});
    });
    return true;
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
          // Keep the source page alive for cookies/session and popup creation,
          // but never expose its catalogue or film page on screen.
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                // Keep the source page fully laid out: many embedded players
                // refuse to initialize when their parent WebView is 1x1.
                opacity: 0.01,
                child: InAppWebView(
                initialUrlRequest: URLRequest(url: _pageUrl),
                initialSettings: _webSettings,
                onWebViewCreated: (controller) {
                  _bootstrapController = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'streamBridge',
                    callback: (args) {
                      _handleStreamBridgeCall(args);
                      return {'accepted': true};
                    },
                  );
                },
                onLoadStop: (controller, url) async {
                  debugPrint('[KinoKino bootstrap] loaded: $url');
                  await _installStreamBridge(controller);
                  if (!_pageLoaded) {
                    _pageLoaded = true;
                    await _activateSitePlayer(controller);
                    if (mounted) setState(() {});
                  }
                },
                onCreateWindow: (_, action) => _showPlayerWindow(action),
                onReceivedError: (_, request, error) {
                  debugPrint(
                    '[KinoKino bootstrap] error main=${request.isForMainFrame}: ${error.description}; ${request.url}',
                  );
                  if (request.isForMainFrame == true && mounted) {
                    setState(() => _error =
                        'Не удалось подготовить плеер. Проверь подключение и попробуй ещё раз.');
                  }
                },
                  onConsoleMessage: (_, message) =>
                      debugPrint('[KinoKino bootstrap console] ${message.message}'),
                ),
              ),
            ),
          ),
          if (!_playerWindowOpened)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _error ??
                          (_pageLoaded
                              ? 'Запускаем встроенный плеер…'
                              : 'Подключаем плеер…'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () async {
                          setState(() {
                            _error = null;
                            _pageLoaded = false;
                          });
                          await _bootstrapController?.loadUrl(
                            urlRequest: URLRequest(url: _pageUrl),
                          );
                        },
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text(
                          'Повторить',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
