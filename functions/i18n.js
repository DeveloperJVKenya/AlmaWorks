/**
 * Server-side translations for the notifications the Cloud Functions write
 * or push. Mirrors the app (lib/core/l10n/l10n.dart):
 *   - a notification doc stores English in `title`/`body` and the other
 *     languages in `i18n.<code>.title/body` (see `bilingual`);
 *   - a push goes out in the recipient's language, read from their Users
 *     doc's `language` field (written by the app's LanguageSync).
 */

const LANGUAGES = ["en", "it"];
const DEFAULT_LANGUAGE = "en";

const plural = (n, one, other) => (n === 1 ? one : other);

const MESSAGES = {
  en: {
    newNotification: () => "🔔 New notification",
    // Safety Training
    attemptTitle: () => "🦺 New safety training attempt",
    attemptBody: ({ who, correct, practice, scenario }) =>
      `${who} answered ${correct ? "correctly" : "incorrectly"} on "${scenario}"${practice ? " (practice attempt)" : ""}. ` +
      "Tap to review their reasoning.",
    aWorker: () => "A worker",
    aReviewer: () => "A reviewer",
    aScenario: () => "a scenario",
    aSafetyScenario: () => "a safety scenario",
    yourTrainer: () => "Your trainer",
    reviewTitle: () => "🦺 Safety training review",
    reviewCleared: ({ date }) => `You've been cleared to work on site until ${date}.`,
    reviewRetraining: ({ count, date }) =>
      `You've been assigned ${count} ${plural(count, "scenario", "scenarios")} to retrain on${date ? ` by ${date}` : ""}.`,
    reviewEscalated: () => "Your safety training standing has been passed to a supervisor for follow-up.",
    escalationTitle: () => "⚠️ Safety escalation",
    escalationBody: ({ reviewer, worker }) =>
      `${reviewer} passed ${worker}'s safety training standing to you for follow-up.`,
    feedbackTitle: ({ scenario }) => `💬 Feedback on "${scenario}"`,
    weeklyTitle: () => "🦺 Weekly safety training",
    weeklyBody: () =>
      "Take a few minutes this week to run through your safety scenarios and check how ready you are to work safely on site.",
    weeklyRetrainingBody: ({ count, date }) =>
      `You still have ${count} assigned retraining ${plural(count, "scenario", "scenarios")} to complete${date ? ` by ${date}` : ""}.`,
    overdueTitle: () => "⏰ Retraining overdue",
    overdueWorkerBody: ({ count, date }) =>
      `Your ${count} retraining ${plural(count, "scenario was", "scenarios were")} due on ${date}. ` +
      `Please complete ${plural(count, "it", "them")} today.`,
    overdueReviewerBody: ({ worker, count, date }) =>
      `${worker} hasn't finished their ${count} retraining ${plural(count, "scenario", "scenarios")} (due ${date}).`,
    dueSoonTitle: () => "🦺 Retraining due soon",
    dueSoonBody: ({ count, date }) =>
      `You have ${count} retraining ${plural(count, "scenario", "scenarios")} to complete by ${date}.`,
    clearanceExpiredTitle: () => "🦺 Safety clearance expired",
    clearanceExpiredWorkerBody: () =>
      "Your safety clearance has expired. Keep practising your scenarios — a reviewer will check your standing again.",
    clearanceExpiredReviewerBody: ({ worker }) =>
      `${worker}'s safety clearance expired today and needs a new review.`,
    // Inventory
    returnReminderTitle: () => "⏰ Return reminder",
    returnReminderBody: ({ asset, who }) =>
      `"${asset}" is booked for ${who} starting tomorrow — please return it in time.`,
    overdueReturnTitle: () => "⚠️ Overdue return",
    overdueReturnBody: ({ asset, days }) =>
      `"${asset}" was due back ${days} ${plural(days, "day", "days")} ago — please return it as soon as possible, ` +
      "especially if someone else has it booked or it's due for maintenance.",
    // Communication
    someone: () => "Someone",
    noSubject: () => "(no subject)",
    messageFrom: ({ from }) => `New message from ${from}`,
    ccdYou: ({ from, subject }) => `${from} copied you on: ${subject}`,
    tapToView: () => "Tap to view the conversation.",
  },
  it: {
    newNotification: () => "🔔 Nuova notifica",
    attemptTitle: () => "🦺 Nuovo tentativo di formazione sulla sicurezza",
    attemptBody: ({ who, correct, practice, scenario }) =>
      `${who} ha risposto ${correct ? "correttamente" : "in modo errato"} a "${scenario}"${practice ? " (tentativo di esercizio)" : ""}. ` +
      "Tocca per vedere il ragionamento.",
    aWorker: () => "Un lavoratore",
    aReviewer: () => "Un valutatore",
    aScenario: () => "uno scenario",
    aSafetyScenario: () => "uno scenario di sicurezza",
    yourTrainer: () => "Il tuo formatore",
    reviewTitle: () => "🦺 Valutazione della formazione sulla sicurezza",
    reviewCleared: ({ date }) => `Sei stato dichiarato idoneo al lavoro in cantiere fino al ${date}.`,
    reviewRetraining: ({ count, date }) =>
      `Ti ${plural(count, "è stato assegnato 1 scenario", `sono stati assegnati ${count} scenari`)} da ripetere${date ? ` entro il ${date}` : ""}.`,
    reviewEscalated: () => "La tua posizione sulla formazione è stata affidata a un supervisore per il seguito.",
    escalationTitle: () => "⚠️ Segnalazione sicurezza",
    escalationBody: ({ reviewer, worker }) =>
      `${reviewer} ti ha affidato la posizione sulla formazione di ${worker} per il seguito.`,
    feedbackTitle: ({ scenario }) => `💬 Feedback su "${scenario}"`,
    weeklyTitle: () => "🦺 Formazione settimanale sulla sicurezza",
    weeklyBody: () =>
      "Dedica qualche minuto questa settimana agli scenari di sicurezza per verificare quanto sei pronto a lavorare in sicurezza in cantiere.",
    weeklyRetrainingBody: ({ count, date }) =>
      `Devi ancora completare ${plural(count, "1 scenario assegnato", `${count} scenari assegnati`)} da ripetere${date ? ` entro il ${date}` : ""}.`,
    overdueTitle: () => "⏰ Riaddestramento in ritardo",
    overdueWorkerBody: ({ count, date }) =>
      `${plural(count, "Il tuo scenario da ripetere era", `I tuoi ${count} scenari da ripetere erano`)} in scadenza il ${date}. ` +
      `${plural(count, "Completalo", "Completali")} oggi.`,
    overdueReviewerBody: ({ worker, count, date }) =>
      `${worker} non ha completato ${plural(count, "1 scenario", `${count} scenari`)} da ripetere (scadenza ${date}).`,
    dueSoonTitle: () => "🦺 Riaddestramento in scadenza",
    dueSoonBody: ({ count, date }) =>
      `Devi completare ${plural(count, "1 scenario", `${count} scenari`)} da ripetere entro il ${date}.`,
    clearanceExpiredTitle: () => "🦺 Idoneità scaduta",
    clearanceExpiredWorkerBody: () =>
      "La tua idoneità di sicurezza è scaduta. Continua a esercitarti con gli scenari: un valutatore riesaminerà la tua posizione.",
    clearanceExpiredReviewerBody: ({ worker }) =>
      `L'idoneità di sicurezza di ${worker} è scaduta oggi e serve una nuova valutazione.`,
    returnReminderTitle: () => "⏰ Promemoria di restituzione",
    returnReminderBody: ({ asset, who }) =>
      `"${asset}" è prenotato per ${who} da domani: restituiscilo in tempo.`,
    overdueReturnTitle: () => "⚠️ Restituzione in ritardo",
    overdueReturnBody: ({ asset, days }) =>
      `"${asset}" doveva essere restituito ${plural(days, "1 giorno", `${days} giorni`)} fa: restituiscilo il prima possibile, ` +
      "soprattutto se qualcun altro lo ha prenotato o se è prevista una manutenzione.",
    someone: () => "Qualcuno",
    noSubject: () => "(nessun oggetto)",
    messageFrom: ({ from }) => `Nuovo messaggio da ${from}`,
    ccdYou: ({ from, subject }) => `${from} ti ha messo in copia su: ${subject}`,
    tapToView: () => "Tocca per vedere la conversazione.",
  },
};

function normalizeLanguage(lang) {
  return LANGUAGES.includes(lang) ? lang : DEFAULT_LANGUAGE;
}

/** One message in one language. */
function t(lang, key, params = {}) {
  const table = MESSAGES[normalizeLanguage(lang)];
  return (table[key] || MESSAGES[DEFAULT_LANGUAGE][key])(params);
}

/** A date as shown to people, e.g. "12 Oct 2026" / "12 ott 2026". */
function formatDate(date, lang) {
  return date.toLocaleDateString(normalizeLanguage(lang) === "it" ? "it-IT" : "en-GB", {
    timeZone: "Africa/Nairobi",
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

/**
 * Notification text in every language, in the shape the app reads:
 * `{title, body, i18n: {it: {title, body}}}`. [build] receives a language
 * code and returns `{title, body}`.
 */
function bilingual(build) {
  const en = build(DEFAULT_LANGUAGE);
  const i18n = {};
  for (const lang of LANGUAGES) {
    if (lang !== DEFAULT_LANGUAGE) i18n[lang] = build(lang);
  }
  return { title: en.title, body: en.body, i18n };
}

/** A queued notification doc's title/body in [lang] (falls back to English). */
function localizedText(data, lang) {
  const code = normalizeLanguage(lang);
  const variant = code !== DEFAULT_LANGUAGE && data.i18n && data.i18n[code];
  return {
    title: (variant && variant.title) || data.title || t(code, "newNotification"),
    body: (variant && variant.body) || data.body || "",
  };
}

module.exports = { LANGUAGES, normalizeLanguage, t, formatDate, bilingual, localizedText };
