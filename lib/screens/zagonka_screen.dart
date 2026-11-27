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
  int? _playerWindowId;
  bool _isFullscreen = false;
  String? _error;

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
  // Keep the real site's launch control, but visually isolate it. The user
  // taps the original DOM element, preserving a trusted gesture and the site's
  // cookies/referrer/session checks. Never synthesize an automatic click.
  Future<void> _activateSitePlayer(InAppWebViewController controller) async {
    const script = r"""
      (() => {
        const isolate = () => {
          const nodes = Array.from(document.querySelectorAll(
            'a,button,[role="button"],input[type="button"],input[type="submit"]'
          ));
          const candidate = nodes.find((node) => {
            const text = ((node.innerText || node.value || node.getAttribute('aria-label') || '') + ' ' +
              (node.getAttribute('title') || '')).trim().toLowerCase();
            const rect = node.getBoundingClientRect();
            const style = getComputedStyle(node);
            return rect.width > 0 && rect.height > 0 &&
              style.visibility !== 'hidden' && style.display !== 'none' &&
              /смотреть онлайн|смотреть фильм|смотреть сери|смотреть|watch online|watch now|play|воспроизвести|запустить/.test(text);
          });
          if (!candidate) return false;
          let branch = candidate;
          while (branch && branch !== document.body) {
            const parent = branch.parentElement;
            if (!parent) break;
            for (const sibling of Array.from(parent.children)) {
              if (sibling !== branch) sibling.style.setProperty('visibility', 'hidden', 'important');
            }
            branch.style.setProperty('visibility', 'visible', 'important');
            branch = parent;
          }
          document.documentElement.style.setProperty('background', '#000', 'important');
          document.body.style.setProperty('background', '#000', 'important');
          Object.entries({
            position:'fixed', left:'50%', top:'50%', transform:'translate(-50%, -50%)',
            'z-index':'2147483647', visibility:'visible', opacity:'1',
            'pointer-events':'auto', 'min-width':'220px', 'min-height':'52px',
            'font-size':'16px', padding:'14px 24px', 'border-radius':'12px',
            background:'#202020', color:'#fff', border:'1px solid #666',
            'box-shadow':'0 4px 24px #000'
          }).forEach(([key,value]) => candidate.style.setProperty(key,value,'important'));
          console.log('[KinoKino] isolated original launch control; waiting for user gesture');
          return true;
        };
        if (isolate()) return;
        let attempts = 0;
        const timer = setInterval(() => {
          attempts += 1;
          if (isolate() || attempts >= 40) clearInterval(timer);
        }, 500);
        new MutationObserver(() => isolate()).observe(document.documentElement, {childList:true,subtree:true});
      })();
    """;
    try {
      await controller.evaluateJavascript(source: script);
    } catch (e) {
      debugPrint('[KinoKino] launch control isolation failed: $e');
    }
  }

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
            const frameUrl = new URL(frame.src || '', location.href);
            // Never promote the catalogue/site page itself. Only a visible,
            // external embedded frame can become the standalone player view.
            if (frameUrl.origin === location.origin ||
                /(^|\\.)kinokino\\.win$/i.test(frameUrl.hostname) ||
                /doubleclick|adservice|analytics|metrika|captcha/i.test(frameUrl.hostname)) return;
            report(frameUrl.href, (frame.title || '') + ' ' + (frame.id || '') + ' ' + (frame.className || '') + ' iframe');
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
    if (args.isEmpty || args.first is! Map) return;
    final data = Map<String, dynamic>.from(args.first as Map);
    final rawUrl = data['url']?.toString() ?? '';
    final kind = data['kind']?.toString() ?? '';
    debugPrint('[StreamBridge] detected $kind: $rawUrl');
    // Keep the source browsing context. A bare iframe URL in a new WebView
    // can lose the site's opener, referrer and session state.
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

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _playerWindowId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _playerWindowId != null) {
          setState(() {
            _playerWindowId = null;
            _playerWindowOpened = false;
          });
          _leaveFullscreen();
        }
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Keep the source page alive for cookies/session and popup creation,
          // but never expose its catalogue or film page on screen.
          // Keep the opener WebView alive for cookies/session and the native
          // windowId, but never let its catalogue page paint over the real player.
          // Opacity preserves the platform view; Offstage/removal can destroy the
          // WebView window relationship on Android.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _playerWindowId != null,
              child: Opacity(
                opacity: _playerWindowId == null ? 1 : 0,
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
                // Attach the original popup WebView in this screen. It
                // retains opener/session/referrer state and the site's user gesture.
                onCreateWindow: (_, action) async {
                  if (!mounted || _playerWindowId != null) return false;
                  debugPrint('[KinoKino] attaching original player window: ${action.request.url}');
                  setState(() {
                    _playerWindowId = action.windowId;
                    _playerWindowOpened = true;
                  });
                  return true;
                },
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
          if (_playerWindowId != null)
            Positioned.fill(
              child: InAppWebView(
                key: ValueKey('kino-inline-player-$_playerWindowId'),
                windowId: _playerWindowId,
                initialSettings: _webSettings,
                onLoadStart: (_, url) => debugPrint('[KinoKino player] loading: $url'),
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
                  if (mounted) setState(() {
                    _playerWindowId = null;
                    _playerWindowOpened = false;
                  });
                  _leaveFullscreen();
                },
                onEnterFullscreen: (_) => _enterFullscreen(),
                onExitFullscreen: (_) => _leaveFullscreen(),
                onCreateWindow: (_, nested) async {
                  debugPrint('[KinoKino player] blocked nested popup: ${nested.request.url}');
                  return false;
                },
              ),
            ),
          if (!_playerWindowOpened && !_pageLoaded)
            const Positioned.fill(
              child: ColoredBox(color: Colors.black),
            ),
          if (!_playerWindowOpened && !_pageLoaded)
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
      ),
    );
  }
}
