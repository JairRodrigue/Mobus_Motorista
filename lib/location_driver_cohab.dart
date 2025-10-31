import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';

class LocationDriverCohab extends StatefulWidget {
  const LocationDriverCohab({super.key});

  @override
  State<LocationDriverCohab> createState() => _LocationDriverCohabState();
}

class _LocationDriverCohabState extends State<LocationDriverCohab> {
  bool _showMap = false;
  LatLng _currentPosition = LatLng(-8.05, -34.9); // posição inicial (Recife)
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;
  List<LatLng> _routePoints = [];

  final DatabaseReference _rotaRef =
      FirebaseDatabase.instance.ref('onibus/cohab/rota');
  final DatabaseReference _atualRef =
      FirebaseDatabase.instance.ref('onibus/cohab/localizacao_atual');

  DateTime? _lastSent;

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
        const SnackBar(content: Text("Permissão de localização negada")),
      );
      return;
    }

    setState(() {
      _showMap = true;
    });

    Position pos = await Geolocator.getCurrentPosition();
    _updateLocation(pos);

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position pos) {
      _updateLocation(pos);
    });
  }

  Future<void> _updateLocation(Position pos) async {
    LatLng newPos = LatLng(pos.latitude, pos.longitude);

    setState(() {
      _currentPosition = newPos;
      _routePoints.add(newPos);
      if (_routePoints.length > 500) {
        _routePoints.removeRange(0, _routePoints.length - 500);
      }
    });

    _mapController.move(newPos, 17);

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
    await _positionStream?.cancel();

    await _rotaRef.remove();
    await _atualRef.remove();

    setState(() {
      _showMap = false;
      _routePoints.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Rota encerrada!"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: const Text(
          "Compartilhar: Ônibus Cohab I",
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
      body: Center(
        child: _showMap
            ? FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentPosition,
                  initialZoom: 16,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                    subdomains: const ['a', 'b', 'c'],
                  ),
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          strokeWidth: 5.0,
                          color: Colors.blueAccent,
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
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.directions_bus_rounded,
                      size: 100,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(height: 30),
                    Text(
                      "Motorista Cohab I: Iniciar Compartilhamento",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Pressione o botão abaixo para começar a transmitir a localização do seu ônibus em tempo real para os passageiros.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton.icon(
                      onPressed: () => _shareLocation(context),
                      icon: const Icon(Icons.share_location, size: 28),
                      label: const Text(
                        'Compartilhar Localização',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 5,
                      ),
                    ),
                  ],
                ),
              ),
      ),
      floatingActionButton: _showMap
          ? FloatingActionButton.extended(
              onPressed: _finishRoute,
              icon: const Icon(Icons.flag, color: Colors.white),
              label: const Text(
                "Chegou ao destino",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.red.shade700,
              elevation: 6,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
