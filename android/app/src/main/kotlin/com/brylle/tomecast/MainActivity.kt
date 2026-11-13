package com.brylle.tomecast

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (instead of FlutterActivity) lets the background
// audio service and the app UI share the same Flutter engine.
class MainActivity : AudioServiceActivity()
