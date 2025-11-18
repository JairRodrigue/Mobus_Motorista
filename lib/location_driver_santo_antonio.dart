import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

class BusStop {
  final String id;
  final LatLng position;
  final String name;
  bool passed;

  BusStop({
    required this.id,
    required this.position,
    required this.name,
    this.passed = false,
  });
}

class LocationDriverSantoAntonio extends StatefulWidget {
  const LocationDriverSantoAntonio({super.key});

  @override
  State<LocationDriverSantoAntonio> createState() =>
      _LocationDriverSantoAntonioState();
}

class _LocationDriverSantoAntonioState
    extends State<LocationDriverSantoAntonio> {
  bool _showMap = false;
  LatLng _currentPosition = LatLng(-8.343481692464032, -36.42004505717594);
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  // rota planejada (pontos retornados pelo OSRM)
  List<LatLng> _plannedRoutePoints = [];

  // pontos que o ônibus passa
  final List<BusStop> _busStops = [];

  // Firebase refs (Santo Antônio)
  final DatabaseReference _rotaRef =
      FirebaseDatabase.instance.ref('onibus/santo_antonio/rota');
  final DatabaseReference _atualRef = FirebaseDatabase.instance
      .ref('onibus/santo_antonio/localizacao_atual');
  final DatabaseReference _pontosRef =
      FirebaseDatabase.instance.ref('onibus/santo_antonio/pontos_passados');
  final DatabaseReference _statusRef =
      FirebaseDatabase.instance.ref('onibus/santo_antonio/status');
  final DatabaseReference _estimativasRef =
      FirebaseDatabase.instance.ref('onibus/santo_antonio/estimativas');

  DateTime? _lastSent;

  // estimativas e próximos
  double? _distanciaProxima_m;
  double? _tempoProxima_s;
  double? _distanciaTotal_m;
  double? _tempoTotal_s;
  String? _proximaParadaId;
  String _speedLabel = '28 km/h';

  // velocidade usada para estimativas
  static const double _speedKmH = 28.0;
  static final double _speedMps = _speedKmH * 1000.0 / 3600.0;

  @override
  void initState() {
    super.initState();
    _loadBusStops();
  }

  void _loadBusStops() {
    // Defina as paradas específicas do Santo Antônio (mantive as que você enviou)
    _busStops.clear();
    _busStops.addAll([
      BusStop(
        id: 's1',
        name: 'Erem João Monteiro',
        position: LatLng(-8.339067752350099, -36.43255993416365),
      ),
      BusStop(
        id: 's2',
        name: 'Posto Petrovia',
        position: LatLng(-8.337454040898562, -36.43059339723894),
      ),
      BusStop(
        id: 's3',
        name: 'Bradesco',
        position: LatLng(-8.337935253551777, -36.425932851649314),
      ),
      BusStop(
        id: 's4',
        name: 'Fórum',
        position: LatLng(-8.33711239401202, -36.41898671794646),
      ),
      BusStop(
        id: 's5',
        name: 'Colegial',
        position: LatLng(-8.33377120753406, -36.41841024066295),
      ),
      BusStop(
        id: 's6',
        name: 'Santa Fé',
        position: LatLng(-8.331888692413065, -36.41357140284076),
      ),
      BusStop(
        id: 's7',
        name: 'UABJ',
        position: LatLng(-8.326865277108523, -36.40530664721273),
      ),
      BusStop(
        id: 's8',
        name: 'AEB',
        position: LatLng(-8.320094221176046, -36.39561876255546),
      ),
    ]);

    if (_busStops.isNotEmpty) {
      _currentPosition = _busStops.first.position;
    }

    // constrói rota OSRM inicialmente
    _buildSingleOsrmRoute();
  }

  String _getProximaParadaNome() {
    if (_proximaParadaId == null || _proximaParadaId!.isEmpty) {
      return 'Nenhuma';
    }

    final stop = _busStops.firstWhere(
      (s) => s.id == _proximaParadaId,
      orElse: () =>
          BusStop(id: '', name: 'Nenhuma', position: const LatLng(0, 0)),
    );

    return stop.name;
  }

  Future<void> _buildSingleOsrmRoute() async {
    _plannedRoutePoints = [];

    List<LatLng> coordsForOsrm = [];
    coordsForOsrm.add(_currentPosition);

    for (final stop in _busStops) {
      if (!stop.passed) {
        coordsForOsrm.add(stop.position);
      }
    }

    if (coordsForOsrm.length < 2) {
      if (mounted) setState(() {});
      await _calculateEstimates();
      return;
    }

    final coordsString =
        coordsForOsrm.map((p) => '${p.longitude},${p.latitude}').join(';');

    final url =
        'https://router.project-osrm.org/route/v1/driving/$coordsString?overview=full&geometries=geojson&steps=false';

    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        if (mounted) setState(() {});
        await _calculateEstimates();
        return;
      }

      final Map<String, dynamic> data = json.decode(resp.body);
      if (data['routes'] == null || (data['routes'] as List).isEmpty) {
        if (mounted) setState(() {});
        await _calculateEstimates();
        return;
      }

      final geometry = data['routes'][0]['geometry'];
      if (geometry == null || geometry['coordinates'] == null) {
        if (mounted) setState(() {});
        await _calculateEstimates();
        return;
      }

      final List coords = geometry['coordinates'];
      final List<LatLng> points = coords.map<LatLng>((c) {
        final double lng = (c[0] as num).toDouble();
        final double lat = (c[1] as num).toDouble();
        return LatLng(lat, lng);
      }).toList();

      _plannedRoutePoints = points;
      if (mounted) setState(() {});

      await _calculateEstimates();
    } catch (e) {
      // falha no OSRM -> recalcula estimativas sem polilinha
      if (mounted) setState(() {});
      await _calculateEstimates();
    }
  }

  Future<void> _calculateEstimates() async {
    _distanciaProxima_m = null;
    _tempoProxima_s = null;
    _distanciaTotal_m = null;
    _tempoTotal_s = null;
    _proximaParadaId = null;

    if (_plannedRoutePoints.isEmpty) {
      await _writeEstimatesToFirebase();
      if (mounted) setState(() {});
      return;
    }

    int indexNearestToCurrent =
        _findNearestIndexOnPolyline(_currentPosition, _plannedRoutePoints);

    BusStop? nextStop;
    for (var stop in _busStops) {
      if (!stop.passed) {
        nextStop = stop;
        break;
      }
    }

    double totalRemaining = 0.0;
    for (int i = indexNearestToCurrent;
        i < _plannedRoutePoints.length - 1;
        i++) {
      final a = _plannedRoutePoints[i];
      final b = _plannedRoutePoints[i + 1];
      totalRemaining += Geolocator.distanceBetween(
          a.latitude, a.longitude, b.latitude, b.longitude);
    }

    _distanciaTotal_m = totalRemaining;
    _tempoTotal_s = totalRemaining / _speedMps;

    if (nextStop != null) {
      _proximaParadaId = nextStop.id;
      int indexNearestToStop = _findNearestIndexOnPolyline(
          nextStop.position, _plannedRoutePoints);

      double distToNext = 0.0;
      if (indexNearestToStop <= indexNearestToCurrent) {
        distToNext = Geolocator.distanceBetween(
          _currentPosition.latitude,
          _currentPosition.longitude,
          nextStop.position.latitude,
          nextStop.position.longitude,
        );
      } else {
        for (int i = indexNearestToCurrent; i < indexNearestToStop; i++) {
          final a = _plannedRoutePoints[i];
          final b = _plannedRoutePoints[i + 1];
          distToNext += Geolocator.distanceBetween(
              a.latitude, a.longitude, b.latitude, b.longitude);
        }

        final nearestPointToStop = _plannedRoutePoints[indexNearestToStop];
        final extra = Geolocator.distanceBetween(
            nearestPointToStop.latitude,
            nearestPointToStop.longitude,
            nextStop.position.latitude,
            nextStop.position.longitude);
        if (extra < 50.0) distToNext += extra;
      }

      _distanciaProxima_m = distToNext;
      _tempoProxima_s = distToNext / _speedMps;
    } else {
      _distanciaProxima_m = 0.0;
      _tempoProxima_s = 0.0;
    }

    await _writeEstimatesToFirebase();

    if (mounted) setState(() {});
  }

  int _findNearestIndexOnPolyline(LatLng target, List<LatLng> poly) {
    int bestIndex = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < poly.length; i++) {
      final p = poly[i];
      final d = Geolocator.distanceBetween(
          target.latitude, target.longitude, p.latitude, p.longitude);
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<void> _writeEstimatesToFirebase() async {
    final now = DateTime.now().toIso8601String();

    final Map<String, dynamic> payload = {
      'distancia_proxima_m': _distanciaProxima_m ?? 0.0,
      'distancia_proxima_km':
          _distanciaProxima_m != null ? (_distanciaProxima_m! / 1000.0) : 0.0,
      'tempo_proxima_s': _tempoProxima_s ?? 0.0,
      'tempo_proxima_min':
          _tempoProxima_s != null ? (_tempoProxima_s! / 60.0) : 0.0,
      'proxima_parada_id': _proximaParadaId ?? '',
      'distancia_total_m': _distanciaTotal_m ?? 0.0,
      'distancia_total_km':
          _distanciaTotal_m != null ? (_distanciaTotal_m! / 1000.0) : 0.0,
      'tempo_total_s': _tempoTotal_s ?? 0.0,
      'tempo_total_min':
          _tempoTotal_s != null ? (_tempoTotal_s! / 60.0) : 0.0,
      'speed_kmh': _speedKmH,
      'updated_at': now,
    };

    try {
      await _estimativasRef.set(payload);
    } catch (_) {
      // ignore erros de escrita
    }
  }

  void _checkBusStops(LatLng busPosition) {
    const double proximityThresholdMeters = 75.0;
    List<String> updatedPassedIds = [];

    for (var stop in _busStops) {
      if (!stop.passed) {
        double distance = Geolocator.distanceBetween(
          busPosition.latitude,
          busPosition.longitude,
          stop.position.latitude,
          stop.position.longitude,
        );
        if (distance <= proximityThresholdMeters) {
          stop.passed = true;
        }
      }
      if (stop.passed) updatedPassedIds.add(stop.id);
    }

    final Map<String, bool> passedMap = Map.fromIterable(updatedPassedIds,
        key: (item) => item, value: (item) => true);

    _pontosRef.set(passedMap);

    // Recalcula rota/estimativas ao marcar paradas
    _buildSingleOsrmRoute();

    setState(() {});
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _shareLocation(BuildContext context) async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permissão de localização negada")));
      return;
    }

    Position pos = await Geolocator.getCurrentPosition();

    setState(() {
      _showMap = true;
      _currentPosition = LatLng(pos.latitude, pos.longitude);
    });

    // constrói rota inicializada com a posição atual
    await _buildSingleOsrmRoute();

    _updateLocation(pos);

    _positionStream = Geolocator.getPositionStream(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0),
    ).listen((Position pos) async {
      await _updateLocation(pos);
    });

    await _statusRef.set({'finalizada': false});
  }

  Future<void> _updateLocation(Position pos) async {
    LatLng newPos = LatLng(pos.latitude, pos.longitude);

    setState(() {
      _currentPosition = newPos;
    });

    _checkBusStops(newPos);

    // atualiza rota planejada com OSRM (reconstrução leve)
    await _buildSingleOsrmRoute();

    if (_showMap) {
      _mapController.move(newPos, 17);
    }

    await _atualRef.set({
      'lat': pos.latitude,
      'lng': pos.longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final now = DateTime.now();
    if (_lastSent == null || now.difference(_lastSent!).inSeconds >= 5) {
      _lastSent = now;
      await _rotaRef.push().set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': now.toIso8601String(),
      });
    }
  }

  Future<void> _finishRoute() async {
    await _statusRef.set({
      'finalizada': true,
      'timestamp': DateTime.now().toIso8601String(),
    });

    await _positionStream?.cancel();
    await _rotaRef.remove();
    await _atualRef.remove();
    await _pontosRef.remove();

    setState(() {
      _showMap = false;
      _plannedRoutePoints.clear();
      for (var stop in _busStops) {
        stop.passed = false;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Rota encerrada e status enviado!"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  String _formatMeters(double? meters) {
    if (meters == null) return '--';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.toStringAsFixed(0)} m';
  }

  String _formatSeconds(double? seconds) {
    if (seconds == null) return '--';
    final minutes = (seconds / 60).round();
    if (minutes <= 0) return '<1 min';
    return '$minutes min';
  }

  String _formatSecondsHM(double? seconds) {
    if (seconds == null) return '--';

    int totalSeconds = seconds.round();
    if (totalSeconds <= 0) return '<1 min';

    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}min';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}min';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: const Text(
          "Compartilhar: Ônibus Santo Antônio",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_showMap) {
              _finishRoute();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _showMap
                ? FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _currentPosition,
                      initialZoom: 16,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                        userAgentPackageName: 'com.example.mobus',
                      ),

                      if (_plannedRoutePoints.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _plannedRoutePoints,
                              strokeWidth: 5.0,
                              color: Colors.blue,
                            ),
                          ],
                        ),

                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentPosition,
                            width: 80,
                            height: 80,
                            child: const Icon(
                              Icons.directions_bus,
                              size: 40,
                              color: Colors.blueAccent,
                            ),
                          ),
                          ..._busStops.map((stop) {
                            final color = stop.passed ? Colors.grey : Colors.red;
                            return Marker(
                              point: stop.position,
                              width: 40,
                              height: 40,
                              child: Tooltip(
                                message: stop.name,
                                child: Icon(
                                  Icons.directions_bus_filled_outlined,
                                  color: color,
                                  size: 30,
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_bus_rounded,
                            size: 100, color: Colors.red.shade700),
                        const SizedBox(height: 30),
                        Text(
                          "Motorista Santo Antônio: Iniciar Compartilhamento",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Pressione o botão abaixo para começar a transmitir a localização do seu ônibus em tempo real.",
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                        const SizedBox(height: 40),
                        ElevatedButton.icon(
                          onPressed: () => _shareLocation(context),
                          icon: const Icon(Icons.share_location, size: 28),
                          label: const Text(
                            'Compartilhar Localização',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          if (_showMap)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ElevatedButton.icon(
                onPressed: _finishRoute,
                icon: const Icon(Icons.flag, color: Colors.white),
                label: const Text(
                  "Chegou ao destino",
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 25),
                ),
              ),
            ),

          if (_showMap)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Velocidade média usada: $_speedLabel',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),

                  Text(
                    'Próxima parada: ${_getProximaParadaNome()}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Expanded(
                          child: Text(
                              'Distância até próxima: ${_formatMeters(_distanciaProxima_m)}')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              'Tempo estimado: ${_formatSecondsHM(_tempoProxima_s)}')),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                          child: Text(
                              'Distância total restante: ${_formatMeters(_distanciaTotal_m)}')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              'Tempo total estimado: ${_formatSecondsHM(_tempoTotal_s)}')),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Última atualização: ${DateTime.now().toLocal().toString().split('.')[0]}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
        ],
      ),
      
    );
  }
}
