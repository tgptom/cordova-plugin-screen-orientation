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

static NSString *const kUnknownOrientationValueError = @"Unknown orientation value";
static NSString *const kMissingWindowSceneError = @"Unable to determine active UIWindowScene";

@interface CDVOrientation () {}
@end

@implementation CDVOrientation

- (void)pluginInitialize
{
    _supportedOrientationMask = UIInterfaceOrientationMaskAll;
    _lastOrientation = UIInterfaceOrientationUnknown;
    [self registerScreenOrientationDelegate];
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return _supportedOrientationMask;
}

- (void)screenOrientation:(CDVInvokedUrlCommand *)command
{
    NSString *orientation = [command argumentAtIndex:0 withDefault:nil andClass:[NSString class]];
    UIInterfaceOrientationMask orientationMask = [self orientationMaskForValue:orientation];

    if (orientationMask == 0) {
        [self sendPluginError:kUnknownOrientationValueError callbackId:command.callbackId];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyOrientationMask:orientationMask callbackId:command.callbackId];
    });
}

- (void)applyOrientationMask:(UIInterfaceOrientationMask)orientationMask callbackId:(NSString *)callbackId
{
    _supportedOrientationMask = orientationMask;
    [self registerScreenOrientationDelegate];
    [self updateLegacySupportedOrientations];

    if (@available(iOS 16.0, *)) {
        [self applyOrientationMaskOnIOS16:orientationMask callbackId:callbackId];
        return;
    }

    [self applyOrientationMaskOnIOS15AndBelow:orientationMask];
    [self sendPluginSuccess:callbackId];
}

- (void)applyOrientationMaskOnIOS15AndBelow:(UIInterfaceOrientationMask)orientationMask
{
    UIInterfaceOrientation currentOrientation = [self currentInterfaceOrientation];

    if (orientationMask != UIInterfaceOrientationMaskAll && !_isLocked) {
        _lastOrientation = currentOrientation;
    }

    UIInterfaceOrientation targetOrientation = [self targetInterfaceOrientationForMask:orientationMask currentOrientation:currentOrientation];
    if (targetOrientation != UIInterfaceOrientationUnknown) {
        [[UIDevice currentDevice] setValue:@(targetOrientation) forKey:@"orientation"];
        [UINavigationController attemptRotationToDeviceOrientation];
    }

    _isLocked = (orientationMask != UIInterfaceOrientationMaskAll);
}

- (void)applyOrientationMaskOnIOS16:(UIInterfaceOrientationMask)orientationMask callbackId:(NSString *)callbackId API_AVAILABLE(ios(16.0))
{
    UIInterfaceOrientation currentOrientation = [self currentInterfaceOrientation];
    if (orientationMask != UIInterfaceOrientationMaskAll && !_isLocked) {
        _lastOrientation = currentOrientation;
    }

    UIWindow *window = self.viewController.view.window;
    UIWindowScene *windowScene = window.windowScene;
    if (windowScene == nil) {
        [self sendPluginError:kMissingWindowSceneError callbackId:callbackId];
        return;
    }

    __block BOOL hasCallback = NO;
    void (^sendOnce)(CDVCommandStatus, NSString *) = ^(CDVCommandStatus status, NSString *message) {
        if (hasCallback) {
            return;
        }
        hasCallback = YES;

        if (status == CDVCommandStatus_OK) {
            [self sendPluginSuccess:callbackId];
        } else {
            [self sendPluginError:message callbackId:callbackId];
        }
    };

    UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:orientationMask];
    [windowScene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError * _Nonnull error) {
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to update interface orientation: %@", error.localizedDescription];
        sendOnce(CDVCommandStatus_ERROR, errorMessage);
    }];

    [self.viewController setNeedsUpdateOfSupportedInterfaceOrientations];
    _isLocked = (orientationMask != UIInterfaceOrientationMaskAll);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sendOnce(CDVCommandStatus_OK, nil);
    });
}

- (void)updateLegacySupportedOrientations
{
    CDVViewController *viewController = (CDVViewController *)self.viewController;
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

    ((void (*)(CDVViewController*, SEL, NSMutableArray*))objc_msgSend)(viewController, selector, supportedOrientations);
}

- (void)registerScreenOrientationDelegate
{
    SEL selector = NSSelectorFromString(@"setScreenOrientationDelegate:");
    if ([self.viewController respondsToSelector:selector]) {
        ((void (*)(id, SEL, id<CDVScreenOrientationDelegate>))objc_msgSend)(self.viewController, selector, self);
    }
}

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

- (UIInterfaceOrientation)targetInterfaceOrientationForMask:(UIInterfaceOrientationMask)orientationMask currentOrientation:(UIInterfaceOrientation)currentOrientation
{
    if (orientationMask == UIInterfaceOrientationMaskLandscapeLeft) {
        return UIInterfaceOrientationLandscapeLeft;
    }
    if (orientationMask == UIInterfaceOrientationMaskLandscapeRight) {
        return UIInterfaceOrientationLandscapeRight;
    }
    if (orientationMask == UIInterfaceOrientationMaskPortrait) {
        return UIInterfaceOrientationPortrait;
    }
    if (orientationMask == UIInterfaceOrientationMaskPortraitUpsideDown) {
        return UIInterfaceOrientationPortraitUpsideDown;
    }
    if (orientationMask == UIInterfaceOrientationMaskLandscape) {
        if (UIInterfaceOrientationIsLandscape(currentOrientation)) {
            return currentOrientation;
        }
        return UIInterfaceOrientationLandscapeLeft;
    }
    if (orientationMask == (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown)) {
        if (UIInterfaceOrientationIsPortrait(currentOrientation)) {
            return currentOrientation;
        }
        return UIInterfaceOrientationPortrait;
    }
    if (orientationMask == UIInterfaceOrientationMaskAll && _lastOrientation != UIInterfaceOrientationUnknown) {
        return _lastOrientation;
    }

    return UIInterfaceOrientationUnknown;
}

- (UIInterfaceOrientation)currentInterfaceOrientation
{
    if (@available(iOS 13.0, *)) {
        UIWindowScene *windowScene = self.viewController.view.window.windowScene;
        if (windowScene != nil) {
            return windowScene.interfaceOrientation;
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
}

- (void)sendPluginSuccess:(NSString *)callbackId
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)sendPluginError:(NSString *)message callbackId:(NSString *)callbackId
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:message];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

@end
