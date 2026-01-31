// lib/utils/thermal_scheduler.dart
// Thermal-aware task scheduling for battery optimization

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Thermal-aware task scheduler to reduce battery drain and device heating
class ThermalScheduler {
  static ThermalScheduler? _instance;
  static ThermalScheduler get instance => _instance ??= ThermalScheduler._();
  
  ThermalScheduler._();
  
  // Track high activity periods
  DateTime? _lastHighActivityTime;
  int _recentTaskCount = 0;
  static const int _maxTasksPerMinute = 10;
  
  /// Check if device is likely overheating (heuristic-based)
  bool get isDeviceHot {
    // Heuristic: If we've done many tasks recently, slow down
    if (_recentTaskCount > _maxTasksPerMinute) return true;
    
    // Check if we've been highly active recently
    if (_lastHighActivityTime != null) {
      final timeSinceActivity = DateTime.now().difference(_lastHighActivityTime!);
      if (timeSinceActivity < const Duration(minutes: 2)) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Schedule a task with thermal awareness
  /// Low priority tasks are delayed if device is hot
  Future<T> scheduleTask<T>(
    Future<T> Function() task, {
    bool lowPriority = false,
    Duration? timeout,
  }) async {
    _recentTaskCount++;
    
    // Decay task count over time
    Future.delayed(const Duration(seconds: 10), () {
      if (_recentTaskCount > 0) _recentTaskCount--;
    });
    
    // If low priority and device is hot, delay execution
    if (lowPriority && isDeviceHot) {
      if (kDebugMode) print('ThermalScheduler: Delaying low-priority task due to thermal throttling');
      await Future.delayed(const Duration(seconds: 5));
    }
    
    // Execute with optional timeout
    if (timeout != null) {
      return Future<T>.value(await task()).timeout(timeout);
    }
    
    return await task();
  }
  
  /// Mark start of high activity (e.g., rapid scrolling, heavy UI)
  void markHighActivity() {
    _lastHighActivityTime = DateTime.now();
  }
  
  /// Batch multiple tasks to reduce CPU wakeups
  Future<List<T>> batchTasks<T>(
    List<Future<T> Function()> tasks, {
    int concurrency = 3,
    Duration delayBetweenBatches = const Duration(milliseconds: 100),
  }) async {
    final results = <T>[];
    
    for (int i = 0; i < tasks.length; i += concurrency) {
      final batch = tasks.skip(i).take(concurrency).toList();
      
      final batchResults = await Future.wait(batch.map((t) => t()));
      results.addAll(batchResults);
      
      // Small delay between batches to allow CPU rest
      if (i + concurrency < tasks.length) {
        await Future.delayed(delayBetweenBatches);
      }
    }
    
    return results;
  }
  
  /// Schedule a background task that should run when device is cooler
  void scheduleDeferred(Future<void> Function() task, {Duration delay = const Duration(seconds: 30)}) {
    Future.delayed(delay, () async {
      // Check thermal state before running
      if (!isDeviceHot) {
        await task();
      } else {
        // Reschedule if still hot
        scheduleDeferred(task, delay: const Duration(minutes: 1));
      }
    });
  }
  
  /// Reset thermal tracking (e.g., on app pause)
  void reset() {
    _recentTaskCount = 0;
    _lastHighActivityTime = null;
  }
}
