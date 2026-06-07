import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MessageBubble extends StatelessWidget {
  final String text;
  final bool isUser;

  const MessageBubble({super.key, required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final textColor = isUser
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: isUser
            ? SelectableText(
                text,
                style: TextStyle(color: textColor, fontSize: 15),
              )
            : SelectionArea(
                child: MarkdownBody(
                  data: text,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: TextStyle(color: textColor, fontSize: 15),
                    strong: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15),
                    em: TextStyle(color: textColor, fontStyle: FontStyle.italic, fontSize: 15),
                    listBullet: TextStyle(color: textColor, fontSize: 15),
                    blockquote: TextStyle(color: textColor, fontSize: 15),
                    code: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
