import '../../../core/contracts/models.dart';

/// La tarjeta "¿Qué tal hoy?" aparece 25 minutos después de validar el almuerzo.
const feedbackDelay = Duration(minutes: 25);

/// Si el comensal no abre la app, la tarjeta caduca a las 24 horas.
const feedbackExpiry = Duration(hours: 24);

/// Reglas de `domain/feedback.ts` del prototipo. Una tarjeta por almuerzo: el
/// repositorio deja de devolverla cuando ya se respondió o descartó.
bool shouldShowFeedback(PendingFeedback? feedback, DateTime now) {
  if (feedback == null) return false;
  final elapsed = now.difference(feedback.validatedAt);
  return elapsed >= feedbackDelay && elapsed <= feedbackExpiry;
}
