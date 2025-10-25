import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF194E9D),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF194E9D),
              ),
            ),
        ],
      ),
    );
  }
}