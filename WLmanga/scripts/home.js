/* =========================================================
   WhiteLight — главная страница
   ========================================================= */
(function () {
    'use strict';

    const {
        esc, raw, icon, coverHTML, titleCardHTML, bookmarkButton, pluralize, plural, relTime, isFresh,
        CHAPTER_FORMS, PAGE_FORMS, TITLE_FORMS, read, bookmarks, progress, statusClass,
        loadLibrary, lastChapterDate, titleActivity, resumeTarget, resumeAction, readerUrl, titleUrl,
        sortChapters, fetchJSON, reveal, toast, RAW
    } = WL;

    WL.renderChrome('home');

    const $ = (id) => document.getElementById(id);
    const params = new URLSearchParams(location.search);

    const state = {
        library: [],
        query: params.get('q') || '',
        status: params.get('status') || 'all',
        genre: params.get('genre') || '',
        sort: params.get('sort') || 'alpha',
        recentLimit: 6
    };

    const isDropped = (t) => statusClass(t.status) === 'dropped';

    /* ---------- Бегущая строка (тексты прежнего тикера) ---------- */

    const SLOGANS = ['WhiteLight', 'Библиотека всех переводов', 'Читайте без СМС и регистрации', 'Никакой рекламы', 'Открытие сайта'];
    const marqueeHTML = SLOGANS.map(s => `<span class="marquee-item">${icon('star')}${esc(s)}</span>`).join('');
    $('marquee-group').innerHTML = marqueeHTML + marqueeHTML;
    $('marquee-group').insertAdjacentHTML('afterend', `<div class="marquee-group">${marqueeHTML + marqueeHTML}</div>`);

    /* ---------- Герой-карусель ---------- */

    const hero = {
        el: $('hero'),
        index: 0,
        timer: null,
        delay: 7000,
        slides: [],
        paused: false,

        render(items) {
            this.slides = items;
            $('hero-skeleton')?.remove();
            if (!items.length) {
                this.el.hidden = true;
                return;
            }

            $('hero-backdrops').innerHTML = items.map(({ title }) =>
                `<div class="hero-backdrop" style="background-image:url('${esc(raw(title.cover))}')"></div>`).join('');

            const slidesHTML = items.map(({ title, badge, note }, i) => {
                const action = resumeAction(title.id, title.chapters || []);
                const count = (title.chapters || []).length;
                return `<article class="hero-slide" aria-roledescription="слайд" aria-label="${i + 1} из ${items.length}: ${esc(title.name)}" ${i ? 'aria-hidden="true"' : ''}>
                    <div class="hero-text">
                        <div class="hero-badge-row">
                            <span class="pill pill-gold">${icon('star')} ${esc(badge)}</span>
                            ${note ? `<span class="pill">${esc(note)}</span>` : ''}
                        </div>
                        ${title.origName ? `<p class="hero-orig">${esc(title.origName)}</p>` : ''}
                        <h2 class="hero-title"><a href="${titleUrl(title.id)}">${esc(title.name)}</a></h2>
                        <div class="hero-meta">
                            <span>${esc(title.type || 'Манга')}</span>
                            ${title.year ? `<span>${esc(title.year)}</span>` : ''}
                            <span><span class="status-dot s-${statusClass(title.status)}">${esc(title.status || 'Онгоинг')}</span></span>
                            <span>${pluralize(count, CHAPTER_FORMS)}</span>
                        </div>
                        ${title.description ? `<p class="hero-desc">${esc(title.description)}</p>` : ''}
                        <div class="hero-actions">
                            ${action ? `<a class="btn btn-gold" href="${action.href}">${icon('play')}${esc(action.label)}</a>` : ''}
                            <a class="btn btn-ghost" href="${titleUrl(title.id)}">Подробнее</a>
                            ${bookmarkButton(title.id, 'btn btn-ghost')}
                        </div>
                    </div>
                    <a class="hero-art" href="${titleUrl(title.id)}" tabindex="-1" aria-hidden="true">
                        ${coverHTML(title, { eager: i === 0 })}
                    </a>
                </article>`;
            }).join('');

            this.el.insertAdjacentHTML('beforeend', `
                <div class="hero-slides">${slidesHTML}</div>
                ${items.length > 1 ? `
                <div class="hero-controls">
                    <div class="hero-dots">${items.map(({ title }, i) => `<button type="button" class="hero-dot" data-i="${i}" aria-label="Показать: ${esc(title.name)}"></button>`).join('')}</div>
                    <span class="hero-counter"><b id="hero-current">01</b> / ${String(items.length).padStart(2, '0')}</span>
                    <button type="button" class="icon-btn" data-dir="-1" aria-label="Предыдущий">${icon('chevLeft')}</button>
                    <button type="button" class="icon-btn" data-dir="1" aria-label="Следующий">${icon('chevRight')}</button>
                </div>` : ''}`);

            this.el.style.setProperty('--hero-delay', `${this.delay}ms`);
            this.el.querySelectorAll('.hero-dot').forEach(dot =>
                dot.addEventListener('click', () => this.go(Number(dot.dataset.i))));
            this.el.querySelectorAll('[data-dir]').forEach(btn =>
                btn.addEventListener('click', () => this.go(this.index + Number(btn.dataset.dir))));

            const pause = () => { this.paused = true; this.el.classList.add('is-paused'); clearTimeout(this.timer); };
            const resume = () => { this.paused = false; this.el.classList.remove('is-paused'); this.schedule(); };
            this.el.addEventListener('mouseenter', pause);
            this.el.addEventListener('mouseleave', resume);
            this.el.addEventListener('focusin', pause);
            this.el.addEventListener('focusout', resume);
            document.addEventListener('visibilitychange', () => document.hidden ? clearTimeout(this.timer) : (!this.paused && this.schedule()));

            let startX = null;
            this.el.addEventListener('touchstart', (e) => { startX = e.touches[0].clientX; }, { passive: true });
            this.el.addEventListener('touchend', (e) => {
                if (startX === null) return;
                const dx = e.changedTouches[0].clientX - startX;
                if (Math.abs(dx) > 60) this.go(this.index + (dx < 0 ? 1 : -1));
                startX = null;
            });

            this.go(0, true);
        },

        go(i, initial = false) {
            const n = this.slides.length;
            this.index = (i + n) % n;
            this.el.querySelectorAll('.hero-slide').forEach((s, k) => {
                s.classList.toggle('is-active', k === this.index);
                s.setAttribute('aria-hidden', k === this.index ? 'false' : 'true');
                s.querySelectorAll('a, button').forEach(el => { el.tabIndex = k === this.index && !el.classList.contains('hero-art') ? 0 : -1; });
            });
            this.el.querySelectorAll('.hero-backdrop').forEach((b, k) => b.classList.toggle('is-active', k === this.index));
            this.el.querySelectorAll('.hero-dot').forEach((d, k) => {
                d.classList.toggle('is-done', k < this.index);
                d.classList.remove('is-active');
                if (k === this.index) { void d.offsetWidth; d.classList.add('is-active'); }
            });
            const counter = $('hero-current');
            if (counter) counter.textContent = String(this.index + 1).padStart(2, '0');
            if (!initial || !this.paused) this.schedule();
        },

        schedule() {
            clearTimeout(this.timer);
            if (this.slides.length < 2 || this.paused || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
            this.timer = setTimeout(() => this.go(this.index + 1), this.delay);
        }
    };

    async function loadFeatured() {
        try {
            return await fetchJSON(`${RAW}featured.json`, { cache: 'no-cache' });
        } catch (e) {
            return null;
        }
    }

    function heroItems(library, featured) {
        const pool = [...library].filter(t => !isDropped(t))
            .sort((a, b) => titleActivity(b).localeCompare(titleActivity(a)));
        const items = pool.slice(0, 5).map((title, i) => {
            const last = lastChapterDate(title);
            return {
                title,
                badge: isFresh(last) ? 'Новая глава' : (i === 0 ? 'Последнее обновление' : 'Читают сейчас'),
                note: last ? `Обновлено ${relTime(last)}` : ''
            };
        });
        if (featured && featured.enabled && featured.titleId) {
            const title = library.find(t => t.id === featured.titleId);
            if (title) {
                const rest = items.filter(item => item.title.id !== title.id);
                const last = lastChapterDate(title);
                return [{ title, badge: featured.badge || 'Рекомендуем', note: last ? `Обновлено ${relTime(last)}` : '' }, ...rest].slice(0, 5);
            }
        }
        return items;
    }

    /* ---------- Продолжить чтение ---------- */

    function renderContinue(library) {
        const section = $('continue');
        const rail = $('continue-rail');
        const byId = new Map((library || []).map(t => [t.id, t]));

        const entries = Object.entries(progress.all())
            .sort((a, b) => String(b[1].updatedAt).localeCompare(String(a[1].updatedAt)));

        const cards = [];
        for (const [titleId, p] of entries) {
            const title = byId.get(titleId);
            const name = title?.name || p.name;
            const cover = title?.cover || p.cover;
            if (!name) continue;

            let target;
            if (title) {
                target = resumeTarget(titleId, title.chapters || []);
                if (!target || target.kind === 'done' || target.kind === 'start') continue;
            } else {
                const finished = p.total && p.page >= p.total - 1;
                if (finished) continue;
                target = { kind: 'continue', chapter: { id: p.chapterId, volume: p.volume, number: p.number }, page: p.page, total: p.total };
            }

            const ch = target.chapter;
            const isNext = target.kind === 'next';
            const pct = isNext ? 0 : Math.round(((target.page + 1) / (target.total || 1)) * 100);
            const href = readerUrl(titleId, ch.id, isNext ? 0 : target.page);
            const fresh = isNext && isFresh(ch.createdAt);

            cards.push(`<article class="ccard" data-reveal>
                <div class="ccard-bg" style="background-image:url('${esc(raw(cover))}')"></div>
                ${coverHTML({ name, cover })}
                <div class="ccard-body">
                    <h3 class="ccard-title">${esc(name)}</h3>
                    <span class="ccard-ch">Том ${esc(ch.volume || 1)} · Глава ${esc(ch.number)}</span>
                    <div class="ccard-foot">
                        <div class="ccard-row">
                            <span>${isNext ? (fresh ? 'Вышла новая глава!' : 'Следующая глава') : `Стр. ${target.page + 1} из ${target.total}`}</span>
                            <span>${esc(relTime(p.updatedAt))}</span>
                        </div>
                        <div class="progress-line"><i style="--p:${pct}%"></i></div>
                        <span class="ccard-go">${isNext ? 'Читать дальше' : 'Продолжить'} ${icon('arrowRight')}</span>
                    </div>
                </div>
                <a class="ccard-link" href="${href}" aria-label="${isNext ? 'Читать дальше' : 'Продолжить'}: ${esc(name)}, глава ${esc(ch.number)}"></a>
                <button type="button" class="ccard-remove" data-remove="${esc(titleId)}" aria-label="Убрать из списка" title="Убрать из списка">${icon('x')}</button>
            </article>`);
        }

        section.hidden = cards.length === 0;
        rail.innerHTML = cards.join('');
        rail.querySelectorAll('[data-remove]').forEach(btn => btn.addEventListener('click', () => {
            const id = btn.dataset.remove;
            const saved = progress.get(id);
            progress.remove(id);
            renderContinue(state.library);
            toast('Убрано из «Продолжить»', {
                action: 'Вернуть',
                onAction: () => {
                    const all = progress.all();
                    all[id] = saved;
                    WL.store.set('wl_progress', all);
                    renderContinue(state.library);
                }
            });
        }));
        reveal(rail);
    }

    /* ---------- Недавние главы ---------- */

    function renderRecent() {
        const grid = $('recent-grid');
        const chapters = [];
        state.library.forEach(title => (title.chapters || []).forEach(ch => chapters.push({ title, ch })));

        if (!chapters.length) {
            grid.innerHTML = `<div class="empty" style="grid-column:1/-1">${icon('clock')}<strong>Главы пока не выходили</strong></div>`;
            $('recent-more').hidden = true;
            return;
        }

        // Свежие вверху
        chapters.sort((a, b) => String(b.ch.createdAt || '1970').localeCompare(String(a.ch.createdAt || '1970')));

        grid.innerHTML = chapters.slice(0, state.recentLimit).map(({ title, ch }) => {
            const isRead = read.has(title.id, ch.id);
            const pages = ch.pagesCount || 0;
            return `<a class="rtile ${isRead ? 'is-read' : ''}" href="${readerUrl(title.id, ch.id)}" data-reveal>
                ${coverHTML(title)}
                <span class="rtile-info">
                    <span class="rtile-name">${esc(title.name)}</span>
                    <span class="rtile-ch">Глава ${esc(ch.number)}</span>
                    <span class="rtile-meta">
                        <span>Том ${esc(ch.volume || 1)}</span>
                        ${pages ? `<span>${pluralize(pages, ['стр.', 'стр.', 'стр.'])}</span>` : ''}
                        ${ch.createdAt ? `<span>${esc(relTime(ch.createdAt))}</span>` : ''}
                    </span>
                </span>
                <span class="rtile-side">
                    ${isFresh(ch.createdAt) && !isRead ? '<span class="pill pill-new">New</span>' : ''}
                    ${isRead ? `<span class="read-mark">${icon('check')}Прочитано</span>` : ''}
                    <span class="rtile-arrow">${icon('arrowRight')}</span>
                </span>
            </a>`;
        }).join('');

        const more = $('recent-more');
        more.hidden = chapters.length <= state.recentLimit;
        reveal(grid);
    }

    $('recent-more').querySelector('button').addEventListener('click', () => {
        state.recentLimit += 6;
        renderRecent();
    });

    /* ---------- Полка ---------- */

    function renderShelf() {
        const box = $('shelf-content');
        const ids = bookmarks.list();
        const byId = new Map(state.library.map(t => [t.id, t]));
        const titles = ids.map(id => byId.get(id)).filter(Boolean);

        if (!titles.length) {
            box.innerHTML = `<div class="empty">
                ${icon('bookmark')}
                <strong>Полка пока пуста</strong>
                <span>Нажмите на значок закладки на обложке — тайтл появится здесь, а новые главы будут видны сразу.</span>
            </div>`;
            return;
        }
        box.innerHTML = `<div class="title-grid">${titles.map(t => titleCardHTML(t)).join('')}</div>`;
        reveal(box);
    }

    document.addEventListener('wl:bookmarks', () => { if (state.library.length) renderShelf(); });

    /* ---------- Каталог ---------- */

    const searchField = $('catalog-search');
    searchField.closest('.field').insertAdjacentHTML('afterbegin', icon('search'));
    searchField.value = state.query;
    $('catalog-sort').value = state.sort;
    $('catalog-sort').closest('.select').insertAdjacentHTML('beforeend', icon('chevDown'));

    const normalize = (s) => String(s || '').toLowerCase().replace(/ё/g, 'е');

    function syncUrl() {
        const p = new URLSearchParams();
        if (state.query) p.set('q', state.query);
        if (state.status !== 'all') p.set('status', state.status);
        if (state.genre) p.set('genre', state.genre);
        if (state.sort !== 'alpha') p.set('sort', state.sort);
        const qs = p.toString();
        history.replaceState(null, '', `${location.pathname}${qs ? `?${qs}` : ''}${location.hash}`);
    }

    function renderFilters() {
        const pool = state.library.filter(t => !isDropped(t));

        const statuses = [...new Set(pool.map(t => t.status || 'Онгоинг'))];
        if (state.status !== 'all' && !statuses.includes(state.status)) state.status = 'all';
        $('status-filter').innerHTML = ['all', ...statuses].map(s =>
            `<button type="button" data-status="${esc(s)}" class="${s === state.status ? 'is-active' : ''}" aria-pressed="${s === state.status}">${s === 'all' ? 'Все' : esc(s)}</button>`).join('');

        const genreCounts = {};
        pool.forEach(t => (t.genres || []).forEach(g => { genreCounts[g] = (genreCounts[g] || 0) + 1; }));
        const genres = Object.keys(genreCounts).sort((a, b) => a.localeCompare(b, 'ru'));
        $('genre-filter').innerHTML = [
            `<button type="button" class="chip ${!state.genre ? 'is-active' : ''}" data-genre="" aria-pressed="${!state.genre}">Все жанры</button>`,
            ...genres.map(g => `<button type="button" class="chip ${g === state.genre ? 'is-active' : ''}" data-genre="${esc(g)}" aria-pressed="${g === state.genre}">${esc(g)} <span class="count">${genreCounts[g]}</span></button>`)
        ].join('');
    }

    function renderCatalog() {
        const grid = $('catalog-grid');
        const q = normalize(state.query.trim());
        let titles = state.library.filter(t => !isDropped(t));

        if (state.status !== 'all') titles = titles.filter(t => (t.status || 'Онгоинг') === state.status);
        if (state.genre) titles = titles.filter(t => (t.genres || []).includes(state.genre));
        if (q) titles = titles.filter(t => normalize(t.name).includes(q) || normalize(t.origName).includes(q));

        const sorters = {
            alpha: (a, b) => a.name.localeCompare(b.name, 'ru'),
            updated: (a, b) => titleActivity(b).localeCompare(titleActivity(a)),
            chapters: (a, b) => (b.chapters || []).length - (a.chapters || []).length,
            year: (a, b) => (Number(b.year) || 0) - (Number(a.year) || 0) || a.name.localeCompare(b.name, 'ru')
        };
        titles.sort(sorters[state.sort] || sorters.alpha);

        const filtered = state.query || state.status !== 'all' || state.genre;
        $('catalog-count').textContent = filtered ? `Найдено: ${pluralize(titles.length, TITLE_FORMS)}` : '';

        if (!titles.length) {
            grid.innerHTML = `<div class="empty" style="grid-column:1/-1">
                ${icon('search')}
                <strong>Ничего не найдено</strong>
                <span>Попробуйте изменить фильтры.</span>
                <button type="button" class="btn btn-ghost btn-sm" id="reset-filters">Сбросить фильтры</button>
            </div>`;
            $('reset-filters').addEventListener('click', () => {
                Object.assign(state, { query: '', status: 'all', genre: '' });
                searchField.value = '';
                renderFilters();
                renderCatalog();
                syncUrl();
            });
            return;
        }
        grid.innerHTML = titles.map(t => titleCardHTML(t)).join('');
        reveal(grid);
    }

    $('status-filter').addEventListener('click', (e) => {
        const btn = e.target.closest('[data-status]');
        if (!btn) return;
        state.status = btn.dataset.status;
        renderFilters();
        renderCatalog();
        syncUrl();
    });

    $('genre-filter').addEventListener('click', (e) => {
        const btn = e.target.closest('[data-genre]');
        if (!btn) return;
        state.genre = btn.dataset.genre === state.genre ? '' : btn.dataset.genre;
        renderFilters();
        renderCatalog();
        syncUrl();
    });

    searchField.addEventListener('input', WL.debounce(() => {
        state.query = searchField.value;
        renderCatalog();
        syncUrl();
    }, 150));

    $('catalog-sort').addEventListener('change', (e) => {
        state.sort = e.target.value;
        renderCatalog();
        syncUrl();
    });

    function renderGraveyard() {
        const dead = state.library.filter(isDropped).sort((a, b) => a.name.localeCompare(b.name, 'ru'));
        $('graveyard').hidden = dead.length === 0;
        $('graveyard-grid').innerHTML = dead.map(t => titleCardHTML(t)).join('');
        reveal($('graveyard-grid'));
    }

    function renderRandom() {
        const btn = $('random-btn');
        const pool = state.library.filter(t => !isDropped(t));
        if (pool.length < 2) return;
        btn.hidden = false;
        btn.innerHTML = `${icon('shuffle')} Случайный тайтл`;
        btn.onclick = () => {
            const pick = pool[Math.floor(Math.random() * pool.length)];
            location.href = titleUrl(pick.id);
        };
    }

    /* ---------- Статистика ---------- */

    function renderStats() {
        const lib = state.library;
        const chapters = lib.reduce((n, t) => n + (t.chapters || []).length, 0);
        const pages = lib.reduce((n, t) => n + (t.chapters || []).reduce((m, ch) => m + (ch.pagesCount || 0), 0), 0);
        const latest = lib.map(lastChapterDate).sort().pop();
        const box = $('stats');
        box.hidden = false;
        box.innerHTML = `
            <div class="stat"><div class="stat-value" data-count="${lib.length}">0</div><div class="stat-label">${plural(lib.length, TITLE_FORMS)} в библиотеке</div></div>
            <div class="stat"><div class="stat-value" data-count="${chapters}">0</div><div class="stat-label">${plural(chapters, CHAPTER_FORMS)} переведено</div></div>
            <div class="stat"><div class="stat-value" data-count="${pages}">0</div><div class="stat-label">${plural(pages, PAGE_FORMS)} отрисовано</div></div>
            <div class="stat"><div class="stat-value" style="font-size: clamp(20px, 2.4vw, 30px)">${esc(latest ? relTime(latest) : '—')}</div><div class="stat-label">последнее обновление</div></div>`;

        const animate = () => box.querySelectorAll('[data-count]').forEach(el => {
            const target = Number(el.dataset.count);
            const start = performance.now();
            const tick = (now) => {
                const k = Math.min(1, (now - start) / 1200);
                el.textContent = Math.round(target * (1 - Math.pow(1 - k, 3))).toLocaleString('ru-RU');
                if (k < 1) requestAnimationFrame(tick);
            };
            requestAnimationFrame(tick);
        });

        if ('IntersectionObserver' in window) {
            const io = new IntersectionObserver((entries) => {
                if (entries.some(e => e.isIntersecting)) { animate(); io.disconnect(); }
            });
            io.observe(box);
        } else {
            animate();
        }
    }

    /* ---------- Ошибка загрузки ---------- */

    function renderError() {
        hero.el.hidden = true;
        const retry = `<button type="button" class="btn btn-gold btn-sm" data-retry>${icon('refresh')}Повторить</button>`;
        const msg = `<div class="empty" style="grid-column:1/-1">${icon('info')}<strong>Не удалось загрузить библиотеку</strong><span>GitHub временно ограничил запросы или пропало соединение. Попробуйте через минуту.</span>${retry}</div>`;
        $('recent-grid').innerHTML = msg;
        $('catalog-grid').innerHTML = '';
        $('shelf-content').innerHTML = '';
        document.querySelectorAll('[data-retry]').forEach(btn => btn.addEventListener('click', () => location.reload()));
    }

    /* ---------- Запуск ---------- */

    // Скелетоны каталога
    $('catalog-grid').innerHTML = Array.from({ length: 6 }, () =>
        `<div class="tcard-skeleton"><div class="skeleton"></div><div class="skeleton"></div></div>`).join('');

    // «Продолжить» можно показать сразу — данные лежат локально
    renderContinue(null);

    async function init() {
        const featuredPromise = loadFeatured();
        let result;
        try {
            result = await loadLibrary();
        } catch (e) {
            renderError();
            return;
        }

        state.library = result.items.map(t => ({ ...t, chapters: sortChapters(t.chapters) }));
        const featured = await featuredPromise;

        hero.render(heroItems(state.library, featured));
        renderContinue(state.library);
        renderRecent();
        renderShelf();
        renderFilters();
        renderCatalog();
        renderGraveyard();
        renderRandom();
        renderStats();

        if (result.stale) {
            toast('Показана сохранённая версия библиотеки — GitHub временно недоступен', { timeout: 5000 });
        }

        // Возврат к якорю после асинхронной отрисовки
        if (location.hash) {
            const target = document.querySelector(location.hash);
            if (target) requestAnimationFrame(() => target.scrollIntoView());
        }
    }

    init();
})();
