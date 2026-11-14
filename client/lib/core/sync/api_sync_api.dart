import '../network/api_client.dart';
import '../storage/file_stream.dart';
import 'sync_engine.dart';

/// [SyncApi] against the backend: `POST /sync`, `POST /files/presign`, presigned S3 PUT.
class ApiSyncApi implements SyncApi {
  ApiSyncApi(this.api);
  final ApiClient api;

  @override
  Future<List<SyncResult>> push(List<Map<String, dynamic>> ops) async {
    final res = await api.post('/sync', body: {'ops': ops}) as Map<String, dynamic>;
    return (res['results'] as List).map((r) => SyncResult.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  @override
  Future<Presigned> presign({required String purpose, required String contentType, required int sizeBytes}) async {
    final r = await api.post('/files/presign', body: {'purpose': purpose, 'contentType': contentType, 'sizeBytes': sizeBytes}) as Map<String, dynamic>;
    return Presigned(
      uploadUrl: r['uploadUrl'] as String,
      key: r['key'] as String,
      headers: Map<String, String>.from(r['headers'] as Map),
    );
  }

  @override
  Future<void> upload(Presigned target, String localPath) => api.putToPresignedUrl(target.uploadUrl, openFileStream(localPath), target.headers);
}
