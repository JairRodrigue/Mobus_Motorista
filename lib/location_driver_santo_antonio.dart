import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';

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

  final List<LatLng> _routeHistory = [];

  final List<BusStop> _busStops = [];

  final DatabaseReference _rotaRef =
      FirebaseDatabase.instance.ref('onibus/santo_antonio/rota');
  final DatabaseReference _atualRef = FirebaseDatabase.instance
      .ref('onibus/santo_antonio/localizacao_atual');
  final DatabaseReference _pontosRef =
      FirebaseDatabase.instance.ref('onibus/santo_antonio/pontos_passados');
  final DatabaseReference _statusRef =
      FirebaseDatabase.instance.ref('onibus/santo_antonio/status');

  DateTime? _lastSent;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadBusStops();
  }

  void _loadBusStops() {
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

    setState(() {});
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
      _routeHistory.clear();
      _routeHistory.add(_currentPosition);
    });

    _updateLocation(pos);

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0),
    ).listen((Position pos) async {
      await _updateLocation(pos);
    });

    await _statusRef.set({'finalizada': false});
  }

  Future<void> _updateLocation(Position pos) async {
    LatLng newPos = LatLng(pos.latitude, pos.longitude);

    setState(() {
      _currentPosition = newPos;
      if (_showMap) {
        _routeHistory.add(newPos);
      }
    });

    _checkBusStops(newPos);

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
    try {
      await _statusRef.set({
        'finalizada': true,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _rotaRef.remove();
      _atualRef.remove();
      _pontosRef.remove();
    } catch (e) {}

    await _positionStream?.cancel();

    if (mounted) {
      setState(() {
        _showMap = false;
        _routeHistory.clear();
        for (var stop in _busStops) {
          stop.passed = false;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Rota encerrada e status enviado!"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
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
              Navigator.of(context).pop();
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
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routeHistory,
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
            SafeArea(
              top: false,
              child: Padding(
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
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 25),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}