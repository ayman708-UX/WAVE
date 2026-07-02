import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/router/app_router.dart';

/// Description of one of the 5 main navigation destinations. Bottom nav
/// variants and the desktop sidebar both consume this list.
@immutable
class NavDestination {
  const NavDestination({
    required this.label,
    required this.route,
    required this.icon,
    required this.iconFilled,
  });

  final String label;
  final String route;
  final IconData icon;
  final IconData iconFilled;
}

/// The 5 root tabs in fixed order — index matches `activeTabIndex` in
/// [AppShell].
final List<NavDestination> kNavDestinations = <NavDestination>[
  NavDestination(
    label: 'Home',
    route: AppRoutes.home,
    icon: PhosphorIconsRegular.house,
    iconFilled: PhosphorIconsFill.house,
  ),
  NavDestination(
    label: 'Discover',
    route: AppRoutes.discover,
    icon: PhosphorIconsRegular.compass,
    iconFilled: PhosphorIconsFill.compass,
  ),
  NavDestination(
    label: 'Search',
    route: AppRoutes.search,
    icon: PhosphorIconsRegular.magnifyingGlass,
    iconFilled: PhosphorIconsFill.magnifyingGlass,
  ),
  NavDestination(
    label: 'Library',
    route: AppRoutes.library,
    icon: PhosphorIconsRegular.stack,
    iconFilled: PhosphorIconsFill.stack,
  ),
];
