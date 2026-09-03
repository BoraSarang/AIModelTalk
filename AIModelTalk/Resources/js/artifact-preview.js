// 아티팩트 프리뷰 인젝터 (v2.5 T-123)
// window.__artifacts = [[lang, doc], ...] — 네이티브(ArtifactPreview)가 생성해 주입
// 지원 코드펜스 위에 미리보기·저장 버튼을 붙이고, 미리보기는 sandbox iframe으로 표시
(function () {
  'use strict';

  var SUPPORTED = { html: 1, svg: 1, mermaid: 1, react: 1 };
  var LABEL = { html: 'HTML', svg: 'SVG', mermaid: 'Mermaid', react: 'React' };

  function postHeight() {
    try {
      var el = document.getElementById('content');
      if (!el || !window.webkit || !window.webkit.messageHandlers.heightChange) return;
      var h = Math.max(el.scrollHeight, el.offsetHeight, 40);
      window.webkit.messageHandlers.heightChange.postMessage(h);
    } catch (e) { /* noop */ }
  }

  function makeToolbar(lang, index) {
    var bar = document.createElement('div');
    bar.className = 'artifact-bar';
    bar.style.cssText = 'display:flex;gap:6px;align-items:center;margin:4px 0 0 0;';

    var previewBtn = document.createElement('button');
    previewBtn.textContent = '\u25B8 \uBBF8\uB9AC\uBCF4\uAE30 (' + (LABEL[lang] || lang) + ')';
    previewBtn.className = 'artifact-preview-btn';
    previewBtn.style.cssText = [
      'font-size:11px', 'padding:2px 8px', 'border-radius:6px', 'cursor:pointer',
      'border:1px solid rgba(128,128,128,.4)', 'background:transparent',
      'color:inherit', 'font-family:inherit'
    ].join(';');

    var saveBtn = document.createElement('button');
    saveBtn.textContent = '\u2E93 \uC800\uC7A5';
    saveBtn.className = 'artifact-save-btn';
    saveBtn.style.cssText = previewBtn.style.cssText;

    bar.appendChild(previewBtn);
    bar.appendChild(saveBtn);
    bar.__previewBtn = previewBtn;
    return bar;
  }

  function togglePreview(pre, doc, lang, btn) {
    var existing = pre.nextSibling;
    if (existing && existing.__artifactPreview) {
      // 이미 열려 있으면 닫기
      existing.parentNode.removeChild(existing);
      btn.textContent = '\u25B8 \uBBF8\uB9AC\uBCF4\uAE30 (' + (LABEL[lang] || lang) + ')';
      postHeight();
      return;
    }

    var frame = document.createElement('iframe');
    frame.setAttribute('sandbox', 'allow-scripts'); // same-origin 차단 — 문서 격리
    frame.setAttribute('srcdoc', doc);
    frame.style.cssText = 'width:100%;height:340px;border:1px solid rgba(128,128,128,.35);' +
                          'border-radius:8px;margin:6px 0;background:#fff;';
    frame.addEventListener('load', postHeight);

    var wrapper = document.createElement('div');
    wrapper.__artifactPreview = true;
    wrapper.appendChild(frame);
    pre.parentNode.insertBefore(wrapper, pre.nextSibling);

    btn.textContent = '\u25BE \uBBF8\uB9AC\uBCF4\uAE30 \uB2EB\uAE30';
    postHeight();
  }

  function requestSave(index) {
    try {
      var handlers = window.webkit && window.webkit.messageHandlers;
      if (handlers && handlers.artifact) {
        handlers.artifact.postMessage({ action: 'download', index: index });
      }
    } catch (e) { /* noop */ }
  }

  function installArtifactButtons(artifacts) {
    artifacts = artifacts || window.__artifacts || [];
    var codeBlocks = document.querySelectorAll('pre > code');
    var artifactIndex = 0;

    codeBlocks.forEach(function (codeEl) {
      if (codeEl.__artifactInstalled) return;
      var match = (codeEl.className || '').match(/language-([\w-]+)/i);
      var rawLang = match ? match[1].toLowerCase() : '';
      var lang = rawLang === 'htm' || rawLang === 'xhtml' ? 'html'
               : rawLang === 'jsx' ? 'react' : rawLang;
      if (!SUPPORTED[lang]) return;

      var i = artifactIndex++;
      if (i >= artifacts.length) return; // 네이티브 감지 결과와 불일치 — 보수적으로 생략

      var pre = codeEl.parentNode;
      var bar = makeToolbar(lang, i);
      pre.parentNode.insertBefore(bar, pre);

      bar.__previewBtn.addEventListener('click', function () {
        togglePreview(pre, artifacts[i][1], lang, bar.__previewBtn);
      });
      bar.querySelector('.artifact-save-btn').addEventListener('click', function () {
        requestSave(i);
      });

      codeEl.__artifactInstalled = true;
    });

    postHeight();
  }

  window.installArtifactButtons = installArtifactButtons;
})();
