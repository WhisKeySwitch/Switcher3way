namespace Switcher3way.Core.Tests;

/// <summary>
/// Natural prose in both languages, at the word lengths and frequencies people actually write.
/// Shared so every measurement in this suite is scored against the same text.
/// </summary>
internal static class PrecisionRecallCorpus
{
    public const string Uk = @"
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
        добре, хоча зовсім не так, як планувалося. Іноді найкращі дні виходять випадково.";

    public const string En = @"
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
        But when we do meet, the conversation starts as though we had never been apart at all.";
}
