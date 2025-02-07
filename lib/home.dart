// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
//import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:html';
//import 'dart:js';

import 'dart:ui_web' as ui_web;
// import 'payment_webview.dart';

class PayPage extends StatefulWidget {
  const PayPage({super.key});

  @override
  State<PayPage> createState() => _PayPageState();
}

class _PayPageState extends State<PayPage> {
  @override
  void initState() {
    super.initState();
    // Generate atom token when page loads
    initiatePayment();
  }

  static const req_EncKey = 'A4476C2062FFA58980DC8F79EB6A799E';
  static const req_Salt = 'A4476C2062FFA58980DC8F79EB6A799E';
  static const res_DecKey = '75AEF0FA1B94B3C10D4F5B268F757F11';
  static const res_Salt = '75AEF0FA1B94B3C10D4F5B268F757F11';
  static const resHashKey = "KEYRESP123657234";
  static const merchId = "317157";
  static const merchPass = "Test@123";
  static const prodId = "NSE";
  final authUrl = "https://caller.atomtech.in/ots/aipay/auth";

  String? atomTokenId;
  String currentTxnId = '';

  bool isLoading = false;

  final password = Uint8List.fromList(utf8.encode(req_EncKey));
  final salt = Uint8List.fromList(utf8.encode(req_Salt));
  final resPassword = Uint8List.fromList(utf8.encode(res_DecKey));
  final resSalt = Uint8List.fromList(utf8.encode(res_Salt));
  final iv = Uint8List.fromList(
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);

  //Encrypt Function
  Future<String> encrypt(String text) async {
    debugPrint('Input text for encryption: $text');
    try {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha512(),
        iterations: 65536,
        bits: 256,
      );

      final derivedKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(password),
        nonce: salt,
      );

      final keyBytes = await derivedKey.extractBytes();
      debugPrint('Derived key bytes: $keyBytes');

      final aesCbc = AesCbc.with256bits(
        macAlgorithm: MacAlgorithm.empty,
        paddingAlgorithm: PaddingAlgorithm.pkcs7,
      );

      final secretBox = await aesCbc.encrypt(
        utf8.encode(text),
        secretKey: SecretKey(keyBytes),
        nonce: iv,
      );

      final hexOutput = secretBox.cipherText
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      debugPrint('Encrypted hex output: $hexOutput');
      return hexOutput;
    } catch (e, stackTrace) {
      debugPrint('Encryption error: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  //Decrypt Function
  Future<String> decrypt(String hexCipherText) async {
    try {
      debugPrint('Input hex for decryption: $hexCipherText');

      // Convert hex string to bytes
      List<int> cipherText = [];
      for (int i = 0; i < hexCipherText.length; i += 2) {
        String hex = hexCipherText.substring(i, i + 2);
        cipherText.add(int.parse(hex, radix: 16));
      }
      debugPrint('Cipher text bytes: $cipherText');

      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha512(),
        iterations: 65536,
        bits: 256,
      );

      final derivedKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(resPassword),
        nonce: resSalt, // Use the same salt as in encryption
      );

      final keyBytes = await derivedKey.extractBytes();

      final aesCbc = AesCbc.with256bits(
        macAlgorithm: MacAlgorithm.empty,
        paddingAlgorithm: PaddingAlgorithm.pkcs7,
      );

      final secretBox = SecretBox(
        cipherText,
        nonce: iv, // Use the same IV as in encryption
        mac: Mac.empty,
      );
      debugPrint('SecretBox: $secretBox');

      final decryptedBytes = await aesCbc.decrypt(
        secretBox,
        secretKey: SecretKey(keyBytes),
      );

      final decryptedText = utf8.decode(decryptedBytes);
      debugPrint('Decrypted text: $decryptedText');
      return decryptedText;
    } catch (e, stackTrace) {
      debugPrint('Decryption error: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  //Generate Signature
  Future<String> generateSignature(Map<String, dynamic> respArray) async {
    debugPrint("Generating signature using response array.");

    final payDetails = respArray['payDetails'];
    final merchDetails = respArray['merchDetails'];
    final responseDetails = respArray['responseDetails'];
    final payModeSpecificData = respArray['payModeSpecificData'];

    // Construct the signature string
    final signatureString =
        '${merchDetails['merchId']}${payDetails['atomTxnId']}${merchDetails['merchTxnId']}${payDetails['totalAmount'].toStringAsFixed(2)}${responseDetails['statusCode']}${payModeSpecificData['subChannel'][0]}${payModeSpecificData['bankDetails']['bankTxnId']}';

    debugPrint("Constructed signature string: $signatureString");

    // Initialize HMAC with the key
    final hmac = Hmac.sha512();
    final secretKey = SecretKey(utf8.encode(resHashKey));
    final signatureBytes = await hmac.calculateMac(
      utf8.encode(signatureString),
      secretKey: secretKey,
    );

    debugPrint("HMAC updated with signature string.");

    // Generate the HMAC (signature)
    final genHmac = signatureBytes.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    debugPrint("Generated HMAC (signature): $genHmac");

    return genHmac;
  }

  //Initiate the payment (Send request to atom server)
  Future<void> initiatePayment() async {
    setState(() {
      isLoading = true;
      currentTxnId =
          'Invoice${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    });

    try {
      final String txnDate = DateTime.now().toString().split('.')[0];
      const String amount = "100";
      const String userEmailId = "test.user@atomtech.in";
      const String userContactNo = "8888888888";

      //Json data for sending to atom server
      String jsonData =
          '{"payInstrument":{"headDetails":{"version":"OTSv1.1","api":"AUTH","platform":"FLASH"},"merchDetails":{"merchId":"$merchId","userId":"","password":"$merchPass","merchTxnId":"$currentTxnId","merchTxnDate":"$txnDate"},"payDetails":{"amount":"$amount","product":"$prodId","custAccNo":"213232323","txnCurrency":"INR"},"custDetails":{"custEmail":"$userEmailId","custMobile":"$userContactNo"},  "extras": {"udf1":"udf1","udf2":"udf2","udf3":"udf3","udf4":"udf4","udf5":"udf5"}}}';

      final String encDataR = await encrypt(jsonData);
      final response = await http.post(
        Uri.parse(authUrl),
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
        },
        body: {
          'encData': encDataR,
          'merchId': merchId,
        },
      );
      if (response.statusCode == 200) {
        debugPrint("Response received: Status code 200");

        final responseData = response.body.split('&');
        debugPrint("Response body split into array: $responseData");

        if (responseData.length > 1) {
          // Extract the encrypted data
          final encDataPart = responseData
              .firstWhere((element) => element.startsWith('encData'));
          final encryptedData = encDataPart.split('=')[1];
          final extractedData = ['encData', encryptedData];
          debugPrint("Extracted encrypted response data: $extractedData");

          try {
            // Decrypt the extracted data
            final decryptedData = await decrypt(extractedData[1]);
            debugPrint("Decrypted data: $decryptedData");

            final jsonResponse = json.decode(decryptedData);
            debugPrint("JSON response: $jsonResponse");

            if (jsonResponse['responseDetails']['txnStatusCode'] == 'OTS0000') {
              setState(() {
                atomTokenId = jsonResponse['atomTokenId'].toString();
                isLoading = false;
                // ignore: prefer_interpolation_to_compose_strings
                debugPrint("Transaction Status Code: " +
                    jsonResponse['responseDetails']['txnStatusCode']);
              });
            } else {
              debugPrint("Error: txnStatusCode is not 'OTS0000'");
              throw Exception('Payment initialization failed');
            }
          } catch (e) {
            debugPrint("Decryption failed: $e");
            throw Exception('Error during decryption: $e');
          }
        } else {
          debugPrint("Error: Invalid response data format");
          throw Exception('Invalid response data format');
        }
      } else {
        debugPrint(
            "Error: Failed to connect to the server. Status code: ${response.statusCode}");
        throw Exception('Failed to connect to the server');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      // showError('Payment initialization failed: $e');
    }
  }

  // Payment Response
  Future<void> handlePaymentResponse(String encData) async {
    try {
      debugPrint('Handling payment response with encData: $encData');

      final decryptedData = await decrypt(encData);
      debugPrint('Decrypted response data: $decryptedData');

      // Step 2: Send decrypted data to your Node.js server
      final response = await http.post(
        Uri.parse('http://localhostfdfdf:3000/Response'),
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
        },
        body: {
          'decryptedData': decryptedData, // Send the decrypted data to server
          'merchId': merchId,
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        debugPrint('Server response: $jsonData');

        final respArray = jsonData as Map<String, dynamic>;
        debugPrint('Response array constructed: $respArray');

        final signature = await generateSignature(respArray);
        debugPrint('Generated signature for validation: $signature');

        if (signature == respArray['payDetails']['signature']) {
          debugPrint('Signature matched. Validating transaction status.');

          if (respArray['responseDetails']['statusCode'] == 'OTS0000') {
            debugPrint('Transaction successful');
            //showSuccess('Transaction successful');
            debugPrint('Complete response array: $respArray');
          } else {
            debugPrint(
                'Transaction failed with status code: ${respArray['responseDetails']['statusCode']}');
            //showError('Transaction failed');
          }
        } else {
          debugPrint('Signature mismatched!! Transaction failed');
          //showError('Transaction failed - Invalid signature');
        }
      } else {
        debugPrint('Server error: ${response.statusCode}');
        //showError('Server error occurred');
      }
    } catch (e) {
      debugPrint('Error processing payment response: $e');
      //showError('Error processing payment response: $e');
    }
  }

  // void showError(String message) {
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(content: Text(message), backgroundColor: Colors.red),
  //   );
  // }

  // void showSuccess(String message) {
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(content: Text(message), backgroundColor: Colors.green),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        toolbarHeight: 100,
        title: const Text(
          'Merchant Shop',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 20.0),
              child: Text(
                "Atom Token ID: $atomTokenId",
                style: const TextStyle(
                    fontSize: 16.0, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              margin:
                  const EdgeInsets.symmetric(vertical: 10.0, horizontal: 30),
              child: Text(
                "Transaction ID: $currentTxnId",
                style: const TextStyle(
                    fontSize: 16.0, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 20.0),
              child: const Text(
                "Pay Rs: 1.00",
                style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 20.0),
              child: isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue),
                      onPressed: () {
                        // Navigator.push(
                        //     context,
                        //     MaterialPageRoute(
                        //         builder: (context) => WebHtmlView(
                        //               atomTokenId: atomTokenId.toString(),
                        //               merchId: merchId,
                        //               currentTxnId: currentTxnId,
                        //             )));
                      },
                      child: const Text(
                        'Pay Now',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


// class WebHtmlView extends StatefulWidget {
//   final String atomTokenId;
//   final String merchId;
//   final String currentTxnId;

//   const WebHtmlView({
//     required this.atomTokenId,
//     required this.merchId,
//     required this.currentTxnId,
//     super.key,
//   });

//   @override
//   State<WebHtmlView> createState() => _WebHtmlViewState();
// }

// class _WebHtmlViewState extends State<WebHtmlView> {
//   final String viewId = 'payment-view-${DateTime.now().millisecondsSinceEpoch}';

//   @override
//   void initState() {
//     super.initState();
//     log("atomTokenId : ${widget.atomTokenId}");

//     // Register iframe only once
   
//       ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
//         final iframe = IFrameElement()
//           ..style.border = 'none'
//           ..style.width = '100%'
//           ..style.height = '100%'
//           ..setAttribute("sandbox", "allow-scripts allow-same-origin allow-forms allow-popups")
//           ..allow = "payment"
//           ..srcdoc = '''
//             <!DOCTYPE html>
//             <html>
//             <head>
//               <meta name="viewport" content="width=device-width, initial-scale=1">
//               <script src="https://pgtest.atomtech.in/staticdata/ots/js/atomcheckout.js"></script>
//               <style>
//                 body { margin: 0; padding: 0; width: 100%; height: 100%; }
//                 #payment-form { width: 100%; height: 100%; }
//               </style>
//             </head>
//             <body>
//               <div id="payment-form"></div>
//               <script>
//                 function initPayment() {
//                   const options = {
//                     "atomTokenId": "${widget.atomTokenId}",
//                     "merchId": "${widget.merchId}",
//                     "custEmail": "test.user@gmail.com",
//                     "custMobile": "8888888888",
//                     "returnUrl": "https://www.atomtech.in/aipay-demo/uat_response",
//                   };
//                   new AtomPaynetz(options, 'uat');

//                   // Notify Flutter when payment is done
//                   window.addEventListener("message", function(event) {
//                     if (event.origin === "https://pgtest.atomtech.in") {
//                       window.parent.postMessage(event.data, "*");
//                     }
//                   });
//                 }

//                 document.addEventListener('DOMContentLoaded', initPayment);
//               </script>
//             </body>
//             </html>
//           ''';

//         return iframe;
//       });
    

//     // Listen for messages from iframe
//     window.onMessage.listen((event) {
//       if (event.origin == "https://pgtest.atomtech.in") {
//         log("Payment Response: ${event.data}");
//         // Handle the payment response (navigate or show a success/failure message)
//       }
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SizedBox.expand(
//         child: HtmlElementView(
//           viewType: viewId,
//         ),
//       ),
//     );
//   }
// }

