import 'dart:collection';
import 'dart:typed_data';

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
  bool _playerLoading = false;
  bool _playerWindowOpened = false;
  int? _playerWindowId;
  bool _isFullscreen = false;
  int _sourceAttemptIndex = 0;
  String? _error;

  static const List<String> _playerSourceHosts = <String>[
    'www.kinokino.win',
    'ggpoisk.ru',
    'sspoisk.ru',
    'kinobox.tv',
  ];

  WebUri _urlForSource(int index) {
    final id = widget.kinopoiskId;
    final host = _playerSourceHosts[index];
    if (id == null || id <= 0) return WebUri('https://$host/');
    if (host == 'kinobox.tv') {
      final type = widget.isSeries ? 'serials' : 'films';
      return WebUri('https://kinobox.tv/#/$type/$id');
    }
    final type = widget.isSeries ? 'series' : 'film';
    return WebUri('https://$host/$type/$id/');
  }

  WebUri get _pageUrl => _urlForSource(_sourceAttemptIndex);

  Future<void> _selectPlayerSource(int index) async {
    if (!mounted || index < 0 || index >= _playerSourceHosts.length ||
        index == _sourceAttemptIndex) return;
    setState(() {
      _sourceAttemptIndex = index;
      _playerWindowId = null;
      _playerWindowOpened = false;
      _pageLoaded = false;
      _playerLoading = true;
      _error = null;
    });
    await _leaveFullscreen();
    await _bootstrapController?.loadUrl(
      urlRequest: URLRequest(url: _urlForSource(index)),
    );
  }

  bool _isAdvertisingUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return false;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return false;
    final host = uri.host.toLowerCase();
    const adHosts = <String>[
      'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
      'adnxs.com', 'taboola.com', 'outbrain.com', 'mgid.com', 'popads.net',
      'popcash.net', 'exoclick.com', 'propellerads.com', 'trafficjunky.net',
      'adsterra.com', 'pushground.com', 'onclicka.com', 'clickadu.com',
      'hilltopads.com', 'admaven.com', 'juicyads.com', 'adf.ly',
      'trafficstars.com', 'adroll.com', 'criteo.com', 'smartadserver.com',
      'adfox.ru', 'adfox.yandex.ru', 'an.yandex.ru',
      'yandexadexchange.net', 'adriver.ru', 'adriver.com',
      'adriver-sync.com', 'adriver-serv.ru',
    ];
    if (adHosts.any((domain) => domain.trim().isNotEmpty &&
        (host == domain.trim() || host.endsWith('.${domain.trim()}')))) {
      return true;
    }
    final pathParts = uri.path.toLowerCase().split('/');
    const adPathParts = <String>{
      'ad', 'ads', 'adserver', 'adservice', 'banner', 'banners',
      'popunder', 'vast', 'vpaid',
    };
    if (pathParts.any(adPathParts.contains)) return true;
    const adQueryKeys = <String>{'adtag', 'ad_tag', 'vast', 'vpaid', 'advertising'};
    return uri.queryParameters.keys.any((key) => adQueryKeys.contains(key.toLowerCase()));
  }

  // Android's native interceptor sees subresources loaded by the page and
  // cross-origin player iframes. Keep the callback synchronous and lightweight.
  final Set<String> _loggedBlockedAdResources = <String>{};

  WebResourceResponse? _interceptAdResource(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) {
    if (defaultTargetPlatform != TargetPlatform.android) return null;

    final rawUrl = request.url.toString();
    // Do not apply generic EasyList rules to media/player requests. Some
    // providers serve manifests, segments and player APIs from ad-tech-looking
    // hosts or paths; blocking those requests leaves only the poster frame.
    final builtInBlocked = _isAdvertisingUrl(rawUrl);
    if (!builtInBlocked) return null;

    final uri = Uri.tryParse(rawUrl);
    if (uri != null && _loggedBlockedAdResources.length < 500) {
      final safePath =
          uri.path.length > 180 ? uri.path.substring(0, 180) : uri.path;
      final key = '${uri.host}$safePath';
      if (_loggedBlockedAdResources.add(key)) {
        debugPrint('[KinoKino][BLOCKED_AD] $key');
      }
    }

    return WebResourceResponse(
      contentType: '',
      contentEncoding: 'utf-8',
      data: Uint8List(0),
      statusCode: 204,
      reasonPhrase: 'No Content',
      headers: const <String, String>{
        'Cache-Control': 'no-store, max-age=0',
        'Content-Length': '0',
      },
    );
  }

  List<ContentBlocker> get _adContentBlockers => [
        // Block common ad networks, trackers and pop-under delivery hosts.
        ContentBlocker(
          trigger: ContentBlockerTrigger(
            urlFilter: r".*://([^/]*\.)?(doubleclick\.net|googlesyndication\.com|googleadservices\.com|adservice\.google\.[^/]+|adnxs\.com|taboola\.com|outbrain\.com|mgid\.com|popads\.net|popcash\.net|exoclick\.com|propellerads\.com|trafficjunky\.net|adsterra\.com|pushground\.com|onclicka\.com|clickadu\.com|hilltopads\.com|admaven\.com|adfox\.ru|adfox\.yandex\.ru|an\.yandex\.ru|yandexadexchange\.net|adriver\.ru|adriver\.com|adriver-sync\.com|adriver-serv\.ru)(/|$).*",
          ),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
        // Common ad and tracking endpoints; deliberately avoid generic video/media URLs.
        ContentBlocker(
          trigger: ContentBlockerTrigger(
            urlFilter: r".*://[^/]+/(ads?|adserver|adservice|banner|popunder|track|pixel)(/|\?|$).*",
          ),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      ];

  UnmodifiableListView<UserScript> get _popupGuardScripts =>
      UnmodifiableListView<UserScript>([
        UserScript(
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
          source: r"""
            (() => {
              const nativeOpen = window.open.bind(window);
              const isAdTarget = (value) => /doubleclick|googlesyndication|googleadservices|adservice|taboola|outbrain|popunder|popads|popcash|exoclick|propellerads|adsterra|clickadu|hilltopads|admaven|adfox|adriver|vast|vpaid/i.test(String(value || ''));
              const safeOpen = (url, ...args) => isAdTarget(url) ? null : nativeOpen(url, ...args);
              try {
                Object.defineProperty(window, 'open', {
                  configurable: true,
                  enumerable: true,
                  writable: true,
                  value: safeOpen
                });
              } catch (_) {
                try { window.open = safeOpen; } catch (_) {}
              }
              const blockBlankTarget = (event) => {
                const link = event.target && event.target.closest
                  ? event.target.closest('a[target="_blank"],area[target="_blank"]')
                  : null;
                if (!link || !isAdTarget(link.href)) return;
                event.preventDefault();
                event.stopImmediatePropagation();
              };
              document.addEventListener('click', blockBlankTarget, true);
              document.addEventListener('auxclick', blockBlankTarget, true);
              document.addEventListener('submit', (event) => {
                const form = event.target;
                if (form && form.target === '_blank' && isAdTarget(form.action)) {
                  event.preventDefault();
                  event.stopImmediatePropagation();
                }
              }, true);
            })();
          """,
        ),
      ]);

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
        useShouldInterceptRequest: defaultTargetPlatform == TargetPlatform.android,
        contentBlockers: _adContentBlockers,
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
  // KinoKino embeds its player in the film page itself. Do not wait for a
  // popup/new window: after the user taps the site's real play control, find
  // the newly-created video/iframe and expand that element in the same WebView.
  // This preserves the document, cookies, referrer and playback session.
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
                /(^|\.)kinokino\.win$/i.test(frameUrl.hostname) ||
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
                initialUserScripts: _popupGuardScripts,
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
                shouldInterceptRequest: (controller, request) =>
                    _interceptAdResource(controller, request),
                shouldOverrideUrlLoading: (controller, action) async {
                  final target = action.request.url?.toString();
                  if (_isAdvertisingUrl(target)) {
                    debugPrint('[KinoKino] blocked ad navigation: $target');
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onLoadStop: (controller, url) async {
                  debugPrint('[KinoKino bootstrap] loaded: $url');
                  await _installStreamBridge(controller);
                  if (!_pageLoaded && mounted) {
                    // Show the real provider page. Do not replace its DOM with
                    // a guessed iframe/poster: providers often initialise video
                    // only after their own controls are tapped.
                    setState(() {
                      _pageLoaded = true;
                      _playerLoading = false;
                      _error = null;
                    });
                  }
                },
                // Attach the original popup WebView in this screen. It
                // retains opener/session/referrer state and the site's user gesture.
                onCreateWindow: (_, action) async {
                  final target = action.request.url?.toString();
                  if (_isAdvertisingUrl(target)) {
                    debugPrint('[KinoKino] blocked advertising window: $target');
                    return false;
                  }
                  // Some providers launch the actual video in a separate
                  // WebView window. Attach that native window instead of
                  // silently rejecting it and leaving only the poster page.
                  if (!mounted) return false;
                  setState(() {
                    _playerWindowId = action.windowId;
                    _playerWindowOpened = true;
                    _playerLoading = false;
                    _error = null;
                  });
                  debugPrint('[KinoKino] opened video window: $target');
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
                initialUserScripts: _popupGuardScripts,
                onLoadStart: (controller, url) {
                  debugPrint('[KinoKino player] loading: $url');
                },
                shouldInterceptRequest: (controller, request) =>
                    _interceptAdResource(controller, request),
                shouldOverrideUrlLoading: (controller, action) async {
                  final target = action.request.url?.toString();
                  if (_isAdvertisingUrl(target)) {
                    debugPrint('[KinoKino player] blocked ad navigation: $target');
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
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
          if (_pageLoaded && !_playerLoading && _error == null)
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: PopupMenuButton<int>(
                  tooltip: 'Сменить плеер',
                  onSelected: _selectPlayerSource,
                  color: const Color(0xFF202124),
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xDD202124),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x66FFD21F)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz_rounded, color: Color(0xFFFFD21F), size: 19),
                        SizedBox(width: 5),
                        Text('Сменить плеер', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  itemBuilder: (context) => [
                    for (var i = 0; i < _playerSourceHosts.length; i++)
                      PopupMenuItem<int>(
                        value: i,
                        child: Row(
                          children: [
                            Icon(
                              i == _sourceAttemptIndex ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: const Color(0xFFFFD21F),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text('Плеер ${i + 1}', style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (!_playerWindowOpened && (!_pageLoaded || _playerLoading))
            const Positioned.fill(
              child: ColoredBox(color: Colors.black),
            ),
          if (!_playerWindowOpened && (!_pageLoaded || _playerLoading))
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
                          (_playerLoading
                              ? 'Загружаем видеоплеер…'
                              : (_pageLoaded
                                  ? 'Плеер готовится к запуску…'
                                  : 'Подключаем плеер…')),
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
                            _playerLoading = false;
                            _sourceAttemptIndex = 0;
                          });
                                  await _bootstrapController?.loadUrl(
                            urlRequest: URLRequest(url: _urlForSource(0)),
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
