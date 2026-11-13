import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/app_settings.dart';
import '../services/playback_service.dart';

/// Volume boost, equalizer, pitch and skip silence.
/// Settings apply to every book and are remembered.
class SoundSheet extends StatefulWidget {
  const SoundSheet({super.key});

  @override
  State<SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<SoundSheet> {
  final _s = AppSettings.instance;
  final _service = PlaybackService.instance;
  AndroidEqualizerParameters? _eq;
  List<double> _gains = [];

  @override
  void initState() {
    super.initState();
    _loadEq();
  }

  Future<void> _loadEq() async {
    try {
      final params = await _service.equalizer.parameters;
      final saved = _s.eqGains;
      if (!mounted) return;
      setState(() {
        _eq = params;
        _gains = [
          for (var i = 0; i < params.bands.length; i++)
            i < saved.length ? saved[i] : 0.0
        ];
      });
    } catch (_) {
      // Equalizer not available on this phone: section stays hidden.
    }
  }

  void _apply() => _service.applySoundSettings();

  String _freq(double hz) =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k' : '${hz.round()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eq = _eq;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text('Sound', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),

          // ---- Volume boost ----
          Text('Volume boost: ${_s.boostDb == 0 ? 'off' : '+${_s.boostDb} dB'}'),
          Slider(
            value: _s.boostDb.toDouble(),
            min: 0,
            max: 15,
            divisions: 15,
            label: '+${_s.boostDb} dB',
            onChanged: (v) => setState(() => _s.boostDb = v.round()),
            onChangeEnd: (_) => _apply(),
          ),

          // ---- Pitch ----
          Row(children: [
            Expanded(child: Text('Pitch: ${_s.pitch.toStringAsFixed(2)}')),
            if (_s.pitch != 1.0)
              TextButton(
                onPressed: () {
                  setState(() => _s.pitch = 1.0);
                  _apply();
                },
                child: const Text('Reset'),
              ),
          ]),
          Slider(
            value: _s.pitch,
            min: 0.5,
            max: 1.5,
            divisions: 20,
            label: _s.pitch.toStringAsFixed(2),
            onChanged: (v) => setState(() => _s.pitch = (v * 20).round() / 20),
            onChangeEnd: (_) => _apply(),
          ),

          // ---- Skip silence ----
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Skip silence'),
            subtitle: const Text('Cut long pauses between words'),
            value: _s.skipSilence,
            onChanged: (v) {
              setState(() => _s.skipSilence = v);
              _apply();
            },
          ),

          // ---- Equalizer ----
          if (eq != null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Equalizer'),
              value: _s.eqEnabled,
              onChanged: (v) {
                setState(() => _s.eqEnabled = v);
                _apply();
              },
            ),
            if (_s.eqEnabled) ...[
              SizedBox(
                height: 180,
                child: Row(
                  children: [
                    for (var i = 0; i < eq.bands.length; i++)
                      Expanded(
                        child: Column(
                          children: [
                            Text('${_gains[i].round()}',
                                style: theme.textTheme.bodySmall),
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3, // vertical slider
                                child: Slider(
                                  value: _gains[i].clamp(eq.minDecibels, eq.maxDecibels),
                                  min: eq.minDecibels,
                                  max: eq.maxDecibels,
                                  onChanged: (v) => setState(() => _gains[i] = v),
                                  onChangeEnd: (_) {
                                    _s.eqGains = _gains;
                                    _apply();
                                  },
                                ),
                              ),
                            ),
                            Text(_freq(eq.bands[i].centerFrequency),
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() => _gains = List.filled(_gains.length, 0.0));
                    _s.eqGains = _gains;
                    _apply();
                  },
                  child: const Text('Flat'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
