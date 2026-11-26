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

  Future<void> _showPlayerOnly(InAppWebViewController controller) async {
    // Locate the site's actual player frame and display it as a clean full-screen
    // surface. The source page is only used to discover the embed URL.
    await controller.evaluateJavascript(source: r"""
      (() => {
        if (window.__kinokinoPlayerOnlyStarted) return;
        window.__kinokinoPlayerOnlyStarted = true;
        let attempts = 0;
        const findAndShow = () => {
          attempts++;
          const frames = Array.from(document.querySelectorAll('iframe'));
          const scored = frames.map(frame => {
            const attrs = [
              frame.id, frame.className, frame.title,
              frame.getAttribute('data-src'), frame.getAttribute('src')
            ].join(' ').toLowerCase();
            let parent = frame.parentElement;
            let depth = 0;
            let playerContext = false;
            while (parent && depth++ < 5) {
              const marker = ((parent.id || '') + ' ' + (parent.className || '')).toLowerCase();
              if (/player|video|watch|movie|film|embed/.test(marker)) playerContext = true;
              parent = parent.parentElement;
            }
            const rect = frame.getBoundingClientRect();
            const url = frame.getAttribute('src') ||
              frame.getAttribute('data-src') ||
              frame.getAttribute('data-lazy-src') ||
              frame.getAttribute('data-original');
            if (!url || /about:blank|doubleclick|googlesyndication|adsystem|banner/i.test(url + attrs)) {
              return {frame, score: -1, url};
            }
            let score = playerContext ? 100 : 0;
            if (/player|video|watch|movie|film|embed/.test(attrs)) score += 40;
            if (rect.width > 250 && rect.height > 120) score += 25;
            if (frame.hasAttribute('allowfullscreen') || frame.hasAttribute('webkitallowfullscreen')) score += 15;
            if (/ad|banner|promo|social|comment/i.test(attrs)) score -= 100;
            return {frame, score, url};
          }).filter(item => item.score >= 0 && item.url)
            .sort((a, b) => b.score - a.score);
          if (!scored.length) {
            const video = document.querySelector('video');
            if (video && (video.currentSrc || video.src)) {
              video.style.setProperty('position', 'fixed', 'important');
              video.style.setProperty('inset', '0', 'important');
              video.style.setProperty('width', '100vw', 'important');
              video.style.setProperty('height', '100vh', 'important');
              video.style.setProperty('z-index', '2147483647', 'important');
              video.style.setProperty('background', '#000', 'important');
              document.documentElement.style.cssText = 'margin:0!important;background:#000!important;overflow:hidden!important';
              document.body.style.cssText = 'margin:0!important;background:#000!important;overflow:hidden!important';
              Array.from(document.body.children).forEach(node => {
                if (!node.contains(video)) node.style.setProperty('display', 'none', 'important');
              });
              return true;
            }
            return false;
          }
          const chosen = scored[0];
          const targetUrl = new URL(chosen.url, document.baseURI).href;
          const overlay = document.createElement('div');
          overlay.id = 'kinokino-player-only';
          overlay.style.cssText = 'position:fixed;inset:0;width:100vw;height:100vh;background:#000;z-index:2147483647;margin:0;padding:0;overflow:hidden';
          const player = document.createElement('iframe');
          player.src = targetUrl;
          player.allow = 'autoplay; fullscreen; picture-in-picture; encrypted-media; accelerometer; gyroscope';
          player.setAttribute('allowfullscreen', 'true');
          player.setAttribute('webkitallowfullscreen', 'true');
          player.referrerPolicy = 'strict-origin-when-cross-origin';
          player.style.cssText = 'display:block;border:0;width:100%;height:100%;background:#000';
          overlay.appendChild(player);
          document.documentElement.appendChild(overlay);
          document.documentElement.style.cssText = 'margin:0!important;padding:0!important;width:100%!important;height:100%!important;overflow:hidden!important;background:#000!important';
          document.body.style.cssText = 'margin:0!important;padding:0!important;width:100%!important;height:100%!important;overflow:hidden!important;background:#000!important';
          Array.from(document.body.children).forEach(node => {
            if (node !== overlay && !node.contains(overlay)) node.style.setProperty('display', 'none', 'important');
          });
          return true;
        };
        if (findAndShow()) return;
        const timer = setInterval(() => {
          if (findAndShow() || attempts >= 24) clearInterval(timer);
        }, 500);
        const observer = new MutationObserver(() => {
          if (!document.getElementById('kinokino-player-only')) findAndShow();
        });
        observer.observe(document.documentElement, {childList:true,subtree:true,attributes:true,attributeFilter:['src','data-src']});
        setTimeout(() => observer.disconnect(), 15000);
      })();
    """);
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
              await _showPlayerOnly(controller);
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
                            '${widget.title} · ${_usingFallback ? 'Zagonka' : 'KinoKino'}',
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
