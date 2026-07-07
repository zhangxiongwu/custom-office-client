/**
 * myHandlerExcel - Excel Decrypt Service
 *
 * Runs inside CEF browser context. Handles:
 * 1. Receive JSON config from native via window.on_native_message
 * 2. Download encrypted Excel via fetch
 * 3. POST encrypted data to decode API for decryption
 * 4. Send decrypted data back to native via AscDesktopEditor.execCommand
 *    to start a local HTTP server (127.0.0.1 only) for editor preview
 *
 * URL protocol: oo-office://action|excel-decode|?json=URL_ENCODED_JSON
 * JSON format: { file: "url to encrypted xlsx", decode: { url: "decode API", headers: {...} } }
 */

(function () {
    'use strict';

    var native = window.AscDesktopEditor;

    /**
     * Wait until Desktop.js has set up window.on_native_message,
     * then wrap it to intercept our custom command.
     */
    function installHandler() {
        var originalHandler = window.on_native_message;

        window.on_native_message = function (cmd, param) {
            if (cmd === 'myHandlerExcel:handle') {
                handleExcelDecrypt(param);
                return;
            }
            if (originalHandler) {
                originalHandler(cmd, param);
            }
        };
    }

    /**
     * Convert ArrayBuffer to Base64 string
     */
    function arrayBufferToBase64(buffer) {
        var bytes = new Uint8Array(buffer);
        var binary = '';
        for (var i = 0; i < bytes.byteLength; i++) {
            binary += String.fromCharCode(bytes[i]);
        }
        return btoa(binary);
    }

    /**
     * Main handler: parse JSON config, download & decrypt, callback to native
     */
    function handleExcelDecrypt(queryString) {
        var config;
        try {
            config = JSON.parse(queryString);
        } catch (e) {
            console.error('[myHandlerExcel] Failed to parse JSON config:', e);
            return;
        }

        if (!config.file) {
            console.error('[myHandlerExcel] Missing file URL in config');
            return;
        }

        console.log('[myHandlerExcel] Downloading encrypted file:', config.file);

        fetch(config.file)
            .then(function (response) {
                if (!response.ok) {
                    throw new Error('Download failed: HTTP ' + response.status);
                }
                return response.arrayBuffer();
            })
            .then(function (encryptedData) {
                console.log('[myHandlerExcel] Downloaded', encryptedData.byteLength, 'bytes');

                var decodeConfig = config.decode;
                if (!decodeConfig || !decodeConfig.url) {
                    console.log('[myHandlerExcel] No decode config, using file as-is');
                    startNativeServer(encryptedData);
                    return;
                }

                console.log('[myHandlerExcel] Decrypting via:', decodeConfig.url);

                var headers = new Headers();
                headers.append('Content-Type', 'application/octet-stream');

                if (decodeConfig.headers) {
                    Object.keys(decodeConfig.headers).forEach(function (key) {
                        var value = decodeConfig.headers[key];
                        if (typeof value === 'string') {
                            headers.append(key, value);
                        }
                    });
                }

                return fetch(decodeConfig.url, {
                    method: 'POST',
                    headers: headers,
                    body: encryptedData
                }).then(function (response) {
                    if (!response.ok) {
                        throw new Error('Decryption failed: HTTP ' + response.status);
                    }
                    return response.arrayBuffer();
                });
            })
            .then(function (decryptedData) {
                if (!decryptedData) return;
                console.log('[myHandlerExcel] Decrypted data:', decryptedData.byteLength, 'bytes');
                startNativeServer(decryptedData);
            })
            .catch(function (err) {
                console.error('[myHandlerExcel] Error:', err);
            });
    }

    /**
     * Send decrypted data to native to start HTTP server
     */
    function startNativeServer(arrayBuffer) {
        if (!native) {
            console.error('[myHandlerExcel] AscDesktopEditor not available');
            return;
        }

        var base64 = arrayBufferToBase64(arrayBuffer);
        console.log('[myHandlerExcel] Starting native HTTP server, base64 length:', base64.length);

        try {
            native.execCommand('myHandlerExcel:startServer:' + base64, '');
        } catch (e) {
            console.error('[myHandlerExcel] Failed to call native execCommand:', e);
        }
    }

    // Install after a short delay to let Desktop.js set up on_native_message
    var checkAttempts = 0;
    var maxAttempts = 50;
    var checkInterval = setInterval(function () {
        checkAttempts++;
        if (typeof window.on_native_message === 'function' &&
            window.on_native_message.toString().indexOf('myHandlerExcel:handle') === -1) {
            installHandler();
            clearInterval(checkInterval);
            console.log('[myHandlerExcel] Handler installed');
        } else if (checkAttempts >= maxAttempts) {
            clearInterval(checkInterval);
            // Fallback: install even if Desktop.js hasn't loaded yet
            console.warn('[myHandlerExcel] Desktop.js not detected, installing fallback handler');
            installHandler();
        }
    }, 100);
})();
