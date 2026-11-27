import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_forge/flutter_inappwebview_forge.dart';

import '../services/ad_filter_engine.dart';

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
  final Set<int> _verifiedPlayerSourceIndices = <int>{};
  int _playerCheckToken = 0;
  String? _error;
  final Expando<String> _sourceUrlByController = Expando<String>('kinoSourceUrl');

  @override
  void initState() {
    super.initState();
    AdFilterEngine.instance.initialize().then((_) {
      debugPrint('[KinoKino] network filter engine ready: ${AdFilterEngine.instance.ruleCount} rules');
    }).catchError((Object error) {
      debugPrint('[KinoKino] filter-list initialization failed: $error');
    });
  }

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
        !_verifiedPlayerSourceIndices.contains(index) ||
        index == _sourceAttemptIndex) return;
    _playerCheckToken++;
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

  Future<void> _tryNextUnverifiedPlayerSource() async {
    if (!mounted) return;
    int? nextIndex;
    for (var index = 0; index < _playerSourceHosts.length; index++) {
      if (index != _sourceAttemptIndex &&
          !_verifiedPlayerSourceIndices.contains(index)) {
        nextIndex = index;
        break;
      }
    }
    final targetIndex = nextIndex;
    if (targetIndex == null) return;
    _playerCheckToken++;
    setState(() {
      _sourceAttemptIndex = targetIndex;
      _playerWindowId = null;
      _playerWindowOpened = false;
      _pageLoaded = false;
      _playerLoading = true;
      _error = null;
    });
    await _leaveFullscreen();
    await _bootstrapController?.loadUrl(
      urlRequest: URLRequest(url: _urlForSource(targetIndex)),
    );
  }

  Future<void> _tryNextPlayerSource(String reason) async {
    if (!mounted) return;
    _verifiedPlayerSourceIndices.remove(_sourceAttemptIndex);
    _playerCheckToken++;
    final nextIndex = _sourceAttemptIndex + 1;
    if (nextIndex >= _playerSourceHosts.length) {
      final fallbackIndex = _verifiedPlayerSourceIndices.isEmpty
          ? null
          : (_verifiedPlayerSourceIndices.toList()..sort()).first;
      if (fallbackIndex != null) {
        debugPrint('[KinoKino] no new source after $reason; returning to verified player');
        setState(() {
          _sourceAttemptIndex = fallbackIndex;
          _pageLoaded = false;
          _playerLoading = true;
          _error = null;
        });
        await _bootstrapController?.loadUrl(
          urlRequest: URLRequest(url: _urlForSource(fallbackIndex)),
        );
        return;
      }
      debugPrint('[KinoKino] no player source left after ' + reason);
      setState(() {
        _pageLoaded = false;
        _playerLoading = false;
        _error = 'На доступных источниках плеер не найден. Попробуй позже.';
      });
      return;
    }
    debugPrint('[KinoKino] player missing (' + reason + '), switching to ' + _playerSourceHosts[nextIndex]);
    setState(() {
      _sourceAttemptIndex = nextIndex;
      _pageLoaded = false;
      _playerLoading = false;
      _error = null;
    });
    await _bootstrapController?.loadUrl(
      urlRequest: URLRequest(url: _urlForSource(nextIndex)),
    );
  }

  void _schedulePlayerCheck(InAppWebViewController controller, Duration delay) {
    final token = ++_playerCheckToken;
    Future<void>.delayed(delay, () async {
      if (!mounted || token != _playerCheckToken) return;
      const probe = r"""
        (() => {
          const visible = (el) => {
            const r = el.getBoundingClientRect();
            const s = getComputedStyle(el);
            return r.width > 100 && r.height > 60 && s.display !== 'none' &&
              s.visibility !== 'hidden' && Number(s.opacity) > 0;
          };
          const hasPlayer = Array.from(document.querySelectorAll('video,iframe')).some((el) => {
            if (!visible(el)) return false;
            if (el.tagName === 'VIDEO') return true;
            const u = (el.src || '').toLowerCase();
            const playerUrl = /player|video|embed|stream|kodik|alloha|collaps|videocdn|kinogo|movie|watch/i.test(u);
            return !!u && playerUrl &&
              !/doubleclick|adservice|analytics|metrika|captcha|banner|reklam|advert|popunder/i.test(u);
          });
          const text = (document.body?.innerText || '').toLowerCase();
          const notFound = /ничего не найдено|фильм не найден|сериал не найден|материал не найден|контент не найден|страница не найдена|404|not found|no results/i.test(text);
          const hasLaunch = Array.from(document.querySelectorAll('a,button,[role="button"],input[type="button"],input[type="submit"]')).some((el) => {
            const t = ((el.innerText || el.value || el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('title') || '')).toLowerCase();
            return visible(el) && /смотреть|watch|play|воспроизвести|запустить/.test(t);
          });
          return hasPlayer ? 2 : ((notFound || !hasLaunch) ? 0 : 1);
        })();
      """;
      try {
        final result = await controller.evaluateJavascript(source: probe);
        final state = int.tryParse(result.toString()) ?? -1;
        if (state == 2) {
          _verifiedPlayerSourceIndices.add(_sourceAttemptIndex);
          if (mounted) setState(() => _playerLoading = false);
          return;
        }
        await _tryNextPlayerSource(
          state == 0 ? 'no embedded player / not found page' : 'no confirmed video player',
        );
      } catch (e) {
        debugPrint('[KinoKino] player availability check failed: $e');
      }
    });
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
    final sourceUrl = _sourceUrlByController[controller] ?? _pageUrl.toString();
    if (request.isForMainFrame == true) {
      _sourceUrlByController[controller] = rawUrl;
    }
    final builtInBlocked = _isAdvertisingUrl(rawUrl);
    final listBlocked = AdFilterEngine.instance.shouldBlock(
      rawUrl: rawUrl,
      sourceUrl: sourceUrl,
      isMainFrame: request.isForMainFrame ?? false,
      headers: request.headers,
    );
    if (!builtInBlocked && !listBlocked) return null;

    final uri = Uri.tryParse(rawUrl);
    if (uri != null && _loggedBlockedAdResources.length < 500) {
      final safePath =
          uri.path.length > 180 ? uri.path.substring(0, 180) : uri.path;
      final key = '${uri.host}$safePath';
      if (_loggedBlockedAdResources.add(key)) {
        debugPrint(listBlocked && !builtInBlocked
            ? '[KinoKino][FILTER_LIST_BLOCK] $key'
            : '[KinoKino][BLOCKED_AD] $key');
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
              const denyPopup = () => null;
              try {
                Object.defineProperty(window, 'open', {
                  configurable: false,
                  enumerable: true,
                  writable: false,
                  value: denyPopup
                });
              } catch (_) {
                try { window.open = denyPopup; } catch (_) {}
              }
              const blockBlankTarget = (event) => {
                const link = event.target && event.target.closest
                  ? event.target.closest('a[target="_blank"],area[target="_blank"]')
                  : null;
                if (!link) return;
                event.preventDefault();
                event.stopImmediatePropagation();
              };
              document.addEventListener('click', blockBlankTarget, true);
              document.addEventListener('auxclick', blockBlankTarget, true);
              document.addEventListener('submit', (event) => {
                const form = event.target;
                if (form && form.target === '_blank') {
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
        javaScriptCanOpenWindowsAutomatically: false,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        hardwareAcceleration: true,
        enableEncryptedMedia: true,
        enableMedia: true,
        isElementFullscreenEnabled: true,
        supportMultipleWindows: false,
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
  Future<void> _activateSitePlayer(InAppWebViewController controller) async {
    const script = r"""
      (() => {
        if (window.__kinoInlinePlayerWatcher) return;
        window.__kinoInlinePlayerWatcher = true;
        const isVisible = (node) => {
          const r = node.getBoundingClientRect();
          const s = getComputedStyle(node);
          return r.width > 100 && r.height > 60 &&
            s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity) > 0;
        };
        const playerFrame = () => {
          const frames = Array.from(document.querySelectorAll('iframe')).filter((frame) => {
            if (!isVisible(frame) || !frame.src) return false;
            try {
              const u = new URL(frame.src, location.href);
              const hints = [u.hostname, u.pathname, u.search, frame.title || '',
                frame.id || '', typeof frame.className === 'string' ? frame.className : ''].join(' ').toLowerCase();
              if (u.origin === location.origin || /(^|\.)kinokino\.win$/i.test(u.hostname)) return false;
              // Reject ad/tracker frames using URL and DOM metadata, not URL alone.
              if (/doubleclick|adservice|analytics|metrika|captcha|banner|reklam|advert|\bads?\b|popunder|tracker|promo|sponsor/i.test(hints)) return false;
              if (/^(about:blank|javascript:)/i.test(frame.src)) return false;
              const rect = frame.getBoundingClientRect();
              const playerHint = /player|video|embed|stream|kodik|alloha|collaps|videocdn|kinogo|movie|watch/i.test(hints);
              const largeFrame = rect.width >= Math.min(320, innerWidth * 0.55) &&
                rect.height >= Math.min(180, innerHeight * 0.35);
              return playerHint || largeFrame;
            } catch (_) { return false; }
          });
          // Explicit player URLs win; large visible frames are a fallback.
          frames.sort((a, b) => {
            const score = (f) => {
              const meta = [f.src, f.title || '', f.id || '', typeof f.className === 'string' ? f.className : ''].join(' ');
              return (/player|video|embed|stream|kodik|alloha|collaps|videocdn|kinogo/i.test(meta) ? 100 : 0) +
                Math.min(50, Math.round(f.getBoundingClientRect().width / Math.max(1, innerWidth) * 50));
            };
            return score(b) - score(a);
          });
          return frames[0] || null;
        };
        const exposeOnly = (target) => {
          let branch = target;
          while (branch && branch !== document.body && branch.parentElement) {
            const parent = branch.parentElement;
            for (const sibling of Array.from(parent.children)) {
              if (sibling !== branch) sibling.style.setProperty('display', 'none', 'important');
            }
            branch = parent;
          }
          document.documentElement.style.cssText += ';background:#000!important;overflow:hidden!important;width:100%!important;height:100%!important';
          document.body.style.cssText += ';background:#000!important;overflow:hidden!important;margin:0!important;padding:0!important;width:100%!important;height:100%!important';
          target.style.setProperty('position', 'fixed', 'important');
          target.style.setProperty('inset', '0', 'important');
          target.style.setProperty('width', '100vw', 'important');
          target.style.setProperty('height', '100dvh', 'important');
          target.style.setProperty('max-width', '100vw', 'important');
          target.style.setProperty('max-height', '100dvh', 'important');
          target.style.setProperty('z-index', '2147483647', 'important');
          target.style.setProperty('border', '0', 'important');
          target.style.setProperty('margin', '0', 'important');
          target.style.setProperty('display', 'block', 'important');
          target.style.setProperty('visibility', 'visible', 'important');
          target.style.setProperty('opacity', '1', 'important');
          console.log('[KinoKino] embedded player isolated in the original page');
          return true;
        };
        let exposed = false;
        let waitingForPlayer = false;
        let launchNotified = false;
        const notify = (state) => {
          try { window.flutter_inappwebview.callHandler('playerState', {state}); } catch (_) {}
        };
        const revealWhenReady = (target, isFrame) => {
          if (waitingForPlayer) return;
          waitingForPlayer = true;
          exposed = exposeOnly(target);
          let finished = false;
          const ready = () => {
            if (finished) return;
            finished = true;
            setTimeout(() => notify('ready'), 500);
          };
          if (isFrame) {
            target.addEventListener('load', ready, {once:true});
            setTimeout(() => { if (!finished) ready(); }, 5000);
          } else if (target.readyState >= 2 && target.videoWidth > 0) {
            ready();
          } else {
            target.addEventListener('loadeddata', ready, {once:true});
            target.addEventListener('canplay', ready, {once:true});
            setTimeout(() => { if (!finished) ready(); }, 5000);
          }
        };
        const detect = () => {
          if (exposed) return;
          const frame = playerFrame();
          if (frame) { revealWhenReady(frame, true); return; }
          const video = Array.from(document.querySelectorAll('video')).find(isVisible);
          if (video) revealWhenReady(video, false);
        };
        const launch = () => {
          const nodes = Array.from(document.querySelectorAll(
            'a,button,[role="button"],input[type="button"],input[type="submit"]'
          ));
          const candidate = nodes.find((node) => {
            const text = ((node.innerText || node.value || node.getAttribute('aria-label') || '') + ' ' +
              (node.getAttribute('title') || '')).trim().toLowerCase();
            return isVisible(node) &&
              /смотреть онлайн|смотреть фильм|смотреть сери|смотреть|watch online|watch now|play|воспроизвести|запустить/.test(text);
          });
          if (!candidate) return false;
          // Isolate only the launch control until it is tapped. Once the actual
          // embedded player appears, detect() replaces this view with the player.
          let branch = candidate;
          while (branch && branch !== document.body && branch.parentElement) {
            const parent = branch.parentElement;
            for (const sibling of Array.from(parent.children)) {
              if (sibling !== branch) sibling.style.setProperty('visibility', 'hidden', 'important');
            }
            branch.style.setProperty('visibility', 'visible', 'important');
            branch = parent;
          }
          Object.entries({
            position:'fixed', left:'50%', top:'50%', transform:'translate(-50%, -50%)',
            'z-index':'2147483647', visibility:'visible', opacity:'1',
            'pointer-events':'auto', 'min-width':'220px', 'min-height':'52px',
            'font-size':'16px', padding:'14px 24px', 'border-radius':'12px',
            background:'#202020', color:'#fff', border:'1px solid #666'
          }).forEach(([key,value]) => candidate.style.setProperty(key,value,'important'));
          if (!launchNotified) {
            launchNotified = true;
            notify('launch');
          }
          return true;
        };
        document.addEventListener('click', (event) => {
          const clicked = event.target && event.target.closest
            ? event.target.closest('a,button,[role="button"],input[type="button"],input[type="submit"]')
            : null;
          if (!clicked) return;
          const text = ((clicked.innerText || clicked.value || clicked.getAttribute('aria-label') || '') + ' ' +
            (clicked.getAttribute('title') || '')).trim().toLowerCase();
          if (/смотреть онлайн|смотреть фильм|смотреть сери|смотреть|watch online|watch now|play|воспроизвести|запустить/.test(text)) notify('loading');
        }, true);
        const observer = new MutationObserver(() => {
          detect();
          if (!exposed) launch();
        });
        observer.observe(document.documentElement, {
          childList:true, subtree:true, attributes:true,
          attributeFilter:['src','style','class']
        });
        launch();
        detect();
        setInterval(detect, 700);
      })();
    """;
    try {
      await controller.evaluateJavascript(source: script);
    } catch (e) {
      debugPrint('[KinoKino] embedded player isolation failed: $e');
    }
  }

  Future<void> _installAdHiding(InAppWebViewController controller) async {
    const script = r"""
      (() => {
        if (window.__kinoAdFilterInstalled) return;
        window.__kinoAdFilterInstalled = true;
        const selectors = [
          'iframe[src*="doubleclick"]','iframe[src*="googlesyndication"]',
          'iframe[src*="googleadservices"]','iframe[src*="adservice"]',
          'iframe[src*="adnxs"]','iframe[src*="taboola"]',
          'iframe[src*="outbrain"]','iframe[src*="mgid"]',
          'iframe[src*="popads"]','iframe[src*="popcash"]',
          'iframe[src*="exoclick"]','iframe[src*="propellerads"]',
          '[id*="google_ads"]','[id*="ad-container"]','[id*="ad_"]',
          '[class*="advert"]','[class*="banner-ad"]','[class*="ad-container"]',
          '[class*="adsbygoogle"]','[class*="popunder"]','[class*="popup-ad"]',
          '[class*="sponsor"]','[data-ad]','[data-advert]',
          'ins.adsbygoogle','amp-ad','div[id^="ad_"]'
        ];
        const removeAds = () => {
          for (const selector of selectors) {
            document.querySelectorAll(selector).forEach((el) => {
              // Never remove a video or an ancestor containing the actual player.
              if (el.matches('video') || el.querySelector('video') ||
                  el.querySelector('iframe[src*="player"],iframe[src*="video"],iframe[src*="embed"]')) return;
              el.remove();
            });
          }
        };
        // Block unsolicited popup attempts. The real inline player remains in-page.
        window.open = () => null;
        const style = document.createElement('style');
        style.textContent = [
          'iframe[src*="doubleclick"],iframe[src*="googlesyndication"],',
          'iframe[src*="adservice"],iframe[src*="taboola"],iframe[src*="outbrain"],',
          '[class*="banner-ad"],[class*="popup-ad"],[class*="popunder"],',
          '[class*="adsbygoogle"],[data-ad],amp-ad{display:none!important;visibility:hidden!important;pointer-events:none!important}'
        ].join('');
        (document.head || document.documentElement).appendChild(style);
        let queued = false;
        const scheduleCleanup = () => {
          if (queued) return;
          queued = true;
          requestAnimationFrame(() => { queued = false; removeAds(); });
        };
        removeAds();
        new MutationObserver(scheduleCleanup).observe(document.documentElement, {
          childList: true, subtree: true
        });
        console.log('[KinoKino] ad filtering enabled');
      })();
    """;
    try {
      await controller.evaluateJavascript(source: script);
    } catch (e) {
      debugPrint('[KinoKino] ad filter injection failed: $e');
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
                  controller.addJavaScriptHandler(
                    handlerName: 'playerState',
                    callback: (args) {
                      final state = args.isNotEmpty && args.first is Map
                          ? (args.first as Map)['state']?.toString()
                          : null;
                      if (mounted && state == 'loading') {
                        setState(() {
                          _playerLoading = true;
                        });
                        final current = _bootstrapController;
                        if (current != null) _schedulePlayerCheck(current, const Duration(seconds: 20));
                      } else if (mounted && state == 'launch') {
                        setState(() {
                          _playerLoading = false;
                        });
                      } else if (mounted && state == 'ready') {
                        _playerCheckToken++;
                        _verifiedPlayerSourceIndices.add(_sourceAttemptIndex);
                        setState(() {
                          _playerLoading = false;
                        });
                      }
                      return {'accepted': true};
                    },
                  );
                },
                shouldInterceptRequest: (controller, request) =>
                    _interceptAdResource(controller, request),
                shouldOverrideUrlLoading: (controller, action) async {
                  final target = action.request.url?.toString();
                  final source = _sourceUrlByController[controller] ?? _pageUrl.toString();
                  final listBlocked = target != null &&
                      AdFilterEngine.instance.shouldBlock(
                        rawUrl: target,
                        sourceUrl: source,
                        isMainFrame: action.isForMainFrame,
                        headers: null,
                      );
                  if (_isAdvertisingUrl(target) || listBlocked) {
                    debugPrint('[KinoKino] blocked ad navigation: $target');
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onLoadStart: (controller, url) {
                  if (url != null) _sourceUrlByController[controller] = url.toString();
                },
                onLoadStop: (controller, url) async {
                  if (url != null) _sourceUrlByController[controller] = url.toString();
                  debugPrint('[KinoKino bootstrap] loaded: $url');
                  await _installAdHiding(controller);
                  await _installStreamBridge(controller);
                  if (!_pageLoaded) {
                    _pageLoaded = true;
                    if (mounted) setState(() => _playerLoading = true);
                    await _activateSitePlayer(controller);
                    if (mounted) setState(() {});
                    _schedulePlayerCheck(controller, const Duration(seconds: 12));
                  }
                },
                // Attach the original popup WebView in this screen. It
                // retains opener/session/referrer state and the site's user gesture.
                onCreateWindow: (_, action) async {
                  // The desired KinoKino player is embedded in the current page.
                  // Reject all new windows so ad pop-ups/pop-unders never load.
                  debugPrint('[KinoKino] blocked new window: ${action.request.url}');
                  return false;
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
                  if (url != null) _sourceUrlByController[controller] = url.toString();
                  debugPrint('[KinoKino player] loading: $url');
                },
                shouldInterceptRequest: (controller, request) =>
                    _interceptAdResource(controller, request),
                shouldOverrideUrlLoading: (controller, action) async {
                  final target = action.request.url?.toString();
                  final source = _sourceUrlByController[controller] ?? _pageUrl.toString();
                  final listBlocked = target != null &&
                      AdFilterEngine.instance.shouldBlock(
                        rawUrl: target,
                        sourceUrl: source,
                        isMainFrame: action.isForMainFrame,
                        headers: null,
                      );
                  if (_isAdvertisingUrl(target) || listBlocked) {
                    debugPrint('[KinoKino player] blocked ad navigation: $target');
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onLoadStop: (controller, url) async {
                  debugPrint('[KinoKino player] loaded: $url');
                  await _installAdHiding(controller);
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
          if (_pageLoaded && !_playerLoading && _error == null &&
              (_verifiedPlayerSourceIndices.length > 1 ||
                  _verifiedPlayerSourceIndices.length < _playerSourceHosts.length))
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: PopupMenuButton<int>(
                  tooltip: 'Сменить плеер',
                  onSelected: (index) {
                    if (index == -1) {
                      _tryNextUnverifiedPlayerSource();
                    } else {
                      _selectPlayerSource(index);
                    }
                  },
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
                  itemBuilder: (context) {
                    final available = _verifiedPlayerSourceIndices.toList()..sort();
                    return [
                      for (var position = 0; position < available.length; position++)
                        PopupMenuItem<int>(
                          value: available[position],
                          child: Row(
                            children: [
                              Icon(
                                available[position] == _sourceAttemptIndex
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: const Color(0xFFFFD21F),
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text('Плеер ${position + 1}', style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      if (available.length < _playerSourceHosts.length)
                        const PopupMenuItem<int>(
                          value: -1,
                          child: Text('Проверить другой плеер',
                              style: TextStyle(color: Colors.white)),
                        ),
                    ];
                  },
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
                          _playerCheckToken++;
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
