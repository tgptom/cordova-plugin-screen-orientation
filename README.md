---
title: Screen Orientation
description: Set the screen orientation
---
<!--
# license: Licensed to the Apache Software Foundation (ASF) under one
#         or more contributor license agreements.  See the NOTICE file
#         distributed with this work for additional information
#         regarding copyright ownership.  The ASF licenses this file
#         to you under the Apache License, Version 2.0 (the
#         "License"); you may not use this file except in compliance
#         with the License.  You may obtain a copy of the License at
#
#           http://www.apache.org/licenses/LICENSE-2.0
#
#         Unless required by applicable law or agreed to in writing,
#         software distributed under the License is distributed on an
#         "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#         KIND, either express or implied.  See the License for the
#         specific language governing permissions and limitations
#         under the License.
-->

# Cordova Screen Orientation Plugin

[![Android Build](https://github.com/apache/cordova-plugin-screen-orientation/actions/workflows/android.yml/badge.svg)](https://github.com/apache/cordova-plugin-screen-orientation/actions/workflows/android.yml) [![Chrome Testsuite](https://github.com/apache/cordova-plugin-screen-orientation/actions/workflows/chrome.yml/badge.svg)](https://github.com/apache/cordova-plugin-screen-orientation/actions/workflows/chrome.yml) [![iOS Build](https://github.com/apache/cordova-plugin-screen-orientation/actions/workflows/ios.yml/badge.svg)](https://github.com/apache/cordova-plugin-screen-orientation/actions/workflows/ios.yml) [![Lint Test](https://github.com/apache/cordova-plugin-screen-orientation/actions/workflows/lint.yml/badge.svg)](https://github.com/apache/cordova-plugin-screen-orientation/actions/workflows/lint.yml)

Cordova plugin to set/lock the screen orientation in a common way for iOS, Android, and windows-uwp.  This plugin is based on [Screen Orientation API](http://www.w3.org/TR/screen-orientation/) so the api matches the current spec.

The plugin adds the following to the screen object (`window.screen`):

```js
// lock the device orientation
.orientation.lock('portrait')

// unlock the orientation
.orientation.unlock()

// current orientation
.orientation
```

## Install


```bash
cordova plugin add cordova-plugin-screen-orientation
```

## Platform Compatibility

| Cordova platform | Build / API compatibility | CI coverage | Runtime notes |
| --- | --- | --- | --- |
| `cordova-android@14.x` | Supported (target/compile SDK 35) | Install + clean debug build | Orientation locks are honoured by Android 15 (API 35) apps. |
| `cordova-android@15.x` | Supported (target/compile SDK 36) | Install + clean debug build | See [Android API 36 large-screen behavior](#android-api-36-large-screen-behavior): locks can be ignored on large screens. |
| `cordova-ios@7.x` | Supported | Install + clean simulator debug build | Uses Cordova's legacy `supportedOrientations` view controller integration. |
| `cordova-ios@8.x` | Supported | Install + clean simulator debug build | Uses the plugin-owned orientation mask (see [iOS Notes](#ios-notes)). |

The CI builds use a pinned Cordova CLI (`cordova@13.0.0`). Cordova platform versions are listed above; they are distinct from Android API levels and iOS OS versions.

"Build / API compatibility" means the plugin installs and compiles against that Cordova platform and uses only public, supported APIs. It does not guarantee that the operating system honours every orientation request on every device (see the platform notes below).

The plugin does not set any Gradle, Android Gradle Plugin, Kotlin, AndroidX, compile SDK or target SDK versions; those are controlled by the Cordova platform and your app.

## Supported Orientations

#### portrait-primary
> The orientation is in the primary portrait mode.

#### portrait-secondary
> The orientation is in the secondary portrait mode.

#### landscape-primary
> The orientation is in the primary landscape mode.

#### landscape-secondary
> The orientation is in the secondary landscape mode.

#### portrait
> The orientation is either portrait-primary or portrait-secondary (sensor).

#### landscape
> The orientation is either landscape-primary or landscape-secondary (sensor).

#### any
>  orientation is  unlocked - all orientations are supported.

## Usage

```js
// set to either landscape
screen.orientation.lock('landscape').then(function () {
    console.log('Orientation locked');
}, function (error) {
    console.error(error.name + ': ' + error.message);
});

// allow user rotate
screen.orientation.unlock();

// access current orientation
console.log('Orientation is ' + screen.orientation.type);
```

`screen.orientation.lock(orientation)` returns a Promise that settles only when the native platform responds:

- it resolves once the native side has applied the request;
- it rejects with a `NotSupportedError` for unsupported orientation values (anything not listed in [Supported Orientations](#supported-orientations)), or (on iOS) for orientations the app does not declare as supported;
- it rejects with the native error (for example `InvalidStateError` or `AbortError` on iOS) if the platform could not apply the request.

`screen.orientation.unlock()` can still be called without handling its return value, but it now also returns a Promise that resolves or rejects based on the native result.

## Events

Both android and iOS will fire the orientationchange event on the window object.
For this version of the plugin use the window object if you require notification.


### Example usage

```js
window.addEventListener("orientationchange", function(){
    console.log(screen.orientation.type); // e.g. portrait
});
```

The 'change' event listener has also been added to the screen.orientation object.

### Example usage

```js
screen.orientation.addEventListener('change', function(){
    console.log(screen.orientation.type); // e.g. portrait
});
    // OR

screen.orientation.onchange = function(){console.log(screen.orientation.type);
};

```
## Android Notes

The __screen.orientation__ property will not update when the phone is [rotated 180 degrees](http://www.quirksmode.org/dom/events/orientationchange.html).

Orientation changes are applied on the Android UI thread using `Activity.setRequestedOrientation()`.

### Android API 36 large-screen behavior

Apps built with `cordova-android@15.x` target Android 16 (API 36). On API 36, Android ignores app orientation restrictions (including `setRequestedOrientation()`) on large-screen devices such as tablets, foldables (unfolded) and desktop windowing, where the smallest screen width is at least 600dp. See [Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-16#ignore-orientation).

This is an operating-system behavior restriction, not a build incompatibility: the plugin still builds and the `lock()` Promise resolves because Android accepted the request, but the screen may not rotate or stay locked on those devices. Phones are not affected. Design your layouts to adapt to any orientation on large screens.

## iOS Notes

- With `cordova-ios@8.x`, `CDVViewController` no longer manages supported orientations (its `supportedOrientations` API was removed and `CDVScreenOrientationDelegate` is no longer consumed by Cordova). The plugin keeps its own `UIInterfaceOrientationMask`, acts as the view controller's `CDVScreenOrientationDelegate`, and provides `supportedInterfaceOrientations` for `CDVViewController` from that mask. Before the first `lock()`, UIKit's default behavior is kept. If your app subclasses the Cordova view controller and overrides `supportedInterfaceOrientations`, your override takes precedence.
- With `cordova-ios@7.x`, the plugin uses the platform's legacy `supportedOrientations` integration.
- On iOS 16 and newer, orientation changes are requested with `UIWindowScene.requestGeometryUpdate(_:)` on the window scene that hosts the Cordova view controller, and `setNeedsUpdateOfSupportedInterfaceOrientations` is called after the mask changes. iOS only reports failures for geometry requests (there is no success callback), so `lock()` resolves if no failure is reported within a short grace period (100 ms) and rejects with `AbortError` when a failure is reported. A failure reported later is logged and the plugin's orientation mask is rolled back.
- Locked orientations are always limited by the orientations your app declares (for example, via the `Orientation` preference / `UISupportedInterfaceOrientations`). Requesting an orientation the app does not support rejects with `NotSupportedError`. iPhones without a Home button do not support `portrait-secondary`.

## Windows UWP Notes

Windows store apps (windows-uwp) will only display orientation changes if the device has some sort of accelerometer.  The internal state of the "orientation" will still be kept, but the actual screen won't rotate unless the device supports it.
