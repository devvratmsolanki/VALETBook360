import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valet_driver_app/api/api_client.dart';
import 'package:valet_driver_app/api/token_store.dart';
import 'package:valet_driver_app/models/company.dart';
import 'package:valet_driver_app/screens/admin_companies_pane.dart';
import 'package:valet_driver_app/state/providers.dart';
import 'package:valet_driver_app/theme/v_theme.dart';

class _FakeTokenStore implements TokenStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// Fake client feeding the companies pane a canned list (or an empty one for
/// the empty-state test). Mirrors the controller-test fakes.
class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.companies) : super(_FakeTokenStore());
  final List<Company> companies;
  @override
  Future<List<Company>> fetchCompanies() async => companies;
}

Widget _wrap(ApiClient client) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      theme: buildValetDarkTheme(),
      home: const AdminCompaniesPane(),
    ),
  );
}

void main() {
  testWidgets('renders a card per company once loaded', (tester) async {
    await tester.pumpWidget(_wrap(_FakeApiClient(const [
      Company(id: '1', companyName: 'Demo Valet Co'),
      Company(id: '2', companyName: 'Skyline Parking'),
    ])));
    // load() runs in the controller constructor; let it settle.
    await tester.pumpAndSettle();

    expect(find.text('Demo Valet Co'), findsOneWidget);
    expect(find.text('Skyline Parking'), findsOneWidget);
    expect(find.text('New company'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no companies',
      (tester) async {
    await tester.pumpWidget(_wrap(_FakeApiClient(const [])));
    await tester.pumpAndSettle();

    expect(find.text('No companies yet'), findsOneWidget);
  });
}
