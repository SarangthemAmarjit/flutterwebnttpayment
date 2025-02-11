import 'package:flutter_web_kit/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_kit/paymentresponse.dart';
import 'package:get/get.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const PayPage(), title: 'Home Page'),
        GetPage(
            name: '/response',
            page: () => const PaymentresponsePage(),
            title: 'Payment Result'),
      ],
      title: 'NTT Data Payment Flutter Kit',
    );
  }
}
