import 'models.dart';
import 'rows_models.dart';

/// What the widgets need from slate. The host (isconl through hub's slate
/// routes, or slate's own app) implements it; tests use a fake.
///
/// Every write here is called only after the host's [WriteStepUp] or
/// [StepUp] passed, so implementations never prompt.
abstract class SlateClient {
  Future<List<SessionInfo>> sessions();

  /// Sends a directive and returns its id.
  Future<String> sendCommand(CommandDraft draft);

  Future<DeliveryState> deliveryState(String commandId);

  /// Live rows, optionally narrowed. `type` is plan, build, work, light or content.
  Future<List<RowSummary>> rows({String? type, String? project});

  Future<RowDetail> row(String id, String project);
  Future<void> claimRow(String id, String project);
  Future<void> closeRow(String id, String project, String note);
  Future<void> editRow(String id, String project, {String? title, String? body});

  /// Rows gated on a decision or an acknowledgement.
  Future<List<RowSummary>> decisions();

  /// Records the answer on the row the way plan-decisions does, clearing the gate.
  Future<void> answerDecision(String id, String project, String answer);

  /// Rows gated on a brainstorm.
  Future<List<RowSummary>> brainstorms();

  Future<List<BlockerInfo>> blockers();
  Future<void> clearBlocker(String id, String evidence);

  Future<MatrixData> matrix();
  Future<TodayData> today();
}

/// Step-up before a command is sent (a passkey in isconl). Returns true when
/// the operator proved presence.
typedef StepUp = Future<bool> Function(CommandDraft draft);

/// Step-up before a row write; [summary] is the plain sentence being approved.
typedef WriteStepUp = Future<bool> Function(String summary);
