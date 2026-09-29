/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
 */

#import "CDVOrientation.h"
#import <Cordova/CDVViewController.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kCDVOrientationNotSupportedError = @"NotSupportedError";
static NSString *const kCDVOrientationInvalidStateError = @"InvalidStateError";
static NSString *const kCDVOrientationAbortError = @"AbortError";

// UIWindowScene geometry requests only report failures, so a request is treated
// as successful if no error has been reported within this grace period.
static const int64_t kCDVOrientationGeometryUpdateGracePeriod = 100 * NSEC_PER_MSEC;

static char kCDVOrientationDelegateKey;

/*
 * Weak reference box stored on the Cordova view controller, so the view
 * controller never retains the plugin (the plugin is owned by the view controller).
 */
@interface CDVOrientationDelegateReference : NSObject
@property (nonatomic, weak) CDVOrientation *delegate;
@end

@implementation CDVOrientationDelegateReference
@end

/*
 * cordova-ios 8 removed CDVViewController's supportedOrientations handling and
 * no longer implements -supportedInterfaceOrientations. This implementation is
 * added to CDVViewController (only if it does not implement the method itself)
 * and forwards the question to the plugin, which acts as the view controller's
 * CDVScreenOrientationDelegate. Without a plugin-requested orientation it
 * falls back to UIKit's default behaviour.
 */
static UIInterfaceOrientationMask CDVOrientationViewControllerSupportedInterfaceOrientations(id self, SEL _cmd)
{
    CDVOrientationDelegateReference *reference = objc_getAssociatedObject(self, &kCDVOrientationDelegateKey);
    UIInterfaceOrientationMask mask = [reference.delegate supportedInterfaceOrientations];
    if (mask != 0) {
        return mask;
    }

    // This IMP is installed on CDVViewController itself, so "super" is
    // CDVViewController's superclass regardless of the receiver's subclass.
    struct objc_super superInfo = {
        .receiver = self,
        .super_class = class_getSuperclass([CDVViewController class])
    };
    return ((UIInterfaceOrientationMask (*)(struct objc_super *, SEL))objc_msgSendSuper)(&superInfo, _cmd);
}

@implementation CDVOrientation

#pragma mark - Plugin lifecycle / CDVScreenOrientationDelegate

- (void)pluginInitialize
{
    _isLocked = NO;
    _lastOrientation = UIInterfaceOrientationUnknown;
    _supportedOrientationMask = 0;
    _requestGeneration = 0;

    if (![self usesLegacyOrientationSupport]) {
        [self attachToViewController];
    }
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return _supportedOrientationMask;
}

- (BOOL)shouldAutorotate
{
    return YES;
}

#pragma mark - Command

- (void)screenOrientation:(CDVInvokedUrlCommand *)command
{
    NSString *orientation = [command argumentAtIndex:0 withDefault:nil andClass:[NSString class]];
    UIInterfaceOrientationMask orientationMask = [self orientationMaskForValue:orientation];
    NSString *callbackId = command.callbackId;

    if (orientationMask == 0) {
        [self sendErrorNamed:kCDVOrientationNotSupportedError
                     message:[NSString stringWithFormat:@"Unsupported orientation value: %@", orientation]
                  callbackId:callbackId];
        return;
    }

    if ([NSThread isMainThread]) {
        [self applyOrientationMask:orientationMask callbackId:callbackId];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyOrientationMask:orientationMask callbackId:callbackId];
        });
    }
}

#pragma mark - Orientation handling

- (void)applyOrientationMask:(UIInterfaceOrientationMask)orientationMask callbackId:(NSString *)callbackId
{
    UIViewController *viewController = self.viewController;
    if (viewController == nil) {
        [self sendErrorNamed:kCDVOrientationInvalidStateError
                     message:@"The Cordova view controller is not available"
                  callbackId:callbackId];
        return;
    }

    BOOL usesLegacySupport = [self usesLegacyOrientationSupport];
    if (!usesLegacySupport && ![self attachToViewController]) {
        [self sendErrorNamed:kCDVOrientationInvalidStateError
                     message:@"Unable to integrate with the Cordova view controller orientation handling"
                  callbackId:callbackId];
        return;
    }

    BOOL isUnlock = (orientationMask == UIInterfaceOrientationMaskAll);
    UIWindow *window = viewController.view.window;

    // Never set a mask that has no orientation in common with the app's
    // supported orientations (Info.plist), since UIKit raises an exception for it.
    if (!isUnlock && window != nil) {
        UIInterfaceOrientationMask appMask = [[UIApplication sharedApplication] supportedInterfaceOrientationsForWindow:window];
        if ((appMask & orientationMask) == 0) {
            [self sendErrorNamed:kCDVOrientationNotSupportedError
                         message:@"The requested orientation is not supported by the application"
                      callbackId:callbackId];
            return;
        }
    }

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
    if (@available(iOS 16.0, *)) {
        // Only the scene hosting the plugin's own view controller is used.
        if (!isUnlock && window.windowScene == nil) {
            [self sendErrorNamed:kCDVOrientationInvalidStateError
                         message:@"The Cordova view controller is not attached to a UIWindowScene"
                      callbackId:callbackId];
            return;
        }
    }
#endif

    UIInterfaceOrientation currentOrientation = [self currentInterfaceOrientation];
    UIInterfaceOrientationMask previousMask = _supportedOrientationMask;
    BOOL previousIsLocked = _isLocked;
    UIInterfaceOrientation previousLastOrientation = _lastOrientation;

    if (!isUnlock && !_isLocked) {
        _lastOrientation = currentOrientation;
    }
    _supportedOrientationMask = orientationMask;
    _isLocked = !isUnlock;
    NSUInteger generation = ++_requestGeneration;

    if (usesLegacySupport) {
        [self updateLegacySupportedOrientations];
    }

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
    if (@available(iOS 16.0, *)) {
        [self applyOrientationMaskWithSceneGeometry:orientationMask
                                        windowScene:(isUnlock ? nil : window.windowScene)
                                       previousMask:previousMask
                                   previousIsLocked:previousIsLocked
                            previousLastOrientation:previousLastOrientation
                                         generation:generation
                                         callbackId:callbackId];
        return;
    }
#endif

    [self applyLegacyDeviceOrientationForMask:orientationMask currentOrientation:currentOrientation];
    [self sendSuccess:callbackId];
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
- (void)applyOrientationMaskWithSceneGeometry:(UIInterfaceOrientationMask)orientationMask
                                  windowScene:(UIWindowScene *)windowScene
                                 previousMask:(UIInterfaceOrientationMask)previousMask
                             previousIsLocked:(BOOL)previousIsLocked
                      previousLastOrientation:(UIInterfaceOrientation)previousLastOrientation
                                   generation:(NSUInteger)generation
                                   callbackId:(NSString *)callbackId API_AVAILABLE(ios(16.0))
{
    if (windowScene == nil) {
        // Unlocking only widens the supported orientations; nothing to force.
        [self.viewController setNeedsUpdateOfSupportedInterfaceOrientations];
        [self sendSuccess:callbackId];
        return;
    }

    __block BOOL finished = NO;
    __weak CDVOrientation *weakSelf = self;
    void (^finish)(NSError *) = ^(NSError *error) {
        // Always executed on the main queue.
        CDVOrientation *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (error != nil && strongSelf->_requestGeneration == generation) {
            // Roll back so the plugin state reflects what is actually applied,
            // unless a newer request has replaced this one.
            strongSelf->_supportedOrientationMask = previousMask;
            strongSelf->_isLocked = previousIsLocked;
            strongSelf->_lastOrientation = previousLastOrientation;
            if ([strongSelf usesLegacyOrientationSupport]) {
                [strongSelf updateLegacySupportedOrientations];
            }
            [strongSelf.viewController setNeedsUpdateOfSupportedInterfaceOrientations];
        }

        if (finished) {
            if (error != nil) {
                NSLog(@"[CDVOrientation] Orientation geometry update failed after the request was resolved: %@", error);
            }
            return;
        }
        finished = YES;

        if (error == nil) {
            [strongSelf sendSuccess:callbackId];
            return;
        }

        [strongSelf sendErrorNamed:kCDVOrientationAbortError
                           message:[NSString stringWithFormat:@"Failed to update interface orientation: %@", error.localizedDescription]
                        callbackId:callbackId];
    };

    UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:orientationMask];
    [windowScene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError * _Nonnull error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            finish(error);
        });
    }];

    // Update the supported orientations after requesting the geometry change to
    // avoid the "double" rotation issue reported in
    // https://github.com/apache/cordova-plugin-screen-orientation/pull/107
    [self.viewController setNeedsUpdateOfSupportedInterfaceOrientations];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kCDVOrientationGeometryUpdateGracePeriod), dispatch_get_main_queue(), ^{
        finish(nil);
    });
}
#endif

/*
 * Legacy path for iOS versions older than 16, which have no public API to
 * request an interface orientation change.
 */
- (void)applyLegacyDeviceOrientationForMask:(UIInterfaceOrientationMask)orientationMask currentOrientation:(UIInterfaceOrientation)currentOrientation
{
    UIInterfaceOrientation targetOrientation = UIInterfaceOrientationUnknown;

    if (orientationMask == UIInterfaceOrientationMaskAll) {
        targetOrientation = _lastOrientation;
    } else if (orientationMask == UIInterfaceOrientationMaskLandscapeLeft ||
               (orientationMask == UIInterfaceOrientationMaskLandscape && !UIInterfaceOrientationIsLandscape(currentOrientation))) {
        targetOrientation = UIInterfaceOrientationLandscapeLeft;
    } else if (orientationMask == UIInterfaceOrientationMaskLandscapeRight) {
        targetOrientation = UIInterfaceOrientationLandscapeRight;
    } else if (orientationMask == UIInterfaceOrientationMaskPortrait ||
               (orientationMask == (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown) && !UIInterfaceOrientationIsPortrait(currentOrientation))) {
        targetOrientation = UIInterfaceOrientationPortrait;
    } else if (orientationMask == UIInterfaceOrientationMaskPortraitUpsideDown) {
        targetOrientation = UIInterfaceOrientationPortraitUpsideDown;
    }

    if (targetOrientation != UIInterfaceOrientationUnknown) {
        [[UIDevice currentDevice] setValue:@(targetOrientation) forKey:@"orientation"];
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [UIViewController attemptRotationToDeviceOrientation];
#pragma clang diagnostic pop
}

- (UIInterfaceOrientation)currentInterfaceOrientation
{
    if (@available(iOS 13.0, *)) {
        UIWindowScene *windowScene = self.viewController.view.window.windowScene;
        if (windowScene != nil) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
            if (@available(iOS 16.0, *)) {
                return windowScene.effectiveGeometry.interfaceOrientation;
            }
#endif
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            return windowScene.interfaceOrientation;
#pragma clang diagnostic pop
        }
    }

    // Legacy fallback for iOS < 13 or when no scene is attached yet.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
}

#pragma mark - Cordova view controller integration

/*
 * cordova-ios 7 and earlier expose -setSupportedOrientations: on
 * CDVViewController and derive -supportedInterfaceOrientations from it.
 */
- (BOOL)usesLegacyOrientationSupport
{
    return [self.viewController respondsToSelector:NSSelectorFromString(@"setSupportedOrientations:")];
}

- (void)updateLegacySupportedOrientations
{
    UIViewController *viewController = self.viewController;
    SEL selector = NSSelectorFromString(@"setSupportedOrientations:");
    if (![viewController respondsToSelector:selector]) {
        return;
    }

    NSMutableArray *supportedOrientations = [[NSMutableArray alloc] init];
    if (_supportedOrientationMask & UIInterfaceOrientationMaskPortrait) {
        [supportedOrientations addObject:@(UIInterfaceOrientationPortrait)];
    }
    if (_supportedOrientationMask & UIInterfaceOrientationMaskPortraitUpsideDown) {
        [supportedOrientations addObject:@(UIInterfaceOrientationPortraitUpsideDown)];
    }
    if (_supportedOrientationMask & UIInterfaceOrientationMaskLandscapeRight) {
        [supportedOrientations addObject:@(UIInterfaceOrientationLandscapeRight)];
    }
    if (_supportedOrientationMask & UIInterfaceOrientationMaskLandscapeLeft) {
        [supportedOrientations addObject:@(UIInterfaceOrientationLandscapeLeft)];
    }

    ((void (*)(id, SEL, NSArray *))objc_msgSend)(viewController, selector, supportedOrientations);
}

+ (BOOL)installViewControllerOrientationHook
{
    static BOOL installed = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class viewControllerClass = [CDVViewController class];
        SEL selector = @selector(supportedInterfaceOrientations);
        IMP implementation = (IMP)CDVOrientationViewControllerSupportedInterfaceOrientations;
        Method baseMethod = class_getInstanceMethod([UIViewController class], selector);

        // class_addMethod does not replace an implementation that
        // CDVViewController already provides itself.
        installed = class_addMethod(viewControllerClass, selector, implementation, method_getTypeEncoding(baseMethod)) ||
            method_getImplementation(class_getInstanceMethod(viewControllerClass, selector)) == implementation;
    });
    return installed;
}

- (BOOL)attachToViewController
{
    UIViewController *viewController = self.viewController;
    if (![viewController isKindOfClass:[CDVViewController class]] || ![[self class] installViewControllerOrientationHook]) {
        return NO;
    }

    CDVOrientationDelegateReference *reference = objc_getAssociatedObject(viewController, &kCDVOrientationDelegateKey);
    if (reference == nil) {
        reference = [[CDVOrientationDelegateReference alloc] init];
        objc_setAssociatedObject(viewController, &kCDVOrientationDelegateKey, reference, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    reference.delegate = self;
    return YES;
}

#pragma mark - Helpers

- (UIInterfaceOrientationMask)orientationMaskForValue:(NSString *)orientationValue
{
    if ([orientationValue isEqualToString:@"portrait-primary"]) {
        return UIInterfaceOrientationMaskPortrait;
    }
    if ([orientationValue isEqualToString:@"portrait-secondary"]) {
        return UIInterfaceOrientationMaskPortraitUpsideDown;
    }
    if ([orientationValue isEqualToString:@"landscape-primary"]) {
        return UIInterfaceOrientationMaskLandscapeRight;
    }
    if ([orientationValue isEqualToString:@"landscape-secondary"]) {
        return UIInterfaceOrientationMaskLandscapeLeft;
    }
    if ([orientationValue isEqualToString:@"portrait"]) {
        return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
    }
    if ([orientationValue isEqualToString:@"landscape"]) {
        return UIInterfaceOrientationMaskLandscape;
    }
    if ([orientationValue isEqualToString:@"any"]) {
        return UIInterfaceOrientationMaskAll;
    }
    return 0;
}

- (void)sendSuccess:(NSString *)callbackId
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)sendErrorNamed:(NSString *)name message:(NSString *)message callbackId:(NSString *)callbackId
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                  messageAsDictionary:@{ @"name": name, @"message": message }];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

@end
