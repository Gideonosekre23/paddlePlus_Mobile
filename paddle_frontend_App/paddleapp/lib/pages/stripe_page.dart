import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class StripeVerificationWebViewPage extends StatefulWidget {
  final String initialUrl;
  const StripeVerificationWebViewPage({super.key, required this.initialUrl});

  @override
  State<StripeVerificationWebViewPage> createState() =>
      _StripeVerificationWebViewPageState();
}

class _StripeVerificationWebViewPageState
    extends State<StripeVerificationWebViewPage> {
  late final WebViewController _controller;
  bool _isLoadingPage = true;
  String? _loadingError;
  bool _isInitialized = false;
  bool _hasRendererCrashed = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  Timer? _crashDetectionTimer;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _startCrashDetection();
  }

  @override
  void dispose() {
    print("🗑️ StripeWebView disposing...");
    _crashDetectionTimer?.cancel();
    // Don't try to dispose controller as it might have crashed
    super.dispose();
  }

  // ✅ ADD: Crash detection mechanism
  void _startCrashDetection() {
    _crashDetectionTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _checkForCrashes();
    });
  }

  // ✅ ADD: Check for renderer crashes
  void _checkForCrashes() {
    if (_hasRendererCrashed || !_isInitialized) return;

    // Try to evaluate JavaScript to check if renderer is alive
    _controller.runJavaScript('1+1').catchError((error) {
      print("🚨 WebView renderer may have crashed: $error");
      if (mounted && !_hasRendererCrashed) {
        _handleRendererCrash();
      }
    });
  }

  // ✅ ADD: Handle renderer crashes
  void _handleRendererCrash() {
    print("💥 WebView renderer crashed!");
    _crashDetectionTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _hasRendererCrashed = true;
      _loadingError =
          "Verification page crashed. This can happen due to high memory usage.";
      _isLoadingPage = false;
    });
  }

  void _initializeWebView() {
    if (_hasRendererCrashed && _retryCount >= _maxRetries) {
      if (mounted) {
        setState(() {
          _loadingError =
              "Maximum retry attempts reached. Please try again later.";
          _isLoadingPage = false;
        });
      }
      return;
    }

    try {
      print("🌐 Initializing WebView (attempt ${_retryCount + 1})...");

      _controller =
          WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setBackgroundColor(const Color(0x00000000))
            ..setNavigationDelegate(
              NavigationDelegate(
                onProgress: (int progress) {
                  print('WebView is loading (progress : $progress%)');
                  if (progress == 100 && _isLoadingPage && mounted) {
                    setState(() {
                      _isLoadingPage = false;
                    });
                  }
                },
                onPageStarted: (String url) {
                  print('📄 Page started loading: $url');
                  if (mounted) {
                    setState(() {
                      _isLoadingPage = true;
                      _loadingError = null;
                      _hasRendererCrashed = false;
                    });
                  }
                },
                onPageFinished: (String url) {
                  print('✅ Page finished loading: $url');
                  if (mounted) {
                    setState(() {
                      _isLoadingPage = false;
                    });
                  }
                },
                onWebResourceError: (WebResourceError error) {
                  print('''❌ Page resource error:
  code: ${error.errorCode}
  description: ${error.description}
  errorType: ${error.errorType}
  isForMainFrame: ${error.isForMainFrame}
              ''');

                  if (mounted && error.isForMainFrame == true) {
                    // Check if this might be a renderer crash
                    if (error.description.toLowerCase().contains('crash') ||
                        error.description.toLowerCase().contains('renderer') ||
                        error.errorCode == -2) {
                      _handleRendererCrash();
                    } else {
                      setState(() {
                        _isLoadingPage = false;
                        _loadingError =
                            "Failed to load verification page: ${error.description} (Code: ${error.errorCode})";
                      });
                    }
                  }
                },
                onNavigationRequest: (NavigationRequest request) {
                  print('🔗 Navigation request to: ${request.url}');

                  return NavigationDecision.navigate;
                },
              ),
            );

      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && _isLoadingPage && _isInitialized) {
          print("⏰ WebView load timeout");
          setState(() {
            _loadingError =
                "Verification page took too long to load. Please try again.";
            _isLoadingPage = false;
          });
        }
      });

      _controller
          .loadRequest(Uri.parse(widget.initialUrl))
          .then((_) {
            if (mounted) {
              setState(() {
                _isInitialized = true;
              });
              print("✅ WebView initialized successfully");
            }
          })
          .catchError((error) {
            print('❌ Error loading initial URL: $error');
            if (mounted) {
              setState(() {
                _loadingError = "Failed to load verification page: $error";
                _isLoadingPage = false;
              });
            }
          });
    } catch (e) {
      print('❌ Error initializing WebView: $e');
      if (mounted) {
        setState(() {
          _loadingError = "Failed to initialize verification page: $e";
          _isLoadingPage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Verification'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _showExitConfirmationDialog(),
        ),
      ),
      body: WillPopScope(
        onWillPop: () async {
          await _showExitConfirmationDialog();
          return false;
        },
        child: Stack(
          children: [
            if (_loadingError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _hasRendererCrashed
                            ? Icons.bug_report
                            : Icons.error_outline,
                        color: Colors.red,
                        size: 50,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _hasRendererCrashed
                            ? "WebView Crashed"
                            : "Loading Error",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _loadingError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red[700], fontSize: 14),
                      ),
                      const SizedBox(height: 20),

                      if (_retryCount < _maxRetries) ...[
                        ElevatedButton.icon(
                          onPressed: _retryLoading,
                          icon: const Icon(Icons.refresh),
                          label: Text(
                            _hasRendererCrashed
                                ? 'Restart WebView (${_maxRetries - _retryCount} attempts left)'
                                : 'Retry Loading',
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                        ),
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).pop({'success': false, 'cancelled': true});
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel and Go Back'),
                      ),

                      if (_hasRendererCrashed) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: const Text(
                            "💡 Tip: Close other apps to free up memory, then try again.",
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else if (_isInitialized && !_hasRendererCrashed)
              WebViewWidget(controller: _controller)
            else
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Color.fromARGB(255, 118, 172, 198),
                    ),
                    SizedBox(height: 16),
                    Text('Initializing verification...'),
                  ],
                ),
              ),

            if (_isLoadingPage &&
                _loadingError == null &&
                _isInitialized &&
                !_hasRendererCrashed)
              Container(
                color: Colors.white.withOpacity(0.9),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: Color.fromARGB(255, 118, 172, 198),
                      ),
                      SizedBox(height: 16),
                      Text('Loading verification page...'),
                      SizedBox(height: 8),
                      Text(
                        'This may take a few moments',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _retryLoading() {
    _retryCount++;
    print("🔄 Retrying WebView load (attempt $_retryCount)...");

    if (mounted) {
      setState(() {
        _isLoadingPage = true;
        _loadingError = null;
        _hasRendererCrashed = false;
        _isInitialized = false;
      });
    }

    // ✅ Restart crash detection
    _crashDetectionTimer?.cancel();
    _startCrashDetection();

    _initializeWebView();
  }

  Future<void> _showExitConfirmationDialog() async {
    final bool? shouldPop = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel Verification?'),
          content: const Text(
            'Are you sure you want to cancel the verification process and go back?\n\nYour registration progress will not be saved.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Stay'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancel & Go Back'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (shouldPop == true && mounted) {
      Navigator.of(context).pop({'success': false, 'cancelled': true});
    }
  }
}
