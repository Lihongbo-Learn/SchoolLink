(function () {
  'use strict';

  var INDEX = [
    { page: 'guide.html', pageTitle: '快速开始', group: '入门指南', title: '快速开始', hash: 'top', keywords: '第一次 部署 使用 概览' },
    { page: 'guide.html', pageTitle: '快速开始', group: '入门指南', title: '安装与更新通道', hash: 'install', keywords: '下载 安装包 apk 更新 SmartScreen 签名' },
    { page: 'guide.html', pageTitle: '快速开始', group: '入门指南', title: '启动 Hub', hash: 'hub', keywords: '服务器 部署 Windows Linux 默认 PIN 注册码' },
    { page: 'guide.html', pageTitle: '快速开始', group: '入门指南', title: '教室端设置', hash: 'classroom', keywords: '年级 班级 锁定 大屏 kiosk 全屏' },
    { page: 'guide.html', pageTitle: '快速开始', group: '入门指南', title: '教师端登录', hash: 'teacher', keywords: '姓名 PIN 注册码 任教班级 登录' },
    { page: 'guide.html', pageTitle: '快速开始', group: '入门指南', title: '发送通知', hash: 'notice', keywords: '全屏 关闭 自动关闭 提示音 手动确认' },
    { page: 'guide.html', pageTitle: '快速开始', group: '入门指南', title: '文件接收', hash: 'files', keywords: '文件 自动保存 附件 下载 保留' },
    { page: 'guide.html', pageTitle: '快速开始', group: '部署与维护', title: '网络与防火墙', hash: 'network', keywords: '端口 8421 8422 8424 防火墙 子网 直连' },
    { page: 'guide.html', pageTitle: '快速开始', group: '部署与维护', title: '数据与备份', hash: 'data', keywords: '数据目录 备份 保留 90 天' },
    { page: 'guide.html', pageTitle: '快速开始', group: '部署与维护', title: '升级与重置', hash: 'update', keywords: '升级 卸载 重装 教室模式 重置' },
    { page: 'guide.html', pageTitle: '快速开始', group: '部署与维护', title: '常见问题', hash: 'faq', keywords: '无法访问 局域网 SmartScreen 后台 全屏 限制' },
    { page: 'develop.html', pageTitle: '开发文档', group: '起步', title: '开发文档', hash: 'top', keywords: '贡献 开发者 概览' },
    { page: 'develop.html', pageTitle: '开发文档', group: '起步', title: '开发环境', hash: 'environment', keywords: 'Flutter Dart Android SDK NDK Visual Studio Inno Setup' },
    { page: 'develop.html', pageTitle: '开发文档', group: '起步', title: '项目结构', hash: 'structure', keywords: '目录 packages apps protocol hub' },
    { page: 'develop.html', pageTitle: '开发文档', group: '起步', title: '构建与运行', hash: 'build', keywords: 'flutter build apk web windows 打包 package' },
    { page: 'develop.html', pageTitle: '开发文档', group: '应用核心', title: '架构总览', hash: 'architecture', keywords: '混合网络 直连 Hub 架构' },
    { page: 'develop.html', pageTitle: '开发文档', group: '应用核心', title: '启动流程', hash: 'startup', keywords: 'AppController onboarding 初始化 平台 连接' },
    { page: 'develop.html', pageTitle: '开发文档', group: '应用核心', title: '通知系统', hash: 'notices', keywords: '通知 全屏 关闭模式 提示音 历史 去重' },
    { page: 'develop.html', pageTitle: '开发文档', group: '应用核心', title: '文件传输', hash: 'files', keywords: '上传 下载 文件 sha256 自动保存' },
    { page: 'develop.html', pageTitle: '开发文档', group: '应用核心', title: '混合网络', hash: 'network', keywords: 'UDP 发现 WebSocket HMAC 重试 去重 离线' },
    { page: 'develop.html', pageTitle: '开发文档', group: '应用核心', title: 'Hub 服务', hash: 'hub', keywords: 'shelf sembast API 管理台 数据' },
    { page: 'develop.html', pageTitle: '开发文档', group: '应用核心', title: '桌面与平台', hash: 'desktop', keywords: '托盘 无边框 Windows Android Web' },
    { page: 'develop.html', pageTitle: '开发文档', group: '参与', title: '参与贡献', hash: 'contributing', keywords: 'PR fork 测试 analyze 规范' },
    { page: 'develop.html', pageTitle: '开发文档', group: '参与', title: '文档维护', hash: 'docs', keywords: '文档 官网 搜索 维护' }
  ];

  var body = document.body;
  var menuButton = document.getElementById('docsMenu');
  var sidebarBackdrop = document.getElementById('sidebarBackdrop');
  var sidebar = document.getElementById('docsSidebar');
  var searchModal = document.getElementById('searchModal');
  var searchInput = document.getElementById('searchInput');
  var searchResults = document.getElementById('searchResults');
  var searchTrigger = document.querySelector('[data-open-search]');
  var lastFocus = null;
  var activeResult = -1;
  var currentResults = [];

  function setDrawer(open) {
    body.classList.toggle('drawer-open', open);
    if (menuButton) menuButton.setAttribute('aria-expanded', String(open));
    if (sidebarBackdrop) sidebarBackdrop.hidden = !open;
  }

  if (menuButton) {
    menuButton.addEventListener('click', function () {
      setDrawer(!body.classList.contains('drawer-open'));
    });
  }

  if (sidebarBackdrop) {
    sidebarBackdrop.addEventListener('click', function () {
      setDrawer(false);
    });
  }

  if (sidebar) {
    sidebar.addEventListener('click', function (event) {
      if (event.target.closest('a') && window.innerWidth <= 1000) setDrawer(false);
    });
  }

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') {
      setDrawer(false);
      closeSearch();
    }
  });

  /* Reading stats */
  var article = document.querySelector('.docs-article');
  var wordCount = document.getElementById('wordCount');
  var readTime = document.getElementById('readTime');
  if (article && wordCount) {
    var text = article.innerText || '';
    var cjk = (text.match(/[\u4e00-\u9fff]/g) || []).length;
    var latin = (text.match(/[A-Za-z0-9_]+/g) || []).length;
    var total = cjk + latin;
    wordCount.textContent = String(total);
    if (readTime) readTime.textContent = Math.max(1, Math.round(total / 300)) + ' 分钟';
  }

  /* Sidebar active section */
  var sideLinks = Array.prototype.slice.call(document.querySelectorAll('.side-link[href^="#"]'));
  var linkByHash = {};
  sideLinks.forEach(function (link) {
    var id = link.getAttribute('href').slice(1);
    if (!linkByHash[id]) linkByHash[id] = [];
    linkByHash[id].push(link);
  });

  function markActive(id) {
    var links = linkByHash[id];
    if (!links) return;
    sideLinks.forEach(function (link) { link.classList.remove('active'); });
    links.forEach(function (link) { link.classList.add('active'); });
  }

  var headings = Array.prototype.slice.call(document.querySelectorAll('.docs-article h2[id], .docs-article h1[id]'));
  function updateActiveSection() {
    if (!headings.length) return;
    var offset = 96;
    var active = headings[0];
    for (var i = 0; i < headings.length; i++) {
      if (headings[i].getBoundingClientRect().top <= offset) active = headings[i];
      else break;
    }
    markActive(active.id);
  }

  var ticking = false;
  window.addEventListener('scroll', function () {
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(function () {
      updateActiveSection();
      ticking = false;
    });
  }, { passive: true });

  window.addEventListener('hashchange', function () {
    var id = location.hash.slice(1);
    if (id) markActive(id);
  });

  if (headings.length) {
    updateActiveSection();
    if (location.hash) markActive(location.hash.slice(1));
  }

  /* Search */
  function escapeText(value) {
    return value.replace(/[&<>"']/g, function (char) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char];
    });
  }

  function renderResults(items, query) {
    if (!searchResults) return;
    currentResults = items;
    activeResult = -1;
    searchResults.innerHTML = '';
    if (!items.length) {
      searchResults.innerHTML = '<div class="search-empty">没有找到相关内容，试试其他关键词。</div>';
      return;
    }
    items.forEach(function (item, index) {
      var link = document.createElement('a');
      link.className = 'search-result';
      link.href = item.page + '#' + item.hash;
      link.dataset.index = String(index);
      link.innerHTML =
        '<span>' + escapeText(item.group) + ' · ' + escapeText(item.pageTitle) + '</span>' +
        '<strong>' + escapeText(item.title) + '</strong>';
      link.addEventListener('click', function () {
        closeSearch();
      });
      searchResults.appendChild(link);
    });
    if (query) {
      var first = searchResults.querySelector('.search-result');
      if (first) setActiveResult(0);
    }
  }

  function setActiveResult(index) {
    var links = Array.prototype.slice.call(searchResults.querySelectorAll('.search-result'));
    if (!links.length) return;
    if (index < 0) index = 0;
    if (index >= links.length) index = links.length - 1;
    links.forEach(function (link) { link.classList.remove('is-active'); });
    links[index].classList.add('is-active');
    links[index].scrollIntoView({ block: 'nearest' });
    activeResult = index;
  }

  function runSearch(query) {
    var q = query.trim().toLowerCase();
    if (!q) {
      renderResults(INDEX.slice(0, 8), '');
      return;
    }
    var terms = q.split(/\s+/).filter(Boolean);
    var results = INDEX.filter(function (item) {
      var haystack = [item.title, item.group, item.pageTitle, item.keywords].join(' ').toLowerCase();
      return terms.every(function (term) { return haystack.indexOf(term) !== -1; });
    });
    renderResults(results, q);
  }

  function openSearch() {
    if (!searchModal || !searchInput) return;
    lastFocus = document.activeElement;
    searchModal.hidden = false;
    runSearch('');
    searchInput.value = '';
    searchInput.focus();
    body.style.overflow = 'hidden';
  }

  function closeSearch() {
    if (!searchModal || searchModal.hidden) return;
    searchModal.hidden = true;
    body.style.overflow = '';
    if (lastFocus && typeof lastFocus.focus === 'function') lastFocus.focus();
  }

  if (searchTrigger) {
    searchTrigger.addEventListener('click', openSearch);
  }

  document.querySelectorAll('[data-close-search]').forEach(function (element) {
    element.addEventListener('click', closeSearch);
  });

  if (searchInput) {
    searchInput.addEventListener('input', function () {
      runSearch(searchInput.value);
    });
    searchInput.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        setActiveResult(activeResult + 1);
      } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        setActiveResult(activeResult - 1);
      } else if (event.key === 'Enter') {
        event.preventDefault();
        var link = searchResults.querySelectorAll('.search-result')[activeResult];
        if (link) link.click();
      }
    });
  }

  document.addEventListener('keydown', function (event) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      openSearch();
    }
  });
})();
