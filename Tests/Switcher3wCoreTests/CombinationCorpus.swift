import Foundation

/// Prose for `LanguageCombinationTests`: ordinary writing, at the word lengths and frequencies people
/// type, one passage per language.
///
/// `en` and `uk` are the Windows port's `PrecisionRecallCorpus`
/// (`windows/tests/Switcher3way.Core.Tests/Corpus.cs`), copied verbatim so both ports score against
/// the same text. `ru`, `bg`, `de` and `fr` were written for this measurement on the same pattern:
/// someone describing their work, an evening out, a visit to their parents. They include the
/// language's own capitalisation, apostrophes and hyphens, because the keep measurement types them
/// as they are.
enum CombinationCorpus {
    static let prose: [String: String] = [
        "en": """
        I want to write a few sentences in English so the app can be checked against ordinary text
        as well. When I type quickly I make mistakes, and that is fine, because nobody writes
        without them. What matters is that the tool does not try to fix what is not broken. If I
        drop a letter from a word, that is a typo and not a different keyboard layout. We talked
        about this with my colleagues and agreed it is better to leave a word alone than to turn
        it into something nobody can read. I like my job a lot, but it takes too much time. There
        has to be a balance between work and rest, and tomorrow will be a better day.
        My name is Helen and I work as an editor at a small publishing house near the edge of
        town. Every day I read dozens of pages of somebody else's writing, correct mistakes,
        check quotations and write short letters to authors. I enjoy the work, although it can
        be hard to concentrate when the road outside is noisy. My computer is old and the
        keyboard sticks a little, so letters sometimes double up or vanish altogether, which
        means I reread everything I write far more often than I would like to admit.
        Last night a friend and I went to the theatre. The play was long but very interesting,
        and afterwards we stood at the bus stop talking about it for ages. It started raining
        on the way home and I remembered that my umbrella was still at the office.
        Next week I plan to take a few days off and visit my parents in the village. It is
        quiet there, the air smells of apples, and you can hear the roosters in the morning.
        My mother always bakes a pie when I arrive and tells me that I have lost weight.
        Lately I have been thinking about how quickly time passes. It feels like I finished
        university only recently, and yet ten years have gone by. Friends have scattered to
        different cities and countries, we rarely meet, and mostly we send each other messages.
        But when we do meet, the conversation starts as though we had never been apart at all.
        """,
        "uk": """
        Сьогодні я хочу написати кілька речень українською мовою, щоб перевірити, як програма
        поводиться зі звичайним текстом. Коли я друкую швидко, то часто помиляюся, і це нормально,
        адже ніхто не пише без помилок. Важливо, щоб програма не намагалася виправити те, що
        виправляти не треба. Наприклад, якщо я пропущу одну літеру в слові, то це просто описка,
        а не інша розкладка клавіатури. Ми з колегами обговорювали це питання і дійшли висновку,
        що краще залишити слово без змін, ніж перетворити його на щось незрозуміле. Я дуже люблю
        свою роботу, але іноді вона забирає надто багато часу. Треба знайти баланс між роботою
        та відпочинком. Завтра буде новий день, і все вийде добре.
        Мене звати Олена, і я працюю редакторкою в невеликому видавництві на околиці міста.
        Щодня я читаю десятки сторінок чужого тексту, виправляю помилки, звіряю цитати та
        пишу короткі листи авторам. Робота мені подобається, хоча буває важко зосередитися,
        коли за вікном шумить дорога. Мій ноутбук уже старий, клавіатура трохи заїдає, тому
        літери іноді подвоюються або зникають зовсім. Через це я часто перечитую написане.
        Учора ввечері ми з подругою ходили до театру. Вистава була довга, але дуже цікава,
        і ми потім довго обговорювали її на зупинці, чекаючи автобус. Дорогою додому пішов
        дощ, і я згадала, що парасолька залишилася на роботі. Довелося бігти під деревами.
        Наступного тижня планую взяти кілька вихідних і поїхати до батьків у село. Там тихо,
        пахне яблуками, а вранці чути півнів. Мама завжди пече пиріг, коли я приїжджаю, і
        каже, що я схудла. Батько показує город і розповідає, як цього року вродила картопля.
        Я люблю ці поїздки, бо вони нагадують мені про дитинство, коли все здавалося простим.
        Останнім часом багато думаю про те, як швидко минає час. Здається, ще недавно я
        закінчувала університет, а вже минуло десять років. Друзі виїхали по різних
        містах і країнах, ми бачимося рідко, здебільшого пишемо одне одному повідомлення.
        Але коли зустрічаємося, розмова починається так, ніби ми не розлучалися ні на день.
        Треба буде написати сестрі, вона давно не озивалася. Може, зателефоную їй увечері,
        якщо не буде пізно. У неї маленька дитина, тому вона рідко має вільну хвилину.
        Взимку ми хотіли поїхати в гори, але квитки виявилися надто дорогими, і ми залишилися
        вдома. Натомість гуляли парком, пили гарячий чай і дивилися старі фільми. Це теж було
        добре, хоча зовсім не так, як планувалося. Іноді найкращі дні виходять випадково.
        """,
        "ru": """
        Сегодня я хочу написать несколько предложений по-русски, чтобы проверить, как программа
        справляется с обычным текстом. Когда я печатаю быстро, я часто ошибаюсь, и это нормально, ведь
        никто не пишет без ошибок. Важно, чтобы программа не пыталась исправить то, что исправлять не
        нужно. Например, если я пропущу одну букву в слове, это просто опечатка, а не другая раскладка
        клавиатуры. Мы с коллегами обсуждали этот вопрос и пришли к выводу, что лучше оставить слово как
        есть, чем превратить его в что-то непонятное. Я очень люблю свою работу, но иногда она отнимает
        слишком много времени. Нужно найти баланс между работой и отдыхом. Завтра будет новый день, и всё
        получится. Меня зовут Анна, я работаю переводчиком в небольшой компании недалеко от вокзала.
        Каждый день я читаю длинные письма, отвечаю клиентам и проверяю чужие тексты. Вчера вечером мы с
        братом ходили в кино. Фильм был длинный, но интересный, и потом мы долго спорили о нём на улице,
        пока ждали такси. По дороге домой пошёл снег, и я вспомнила, что оставила шарф в офисе. На
        следующей неделе я хочу взять отпуск и поехать к родителям на дачу. Там тихо, пахнет соснами, а по
        утрам слышно птиц. Мама всегда печёт пирог, когда я приезжаю, и говорит, что я похудела. Отец
        показывает огород и рассказывает, как в этом году уродилась картошка. Я люблю эти поездки, потому
        что они напоминают мне о детстве, когда всё казалось простым и понятным. Друзья разъехались по
        разным городам, мы видимся редко и в основном пишем друг другу сообщения. Но когда встречаемся,
        разговор начинается так, будто мы никогда не расставались.
        """,
        "bg": """
        Днес искам да напиша няколко изречения на български, за да проверя как програмата се справя с
        обикновен текст. Когато пиша бързо, често греша, и това е нормално, защото никой не пише без
        грешки. Важно е програмата да не се опитва да поправя това, което не трябва. Например, ако
        пропусна една буква в думата, това е просто печатна грешка, а не друга клавиатурна подредба.
        С колегите обсъждахме този въпрос и решихме, че е по-добре думата да остане непроменена,
        отколкото да се превърне в нещо неразбираемо. Много обичам работата си, но понякога тя отнема
        твърде много време. Трябва да се намери баланс между работата и почивката. Утре ще бъде нов
        ден и всичко ще се нареди. Казвам се Елена и работя като редактор в малко издателство в края
        на града. Всеки ден чета десетки страници чужд текст, поправям грешки и пиша кратки писма на
        авторите. Работата ми харесва, макар че понякога е трудно да се съсредоточа, когато навън е
        шумно. Компютърът ми е стар и клавиатурата засича, затова буквите понякога се удвояват или
        изчезват. Вчера вечерта с приятелка ходихме на театър. Представлението беше дълго, но много
        интересно, и после дълго го обсъждахме на спирката, докато чакахме автобуса. По пътя към
        вкъщи заваля дъжд и си спомних, че чадърът остана в офиса. Следващата седмица смятам да си
        взема няколко почивни дни и да отида при родителите си на село. Там е тихо, мирише на ябълки,
        а сутрин се чуват петлите. Майка ми винаги пече баница, когато пристигна, и казва, че съм
        отслабнала. Баща ми показва градината и разказва как тази година е родил картофът. Обичам
        тези пътувания, защото ми напомнят за детството, когато всичко изглеждаше просто. Приятелите
        ми се разпръснаха по различни градове и държави, виждаме се рядко и най-често си пишем
        съобщения. Но когато се срещнем, разговорът започва така, сякаш никога не сме се разделяли.
        """,
        "de": """
        Heute möchte ich ein paar Sätze auf Deutsch schreiben, um zu prüfen, wie das Programm mit
        gewöhnlichem Text umgeht. Wenn ich schnell tippe, mache ich oft Fehler, und das ist normal, denn
        niemand schreibt ganz ohne sie. Wichtig ist, dass das Programm nicht versucht, etwas zu
        korrigieren, das gar nicht falsch ist. Wenn ich zum Beispiel einen Buchstaben in einem Wort
        vergesse, ist das ein Tippfehler und keine andere Tastaturbelegung. Wir haben mit den Kollegen
        darüber gesprochen und waren uns einig, dass es besser ist, ein Wort so zu lassen, wie es ist,
        als es in etwas Unverständliches zu verwandeln. Ich mag meine Arbeit sehr, aber manchmal kostet
        sie zu viel Zeit. Man muss ein Gleichgewicht zwischen Arbeit und Erholung finden. Morgen ist ein
        neuer Tag, und dann wird alles gut. Ich heiße Jana und arbeite als Lektorin in einem kleinen
        Verlag am Rand der Stadt. Jeden Tag lese ich viele Seiten fremder Texte, korrigiere Fehler und
        schreibe kurze Briefe an die Autoren. Die Arbeit gefällt mir, obwohl es schwer ist, sich zu
        konzentrieren, wenn draußen die Straße laut ist. Mein Laptop ist schon alt, und die Tastatur
        klemmt ein wenig, deshalb verdoppeln sich manchmal Buchstaben oder verschwinden ganz. Gestern
        Abend war ich mit einer Freundin im Theater. Das Stück war lang, aber sehr spannend, und danach
        haben wir noch lange an der Haltestelle darüber geredet, während wir auf den Bus gewartet haben.
        Auf dem Heimweg fing es an zu regnen, und mir fiel ein, dass mein Schirm noch im Büro lag.
        Nächste Woche will ich ein paar Tage freinehmen und meine Eltern auf dem Dorf besuchen. Dort ist
        es ruhig, es riecht nach Äpfeln, und morgens hört man die Hähne. Meine Mutter backt immer einen
        Kuchen, wenn ich komme, und sagt, dass ich dünner geworden bin. Mein Vater zeigt mir den Garten
        und erzählt, wie die Kartoffeln in diesem Jahr gewachsen sind. Ich liebe diese Reisen, weil sie
        mich an meine Kindheit erinnern, als alles einfach schien.
        """,
        "fr": """
        Aujourd'hui, je voudrais écrire quelques phrases en français pour vérifier comment le
        programme se comporte avec un texte ordinaire. Quand je tape vite, je fais souvent des fautes, et
        c'est normal, parce que personne n'écrit sans erreurs. Ce qui compte, c'est que le programme
        n'essaie pas de corriger ce qui n'est pas faux. Par exemple, si j'oublie une lettre dans un mot,
        c'est une simple faute de frappe et pas une autre disposition du clavier. Nous en avons parlé avec
        mes collègues, et nous sommes d'accord qu'il vaut mieux laisser un mot tel quel plutôt que de le
        transformer en quelque chose d'illisible. J'aime beaucoup mon travail, mais parfois il me prend
        trop de temps. Il faut trouver un équilibre entre le travail et le repos. Demain sera un nouveau
        jour, et tout ira bien. Je m'appelle Claire et je travaille comme correctrice dans une petite
        maison d'édition au bord de la ville. Chaque jour, je lis des dizaines de pages écrites par
        d'autres, je corrige des fautes et j'écris de courtes lettres aux auteurs. Le travail me plaît,
        même s'il est difficile de se concentrer quand la rue est bruyante. Mon ordinateur est vieux et
        le clavier accroche un peu, alors les lettres se doublent parfois ou disparaissent. Hier soir,
        je suis allée au théâtre avec une amie. La pièce était longue mais très intéressante, et ensuite
        nous en avons parlé longtemps à l'arrêt en attendant le bus. Sur le chemin du retour, il a
        commencé à pleuvoir, et je me suis rappelé que mon parapluie était resté au bureau. La semaine
        prochaine, je compte prendre quelques jours de congé et rendre visite à mes parents à la
        campagne. C'est calme là-bas, ça sent les pommes, et le matin on entend les coqs. Ma mère fait
        toujours une tarte quand j'arrive et me dit que j'ai maigri. Mon père me montre le jardin et
        raconte comment les pommes de terre ont poussé cette année. J'aime ces voyages parce qu'ils me
        rappellent mon enfance, quand tout semblait simple.
        """,
    ]
}
