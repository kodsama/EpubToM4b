/// Step 1: choose an EPUB and review its metadata + chapter selection.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../logic/app_controller.dart';
import '../theme.dart';
import 'section_card.dart';

/// Lets the user pick an `.epub`, then shows the parsed cover, metadata, and a
/// per-chapter include/exclude checklist.
class FilePickerCard extends StatelessWidget {
  final AppController controller;
  const FilePickerCard({super.key, required this.controller});

  Future<void> _pick() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
        dialogTitle: 'Choose an EPUB',
      );
      final path = result?.files.single.path;
      if (path == null) return; // user cancelled
      final bytes = await File(path).readAsBytes();
      await controller.loadBook(bytes, path);
    } on Object catch (e) {
      controller.log.error('Could not open file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = controller.book;
    return SectionCard(
      step: 2,
      title: 'Choose your book',
      subtitle: controller.environmentReady
          ? 'A DRM-free EPUB file'
          : 'Finish the toolkit step first',
      dimmed: !controller.environmentReady,
      trailing: book == null
          ? null
          : const StatusPill('Loaded', icon: Icons.check_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: Text(book == null ? 'Browse for EPUB…' : 'Choose a different EPUB'),
              ),
            ],
          ),
          if (controller.parseError != null) ...[
            const SizedBox(height: 14),
            Text(controller.parseError!,
                style: const TextStyle(color: AppTokens.rust)),
          ],
          if (book != null) ...[
            const SizedBox(height: 18),
            _Metadata(controller: controller),
            const SizedBox(height: 18),
            _ChapterList(controller: controller),
          ],
        ],
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  final AppController controller;
  const _Metadata({required this.controller});

  @override
  Widget build(BuildContext context) {
    final book = controller.book!;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: book.hasCover
              ? Image.memory(book.coverBytes!,
                  width: 84, height: 120, fit: BoxFit.cover)
              : Container(
                  width: 84,
                  height: 120,
                  color: AppTokens.surfaceHigh,
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: AppTokens.muted),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(book.title, style: text.headlineSmall),
              const SizedBox(height: 4),
              Text(book.author, style: text.bodyMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(book.languageCode.toUpperCase(),
                      color: AppTokens.amber, icon: Icons.translate_rounded),
                  StatusPill('${book.chapters.length} chapters',
                      color: AppTokens.muted, icon: Icons.list_rounded),
                  StatusPill('${(book.totalChars / 1000).round()}k chars',
                      color: AppTokens.muted, icon: Icons.notes_rounded),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChapterList extends StatelessWidget {
  final AppController controller;
  const _ChapterList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final book = controller.book!;
    final selected = controller.options!.selectedChapterIndices;
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.ink,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.line),
      ),
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: book.chapters.length,
        itemBuilder: (context, i) {
          final ch = book.chapters[i];
          final on = selected.contains(ch.index);
          return CheckboxListTile(
            dense: true,
            value: on,
            onChanged: (_) => controller.toggleChapter(ch.index),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTokens.amber,
            checkColor: AppTokens.ink,
            title: Text(ch.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${ch.charCount} chars'),
          );
        },
      ),
    );
  }
}
