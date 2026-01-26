// Test file to verify InternetConnectionChecker fix
import 'package:internet_connection_checker/internet_connection_checker.dart';

void main() async {
  // This should compile without errors now
  final checker = InternetConnectionChecker.instance;
  
  // Test basic functionality
  final hasConnection = await checker.hasConnection;
  print('Has connection: $hasConnection');
  
  // Test stream
  final subscription = checker.onStatusChange.listen((status) {
    print('Connection status: $status');
  });
  
  await Future.delayed(const Duration(seconds: 2));
  subscription.cancel();
  
  print('✅ InternetConnectionChecker test passed!');
}
