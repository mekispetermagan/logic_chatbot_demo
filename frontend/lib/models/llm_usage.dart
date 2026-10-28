class LlmUsage {
  const LlmUsage({
    required this.status,
    required this.model,
    this.costUsd,
    this.reservedUsd = 0,
    this.inputTokens,
    this.outputTokens,
  });

  factory LlmUsage.fromJson(Map<String, dynamic> json) => LlmUsage(
    status: json['status'] as String,
    model: json['model'] as String,
    costUsd: (json['costUsd'] as num?)?.toDouble(),
    reservedUsd: (json['reservedUsd'] as num? ?? 0).toDouble(),
    inputTokens: json['inputTokens'] as int?,
    outputTokens: json['outputTokens'] as int?,
  );

  final String status;
  final String model;
  final double? costUsd;
  final double reservedUsd;
  final int? inputTokens;
  final int? outputTokens;
}

class LlmBudget {
  const LlmBudget({
    this.limitUsd,
    required this.spentUsd,
    required this.reservedUsd,
    this.remainingUsd,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.pendingUsageCount = 0,
  });

  factory LlmBudget.fromJson(Map<String, dynamic> json) => LlmBudget(
    limitUsd: (json['limitUsd'] as num?)?.toDouble(),
    spentUsd: (json['spentUsd'] as num).toDouble(),
    reservedUsd: (json['reservedUsd'] as num).toDouble(),
    remainingUsd: (json['remainingUsd'] as num?)?.toDouble(),
    inputTokens: json['inputTokens'] as int? ?? 0,
    outputTokens: json['outputTokens'] as int? ?? 0,
    pendingUsageCount: json['pendingUsageCount'] as int? ?? 0,
  );

  final double? limitUsd;
  final double spentUsd;
  final double reservedUsd;
  final double? remainingUsd;
  final int inputTokens;
  final int outputTokens;
  final int pendingUsageCount;
}
