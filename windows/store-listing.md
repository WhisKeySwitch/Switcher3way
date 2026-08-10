# Microsoft Store listing copy

Ready to paste into Partner Center → **Store listings**. One listing per language: English (en),
Ukrainian (uk), Russian (ru) — the three languages the app itself converts between, which is also what
`Package.appxmanifest` declares under `<Resources>`.

## What the form actually asks for

The current Partner Center listing page has these fields, and no separate "short description" — so the
hook has to be the **first paragraph of Description**, because that is what gets used in previews and
search results:

| Field | Limit | Notes |
|---|---|---|
| **Description** (required) | 10,000 chars | Plain text. Blank lines separate paragraphs; markdown is not rendered, so no backticks or asterisks |
| **What's new in this version** | 1,500 chars | **Leave blank on the first submission** — the form says so, and there is no previous Store version to compare against. Use the text below from the *second* submission onwards |
| **Product features** | 20 items, 200 chars each | One box per bullet; "Add more" for each. Displayed as a bulleted list |
| **Search terms** | 7 terms, 30 chars each, 21 words total | Not shown to customers |
| **Screenshots** | at least 1, 1366×768 or larger | Each has its own caption field |
| **Copyright and trademark info** | 200 chars | Optional, but fill it — see below |
| **Additional license terms** | 10,000 chars | **Leave blank.** Blank means Microsoft's Standard Application License Terms, which is the normal arrangement for a free app. MIT already reaches the user: `LICENSE` ships inside the package (`Switcher3way.App.csproj` copies it next to the exe), which is what the licence requires. Pasting MIT here would add its warranty disclaimer *on top of* Microsoft's terms and invites questions about which governs |
| **Developed by** | 255 chars | `IronMade` |

Keep the three languages in step — if you edit one, edit all three.

---

## English (en)

### Description

Typed in the wrong keyboard layout? Switcher3way spots it and fixes it. Type ghbdsn and it becomes
привіт, the layout switches, and you carry on. English, Ukrainian and Russian — free, offline and open
source.

You know the moment: half a sentence in and you realise the layout was wrong. Switcher3way takes that
moment away.

It watches the word you are typing and, when the word is clearly in the wrong keyboard layout, retypes
it correctly and switches the layout for you. Not a guess on every word — only when the word makes
sense in another layout's language and nonsense in the current one. Short fragments and ambiguous
scraps are left alone, because a wrong fix is worse than a missed one.

Three languages, not two. Most layout fixers flip between two layouts. Switcher3way reads every layout
Windows has installed and checks each candidate against that language's dictionary, so English,
Ukrainian and Russian all work together.

Words that exist in both Ukrainian and Russian — там, добре — go to whichever language you prefer, and
if a later word makes the phrase clearly the other one, the app goes back and corrects itself.

FIX IT YOURSELF, TOO

Tap the trigger key — a double tap of Ctrl by default, or Pause/Break, F9 and others — to convert the
last word you typed. Select any text and tap it to convert the selection instead. Tap again with
nothing typed in between to step through the other layouts, and once more to get your original text
back. The trigger obeys you even where automatic fixing holds back.

Every fix shows a small chip under the corrected word, with a reminder of the undo key, so a change is
never silent.

WHERE IT STAYS OUT OF THE WAY

Password fields are excluded, including password boxes on web pages. Password managers and terminals
are excluded by default, and you can exclude any other app yourself. Individual words can be added to
a never-convert list — one click when a fix was wrong — or to an always-convert list.

Pause it for half an hour, an hour, or until you restart. Turn automatic fixing off and keep the manual
trigger. Let it remember a layout per application, so switching windows puts you back where you were.

PRIVATE BY DESIGN

Nothing you type is stored or transmitted. Keystrokes for the current word are held in memory and
discarded the moment the word ends. This Store version makes no network connections at all. Word
checking uses dictionaries built into the app. The whole source is public under the MIT licence.

BEFORE YOU START

Add both keyboard layouts in Windows first — English and Ukrainian or Russian — or there is nothing for
the app to switch between. Switcher3way lives in the notification area and has no main window; a short
welcome flow appears the first time you run it.

Works wherever your keystrokes come from — a directly attached keyboard, Remote Desktop, a virtual
machine, a remapped keyboard, or the on-screen keyboard.

The interface is fully translated into English, Ukrainian and Russian. Thirteen more languages are
partly translated and fall back to English for anything not yet covered; the language picker says which
is which.

### Product features

- Fixes words typed in the wrong keyboard layout automatically, as you finish each word
- Three languages together — English, Ukrainian and Russian — not just a two-layout toggle
- Checks every layout Windows has installed against that language's dictionary
- Words valid in both Ukrainian and Russian follow your preference, and are corrected later if the phrase proves otherwise
- Manual trigger — double Ctrl by default — converts the last word or the current selection
- Tap the trigger again to step through the other layouts, once more to undo
- A chip under the corrected word shows what changed and how to undo it
- Password fields, password managers and terminals are left alone; you can exclude any app
- Never-convert and always-convert lists for individual words
- Pause for half an hour, an hour, or until restart
- Optional per-application layout memory
- No network connections, no telemetry, nothing stored — open source under the MIT licence

### What's new in this version

Leave blank for the first submission. From the next update onwards:

Version 0.2.2

• The trigger key is now a double tap of Ctrl by default. It needs no reach on laptop keyboards and
  doesn't collide with anything — two taps with no other key in between. If you already chose a
  trigger, it is left exactly as you set it.
• Fixed: the app could quit after you finished the welcome flow instead of settling into the
  notification area.
• The trigger names in the welcome flow are no longer clipped.

### Search terms

keyboard layout
layout switcher
wrong layout
ukrainian keyboard
russian keyboard
розкладка
раскладка

---

## Українська (uk)

### Опис

Набрали не в тій розкладці? Switcher3way це помітить і виправить. Наберіть ghbdsn — і це стане привіт,
розкладка перемкнеться, а ви просто продовжите писати. Англійська, українська та російська —
безкоштовно, без інтернету, з відкритим кодом.

Знайомий момент: пів речення вже набрано, і аж тоді ви розумієте, що розкладка була не та.
Switcher3way прибирає цей момент.

Застосунок дивиться на слово, яке ви набираєте, і коли слово явно набране не в тій розкладці —
перенабирає його правильно та перемикає розкладку. Це не вгадування на кожному слові: виправлення
відбувається лише тоді, коли слово має сенс мовою іншої розкладки й не має сенсу поточною. Короткі
уривки та неоднозначні залишки лишаються недоторканими, бо помилкове виправлення гірше за пропущене.

Три мови, а не дві. Більшість подібних програм перемикається між двома розкладками. Switcher3way
читає всі розкладки, встановлені у Windows, і перевіряє кожен варіант словником відповідної мови —
тому англійська, українська та російська працюють разом.

Слова, які існують і українською, і російською — там, добре — переходять у мову, яку ви обрали. А якщо
наступне слово робить фразу однозначно іншою мовою, застосунок повертається й виправляє себе сам.

ВИПРАВЛЯЙТЕ Й САМОСТІЙНО

Натисніть клавішу-тригер — типово подвійний Ctrl, також доступні Pause/Break, F9 та інші — щоб
конвертувати останнє набране слово. Виділіть будь-який текст, і тригер конвертує саме виділення.
Натисніть ще раз, нічого не набираючи між натисканнями, щоб перейти до наступної розкладки, і ще раз —
щоб повернути початковий текст. Тригер слухається вас навіть там, де автоматичне виправлення
стримується.

Кожне виправлення показує невелику підказку під словом із нагадуванням про клавішу скасування, тож
зміна ніколи не буває непомітною.

ДЕ ЗАСТОСУНОК НЕ ВТРУЧАЄТЬСЯ

Поля паролів виключені, включно з полями паролів на вебсторінках. Менеджери паролів і термінали
виключені типово, і ви можете виключити будь-який інший застосунок. Окремі слова можна додати до
списку «ніколи не конвертувати» — одним клацанням, коли виправлення було зайвим — або до списку
«конвертувати завжди».

Призупиніть роботу на півгодини, годину або до перезапуску. Вимкніть автоматичне виправлення й
залиште лише ручний тригер. Дозвольте запам'ятовувати розкладку для кожного застосунку окремо, щоб
перехід між вікнами повертав вас туди, де ви були.

ПРИВАТНІСТЬ ЗА ЗАМОВЧУВАННЯМ

Ніщо з набраного не зберігається й не передається. Натискання клавіш для поточного слова тримаються
лише в пам'яті та відкидаються, щойно слово завершилося. Ця версія зі Store не робить жодних мережевих
з'єднань. Перевірка слів використовує словники, вбудовані в застосунок. Увесь вихідний код відкритий
за ліцензією MIT.

ПЕРЕД ПОЧАТКОМ

Спершу додайте у Windows обидві розкладки — англійську та українську чи російську — інакше застосунку
не буде між чим перемикатися. Switcher3way живе в області повідомлень і не має головного вікна; під
час першого запуску з'явиться короткий вступний покроковий екран.

Потрібна фізична клавіатура: застосунок не бачить введення з екранної клавіатури.

Інтерфейс повністю перекладено англійською, українською та російською. Ще тринадцять мов перекладено
частково — там, де перекладу ще немає, показується англійська; у виборі мови це позначено.

### Можливості

- Автоматично виправляє слова, набрані не в тій розкладці, щойно слово завершено
- Три мови разом — англійська, українська та російська, а не просто перемикач двох розкладок
- Перевіряє кожну встановлену у Windows розкладку словником відповідної мови
- Слова, дійсні і українською, і російською, ідуть за вашим вибором, а згодом виправляються, якщо фраза виявилася іншою
- Ручний тригер — типово подвійний Ctrl — конвертує останнє слово або виділений текст
- Повторне натискання перебирає інші розкладки, ще одне — скасовує
- Підказка під виправленим словом показує, що змінилося, і як це скасувати
- Поля паролів, менеджери паролів і термінали не зачіпаються; можна виключити будь-який застосунок
- Списки «ніколи не конвертувати» та «конвертувати завжди» для окремих слів
- Пауза на півгодини, годину або до перезапуску
- Необов'язкове запам'ятовування розкладки для кожного застосунку
- Жодних мережевих з'єднань, жодної телеметрії, нічого не зберігається — відкритий код за ліцензією MIT

### Що нового

Для першої публікації лишіть порожнім. Починаючи з наступного оновлення:

Версія 0.2.2

• Тригером типово став подвійний Ctrl. До нього не треба тягтися на ноутбуці й він ні з чим не
  конфліктує — два натискання без інших клавіш між ними. Якщо ви вже вибрали тригер, він залишається
  таким, як ви налаштували.
• Виправлено: застосунок міг завершити роботу після вступного екрана замість того, щоб залишитися
  в області повідомлень.
• Назви тригерів у вступному екрані більше не обрізаються.

### Ключові слова

розкладка клавіатури
перемикач розкладки
не та розкладка
українська розкладка
keyboard layout
layout switcher
раскладка

---

## Русский (ru)

### Описание

Набрали не в той раскладке? Switcher3way это заметит и исправит. Наберите ghbdsn — и это превратится
в привіт, раскладка переключится, а вы просто продолжите писать. Английский, украинский и русский —
бесплатно, без интернета, с открытым исходным кодом.

Знакомый момент: полфразы уже набрано, и только тогда вы понимаете, что раскладка была не та.
Switcher3way избавляет от этого момента.

Программа смотрит на слово, которое вы набираете, и когда слово явно набрано не в той раскладке —
перенабирает его правильно и переключает раскладку. Это не угадывание на каждом слове: исправление
происходит только если слово осмысленно на языке другой раскладки и бессмысленно на текущем. Короткие
обрывки и неоднозначные остатки остаются нетронутыми, потому что неверное исправление хуже
пропущенного.

Три языка, а не два. Большинство подобных программ переключается между двумя раскладками.
Switcher3way читает все раскладки, установленные в Windows, и проверяет каждый вариант словарём
соответствующего языка — поэтому английский, украинский и русский работают вместе.

Слова, которые существуют и в украинском, и в русском — там, добре — переходят в тот язык, который вы
предпочли. А если следующее слово делает фразу однозначно другой, программа возвращается и исправляет
себя сама.

ИСПРАВЛЯЙТЕ И ВРУЧНУЮ

Нажмите клавишу-триггер — по умолчанию двойной Ctrl, также доступны Pause/Break, F9 и другие — чтобы
преобразовать последнее набранное слово. Выделите любой текст, и триггер преобразует именно выделение.
Нажмите ещё раз, ничего не набирая между нажатиями, чтобы перейти к следующей раскладке, и ещё раз —
чтобы вернуть исходный текст. Триггер слушается вас даже там, где автоматическое исправление
воздерживается.

Каждое исправление показывает небольшую подсказку под словом с напоминанием о клавише отмены, так что
изменение никогда не остаётся незамеченным.

ГДЕ ПРОГРАММА НЕ ВМЕШИВАЕТСЯ

Поля паролей исключены, включая поля паролей на веб-страницах. Менеджеры паролей и терминалы исключены
по умолчанию, и вы можете исключить любое другое приложение. Отдельные слова можно добавить в список
«никогда не преобразовывать» — одним щелчком, когда исправление оказалось лишним — или в список
«преобразовывать всегда».

Приостановите работу на полчаса, час или до перезапуска. Отключите автоматическое исправление и
оставьте только ручной триггер. Разрешите запоминать раскладку для каждого приложения отдельно, чтобы
переход между окнами возвращал вас туда, где вы были.

ПРИВАТНОСТЬ ПО УМОЛЧАНИЮ

Ничего из набранного не сохраняется и не передаётся. Нажатия клавиш для текущего слова хранятся только
в памяти и отбрасываются, как только слово закончилось. Эта версия из Store не устанавливает никаких
сетевых соединений. Проверка слов использует словари, встроенные в программу. Весь исходный код
открыт по лицензии MIT.

ПЕРЕД НАЧАЛОМ

Сначала добавьте в Windows обе раскладки — английскую и украинскую или русскую — иначе программе не
между чем переключаться. Switcher3way живёт в области уведомлений и не имеет главного окна; при первом
запуске появится короткий вступительный экран.

Нужна физическая клавиатура: программа не видит ввод с экранной клавиатуры.

Интерфейс полностью переведён на английский, украинский и русский. Ещё тринадцать языков переведены
частично — там, где перевода ещё нет, показывается английский; в выборе языка это отмечено.

### Возможности

- Автоматически исправляет слова, набранные не в той раскладке, как только слово закончено
- Три языка вместе — английский, украинский и русский, а не просто переключатель двух раскладок
- Проверяет каждую установленную в Windows раскладку словарём соответствующего языка
- Слова, верные и в украинском, и в русском, следуют вашему выбору и исправляются позже, если фраза оказалась другой
- Ручной триггер — по умолчанию двойной Ctrl — преобразует последнее слово или выделенный текст
- Повторное нажатие перебирает другие раскладки, ещё одно — отменяет
- Подсказка под исправленным словом показывает, что изменилось и как это отменить
- Поля паролей, менеджеры паролей и терминалы не затрагиваются; можно исключить любое приложение
- Списки «никогда не преобразовывать» и «преобразовывать всегда» для отдельных слов
- Пауза на полчаса, час или до перезапуска
- Необязательное запоминание раскладки для каждого приложения
- Никаких сетевых соединений, никакой телеметрии, ничего не сохраняется — открытый код по лицензии MIT

### Что нового

Для первой публикации оставьте пустым. Начиная со следующего обновления:

Версия 0.2.2

• Триггером по умолчанию стал двойной Ctrl. К нему не нужно тянуться на ноутбуке, и он ни с чем не
  конфликтует — два нажатия без других клавиш между ними. Если вы уже выбрали триггер, он остаётся
  таким, как вы его настроили.
• Исправлено: программа могла завершиться после вступительного экрана вместо того, чтобы остаться
  в области уведомлений.
• Названия триггеров на вступительном экране больше не обрезаются.

### Ключевые слова

раскладка клавиатуры
переключатель раскладки
не та раскладка
русская раскладка
украинская раскладка
keyboard layout
layout switcher

---

## Notes on choices made here

**The hook is the first paragraph of Description, not a separate field.** The listing form has no short
description, and previews take the opening lines — so the description leads with the problem and the
example rather than with "Switcher3way is an application that…".

**No markdown, no backticks.** The Description box renders plain text; asterisks and backticks would
appear literally. Paragraph breaks and the ALL-CAPS section headings are the only structure available.

**No competitor names in the search terms.** "Punto Switcher" and similar would pull real traffic, but
they are other people's product names and Store policy 10.1.1 rejects listings that use trademarks the
publisher does not own.

**The examples are honest.** ghbdsn → привіт is what the app actually produces with an English layout
active and Ukrainian preferred — the same string the self-test prints. Don't swap in an example without
checking that it converts.

**No "physical keyboard required" claim.** It was true until 0.2.7: the hook ignored all injected input,
which made the app inert on a tablet using the on-screen keyboard — and failed Store certification twice.
Our own synthesized keys are now tagged, so everything else counts as real typing.

**Every claim needs checking against the code, not memory.** Two were wrong in the first draft. The
pause durations are 30 minutes / 1 hour / until restart (`TrayFlyoutWindow.xaml.cs`), not "ten minutes".
And the interface was described as "available in 16 languages" on the strength of `Loc.cs` holding 16
language blocks — but the WinUI rewrite had added ~50 strings hard-coded in English, so Ukrainian and
Russian users saw most of Settings and all of onboarding in English. That is now fixed in the app for
en/uk/ru; the other 13 languages fall back to English for those strings and the picker labels them
partly translated. Recheck if the copy is reused for a later version.

---

## Copyright and trademark info

One line per listing, 200-character limit. It names the project's own copyright first, then the upstream
fork and the dictionary licences — the MPL 1.1 Ukrainian dictionary is the one with a real notice
obligation, and the `LICENSE` shipped in the package carries the full texts.

- **en** — (c) 2026 IronMade. MIT License. A fork of RuSwitcher, (c) 2025 Rashns. Bundled Hunspell dictionaries: en/ru BSD, uk MPL 1.1. Full notices ship with the app.
- **uk** — (c) 2026 IronMade. Ліцензія MIT. Форк RuSwitcher, (c) 2025 Rashns. Вбудовані словники Hunspell: en/ru BSD, uk MPL 1.1. Повні тексти постачаються із застосунком.
- **ru** — (c) 2026 IronMade. Лицензия MIT. Форк RuSwitcher, (c) 2025 Rashns. Встроенные словари Hunspell: en/ru BSD, uk MPL 1.1. Полные тексты поставляются с программой.

Use the © character rather than "(c)" if the field accepts it — these are written in ASCII only so they
survive being copied out of this file.

---

## Screenshots

At least one is required; up to 10 are allowed. Each must be **1366×768 or larger** — a bare app window
is too small, so compose each shot on a full 1920×1080 screen rather than cropping tight to the window.
PNG. Captions are a separate field per image, 200 characters each.

Order matters: the first screenshot is the one shown in search results and at the top of the listing,
so it must be the app *doing its job*, not a settings page.

### 1. The fix happening — the hero shot

Notepad with `привіт` just written where `ghbdsn` was typed, and the feedback chip visible underneath.
This is the whole product in one frame.

The chip is only on screen for about 1.9 s (200 ms fade in, 1.6 s hold, 120 ms fade out — `CaretChip.cs`),
and it cannot be triggered by synthetic input because the hook ignores injected keys. So it has to be
captured live while someone types: a burst of screen grabs every ~150 ms for a few seconds, then pick
the frame where the chip is at full opacity.

- **en** — Type a word in the wrong layout and keep going. Switcher3way rewrites it and switches the layout, showing what changed and how to undo it.
- **uk** — Наберіть слово не в тій розкладці й продовжуйте. Switcher3way перепише його та перемкне розкладку, показавши, що змінилось і як це скасувати.
- **ru** — Наберите слово не в той раскладке и продолжайте. Switcher3way перепишет его и переключит раскладку, показав, что изменилось и как это отменить.

### 2. The tray flyout

The status header with the current layout, the quick toggles and the Pause submenu.

- **en** — Everything from the notification area: current layout, master switch, Auto-fix, and pause for half an hour, an hour or until restart.
- **uk** — Усе з області повідомлень: поточна розкладка, головний вимикач, автовиправлення та пауза на півгодини, годину чи до перезапуску.
- **ru** — Всё из области уведомлений: текущая раскладка, главный выключатель, автоисправление и пауза на полчаса, час или до перезапуска.

### 3. Welcome flow, step 2 — "Your layouts"

The three detected layouts with their "Dictionary ready" pills. This is the three-language claim made
visible, and it is the clearest single answer to "how is this different from a two-layout switcher".

- **en** — Nothing to configure: Switcher3way reads every layout Windows has installed and checks each one against that language's dictionary.
- **uk** — Нічого не треба налаштовувати: Switcher3way читає всі встановлені у Windows розкладки й перевіряє кожну словником її мови.
- **ru** — Ничего не нужно настраивать: Switcher3way читает все установленные в Windows раскладки и проверяет каждую словарём её языка.

### 4. Settings → General

The trigger picker open, showing Double Ctrl selected with Pause/Break and F9 beneath it.

- **en** — Pick the trigger that suits your keyboard. Tap it to convert the last word or a selection; tap again to cycle layouts or undo.
- **uk** — Виберіть тригер, який пасує вашій клавіатурі. Натисніть, щоб конвертувати останнє слово або виділення; ще раз — щоб перебрати розкладки чи скасувати.
- **ru** — Выберите триггер под свою клавиатуру. Нажмите, чтобы преобразовать последнее слово или выделение; ещё раз — чтобы перебрать раскладки или отменить.

### 5. Settings → Auto-fix

The preferred-language choice for words that are valid in both Ukrainian and Russian.

- **en** — Words that exist in both Ukrainian and Russian go to the language you prefer — and are corrected later if the rest of the phrase says otherwise.
- **uk** — Слова, які існують і українською, і російською, конвертуються у задану вами розкладку — а згодом виправляються, якщо решта фрази іншою мовою.
- **ru** — Слова, которые есть и в украинском, и в русском, конвертируются в выбранную вами раскладку — а позже исправляются, если далее фраза на другом языке.

### 6. Settings → the exceptions list

The unified list with a password manager showing its "always off" badge.

- **en** — Password fields are never touched. Password managers and terminals are excluded by default, and you can exclude any app or single word.
- **uk** — Поля паролів не зачіпаються ніколи. Менеджери паролів і термінали виключені типово, і ви можете виключити будь-який застосунок чи окреме слово.
- **ru** — Поля паролей не затрагиваются никогда. Менеджеры паролей и терминалы исключены по умолчанию, и вы можете исключить любое приложение или отдельное слово.

### Before you shoot

- **One theme throughout.** The app follows the system theme; a listing that mixes dark and light shots
  looks careless. Dark reads well for shots 2–6.
- **Clean the frame.** No repository paths, editor windows, personal file names, chat notifications or
  taskbar badges — the hero shot in particular wants an empty Notepad on a plain desktop.
- **Don't crop to the window.** A 560×620 window on its own is under the minimum and will be rejected;
  leave it on the full screen.
- **Same layout pair in every shot** (English + Ukrainian, say), so the story stays consistent.
