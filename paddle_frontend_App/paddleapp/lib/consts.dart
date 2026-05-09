// Inject at build time: --dart-define=GOOGLE_API_KEY=AIza...
// Falls back to the hardcoded key so plain `flutter run` works for the demo.
const String google_api_key = String.fromEnvironment(
  'GOOGLE_API_KEY',
  defaultValue: 'AIzaSyDyuDAmC-tBrFhG5Aadiyc_CxdJ5Y3H_K4',
);
