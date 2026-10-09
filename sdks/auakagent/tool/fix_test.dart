import 'dart:io';

void main() {
  var content = File('test/agent_proxy_scenario_test.dart').readAsStringSync();
  content = content.replaceAll('return null;', 'return <String, dynamic>{};');
  content = content.replaceAll('return {};', 'return <String, dynamic>{};');
  File('test/agent_proxy_scenario_test.dart').writeAsStringSync(content);
  print('Done');
}
