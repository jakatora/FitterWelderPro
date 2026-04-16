import 'dart:convert';

class WelderPipeParam {
  final int? id;

  final String material;
  final double odMm;
  final double wtMm;

  final double amps;
  final String method; // 'WTC' | 'FREE_HAND'
  final double cupSize;
  final double electrodeMm;
  final String torchGas;
  final String pipeGas;

  // NEW
  final int outletHolesCount; // default 1
  final String weldTempo; // 'SLOW' | 'NORMAL' | 'FAST'

  final bool purgeEnabled;
  final double? purgeFlowLpm;

  final bool wireEnabled;
  final double? wireMm;

  final String? notes;

  final String signature;

  final DateTime createdAt;
  final DateTime updatedAt;

  const WelderPipeParam({
    this.id,
    required this.material,
    required this.odMm,
    required this.wtMm,
    required this.amps,
    required this.method,
    required this.cupSize,
    required this.electrodeMm,
    required this.torchGas,
    required this.pipeGas,
    required this.outletHolesCount,
    required this.weldTempo,
    required this.purgeEnabled,
    required this.purgeFlowLpm,
    required this.wireEnabled,
    required this.wireMm,
    required this.notes,
    required this.signature,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'material': material,
        'od_mm': odMm,
        'wt_mm': wtMm,
        'amps': amps,
        'method': method,
        'cup_size': cupSize,
        'electrode_mm': electrodeMm,
        'torch_gas': torchGas,
        'pipe_gas': pipeGas,
        'outlet_holes_count': outletHolesCount,
        'weld_tempo': weldTempo,
        'purge_enabled': purgeEnabled ? 1 : 0,
        'purge_flow_lpm': purgeFlowLpm,
        'wire_enabled': wireEnabled ? 1 : 0,
        'wire_mm': wireMm,
        'notes': notes,
        'signature': signature,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static WelderPipeParam fromMap(Map<String, Object?> m) => WelderPipeParam(
        id: m['id'] as int?,
        material: (m['material'] as String?) ?? '',
        odMm: (m['od_mm'] as num).toDouble(),
        wtMm: (m['wt_mm'] as num).toDouble(),
        amps: (m['amps'] as num).toDouble(),
        method: (m['method'] as String?) ?? 'WTC',
        cupSize: (m['cup_size'] as num).toDouble(),
        electrodeMm: (m['electrode_mm'] as num).toDouble(),
        torchGas: (m['torch_gas'] as String?) ?? '',
        pipeGas: (m['pipe_gas'] as String?) ?? '',
        outletHolesCount: (m['outlet_holes_count'] as int?) ?? 1,
        weldTempo: (m['weld_tempo'] as String?) ?? 'NORMAL',
        purgeEnabled: (m['purge_enabled'] as int) == 1,
        purgeFlowLpm: m['purge_flow_lpm'] == null ? null : (m['purge_flow_lpm'] as num).toDouble(),
        wireEnabled: (m['wire_enabled'] as int) == 1,
        wireMm: m['wire_mm'] == null ? null : (m['wire_mm'] as num).toDouble(),
        notes: m['notes'] as String?,
        signature: (m['signature'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );

  Map<String, dynamic> toCommunityPayload() => {
        'module': 'welder_pipe',
        'material': material,
        'od_mm': odMm,
        'wt_mm': wtMm,
        'amps': amps,
        'method': method,
        'cup_size': cupSize,
        'electrode_mm': electrodeMm,
        'torch_gas': torchGas,
        'pipe_gas': pipeGas,
        'outlet_holes_count': outletHolesCount,
        'weld_tempo': weldTempo,
        'purge_enabled': purgeEnabled,
        'purge_flow_lpm': purgeFlowLpm,
        'wire_enabled': wireEnabled,
        'wire_mm': wireMm,
      };

  String toJson() => jsonEncode(toCommunityPayload());
}
