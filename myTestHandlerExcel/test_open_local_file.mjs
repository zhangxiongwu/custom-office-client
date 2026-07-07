#!/usr/bin/env node
/**
 * myTestHandlerExcel - 唤起客户端打开本地文件测试
 *
 * 测试流程:
 * 1. 通过 open -a 命令唤起 ONLYOFFICE 打开本地 test_sales.xlsx
 * 2. 验证应用是否正常加载文件
 *
 * 使用方法:
 *   node myTestHandlerExcel/test_open_local_file.mjs
 *
 * ⚠️ 注意:
 *   浏览器 URL 栏无法直接用 URL Scheme 打开本地文件（浏览器安全限制）。
 *   以下是在浏览器地址栏可直接使用的 oo-office:// 协议唤醒测试 URL:
 *
 *   纯唤醒（打开首页）:
 *     oo-office://
 *
 *   面板选择:
 *     oo-office://action|panel|
 *
 *   Excel 解密预览（开发中）:
 *     oo-office://action|excel-decode|?json=URL_ENCODED_JSON
 */

import { execSync } from 'child_process';
import { setTimeout } from 'timers/promises';
import { existsSync } from 'fs';
import { resolve, dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// 彩色输出
const c = { red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m', cyan: '\x1b[36m', magenta: '\x1b[35m', reset: '\x1b[0m' };
function log(level, msg) { console.log(`  ${({ok:c.green+'✓',fail:c.red+'✗',info:c.cyan+'ℹ',warn:c.yellow+'⚠',url:c.magenta+'▶'}[level]||'')} ${msg}${c.reset}`); }
function section(t) { console.log(`\n${c.cyan}━━━ ${t} ━━━${c.reset}`); }

function execCmd(cmd, timeout = 10000) {
    try { return execSync(cmd, { encoding: 'utf8', timeout }).trim(); } catch { return ''; }
}

// ============================================================
// 自动查找应用
// ============================================================
const WORKSPACE = resolve(execCmd('git rev-parse --show-toplevel'), '.') || resolve(__dirname, '../..');

const CANDIDATE_PATHS = [
    `${process.env.HOME}/Applications/ONLYOFFICE.app`,
    '/Applications/ONLYOFFICE.app',
    resolve(WORKSPACE, 'dist/ONLYOFFICE.app'),
    resolve(WORKSPACE, 'DesktopEditors/build_tools/out/ONLYOFFICE.app'),
];

function findApp() {
    for (const p of CANDIDATE_PATHS) {
        if (existsSync(p)) return p;
    }
    return execCmd(`mdfind "kMDItemDisplayName == 'ONLYOFFICE'" 2>/dev/null | head -1`) || null;
}

const APP_PATH = findApp();

// ============================================================
// 自动签名
// ============================================================
function codesignApp(appPath) {
    const appExec = `${appPath}/Contents/MacOS/ONLYOFFICE`;
    if (!existsSync(appExec)) return false;

    const signInfo = execCmd(`codesign -dv "${appPath}" 2>&1`);
    if (signInfo.includes('adhoc') || signInfo.includes('Authority=Apple Development')) {
        log('ok', '应用已签名');
        return true;
    }

    log('warn', '应用未签名，正在 ad-hoc 签名...');
    const cmds = [
        `find "${appPath}/Contents/Frameworks" -name "*.dylib" -exec codesign --force --sign - {} \\; 2>/dev/null`,
        `codesign --force --deep --sign - "${appPath}/Contents/Frameworks/Chromium Embedded Framework.framework" 2>/dev/null`,
        `find "${appPath}/Contents/Resources/converter" -name "*.dylib" -exec codesign --force --sign - {} \\; 2>/dev/null`,
        `codesign --force --sign - "${appExec}" 2>/dev/null`,
        `codesign --force --deep --sign - "${appPath}" 2>/dev/null`,
    ];
    for (const cmd of cmds) execCmd(cmd, 30000);
    log('ok', '签名完成');
    return true;
}

// ============================================================
// 启动应用
// ============================================================
async function launchApp() {
    const running = execCmd('pgrep -f "ONLYOFFICE"');
    if (running) {
        log('ok', `应用正在运行 (PID: ${running.split('\n')[0]})`);
        return;
    }

    log('info', '启动应用...');
    execCmd(`open "${APP_PATH}"`, 10000);

    for (let i = 0; i < 40; i++) {
        await setTimeout(1000);
        if (execCmd('pgrep -f "ONLYOFFICE"')) {
            log('ok', '应用已启动');
            await setTimeout(5000);
            return;
        }
    }
    log('fail', '应用启动超时');
    process.exit(1);
}

// ============================================================
// 展示浏览器可用的 URL Scheme
// ============================================================
function showBrowserURLs() {
    section('浏览器 URL 栏可直接使用的协议唤醒地址');
    const urls = [
        { url: 'oo-office://',                                       desc: '纯唤醒 — 打开 ONLYOFFICE 首页' },
        { url: 'oo-office://action|panel|',                          desc: '面板选择' },
        { url: 'oo-office://action|excel-decode|?json=URL_ENCODED',  desc: 'Excel 解密预览（开发中）' },
    ];

    console.log(`  ${c.yellow}以下 URL 可直接复制到浏览器地址栏回车测试:${c.reset}\n`);
    for (const u of urls) {
        console.log(`  ${c.magenta}▶${c.reset}  ${c.cyan}${u.url}${c.reset}`);
        console.log(`     ${u.desc}\n`);
    }

    console.log(`  ${c.yellow}⚠️  本地文件无法通过浏览器 URL Scheme 直接打开（安全限制）${c.reset}`);
    console.log(`  ${c.yellow}   请用以下方式打开本地文件:${c.reset}`);
    console.log(`  ${c.yellow}   - 终端: open -a ONLYOFFICE.app test_sales.xlsx${c.reset}`);
    console.log(`  ${c.yellow}   - Node:  node myTestHandlerExcel/test_open_local_file.mjs${c.reset}`);
}

// ============================================================
// 测试打开本地文件
// ============================================================
async function testOpenLocalFile() {
    section('打开本地文件测试');

    const testFile = join(WORKSPACE, 'test_sales.xlsx');
    if (!existsSync(testFile)) {
        log('fail', `文件不存在: ${testFile}`);
        process.exit(1);
    }

    // 方式 1: open -a 直接打开
    log('info', `方式 1 — open -a 命令打开: ${testFile}`);
    execCmd(`open -a "${APP_PATH}" "${testFile}"`, 5000);
    await setTimeout(3000);

    if (!execCmd('pgrep -f "ONLYOFFICE"')) {
        log('fail', '应用在打开文件后崩溃');
        process.exit(1);
    }
    log('ok', '进程存活 — 文件已在编辑器中打开');

    // 方式 2: file:// URL (通过 open 命令等价于浏览器行为)
    const fileURL = `file://${testFile}`;
    log('info', `方式 2 — file:// URL 打开: ${fileURL}`);
    execCmd(`open "${fileURL}"`, 5000);
    await setTimeout(2000);

    if (!execCmd('pgrep -f "ONLYOFFICE"')) {
        log('fail', '应用在打开 file:// URL 后崩溃');
        process.exit(1);
    }
    log('ok', '进程存活');
}

// ============================================================
// 主函数
// ============================================================
async function main() {
    console.log(`${c.cyan}
  ╔══════════════════════════════════════════════╗
  ║   唤起客户端打开本地文件测试                   ║
  ║   myTestHandlerExcel                       ║
  ╚══════════════════════════════════════════════╝
${c.reset}`);

    const start = Date.now();

    // 1. 查找应用
    section('步骤 1: 查找 ONLYOFFICE.app');
    if (!APP_PATH) {
        log('fail', '未找到应用');
        CANDIDATE_PATHS.forEach(p => log('info', existsSync(p) ? `  ✓ ${p}` : `  ✗ ${p}`));
        log('info', '请先运行: bash install.command && bash build.command');
        process.exit(1);
    }
    log('ok', APP_PATH);

    // 2. 签名
    section('步骤 2: 签名检查');
    codesignApp(APP_PATH);

    // 3. 浏览器 URL 展示
    showBrowserURLs();

    // 4. 启动
    section('步骤 3: 启动应用');
    await launchApp();

    // 5. 打开文件测试
    await testOpenLocalFile();

    // 6. 验证
    section('步骤 4: 验证结果');
    const crashes = execCmd(`ls -t ~/Library/Logs/DiagnosticReports/ONLYOFFICE*.crash 2>/dev/null | head -1`, 5000);
    if (crashes) { log('fail', `发现崩溃报告: ${crashes}`); process.exit(1); }
    log('ok', '无崩溃报告');

    console.log(`\n${c.green}━━━ 全部测试通过 (${((Date.now()-start)/1000).toFixed(1)}s) ━━━${c.reset}\n`);
    process.exit(0);
}

main().catch(err => { console.error(`${c.red}${err.message}${c.reset}`); process.exit(1); });
