import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

class QuoteWidgetHelper {
  static const _widgetId = 'QuoteWidgetProvider';

  static Future<void> updateQuote(String quote) async {
    await HomeWidget.saveWidgetData<String>('quote', quote);
    await HomeWidget.updateWidget(name: _widgetId);
  }
}

class QuotePage extends StatelessWidget {
  const QuotePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Quote Widget')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Ketik quote...',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                QuoteWidgetHelper.updateQuote(controller.text);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Widget updated')),
                );
              },
              child: const Text('Update Widget'),
            ),
          ],
        ),
      ),
    );
  }
}
