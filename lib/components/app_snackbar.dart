import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppSnackbar {
  AppSnackbar._();

  static void show(
    String title,
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    final context = Get.context;
    final colorScheme = context != null
        ? Theme.of(context).colorScheme
        : ColorScheme.fromSeed(seedColor: Colors.blue);

    final backgroundColor = isError
        ? colorScheme.errorContainer
        : colorScheme.surfaceContainerHigh;
    final foregroundColor = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSurface;

    Get.closeAllSnackbars();
    Get.showSnackbar(
      GetSnackBar(
        snackPosition: SnackPosition.TOP,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        borderRadius: 16,
        backgroundColor: backgroundColor,
        duration: duration,
        isDismissible: true,
        dismissDirection: DismissDirection.horizontal,
        snackStyle: SnackStyle.FLOATING,
        messageText: Text(message, style: TextStyle(color: foregroundColor)),
        titleText: Text(
          title,
          style: TextStyle(color: foregroundColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
