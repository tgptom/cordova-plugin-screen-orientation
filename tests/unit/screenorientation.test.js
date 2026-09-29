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

const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', '..', 'www', 'screenorientation.js'), 'utf8');

/**
 * Loads www/screenorientation.js in an isolated context with a fake
 * cordova.exec, so the native callbacks can be driven from the tests.
 */
function loadPlugin () {
    const execCalls = [];
    const window = {
        orientation: 0,
        addEventListener: function () {}
    };
    const context = {
        window,
        document: { createEvent: function () { return { initEvent: function () {} }; } },
        XMLHttpRequest: function () {
            this.addEventListener = function () {};
            this.removeEventListener = function () {};
            this.dispatchEvent = function () {};
        },
        cordova: {
            exec: function (success, fail, service, action, args) {
                execCalls.push({ success, fail, service, action, args });
            }
        },
        Promise,
        Error,
        module: { exports: {} }
    };
    vm.runInNewContext(source, context);
    return { screenOrientation: context.module.exports, execCalls, window };
}

async function isPending (promise) {
    const marker = {};
    const result = await Promise.race([promise.then(() => 'resolved', () => 'rejected'), Promise.resolve(marker)]);
    return result === marker;
}

const SUPPORTED = [
    'portrait-primary',
    'portrait-secondary',
    'landscape-primary',
    'landscape-secondary',
    'portrait',
    'landscape',
    'any'
];

describe('screen.orientation', function () {
    let plugin;

    beforeEach(function () {
        plugin = loadPlugin();
    });

    describe('lock()', function () {
        for (const orientation of SUPPORTED) {
            it('sends only the orientation value to native for "' + orientation + '"', function () {
                plugin.screenOrientation.lock(orientation);
                assert.equal(plugin.execCalls.length, 1);
                const call = plugin.execCalls[0];
                assert.equal(call.service, 'CDVOrientation');
                assert.equal(call.action, 'screenOrientation');
                assert.deepEqual(Array.from(call.args), [orientation]);
            });
        }

        it('stays pending until the native callback is invoked', async function () {
            const promise = plugin.screenOrientation.lock('landscape');
            assert.equal(await isPending(promise), true);
            plugin.execCalls[0].success();
            await promise;
        });

        it('resolves when native reports success', async function () {
            const promise = plugin.screenOrientation.lock('portrait-primary');
            plugin.execCalls[0].success();
            assert.equal(await promise, undefined);
        });

        it('rejects with the native error name and message', async function () {
            const promise = plugin.screenOrientation.lock('landscape-secondary');
            plugin.execCalls[0].fail({ name: 'AbortError', message: 'Failed to update interface orientation' });
            await assert.rejects(promise, { name: 'AbortError', message: 'Failed to update interface orientation' });
        });

        it('rejects with an Error when native reports a string error', async function () {
            const promise = plugin.screenOrientation.lock('portrait');
            plugin.execCalls[0].fail('Class not found');
            await assert.rejects(promise, { name: 'Error', message: 'Class not found' });
        });

        it('rejects with a fallback message when native reports no error details', async function () {
            const promise = plugin.screenOrientation.lock('portrait');
            plugin.execCalls[0].fail();
            await assert.rejects(promise, { name: 'Error', message: 'Unable to set orientation: portrait' });
        });

        for (const invalid of ['upside-down', '', undefined, null, 15, 'toString', '__proto__', {}]) {
            it('rejects invalid value ' + JSON.stringify(invalid) + ' with NotSupportedError without calling native', async function () {
                await assert.rejects(plugin.screenOrientation.lock(invalid), { name: 'NotSupportedError' });
                assert.equal(plugin.execCalls.length, 0);
            });
        }
    });

    describe('unlock()', function () {
        it('requests "any" from native and returns a Promise', async function () {
            const promise = plugin.screenOrientation.unlock();
            assert.ok(promise instanceof Promise);
            assert.equal(plugin.execCalls.length, 1);
            assert.deepEqual(Array.from(plugin.execCalls[0].args), ['any']);
            assert.equal(await isPending(promise), true);
            plugin.execCalls[0].success();
            await promise;
        });

        it('does not throw synchronously and rejects on native error', async function () {
            let promise;
            assert.doesNotThrow(function () {
                promise = plugin.screenOrientation.unlock();
            });
            plugin.execCalls[0].fail({ name: 'InvalidStateError', message: 'No view controller' });
            await assert.rejects(promise, { name: 'InvalidStateError', message: 'No view controller' });
        });
    });

    describe('properties', function () {
        it('exposes OrientationLockType values', function () {
            assert.equal(plugin.window.OrientationLockType.any, 15);
            assert.equal(plugin.window.OrientationLockType.portrait, 3);
            assert.equal(plugin.window.OrientationLockType.landscape, 12);
        });

        it('derives type and angle from window.orientation', function () {
            assert.equal(plugin.screenOrientation.type, 'portrait-primary');
            assert.equal(plugin.screenOrientation.angle, 0);
        });
    });
});
