package com.yasir.fork

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) - local_auth's biometric
// prompt is built on androidx.biometric, which requires a FragmentActivity.
class MainActivity : FlutterFragmentActivity()
