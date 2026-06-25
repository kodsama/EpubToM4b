/// Step 1: choose an EPUB and review its metadata + chapter selection.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../logic/app_controller.dart';
import '../theme.dart';
import 'section_card.dart';

/// Narration rate measured from a real French audiobook run (≈416k chars →
/// 6.3 h ⇒ ~18 characters/second). Used only for a rough time estimate.
const double _charsPerSecond = 18.3;

/// Formats a character count as a friendly estimated narration time.
String estimateLabel(int chars) {
  final seconds = chars / _charsPerSecond;
  if (seconds < 60) return '~1 min';
  if (seconds < 3600) return '~${(seconds / 60).round()} min';
  return '~${(seconds / 3600).toStringAsFixed(1)} h';
}

/// Lets the user pick an `.epub`, then shows the parsed cover, metadata, and a
/// per-chapter include/exclude checklist.
class FilePickerCard extends StatelessWidget {
  final AppController controller;
  final bool expanded;
  final VoidCallback? onToggle;
  final bool done;
  const FilePickerCard({
    super.key,
    required this.controller,
    this.expanded = true,
    this.onToggle,
    this.done = false,
  });

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
      subtitle: controller.coreToolsReady
          ? 'A DRM-free EPUB file'
          : 'Install the required tools first',
      dimmed: !controller.coreToolsReady,
      expanded: expanded,
      onToggle: onToggle,
      done: done,
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
                style: TextStyle(color: AppTokens.rust)),
          ],
          if (book != null) ...[
            const SizedBox(height: 18),
            _Metadata(controller: controller),
            const SizedBox(height: 16),
            _SelectionSummary(controller: controller),
            const SizedBox(height: 12),
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
                  child: Icon(Icons.image_not_supported_outlined,
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
                  StatusPill(estimateLabel(book.totalChars),
                      color: AppTokens.amber, icon: Icons.schedule_rounded),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A highlighted line summarizing what will actually be converted, updating live
/// as chapters are ticked/unticked.
class _SelectionSummary extends StatelessWidget {
  final AppController controller;
  const _SelectionSummary({required this.controller});

  @override
  Widget build(BuildContext context) {
    final book = controller.book!;
    final selected = controller.options!.selectedChapterIndices;
    final chosen = book.chapters.where((c) => selected.contains(c.index));
    final count = chosen.length;
    final chars = chosen.fold<int>(0, (sum, c) => sum + c.charCount);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTokens.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.amber.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.playlist_add_check_rounded,
              size: 18, color: AppTokens.amberBright),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 0
                  ? 'No chapters selected'
                  : 'Converting $count of ${book.chapters.length} chapters  ·  '
                      '${(chars / 1000).round()}k chars  ·  ${estimateLabel(chars)} of audio',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
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
