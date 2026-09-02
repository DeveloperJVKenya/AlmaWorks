/// Translates a raw exception (Firestore permission-denied codes, our own
/// InventoryService `Exception('...')` messages, network failures, etc.)
/// into a short, clear sentence safe to show a non-technical user.
///
/// The raw error is never shown in the UI — every call site still logs it
/// via its own `logger.e(..., error: e)` call for developer diagnosis;
/// this is purely what the user sees on screen.
String friendlyInventoryError(Object error) {
  final raw = error.toString().toLowerCase();

  if (raw.contains('permission-denied') || raw.contains('permission_denied') || raw.contains('permission denied')) {
    return "You don't have permission to do that. If this seems wrong, ask an Admin to check your account access.";
  }
  if (raw.contains('already has a pending request')) {
    return 'This item already has a pending request — someone else is waiting on a decision first.';
  }
  if (raw.contains('overlaps an existing booking') || raw.contains('overlaps a scheduled maintenance period')) {
    // These already carry the specific conflicting dates/holder — that
    // detail is exactly what the user needs to pick a different window, so
    // surface it as-is rather than falling back to a generic message.
    final message = error.toString();
    final withoutPrefix = message.startsWith('Exception: ') ? message.substring('Exception: '.length) : message;
    return withoutPrefix;
  }
  if (raw.contains('not available for an immediate checkout') || raw.contains('is not available')) {
    return "This item isn't available right now — someone may have just checked it out or booked it.";
  }
  if (raw.contains('cannot check') && raw.contains('themself') || raw.contains('cannot book an asset out to themself')) {
    return 'You can\'t check this out to yourself — use "Request for Myself", or ask another Admin/MainAdmin to process it.';
  }
  if (raw.contains('already been responded to')) {
    return 'This request was already handled by someone else.';
  }
  if (raw.contains('no longer exists')) {
    return 'This item no longer exists — it may have been removed or changed.';
  }
  if (raw.contains('only the person this item is booked for')) {
    return "Only the person this item was booked for can acknowledge its receipt.";
  }
  if (raw.contains('not a driver delivery')) {
    return 'This item isn\'t out for driver delivery — nothing to acknowledge.';
  }
  if (raw.contains('select who this booking is for') || raw.contains('reason is required')) {
    return raw.contains('reason') ? 'Please enter a reason before continuing.' : 'Please choose who this is for before continuing.';
  }
  if (raw.contains('socketexception') || raw.contains('network') || raw.contains('unavailable') || raw.contains('timeout')) {
    return 'Network issue — please check your connection and try again.';
  }

  return 'Something went wrong. Please try again — if it keeps happening, contact your Admin.';
}
