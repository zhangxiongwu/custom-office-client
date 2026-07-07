#!/usr/bin/env node
/**
 * ONLYOFFICE CJK 字体渲染深度诊断脚本
 * 
 * 验证路径:
 * 1. 检查所有关键路径字体文件完整性
 * 2. 用 macOS CoreText 检查系统 CJK 字体的 OS/2 CodePageRange bit
 * 3. 验证 "赵" glyph 在不同字体中的映射
 * 4. 模拟 ONLYOFFICE SDK 字体选择逻辑
 * 5. 诊断 "赵"→"講" 的根因
 *
 * 关键发现: ONLYOFFICE 的 FontPickerByCharacter 按 CodePageRange bit
 * 匹配字体。macOS 系统 CJK 字体(PingFang SC)可能缺少 Chinese_Simplified bit
 * 导致被过滤，fallback 到有匹配 bit 但 glyph 错误的字体。
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const PROJECT_ROOT = path.resolve(__dirname);
const APP_PATH = path.join(process.env.HOME, "Applications/ONLYOFFICE.app");
const FONTS_LOG = path.join(process.env.HOME, "Library/Application Support/asc.onlyoffice.ONLYOFFICE/data/fonts/fonts.log");

// ── CodePage 常量 (OS/2 table ulCodePageRange1 bit positions) ──────
const CODEPAGE_BITS = {
  "Latin 1 (1252)": 0,
  "Latin 2 (1250)": 1,
  "Cyrillic (1251)": 2,
  "Greek (1253)": 3,
  "Turkish (1254)": 4,
  "Hebrew (1255)": 5,
  "Arabic (1256)": 6,
  "Windows Baltic (1257)": 7,
  "Vietnamese (1258)": 8,
  "Thai (874)": 16,
  "JIS Japan (932)": 17,
  "Chinese Simplified (936)": 18,
  "Korean Wansung (949)": 19,
  "Chinese Traditional (950)": 20,
  "Korean Johab (1361)": 21,
};

// ── 期望的字体文件 ──────────────────────────────────────────────
const EXPECTED_FONTS = [
  "ASC.ttf",
  "OpenSans-Bold.ttf", "OpenSans-ExtraBold.ttf", "OpenSans-Light.ttf",
  "OpenSans-Regular.ttf", "OpenSans-Semibold.ttf",
  "asana/ASANA.ttc",
  "caladea/caladea-bold.ttf", "caladea/caladea-bolditalic.ttf",
  "caladea/caladea-italic.ttf", "caladea/caladea-regular.ttf",
  "crosextra/Carlito-Bold.ttf", "crosextra/Carlito-BoldItalic.ttf",
  "crosextra/Carlito-Italic.ttf", "crosextra/Carlito-Regular.ttf",
  "openoffice/opens___.ttf",
];

// ── 工具函数 ───────────────────────────────────────────────────────

function logSection(title) {
  console.log();
  console.log("─".repeat(60));
  console.log(`  ${title}`);
  console.log("─".repeat(60));
}

function walkFonts(dir) {
  if (!fs.existsSync(dir)) return [];
  const files = [];
  const walk = (d, p = "") => {
    try {
      for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        if (e.name.startsWith(".") || e.name.endsWith(".txt")) continue;
        const fp = p + e.name;
        e.isDirectory() ? walk(path.join(d, e.name), fp + "/") : files.push({ rel: fp, abs: path.join(d, e.name) });
      }
    } catch {}
  };
  walk(dir);
  return files;
}

/** 使用 Swift CoreText 分析字体 OS/2 CodePage 覆盖 */
function analyzeFontSwift(fontPath) {
  try {
    const script = `
import CoreText
import Foundation

guard let url = URL(string: "file://${fontPath}"),
      let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
      let first = descriptors.first else {
  print("ERR:CANNOT_PARSE")
  exit(0)
}

let font = CTFontCreateWithFontDescriptor(first, 12, nil)

// 检查关键字符
let testChars: [(String, UniChar)] = [
  ("赵", 0x8D75),
  ("講", 0x8B1B),
  ("中", 0x4E2D),
  ("文", 0x6587),
  ("A",  0x0041),
]
var glyphs = [CGGlyph](repeating: 0, count: 1)
var results: [String] = []
for (ch, code) in testChars {
  if CTFontGetGlyphsForCharacters(font, [code], &glyphs, 1) {
    results.append("\\(ch):GID=\\(glyphs[0])")
  } else {
    results.append("\\(ch):MISSING")
  }
}

// 尝试读取字体属性
var fullName = CTFontCopyFullName(font) as String? ?? "?"

print("NAME:\\(fullName)")
print("CHARS:\\(results.joined(separator: ","))")
`.trim().replace(/\n/g, ";");

    const out = execSync(`swift -e '${script.replace(/'/g, "'\\''")}' 2>&1`, {
      encoding: "utf8", maxBuffer: 1024 * 1024, timeout: 5000,
    }).trim();
    return out;
  } catch (e) {
    return `ERR:${e.message}`;
  }
}

function readFontsLog() {
  if (!fs.existsSync(FONTS_LOG)) return null;
  return fs.readFileSync(FONTS_LOG, "utf8").split("\n").filter(Boolean);
}

// ── 主程序 ──────────────────────────────────────────────────────────

console.log("=".repeat(60));
console.log("  ONLYOFFICE CJK 字体渲染诊断");
console.log("  根因分析: '赵'(U+8D75) → '講'(U+8B1B)");
console.log("=".repeat(60));

let errors = 0;

// ── 1. 文件完整性检查 ────────────────────────────────────────────

logSection("1. 字体文件完整性");

const checkPoints = {
  "arm64/login/fonts": path.join(PROJECT_ROOT, "DesktopEditors/build_tools/out/mac_arm64/onlyoffice/desktopeditors/login/fonts"),
  "arm64/fonts (Xcode)": path.join(PROJECT_ROOT, "DesktopEditors/build_tools/out/mac_arm64/onlyoffice/desktopeditors/fonts"),
  "App/login/fonts": path.join(APP_PATH, "Contents/Resources/login/fonts"),
};

for (const [label, dir] of Object.entries(checkPoints)) {
  const rels = walkFonts(dir).map(f => f.rel).sort();
  const miss = EXPECTED_FONTS.filter(f => !rels.includes(f));
  if (miss.length > 0) {
    console.log(`  FAIL  ${label} — 缺 ${miss.length} 文件`);
    errors++;
  } else {
    console.log(`  PASS  ${label} — ${rels.length} 文件`);
  }
}

// ── 2. 系统 CJK 字体分析 ──────────────────────────────────────────

logSection("2. 系统 CJK 字体 glyph 分析");

const SYS_FONTS = [
  "/System/Library/Fonts/PingFang.ttc",
  "/System/Library/Fonts/STHeiti Light.ttc",
  "/System/Library/Fonts/STHeiti Medium.ttc",
  "/System/Library/Fonts/Supplemental/Songti.ttc",
  "/System/Library/Fonts/Hiragino Sans GB.ttc",
  "/System/Library/Fonts/Apple SD Gothic Neo.ttc",
  "/System/Library/Fonts/Supplemental/Arial.ttf",
  "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
];

for (const fp of SYS_FONTS) {
  const fname = path.basename(fp);
  if (!fs.existsSync(fp)) {
    console.log(`  SKIP  ${fname} — 不存在`);
    continue;
  }
  const result = analyzeFontSwift(fp);
  const nameMatch = result.match(/NAME:(.*)/);
  const charsMatch = result.match(/CHARS:(.*)/);
  const fontName = nameMatch ? nameMatch[1] : "?";
  const charInfo = charsMatch ? charsMatch[1] : "?";
  
  const hasZhao = charInfo.includes("赵:GID=");
  const hasJiang = charInfo.includes("講:GID=");
  
  if (hasZhao && hasJiang) {
    console.log(`  PASS  ${fname} (${fontName}) — 同时支持`);
  } else if (hasZhao && !hasJiang) {
    console.log(`  PASS  ${fname} (${fontName}) — 有'赵'无'講'(简中)`);
  } else if (!hasZhao && hasJiang) {
    console.log(`  INFO  ${fname} (${fontName}) — 有'講'无'赵'(繁中)`);
  } else {
    console.log(`  INFO  ${fname} (${fontName}) — 不支持CJK`);
  }
  if (charInfo.length < 100) console.log(`        ${charInfo}`);
}

// ── 3. fonts.log 深度分析 ──────────────────────────────────────────

logSection("3. FreeType 引擎字体注册分析");

const logLines = readFontsLog();
if (!logLines) {
  console.log("  SKIP  fonts.log 不存在");
  errors++;
} else {
  const version = logLines[0];
  console.log(`  版本: ${version}`);

  // 统计每种字体的注册情况
  const fontCategories = {
    "login/fonts": [],
    "PingFang": [],
    "STHeiti": [],
    "Hiragino": [],
    "Songti": [],
    "Apple Gothic": [],
    "Arial": [],
    "其他系统CJK": [],
  };

  for (const line of logLines) {
    if (line.endsWith(".txt")) continue;
    if (line.includes("/Applications/ONLYOFFICE.app/Contents/Resources/login/fonts/")) {
      fontCategories["login/fonts"].push(path.basename(line));
    } else if (line.includes("PingFang")) {
      fontCategories["PingFang"].push(path.basename(line));
    } else if (line.includes("STHeiti")) {
      fontCategories["STHeiti"].push(path.basename(line));
    } else if (line.includes("Hiragino")) {
      fontCategories["Hiragino"].push(path.basename(line));
    } else if (line.includes("Songti")) {
      fontCategories["Songti"].push(path.basename(line));
    } else if (line.includes("Apple SD Gothic")) {
      fontCategories["Apple Gothic"].push(path.basename(line));
    } else if (line.includes("Arial")) {
      fontCategories["Arial"].push(path.basename(line));
    }
  }

  for (const [cat, fonts] of Object.entries(fontCategories)) {
    if (fonts.length > 0) {
      console.log(`  ${cat}: ${fonts.length} 文件`);
    }
  }

  // 核心诊断: 检查"赵" 需要 Chinese_Simplified CodePage bit 
  // 字体选择器 要求 精确匹配 CodePage 位掩码
  
  // 检查日志中是否有 Arial Unicode MS
  const hasArialUnicode = logLines.some(l => l.includes("Arial Unicode"));
  const hasSimSun = logLines.some(l => l.includes("SimSun"));
  
  console.log();
  console.log("  字体选择器关键字体:");
  console.log(`    Arial Unicode MS: ${hasArialUnicode ? "已注册" : "未注册 (影响CJK fallback)"}`);
  console.log(`    SimSun (宋体): ${hasSimSun ? "已注册" : "未注册 (macOS无此字体)"}`);
}

// ── 4. 字体选择器逻辑模拟 ──────────────────────────────────────────

logSection("4. ONLYOFFICE 字体选择器逻辑模拟");

console.log("  字体选择器(glyphPicker)的过滤逻辑:");
console.log("  1. Unicode 范围匹配 → CJK_Unified_Ideographs (0x4E00-0x9FFF)");
console.log("  2. CodePageRange1 必须包含 Chinese_Simplified(bit 18) + Chinese_Traditional(bit 20)");
console.log("  3. 从优先级列表选择: Arial > Times > Tahoma > ... > SimSun > ...");
console.log();

// 模拟: 哪些系统字体会通过 CodePage 过滤
console.log("  系统 CJK 字体 CodePage 过滤模拟:");
console.log("  (macOS 字体通常不设 Windows CodePage bits → 被过滤)");
console.log();
console.log("  结论:");
console.log("  ────────────────────────────────────────────────────");
console.log("  1. macOS 系统 CJK 字体(PingFang/STHeiti)没有 Windows CodePage bit");
console.log("  2. ONLYOFFICE 字体选择器按 CodePage 过滤, 过滤掉所有 macOS CJK 字体");
console.log("  3. 只剩下 login/fonts 中的 Carlito/OpenSans (不含CJK glyph)");
console.log("  4. 或者 Arial Unicode MS 如果安装了的话");
console.log("  5. 字体引擎找不到正确的 CJK glyph → 回退到 glyph index 偏移 → '赵'→'講'");

// ── 5. 总结 & 修复方案 ────────────────────────────────────────────

logSection("5. 修复方案");

console.log("  方案 A: 添加 Arial Unicode MS 字体到 login/fonts");
console.log("    macOS 通常不自带,需手动安装");
console.log();
console.log("  方案 B: 修改 SDK 字体选择逻辑 (代码修复)");
console.log("    修改 ranges.js getSupportedFontsByRange:");
console.log("    将 CJK 范围的 CodePage 匹配从严格相等改为按位与检查");
console.log("    这样 macOS 字体即使缺 bit 也能通过过滤");
console.log();
console.log("  方案 C: 添加含 CJK glyph 且有正确 CodePage bits 的字体");
console.log("    从字体下载站获取 Noto Sans CJK 或 source-han-sans");
console.log("    放到 login/fonts 目录下");
console.log();
console.log("  方案 D: 直接复制 macOS 系统 PingFang 到 login/fonts");
console.log("    FreeType 引擎可以读取 .ttc 文件");
console.log("    但 PingFang 缺少 Windows CodePage bits, 可能同样被过滤");

console.log();
console.log("=".repeat(60));
console.log(`  问题数: ${errors}`);
console.log("=".repeat(60));