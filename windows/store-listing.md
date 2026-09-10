# Microsoft Store listing copy

Ready to paste into Partner Center → **Store listings**. One listing per language: English (en),
Ukrainian (uk), Russian (ru), Bulgarian (bg) — the four languages the app converts between.

These are the same four `Package.appxmanifest` declares under `<Resources>`, and they are the same
four the *interface* is fully translated into — Bulgarian was finished after the listing was written,
so a Bulgarian-language listing no longer promises an app the reader will not get. The other twelve
languages in `Loc.cs` are partial and fall back to English. That is measured, not assumed:

```powershell
python windows/tools/check-localization.py --require en,uk,ru,bg
```

## What the form actually asks for

The current Partner Center listing page has these fields, and no separate "short description" — so the
hook has to be the **first paragraph of Description**, because that is what gets used in previews and
search results:

| Field | Limit | Notes |
|---|---|---|
| **Description** (required) | 10,000 chars | Plain text. Blank lines separate paragraphs; markdown is not rendered, so no backticks or asterisks |
| **What's new in this version** | 1,500 chars | **Leave blank on the first submission** — the form says so, and there is no previous Store version to compare against. Use the text below from the *second* submission onwards |
| **Product features** | 20 items, 200 chars each | One box per bullet; "Add more" for each. Displayed as a bulleted list |
| **Search terms** | 7 terms, 30 chars each, 21 words total | Not shown to customers. **The documented 30 is not what the form enforced** — the Ukrainian and Russian terms Partner Center holds are 32–36 characters. The script warns and uploads them anyway rather than shortening someone's terms on the strength of a number in a doc |
| **Screenshots** | at least 1, 1366×768 or larger | Each has its own caption field |
| **Copyright and trademark info** | 200 chars | Optional, but fill it — see below |
| **Additional license terms** | 10,000 chars | **Leave blank.** Blank means Microsoft's Standard Application License Terms, which is the normal arrangement for a free app. MIT already reaches the user: `LICENSE` ships inside the package (`Switcher3way.App.csproj` copies it next to the exe), which is what the licence requires. Pasting MIT here would add its warranty disclaimer *on top of* Microsoft's terms and invites questions about which governs |
| **Developed by** | 255 chars | `IronMade` |

Keep the four languages in step — if you edit one, edit all four. You do not have to do that by
hand, and by hand is how they came apart:

```powershell
python windows/tools/build-listing-csv.py     # this file + whats-new.md -> windows/listing-data.csv
```

Partner Center can export all four listings as one CSV and take the edited file back
(**Store listings → Export/Import listings**). `listing-data.csv` is the last export, and the script
rewrites every text field in it from the copy below, checks each against the Store's limits, and
leaves the screenshot rows alone. Download a fresh export first if the listing has changed in the
browser since, because that file — not this one — is what carries the image assets.

What that fixed the first time it ran says why it exists. The Store was missing the product-feature
bullet about words no dictionary knows, written here for 0.5.0 and never pasted in; one bullet had
lost its last character to a bad paste (`exclude any ap`); the Russian What's-new still described
0.5.0 while English and Ukrainian described 0.6.0; and every description carried this file's
100-column line wraps as hard breaks, so the live English listing broke a line in the middle of
*"Type ghbdsn and it becomes / привіт"*. The script unwraps paragraphs, which is what the field
actually wants.

---

## English (en)

### Description

Typed in the wrong keyboard layout? Switcher3way spots it and fixes it. Type ghbdsn and it becomes
привіт, the layout switches, and you carry on. English, Ukrainian, Russian and Bulgarian — free,
offline and open source.

You know the moment: half a sentence in and you realise the layout was wrong. Switcher3way takes that
moment away.

It watches the word you are typing and, when the word is clearly in the wrong keyboard layout, retypes
it correctly and switches the layout for you. Not a guess on every word — only when the word makes
sense in another layout's language and nonsense in the current one. Short fragments and ambiguous
scraps are left alone, because a wrong fix is worse than a missed one.

Four languages, not two. Most layout fixers flip between two layouts. Switcher3way reads every layout
Windows has installed and checks each candidate against that language's dictionary, so English,
Ukrainian, Russian and Bulgarian all work together.

Words that exist in both Ukrainian and Russian — там, добре — go to whichever language you prefer, and
if a later word makes the phrase clearly the other one, the app goes back and corrects itself.

Names and jargon are handled too, even though no dictionary contains them. Type Kyiv with a Ukrainian
layout active and you get Лншм — a shape no Ukrainian word could have, while Kyiv is an entirely
ordinary English one. Switcher3way reads that difference and fixes it. Words that only look unusual
are left alone: a name you typed on purpose, camelCase, ALL-CAPS, code identifiers and abbreviations
without vowels all stay exactly as you typed them.

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
discarded the moment the word ends. Correcting a long phrase briefly places the corrected text on the
clipboard so it can be pasted in one go, and puts your previous clipboard contents straight back;
shorter corrections are typed and never touch it. This Store version makes no network connections at
all. Word checking uses dictionaries built into the app. The whole source is public under the MIT
licence.

BEFORE YOU START

Add both keyboard layouts in Windows first — English and Ukrainian, Russian or Bulgarian — or there is
nothing for the app to switch between. Switcher3way lives in the notification area and has no main window; a short
welcome flow appears the first time you run it.

Works wherever your keystrokes come from — a directly attached keyboard, Remote Desktop, a virtual
machine, a remapped keyboard, or the on-screen keyboard.

The interface is fully translated into English, Ukrainian, Russian and Bulgarian. Twelve more
languages are partly translated and fall back to English for anything not yet covered; the language
picker says which is which.

### Product features

- Fixes words typed in the wrong keyboard layout automatically, as you finish each word
- Four languages together — English, Ukrainian, Russian and Bulgarian — not just a two-layout toggle
- Checks every layout Windows has installed against that language's dictionary
- Names and jargon no dictionary contains are fixed by their shape, while deliberate names, camelCase, ALL-CAPS and vowel-less abbreviations are left alone
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

Lives in [`whats-new.md`](whats-new.md), alongside the other three languages, so the
four blocks can be copied into Partner Center without scrolling this file.

### Search terms

keyboard layout switcher
keyboard layout fixer
multilingual keyboard switch
language layout autocorrect

---

## Українська (uk)

### Опис

Набрали не в тій розкладці? Switcher3way це помітить і виправить. Наберіть ghbdsn — і це стане привіт,
розкладка перемкнеться, а ви просто продовжите писати. Англійська, українська, російська та
болгарська — безкоштовно, без інтернету, з відкритим кодом.

Знайомий момент: пів речення вже набрано, і аж тоді ви розумієте, що розкладка була не та.
Switcher3way прибирає цей момент.

Застосунок дивиться на слово, яке ви набираєте, і коли слово явно набране не в тій розкладці —
перенабирає його правильно та перемикає розкладку. Це не вгадування на кожному слові: виправлення
відбувається лише тоді, коли слово має сенс мовою іншої розкладки й не має сенсу поточною. Короткі
уривки та неоднозначні залишки лишаються недоторканими, бо помилкове виправлення гірше за пропущене.

Чотири мови, а не дві. Більшість подібних програм перемикається між двома розкладками. Switcher3way
читає всі розкладки, встановлені у Windows, і перевіряє кожен варіант словником відповідної мови —
тому англійська, українська, російська та болгарська працюють разом.

Слова, які існують і українською, і російською — там, добре — переходять у мову, яку ви обрали. А якщо
наступне слово робить фразу однозначно іншою мовою, застосунок повертається й виправляє себе сам.

Назви та професійний сленг теж виправляються, хоча їх немає в жодному словнику. Наберіть Kyiv з
українською розкладкою — і отримаєте Лншм: форма, якої не може мати жодне українське слово, тоді як
Kyiv — цілком звичайне англійське. Switcher3way бачить цю різницю й виправляє. А те, що лише виглядає
незвично, лишається недоторканим: навмисно набрана назва, camelCase, ВЕЛИКІ ЛІТЕРИ, ідентифікатори з
коду та скорочення без голосних зостаються такими, як ви їх набрали.

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
лише в пам'яті та відкидаються, щойно слово завершилося. Виправлення довгої фрази на мить кладе
виправлений текст у буфер обміну, щоб вставити його одним рухом, і одразу повертає ваш попередній вміст
буфера; коротші виправлення набираються й буфера не торкаються. Ця версія зі Store не робить жодних
мережевих з'єднань. Перевірка слів використовує словники, вбудовані в застосунок. Увесь вихідний код
відкритий за ліцензією MIT.

ПЕРЕД ПОЧАТКОМ

Спершу додайте у Windows обидві розкладки — англійську та українську, російську чи болгарську —
інакше застосунку не буде між чим перемикатися. Switcher3way живе в області повідомлень і не має головного вікна; під
час першого запуску з'явиться короткий вступний покроковий екран.

Працює незалежно від того, звідки надходять натискання клавіш — безпосередньо підключена клавіатура,
віддалений робочий стіл, віртуальна машина, перепризначена клавіатура чи екранна клавіатура.

Інтерфейс повністю перекладено англійською, українською, російською та болгарською. Ще дванадцять
мов перекладено частково — там, де перекладу ще немає, показується англійська; у виборі мови це
позначено.

### Можливості

- Автоматично виправляє слова, набрані не в тій розкладці, щойно слово завершено
- Чотири мови разом — англійська, українська, російська та болгарська, а не просто перемикач двох розкладок
- Назви та сленг, яких немає в словниках, виправляються за формою слова, а навмисні назви, camelCase, ВЕЛИКІ ЛІТЕРИ й скорочення без голосних лишаються незмінними
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

Lives in [`whats-new.md`](whats-new.md), alongside the other three languages, so the
four blocks can be copied into Partner Center without scrolling this file.

### Ключові слова

виправлення розкладки клавіатури
перемикання розкладок клавіатури
багатомовне введення тексту
безкоштовний перемикач розкладок
автоматичний перемикач клавіатури

---

## Русский (ru)

### Описание

Набрали не в той раскладке? Switcher3way это заметит и исправит. Наберите ghbdsn — и это превратится
в привіт, раскладка переключится, а вы просто продолжите писать. Английский, украинский, русский и
болгарский — бесплатно, без интернета, с открытым исходным кодом.

Знакомый момент: полфразы уже набрано, и только тогда вы понимаете, что раскладка была не та.
Switcher3way избавляет от этого момента.

Программа смотрит на слово, которое вы набираете, и когда слово явно набрано не в той раскладке —
перенабирает его правильно и переключает раскладку. Это не угадывание на каждом слове: исправление
происходит только если слово осмысленно на языке другой раскладки и бессмысленно на текущем. Короткие
обрывки и неоднозначные остатки остаются нетронутыми, потому что неверное исправление хуже
пропущенного.

Четыре языка, а не два. Большинство подобных программ переключается между двумя раскладками.
Switcher3way читает все раскладки, установленные в Windows, и проверяет каждый вариант словарём
соответствующего языка — поэтому английский, украинский, русский и болгарский работают вместе.

Слова, которые существуют и в украинском, и в русском — там, добре — переходят в тот язык, который вы
предпочли. А если следующее слово делает фразу однозначно другой, программа возвращается и исправляет
себя сама.

Названия и профессиональный сленг тоже исправляются, хотя их нет ни в одном словаре. Наберите Kyiv с
украинской раскладкой — и получите Лншм: форма, которой не может быть ни у одного украинского слова,
тогда как Kyiv — совершенно обычное английское. Switcher3way видит эту разницу и исправляет. А то, что
лишь выглядит необычно, остаётся нетронутым: намеренно набранное название, camelCase, ЗАГЛАВНЫЕ,
идентификаторы из кода и сокращения без гласных остаются такими, как вы их набрали.

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
в памяти и отбрасываются, как только слово закончилось. Исправление длинной фразы на мгновение кладёт
исправленный текст в буфер обмена, чтобы вставить его одним движением, и сразу возвращает ваше
предыдущее содержимое буфера; более короткие исправления набираются и буфер не трогают. Эта версия из
Store не устанавливает никаких сетевых соединений. Проверка слов использует словари, встроенные в
программу. Весь исходный код открыт по лицензии MIT.

ПЕРЕД НАЧАЛОМ

Сначала добавьте в Windows обе раскладки — английскую и украинскую, русскую или болгарскую — иначе
программе не между чем переключаться. Switcher3way живёт в области уведомлений и не имеет главного окна; при первом
запуске появится короткий вступительный экран.

Работает независимо от того, откуда приходят нажатия клавиш — напрямую подключённая клавиатура,
удалённый рабочий стол, виртуальная машина, переназначенная клавиатура или экранная клавиатура.

Интерфейс полностью переведён на английский, украинский, русский и болгарский. Ещё двенадцать языков
переведены частично — там, где перевода ещё нет, показывается английский; в выборе языка это
отмечено.

### Возможности

- Автоматически исправляет слова, набранные не в той раскладке, как только слово закончено
- Четыре языка вместе — английский, украинский, русский и болгарский, а не просто переключатель двух раскладок
- Проверяет каждую установленную в Windows раскладку словарём соответствующего языка
- Названия и сленг, которых нет в словарях, исправляются по форме слова, а намеренные названия, camelCase, ЗАГЛАВНЫЕ и сокращения без гласных остаются нетронутыми
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

Lives in [`whats-new.md`](whats-new.md), alongside the other three languages, so the
four blocks can be copied into Partner Center without scrolling this file.

### Ключевые слова

переключатель раскладки
исправление раскладки клавиатуры
переключение раскладки автоматически
исправитель неправильной раскладки
смена раскладки клавиатуры
автоматическое исправление раскладки
переключатель языков клавиатуры

## Български (bg)

### Описание

Писали сте с грешна клавиатурна подредба? Switcher3way го забелязва и го поправя. Напишете pdeokf —
и се получава заедно, подредбата се сменя, а вие продължавате нататък. Английски, украински, руски и
български — безплатно, без интернет, с отворен код.

Познат момент: половин изречение вече е написано и чак тогава осъзнавате, че подредбата е била
грешна. Switcher3way премахва този момент.

Приложението следи думата, която пишете, и когато тя явно е написана с грешна подредба, я
пренаписва правилно и сменя подредбата вместо вас. Това не е налучкване при всяка дума: поправка има
само когато думата има смисъл на езика на друга подредба и няма смисъл на текущия. Кратките откъси и
двусмислените остатъци остават недокоснати, защото погрешната поправка е по-лоша от пропуснатата.

Четири езика, а не два. Повечето подобни програми превключват между две подредби. Switcher3way чете
всички подредби, инсталирани в Windows, и проверява всеки вариант с речника на съответния език —
затова английският, украинският, руският и българският работят заедно.

Думи, които съществуват и в украинския, и в руския — там, добре — отиват към езика, който сте
предпочели. А ако следваща дума направи фразата еднозначно на другия език, приложението се връща и се
поправя само.

Имената и професионалният жаргон също се поправят, макар да ги няма в нито един речник. Напишете
Linux с активна българска подредба — и получавате Всхкй: форма, каквато никоя българска дума не може
да има, докато Linux е съвсем обикновена английска дума. Switcher3way вижда тази разлика и я поправя.
А това, което само изглежда необичайно, остава недокоснато: нарочно написано име, camelCase, ГЛАВНИ
БУКВИ, идентификатори от код и съкращения без гласни остават точно както сте ги написали.

ПОПРАВЯЙТЕ И САМИ

Натиснете клавиша-тригер — по подразбиране двойно Ctrl, също Pause/Break, F9 и други — за да
преобразувате последната написана дума. Маркирайте текст и натиснете тригера, за да преобразувате
маркираното. Натиснете отново, без да пишете между натисканията, за да минете през останалите
подредби, и още веднъж — за да върнете първоначалния текст. Тригерът ви се подчинява дори там,
където автоматичната поправка се въздържа.

Всяка поправка показва малък надпис под поправената дума с напомняне за клавиша за отмяна, така че
промяната никога не е незабележима.

КЪДЕТО ПРИЛОЖЕНИЕТО НЕ СЕ НАМЕСВА

Полетата за пароли са изключени, включително полетата за пароли в уеб страници. Мениджърите на пароли
и терминалите са изключени по подразбиране, а вие можете да изключите всяко друго приложение. Отделни
думи могат да се добавят към списък «никога да не се преобразуват» — с едно щракване, когато
поправката е била излишна — или към списък «винаги да се преобразуват».

Спрете работата за половин час, за час или до рестартиране. Изключете автоматичната поправка и
оставете само ръчния тригер. Разрешете подредбата да се помни за всяко приложение поотделно, за да ви
връща смяната на прозорци там, където сте били.

ПОВЕРИТЕЛНОСТ ПО ЗАМИСЪЛ

Нищо от написаното не се съхранява и не се изпраща. Натисканията на клавиши за текущата дума се пазят
само в паметта и се изхвърлят веднага щом думата завърши. Поправката на дълга фраза за момент поставя
поправения текст в клипборда, за да бъде вмъкнат наведнъж, и веднага връща предишното ви съдържание;
по-кратките поправки се изписват и не докосват клипборда. Тази версия от Store не прави никакви
мрежови връзки. Проверката на думите използва речници, вградени в приложението. Целият изходен код е
публичен под лиценза MIT.

ПРЕДИ ДА ЗАПОЧНЕТЕ

Първо добавете в Windows и двете подредби — английската и българската, украинската или руската —
иначе няма между какво да се превключва. Switcher3way живее в областта за уведомления и няма главен
прозорец; при първото стартиране се появява кратък начален екран.

Работи независимо откъде идват натисканията на клавиши — пряко свързана клавиатура, отдалечен работен
плот, виртуална машина, преназначена клавиатура или екранната клавиатура.

Интерфейсът е преведен изцяло на английски, украински, руски и български. Още дванадесет езика са
преведени частично: където превод още няма, се показва английски, а изборът на език го отбелязва.

### Възможности

- Автоматично поправя думи, написани с грешната клавиатурна подредба, веднага щом думата завърши
- Четири езика заедно — английски, украински, руски и български, а не просто превключвател между две подредби
- Проверява всяка инсталирана в Windows подредба с речника на съответния език
- Имена и жаргон, каквито няма в речниците, се поправят по формата на думата, а нарочните имена, camelCase, ГЛАВНИ БУКВИ и съкращенията без гласни остават непроменени
- Думи, валидни и в украинския, и в руския, следват вашия избор и се поправят по-късно, ако фразата се окаже друга
- Ръчен тригер — по подразбиране двойно Ctrl — преобразува последната дума или маркирания текст
- Повторно натискане минава през останалите подредби, още едно — отменя
- Надпис под поправената дума показва какво се е променило и как да се отмени
- Полетата за пароли, мениджърите на пароли и терминалите не се засягат; можете да изключите всяко приложение
- Списъци «никога да не се преобразува» и «винаги да се преобразува» за отделни думи
- Пауза за половин час, за час или до рестартиране
- По желание — запомняне на подредбата за всяко приложение
- Никакви мрежови връзки, никаква телеметрия, нищо не се съхранява — отворен код под лиценза MIT

### Какво е новото

Lives in [`whats-new.md`](whats-new.md), alongside the other three languages, so the
four blocks can be copied into Partner Center without scrolling this file.

### Ключови думи

смяна на подредбата
поправяне на подредбата
грешна клавиатурна подредба
автоматична смяна на езика
превключвател на подредби
кирилица
безплатен превключвател

---

---

## Notes on choices made here

**The hook is the first paragraph of Description, not a separate field.** The listing form has no short
description, and previews take the opening lines — so the description leads with the problem and the
example rather than with "Switcher3way is an application that…".

**No markdown, no backticks.** The Description box renders plain text; asterisks and backticks would
appear literally. Paragraph breaks and the ALL-CAPS section headings are the only structure available.

**The search terms here are the ones Partner Center holds.** The first draft of this file invented
its own — shorter, and never uploaded — so for a year the file and the Store disagreed and nobody
could tell which was right. Whatever is written here is now what `build-listing-csv.py` uploads.

**No competitor names in the search terms.** "Punto Switcher" and similar would pull real traffic, but
they are other people's product names and Store policy 10.1.1 rejects listings that use trademarks the
publisher does not own.

**The examples are honest, and now they are pinned.** ghbdsn → привіт is what the app actually
produces with an English layout active and Ukrainian preferred — the same string the self-test prints.
Don't swap in an example without checking that it converts; `StoreListingExampleTests` asserts all four
of them against the real dictionaries and the real layout tables, so a dictionary or resolver change
that falsifies the copy fails the build instead of reaching a reader who tries it.

**The Bulgarian examples are true of Bulgarian (Typewriter) and only that one.** Windows offers five
Bulgarian layouts, and `pdeokf` means nothing on the phonetic ones. Typewriter — BDS — is what you get
when you tell Windows to add Bulgarian, so it is what the copy assumes; the table was read off Windows
with `ToUnicodeEx` rather than copied from a reference. `pdeokf` → заедно was also verified end to end
on a packaged build, and Linux → Всхкй is the names-and-jargon example because a string with no vowel
at all cannot be a Bulgarian word while Linux is an ordinary English one.

**No "physical keyboard required" claim.** It was true until 0.2.7: the hook ignored all injected input,
which made the app inert on a tablet using the on-screen keyboard — and failed Store certification twice.
Our own synthesized keys are now tagged, so everything else counts as real typing.

**"Sixteen languages" was never a count of anything.** The first draft called the interface
"available in 16 languages" because `Loc.cs` held 16 language blocks — twelve of which held a third
of the strings, so most of Settings and all of onboarding came out in English. `check-localization.py`
counts the strings, and `--require` turns the sentence in the copy into something a build can fail on.

**Every claim needs checking against the code, not memory.** Three were wrong. Two in the first
draft, and one that survived a year: the Ukrainian and Russian descriptions still said a physical
keyboard was required and that the on-screen keyboard was invisible to the app. That stopped being
true in 0.2.7 — the note below records it being removed — but it was only removed from the English
text, so the two translations went on making a claim that had already failed certification twice. That
is the argument for editing all four listings in one pass rather than the one being read. The
pause durations are 30 minutes / 1 hour / until restart (`TrayFlyoutWindow.xaml.cs`), not "ten minutes".
And the interface was described as "available in 16 languages" on the strength of `Loc.cs` holding 16
language blocks — but the WinUI rewrite had added ~50 strings hard-coded in English, so Ukrainian and
Russian users saw most of Settings and all of onboarding in English. That is now fixed in the app for
en/uk/ru; the other 13 languages fall back to English for those strings and the picker labels them
partly translated. Recheck if the copy is reused for a later version.

---

## Copyright and trademark info

One line per listing, 200-character limit. It names the project's own copyright first, then the upstream
fork and the dictionary licences — the MPL 1.1 Ukrainian and Bulgarian dictionaries are the ones with a
real notice obligation, and the `LICENSE` shipped in the package carries the full texts. Bulgarian is
tri-licensed upstream (GPL-2 / LGPL-2 / MPL-1.1) and we rely on the MPL branch, which is why it is
grouped with Ukrainian rather than listed separately; the evidence is in `dict/bg.license`.

- **en** — (c) 2026 IronMade. MIT License. A fork of RuSwitcher, (c) 2025 Rashns. Bundled Hunspell dictionaries: en/ru BSD, uk/bg MPL 1.1. Full notices ship with the app.
- **uk** — (c) 2026 IronMade. Ліцензія MIT. Форк RuSwitcher, (c) 2025 Rashns. Вбудовані словники Hunspell: en/ru BSD, uk/bg MPL 1.1. Повні тексти постачаються із застосунком.
- **ru** — (c) 2026 IronMade. Лицензия MIT. Форк RuSwitcher, (c) 2025 Rashns. Встроенные словари Hunspell: en/ru BSD, uk/bg MPL 1.1. Полные тексты поставляются с программой.
- **bg** — (c) 2026 IronMade. Лиценз MIT. Форк на RuSwitcher, (c) 2025 Rashns. Вградени речници Hunspell: en/ru BSD, uk/bg MPL 1.1. Пълните текстове се доставят с приложението.

Use the © character rather than "(c)" if the field accepts it — these are written in ASCII only so they
survive being copied out of this file.

---

## Screenshots

At least one is required; up to 10 are allowed. Each must be **1366×768 or larger** — a bare app window
is too small, so compose each shot on a full 1920×1080 screen rather than cropping tight to the window.
PNG. Captions are a separate field per image, 200 characters each.

**Screenshots and their captions are not generated from this file.** Each image is uploaded per
listing language and gets its own asset URL, and a caption is bound to an image slot rather than to
the text below — the English and Russian listings use shots 1, 2, 4, 5 and 6, the Ukrainian one uses
all six. `build-listing-csv.py` therefore leaves both alone. The Bulgarian listing has no images yet;
the Store requires at least one, so they have to be uploaded in Partner Center before that listing can
be submitted, and the Bulgarian captions below are ready to paste when they are.

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
- **bg** — Напишете дума с грешна подредба и продължете. Switcher3way я пренаписва и сменя подредбата, като показва какво се е променило и как да го отмените.

### 2. The tray flyout

The status header with the current layout, the quick toggles and the Pause submenu.

- **en** — Everything from the notification area: current layout, master switch, Auto-fix, and pause for half an hour, an hour or until restart.
- **uk** — Усе з області повідомлень: поточна розкладка, головний вимикач, автовиправлення та пауза на півгодини, годину чи до перезапуску.
- **ru** — Всё из области уведомлений: текущая раскладка, главный выключатель, автоисправление и пауза на полчаса, час или до перезапуска.
- **bg** — Всичко от областта за уведомления: текуща подредба, главен ключ, автоматична поправка и пауза за половин час, час или до рестартиране.

### 3. Welcome flow, step 2 — "Your layouts"

The three detected layouts with their "Dictionary ready" pills. This is the three-language claim made
visible, and it is the clearest single answer to "how is this different from a two-layout switcher".

- **en** — Nothing to configure: Switcher3way reads every layout Windows has installed and checks each one against that language's dictionary.
- **uk** — Нічого не треба налаштовувати: Switcher3way читає всі встановлені у Windows розкладки й перевіряє кожну словником її мови.
- **ru** — Ничего не нужно настраивать: Switcher3way читает все установленные в Windows раскладки и проверяет каждую словарём её языка.
- **bg** — Няма какво да се настройва: Switcher3way чете всички инсталирани в Windows подредби и проверява всяка с речника на нейния език.

### 4. Settings → General

The trigger picker open, showing Double Ctrl selected with Pause/Break and F9 beneath it.

- **en** — Pick the trigger that suits your keyboard. Tap it to convert the last word or a selection; tap again to cycle layouts or undo.
- **uk** — Виберіть тригер, який пасує вашій клавіатурі. Натисніть, щоб конвертувати останнє слово або виділення; ще раз — щоб перебрати розкладки чи скасувати.
- **ru** — Выберите триггер под свою клавиатуру. Нажмите, чтобы преобразовать последнее слово или выделение; ещё раз — чтобы перебрать раскладки или отменить.
- **bg** — Изберете тригера, който пасва на клавиатурата ви. Натиснете за последната дума или маркираното; още веднъж — за да минете през подредбите или да отмените.

### 5. Settings → Auto-fix

The preferred-language choice for words that are valid in both Ukrainian and Russian.

- **en** — Words that exist in both Ukrainian and Russian go to the language you prefer — and are corrected later if the rest of the phrase says otherwise.
- **uk** — Слова, які існують і українською, і російською, конвертуються у задану вами розкладку — а згодом виправляються, якщо решта фрази іншою мовою.
- **ru** — Слова, которые есть и в украинском, и в русском, конвертируются в выбранную вами раскладку — а позже исправляются, если далее фраза на другом языке.
- **bg** — Думи, които съществуват и в украинския, и в руския, отиват в предпочитания от вас език — и се поправят по-късно, ако останалата част от фразата казва друго.

### 6. Settings → the exceptions list

The unified list with a password manager showing its "always off" badge.

- **en** — Password fields are never touched. Password managers and terminals are excluded by default, and you can exclude any app or single word.
- **uk** — Поля паролів не зачіпаються ніколи. Менеджери паролів і термінали виключені типово, і ви можете виключити будь-який застосунок чи окреме слово.
- **ru** — Поля паролей не затрагиваются никогда. Менеджеры паролей и терминалы исключены по умолчанию, и вы можете исключить любое приложение или отдельное слово.
- **bg** — Полетата за пароли никога не се докосват. Мениджърите на пароли и терминалите са изключени по подразбиране, а вие можете да изключите всяко приложение или отделна дума.

### Before you shoot

- **One theme throughout.** The app follows the system theme; a listing that mixes dark and light shots
  looks careless. Dark reads well for shots 2–6.
- **Clean the frame.** No repository paths, editor windows, personal file names, chat notifications or
  taskbar badges — the hero shot in particular wants an empty Notepad on a plain desktop.
- **Don't crop to the window.** A 560×620 window on its own is under the minimum and will be rejected;
  leave it on the full screen.
- **Same layout pair in every shot** (English + Ukrainian, say), so the story stays consistent.
