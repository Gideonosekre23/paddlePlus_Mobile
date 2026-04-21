// Override at build time with --dart-define=GOOGLE_API_KEY=AIza...
// Restrict this key in Google Cloud Console to your app's package name / bundle ID.
const String google_api_key = String.fromEnvironment(
  'GOOGLE_API_KEY',
  defaultValue: 'AIzaSyDyuDAmC-tBrFhG5Aadiyc_CxdJ5Y3H_K4',
);
