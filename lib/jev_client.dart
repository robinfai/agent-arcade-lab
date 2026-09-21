import 'dart:convert';
import 'package:http/http.dart' as http;

class JevClient {
  final String baseUrl;
  final http.Client client = http.Client();
  final String endpoint;
  JevClient(this.baseUrl, {this.endpoint = '/v1/systemone'});
  Future<Map<String, dynamic>> decide(Map<String, dynamic> request) async {
    final timer = Stopwatch()..start();
    final response = await client
        .post(
          Uri.parse('$baseUrl$endpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(request),
        )
        .timeout(const Duration(seconds: 180));
    timer.stop();
    if (response.statusCode != 200) {
      throw StateError('API ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    data['_http_ms'] = timer.elapsedMicroseconds / 1000;
    data['_inference_ms'] = double.tryParse(
      response.headers['x-inference-ms'] ?? '',
    );
    return data;
  }

  void close() => client.close();
}
