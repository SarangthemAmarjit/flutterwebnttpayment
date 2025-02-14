import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_web_kit/atom_pay_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class WebViewContainer extends StatefulWidget {
  final String mode;
  final String payDetails;
  final String responsehashKey;
  final String responseDecryptionKey;
  final String atomTokenId;
  final String merchId;

  WebViewContainer(this.mode, this.payDetails, this.responsehashKey,
      this.responseDecryptionKey, this.atomTokenId, this.merchId);

  @override
  createState() => _WebViewContainerState();
}

class _WebViewContainerState extends State<WebViewContainer> {
  late InAppWebViewController _controller;
  final Completer<InAppWebViewController> _controllerCompleter =
      Completer<InAppWebViewController>();

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _handleBackButtonAction(context),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          elevation: 0,
          toolbarHeight: 2,
        ),
        body: SafeArea(
          child: InAppWebView(
            key: UniqueKey(),
            initialSettings: InAppWebViewSettings(
              supportMultipleWindows: true,
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: true,
            ),
            initialData: InAppWebViewInitialData(
              data: '''
              <!DOCTYPE html>
              <html>
              <head>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <script src="https://pgtest.atomtech.in/staticdata/ots/js/atomcheckout.js"></script>
                <style>
                  body { margin: 0; padding: 0; width: 100%; height: 100%; }
                  #payment-form { width: 100%; height: 100%; }
                </style>
              </head>
              <body>
                <div id="payment-form"></div>
                <script>
                  function initPayment() {
                    const options = {
                      "atomTokenId": "${widget.atomTokenId}",
                      "merchId": "${widget.merchId}",
                      "custEmail": "test.user@gmail.com",
                      "custMobile": "8888888888",
                      "returnUrl": "https://pgtest.atomtech.in/mobilesdk/param"
                    };
                    new AtomPaynetz(options, 'uat');
                  }
                  document.addEventListener('DOMContentLoaded', initPayment);
                </script>
              </body>
              </html>
              ''',
            ),
            onWebViewCreated: (InAppWebViewController inAppWebViewController) {
              _controllerCompleter.future.then((value) => _controller = value);
              _controllerCompleter.complete(inAppWebViewController);
              debugPrint("payDetails from webview ${widget.payDetails}");
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              debugPrint("shouldOverrideUrlLoading called");
              var uri = navigationAction.request.url!;
              debugPrint(uri.scheme);
              if (["upi"].contains(uri.scheme)) {
                debugPrint("UPI URL detected");
                await launchUrl(uri);
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            onLoadStop: (controller, url) async {
              debugPrint("onloadstop_url: $url");
              if (url.toString().contains("AIPAYLocalFile")) {
                debugPrint(" AIPAYLocalFile Now url loaded: $url");
                await _controller.evaluateJavascript(
                    source: "openPay('" + widget.payDetails + "')");
              }
              if (url.toString().contains('/mobilesdk/param')) {
                _handleTransactionResponse();
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleTransactionResponse() async {
    final String response = await _controller.evaluateJavascript(
        source: "document.getElementsByTagName('h5')[0].innerHTML");
    debugPrint("HTML response : $response");

    String transactionResult = "Transaction Failed";

    if (response.trim().contains("cancelTransaction")) {
      transactionResult = "Transaction Cancelled!";
    } else {
      final split = response.trim().split('|');
      final splitTwo = split[1].split('=');
      const platform = MethodChannel('flutter.dev/NDPSAESLibrary');

      try {
        final String result = await platform.invokeMethod('NDPSAESInit', {
          'AES_Method': 'decrypt',
          'text': splitTwo[1].toString(),
          'encKey': widget.responseDecryptionKey
        });

        Map<String, dynamic> jsonInput = jsonDecode(result);
        debugPrint("Transaction Response: $jsonInput");

        bool isValid = validateSignature(jsonInput, widget.responsehashKey);

        if (isValid &&
            (jsonInput["payInstrument"]["responseDetails"]["statusCode"] ==
                    'OTS0000' ||
                jsonInput["payInstrument"]["responseDetails"]["statusCode"] ==
                    'OTS0551')) {
          transactionResult = "Transaction Success";
        }
      } on PlatformException catch (e) {
        debugPrint("Failed to decrypt: '${e.message}'");
      }
    }
    _closeWebView(context, transactionResult);
  }

  void _closeWebView(BuildContext context, String transactionResult) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Transaction Status = $transactionResult")));
  }

  Future<bool> _handleBackButtonAction(BuildContext context) async {
    debugPrint("_handleBackButtonAction called");
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Do you want to exit the payment?'),
              actions: <Widget>[
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('No'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            "Transaction Status = Transaction cancelled")));
                  },
                  child: const Text('Yes'),
                ),
              ],
            ));
    return Future.value(true);
  }
}
