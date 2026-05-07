// Inject at build time: --dart-define=GOOGLE_API_KEY=AIza...
// Restrict this key in Google Cloud Console to your app's package name / bundle ID.
// Build will fail with an empty string if the key is not provided, which is intentional —
// it prevents accidentally shipping a keyless build that silently breaks Maps.
const String google_api_key = String.fromEnvironment('GOOGLE_API_KEY');
