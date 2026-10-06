/* =========================================================
   WhiteLight — читалка
   ========================================================= */
(function () {
    'use strict';

    const {
        esc, raw, icon, store, read, progress, bookmarks, bookmarkButton, sortChapters,
        fetchJSON, readerUrl, titleUrl, toast, RAW
    } = WL;

    const $ = (id) => document.getElementById(id);
    const params = new URLSearchParams(location.search);
    const titleId = params.get('title');
    const chapterId = params.get('chapter');
    const startPage = parseInt(params.get('page'), 10);

    const body = document.body;
    const readerContainer = $('reader-container');
    const pagesWrapper = $('pages-wrapper');
    const endEl = $('rd-end');
    const chapterTitleEl = $('chapter-title');
    const chapterSelect = $('rd-chapter-select');
    const prevChapterBtn = $('prev-chapter-btn');
    const nextChapterBtn = $('next-chapter-btn');
    const settingsModal = $('settings-modal');
    const slider = $('page-slider');
    const counter = $('page-counter');
    const progressBar = $('rd-progress-bar');

    /* ---------- Иконки ---------- */

    $('rd-back').innerHTML = icon('arrowLeft');
    prevChapterBtn.innerHTML = icon('chevLeft');
    nextChapterBtn.innerHTML = icon('chevRight');
    $('open-settings').innerHTML = icon('sliders');
    $('close-settings-x').innerHTML = icon('x');
    $('page-prev').innerHTML = icon('chevLeft');
    $('page-next').innerHTML = icon('chevRight');
    document.querySelector('.rd-chapter').insertAdjacentHTML('beforeend', icon('chevDown'));
    document.querySelectorAll('[data-icon]').forEach(el => el.insertAdjacentHTML('afterbegin', icon(el.dataset.icon)));

    const fsBtn = $('rd-fullscreen');
    if (!document.fullscreenEnabled) fsBtn.remove();
    const updateFsIcon = () => { if (fsBtn.isConnected) fsBtn.innerHTML = icon(document.fullscreenElement ? 'minimize' : 'maximize'); };
    updateFsIcon();

    /* ---------- Настройки ---------- */

    const prefs = Object.assign(
        { width: 900, gap: 10, dir: 'ltr', bg: 'black', numbers: true, autoHide: true },
        store.get('wl_reader_prefs', {})
    );
    let mode = store.rawGet('wl_read_mode') === 'horizontal' ? 'horizontal' : 'vertical';
    let fit = store.rawGet('wl_fit_mode') === 'height' ? 'height' : 'width';

    const BG_COLORS = { black: '#000000', ink: '#18181d', paper: '#efe9dd' };

    function applyPrefs() {
        readerContainer.classList.toggle('mode-vertical', mode === 'vertical');
        readerContainer.classList.toggle('mode-horizontal', mode === 'horizontal');
        readerContainer.classList.toggle('fit-width', fit === 'width');
        readerContainer.classList.toggle('fit-height', fit === 'height');
        readerContainer.classList.toggle('dir-rtl', prefs.dir === 'rtl');
        body.classList.toggle('is-horizontal', mode === 'horizontal');
        body.classList.remove('bg-black', 'bg-ink', 'bg-paper');
        body.classList.add(`bg-${prefs.bg}`);
        body.classList.toggle('no-numbers', !prefs.numbers);
        body.style.setProperty('--rd-width', `${prefs.width}px`);
        body.style.setProperty('--rd-gap', `${prefs.gap}px`);
        document.querySelector('meta[name="theme-color"]').content = BG_COLORS[prefs.bg] || '#000000';

        document.querySelectorAll('[data-show-mode]').forEach(el => { el.hidden = el.dataset.showMode !== mode; });
        document.querySelectorAll('[data-show-fit]').forEach(el => { el.hidden = el.dataset.showFit !== fit; });
        $('opt-width-out').textContent = `${prefs.width} px`;
        setFill($('opt-width'));
    }

    function savePrefs() {
        store.set('wl_reader_prefs', prefs);
    }

    function syncSettingsForm() {
        const check = (name, value) => document.querySelectorAll(`input[name="${name}"]`).forEach(r => { r.checked = r.value === String(value); });
        check('read-mode', mode);
        check('fit-mode', fit);
        check('gap', prefs.gap);
        check('dir', prefs.dir);
        check('bg', prefs.bg);
        $('opt-width').value = prefs.width;
        $('opt-numbers').checked = prefs.numbers;
        $('opt-autohide').checked = prefs.autoHide;
    }

    const setFill = (input) => {
        const min = Number(input.min) || 0;
        const max = Number(input.max) || 1;
        const pct = max > min ? ((Number(input.value) - min) / (max - min)) * 100 : 0;
        input.style.setProperty('--fill', `${pct}%`);
    };

    syncSettingsForm();
    applyPrefs();

    /* ---------- Состояние ---------- */

    let chapters = [];
    let chapter = null;
    let titleData = null;
    let prevChap = null;
    let nextChap = null;
    let wrappers = [];
    let totalPages = 0;
    let currentPageIndex = 0;
    let readMarked = false;
    let nextPrefetched = false;

    /* ---------- Видимость панелей ---------- */

    const setUI = (visible) => body.classList.toggle('ui-hidden', !visible);
    const toggleUI = () => setUI(body.classList.contains('ui-hidden'));

    let lastY = window.scrollY;
    window.addEventListener('scroll', () => {
        const y = window.scrollY;
        const delta = y - lastY;
        lastY = y;
        if (mode === 'vertical') {
            if (y < 80) setUI(true);
            else if (prefs.autoHide && delta > 8) setUI(false);
            else if (delta < -14) setUI(true);
            updateVerticalProgress();
        }
    }, { passive: true });

    window.addEventListener('mousemove', (e) => {
        if (e.clientY < 72 || e.clientY > window.innerHeight - 72) {
            if (body.classList.contains('ui-hidden') && !settingsOpen()) setUI(true);
        }
    }, { passive: true });

    readerContainer.addEventListener('click', (e) => {
        if (mode !== 'vertical' || e.target.closest('a, button, select, input, .rd-end')) return;
        toggleUI();
    });

    /* ---------- Прогресс ---------- */

    function updateVerticalProgress() {
        const max = document.documentElement.scrollHeight - window.innerHeight;
        const pct = max > 0 ? Math.min(100, (window.scrollY / max) * 100) : 0;
        progressBar.style.width = `${pct}%`;
    }

    const saveProgress = WL.debounce(() => {
        if (!chapter || !totalPages) return;
        progress.set(titleId, {
            chapterId: chapter.id,
            volume: chapter.volume,
            number: chapter.number,
            page: Math.min(currentPageIndex, totalPages - 1),
            total: totalPages,
            name: titleData?.name || '',
            cover: titleData?.cover || ''
        });
    }, 400);

    function markReadOnce() {
        if (readMarked || !chapter) return;
        readMarked = true;
        read.mark(titleId, chapter.id);
    }

    function prefetchNext() {
        if (nextPrefetched || !nextChap || !nextChap.pages) return;
        nextPrefetched = true;
        nextChap.pages.slice(0, 2).forEach(p => { const img = new Image(); img.src = raw(p); });
    }

    function onPageChange() {
        const shown = Math.min(currentPageIndex, totalPages - 1) + 1;
        counter.textContent = `${shown} / ${totalPages}`;
        slider.value = shown;
        setFill(slider);
        if (mode === 'horizontal') {
            const pct = currentPageIndex >= totalPages ? 100 : (shown / totalPages) * 100;
            progressBar.style.width = `${pct}%`;
        }
        $('page-prev').disabled = currentPageIndex <= 0;
        $('page-next').disabled = mode === 'horizontal' ? currentPageIndex >= totalPages : currentPageIndex >= totalPages - 1;
        if (currentPageIndex >= totalPages - 1) markReadOnce();
        if (currentPageIndex >= totalPages * 0.7) prefetchNext();
        saveProgress();
    }

    /* ---------- Горизонтальный режим ---------- */

    function preloadAround(i) {
        for (let k = i - 1; k <= i + 3; k++) {
            const img = wrappers[k]?.querySelector('img');
            if (img) img.loading = 'eager';
        }
    }

    // Переключение страниц в горизонтальном режиме (индекс totalPages — экран «конец главы»)
    function updateHorizontalView(prevIndex = currentPageIndex) {
        const atEnd = currentPageIndex >= totalPages;
        readerContainer.classList.toggle('show-end', atEnd);
        body.classList.toggle('at-end', atEnd);
        document.querySelector('.rd-zones').style.display = atEnd ? 'none' : '';
        wrappers.forEach((wrapper, index) => {
            wrapper.classList.remove('from-next', 'from-prev');
            wrapper.classList.toggle('active', index === currentPageIndex);
        });
        const active = wrappers[currentPageIndex];
        if (active && prevIndex !== currentPageIndex) {
            active.classList.add(currentPageIndex > prevIndex ? 'from-next' : 'from-prev');
        }
        preloadAround(currentPageIndex);
        if (atEnd) setUI(true);
        window.scrollTo(0, 0);
    }

    function goTo(i) {
        const max = mode === 'horizontal' ? totalPages : totalPages - 1;
        const target = Math.max(0, Math.min(i, max));
        if (mode === 'horizontal') {
            const prev = currentPageIndex;
            currentPageIndex = target;
            updateHorizontalView(prev);
            onPageChange();
        } else {
            jumpVertical(target, true);
        }
    }

    function nextPage(isRepeat = false) {
        if (mode === 'horizontal') {
            if (currentPageIndex < totalPages) {
                goTo(currentPageIndex + 1);
                if (prefs.autoHide && currentPageIndex < totalPages) setUI(false);
            } else if (nextChap && !isRepeat) {
                // С экрана «конец главы» — сразу в следующую (но не по зажатой клавише)
                location.href = readerUrl(titleId, nextChap.id);
            }
        } else {
            goTo(currentPageIndex + 1);
        }
    }

    function prevPage() {
        if (currentPageIndex > 0) goTo(currentPageIndex - 1);
    }

    /* ---------- Вертикальный режим ---------- */

    let jumpCancel = null;

    function jumpVertical(i, smooth = false) {
        if (jumpCancel) jumpCancel();
        const target = wrappers[i];
        if (!target) return;
        for (let k = 0; k <= i; k++) {
            const img = wrappers[k].querySelector('img');
            if (img) img.loading = 'eager';
        }
        let cancelled = false;
        const doScroll = () => { if (!cancelled) target.scrollIntoView({ block: 'start', behavior: smooth ? 'smooth' : 'auto' }); };
        const stop = () => {
            cancelled = true;
            ['wheel', 'touchstart'].forEach(ev => window.removeEventListener(ev, stop));
        };
        jumpCancel = stop;
        ['wheel', 'touchstart'].forEach(ev => window.addEventListener(ev, stop, { passive: true }));

        doScroll();
        smooth = false;
        // Пока догружаются страницы выше, удерживаем нужную позицию
        wrappers.slice(0, i).forEach(w => {
            const img = w.querySelector('img');
            if (img && !img.complete) img.addEventListener('load', doScroll, { once: true });
        });
        setTimeout(stop, 8000);
    }

    let pageObserver = null;
    let endObserver = null;

    function observeVertical() {
        if (pageObserver) pageObserver.disconnect();
        if (endObserver) endObserver.disconnect();
        if (mode !== 'vertical' || !('IntersectionObserver' in window)) return;

        pageObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    const idx = Number(entry.target.dataset.index);
                    if (idx !== currentPageIndex) {
                        currentPageIndex = idx;
                        onPageChange();
                    }
                }
            });
        }, { rootMargin: '-45% 0px -54% 0px' });
        wrappers.forEach(w => pageObserver.observe(w));

        endObserver = new IntersectionObserver((entries) => {
            if (entries.some(e => e.isIntersecting)) {
                currentPageIndex = totalPages - 1;
                onPageChange();
                markReadOnce();
                setUI(true);
            }
        }, { threshold: 0.25 });
        endObserver.observe(endEl);
    }

    /* ---------- Загрузка главы ---------- */

    function showFatal(message) {
        chapterTitleEl.textContent = message;
        pagesWrapper.innerHTML = `<div class="rd-loading" style="flex-direction:column;text-align:center">
            <strong style="font-size:18px">${esc(message)}</strong>
            <a class="btn btn-ghost" href="${titleId ? titleUrl(titleId) : 'main.html'}">${titleId ? 'К тайтлу' : 'На главную'}</a>
        </div>`;
        $('rd-bottom').hidden = true;
    }

    async function loadReader() {
        if (!titleId || !chapterId) {
            showFatal('Ошибка: Глава не найдена');
            return;
        }

        $('rd-back').href = titleUrl(titleId);
        $('rd-title-name').href = titleUrl(titleId);

        const base = `${RAW}titles/${encodeURIComponent(titleId)}/`;
        const [chapRes, dataRes] = await Promise.allSettled([
            fetchJSON(base + 'chapters.json', { cache: 'no-cache' }),
            fetchJSON(base + 'data.json', { cache: 'no-cache' })
        ]);

        if (chapRes.status !== 'fulfilled') {
            console.error(chapRes.reason);
            showFatal('Ошибка сети');
            return;
        }

        titleData = dataRes.status === 'fulfilled' ? dataRes.value : null;
        chapters = sortChapters(chapRes.value);
        const currentChapterIndex = chapters.findIndex(c => c.id === chapterId);

        if (currentChapterIndex === -1) {
            showFatal('Глава не найдена');
            return;
        }

        chapter = chapters[currentChapterIndex];
        prevChap = chapters[currentChapterIndex - 1] || null;
        nextChap = chapters[currentChapterIndex + 1] || null;

        const label = `Том ${chapter.volume} Глава ${chapter.number}`;
        chapterTitleEl.textContent = label;
        if (titleData) {
            $('rd-title-name').textContent = titleData.name;
            document.title = `Глава ${chapter.number} — ${titleData.name} | WL`;
        } else {
            document.title = `${label} — WL`;
        }

        // Выпадающий список глав
        chapterSelect.innerHTML = [...chapters].reverse().map(c =>
            `<option value="${esc(c.id)}" ${c.id === chapter.id ? 'selected' : ''}>Том ${esc(c.volume)} · Глава ${esc(c.number)}${read.has(titleId, c.id) && c.id !== chapter.id ? ' ✓' : ''}</option>`).join('');
        chapterSelect.hidden = chapters.length < 2;
        chapterSelect.addEventListener('change', () => {
            location.href = readerUrl(titleId, chapterSelect.value);
        });

        prevChapterBtn.disabled = !prevChap;
        nextChapterBtn.disabled = !nextChap;
        if (prevChap) prevChapterBtn.title = `Предыдущая: Глава ${prevChap.number}`;
        if (nextChap) nextChapterBtn.title = `Следующая: Глава ${nextChap.number}`;

        buildPages(chapter.pages || []);
        renderEnd();

        if (!totalPages) {
            showFatal('В этой главе пока нет страниц');
            return;
        }

        // Восстановление позиции
        const saved = progress.get(titleId);
        if (!isNaN(startPage) && startPage > 1) {
            restore(Math.min(startPage, totalPages) - 1);
        } else {
            start(0);
            if (saved && saved.chapterId === chapter.id && saved.page > 0 && saved.page < totalPages - 1) {
                toast(`Вы остановились на стр. ${saved.page + 1}`, {
                    action: 'Продолжить',
                    onAction: () => goTo(saved.page),
                    timeout: 7000
                });
            }
        }

        maybeShowHint();
    }

    function start(index) {
        currentPageIndex = index;
        if (mode === 'horizontal') updateHorizontalView(index);
        observeVertical();
        onPageChange();
        updateVerticalProgress();
    }

    function restore(index) {
        start(mode === 'horizontal' ? index : 0);
        if (mode === 'vertical' && index > 0) {
            requestAnimationFrame(() => jumpVertical(index));
        }
    }

    // Создаём контейнер для каждой страницы + бейдж номера
    function buildPages(pagesList) {
        totalPages = pagesList.length;
        pagesWrapper.innerHTML = '';
        slider.max = Math.max(1, totalPages);

        wrappers = pagesList.map((pagePath, index) => {
            const wrapper = document.createElement('div');
            wrapper.className = 'manga-page-wrapper is-loading';
            wrapper.dataset.index = index;

            const img = document.createElement('img');
            img.className = 'manga-page';
            img.alt = `Страница ${index + 1}`;
            img.decoding = 'async';
            img.loading = index < 3 ? 'eager' : 'lazy';
            img.draggable = false;
            img.addEventListener('load', () => {
                wrapper.classList.remove('is-loading');
                img.classList.add('is-loaded');
            });
            img.addEventListener('error', () => showPageError(wrapper, img, pagePath));
            img.src = raw(pagePath);

            const badge = document.createElement('div');
            badge.className = 'page-number-badge';
            badge.textContent = `${index + 1} / ${totalPages}`;

            wrapper.appendChild(img);
            wrapper.appendChild(badge);
            pagesWrapper.appendChild(wrapper);
            return wrapper;
        });
    }

    function showPageError(wrapper, img, pagePath) {
        wrapper.classList.remove('is-loading');
        img.hidden = true;
        if (wrapper.querySelector('.page-error')) return;
        const box = document.createElement('div');
        box.className = 'page-error';
        box.innerHTML = `<span>Не удалось загрузить страницу ${Number(wrapper.dataset.index) + 1}</span>
            <button type="button" class="btn btn-ghost btn-sm">${icon('refresh')}Повторить</button>`;
        box.querySelector('button').addEventListener('click', (e) => {
            e.stopPropagation();
            box.remove();
            img.hidden = false;
            wrapper.classList.add('is-loading');
            img.src = `${raw(pagePath)}?retry=${Date.now()}`;
        });
        wrapper.insertBefore(box, img);
    }

    function renderEnd() {
        const isCompleted = ['завершён', 'завершен'].includes(String(titleData?.status || '').toLowerCase());
        const text = nextChap
            ? 'Следующая глава уже ждёт — продолжайте без пауз.'
            : isCompleted
                ? 'Это финальная глава тайтла. Спасибо, что дочитали вместе с WhiteLight!'
                : 'Это последняя вышедшая глава. Добавьте тайтл на полку, чтобы не пропустить продолжение.';
        const bm = bookmarkButton(titleId, 'btn btn-ghost')
            .replace(/<\/button>$/, `<span class="btn-label">${bookmarks.has(titleId) ? 'На полке' : 'На полку'}</span></button>`);

        endEl.innerHTML = `
            <img class="rd-end-star" src="data/team-logo.png" alt="">
            <p class="rd-end-kicker">Конец главы</p>
            <h2>Глава ${esc(chapter.number)} прочитана</h2>
            <p>${text}</p>
            ${nextChap ? `<a class="btn btn-gold rd-end-next" href="${readerUrl(titleId, nextChap.id)}">Глава ${esc(nextChap.number)} ${icon('arrowRight')}</a>` : ''}
            <div class="rd-end-actions">
                <a class="btn btn-ghost" href="${titleUrl(titleId)}">${icon('list')}К списку глав</a>
                ${bm}
                <a class="btn btn-ghost" href="socials.html">${icon('heart')}Поддержать команду</a>
            </div>`;
        endEl.hidden = false;
    }

    /* ---------- Подсказка по зонам ---------- */

    function maybeShowHint() {
        if (mode !== 'horizontal' || store.rawGet('wl_reader_hint_seen')) return;
        const hint = $('rd-hint');
        $('hint-left').textContent = prefs.dir === 'rtl' ? 'Вперёд' : 'Назад';
        $('hint-right').textContent = prefs.dir === 'rtl' ? 'Назад' : 'Вперёд';
        hint.hidden = false;
        hint.addEventListener('click', () => {
            hint.hidden = true;
            store.rawSet('wl_reader_hint_seen', '1');
        }, { once: true });
    }

    /* ---------- Управление ---------- */

    const forward = (isRepeat = false) => (prefs.dir === 'rtl' ? prevPage() : nextPage(isRepeat));
    const backward = (isRepeat = false) => (prefs.dir === 'rtl' ? nextPage(isRepeat) : prevPage());

    $('nav-next').addEventListener('click', (e) => { e.stopPropagation(); if (mode === 'horizontal') forward(); });
    $('nav-prev').addEventListener('click', (e) => { e.stopPropagation(); if (mode === 'horizontal') backward(); });
    $('nav-center').addEventListener('click', (e) => { e.stopPropagation(); toggleUI(); });

    $('page-next').addEventListener('click', () => nextPage());
    $('page-prev').addEventListener('click', prevPage);

    prevChapterBtn.addEventListener('click', () => { if (prevChap) location.href = readerUrl(titleId, prevChap.id); });
    nextChapterBtn.addEventListener('click', () => { if (nextChap) location.href = readerUrl(titleId, nextChap.id); });

    slider.addEventListener('input', () => {
        setFill(slider);
        const i = Number(slider.value) - 1;
        if (mode === 'horizontal') goTo(i);
        else counter.textContent = `${i + 1} / ${totalPages}`;
    });
    slider.addEventListener('change', () => {
        if (mode === 'vertical') jumpVertical(Number(slider.value) - 1);
    });

    // Свайпы в горизонтальном режиме
    let touchStart = null;
    document.querySelector('.rd-zones').addEventListener('touchstart', (e) => {
        if (e.touches.length !== 1) { touchStart = null; return; }
        touchStart = { x: e.touches[0].clientX, y: e.touches[0].clientY };
    }, { passive: true });
    document.querySelector('.rd-zones').addEventListener('touchend', (e) => {
        if (!touchStart || mode !== 'horizontal') return;
        if (window.visualViewport && window.visualViewport.scale > 1.05) { touchStart = null; return; }
        const dx = e.changedTouches[0].clientX - touchStart.x;
        const dy = e.changedTouches[0].clientY - touchStart.y;
        touchStart = null;
        if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) {
            // Свайп влево = следующая страница (для RTL — наоборот)
            if (dx < 0) forward(); else backward();
        }
    });

    function toggleFullscreen() {
        if (!document.fullscreenEnabled) return;
        if (document.fullscreenElement) document.exitFullscreen();
        else document.documentElement.requestFullscreen().catch(() => {});
    }
    if (fsBtn.isConnected) fsBtn.addEventListener('click', toggleFullscreen);
    document.addEventListener('fullscreenchange', updateFsIcon);

    // Клавиатура
    window.addEventListener('keydown', (e) => {
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        const code = e.code;

        if (settingsOpen()) {
            if (e.key === 'Escape') closeSettings();
            return;
        }

        // Стрелки не должны переключать главу в сфокусированном списке
        if (document.activeElement === chapterSelect && /^Arrow/.test(e.key)) {
            e.preventDefault();
            chapterSelect.blur();
        } else if (/^(INPUT|TEXTAREA)$/.test(document.activeElement?.tagName)) {
            return;
        }

        const isRight = code === 'ArrowRight' || code === 'KeyD';
        const isLeft = code === 'ArrowLeft' || code === 'KeyA';

        if (isRight || isLeft) {
            e.preventDefault();
            if (mode === 'horizontal') {
                if (isRight) forward(e.repeat); else backward(e.repeat);
            } else {
                if (isRight) nextPage(); else prevPage();
            }
        } else if (code === 'Space' && mode === 'horizontal') {
            const atBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 4;
            if (atBottom) {
                e.preventDefault();
                if (e.shiftKey) prevPage(); else nextPage(e.repeat);
            }
        } else if (code === 'BracketLeft') {
            if (prevChap) location.href = readerUrl(titleId, prevChap.id);
        } else if (code === 'BracketRight') {
            if (nextChap) location.href = readerUrl(titleId, nextChap.id);
        } else if (code === 'KeyF') {
            toggleFullscreen();
        } else if (code === 'KeyH') {
            toggleUI();
        } else if (code === 'KeyS') {
            openSettings();
        } else if (e.key === 'Escape') {
            setUI(true);
        }
    }, true);

    /* ---------- Лист настроек ---------- */

    const settingsOpen = () => !settingsModal.hidden;

    function openSettings() {
        syncSettingsForm();
        settingsModal.hidden = false;
        requestAnimationFrame(() => settingsModal.classList.add('is-open'));
        setTimeout(() => $('close-settings-x').focus(), 50);
    }

    function closeSettings() {
        settingsModal.classList.remove('is-open');
        setTimeout(() => { settingsModal.hidden = true; }, 250);
        $('open-settings').focus({ preventScroll: true });
    }

    $('open-settings').addEventListener('click', openSettings);
    $('close-settings').addEventListener('click', closeSettings);
    $('close-settings-x').addEventListener('click', closeSettings);
    settingsModal.addEventListener('click', (e) => { if (e.target === settingsModal) closeSettings(); });

    function switchMode(newMode) {
        if (newMode === mode) return;
        const keep = Math.min(currentPageIndex, totalPages - 1);
        mode = newMode;
        store.rawSet('wl_read_mode', mode);
        applyPrefs();
        if (!totalPages) return;
        if (mode === 'horizontal') {
            currentPageIndex = keep;
            updateHorizontalView(keep);
            observeVertical();
            onPageChange();
            maybeShowHint();
        } else {
            readerContainer.classList.remove('show-end');
            body.classList.remove('at-end');
            document.querySelector('.rd-zones').style.display = '';
            observeVertical();
            requestAnimationFrame(() => jumpVertical(keep));
        }
    }

    document.querySelectorAll('input[name="read-mode"]').forEach(radio =>
        radio.addEventListener('change', (e) => switchMode(e.target.value)));

    document.querySelectorAll('input[name="fit-mode"]').forEach(radio =>
        radio.addEventListener('change', (e) => {
            const keep = currentPageIndex;
            fit = e.target.value;
            store.rawSet('wl_fit_mode', fit);
            applyPrefs();
            if (mode === 'vertical' && totalPages) requestAnimationFrame(() => jumpVertical(Math.min(keep, totalPages - 1)));
        }));

    document.querySelectorAll('input[name="gap"]').forEach(radio =>
        radio.addEventListener('change', (e) => { prefs.gap = Number(e.target.value); savePrefs(); applyPrefs(); }));

    document.querySelectorAll('input[name="dir"]').forEach(radio =>
        radio.addEventListener('change', (e) => { prefs.dir = e.target.value; savePrefs(); applyPrefs(); }));

    document.querySelectorAll('input[name="bg"]').forEach(radio =>
        radio.addEventListener('change', (e) => { prefs.bg = e.target.value; savePrefs(); applyPrefs(); }));

    $('opt-width').addEventListener('input', (e) => { prefs.width = Number(e.target.value); applyPrefs(); });
    $('opt-width').addEventListener('change', savePrefs);
    $('opt-numbers').addEventListener('change', (e) => { prefs.numbers = e.target.checked; savePrefs(); applyPrefs(); });
    $('opt-autohide').addEventListener('change', (e) => {
        prefs.autoHide = e.target.checked;
        savePrefs();
        if (!prefs.autoHide) setUI(true);
    });

    window.addEventListener('DOMContentLoaded', loadReader);
    if (document.readyState !== 'loading') {
        window.removeEventListener('DOMContentLoaded', loadReader);
        loadReader();
    }
})();
