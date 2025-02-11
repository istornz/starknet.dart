import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> callRpcEndpoint(
    {required Uri nodeUri, required String method, Object? params}) async {
  const headers = {
    'Content-Type': 'application/json',
  };

  final body = {
    'jsonrpc': '2.0',
    'method': method,
    'params': params ?? [],
    'id': 0
  };

  final response =
      await http.post(nodeUri, headers: headers, body: json.encode(body));

  final jsonResponse = json.decode(response.body);

  return jsonResponse;
}
