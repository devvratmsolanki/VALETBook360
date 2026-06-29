import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valet_driver_app/models/assignment.dart';
import 'package:valet_driver_app/state/clock.dart';
import 'package:valet_driver_app/theme/v_theme.dart';
import 'package:valet_driver_app/widgets/mission_card.dart';

/// Regression test for the driver-panel crash: MissionCard's Column distributes
/// content with flex Spacers, so it must receive a BOUNDED height. Inside the
/// mission screen's SingleChildScrollView the incoming maxHeight is infinite, so
/// the card is pinned to a tight height. This reproduces that exact constraint
/// chain and asserts the card lays out without the "RenderFlex children have
/// non-zero flex but incoming height constraints are unbounded" assertion.
void main() {
  testWidgets('MissionCard lays out under a tight height inside a scroll view',
      (tester) async {
    final mission = Assignment.fromJson(const {
      'id': '0401f2d6-9bd0-40a4-8740-66cca1c9e0f8',
      'carPlate': 'GJ01MW9024',
      'carMake': 'merc',
      'carModel': 'maybach',
      'carColor': 'dual',
      'keyCode': 'GV1',
      'status': 'waiting_for_driver',
      'guestName': 'Devvrat',
      'locationId': '33333333-3333-3333-3333-333333333333',
      'requestedAt': null,
      'missionType': 'park',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWith((ref) => Stream.value(DateTime(2026, 6, 29))),
        ],
        child: MaterialApp(
          theme: buildValetLightTheme(),
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints.tightFor(
                          height: constraints.maxHeight - 24,
                        ).copyWith(maxWidth: 640),
                        child: MissionCard(
                          mission: mission,
                          busy: false,
                          onAdvance: (_) async {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // No RenderFlex/unbounded-constraint assertion was thrown during layout.
    expect(tester.takeException(), isNull);
    expect(find.text('GJ01MW9024'), findsOneWidget);
  });
}
