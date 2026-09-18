import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/places_service.dart';

/// Address search box with debounced Places Autocomplete suggestions.
/// Calls [onResolved] with lat/lng + formatted address once the user picks
/// a suggestion -- callers own what to do with that (save to a profile,
/// etc.), this widget only owns the search/select interaction.
class LocationSearchField extends StatefulWidget {
  final String? initialText;
  final String label;
  final void Function(ResolvedPlace place) onResolved;
  const LocationSearchField({super.key, this.initialText, required this.label, required this.onResolved});

  @override
  State<LocationSearchField> createState() => _LocationSearchFieldState();
}

class _LocationSearchFieldState extends State<LocationSearchField> {
  late final _ctrl = TextEditingController(text: widget.initialText ?? '');
  List<PlaceSuggestion> _suggestions = [];
  bool _loading = false;
  bool _resolving = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _loading = true);
      final places = context.read<PlacesService>();
      final results = await places.autocomplete(value);
      if (mounted) setState(() {
        _suggestions = results;
        _loading = false;
      });
    });
  }

  Future<void> _select(PlaceSuggestion s) async {
    setState(() {
      _ctrl.text = s.description;
      _suggestions = [];
      _resolving = true;
    });
    final places = context.read<PlacesService>();
    final resolved = await places.resolve(s.placeId);
    if (mounted) setState(() => _resolving = false);
    if (resolved != null) widget.onResolved(resolved);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _ctrl,
          onChanged: _onChanged,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'Search for an area, landmark, or address',
            suffixIcon: (_loading || _resolving)
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : const Icon(Icons.search),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _suggestions
                  .map((s) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on_outlined, size: 20),
                        title: Text(s.description, style: const TextStyle(fontSize: 14)),
                        onTap: () => _select(s),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
