import 'package:flutter_test/flutter_test.dart';
import 'package:duchamp_essential_ui/backend/backend_connection.dart';

void main() {
  test('paused controls are Disabled, not Live or a fake Offline', () {
    expect(
      DuchampConnectionState.online.serviceLabel(enabled: false),
      'Disabled',
    );
    expect(DuchampConnectionState.online.serviceLabel(enabled: true), 'Live');
    expect(
      DuchampConnectionState.offline.serviceLabel(enabled: false),
      'Offline',
    );
    expect(
      DuchampConnectionState.connecting.serviceLabel(enabled: false),
      'Connecting',
    );
  });
  test('only a successful handshake is Live', () {
    expect(DuchampConnectionState.fromNative(1), DuchampConnectionState.online);
    expect(DuchampConnectionState.fromNative(1).badgeLabel, 'LIVE');
  });

  test('startup and a confirmed connection failure remain distinct', () {
    expect(
      DuchampConnectionState.fromNative(-1),
      DuchampConnectionState.connecting,
    );
    expect(DuchampConnectionState.fromNative(-1).badgeLabel, 'CONNECTING');
    expect(DuchampConnectionState.fromNative(0), DuchampConnectionState.offline);
    expect(DuchampConnectionState.fromNative(0).badgeLabel, 'OFFLINE');
  });
}
