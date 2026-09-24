/// NDT per method on the weld card: why the weld is examined (required /
/// selected / additional §341.3.4), the result, the report number and date.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/weld_journal/weld_dates.dart';
import '../../domain/weld_journal/weld_ndt.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import 'wj_ui.dart';

String ndtScopeLabel(BuildContext context, String scope) => switch (scope) {
      NdtScope.required =>
        context.tr(pl: 'wymagane (100%)', en: 'required (100%)'),
      NdtScope.selected =>
        context.tr(pl: 'wybrana (losowo)', en: 'selected (random)'),
      NdtScope.progressive =>
        context.tr(pl: 'dodatkowa §341.3.4', en: 'additional §341.3.4'),
      _ => context.tr(pl: 'nie badana', en: 'not examined'),
    };

/// Editor of all five methods. Owns its text controllers; reports every
/// change through [onChanged] with the full, compacted map.
class WeldNdtEditor extends StatefulWidget {
  final Map<NdtMethod, WeldNdt> initial;
  final ValueChanged<Map<NdtMethod, WeldNdt>> onChanged;

  const WeldNdtEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<WeldNdtEditor> createState() => _WeldNdtEditorState();
}

class _WeldNdtEditorState extends State<WeldNdtEditor> {
  late final Map<NdtMethod, WeldNdt> _ndt = {
    for (final m in NdtMethod.values) m: widget.initial[m] ?? const WeldNdt(),
  };
  late final Map<NdtMethod, TextEditingController> _report = {
    for (final m in NdtMethod.values)
      m: TextEditingController(text: _ndt[m]!.reportNo),
  };
  late final Map<NdtMethod, TextEditingController> _date = {
    for (final m in NdtMethod.values)
      m: TextEditingController(text: _ndt[m]!.date),
  };
  late final Set<NdtMethod> _open = {
    for (final m in NdtMethod.values)
      if (!_ndt[m]!.isEmpty) m,
  };

  @override
  void dispose() {
    for (final c in [..._report.values, ..._date.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(NdtMethod m, WeldNdt n) {
    setState(() => _ndt[m] = n);
    widget.onChanged(compactNdt(_ndt));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in NdtMethod.values) _method(context, m),
      ],
    );
  }

  Widget _method(BuildContext context, NdtMethod m) {
    final n = _ndt[m]!;
    final open = _open.contains(m);
    final resultColor = n.isRejected
        ? kFail
        : (n.result == NdtResult.ok ? kPass : kTextSec);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: n.isRejected ? kFail : kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open ? _open.remove(m) : _open.add(m)),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(m.code,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: kText)),
                  ),
                  Expanded(
                    child: Text(
                      n.isEmpty
                          ? ndtScopeLabel(context, NdtScope.none)
                          : [
                              if (n.scope.isNotEmpty)
                                ndtScopeLabel(context, n.scope),
                              if (n.result.isNotEmpty) n.result,
                              if (n.reportNo.isNotEmpty) n.reportNo,
                            ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: resultColor),
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: kTextSec),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: NdtScope.values.contains(n.scope)
                        ? n.scope
                        : NdtScope.none,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr(
                          pl: '${m.code} — zakres badania',
                          en: '${m.code} — examination scope'),
                    ),
                    items: [
                      for (final s in NdtScope.values)
                        DropdownMenuItem(
                            value: s, child: Text(ndtScopeLabel(context, s))),
                    ],
                    onChanged: (v) => _set(m, n.copyWith(scope: v ?? '')),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in [
                        (NdtResult.none, context.tr(pl: 'brak', en: 'none'),
                            kTextSec),
                        (NdtResult.ok, 'OK', kPass),
                        (NdtResult.nok, 'NOK', kFail),
                      ])
                        WjChoiceChip(
                          label: r.$2,
                          selected: n.result == r.$1,
                          color: r.$3,
                          onTap: () => _set(m, n.copyWith(result: r.$1)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  WjRow([
                    TextField(
                      controller: _report[m],
                      decoration: InputDecoration(
                          labelText: context.tr(
                              pl: 'Nr raportu', en: 'Report no.')),
                      onChanged: (v) =>
                          _set(m, _ndt[m]!.copyWith(reportNo: v.trim())),
                    ),
                    TextField(
                      controller: _date[m],
                      keyboardType: TextInputType.datetime,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                      ],
                      decoration: InputDecoration(
                        labelText: context.tr(pl: 'Data', en: 'Date'),
                        hintText: 'RRRR-MM-DD',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.today_outlined, size: 20),
                          tooltip: context.tr(pl: 'Dziś', en: 'Today'),
                          onPressed: () {
                            final today = isoDate(DateTime.now());
                            _date[m]!.text = today;
                            _set(m, _ndt[m]!.copyWith(date: today));
                          },
                        ),
                      ),
                      onChanged: (v) =>
                          _set(m, _ndt[m]!.copyWith(date: v.trim())),
                    ),
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Validates the NDT dates typed into the editor; returns the normalised
/// map, or null when a date is not a real date (the caller refuses to save).
Map<NdtMethod, WeldNdt>? normalizeNdtDates(Map<NdtMethod, WeldNdt> ndt) {
  final out = <NdtMethod, WeldNdt>{};
  for (final e in ndt.entries) {
    final d = normalizeWeldDate(e.value.date);
    if (d == null) return null;
    out[e.key] = e.value.copyWith(date: d);
  }
  return compactNdt(out);
}
