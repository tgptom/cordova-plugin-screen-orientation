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

#import <Cordova/CDVPlugin.h>
#import <UIKit/UIKit.h>
#import <Cordova/CDVViewController.h>

#if __has_include(<Cordova/CDVScreenOrientationDelegate.h>)
#import <Cordova/CDVScreenOrientationDelegate.h>
#define CDV_ORIENTATION_HAS_SCREEN_ORIENTATION_DELEGATE 1
#else
#define CDV_ORIENTATION_HAS_SCREEN_ORIENTATION_DELEGATE 0
#endif

// CDVScreenOrientationDelegate is marked deprecated in cordova-ios 8, but it is
// still the public Cordova protocol describing an orientation provider.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@interface CDVOrientation : CDVPlugin
#if CDV_ORIENTATION_HAS_SCREEN_ORIENTATION_DELEGATE
<CDVScreenOrientationDelegate>
#endif
{
@protected
    BOOL _isLocked;
    UIInterfaceOrientation _lastOrientation;
    // Plugin-owned orientation mask. 0 means the plugin has not requested any orientation yet.
    UIInterfaceOrientationMask _supportedOrientationMask;
    NSUInteger _requestGeneration;
}

- (void)screenOrientation:(CDVInvokedUrlCommand *)command;

- (UIInterfaceOrientationMask)supportedInterfaceOrientations;

- (BOOL)shouldAutorotate;

@end
#pragma clang diagnostic pop
