import 'package:flutter/material.dart';

import 'integration.dart';
import 'services.dart';
import 'settings.dart';

/// Top-level shell. Uses a [NavigationBar] on narrow viewports and a
/// [NavigationRail] on wider ones so the same app feels right on web and
/// mobile without a separate desktop layout.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = <Widget>[
    ServicesScreen(),
    IntegrationScreen(),
    SettingsScreen(),
  ];

  static const _destinations = <_Dest>[
    _Dest(Icons.account_tree_outlined, Icons.account_tree, 'Services'),
    _Dest(Icons.swap_horiz, Icons.swap_horiz, 'Integration'),
    _Dest(Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Scaffold(
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: _Brand(),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _pages[_index]),
              ],
            )
          : _pages[_index],
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.hub, color: theme.colorScheme.primary, size: 32),
        const SizedBox(height: 4),
        Text(
          'SAP\nGateway',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
