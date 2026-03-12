import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AEDWebViewScreen
//
// In-app browser used for:
//   • AED detail pages (iSaveLives / KSL registry)
//   • Kids Save Lives website
//   • Report-issue form
// ─────────────────────────────────────────────────────────────────────────────

class AEDWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const AEDWebViewScreen({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<AEDWebViewScreen> createState() => _AEDWebViewScreenState();
}

class _AEDWebViewScreenState extends State<AEDWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted:    (_) => setState(() => _isLoading = true),
          onPageFinished:   (_) => setState(() => _isLoading = false),
          onWebResourceError: (_) {
            // Silently handled — user sees the WebView error page naturally.
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: context.pop,
        ),
        title: Text(
          widget.title,
          style: AppTypography.bodyMedium(color: AppColors.textOnDark),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}