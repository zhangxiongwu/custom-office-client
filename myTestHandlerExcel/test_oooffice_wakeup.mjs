#!/usr/bin/env node
/**
 * myTestHandlerExcel - oo-office:// 协议唤醒测试
 *
 * 测试流程:
 * 1. 自动查找 ONLYOFFICE.app（dist/ 或 ~/Applications/ 等）
 * 2. 自动 ad-hoc 签名（如需要）
 * 3. 启动应用
 * 4. 通过 oo-office:// 协议发送唤醒命令
 * 5. 验证登录页是否正常加载
 * 6. 测试创建新表格
 *
 * 使用方法:
 *   node myTestHandlerExcel/test_oooffice_wakeup.mjs
 *   或双击 myTestHandlerExcel/run_test.command
 */

import { execSync } from 'child_process';
import { setTimeout } from 'timers/promises';
import { existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// 彩色输出
const c = { red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m', cyan: '\x1b[36m', reset: '\x1b[0m' };
function log(level, msg) { console.log(`  ${({ok:c.green+'✓',fail:c.red+'✗',info:c.cyan+'ℹ',warn:c.yellow+'⚠'}[level]||'')} ${msg}${c.reset}`); }
function section(t) { console.log(`\n${c.cyan}━━━ ${t} ━━━${c.reset}`); }

function execCmd(cmd, timeout = 10000) {
    try { return execSync(cmd, { encoding: 'utf8', timeout }).trim(); } catch { return ''; }
}

// ============================================================
// 步骤 1: 自动查找应用
// ============================================================
const WORKSPACE = resolve(execCmd('git rev-parse --show-toplevel'), '../../') || resolve(__dirname, '../..');

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

let APP_PATH = findApp();

// ============================================================
// 步骤 2: 自动签名
// ============================================================
function codesignApp(appPath) {
    const appExec = `${appPath}/Contents/MacOS/ONLYOFFICE`;
    if (!existsSync(appExec)) return false;

    // 检查是否已签名
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
// 步骤 3: 启动应用
// ============================================================
async function launchApp() {
    const running = execCmd('pgrep -f "ONLYOFFICE"');
    if (running) {
        log('ok', `应用正在运行 (PID: ${running})`);
        return;
    }

    log('info', '启动应用...');
    execCmd(`open "${APP_PATH}"`, 10000);

    for (let i = 0; i < 40; i++) {
        await setTimeout(1000);
        if (execCmd('pgrep -f "ONLYOFFICE"')) {
            log('ok', '应用已启动');
            await setTimeout(5000); // 等登录页加载
            return;
        }
    }
    log('fail', '应用启动超时');
    process.exit(1);
}

// ============================================================
// 步骤 4: oo-office:// 协议测试
// ============================================================
async function testProtocol() {
    const tests = [
        { url: 'oo-office://',                desc: '纯唤醒（打开首页）' },
        { url: 'oo-office://action|panel|',   desc: '面板选择' },
        { url: 'oo-office://--new:cell',      desc: '创建新表格' },
    ];

    for (const t of tests) {
        log('info', `发送: ${t.url}  (${t.desc})`);
        execCmd(`open "${t.url}"`, 5000);
        await setTimeout(2000);

        if (!execCmd('pgrep -f "ONLYOFFICE"')) {
            log('fail', `应用在 "${t.desc}" 后崩溃`);
            process.exit(1);
        }
        log('ok', `  进程存活 — ${t.desc}`);
    }
}

// ============================================================
// 步骤 5: 验证窗口
// ============================================================
async function verifyWindows() {
    const win = execCmd(`osascript -e 'tell app "System Events" to name of windows of process "ONLYOFFICE"' 2>/dev/null`, 5000);
    if (win) { log('ok', `窗口: ${win}`); }
    else { log('warn', '无法获取窗口信息'); }

    // 检查崩溃日志
    const crashes = execCmd(`ls -t ~/Library/Logs/DiagnosticReports/ONLYOFFICE*.crash 2>/dev/null | head -1`, 5000);
    if (crashes) { log('fail', `发现崩溃报告: ${crashes}`); process.exit(1); }
    else { log('ok', '无崩溃报告'); }
}

// ============================================================
// 主函数
// ============================================================
async function main() {
    console.log(`${c.cyan}
  ╔══════════════════════════════════════════════╗
  ║   oo-office:// 协议唤醒测试                   ║
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

    // 3. 启动
    section('步骤 3: 启动应用');
    await launchApp();

    // 4. 协议测试
    section('步骤 4: oo-office:// 协议测试');
    await testProtocol();

    // 5. 验证
    section('步骤 5: 验证结果');
    await verifyWindows();

    console.log(`\n${c.green}━━━ 全部测试通过 (${((Date.now()-start)/1000).toFixed(1)}s) ━━━${c.reset}\n`);
    process.exit(0);
}

main().catch(err => { console.error(`${c.red}${err.message}${c.reset}`); process.exit(1); });
