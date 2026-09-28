const test = require('node:test');
const assert = require('node:assert/strict');
const { splitDiagrams, validateIncludes } = require('../Resources/Web/source.js');

test('BOM, CRLF, Chinese and multiple diagram selection retain sources', () => {
  const input = '\uFEFF@startuml\r\ntitle 一\r\nAlice -> Bob: 你好\r\n@enduml\r\n@startmindmap\r\n* 二\r\n@endmindmap';
  const diagrams = splitDiagrams(input);
  assert.equal(diagrams.length, 2);
  assert.equal(diagrams[0].title, '一');
  assert.match(diagrams[1].source, /\* 二/);
  assert.doesNotMatch(diagrams[1].source, /Alice/);
});
test('incomplete, nested or mismatched diagrams have actionable errors', () => {
  assert.throws(() => splitDiagrams('@startuml\nAlice -> Bob'), /缺少 @enduml/);
  assert.throws(() => splitDiagrams('@startuml\n@endjson'), /不匹配/);
  assert.throws(() => splitDiagrams('@startuml\n@startuml'), /前一张图/);
  assert.throws(() => splitDiagrams('not a diagram'), /没有找到/);
});
test('shared preamble is retained for every diagram', () => {
  const diagrams = splitDiagrams('!define NAME Alice\n@startuml\nNAME -> Bob\n@enduml\n@startuml\nNAME -> Eve\n@enduml');
  assert.ok(diagrams.every(d => d.source.startsWith('!define NAME Alice')));
});
test('only bundled standard libraries are accepted by offline includes', () => {
  validateIncludes("!include <C4/C4_Context> ' local library\n!include_once <archimate/Archimate>");
  for (const source of ['!include https://example.com/a', '!includeurl https://example.com/a', '!include ../secrets', '!import /tmp/file', '!include_many "a.puml"']) {
    assert.throws(() => validateIncludes(source), /离线预览/);
  }
  assert.throws(() => validateIncludes('!include <awslib/AWSCommon>'), /未内置标准库/);
});
