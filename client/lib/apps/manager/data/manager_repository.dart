import '../../../core/network/api_client.dart';
import 'models.dart';

/// Every control-tower call (Section 10.6). Online only: no outbox for managers (Section 10.6).
class ManagerRepository {
  ManagerRepository(this.api);
  final ApiClient api;

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? q]) async => map(await api.get(path, query: q?..removeWhere((_, v) => v == null || v == '')));

  // dashboard
  Future<ControlSummary> summary() async => ControlSummary.fromJson(await _get('/control/summary'));

  // masters (cached by the server's ETag; small lists)
  Future<Map<String, dynamic>> bundle() => _get('/masters/bundle');
  Future<List<Map<String, dynamic>>> vehicles() async => maps(await api.get('/masters/vehicles'));
  Future<List<Map<String, dynamic>>> drivers() async => maps((await _get('/control/drivers'))['items']);

  // trips (#2)
  Future<ApiPage> trips({String? status, String? date, String? cursor}) async => ApiPage.fromJson(await api.get('/trips', query: {'status': ?status, 'date': ?date, 'cursor': ?cursor, 'limit': 30}));
  Future<Map<String, dynamic>> trip(String id) => _get('/trips/$id');
  Future<Map<String, dynamic>> route(String id) => _get('/trips/$id/route');
  Future<TelemetrySeries> telemetry(String id, DateTime from, DateTime to, {String every = '5m'}) async =>
      TelemetrySeries.fromJson(await _get('/trips/$id/telemetry', {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String(), 'every': every}));
  Future<void> assign(String tripId, {required String driverId, required String vehicleId}) => api.post('/trips/$tripId/assign', body: {'driverId': driverId, 'vehicleId': vehicleId});

  // alerts + incidents (#3)
  Future<ApiPage> alerts({String? status, String? cursor}) async => ApiPage.fromJson(await api.get('/alerts', query: {'status': ?status, 'cursor': ?cursor, 'limit': 30}));
  Future<void> ackAlert(String id) => api.post('/alerts/$id/ack');
  Future<void> resolveAlert(String id) => api.post('/alerts/$id/resolve');
  Future<ApiPage> incidents({String? status, String? cursor}) async => ApiPage.fromJson(await api.get('/incidents', query: {'status': ?status, 'cursor': ?cursor, 'limit': 30}));
  Future<Map<String, dynamic>> incident(String id) => _get('/incidents/$id');
  Future<void> incidentAction(String id, String action, {String? buyerId, String? rescueTripId, String? note}) =>
      api.post('/incidents/$id/action', body: {'action': action, 'buyerId': ?buyerId, 'rescueTripId': ?rescueTripId, 'note': ?note});
  Future<void> resolveIncident(String id, {String? note, bool failed = false}) => api.post('/incidents/$id/resolve', body: {'note': ?note, 'failed': failed});

  // forecast (#4)
  Future<List<ForecastDay>> forecast({required String siteId, required String productId, required DateTime from, required DateTime to}) async {
    String d(DateTime x) => '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final rows = await api.get('/forecasts', query: {'siteId': siteId, 'productId': productId, 'from': d(from), 'to': d(to)});
    return [for (final r in maps(rows)) ForecastDay.fromJson(r)]..sort((a, b) => a.day.compareTo(b.day));
  }

  Future<String> runForecast() async => '${map(await api.post('/forecasts/run', body: const {}))['id']}';
  Future<Map<String, dynamic>> forecastJob(String id) => _get('/forecasts/jobs/$id');

  // planning (#5)
  Future<Map<String, dynamic>> runPlanner(String date) async => map(await api.post('/planning/run', body: {'date': date}));
  Future<ApiPage> orders({String? status, String? date}) async => ApiPage.fromJson(await api.get('/orders', query: {'status': ?status, 'date': ?date, 'limit': 100}));
  Future<void> editOrder(String id, {double? quantityKg, String? destinationSiteId}) => api.patch('/orders/$id', body: {'quantityKg': ?quantityKg, 'destinationSiteId': ?destinationSiteId});
  Future<Map<String, dynamic>> approveOrder(String id) async => map(await api.post('/orders/$id/approve'));
  Future<Map<String, dynamic>> buildRoutes(String date, String depotSiteId) async => map(await api.post('/planning/routes', body: {'date': date, 'depotSiteId': depotSiteId}));

  // approvals (#6)
  Future<ApiPage> editRequests() async => ApiPage.fromJson(await api.get('/edit-requests', query: {'status': 'PENDING', 'limit': 50}));
  Future<void> decideEdit(String id, bool approve, {String? note}) => api.post('/edit-requests/$id/${approve ? 'approve' : 'reject'}', body: {'note': ?note});
  Future<ApiPage> disputes() async => ApiPage.fromJson(await api.get('/grades/disputes', query: {'limit': 50}));
  Future<void> resolveDispute(String gradeId, String grade) => api.post('/grades/$gradeId/resolve', body: {'grade': grade});

  // buyers (#7)
  Future<ApiPage> buyers({String? cursor}) async => ApiPage.fromJson(await api.get('/buyers', query: {'active': 'true', 'cursor': ?cursor, 'limit': 50}));
  Future<void> saveBuyer(String? id, Map<String, dynamic> body) => id == null ? api.post('/buyers', body: body) : api.patch('/buyers/$id', body: body);
  Future<void> deleteBuyer(String id) => api.delete('/buyers/$id');

  // admin (#8, #9)
  Future<ApiPage> users({String? role, String? q, String? cursor}) async => ApiPage.fromJson(await api.get('/admin/users', query: {'role': ?role, 'q': ?q, 'cursor': ?cursor, 'limit': 50}));
  Future<void> saveUser(String? id, Map<String, dynamic> body) => id == null ? api.post('/admin/users', body: body) : api.patch('/admin/users/$id', body: body);
  Future<void> setUserDisabled(String id, bool disabled) => api.post('/admin/users/$id/${disabled ? 'disable' : 'enable'}');
  Future<List<Map<String, dynamic>>> masterList(String entity) async => maps(await api.get('/masters/$entity'));
  Future<void> saveMaster(String entity, String? id, Map<String, dynamic> body) => id == null ? api.post('/masters/$entity', body: body) : api.patch('/masters/$entity/$id', body: body);
  Future<Object?> config(String key) async => map(await api.get('/config/$key'))['value'];
  Future<void> setConfig(String key, Object? value) => api.put('/config/$key', body: {'value': value});

  // reports (#10)
  Future<String> complianceHtml(String batchId) async => '${await api.get('/reports/batches/$batchId/compliance', query: {'format': 'html'})}';
  Future<String> traceabilityCsv(String from, String to) async => '${await api.get('/reports/traceability', query: {'from': from, 'to': to, 'format': 'csv'})}';
  Future<Map<String, dynamic>> emissions(String from, String to) => _get('/reports/emissions', {'from': from, 'to': to, 'format': 'json'});
  Future<String> emissionsCsv(String from, String to) async => '${await api.get('/reports/emissions', query: {'from': from, 'to': to, 'format': 'csv'})}';
  Future<List<Map<String, dynamic>>> reeferHealth() async => maps(await api.get('/reports/reefer-health'));
  Future<ApiPage> findBatches(String q) async => ApiPage.fromJson(await api.get('/batches', query: {'q': q, 'limit': 10}));

  // releases (#11)
  Future<List<Map<String, dynamic>>> releases() async => maps((await _get('/control/releases'))['items']);
}
