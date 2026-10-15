import 'models.dart';

/// What the widgets need from slate. The host (isconl through hub's slate
/// routes, or slate's own app) implements it; tests use a fake.
abstract class SlateClient {
  Future<List<SessionInfo>> sessions();

  /// Sends a directive and returns its id. The caller has already passed
  /// step-up; this never prompts.
  Future<String> sendCommand(CommandDraft draft);

  Future<DeliveryState> deliveryState(String commandId);
}

/// Step-up before a command is sent (a passkey in isconl). Returns true when
/// the operator proved presence.
typedef StepUp = Future<bool> Function(CommandDraft draft);
