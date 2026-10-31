import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:school_link_protocol/protocol.dart';

import 'discovered_hub.dart';

class HubDiscovery {
  Future<List<DiscoveredHub>> discover({
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        hubUdpPort,
        reuseAddress: true,
      );
    } catch (_) {
      return const [];
    }
    final found = <String, DiscoveredHub>{};
    final query = utf8.encode(jsonEncode({
      'svc': 'schoollink',
      'type': 'discover',
      'v': protocolVersion,
    }));

    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket!.receive();
      if (datagram == null) return;
      try {
        final data = asMap(jsonDecode(utf8.decode(datagram.data)));
        if (asString(data['svc']) != 'schoollink' ||
            asString(data['type']) != 'hub') {
          return;
        }
        final port = asInt(data['port'], hubHttpPort);
        final url = 'http://${datagram.address.address}:$port';
        found[url] = DiscoveredHub(
          url: url,
          hubId: asString(data['hubId']),
          name: asString(data['name'], '校联服务器'),
          version: asString(data['version']),
        );
      } catch (_) {}
    });

    void broadcastQuery() {
      try {
        socket!.send(query, InternetAddress('255.255.255.255'), hubUdpPort);
      } catch (_) {}
      try {
        socket!.send(query, InternetAddress.loopbackIPv4, hubUdpPort);
      } catch (_) {}
      // Most school networks use /24; try the subnet broadcast of each NIC.
      NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)
          .then((interfaces) {
        for (final interface in interfaces) {
          for (final address in interface.addresses) {
            final parts = address.address.split('.');
            if (parts.length != 4) continue;
            final broadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            try {
              socket!.send(query, InternetAddress(broadcast), hubUdpPort);
            } catch (_) {}
          }
        }
      }).catchError((_) {});
    }

    broadcastQuery();
    Timer(const Duration(milliseconds: 400), broadcastQuery);
    Timer(const Duration(milliseconds: 900), broadcastQuery);
    await Future<void>.delayed(timeout);
    await subscription.cancel();
    socket.close();
    final result = found.values.toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }
}
