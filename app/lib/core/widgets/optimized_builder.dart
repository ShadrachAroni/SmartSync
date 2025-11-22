import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builder that prevents unnecessary rebuilds
class OptimizedBuilder<T> extends ConsumerWidget {
  final ProviderBase<AsyncValue<T>> provider;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loading;
  final Widget Function(BuildContext context, Object error, StackTrace stack)? error;

  const OptimizedBuilder({
    super.key,
    required this.provider,
    required this.builder,
    this.loading,
    this.error,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(provider);
    
    return asyncValue.when(
      data: (data) => builder(context, data),
      loading: () => loading ?? const Center(child: CircularProgressIndicator()),
      error: (err, stack) => error?.call(context, err, stack) ??
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(height: 8),
                Text('Error: $err'),
              ],
            ),
          ),
    );
  }
}

/// Memoized widget that only rebuilds when data actually changes
class MemoizedWidget extends StatelessWidget {
  final Widget child;
  final Object? keyValue;

  const MemoizedWidget({
    super.key,
    required this.child,
    this.keyValue,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MemoizedWidget && other.keyValue == keyValue;
  }

  @override
  int get hashCode => keyValue.hashCode;
}

