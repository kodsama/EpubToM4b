/// Step 3: all conversion options, with best-practice defaults preselected.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/tts/voice_catalog.dart';
import '../../domain/conversion_options.dart';
import '../../logic/app_controller.dart';
import '../theme.dart';
import 'section_card.dart';

/// Exposes every conversion option in the UI. Voice list follows the selected
/// backend + language; API-key fields appear only for cloud backends; the cover
/// can be overridden or left to the EPUB's embedded image.
class OptionsPanel extends StatelessWidget {
  final AppController controller;
  const OptionsPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final o = controller.options;
    return SectionCard(
      step: 3,
      title: 'Tune the narration',
      subtitle: 'Engine, voice, and output',
      dimmed: o == null,
      child: o == null
          ? const Text('Load a book first.',
              style: TextStyle(color: AppTokens.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Grid(children: [
                  _backendField(o),
                  _languageField(o),
                  _voiceField(o),
                  _bitrateField(o),
                ]),
                const SizedBox(height: 18),
                _speedSlider(context, o),
                if (o.backend.isCloud) ...[
                  const SizedBox(height: 8),
                  _ApiKeyField(controller: controller),
                ],
                const SizedBox(height: 18),
                _CoverField(controller: controller),
                const SizedBox(height: 18),
                _OutputField(controller: controller),
              ],
            ),
    );
  }

  Widget _backendField(ConversionOptions o) => _Labeled(
        'TTS engine',
        DropdownButtonFormField<TtsBackendKind>(
          isExpanded: true,
          initialValue: o.backend,
          selectedItemBuilder: (context) => [
            for (final k in TtsBackendKind.values) Text(k.label),
          ],
          items: [
            for (final k in TtsBackendKind.values)
              DropdownMenuItem(
                value: k,
                enabled: controller.backendAvailable(k),
                child: _engineItem(k),
              ),
          ],
          onChanged: (k) =>
              (k == null || !controller.backendAvailable(k))
                  ? null
                  : controller.setBackend(k),
        ),
      );

  /// Dropdown row for an engine: greyed with a reason when not selectable.
  Widget _engineItem(TtsBackendKind k) {
    final available = controller.backendAvailable(k);
    if (available) return Text(k.label);
    return Row(
      children: [
        Expanded(
          child: Text(k.label, style: const TextStyle(color: AppTokens.muted)),
        ),
        Text('· ${controller.unavailableReason(k)}',
            style: const TextStyle(color: AppTokens.muted, fontSize: 12)),
      ],
    );
  }

  Widget _languageField(ConversionOptions o) {
    final langs = VoiceCatalog.languages(o.backend);
    return _Labeled(
      'Language',
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: langs.any((l) => l.code == o.languageCode)
            ? o.languageCode
            : (langs.isEmpty ? null : langs.first.code),
        items: [
          for (final l in langs)
            DropdownMenuItem(value: l.code, child: Text(l.label)),
        ],
        onChanged: (c) => c == null ? null : controller.setLanguage(c),
      ),
    );
  }

  Widget _voiceField(ConversionOptions o) {
    final voices = VoiceCatalog.voices(o.backend, o.languageCode);
    return _Labeled(
      'Voice',
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue:
            voices.any((v) => v.id == o.voiceId) ? o.voiceId : (voices.isEmpty ? null : voices.first.id),
        items: [
          for (final v in voices)
            DropdownMenuItem(value: v.id, child: Text(v.label)),
        ],
        onChanged: (id) => id == null
            ? null
            : controller.updateOptions((o) => o.copyWith(voiceId: id)),
      ),
    );
  }

  Widget _bitrateField(ConversionOptions o) => _Labeled(
        'Quality (bitrate)',
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: o.bitrate,
          items: const [
            DropdownMenuItem(value: '96k', child: Text('96 kbps (small)')),
            DropdownMenuItem(value: '128k', child: Text('128 kbps (recommended)')),
            DropdownMenuItem(value: '192k', child: Text('192 kbps (rich)')),
          ],
          onChanged: (b) => b == null
              ? null
              : controller.updateOptions((o) => o.copyWith(bitrate: b)),
        ),
      );

  Widget _speedSlider(BuildContext context, ConversionOptions o) => _Labeled(
        'Narration speed — ${o.speed.toStringAsFixed(2)}×',
        Slider(
          value: o.speed,
          min: 0.5,
          max: 2.0,
          divisions: 30,
          activeColor: AppTokens.amber,
          label: '${o.speed.toStringAsFixed(2)}×',
          onChanged: (v) =>
              controller.updateOptions((o) => o.copyWith(speed: v)),
        ),
      );

}

/// Obscured API-key input that owns its [TextEditingController] so typing isn't
/// disrupted by parent rebuilds.
class _ApiKeyField extends StatefulWidget {
  final AppController controller;
  const _ApiKeyField({required this.controller});

  @override
  State<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<_ApiKeyField> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    final o = widget.controller.options!;
    _field = TextEditingController(text: o.apiKeys[o.backend.name] ?? '');
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.controller.options!.backend;
    return _Labeled(
      '${backend.label} API key',
      TextField(
        controller: _field,
        obscureText: true,
        decoration: const InputDecoration(hintText: 'Paste your secret key'),
        onChanged: (v) => widget.controller.updateOptions(
          (o) => o.copyWith(apiKeys: {...o.apiKeys, o.backend.name: v}),
        ),
      ),
    );
  }
}

/// Cover override row: shows the override or "from EPUB", with a picker.
class _CoverField extends StatelessWidget {
  final AppController controller;
  const _CoverField({required this.controller});

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      dialogTitle: 'Choose a cover image',
    );
    final path = res?.files.single.path;
    if (path != null) {
      controller.updateOptions((o) => o.copyWith(coverOverridePath: path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = controller.options!;
    final label = o.coverOverridePath != null
        ? p.basename(o.coverOverridePath!)
        : (controller.book!.hasCover ? "Using the EPUB's cover" : 'No cover');
    return _Labeled(
      'Cover image',
      Row(
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.image_outlined, size: 16),
            label: const Text('Override'),
          ),
        ],
      ),
    );
  }
}

/// Output filename + destination folder picker.
class _OutputField extends StatelessWidget {
  final AppController controller;
  const _OutputField({required this.controller});

  Future<void> _pickLocation() async {
    final o = controller.options!;
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save audiobook as…',
      fileName: p.basename(o.outputPath),
      type: FileType.custom,
      allowedExtensions: ['m4b'],
    );
    if (path != null) {
      final fixed = path.endsWith('.m4b') ? path : '$path.m4b';
      controller.updateOptions((o) => o.copyWith(outputPath: fixed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = controller.options!;
    return _Labeled(
      'Save to',
      Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTokens.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTokens.line),
              ),
              child: Text(o.outputPath,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _pickLocation,
            icon: const Icon(Icons.folder_open_rounded, size: 16),
            label: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

/// Two-column responsive grid for compact option fields.
class _Grid extends StatelessWidget {
  final List<Widget> children;
  const _Grid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final twoCol = c.maxWidth > 520;
      final width = twoCol ? (c.maxWidth - 16) / 2 : c.maxWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children)
            SizedBox(width: width, child: child),
        ],
      );
    });
  }
}

/// A labeled form field (caption above the control).
class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled(this.label, this.child);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
