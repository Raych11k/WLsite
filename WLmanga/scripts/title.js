/* =========================================================
   WhiteLight — страница тайтла
   ========================================================= */
(function () {
    'use strict';

    const {
        esc, raw, icon, coverHTML, titleCardHTML, bookmarkButton, pluralize, plural, relTime, fmtDate, isFresh,
        CHAPTER_FORMS, PAGE_FORMS, read, progress, store, statusClass, loadTitle, loadLibrary,
        resumeAction, readerUrl, titleUrl, sortChapters, fetchJSON, reveal, share, COUNTER_NS
    } = WL;

    WL.renderChrome('catalog');

    const $ = (id) => document.getElementById(id);
    const titleId = new URLSearchParams(location.search).get('id');

    let titleData = null;
    let chapters = [];
    let order = store.rawGet('wl_chapter_order') === 'asc' ? 'asc' : 'desc';
    let chapterQuery = '';

    /* ---------- Загрузка ---------- */

    async function loadTitlePage() {
        if (!titleId) {
            showError('Тайтл не найден или указан неверный ID.');
            return;
        }
        try {
            const result = await loadTitle(titleId);
            titleData = result.data;
            chapters = result.chapters;
        } catch (err) {
            console.error('Ошибка:', err);
            showError(err.status === 404
                ? 'Не удалось найти данные выбранного тайтла.'
                : 'Произошла ошибка при загрузке данных с сервера.');
            return;
        }

        renderTitleDetails(titleData);
        renderActions();
        renderReadStats();
        renderChapters();
        setupTitlePopularity(titleId);

        $('loading').remove();
        $('title-content').hidden = false;
        requestAnimationFrame(setupDescriptionToggle);
        loadMore();
    }

    /* ---------- Детали ---------- */

    function renderTitleDetails(data) {
        document.title = `${data.name} | WhiteLight`;

        const coverUrl = raw(data.cover);
        $('title-backdrop').style.setProperty('--cover-url', `url('${coverUrl.replace(/'/g, '%27')}')`);
        $('title-cover').innerHTML = coverHTML(data, { eager: true });

        $('title-name-ru').textContent = data.name || 'Без названия';
        $('title-name-orig').textContent = data.origName || '';
        $('title-description-text').textContent = data.description || 'Описание не заполнено.';

        $('meta-type').textContent = data.type || 'Манга';
        $('meta-year').textContent = data.year || '—';
        const statusText = data.status || 'Онгоинг';
        $('meta-status').innerHTML = `<span class="status-dot s-${statusClass(statusText)}">${esc(statusText)}</span>`;

        const crumbs = document.querySelector('.breadcrumbs');
        crumbs.innerHTML = `<a href="main.html">Главная</a>${icon('chevRight')}<a href="main.html#catalog">Каталог</a>${icon('chevRight')}<span>${esc(data.name || '')}</span>`;

        // Жанры ведут в каталог с готовым фильтром
        $('genres-list').innerHTML = (data.genres || []).map(g =>
            `<a class="chip" href="main.html?genre=${encodeURIComponent(g)}#catalog">${esc(g)}</a>`).join('');
    }

    function renderActions() {
        const action = resumeAction(titleId, chapters);
        $('title-actions').innerHTML = `
            ${action
                ? `<a class="btn btn-gold" href="${action.href}" data-open-chapter="${esc(action.chapter.id)}">${icon('play')}${esc(action.label)}</a>`
                : `<span class="btn btn-gold" aria-disabled="true" style="opacity:.5">${icon('clock')}Скоро первая глава</span>`}
            ${bookmarkButton(titleId, 'btn btn-ghost').replace(/<\/button>$/, `<span class="btn-label">${WL.bookmarks.has(titleId) ? 'На полке' : 'На полку'}</span></button>`)}
            <button type="button" class="btn btn-ghost" id="share-btn" aria-label="Поделиться">${icon('share')}<span class="btn-label">Поделиться</span></button>`;

        $('share-btn').addEventListener('click', () => share({
            title: `${titleData.name} | WhiteLight`,
            text: `Читайте «${titleData.name}» на WhiteLight`
        }));
    }

    function renderReadStats() {
        const box = $('read-stats');
        if (!chapters.length) { box.hidden = true; return; }
        const done = read.countFor(titleId, chapters);
        const pct = Math.round((done / chapters.length) * 100);
        box.hidden = false;
        box.innerHTML = `
            <div class="read-stats-ring" style="--p:${pct}"><span>${pct}%</span></div>
            <div class="read-stats-text">
                <strong>${done === chapters.length ? 'Вы прочитали всё, что вышло!' : done ? `Прочитано ${done} из ${pluralize(chapters.length, CHAPTER_FORMS)}` : 'Вы ещё не начинали этот тайтл'}</strong>
                <span>${done === chapters.length ? 'Добавьте тайтл на полку, чтобы не пропустить новые главы.' : done ? `Осталось ${pluralize(chapters.length - done, CHAPTER_FORMS)}.` : `Доступно ${pluralize(chapters.length, CHAPTER_FORMS)} — самое время начать.`}</span>
            </div>`;
    }

    /* ---------- Популярность (тот же счётчик и защита от накруток) ---------- */

    function getFlameLevel(views) {
        if (views >= 500) return 3;
        if (views >= 100) return 2;
        if (views >= 30) return 1;
        return 0;
    }

    async function setupTitlePopularity(id) {
        const key = `title_${id}`;
        const popularityEl = $('meta-popularity');
        if (!popularityEl) return;

        // Защита от частых накруток за сутки через localStorage
        const lastViewKey = `wl_last_view_${id}`;
        const lastViewTime = store.rawGet(lastViewKey);
        const now = Date.now();
        const twentyFourHours = 24 * 60 * 60 * 1000;

        let url = `https://abacus.jasoncameron.dev/get/${COUNTER_NS}/${key}`;
        // Если прошли сутки или просмотров ещё не было — увеличиваем счётчик на 1
        if (!lastViewTime || (now - lastViewTime > twentyFourHours)) {
            url = `https://abacus.jasoncameron.dev/hit/${COUNTER_NS}/${key}`;
            store.rawSet(lastViewKey, now);
        }

        try {
            const data = await fetchJSON(url);
            const totalViews = data.value || 1;
            const level = getFlameLevel(totalViews);
            popularityEl.innerHTML = [0, 1, 2].map(i => icon('flame', i < level ? 'is-lit' : '')).join('');
            popularityEl.title = `Просмотров: ${totalViews}`;
            popularityEl.setAttribute('aria-label', `Популярность: ${level} из 3, просмотров: ${totalViews}`);
        } catch (err) {
            console.error('Не удалось загрузить популярность:', err);
            popularityEl.textContent = '—';
        }
    }

    /* ---------- Главы ---------- */

    function renderChapters() {
        const container = $('chapters-container');
        $('chapters-count').textContent = chapters.length ? pluralize(chapters.length, CHAPTER_FORMS) : '';

        if (!chapters.length) {
            container.innerHTML = '<div class="no-chapters">У этого тайтла пока нет опубликованных глав.</div>';
            return;
        }

        $('chapters-tools').hidden = chapters.length < 2;
        $('chapter-sort').innerHTML = `${icon('sort')}${order === 'desc' ? 'Сначала новые' : 'Сначала первые'}`;

        const readList = read.list();
        const p = progress.get(titleId);
        const isCompleted = ['завершён', 'завершен'].includes(String(titleData.status || '').toLowerCase());
        // Финальная глава — последняя в самом старшем томе (как и раньше)
        const finalId = isCompleted ? chapters[chapters.length - 1].id : null;

        const q = chapterQuery.trim().toLowerCase();
        const visible = q ? chapters.filter(ch => String(ch.number).toLowerCase().includes(q)) : chapters;

        if (!visible.length) {
            container.innerHTML = `<div class="no-chapters">Глава «${esc(chapterQuery)}» не найдена.</div>`;
            return;
        }

        const volumes = new Map();
        visible.forEach(ch => {
            const vol = ch.volume || 1;
            if (!volumes.has(vol)) volumes.set(vol, []);
            volumes.get(vol).push(ch);
        });

        const volumeKeys = [...volumes.keys()].sort((a, b) => order === 'desc' ? b - a : a - b);

        container.innerHTML = volumeKeys.map(vol => {
            const list = order === 'desc' ? [...volumes.get(vol)].reverse() : volumes.get(vol);
            const volRead = list.filter(ch => readList.includes(read.key(titleId, ch.id))).length;
            const pct = Math.round((volRead / list.length) * 100);

            return `<details class="volume" open>
                <summary>
                    <span class="volume-num">Том ${esc(vol)}</span>
                    <span class="volume-count">${pluralize(list.length, CHAPTER_FORMS)}</span>
                    <span class="volume-progress progress-line" title="Прочитано ${volRead} из ${list.length}"><i style="--p:${pct}%"></i></span>
                    ${icon('chevDown')}
                </summary>
                <div class="chapter-list">
                    ${list.map(ch => {
                        const isRead = readList.includes(read.key(titleId, ch.id));
                        const inProgress = p && p.chapterId === ch.id && p.total && p.page < p.total - 1;
                        const pages = ch.pagesCount || (ch.pages || []).length;
                        return `<div class="chapter ${isRead ? 'is-read' : ''}" data-id="${esc(ch.id)}">
                            <a class="chapter-main" href="${readerUrl(titleId, ch.id, inProgress ? p.page : 0)}" data-open-chapter="${esc(ch.id)}">
                                <span class="chapter-name">Глава ${esc(ch.number)}</span>
                                ${ch.id === finalId ? '<span class="pill pill-end">Конец</span>' : ''}
                                ${isFresh(ch.createdAt) && !isRead ? '<span class="pill pill-new">New</span>' : ''}
                            </a>
                            <span class="chapter-meta">
                                ${inProgress ? `<span class="chapter-progress">стр. ${p.page + 1}/${p.total}</span>` : ''}
                                ${pages ? `<span class="chapter-pages">${pluralize(pages, ['стр.', 'стр.', 'стр.'])}</span>` : ''}
                                ${ch.createdAt ? `<time datetime="${esc(ch.createdAt)}" title="${esc(relTime(ch.createdAt))}">${fmtDate(ch.createdAt)}</time>` : ''}
                            </span>
                            <button type="button" class="chapter-check" data-toggle-read="${esc(ch.id)}" aria-pressed="${isRead}" aria-label="${isRead ? 'Отметить непрочитанной' : 'Отметить прочитанной'}" title="${isRead ? 'Отметить непрочитанной' : 'Отметить прочитанной'}">
                                <span>${icon('check')}</span>
                            </button>
                        </div>`;
                    }).join('')}
                </div>
            </details>`;
        }).join('');
    }

    // Открытие главы отмечает её прочитанной (как и раньше)
    document.addEventListener('click', (e) => {
        const link = e.target.closest('[data-open-chapter]');
        if (link) read.mark(titleId, link.dataset.openChapter);

        const toggle = e.target.closest('[data-toggle-read]');
        if (toggle) {
            const id = toggle.dataset.toggleRead;
            if (read.has(titleId, id)) read.unmark(titleId, id); else read.mark(titleId, id);
            renderChapters();
            renderReadStats();
            renderActions();
        }
    });

    $('chapter-sort').addEventListener('click', () => {
        order = order === 'desc' ? 'asc' : 'desc';
        store.rawSet('wl_chapter_order', order);
        renderChapters();
    });

    $('chapter-search').closest('.field').insertAdjacentHTML('afterbegin', icon('search'));
    $('chapter-search').addEventListener('input', WL.debounce((e) => {
        chapterQuery = e.target.value;
        renderChapters();
    }, 120));

    /* ---------- Описание ---------- */

    function setupDescriptionToggle() {
        const descText = $('title-description-text');
        const toggleBtn = $('desc-toggle-btn');
        if (!descText || !toggleBtn) return;

        // Сравниваем реальную высоту текста с отображаемой
        if (descText.scrollHeight > descText.clientHeight + 4) {
            toggleBtn.hidden = false;
            toggleBtn.innerHTML = `<span>Читать далее</span>${icon('chevDown')}`;
            toggleBtn.onclick = () => {
                const collapsed = descText.classList.toggle('is-collapsed');
                toggleBtn.setAttribute('aria-expanded', String(!collapsed));
                toggleBtn.querySelector('span').textContent = collapsed ? 'Читать далее' : 'Свернуть';
            };
        } else {
            descText.classList.remove('is-collapsed');
            toggleBtn.hidden = true;
        }
    }

    /* ---------- Похожие тайтлы ---------- */

    async function loadMore() {
        try {
            const { items } = await loadLibrary();
            const genres = new Set(titleData.genres || []);
            const others = items
                .filter(t => t.id !== titleId)
                .map(t => ({ t, score: (t.genres || []).filter(g => genres.has(g)).length }))
                .sort((a, b) => b.score - a.score || a.t.name.localeCompare(b.t.name, 'ru'))
                .slice(0, 6)
                .map(x => ({ ...x.t, chapters: sortChapters(x.t.chapters) }));
            if (!others.length) return;
            $('more-grid').innerHTML = others.map(t => titleCardHTML(t)).join('');
            $('more-link').innerHTML = `Весь каталог ${icon('arrowRight')}`;
            $('more-section').hidden = false;
            reveal($('more-grid'));
        } catch (e) {
            /* блок необязательный */
        }
    }

    function showError(msg) {
        document.title = 'Тайтл не найден | WhiteLight';
        $('main').innerHTML = `<div class="state">
            ${icon('ghost', 'state-ico')}
            <h1>Упс, тайтл потерялся</h1>
            <p>${esc(msg)}</p>
            <a class="btn btn-gold" href="main.html#catalog">${icon('grid')}В каталог</a>
        </div>`;
    }

    // Обновляем отметки при возвращении из читалки кнопкой «назад»
    window.addEventListener('pageshow', (e) => {
        if (e.persisted && titleData) {
            renderChapters();
            renderReadStats();
            renderActions();
        }
    });

    loadTitlePage();
})();
