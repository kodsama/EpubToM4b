/// Step 3: all conversion options, with best-practice defaults preselected.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/tts/sherpa_catalog.dart';
import '../../data/tts/voice_catalog.dart';
import '../../domain/conversion_options.dart';
import '../../logic/app_controller.dart';
import '../../util/platform_env.dart';
import '../theme.dart';
import 'section_card.dart';

/// Exposes every conversion option in the UI. Voice list follows the selected
/// backend + language; API-key fields appear only for cloud backends; the cover
/// can be overridden or left to the EPUB's embedded image.
class OptionsPanel extends StatelessWidget {
  final AppController controller;
  final bool expanded;
  final VoidCallback? onToggle;
  final bool done;
  const OptionsPanel({
    super.key,
    required this.controller,
    this.expanded = true,
    this.onToggle,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final o = controller.options;
    return SectionCard(
      step: 3,
      title: 'Tune the narration',
      subtitle: 'Engine, voice, and output',
      dimmed: o == null,
      expanded: expanded,
      onToggle: onToggle,
      done: done,
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
                if (controller.needsModelDownload) ...[
                  const SizedBox(height: 16),
                  _ModelSetup(controller: controller),
                ],
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
          items: [
            for (final k in TtsBackendKind.values)
              DropdownMenuItem(value: k, child: Text(k.label)),
          ],
          onChanged: (k) => k == null ? null : controller.setBackend(k),
        ),
      );

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
    // Local engine → sherpa model catalog for the language; cloud → cloud voices.
    final items = o.backend == TtsBackendKind.local
        ? [
            for (final m in sherpaModelsFor(o.languageCode))
              (id: m.id, label: m.label)
          ]
        : [
            for (final v in VoiceCatalog.voices(o.backend, o.languageCode))
              (id: v.id, label: v.label)
          ];
    final hasSelected = items.any((i) => i.id == o.voiceId);
    return _Labeled(
      o.backend == TtsBackendKind.local ? 'Model / voice' : 'Voice',
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue:
            hasSelected ? o.voiceId : (items.isEmpty ? null : items.first.id),
        items: [
          for (final i in items)
            DropdownMenuItem(value: i.id, child: Text(i.label)),
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

/// One-click setup: downloads the selected local model on demand.
class _ModelSetup extends StatelessWidget {
  final AppController controller;
  const _ModelSetup({required this.controller});

  @override
  Widget build(BuildContext context) {
    final installing = controller.installingModel;
    final model = controller.selectedModel;
    final mb = model?.sizeMb ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.amber.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: installing ? null : controller.setupModel,
            icon: installing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTokens.ink))
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(installing
                ? 'Downloading… ${(controller.downloadProgress * 100).round()}%'
                : 'Download ${model?.label ?? 'model'}'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              installing
                  ? 'Fetching the model (~$mb MB). Watch the log below.'
                  : 'Free, offline, runs on your machine. One-time ~$mb MB download.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
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
    // On mobile there is no folder picker; output lands in app storage and is
    // shared from the progress step. Show just the filename + a hint.
    final display = isMobilePlatform ? p.basename(o.outputPath) : o.outputPath;
    return _Labeled(
      isMobilePlatform ? 'Saves as (share when done)' : 'Save to',
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
              child:
                  Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (!isMobilePlatform) ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _pickLocation,
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text('Change'),
            ),
          ],
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
