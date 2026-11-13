#if canImport(AppKit)
import XCTest
@testable import Switcher3wCore

/// Every string under four letters that a Cyrillic dictionary accepts, classified once: a word people
/// type (it is in `ShortWords`) or noise (it is in `noise` below).
///
/// The short-word lists used to be checked only against sample prose, and a word the prose never used
/// could be missing unseen: `він` and `чим` were, and a fortnight's field log refused `він` nine times
/// (`convert-words-left-behind`). The dictionary's accepted strings are a finite set, and exactly the
/// set where the list's verdict matters. A string the dictionary rejects is never a hit, so the list
/// cannot affect it. So the review covers that set completely, and a string in neither place fails the
/// test by name.
///
/// When a macOS update changes a dictionary, this fails with the new strings listed: classify them.
/// `SWITCHER3W_REVIEW_OUT=<path>` also writes the unclassified strings there, one `lang<TAB>word` per line.
@MainActor
final class ShortWordReview: XCTestCase {

    static let alphabets: [String: String] = [
        "uk": "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя",
        "ru": "абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
        "bg": "абвгдежзийклмнопрстуфхцчшщъьюя",
    ]

    /// Accepted by the dictionary, typed by nobody as a word: lone consonants, abbreviations without
    /// their dots, syllables, Scrabble-only and obsolete forms. Whitespace-separated, per language.
    static let noise: [String: String] = [
        "uk": """
            аг аги аго агу ад аде ади аді аду аз аза азе ази азі азу айв
            ант ану ара аре ари арі ару аса асе аси асі асу аур ахи ач ба
            баї баю бая беж беї бей бел бер бею бея бив бий бик біб бір боа
            бой бон боя буд буї бур бут буч бую буя ва ваб важ ваї ван вед
            веж вив виз вин вис виш ві віг віт во вої вол вою воя г гаг
            гає гал гар геп гею гея гик гир гін год гоу гри грі гро гру гу
            гув гум гун гут ґ ґав д дак даш дек ден дер дин диш ді дів
            дм дми дму дод дон дот дох дою дук дур е еве екю елі ель елю
            еля ем ер еро ест ет ети еті ету ємо єн єна єни єні єно єну
            єра єси єті жав жаг жал жде жди жду жер жми жни жуп зви зек зик
            зів зли злу зна зоб зол зри зрю и ід ідо ієн іже ікр імя ін
            іст іт іті іту іч ї їда їди їді їдо їже їзд їси йно йог йот
            йю к кав кає кай кал кап кар кас каш каю кед кер кет кил кип
            кис кия кіз кіл кім кін кіп кір кіс кіш кой кок кол ком кою крі
            кру кув кує куй кул кун куп куш кую л лаг лаж лаз лам лан лат
            леє лез леї лей лем лен лес лею лея либ лив лий лик лин лі ліґ
            лії лій лір лію лія лої лон лою лоя луб луж луз луо луп люб ляд
            ляж лям ляп лях лящ м маґ маж маз ман мар ме мес мет меш мил
            мис мі мів міс міх мла мли млі мло млу мне мни мну мок мор мре
            мри мру му мус муч мщу н най нал нар ней нео неф нив ниє ний
            нию ній нір ніц нко нош нут ню оаз оба обі обр огр од оди оді
            одо оду ом ома оме оми омі ому она оне они ону орд оре ори орт
            орю ос осе осо ост ота п па пав паз паї пай пак пал пап пат
            паш пащ паю пед пек пер пик пих пі пій піл пін піп пір піс пні
            пню пня поц пою пре прі пру прю пря псе псі псу пуд пуз пук пум
            пуп пут пущ р рає раї рал рва ре реє реї рей рею рея рже ржи
            рив риє риз рий рик рил рию різ ріп роб род рож роз рої рол рос
            рою роя руб руд рун руш ряс рях с саг саж сак сан сап се сеє
            сей сем сер сим сип сит сих сич сі сіє сії сій сіл сін сіп сіх
            сію ска сне сни сні сну сню сов соє сої сот соф сох сою ссе сси
            ссу ста су сур суч суш сци сцю сю сюр сюю ся сяй сям сяя т
            тав таж таї тал тар тат таю тая тві теґ теє тез тек тер тет теч
            тещ тил тин тис тиф тич тиш тів тіг тії тік тім тіш тла тле тлі
            тло тлу тлю тля тог тол тор тре тру туб туг тує туї туй тук туф
            тую туя тче тчи тчу тюк тяг тяж тям ув уві уде уії уїк уй ули
            ум ума уме уми умі уму урн уси уха ухо уху уюю уяя ф фа фаг
            фаз фас фат феє фей фею фін фіф фол фот фрі фуг фур фут х хан
            хащ хиб хиж хну хо хол ху худ хук ц цап цеє цеп ців ціп ція
            цюю цяя ч чад чаї чан чаш чин чіл чіп чот чуд чуй чум ш шаг
            шал шат шаф шва шве шви шві шву шив шиє ший шил шип шир шле шли
            шоп шуб щ щез щир щік щук ь ю юга юги юго югу юзі юна юне
            юні юно юну юра юрб юри юрі юро юрт юру ют юта юте юти юті юту
            яв ява яви яві яво яву яг яга ягу язв яйл яки яко ям ямо яо
            яп яра яре яри ярі яро яру ярю яса яті ять ятю ятя яче
            """,
        "ru": """
            аак аб аба абс абу ав ава аве аву авы агр агу ада аде аду ады
            аз аза азе азу азы аи аил аир айв айе айн ака аки ала але али
            алы аль ами амт ан ант ап апп апр ара арб арг аре ару арч ары
            аса асе асу асы атм ату аур афт ахи аэд аяк аят ба бае баи бат
            баю бая ббс бе бед бее беж беи бел бен беф бею бея би бив биг
            бил блт блю боа бод бое бои бол бон боя буе буж буи буй бур бут
            буц буч буш бую буя быы бэр бяк ва ваг важ ваз вап ве вед веж
            вей вен вер вех веч вею вея вёз вёл вёх вив виз вик вил вин вир
            вис вит виц вич влк вов вое вои вок вом воч вою воя впб ври всу
            ву вуе вуи вуй вул вую вуя вчь вши выв вые выи вый выю выя вяз
            вял г гаг гак гао гас гау гаш гаю гее гез геи гем гер гею гея
            гёз гиб гиг гик гит гиф гл гое гож гои гой гоу гою гоя гуд гуж
            гуз гун гущ гэг гэп д даа даб дав дак дан дао дев дез дек дер
            дёр джа джи дзю ди дик дин дли длю дн дож доз дои дол доп дор
            дос дот дох дою доя др дув дуг дуд дуй дун дур дут дуя дыб дюж
            дюк е ебк ебл ебц ебя ев ед едк едя ежа еже ежи ежу езд ел
            еле емк епт ере ери ерш ерь ерю еря еси ест ё ёжа ёмк ёрш жа
            жаб жав жат жги ждя жей жёг жён жи жиг жид жиз жим жит жни жну
            жок жом жор жох жри жу жур жух жуя жэк з зав зае заи зай зач
            заю зая збс зга зге зги згу зек зет зёв ззы зим зир злу зля зоб
            зри зрю зуе зуи зуй зую зуя зыж зык зэк зю зяб ив ива иве иву
            ивы иг ига иге игл иго игр игу ид иды иен иже изб изд изо изр
            икр ил ила иле илл илу илы ими ин инв инд инк инь ирг ирл иск
            исл исп ист ите ити ито иуд иха ища й йен йо йог йот ка каз
            кам кан кар каф ках кач каш ква кво квт кгс кд ке кеб кет ки
            кие кии кип кич кию кия клб кле кмк коб ков кож коз кои кой коп
            кор кос коф кош кою кп кпд крч ку куд кун куц куч кую куя кш
            кью кэ кэб л лав лаг лае лаж лаз лаи лал лам лан лас лат лаф
            лах лаю лая лбе лбы лее леж лез леи лек лею лея лив лиг лик лип
            лир лит лих лк лм лоз лон лос луб луд луж луз лун луо луп лык
            лын лыс ль лье лью лю люф ляд лян ляп ляс лях м мае маи ман
            мар мац мвт ме мез мен мер мес мет меу мёр мзд ми мк мни мню
            мня моб мов мож мри мру му мур мха мхе мхи мху мщу мыв мэн мю
            мяк мят н наг нал наю неб нег неф нею нёб нив ниц нищ ной нон
            нор ноу нош ною ноя нун нут ныв нью няш обл обр ов ова ове ово
            ову од оде одр оду ока оке окр оку ома оме ому омы оне оны опп
            ор ора орд оре ори орт оры оря ос осе осё осп ост осу отд офф
            оха охе охи охр оху очы п па пав пае паж паз паи пай пак пат
            паф паю пая пвх пдф пев пег пед пей пет печ пеш пёр пи пих пне
            пну пню пня поз пои пой пол пом поо пос поч поя прт пря псе псу
            псц пуд пуз пук пул пум пун пуп пут пуф пуш пущ пхв пыж пых пэ
            пэр р ра рае рал рат рах раш раю рая рвы рвя ре ред рее рез
            реи рей рек рел реч рею рея рё ржа рже ржи ржу риг риз рил роб
            рое рои рол рощ рою роя рте ру руг руд руж рум рун рут рую рцы
            ры рыв рые рый рым рых рюх рюш ряб ряж ряс рях саб саг саж саз
            сак сап се сег сеи сей сек сеч сею сея сё сёк сёл сём си сив
            сиг сиё сиз сии сио сип сис сиу сих сию сия скл сл слу сне сод
            сое сои сой сол соо сот соф соч сою спс спя сри сря ссу ста су
            суй сур суш сущ сую суя сцу сцы сыч ся сям т таб таг таи тай
            тал тан тап тар тат тау тах тач таю тая тв теа тек теп тер тес
            тет теш тещ тёк тёп тёс тёш тёщ тж тин тис тиф тк тки тку тле
            тли тлю тля тоб тов тог тож тол тощ тою тра тсу туб туг туе туи
            туй тул тус туф тух туч тую туя тчк тые тын тя тяг тяж тям тяп
            тят тяф тях уа уб убо ува уво уг уго угр уд уда уди уду уды
            удя уев уел уем уз уза узб узд узе узк узу узы узь узя уик уйм
            укр ул улю уме умы ун унт унц урн усе усо уст усу усю утл утр
            уу ухе ухи уху уч уча ушу ф фа фаа фаг фад фае фаз фай фал
            фар фат фау фаю фая фев фее феи фей фею фён фи фид фит фич фнт
            фор фра фри фрр фру фт фуа фуг фуд фук фур фут фф фэн х хае
            хаз хаи хал хап хар хат хау хач хаю хая хед хек хет хеш хил хин
            хне хну хны хо хоз хол хот хул хуп хур ц ца цам цах цац це
            цев цек цел цем цен цеп цер цзю цу цуг цук цы цып цыц ч чаг
            чае чаи чау чах чач чаш чащ чая чви че чез чес чеш чёл чёс чии
            чит чию чия чл чма чме чму чоп чох чтя чу чув чуй чум чун чур
            чух чуя ш шаи шаф шва шве шву швы шив шир шк шлю шля шо шов
            шор шот шох шуг шуй шш шэд щ щам щах щен щеп щец щзр ъ ы
            ыми ь э эва эг эе эи эйр эк эка экз эки экю эма эму эн
            энд эни эрг эре эру эры эс эст эты эф эфа эфе эфу эфы эха эхе
            эху эя ю юго юда юде юдо юду юж южн юл юле юли юлу юлы юлю
            юля юна юне юно юны юо юр юра юре юри юрк юрт юру юры яви явь
            яга яге яги ягу яде яды язв язе язи язю язя яка яке яки яко яку
            яла яле ялу ялы ямс яму ян яой яп яра ярг яре яри ярм яро яру
            яры ярь яте яти ять ятю ятя яшм
            """,
        "bg": """
            аба аби авт авь аги аго ада адв адм аед аза айр ака ало алп алт
            ама аое ап апр ара арж арх аса асо ата атр ауф б ба бае бау
            бач баш бая бг бди бдя беж беи бек бет беч бея бии бик био бип
            бкб бкх бнк бнф боа бод бои бон боц боя бря бул бур бут бфг бфр
            бфх бъг бър ва вае вай ван вар вби вег вее вей веф веч вещ вея
            вж взе вий вит вих виц вия вкф вля вм вмх воя впб впи вр ври
            вря вул вх вши въз въй въс въх вяж вям вят вях г га гал гаф
            гел гем геш гея гиг гиф гия гну гои гой гоя гпу гря гуш гък гюл
            гюм д даа дан двг двд дву дгф дер дий дкт дл для дм дмд дог
            дож дои дой доп доц доя дра дуа дуд дуе дуй дук дул дум дуо дут
            дуя дцп дън дю дюс ебъ еве ега ези ейд ейл ейс ек ека екю ел
            елф ене ент еня ерг ери есе ет еха ехе еча ечи еш ж жа жад
            жак жиу жо жур жфк з зав заг зае зар звд здр зев зее зей зер
            зет зея зиг зид зил зн зоб зра зре зри зрс зфк зъл зън зян иба
            ива иви иде изд изп изр изу ика инв инж инч иом ирл иса иск исо
            исп ите ифа иха иху й йок йон йот йощ к кае кай кая кв кви
            квм квч кеи кел кец кеч кея киа ким кир ких кич киш кия кл кла
            кле кмн ко кор коч кош кри кси куп куц кър къч къш кюп кяр л
            ла лаб лае лат лаф лая лвз ле лее леи лен леш лея лин лит лия
            лкм лм лог лой лос лсд луб луд луп лча лъг лък лъх лял лят лях
            м мае маи мас мац мек мие мий мих миш мля моа моб мож моп мпо
            мра мре мри мря муй муш мхм мч мък мях н нае нал нач ндп ндф
            ндх неи ней нео нес нз ний нит нищ ния нкщ нлр нмо нок нон ноу
            нп нюс обв обе обн обу овя оди одм ози оил ока оки окр оле оля
            ома омп оня опи опя оре ори осе ост ося отм отт охо ояж оял оям
            п па паж пай паф пач пая пдп пдц пдч пее пеш пея пз пи пик
            пих пич пла плу плю пнг пое пои пой пош поя пр пра псе пуд пук
            пул пуф пуч пфу пфю пъб пъй пък пью пя пян пях р раи рап рат
            рая ре рев рег рее рей рец рея ри рид рие риж рий рил рин рис
            рит рих рия рмс ро роб рои роя рпр руж рул рун руп ръб рът рю
            ря рял рят рях саз саи сак сап сач сая сбг сби свс сее сео сеп
            сеч сея сиг сим сип ск ска скл сл сля сми смя сн сне сои сос
            соф соц сп сра сри сст ств стз сти стк стм стс стц сур счу сък
            същ сют ся сяй сял сям сят сях сяш сящ т та таг таи тас таш
            тая тв тва тдж тдс тез тет теч тея тил тим тис тиф тля тма тми
            тн тов тоз тоя туи туй туп туч туя тц тъй тъч тю тюх тям у
            уби уеб уем узо уйо укр уля уми умя уни уно унр уок упр ууу уча
            ф фа фал фар фас фб фбк фев феи фер фес фи фии фий фиш фия
            фоб фр фук фус фъч фю х хав хал хап хас хаш хдп хек хем хип
            хич хлу хр ху хун хъм хъс хъш ц цап цдф це цев цеп цер цец
            ции цип цол цоп цп цпу цу цък цър цяр ч чад чал чам чан чая
            чеп чим чин чнг чоп чуе чуй чук чут чуш чуя ш шап шат шаш шв
            шет шех шзо шии ший ших шля шм шол шот шош шс шта шшт шшш щ
            щаб щам щем щеш щик щип щир щит щок щот щшц щял ъ ъб ъй ъл
            ът ъх ъч ь ю юга юго юда юди юдя юз юза юзу юпи юре юро
            юсв юси ют юта юти юф юфт юфу юц юч яаа яве яви явя яда яз
            яза яй яке яки яло ямб ями ямх янк яно яну яра яре яри ят ята
            ято яфа ях яха
            """,
    ]

    /// Real words, recorded as noise anyway because the same keys spell a common English word on the
    /// US layout, and English typed on the Cyrillic layout is the commoner mistake: listing `еру`
    /// would keep `the` typed on Ukrainian as `еру`. Found by rendering every added word on US.
    static let mirrors: [String: [String: String]] = [
        "uk": ["еру": "the", "рук": "her", "дуп": "leg", "ікс": "src"],
        "ru": ["рук": "her", "ща": "of", "гы": "us", "ем": "tv", "шт": "in"],
        "bg": ["яд": "so", "дух": "own", "хеш": "net", "ат": "dj"],
    ]

    static func noiseSet(_ lang: String) -> Set<String> {
        Set((noise[lang] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            .union((mirrors[lang] ?? [:]).keys)
    }

    /// Every 1–3 letter string over the alphabet that the dictionary accepts.
    static func accepted(_ lang: String, dict: LanguageCombinationTests.Dict) -> [String] {
        let a = Array(alphabets[lang]!).map(String.init)
        var out: [String] = []
        for x in a {
            if dict.isValidWord(x, lang: lang) { out.append(x) }
            for y in a {
                if dict.isValidWord(x + y, lang: lang) { out.append(x + y) }
                for z in a where dict.isValidWord(x + y + z, lang: lang) { out.append(x + y + z) }
            }
        }
        return out
    }

    func testEveryAcceptedShortStringIsClassified() throws {
        let dict = LanguageCombinationTests.Dict()
        var report: [String] = []
        for lang in ["uk", "ru", "bg"] {
            guard dict.isAvailable(lang) else { print("review: skip \(lang) — no dictionary"); continue }
            let noise = Self.noiseSet(lang)
            let accepted = Self.accepted(lang, dict: dict)
            let listed = accepted.filter { ShortWords.admits($0, lang: lang) }
            let unclassified = accepted.filter { !ShortWords.admits($0, lang: lang) && !noise.contains($0) }
            print("review: \(lang) accepted \(accepted.count), listed \(listed.count), noise \(noise.count),"
                  + " unclassified \(unclassified.count)")
            report += unclassified.map { "\(lang)\t\($0)" }
            XCTAssertTrue(unclassified.isEmpty, "\(lang): classify as a typed word (ShortWords.swift) or"
                          + " noise (ShortWordReview.noise): \(unclassified.prefix(80).joined(separator: " "))")
            let both = noise.filter { ShortWords.admits($0, lang: lang) }
            XCTAssertTrue(both.isEmpty, "\(lang): listed and also recorded as noise: \(both.sorted())")
        }
        if let out = ProcessInfo.processInfo.environment["SWITCHER3W_REVIEW_OUT"] {
            try report.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    /// Listed short words whose keys spell a listed English word on US, accepted knowingly.
    /// - Added by the review, where the English twin is rare in running text: `см`/cv, `учу`/exe,
    ///   `туш`/jwt. (`см` also takes the vowel-less rule's false conversions of `см` to 0.)
    /// - On the lists before the review, core function words (`до`, `са`, `ви`, `зі`, `мы`): converting
    ///   real Bulgarian, Ukrainian or Russian away is the dangerous direction.
    static let acceptedMirrors: [String: Set<String>] = [
        "uk": ["см", "учу", "ви", "зі", "оце", "сім"],
        "ru": ["см", "учу", "во", "мы"],
        "bg": ["туш", "ад", "все", "ги", "два", "до", "ей", "са"],
    ]

    /// A short Cyrillic word on the list keeps the keys that typed it, so if those keys spell an
    /// English word on US, English typed on the wrong layout is kept too. Every such pair is a decision.
    func testNoListedWordHidesACommonEnglishWord() throws {
        let us = LanguageCombinationTests.defaultLayout["en"]!
        try XCTSkipUnless(LanguageCombinationTests.table(us) != nil, "US layout not installed")
        for lang in ["uk", "ru", "bg"] {
            let id = LanguageCombinationTests.defaultLayout[lang]!
            guard LanguageCombinationTests.table(id) != nil else { continue }
            let catalog = LanguageCombinationTests.Catalog(["en", lang], current: lang)
            var hits: [String] = []
            for w in (ShortWords.common[lang] ?? []).sorted() where !(Self.acceptedMirrors[lang] ?? []).contains(w) {
                guard w.count > 1, let k = LanguageCombinationTests.keys(for: w, on: id),
                      let r = catalog.render(k, layoutID: us), r.allSatisfy(\.isLetter),
                      ShortWords.admits(r.lowercased(), lang: "en") else { continue }
                hits.append("\(w)/\(r)")
            }
            XCTAssertTrue(hits.isEmpty, "\(lang): listed words that spell English on US — record each in"
                          + " `mirrors` (noise) or `acceptedMirrors`: \(hits.joined(separator: " "))")
        }
    }
}
#endif
