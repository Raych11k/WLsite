/* =========================================================
   WhiteLight — общее ядро сайта
   Данные, хранилище, тема, шапка, поиск, лайки, тосты
   ========================================================= */
(function () {
    'use strict';

    const REPO_NAME = 'Raych11k/WLsite';
    const RAW = `https://raw.githubusercontent.com/${REPO_NAME}/main/`;
    const API = `https://api.github.com/repos/${REPO_NAME}/contents/`;
    const COUNTER_NS = 'whitelight-site.github.io';
    const LIBRARY_CACHE_KEY = 'wl_library_cache';
    const LIBRARY_FRESH_MS = 3 * 60 * 1000;

    /* ---------- Утилиты ---------- */

    const esc = (value) => String(value ?? '')
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

    const raw = (path) => path ? RAW + String(path).replace(/^\/+/, '') : '';

    function plural(n, forms) {
        const mod10 = n % 10;
        const mod100 = n % 100;
        if (mod100 >= 11 && mod100 <= 19) return forms[2];
        if (mod10 === 1) return forms[0];
        if (mod10 >= 2 && mod10 <= 4) return forms[1];
        return forms[2];
    }
    const pluralize = (n, forms) => `${n} ${plural(n, forms)}`;
    const CHAPTER_FORMS = ['глава', 'главы', 'глав'];
    const PAGE_FORMS = ['страница', 'страницы', 'страниц'];
    const TITLE_FORMS = ['тайтл', 'тайтла', 'тайтлов'];
    const LIKE_FORMS = ['лайк', 'лайка', 'лайков'];

    function relTime(iso) {
        if (!iso) return '';
        const date = new Date(iso);
        if (isNaN(date)) return '';
        const diff = Date.now() - date.getTime();
        const min = 60 * 1000, hour = 60 * min, day = 24 * hour;
        if (diff < min) return 'только что';
        if (diff < hour) { const m = Math.floor(diff / min); return `${m} ${plural(m, ['минуту', 'минуты', 'минут'])} назад`; }
        if (diff < day) { const h = Math.floor(diff / hour); return `${h} ${plural(h, ['час', 'часа', 'часов'])} назад`; }
        const d = Math.floor(diff / day);
        if (d === 1) return 'вчера';
        if (d < 7) return `${d} ${plural(d, ['день', 'дня', 'дней'])} назад`;
        if (d < 31) { const w = Math.floor(d / 7); return `${w} ${plural(w, ['неделю', 'недели', 'недель'])} назад`; }
        return date.toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', year: 'numeric' });
    }

    const fmtDate = (iso) => {
        if (!iso) return '';
        const d = new Date(iso);
        return isNaN(d) ? '' : d.toLocaleDateString('ru-RU');
    };

    const isFresh = (iso, days = 7) => {
        if (!iso) return false;
        const t = new Date(iso).getTime();
        return !isNaN(t) && Date.now() - t < days * 86400000;
    };

    function hashHue(str) {
        let h = 0;
        for (const ch of String(str)) h = (h * 31 + ch.codePointAt(0)) >>> 0;
        return h % 360;
    }

    const debounce = (fn, ms) => {
        let t;
        return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
    };

    /* ---------- Хранилище ---------- */

    const store = {
        get(key, fallback) {
            try {
                const value = localStorage.getItem(key);
                return value === null ? fallback : JSON.parse(value);
            } catch (e) { return fallback; }
        },
        set(key, value) {
            try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) { /* хранилище недоступно */ }
        },
        rawGet(key) { try { return localStorage.getItem(key); } catch (e) { return null; } },
        rawSet(key, value) { try { localStorage.setItem(key, value); } catch (e) { /* хранилище недоступно */ } },
        remove(key) { try { localStorage.removeItem(key); } catch (e) { /* хранилище недоступно */ } }
    };

    /* Прочитанные главы: тот же формат, что и раньше — массив "titleId_chapterId" */
    const read = {
        list: () => store.get('wl_read_chapters', []),
        key: (titleId, chapterId) => `${titleId}_${chapterId}`,
        has(titleId, chapterId) { return this.list().includes(this.key(titleId, chapterId)); },
        mark(titleId, chapterId) {
            const list = this.list();
            const key = this.key(titleId, chapterId);
            if (!list.includes(key)) { list.push(key); store.set('wl_read_chapters', list); }
        },
        unmark(titleId, chapterId) {
            const key = this.key(titleId, chapterId);
            store.set('wl_read_chapters', this.list().filter(k => k !== key));
        },
        countFor(titleId, chapters) {
            const list = this.list();
            return chapters.filter(ch => list.includes(this.key(titleId, ch.id))).length;
        }
    };

    /* Закладки (полка) */
    const bookmarks = {
        list: () => store.get('wl_bookmarks', []),
        has(id) { return this.list().includes(id); },
        toggle(id) {
            const list = this.list();
            const idx = list.indexOf(id);
            if (idx === -1) list.unshift(id); else list.splice(idx, 1);
            store.set('wl_bookmarks', list);
            document.dispatchEvent(new CustomEvent('wl:bookmarks'));
            return idx === -1;
        }
    };

    /* Прогресс чтения: { [titleId]: { chapterId, page, total, volume, number, name, cover, updatedAt } } */
    const progress = {
        all: () => store.get('wl_progress', {}),
        get(titleId) { return this.all()[titleId] || null; },
        set(titleId, data) {
            const all = this.all();
            all[titleId] = { ...(all[titleId] || {}), ...data, updatedAt: new Date().toISOString() };
            store.set('wl_progress', all);
        },
        remove(titleId) {
            const all = this.all();
            delete all[titleId];
            store.set('wl_progress', all);
        }
    };

    /* ---------- Данные ---------- */

    const chapterNum = (ch) => {
        const n = parseFloat(ch.number);
        return isNaN(n) ? Infinity : n;
    };

    // Тот же порядок, что формирует админка: по тому, затем по номеру главы
    function sortChapters(chapters) {
        return [...(chapters || [])].sort((a, b) =>
            (Number(a.volume) || 0) - (Number(b.volume) || 0) ||
            chapterNum(a) - chapterNum(b) ||
            String(a.number).localeCompare(String(b.number), 'ru', { numeric: true }));
    }

    const chapterLabel = (ch, withVolume = true) =>
        withVolume ? `Том ${ch.volume || 1} · Глава ${ch.number}` : `Глава ${ch.number}`;

    async function fetchJSON(url, options) {
        const res = await fetch(url, options);
        if (!res.ok) {
            const err = new Error(`HTTP ${res.status}`);
            err.status = res.status;
            throw err;
        }
        return res.json();
    }

    async function loadTitle(titleId) {
        const base = `${RAW}titles/${encodeURIComponent(titleId)}/`;
        const [dataRes, chapRes] = await Promise.allSettled([
            fetchJSON(base + 'data.json', { cache: 'no-cache' }),
            fetchJSON(base + 'chapters.json', { cache: 'no-cache' })
        ]);
        if (dataRes.status !== 'fulfilled') throw dataRes.reason;
        const chapters = chapRes.status === 'fulfilled' && Array.isArray(chapRes.value) ? chapRes.value : [];
        return { data: dataRes.value, chapters: sortChapters(chapters) };
    }

    const stripPages = (chapters) => chapters.map(({ pages, ...rest }) => ({
        ...rest,
        pagesCount: rest.pagesCount || (pages ? pages.length : 0)
    }));

    function readLibraryCache() {
        const cache = store.get(LIBRARY_CACHE_KEY, null);
        return cache && Array.isArray(cache.items) ? cache : null;
    }

    let libraryPromise = null;

    /**
     * Загружает все тайтлы со списками глав.
     * Свежий кэш отдаётся сразу; при сбое GitHub API (например, лимит запросов)
     * используется последний удачный снимок библиотеки.
     */
    function loadLibrary({ force = false } = {}) {
        if (libraryPromise && !force) return libraryPromise;

        libraryPromise = (async () => {
            const cache = readLibraryCache();
            if (!force && cache && Date.now() - cache.time < LIBRARY_FRESH_MS) {
                return { items: cache.items, fromCache: true };
            }
            try {
                const listing = await fetchJSON(`${API}titles`);
                const folders = listing.filter(item => item.type === 'dir').map(item => item.name);

                const loaded = await Promise.all(folders.map(async (folder) => {
                    try {
                        const { data, chapters } = await loadTitle(folder);
                        return { ...data, id: data.id || folder, chapters: stripPages(chapters) };
                    } catch (e) {
                        console.error(`Ошибка загрузки данных ${folder}:`, e);
                        return null;
                    }
                }));

                const items = loaded.filter(Boolean);
                store.set(LIBRARY_CACHE_KEY, { time: Date.now(), items });
                return { items, fromCache: false };
            } catch (err) {
                console.error('Не удалось загрузить библиотеку:', err);
                if (cache) return { items: cache.items, fromCache: true, stale: true };
                libraryPromise = null;
                throw err;
            }
        })();

        return libraryPromise;
    }

    const lastChapterDate = (title) => (title.chapters || [])
        .reduce((max, ch) => (ch.createdAt && ch.createdAt > max ? ch.createdAt : max), '');

    const titleActivity = (title) => lastChapterDate(title) || title.updatedAt || title.createdAt || '';

    /** Куда вести читателя: продолжение, следующая глава или первая глава */
    function resumeTarget(titleId, chapters) {
        const sorted = sortChapters(chapters);
        if (!sorted.length) return null;
        const p = progress.get(titleId);
        if (p) {
            const idx = sorted.findIndex(c => c.id === p.chapterId);
            if (idx !== -1) {
                const finished = p.total && p.page >= p.total - 1;
                if (!finished) {
                    return { kind: 'continue', chapter: sorted[idx], page: p.page || 0, total: p.total || 0 };
                }
                if (idx < sorted.length - 1) {
                    return { kind: 'next', chapter: sorted[idx + 1], page: 0 };
                }
                return { kind: 'done', chapter: sorted[idx], page: 0 };
            }
        }
        const firstUnread = sorted.find(c => !read.has(titleId, c.id));
        if (firstUnread && firstUnread !== sorted[0]) return { kind: 'next', chapter: firstUnread, page: 0 };
        if (!firstUnread) return { kind: 'done', chapter: sorted[sorted.length - 1], page: 0 };
        return { kind: 'start', chapter: sorted[0], page: 0 };
    }

    const readerUrl = (titleId, chapterId, page) =>
        `reader.html?title=${encodeURIComponent(titleId)}&chapter=${encodeURIComponent(chapterId)}${page ? `&page=${page + 1}` : ''}`;
    const titleUrl = (titleId) => `title.html?id=${encodeURIComponent(titleId)}`;

    const STATUS_CLASS = {
        'онгоинг': 'ongoing',
        'завершён': 'completed',
        'завершен': 'completed',
        'отложен': 'onhold',
        'брошен': 'dropped'
    };
    const statusClass = (status) => STATUS_CLASS[String(status || 'Онгоинг').toLowerCase()] || 'ongoing';

    /* ---------- Иконки ---------- */

    const ICONS = {
        search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
        sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
        moon: '<path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11z"/>',
        heart: '<path d="M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z"/>',
        bookmark: '<path d="M19 21l-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/>',
        arrowLeft: '<path d="M19 12H5M12 19l-7-7 7-7"/>',
        arrowRight: '<path d="M5 12h14M12 5l7 7-7 7"/>',
        arrowUp: '<path d="M12 19V5M5 12l7-7 7 7"/>',
        chevLeft: '<path d="m15 18-6-6 6-6"/>',
        chevRight: '<path d="m9 18 6-6-6-6"/>',
        chevDown: '<path d="m6 9 6 6 6-6"/>',
        sliders: '<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/>',
        x: '<path d="M18 6 6 18M6 6l12 12"/>',
        book: '<path d="M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2zM22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z"/>',
        share: '<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.6 13.5 6.8 4M15.4 6.5l-6.8 4"/>',
        check: '<path d="M20 6 9 17l-5-5"/>',
        maximize: '<path d="M8 3H5a2 2 0 0 0-2 2v3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M16 21h3a2 2 0 0 0 2-2v-3"/>',
        minimize: '<path d="M8 3v3a2 2 0 0 1-2 2H3M21 8h-3a2 2 0 0 1-2-2V3M3 16h3a2 2 0 0 1 2 2v3M16 21v-3a2 2 0 0 1 2-2h3"/>',
        home: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
        grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
        info: '<circle cx="12" cy="12" r="9.5"/><path d="M12 16v-4M12 8h.01"/>',
        clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
        list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
        sort: '<path d="m3 16 4 4 4-4M7 20V4M21 8l-4-4-4 4M17 4v16"/>',
        play: '<path d="M7 4.5v15l12-7.5z"/>',
        star: '<path d="M12 2.5l2.9 6 6.6.9-4.8 4.6 1.2 6.5L12 17.4l-5.9 3.1 1.2-6.5L2.5 9.4l6.6-.9z"/>',
        flame: '<path d="M12 22c4 0 7-2.8 7-7 0-4-3-6.5-4-10-2 1.5-3 3.5-3 5.5-1-.5-2-2-2-3.5C7.5 9 5 11.5 5 15c0 4.2 3 7 7 7z"/>',
        ghost: '<path d="M9 10h.01M15 10h.01M12 2a8 8 0 0 0-8 8v12l3-3 2.5 3 2.5-3 2.5 3 2.5-3 3 3V10a8 8 0 0 0-8-8z"/>',
        send: '<path d="m22 2-7 20-4-9-9-4zM22 2 11 13"/>',
        external: '<path d="M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
        eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
        rows: '<rect x="5" y="2.5" width="14" height="8.5" rx="1.5"/><rect x="5" y="13" width="14" height="8.5" rx="1.5"/>',
        columns: '<rect x="2.5" y="5" width="8.5" height="14" rx="1.5"/><rect x="13" y="5" width="8.5" height="14" rx="1.5"/>',
        shuffle: '<path d="M16 3h5v5M4 20 21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/>',
        help: '<circle cx="12" cy="12" r="9.5"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"/>',
        users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/>',
        refresh: '<path d="M3 12a9 9 0 0 1 15.5-6.3L21 8M21 3v5h-5M21 12a9 9 0 0 1-15.5 6.3L3 16M3 21v-5h5"/>',
        keyboard: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M6 9h.01M10 9h.01M14 9h.01M18 9h.01M6 13h.01M18 13h.01M8 16h8M10 13h4"/>'
    };

    const icon = (name, cls = '') =>
        `<svg class="ico ${cls}" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;

    /* ---------- Обложки ---------- */

    function coverHTML(title, { cls = '', eager = false } = {}) {
        const name = title.name || title.mangaName || '?';
        const hue = hashHue(name);
        const initial = esc(name.trim().charAt(0).toUpperCase());
        const src = raw(title.cover);
        return `<div class="cover ${cls}" style="--hue:${hue}">
            <span class="cover-fallback" aria-hidden="true">${initial}</span>
            ${src ? `<img src="${esc(src)}" alt="" ${eager ? 'fetchpriority="high"' : 'loading="lazy"'} decoding="async" onload="this.classList.add('is-loaded')" onerror="this.remove()">` : ''}
        </div>`;
    }

    /* ---------- Действие «читать» для тайтла ---------- */

    function resumeAction(titleId, chapters) {
        const target = resumeTarget(titleId, chapters);
        if (!target) return null;
        const ch = target.chapter;
        const map = {
            start: { label: 'Начать читать', short: 'Читать' },
            continue: { label: `Продолжить · Глава ${ch.number}`, short: `Гл. ${ch.number}` },
            next: { label: `Читать главу ${ch.number}`, short: `Гл. ${ch.number}` },
            done: { label: 'Перечитать последнюю', short: 'Перечитать' }
        };
        return { ...target, ...map[target.kind], href: readerUrl(titleId, ch.id, target.kind === 'continue' ? target.page : 0) };
    }

    /* ---------- Карточка тайтла ---------- */

    function bookmarkButton(id, cls = 'bm-btn') {
        const on = bookmarks.has(id);
        return `<button type="button" class="${cls} ${on ? 'is-on' : ''}" data-bm="${esc(id)}" aria-pressed="${on}" aria-label="${on ? 'Убрать с полки' : 'Добавить на полку'}" title="${on ? 'Убрать с полки' : 'Добавить на полку'}">${icon('bookmark')}</button>`;
    }

    function titleCardHTML(title, { reveal = true, eager = false } = {}) {
        const chapters = title.chapters || [];
        const readCount = read.countFor(title.id, chapters);
        const last = lastChapterDate(title);
        const fresh = isFresh(last);
        const pct = chapters.length ? Math.round((readCount / chapters.length) * 100) : 0;
        const unread = chapters.length - readCount;
        const sub = [(title.genres || [])[0], title.year].filter(Boolean).join(' · ');
        return `<article class="tcard" ${reveal ? 'data-reveal' : ''}>
            <a class="tcard-link" href="${titleUrl(title.id)}">
                <div class="tcard-cover">
                    ${coverHTML(title, { eager })}
                    <span class="tcard-shade"></span>
                    <span class="tcard-top">
                        ${fresh ? '<span class="pill pill-new">Новое</span>' : ''}
                        ${readCount > 0 && unread > 0 ? `<span class="pill">+${unread} ${plural(unread, ['новая', 'новых', 'новых'])}</span>` : ''}
                    </span>
                    <span class="tcard-cta"><span>${icon('book')}Открыть</span></span>
                    <span class="tcard-bottom">
                        <span class="status-dot s-${statusClass(title.status)}">${esc(title.status || 'Онгоинг')} · ${pluralize(chapters.length, CHAPTER_FORMS)}</span>
                        ${readCount > 0 ? `<span class="progress-line" title="Прочитано ${readCount} из ${chapters.length}"><i style="--p:${pct}%"></i></span>` : ''}
                    </span>
                </div>
                <h3 class="tcard-name">${esc(title.name)}</h3>
            </a>
            ${sub ? `<p class="tcard-sub">${esc(sub)}</p>` : ''}
            ${bookmarkButton(title.id)}
        </article>`;
    }

    // Делегированный обработчик кнопок «на полку» на любой странице
    document.addEventListener('click', (e) => {
        const btn = e.target.closest('[data-bm]');
        if (!btn) return;
        e.preventDefault();
        e.stopPropagation();
        const id = btn.dataset.bm;
        const on = bookmarks.toggle(id);
        syncBookmarkButtons(id, on);
        toast(on ? 'Добавлено на полку' : 'Убрано с полки', {
            action: 'Отменить',
            onAction: () => syncBookmarkButtons(id, bookmarks.toggle(id))
        });
    });

    function syncBookmarkButtons(id, on) {
        document.querySelectorAll(`[data-bm="${CSS.escape(id)}"]`).forEach(el => {
            el.classList.toggle('is-on', on);
            el.setAttribute('aria-pressed', on);
            const label = on ? 'Убрать с полки' : 'Добавить на полку';
            el.setAttribute('aria-label', label);
            el.title = label;
            const text = el.querySelector('.btn-label');
            if (text) text.textContent = on ? 'На полке' : 'На полку';
        });
    }

    /* ---------- Тема ---------- */

    const theme = {
        current: () => document.documentElement.dataset.theme === 'light' ? 'light' : 'dark',
        set(value) {
            document.documentElement.dataset.theme = value;
            store.rawSet('wl_theme', value);
            document.querySelectorAll('[data-theme-toggle]').forEach(updateThemeButton);
            const meta = document.querySelector('meta[name="theme-color"]');
            if (meta) meta.content = value === 'light' ? '#f4efe6' : '#09090d';
        },
        toggle() { this.set(this.current() === 'light' ? 'dark' : 'light'); }
    };

    function updateThemeButton(btn) {
        const isLight = theme.current() === 'light';
        btn.innerHTML = icon(isLight ? 'moon' : 'sun');
        btn.title = isLight ? 'Тёмная тема' : 'Светлая тема';
        btn.setAttribute('aria-label', btn.title);
    }

    /* ---------- Тосты ---------- */

    let toastBox = null;
    function toast(message, { action, onAction, timeout = 3200 } = {}) {
        if (!toastBox) {
            toastBox = document.createElement('div');
            toastBox.className = 'toasts';
            toastBox.setAttribute('role', 'status');
            toastBox.setAttribute('aria-live', 'polite');
            document.body.appendChild(toastBox);
        }
        const el = document.createElement('div');
        el.className = 'toast';
        el.innerHTML = `<span>${esc(message)}</span>${action ? `<button type="button">${esc(action)}</button>` : ''}`;
        const close = () => { el.classList.add('is-leaving'); setTimeout(() => el.remove(), 300); };
        if (action) el.querySelector('button').addEventListener('click', () => { onAction && onAction(); close(); });
        toastBox.appendChild(el);
        setTimeout(close, timeout);
        return close;
    }

    /* ---------- Лайки сайта (тот же счётчик, что и раньше) ---------- */

    const LIKE_KEY = 'site_total_likes';
    let likeCount = null;

    function renderLikes() {
        document.querySelectorAll('[data-like]').forEach(btn => {
            const liked = store.rawGet('wl_site_liked') === 'true';
            btn.classList.toggle('is-liked', liked);
            btn.setAttribute('aria-pressed', liked ? 'true' : 'false');
            const label = btn.querySelector('[data-like-count]');
            if (label) label.textContent = likeCount === null ? '—' : (btn.dataset.like === 'full' ? pluralize(likeCount, LIKE_FORMS) : likeCount);
            btn.title = liked ? 'Спасибо за поддержку!' : 'Поддержать проект лайком';
        });
    }

    async function initLikes() {
        const buttons = document.querySelectorAll('[data-like]');
        if (!buttons.length) return;
        renderLikes();
        buttons.forEach(btn => btn.addEventListener('click', async () => {
            if (store.rawGet('wl_site_liked') === 'true') {
                btn.classList.remove('pop'); void btn.offsetWidth; btn.classList.add('pop');
                return;
            }
            store.rawSet('wl_site_liked', 'true');
            likeCount = (likeCount || 0) + 1;
            renderLikes();
            btn.classList.add('pop');
            burst(btn);
            toast('Спасибо! Лайк засчитан ♥');
            try {
                await fetch(`https://abacus.jasoncameron.dev/hit/${COUNTER_NS}/${LIKE_KEY}`);
            } catch (e) {
                console.error('Ошибка отправки лайка:', e);
            }
        }));
        try {
            const data = await fetchJSON(`https://abacus.jasoncameron.dev/get/${COUNTER_NS}/${LIKE_KEY}`);
            likeCount = data.value || 0;
            renderLikes();
        } catch (e) {
            console.error('Ошибка получения лайков:', e);
        }
    }

    function burst(anchor) {
        if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
        const rect = anchor.getBoundingClientRect();
        for (let i = 0; i < 10; i++) {
            const s = document.createElement('span');
            s.className = 'burst';
            const angle = (Math.PI * 2 * i) / 10;
            s.style.left = `${rect.left + rect.width / 2}px`;
            s.style.top = `${rect.top + rect.height / 2}px`;
            s.style.setProperty('--dx', `${Math.cos(angle) * 46}px`);
            s.style.setProperty('--dy', `${Math.sin(angle) * 46}px`);
            document.body.appendChild(s);
            setTimeout(() => s.remove(), 700);
        }
    }

    /* ---------- Шапка, нижняя навигация, подвал ---------- */

    const NAV = [
        { id: 'home', href: 'main.html', label: 'Главная', icon: 'home' },
        { id: 'catalog', href: 'main.html#catalog', label: 'Каталог', icon: 'grid' },
        { id: 'shelf', href: 'main.html#shelf', label: 'Полка', icon: 'bookmark' },
        { id: 'faq', href: 'faq.html', label: 'FAQ', icon: 'help' },
        { id: 'socials', href: 'socials.html', label: 'Соц.сети', icon: 'send' }
    ];

    function renderChrome(active) {
        const isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
        const header = document.getElementById('site-header');
        if (header) {
            header.className = 'site-header';
            header.innerHTML = `
                <div class="site-header-inner">
                    <a class="brand" href="main.html" aria-label="WhiteLight — на главную">
                        <img src="data/team-logo.png" alt="" width="44" height="44">
                        <span class="brand-name">White<b>Light</b></span>
                    </a>
                    <nav class="nav" aria-label="Основная навигация">
                        ${NAV.map(item => `<a href="${item.href}" class="nav-link ${item.id === active ? 'is-active' : ''}" ${item.id === active ? 'aria-current="page"' : ''}>${item.label}</a>`).join('')}
                    </nav>
                    <div class="header-actions">
                        <button type="button" class="search-trigger" data-search-open aria-label="Поиск по тайтлам">
                            ${icon('search')}<span class="search-trigger-text">Поиск тайтлов</span><kbd>${isMac ? '⌘' : 'Ctrl'} K</kbd>
                        </button>
                        <button type="button" class="icon-btn like-chip" data-like="short" aria-pressed="false">
                            ${icon('heart')}<span data-like-count>—</span>
                        </button>
                        <button type="button" class="icon-btn" data-theme-toggle></button>
                    </div>
                </div>`;
        }

        const tabbar = document.createElement('nav');
        tabbar.className = 'tabbar';
        tabbar.setAttribute('aria-label', 'Быстрая навигация');
        const tabs = [NAV[0], NAV[1], { id: 'search', label: 'Поиск', icon: 'search' }, NAV[2], NAV[3]];
        tabbar.innerHTML = tabs.map(t => t.id === 'search'
            ? `<button type="button" class="tab" data-search-open>${icon(t.icon)}<span>${t.label}</span></button>`
            : `<a class="tab ${t.id === active ? 'is-active' : ''}" href="${t.href}">${icon(t.icon)}<span>${t.label}</span></a>`).join('');
        document.body.appendChild(tabbar);

        const footer = document.getElementById('site-footer');
        if (footer) {
            footer.className = 'site-footer';
            footer.innerHTML = `
                <div class="footer-glow" aria-hidden="true"></div>
                <div class="footer-inner">
                    <div class="footer-brand">
                        <img src="data/team-logo.png" alt="" width="72" height="72">
                        <div>
                            <p class="footer-title">WhiteLight</p>
                            <p class="footer-sub">Переводы манги без рекламы, СМС и регистрации.</p>
                        </div>
                    </div>
                    <nav class="footer-nav" aria-label="Ссылки подвала">
                        <a href="faq.html#about">О нас</a>
                        <a href="socials.html">Соц.сети</a>
                        <a href="faq.html">FAQ</a>
                        <a href="main.html#catalog">Каталог</a>
                    </nav>
                    <div class="footer-copyright">&copy; 2026 WhiteLight. Все права защищены.</div>
                </div>`;
        }

        document.querySelectorAll('[data-theme-toggle]').forEach(btn => {
            updateThemeButton(btn);
            btn.addEventListener('click', () => theme.toggle());
        });

        document.querySelectorAll('[data-search-open]').forEach(btn =>
            btn.addEventListener('click', () => search.open()));

        // Шапка становится плотнее при прокрутке
        if (header) {
            const onScroll = () => header.classList.toggle('is-scrolled', window.scrollY > 12);
            onScroll();
            window.addEventListener('scroll', onScroll, { passive: true });
        }

        initLikes();
    }

    /* ---------- Поиск (палитра команд) ---------- */

    const search = (() => {
        let root, input, results, items = [], active = 0, library = null;

        const normalize = (s) => String(s || '').toLowerCase().replace(/ё/g, 'е');

        function build() {
            root = document.createElement('div');
            root.className = 'palette';
            root.hidden = true;
            root.innerHTML = `
                <div class="palette-backdrop" data-close></div>
                <div class="palette-box" role="dialog" aria-modal="true" aria-label="Поиск тайтлов">
                    <div class="palette-field">
                        ${icon('search')}
                        <input type="search" placeholder="Название, оригинал или жанр…" autocomplete="off" spellcheck="false" aria-label="Поиск">
                        <button type="button" class="palette-esc" data-close>Esc</button>
                    </div>
                    <div class="palette-results" role="listbox"></div>
                    <div class="palette-foot"><span><kbd>↑</kbd><kbd>↓</kbd> выбор</span><span><kbd>Enter</kbd> открыть</span><span><kbd>Esc</kbd> закрыть</span></div>
                </div>`;
            document.body.appendChild(root);
            input = root.querySelector('input');
            results = root.querySelector('.palette-results');
            root.querySelectorAll('[data-close]').forEach(el => el.addEventListener('click', close));
            input.addEventListener('input', render);
            input.addEventListener('keydown', (e) => {
                if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
                else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
                else if (e.key === 'Enter') {
                    e.preventDefault();
                    const target = items[active];
                    if (target) window.location.href = target.href;
                }
            });
        }

        function move(delta) {
            if (!items.length) return;
            active = (active + delta + items.length) % items.length;
            highlight();
        }

        function highlight() {
            results.querySelectorAll('.palette-item').forEach((el, i) => {
                el.classList.toggle('is-active', i === active);
                el.setAttribute('aria-selected', i === active ? 'true' : 'false');
                if (i === active) el.scrollIntoView({ block: 'nearest' });
            });
        }

        function render() {
            if (!library) {
                results.innerHTML = `<div class="palette-empty"><span class="spinner"></span>Загружаем библиотеку…</div>`;
                return;
            }
            const q = normalize(input.value.trim());
            const matched = library.filter(t => !q ||
                normalize(t.name).includes(q) ||
                normalize(t.origName).includes(q) ||
                (t.genres || []).some(g => normalize(g).includes(q)));

            items = matched.map(t => ({ href: titleUrl(t.id), title: t }));
            active = 0;

            if (!items.length) {
                results.innerHTML = `<div class="palette-empty">Ничего не нашлось по запросу «${esc(input.value)}»</div>`;
                return;
            }

            results.innerHTML = items.map(({ href, title }) => {
                const count = (title.chapters || []).length;
                return `<a class="palette-item" role="option" href="${href}">
                    ${coverHTML(title, { cls: 'palette-cover' })}
                    <span class="palette-text">
                        <span class="palette-name">${esc(title.name)}</span>
                        <span class="palette-meta">${esc(title.origName || '')}</span>
                        <span class="palette-tags">${(title.genres || []).slice(0, 3).map(g => `<i>${esc(g)}</i>`).join('')}</span>
                    </span>
                    <span class="palette-side">
                        <span class="status-dot s-${statusClass(title.status)}">${esc(title.status || 'Онгоинг')}</span>
                        <span>${pluralize(count, CHAPTER_FORMS)}</span>
                    </span>
                </a>`;
            }).join('');
            results.querySelectorAll('.palette-item').forEach((el, i) =>
                el.addEventListener('mousemove', () => { if (active !== i) { active = i; highlight(); } }));
            highlight();
        }

        async function open(prefill = '') {
            if (!root) build();
            root.hidden = false;
            document.documentElement.classList.add('no-scroll');
            requestAnimationFrame(() => root.classList.add('is-open'));
            input.value = prefill;
            input.focus();
            render();
            if (!library) {
                try {
                    const { items: lib } = await loadLibrary();
                    library = [...lib].sort((a, b) => a.name.localeCompare(b.name, 'ru'));
                } catch (e) {
                    results.innerHTML = `<div class="palette-empty">Не удалось загрузить список тайтлов. Попробуйте позже.</div>`;
                    return;
                }
                render();
            }
        }

        function close() {
            if (!root || root.hidden) return;
            root.classList.remove('is-open');
            document.documentElement.classList.remove('no-scroll');
            setTimeout(() => { root.hidden = true; }, 180);
        }

        document.addEventListener('keydown', (e) => {
            const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName) || document.activeElement?.isContentEditable;
            if ((e.key === 'k' || e.key === 'K' || e.code === 'KeyK') && (e.metaKey || e.ctrlKey)) {
                e.preventDefault();
                root && !root.hidden ? close() : open();
            } else if (e.key === '/' && !typing && !document.body.dataset.noSearchHotkey) {
                e.preventDefault();
                open();
            } else if (e.key === 'Escape' && root && !root.hidden) {
                close();
            }
        });

        return { open, close };
    })();

    /* ---------- Появление при прокрутке ---------- */

    const revealObserver = 'IntersectionObserver' in window
        ? new IntersectionObserver((entries) => entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('is-visible');
                revealObserver.unobserve(entry.target);
            }
        }), { rootMargin: '0px 0px -8% 0px' })
        : null;

    function reveal(root = document) {
        root.querySelectorAll('[data-reveal]:not(.is-visible)').forEach((el, i) => {
            el.style.setProperty('--d', `${Math.min(i, 12) * 40}ms`);
            if (revealObserver) revealObserver.observe(el); else el.classList.add('is-visible');
        });
    }

    /* ---------- Поделиться ---------- */

    async function share({ title, text, url = location.href }) {
        if (navigator.share) {
            try { await navigator.share({ title, text, url }); return; } catch (e) { if (e.name === 'AbortError') return; }
        }
        try {
            await navigator.clipboard.writeText(url);
            toast('Ссылка скопирована');
        } catch (e) {
            prompt('Скопируйте ссылку:', url);
        }
    }

    window.WL = {
        REPO_NAME, RAW, COUNTER_NS,
        esc, raw, plural, pluralize, relTime, fmtDate, isFresh, debounce, hashHue,
        CHAPTER_FORMS, PAGE_FORMS, TITLE_FORMS,
        store, read, bookmarks, progress,
        sortChapters, chapterLabel, fetchJSON, loadTitle, loadLibrary, readLibraryCache,
        lastChapterDate, titleActivity, resumeTarget, resumeAction, readerUrl, titleUrl, statusClass,
        icon, coverHTML, titleCardHTML, bookmarkButton, theme, toast, renderChrome, search, reveal, share, burst
    };
})();
