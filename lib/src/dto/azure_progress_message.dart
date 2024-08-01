class AzureProgressMessage {
  final double progress;
  final Object? error;
  final bool completed;

  AzureProgressMessage({
    required this.progress,
    this.error,
    this.completed = false,
  });

  @override
  bool operator ==(covariant AzureProgressMessage other) {
    if (identical(this, other)) return true;

    return other.progress == progress &&
        other.error == error &&
        other.completed == completed;
  }

  @override
  int get hashCode => progress.hashCode ^ error.hashCode ^ completed.hashCode;
}
