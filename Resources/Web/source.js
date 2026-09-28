/* Pure source preparation, shared by the WebKit renderer and Node tests. */
(function (root) {
  'use strict';
  const libraries = new Set(['adaml', 'archimate', 'azure', 'c4', 'classy', 'classy-c4',
    'cloudinsight', 'cloudogu', 'domainstory', 'edgy', 'eip', 'elastic', 'gcp', 'k8s', 'kubernetes', 'osa2']);

  function splitDiagrams(source) {
    const lines = source.replace(/^\uFEFF/, '').split(/\r\n|\r|\n/);
    const diagrams = [];
    let start = -1, kind = '', preamble = [];
    for (let i = 0; i < lines.length; i++) {
      const begin = /^\s*@start([a-z]+)\b/i.exec(lines[i]);
      const end = /^\s*@end([a-z]+)\b/i.exec(lines[i]);
      if (begin) {
        if (start !== -1) throw new Error('第 ' + (i + 1) + ' 行：前一张图缺少 @end' + kind + '。');
        start = i; kind = begin[1].toLowerCase();
      } else if (end && start !== -1) {
        if (end[1].toLowerCase() !== kind) throw new Error('第 ' + (i + 1) + ' 行：开始和结束标记不匹配。');
        const body = lines.slice(start, i + 1);
        const title = body.map(line => /^\s*title\s+(.+)/i.exec(line)).find(Boolean);
        diagrams.push({ source: preamble.concat(body).join('\n'), title: title ? title[1] : '图 ' + (diagrams.length + 1), line: start + 1 });
        start = -1;
      } else if (start === -1 && diagrams.length === 0) {
        preamble.push(lines[i]);
      }
    }
    if (start !== -1) throw new Error('缺少 @end' + kind + '，请检查第 ' + (start + 1) + ' 行开始的图。');
    if (!diagrams.length) throw new Error('没有找到图表。请使用 @startuml 和 @enduml 包围图表源码。');
    return diagrams;
  }

  function validateIncludes(source) {
    // No sibling-file or remote includes: Quick Look only grants the selected file.
    for (const line of source.split(/\r\n|\r|\n/)) {
      const include = /^\s*!(?:include(?:_once|_many|url)?|import)\s+(.+)/i.exec(line);
      if (!include) continue;
      const target = /^<([a-z0-9_-]+)(?:\/[^>]+)?>\s*(?:'.*)?$/i.exec(include[1].trim());
      if (!target) throw new Error('离线预览仅支持内置标准库 !include <库/文件>。请先将本地文件或 URL 引用展开为单个文件。');
      if (!libraries.has(target[1].toLowerCase())) throw new Error('未内置标准库：' + target[1] + '。本版本包含 C4、Archimate 等 16 个标准库。');
    }
  }

  const api = { splitDiagrams, validateIncludes };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.PlantUMLSource = api;
})(globalThis);
