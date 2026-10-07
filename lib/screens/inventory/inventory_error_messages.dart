import 'package:almaworks/core/errors/friendly_error.dart';

/// A short, clear sentence for any Inventory error, safe to show a
/// non-technical user.
///
/// InventoryService throws [UserFacingException]s with messages already
/// written (and translated) for people — booking conflicts with their
/// dates, "only N left in storage", and so on — and those are shown as-is.
/// Anything else (permissions, connection problems, unexpected failures)
/// becomes a plain-language explanation via [friendlyError]. The raw error
/// is never shown in the UI; call sites still log it for diagnosis.
String friendlyInventoryError(Object error) => friendlyError(error);
