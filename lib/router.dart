import 'package:ble_test/screens/advertise.dart';
import 'package:ble_test/screens/discovery.dart';
import 'package:ble_test/screens/home.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

part 'router.g.dart';

@TypedGoRoute<HomeRoute>(path: "/")
class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return HomeScreen();
  }
}

@TypedGoRoute<AdvertiseRoute>(path: "/advertise")
class AdvertiseRoute extends GoRouteData with $AdvertiseRoute {
  const AdvertiseRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return AdvertiseScreen();
  }
}

@TypedGoRoute<DiscoveryRoute>(path: "/discovery")
class DiscoveryRoute extends GoRouteData with $DiscoveryRoute {
  const DiscoveryRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return DiscoveryScreen();
  }
}

final router = GoRouter(routes: $appRoutes);
