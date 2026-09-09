/// The fabricated campus behind Guest Login.
///
/// Everything here is invented. There is no real club, no real student and no
/// real photograph: club and student names are fictional, and every image is a
/// built-in gradient template (`tpl:N`, see `create_post_screen.dart`) or the
/// existing initials fallback, so the joyride needs no bundled asset and never
/// resolves a remote URL.
///
/// The seed lands in the same global registries Supabase normally fills
/// (`mock_data.dart`), which is why the whole app renders it without a single
/// screen change.
///
/// ## Two invariants
///
/// **Ids are prefixed [kGuestIdPrefix].** Two startup migrations delete rows
/// that look like the legacy fixtures this repo removed —
/// `ContentStore._removeLegacyFixtures` drops posts matching `^n\d+$`, events
/// `^ev\d+$` and users `^u\d+$`, and `ChatStore._removeMockChatData` drops
/// `seed_dm_*` / `seed_club_*` ids. A seed world using those shapes would be
/// silently eaten. `guest_test.dart` pins this.
///
/// **Ids are deterministic.** [refreshGuestWorldLocale] rebuilds the localized
/// rows in place when the language toggle flips; because every id is stable,
/// the guest's own likes, RSVPs, votes and comments survive the swap.
library;

import 'dart:async';

import '../models/chat_group.dart';
import '../models/content_audience.dart';
import '../models/chat_message.dart';
import '../models/club.dart';
import '../models/comment.dart';
import '../models/event.dart';
import '../models/like.dart';
import '../models/news_post.dart';
import '../models/notification.dart';
import '../models/share.dart';
import '../models/subscription.dart';
import '../models/user.dart';
import 'auth_service.dart';
import 'chat_attachment_staging.dart';
import 'chat_store.dart';
import 'checkin_store.dart';
import 'comment_store.dart';
import 'content_audience_store.dart';
import 'locale_service.dart';
import 'mock_data.dart';
import 'people_service.dart';
import 'poll_store.dart';
import 'rsvp_store.dart';
import 'user_state.dart';

/// Prefix shared by every seeded id.
const String kGuestIdPrefix = 'guest_';

/// The guest's own profile id.
const String kGuestUserId = 'guest_me';

/// The club the guest sits on the board of — this is what makes the club-admin
/// point of view appear in the account switcher, and what grants write access
/// to that club's board and chat lanes.
const String kGuestBoardClubId = 'guest_club_debate';

bool _seeded = false;

/// True once [seedGuestWorld] has run and before [clearGuestWorld].
bool get guestWorldIsSeeded => _seeded;

/// The guest's own profile, so `AuthService` and the seed world cannot drift
/// apart on name, handle or role.
User guestSessionUser() =>
    _userFor(_people.firstWhere((person) => person.id == kGuestUserId));

/// Whether seeded clubs, posts and events use real photographs.
///
/// Flip this to `false` to take the joyride fully offline again: every row
/// falls back to the `tpl:N` built-in gradient it declares below, which needs
/// no network and no bundled asset.
const bool _useRemotePhotos = true;

/// A stable photograph for [seed].
///
/// Deterministic per seed, so a club or post keeps the same picture across
/// launches and the image cache actually hits. These are placeholder-service
/// photographs, deliberately not of identifiable people — the fictional
/// students keep the app's initials avatars instead (see `ClubAvatar`, which
/// also falls back to initials if a photo cannot load).
String _photoUrl(String seed, int width, int height) =>
    'https://picsum.photos/seed/clubup-$seed/$width/$height';

/// Resolves a row's declared `tpl:N` gradient to a photograph when
/// [_useRemotePhotos] is on. Rows with no imagery stay without any.
String? _imageFor(String? declared, String seed, int width, int height) {
  if (declared == null) return null;
  if (!_useRemotePhotos) return declared;
  return _photoUrl(seed, width, height);
}

String _t(String en, String tr) => localeService.languageCode == 'tr' ? tr : en;

// ── People ──────────────────────────────────────────────────────────────────

class _Person {
  const _Person(
    this.id,
    this.name,
    this.handle, {
    this.nameTr,
    required this.majorEn,
    required this.majorTr,
    required this.yearEn,
    required this.yearTr,
    required this.bioEn,
    required this.bioTr,
  });

  final String id;
  final String name;

  /// Only the guest's own label is translated — the other students are
  /// fictional people, and a name is not copy.
  final String? nameTr;

  /// The email local part, which surfaces in the UI as `@handle`
  /// (see `explore_screen.dart`, which derives it from the address). Spelled
  /// out per person rather than transliterated from the name, so Turkish
  /// characters cannot produce something odd.
  final String handle;
  final String majorEn;
  final String majorTr;
  final String yearEn;
  final String yearTr;
  final String bioEn;
  final String bioTr;
}

const List<_Person> _people = [
  _Person(
    kGuestUserId,
    'Guest 1#',
    'guest',
    nameTr: 'Guest 1#',
    majorEn: 'Computer Engineering',
    majorTr: 'Bilgisayar Mühendisliği',
    yearEn: '3rd Year',
    yearTr: '3. Sınıf',
    bioEn: 'Debate society board. Coffee, chess and late-night code.',
    bioTr: 'Tartışma kulübü yönetimi. Kahve, satranç ve gece kodlamaları.',
  ),
  _Person(
    'guest_u_selin',
    'Selin Korkmaz',
    'selin.korkmaz',
    majorEn: 'Industrial Engineering',
    majorTr: 'Endüstri Mühendisliği',
    yearEn: '4th Year',
    yearTr: '4. Sınıf',
    bioEn: 'Runs the robotics build nights. Ask me about CAD.',
    bioTr: 'Robotik atölye gecelerini yürütüyorum. CAD konusunda bana sorun.',
  ),
  _Person(
    'guest_u_mert',
    'Mert Şahin',
    'mert.sahin',
    majorEn: 'Business Administration',
    majorTr: 'İşletme',
    yearEn: '2nd Year',
    yearTr: '2. Sınıf',
    bioEn: 'Entrepreneurship club. Building something small.',
    bioTr: 'Girişimcilik kulübü. Küçük bir şeyler inşa ediyorum.',
  ),
  _Person(
    'guest_u_zeynep',
    'Zeynep Ünal',
    'zeynep.unal',
    majorEn: 'Psychology',
    majorTr: 'Psikoloji',
    yearEn: '3rd Year',
    yearTr: '3. Sınıf',
    bioEn: 'Photography, film nights, long walks on campus.',
    bioTr: 'Fotoğraf, film geceleri, kampüste uzun yürüyüşler.',
  ),
  _Person(
    'guest_u_can',
    'Can Demirtaş',
    'can.demirtas',
    majorEn: 'Electrical Engineering',
    majorTr: 'Elektrik Mühendisliği',
    yearEn: '1st Year',
    yearTr: '1. Sınıf',
    bioEn: 'New here. Trying every club at least once.',
    bioTr: 'Yeniyim. Her kulübü en az bir kez deniyorum.',
  ),
  _Person(
    'guest_u_elif',
    'Elif Yıldız',
    'elif.yildiz',
    majorEn: 'International Relations',
    majorTr: 'Uluslararası İlişkiler',
    yearEn: '4th Year',
    yearTr: '4. Sınıf',
    bioEn: 'Model UN veteran. Will argue any side.',
    bioTr: 'Model BM kıdemlisi. Her tarafı savunurum.',
  ),
  _Person(
    'guest_u_kaan',
    'Kaan Erdoğan',
    'kaan.erdogan',
    majorEn: 'Mechanical Engineering',
    majorTr: 'Makine Mühendisliği',
    yearEn: '2nd Year',
    yearTr: '2. Sınıf',
    bioEn: 'Formula student team. Mostly found in the workshop.',
    bioTr: 'Formula öğrenci takımı. Genelde atölyede bulunurum.',
  ),
  _Person(
    'guest_u_ayse',
    'Ayşe Kaplan',
    'ayse.kaplan',
    majorEn: 'Molecular Biology',
    majorTr: 'Moleküler Biyoloji',
    yearEn: '3rd Year',
    yearTr: '3. Sınıf',
    bioEn: 'Lab by day, choir by night.',
    bioTr: 'Gündüz laboratuvar, gece koro.',
  ),
  _Person(
    'guest_u_burak',
    'Burak Aslan',
    'burak.aslan',
    majorEn: 'Economics',
    majorTr: 'Ekonomi',
    yearEn: '2nd Year',
    yearTr: '2. Sınıf',
    bioEn: 'Basketball, spreadsheets, and strong opinions on both.',
    bioTr: 'Basketbol, tablolar ve ikisi hakkında da güçlü fikirler.',
  ),
  _Person(
    'guest_u_ipek',
    'İpek Tanrıöver',
    'ipek.tanriover',
    majorEn: 'Media and Visual Arts',
    majorTr: 'Medya ve Görsel Sanatlar',
    yearEn: '4th Year',
    yearTr: '4. Sınıf',
    bioEn: 'Shooting the campus one frame at a time.',
    bioTr: 'Kampüsü kare kare çekiyorum.',
  ),
  _Person(
    'guest_u_omer',
    'Ömer Faruk Çelik',
    'omer.celik',
    majorEn: 'Law',
    majorTr: 'Hukuk',
    yearEn: '3rd Year',
    yearTr: '3. Sınıf',
    bioEn: 'Debate partner, terrible at chess.',
    bioTr: 'Tartışma partneri, satrançta berbat.',
  ),
  _Person(
    'guest_u_nil',
    'Nil Aksoy',
    'nil.aksoy',
    majorEn: 'Sociology',
    majorTr: 'Sosyoloji',
    yearEn: '1st Year',
    yearTr: '1. Sınıf',
    bioEn: 'Here for the volunteering and the free tea.',
    bioTr: 'Gönüllülük ve bedava çay için buradayım.',
  ),
];

// ── Clubs ───────────────────────────────────────────────────────────────────

class _ClubSeed {
  const _ClubSeed(
    this.id,
    this.name,
    this.shortName, {
    required this.descEn,
    required this.descTr,
    required this.categoryEn,
    required this.categoryTr,
    required this.memberCount,
  });

  final String id;
  final String name;
  final String shortName;
  final String descEn;
  final String descTr;
  final String categoryEn;
  final String categoryTr;
  final int memberCount;
}

const List<_ClubSeed> _clubSeeds = [
  _ClubSeed(
    kGuestBoardClubId,
    'Debate Society',
    'DEBATE',
    descEn:
        'Weekly parliamentary debates, public speaking workshops and an '
        'intervarsity team that travels every spring.',
    descTr:
        'Haftalık parlamenter tartışmalar, hitabet atölyeleri ve her bahar '
        'turnuvalara giden bir üniversiteler arası takım.',
    categoryEn: 'Academic',
    categoryTr: 'Akademik',
    memberCount: 214,
  ),
  _ClubSeed(
    'guest_club_robotics',
    'Robotics Collective',
    'ROBO',
    descEn:
        'We design, print and break robots. Open build nights every Thursday '
        'in the engineering workshop — no experience needed.',
    descTr:
        'Robot tasarlıyor, basıyor ve kırıyoruz. Her perşembe mühendislik '
        'atölyesinde açık atölye gecesi — deneyim gerekmez.',
    categoryEn: 'Technology',
    categoryTr: 'Teknoloji',
    memberCount: 341,
  ),
  _ClubSeed(
    'guest_club_photo',
    'Frame Photography Club',
    'FRAME',
    descEn:
        'Darkroom access, monthly photo walks and a print exhibition at the '
        'end of each term.',
    descTr:
        'Karanlık oda erişimi, aylık fotoğraf yürüyüşleri ve her dönem sonunda '
        'bir baskı sergisi.',
    categoryEn: 'Arts',
    categoryTr: 'Sanat',
    memberCount: 176,
  ),
  _ClubSeed(
    'guest_club_entre',
    'Founders Circle',
    'FOUNDERS',
    descEn:
        'A room full of people building things. Pitch nights, mentor hours '
        'and a demo day every May.',
    descTr:
        'Bir şeyler inşa eden insanlarla dolu bir oda. Sunum geceleri, mentor '
        'saatleri ve her mayıs bir demo günü.',
    categoryEn: 'Entrepreneurship',
    categoryTr: 'Girişimcilik',
    memberCount: 289,
  ),
  _ClubSeed(
    'guest_club_hiking',
    'Trailhead Outdoor Club',
    'TRAIL',
    descEn:
        'Day hikes near the city, two big treks a year, and gear you can '
        'borrow instead of buy.',
    descTr:
        'Şehre yakın günübirlik yürüyüşler, yılda iki büyük tırmanış ve satın '
        'almak yerine ödünç alabileceğiniz ekipman.',
    categoryEn: 'Sports',
    categoryTr: 'Spor',
    memberCount: 198,
  ),
  _ClubSeed(
    'guest_club_music',
    'Campus Choir',
    'CHOIR',
    descEn:
        'Four voice parts, two concerts a term, and absolutely no audition '
        'for your first rehearsal.',
    descTr:
        'Dört ses grubu, dönemde iki konser ve ilk provanız için kesinlikle '
        'seçme yok.',
    categoryEn: 'Music',
    categoryTr: 'Müzik',
    memberCount: 132,
  ),
  _ClubSeed(
    'guest_club_volunteer',
    'Community Volunteers',
    'VOLUNTEER',
    descEn:
        'Tutoring, food drives and neighbourhood clean-ups. Come for one '
        'Saturday and see.',
    descTr:
        'Özel ders, gıda toplama ve mahalle temizliği. Bir cumartesi gelin ve '
        'görün.',
    categoryEn: 'Community',
    categoryTr: 'Topluluk',
    memberCount: 254,
  ),
  _ClubSeed(
    'guest_club_film',
    'Reel Society',
    'REEL',
    descEn:
        'Screenings every Tuesday with a short talk after. This term: films '
        'that were banned somewhere.',
    descTr:
        'Her salı gösterim ve ardından kısa bir konuşma. Bu dönem: bir yerde '
        'yasaklanmış filmler.',
    categoryEn: 'Arts',
    categoryTr: 'Sanat',
    memberCount: 167,
  ),
];

// ── Posts ───────────────────────────────────────────────────────────────────

class _PostSeed {
  const _PostSeed(
    this.id,
    this.clubId,
    this.authorId, {
    required this.en,
    required this.tr,
    this.imagePath,
    this.isAnnouncement = false,
    this.audience = ContentAudience.everyone,
    this.pollEn,
    this.pollTr,
    this.pollOptionsEn,
    this.pollOptionsTr,
    required this.ageHours,
    required this.likeCount,
  });

  final String id;
  final String clubId;
  final String authorId;
  final String en;
  final String tr;
  final String? imagePath;
  final ContentAudience audience;
  final bool isAnnouncement;
  final String? pollEn;
  final String? pollTr;
  final List<String>? pollOptionsEn;
  final List<String>? pollOptionsTr;
  final int ageHours;
  final int likeCount;
}

const List<_PostSeed> _postSeeds = [
  _PostSeed(
    'guest_post_1',
    kGuestBoardClubId,
    kGuestUserId,
    en:
        'Motion for Thursday: "This house would make voting compulsory." '
        'Sign-ups close Wednesday noon — first-timers get a practice round '
        'with a board member.',
    tr:
        'Perşembe önergesi: "Bu meclis oy vermeyi zorunlu kılardı." Kayıtlar '
        'çarşamba öğlen kapanıyor — ilk kez katılanlar yönetim üyesiyle bir '
        'deneme turu yapıyor.',
    imagePath: 'tpl:4',
    isAnnouncement: true,
    ageHours: 3,
    likeCount: 48,
  ),
  _PostSeed(
    'guest_post_2',
    'guest_club_robotics',
    'guest_u_selin',
    en:
        'The line-follower finally finished the course without falling off. '
        'Six weeks of Thursday nights in one photo.',
    tr:
        'Çizgi izleyen robot sonunda pistten düşmeden turu tamamladı. Altı '
        'haftalık perşembe geceleri tek bir fotoğrafta.',
    imagePath: 'tpl:1',
    ageHours: 6,
    likeCount: 132,
  ),
  _PostSeed(
    'guest_post_3',
    'guest_club_photo',
    'guest_u_ipek',
    en:
        'Photo walk down to the old harbour on Saturday at 07:00 — yes, that '
        'early, the light is worth it. Bring whatever camera you own, phones '
        'absolutely count.',
    tr:
        'Cumartesi 07:00\'de eski limana fotoğraf yürüyüşü — evet, o kadar '
        'erken, ışık buna değer. Elinizdeki her kamerayı getirin, telefonlar '
        'kesinlikle sayılır.',
    imagePath: 'tpl:0',
    ageHours: 11,
    likeCount: 87,
  ),
  _PostSeed(
    'guest_post_4',
    'guest_club_entre',
    'guest_u_mert',
    en:
        'Pitch night was packed. Nine teams, four minutes each, and one idea '
        'that made the whole room go quiet. Next one is in three weeks.',
    tr:
        'Sunum gecesi doluydu. Dokuz takım, her birine dört dakika ve tüm '
        'salonu sessizleştiren bir fikir. Bir sonrakine üç hafta var.',
    imagePath: 'tpl:6',
    ageHours: 20,
    likeCount: 76,
  ),
  _PostSeed(
    'guest_post_5',
    'guest_club_hiking',
    'guest_u_kaan',
    en: 'Where should the spring trek go?',
    tr: 'Bahar tırmanışı nereye olsun?',
    pollEn: 'Where should the spring trek go?',
    pollTr: 'Bahar tırmanışı nereye olsun?',
    pollOptionsEn: ['Coastal ridge', 'Volcano crater', 'Forest lakes'],
    pollOptionsTr: ['Kıyı sırtı', 'Volkan krateri', 'Orman gölleri'],
    ageHours: 26,
    likeCount: 54,
  ),
  _PostSeed(
    'guest_post_6',
    'guest_club_music',
    'guest_u_ayse',
    en:
        'We are short two altos for the winter concert. If you can hold a '
        'tune in the shower you can hold one here — rehearsal is Monday 18:00.',
    tr:
        'Kış konseri için iki alto eksiğimiz var. Duşta bir melodiyi '
        'tutturabiliyorsanız burada da tutturabilirsiniz — prova pazartesi '
        '18:00.',
    imagePath: 'tpl:7',
    ageHours: 33,
    likeCount: 41,
  ),
  _PostSeed(
    'guest_post_7',
    'guest_club_volunteer',
    'guest_u_nil',
    en:
        'Saturday\'s tutoring session covered forty-one kids and we still had '
        'volunteers spare. Thank you to everyone who gave up a morning.',
    tr:
        'Cumartesi özel ders oturumunda kırk bir çocuğa ulaştık ve hâlâ yedek '
        'gönüllümüz vardı. Bir sabahından vazgeçen herkese teşekkürler.',
    imagePath: 'tpl:2',
    ageHours: 40,
    likeCount: 118,
  ),
  _PostSeed(
    'guest_post_8',
    'guest_club_film',
    'guest_u_zeynep',
    en:
        'Tuesday: a film that three countries pulled from cinemas in the same '
        'month. Short talk afterwards from the Law faculty, then arguing in '
        'the corridor as usual.',
    tr:
        'Salı: aynı ay içinde üç ülkenin sinemalardan kaldırdığı bir film. '
        'Ardından Hukuk fakültesinden kısa bir konuşma, sonra her zamanki gibi '
        'koridorda tartışma.',
    imagePath: 'tpl:3',
    ageHours: 47,
    likeCount: 63,
  ),
  _PostSeed(
    'guest_post_9',
    kGuestBoardClubId,
    'guest_u_omer',
    en:
        'Intervarsity results: we took second overall and Elif was named best '
        'speaker in the final. Full write-up on the board.',
    tr:
        'Üniversiteler arası sonuçlar: genel ikincilik bizde ve Elif finalde '
        'en iyi konuşmacı seçildi. Detaylı yazı panoda.',
    imagePath: 'tpl:5',
    audience: ContentAudience.board,
    ageHours: 54,
    likeCount: 204,
  ),
  _PostSeed(
    'guest_post_10',
    'guest_club_robotics',
    'guest_u_can',
    en:
        'First build night as a first-year: I broke a servo in the first ten '
        'minutes and nobody minded. Come along, genuinely.',
    tr:
        'Birinci sınıf olarak ilk atölye gecem: ilk on dakikada bir servoyu '
        'kırdım ve kimse aldırmadı. Gerçekten, siz de gelin.',
    audience: ContentAudience.board,
    ageHours: 61,
    likeCount: 95,
  ),
  _PostSeed(
    'guest_post_11',
    'guest_club_entre',
    'guest_u_burak',
    en:
        'Mentor hours are open for booking — twenty-minute slots with founders '
        'who have actually shipped something. Sign-up sheet is on the board.',
    tr:
        'Mentor saatleri randevuya açık — gerçekten bir şey yayınlamış '
        'kurucularla yirmi dakikalık görüşmeler. Kayıt listesi panoda.',
    audience: ContentAudience.followers,
    ageHours: 68,
    likeCount: 37,
  ),
  _PostSeed(
    'guest_post_12',
    'guest_club_photo',
    'guest_u_zeynep',
    en:
        'Darkroom induction for new members on Friday. Eight places, and once '
        'you are inducted you can book it whenever it is free.',
    tr:
        'Cuma günü yeni üyeler için karanlık oda eğitimi. Sekiz kişilik yer ve '
        'eğitimden sonra boş olduğu her an rezerve edebilirsiniz.',
    imagePath: 'tpl:3',
    isAnnouncement: true,
    audience: ContentAudience.followers,
    ageHours: 76,
    likeCount: 52,
  ),
  _PostSeed(
    'guest_post_13',
    'guest_club_hiking',
    'guest_u_kaan',
    en:
        'Gear library restocked: four tents, eleven sleeping bags and a lot of '
        'mismatched trekking poles. Borrow it, do not buy it.',
    tr:
        'Ekipman kütüphanesi yenilendi: dört çadır, on bir uyku tulumu ve bir '
        'sürü eşleşmeyen yürüyüş bastonu. Satın almayın, ödünç alın.',
    ageHours: 84,
    likeCount: 44,
  ),
  _PostSeed(
    'guest_post_14',
    'guest_club_volunteer',
    'guest_u_nil',
    en:
        'Food drive total: 612 kilos. That is a third more than last term and '
        'it all came from one week of tabling outside the library.',
    tr:
        'Gıda toplama toplamı: 612 kilo. Bu geçen dönemden üçte bir fazla ve '
        'hepsi kütüphane önünde bir haftalık masa açmaktan geldi.',
    imagePath: 'tpl:2',
    ageHours: 92,
    likeCount: 149,
  ),
  _PostSeed(
    'guest_post_15',
    'guest_club_music',
    'guest_u_ayse',
    en: 'Which piece should close the winter concert?',
    tr: 'Kış konserini hangi parça kapatsın?',
    pollEn: 'Which piece should close the winter concert?',
    pollTr: 'Kış konserini hangi parça kapatsın?',
    pollOptionsEn: ['The commissioned piece', 'A folk arrangement', 'Requiem'],
    pollOptionsTr: ['Sipariş edilen eser', 'Bir halk düzenlemesi', 'Requiem'],
    ageHours: 100,
    likeCount: 58,
  ),
  _PostSeed(
    'guest_post_16',
    kGuestBoardClubId,
    kGuestUserId,
    en:
        'Public speaking workshop for anyone who has never done this — no '
        'motion, no judging, just getting used to standing up. Twelve places.',
    tr:
        'Bunu hiç yapmamış olanlar için hitabet atölyesi — önerge yok, '
        'jüri yok, sadece ayağa kalkmaya alışmak. On iki kişilik yer.',
    ageHours: 108,
    likeCount: 71,
  ),
  _PostSeed(
    'guest_post_17',
    'guest_club_film',
    'guest_u_ipek',
    en:
        'We are programming next term now. If there is a film you want on the '
        'big screen with an argument after it, put it on the board.',
    tr:
        'Gelecek dönemin programını şimdi yapıyoruz. Büyük ekranda görmek ve '
        'ardından tartışmak istediğiniz bir film varsa panoya yazın.',
    ageHours: 116,
    likeCount: 33,
  ),
  _PostSeed(
    'guest_post_18',
    'guest_club_robotics',
    'guest_u_selin',
    en:
        'Formula team is recruiting for the aero subteam. You do not need to '
        'know CFD, you need to be willing to learn it by March.',
    tr:
        'Formula takımı aero alt takımı için üye alıyor. CFD bilmeniz gerekmez, '
        'mart\'a kadar öğrenmeye istekli olmanız gerekir.',
    imagePath: 'tpl:1',
    ageHours: 124,
    likeCount: 88,
  ),
  _PostSeed(
    'guest_post_19',
    'guest_club_entre',
    'guest_u_mert',
    en:
        'Demo day is booked for May. Six slots, ten minutes each, real '
        'investors in the room. Applications open after reading week.',
    tr:
        'Demo günü mayıs için ayarlandı. Altı slot, her birine on dakika, '
        'salonda gerçek yatırımcılar. Başvurular ara tatilden sonra açılıyor.',
    imagePath: 'tpl:6',
    isAnnouncement: true,
    ageHours: 132,
    likeCount: 112,
  ),
  _PostSeed(
    'guest_post_20',
    'guest_club_hiking',
    'guest_u_elif',
    en:
        'Sunrise from the ridge on Sunday. We left at four in the morning and '
        'every single person said it was worth it on the way down.',
    tr:
        'Pazar günü sırttan gün doğumu. Sabah dörtte çıktık ve inişte herkes '
        'buna değdiğini söyledi.',
    imagePath: 'tpl:0',
    ageHours: 140,
    likeCount: 167,
  ),
  _PostSeed(
    'guest_post_21',
    'guest_club_photo',
    'guest_u_ipek',
    en:
        'Print exhibition opens in the atrium next week. Thirty-one prints '
        'from nineteen members, and a lot of them are first-years.',
    tr:
        'Baskı sergisi gelecek hafta atriumda açılıyor. On dokuz üyeden otuz '
        'bir baskı ve çoğu birinci sınıf öğrencisi.',
    imagePath: 'tpl:5',
    ageHours: 148,
    likeCount: 94,
  ),
  _PostSeed(
    'guest_post_22',
    'guest_club_volunteer',
    'guest_u_nil',
    en:
        'Neighbourhood clean-up on Saturday morning. Gloves and bags provided, '
        'tea afterwards is the actual reason most people come.',
    tr:
        'Cumartesi sabahı mahalle temizliği. Eldiven ve poşetler bizden, '
        'çoğu insanın gelme sebebi ise sonrasındaki çay.',
    ageHours: 156,
    likeCount: 39,
  ),
  _PostSeed(
    'guest_post_23',
    kGuestBoardClubId,
    'guest_u_elif',
    en:
        'Model UN delegation places are up. Four committees, and we will run '
        'position-paper clinics through February for anyone who applies.',
    tr:
        'Model BM delegasyon yerleri açıldı. Dört komite ve başvuran herkes '
        'için şubat boyunca pozisyon belgesi atölyeleri yapacağız.',
    ageHours: 164,
    likeCount: 66,
  ),
  _PostSeed(
    'guest_post_24',
    'guest_club_film',
    'guest_u_omer',
    en:
        'Reminder that the Tuesday screening is free and you do not have to be '
        'a member. Just turn up, the back row is always empty.',
    tr:
        'Salı gösteriminin ücretsiz olduğunu ve üye olmanız gerekmediğini '
        'hatırlatırız. Sadece gelin, arka sıra her zaman boş.',
    ageHours: 172,
    likeCount: 28,
  ),
  _PostSeed(
    'guest_post_25',
    'guest_club_music',
    'guest_u_ayse',
    en:
        'Recording session for the term single went long but we got it. '
        'Mixing now, out before the holidays.',
    tr:
        'Dönem şarkısı için kayıt oturumu uzun sürdü ama başardık. Şimdi mix '
        'aşamasında, tatilden önce çıkıyor.',
    imagePath: 'tpl:7',
    ageHours: 180,
    likeCount: 81,
  ),
];

// ── Events ──────────────────────────────────────────────────────────────────

class _EventSeed {
  const _EventSeed(
    this.id,
    this.clubId, {
    required this.titleEn,
    required this.titleTr,
    required this.descEn,
    required this.descTr,
    required this.locationEn,
    required this.locationTr,
    this.weekday,
    this.weeksAhead = 0,
    this.dayOffset = 0,
    required this.startHour,
    this.startMinute = 0,
    required this.durationHours,
    this.imagePath,
    this.capacity,
    this.accentColorHex,
    this.attendees = const [],
    this.tagsEn = const [],
    this.tagsTr = const [],
    this.withSchedule = false,
    this.withSpeakers = false,
  });

  final String id;
  final String clubId;
  final String titleEn;
  final String titleTr;
  final String descEn;
  final String descTr;
  final String locationEn;
  final String locationTr;

  /// Anchors the event to the next occurrence of this weekday, so a "Thursday
  /// debate" really does land on a Thursday whenever the demo is opened.
  /// Null for the past events, which use [dayOffset] instead.
  final int? weekday;
  final int weeksAhead;
  final int dayOffset;
  final int startHour;
  final int startMinute;
  final int durationHours;
  final String? imagePath;
  final int? capacity;
  final String? accentColorHex;
  final List<String> attendees;
  final List<String> tagsEn;
  final List<String> tagsTr;
  final bool withSchedule;
  final bool withSpeakers;
}

const List<_EventSeed> _eventSeeds = [
  _EventSeed(
    'guest_event_1',
    kGuestBoardClubId,
    titleEn: 'Thursday Parliamentary Debate',
    titleTr: 'Perşembe Parlamenter Tartışması',
    descEn:
        'Two motions, eight speakers, and a practice round for anyone who has '
        'never spoken before. Judging is friendly and feedback is the point.',
    descTr:
        'İki önerge, sekiz konuşmacı ve daha önce hiç konuşmamış olanlar için '
        'bir deneme turu. Jüri dostane, amaç geri bildirim.',
    locationEn: 'Social Sciences Building, Room 204',
    locationTr: 'Sosyal Bilimler Binası, 204',
    weekday: DateTime.thursday,
    startHour: 18,
    durationHours: 3,
    imagePath: 'tpl:4',
    capacity: 60,
    accentColorHex: '8C1D40',
    attendees: [
      kGuestUserId,
      'guest_u_omer',
      'guest_u_elif',
      'guest_u_can',
      'guest_u_nil',
    ],
    tagsEn: ['Debate', 'Beginner friendly'],
    tagsTr: ['Tartışma', 'Yeni başlayanlara uygun'],
    withSchedule: true,
  ),
  _EventSeed(
    'guest_event_2',
    'guest_club_robotics',
    titleEn: 'Open Build Night',
    titleTr: 'Açık Atölye Gecesi',
    descEn:
        'The workshop is open, the soldering irons are hot and someone will '
        'show you how to use them. Bring nothing.',
    descTr:
        'Atölye açık, havyalar sıcak ve biri size nasıl kullanılacağını '
        'gösterecek. Hiçbir şey getirmeyin.',
    locationEn: 'Engineering Workshop B',
    locationTr: 'Mühendislik Atölyesi B',
    weekday: DateTime.thursday,
    startHour: 19,
    durationHours: 4,
    imagePath: 'tpl:1',
    capacity: 40,
    accentColorHex: '667EEA',
    attendees: ['guest_u_selin', 'guest_u_can', 'guest_u_kaan'],
    tagsEn: ['Workshop', 'Hands-on'],
    tagsTr: ['Atölye', 'Uygulamalı'],
  ),
  _EventSeed(
    'guest_event_3',
    'guest_club_photo',
    titleEn: 'Sunrise Photo Walk',
    titleTr: 'Gün Doğumu Fotoğraf Yürüyüşü',
    descEn:
        'Down to the old harbour for the first light. Any camera, phones '
        'included. We finish with breakfast.',
    descTr:
        'İlk ışık için eski limana. Her kamera, telefonlar dahil. Kahvaltıyla '
        'bitiriyoruz.',
    locationEn: 'Main Gate, then the harbour',
    locationTr: 'Ana Kapı, ardından liman',
    weekday: DateTime.saturday,
    startHour: 7,
    durationHours: 4,
    imagePath: 'tpl:0',
    capacity: 25,
    accentColorHex: 'FF6B6B',
    attendees: ['guest_u_ipek', 'guest_u_zeynep', kGuestUserId],
    tagsEn: ['Photography', 'Outdoors'],
    tagsTr: ['Fotoğraf', 'Açık hava'],
  ),
  _EventSeed(
    'guest_event_4',
    'guest_club_entre',
    titleEn: 'Founders Pitch Night',
    titleTr: 'Kurucular Sunum Gecesi',
    descEn:
        'Nine teams, four minutes each, then questions from a panel who have '
        'built and sold things themselves.',
    descTr:
        'Dokuz takım, her birine dört dakika, ardından kendisi bir şeyler '
        'kurmuş ve satmış bir panelden sorular.',
    locationEn: 'Innovation Hub Auditorium',
    locationTr: 'İnovasyon Merkezi Oditoryumu',
    weekday: DateTime.wednesday,
    startHour: 18,
    startMinute: 30,
    durationHours: 3,
    imagePath: 'tpl:6',
    capacity: 120,
    accentColorHex: '6A1B9A',
    attendees: ['guest_u_mert', 'guest_u_burak', 'guest_u_selin', kGuestUserId],
    tagsEn: ['Pitching', 'Networking'],
    tagsTr: ['Sunum', 'Networking'],
    withSchedule: true,
    withSpeakers: true,
  ),
  _EventSeed(
    'guest_event_5',
    'guest_club_hiking',
    titleEn: 'Coastal Ridge Day Hike',
    titleTr: 'Kıyı Sırtı Günübirlik Yürüyüşü',
    descEn:
        'Eighteen kilometres with about six hundred metres of climb. Boots '
        'required, poles available from the gear library.',
    descTr:
        'Yaklaşık altı yüz metre tırmanışla on sekiz kilometre. Bot zorunlu, '
        'baston ekipman kütüphanesinden temin edilebilir.',
    locationEn: 'Meet at the bus bay, 06:30',
    locationTr: 'Otobüs durağında buluşma, 06:30',
    weekday: DateTime.sunday,
    startHour: 6,
    startMinute: 30,
    durationHours: 9,
    imagePath: 'tpl:2',
    capacity: 30,
    accentColorHex: '2E7D32',
    attendees: ['guest_u_kaan', 'guest_u_elif', 'guest_u_burak'],
    tagsEn: ['Hiking', 'Full day'],
    tagsTr: ['Yürüyüş', 'Tam gün'],
  ),
  _EventSeed(
    'guest_event_6',
    'guest_club_music',
    titleEn: 'Winter Concert',
    titleTr: 'Kış Konseri',
    descEn:
        'Four voice parts, one commissioned piece and a folk arrangement that '
        'has become a bit of a tradition. Free entry.',
    descTr:
        'Dört ses grubu, sipariş edilmiş bir eser ve artık biraz gelenek hâline '
        'gelmiş bir halk düzenlemesi. Giriş ücretsiz.',
    locationEn: 'Sever Hall',
    locationTr: 'Sever Salonu',
    weekday: DateTime.friday,
    weeksAhead: 2,
    startHour: 20,
    durationHours: 2,
    imagePath: 'tpl:7',
    capacity: 300,
    accentColorHex: 'B8860B',
    attendees: ['guest_u_ayse', 'guest_u_zeynep', 'guest_u_nil', kGuestUserId],
    tagsEn: ['Concert', 'Free'],
    tagsTr: ['Konser', 'Ücretsiz'],
    withSpeakers: true,
  ),
  _EventSeed(
    'guest_event_7',
    'guest_club_volunteer',
    titleEn: 'Saturday Tutoring',
    titleTr: 'Cumartesi Özel Ders',
    descEn:
        'Maths and reading with local secondary students. Three hours, and '
        'you are paired with someone experienced for your first session.',
    descTr:
        'Yerel ortaokul öğrencileriyle matematik ve okuma. Üç saat ve ilk '
        'oturumunuzda deneyimli biriyle eşleştiriliyorsunuz.',
    locationEn: 'Community Centre, Sarıyer',
    locationTr: 'Toplum Merkezi, Sarıyer',
    weekday: DateTime.saturday,
    startHour: 10,
    durationHours: 3,
    imagePath: 'tpl:2',
    capacity: 45,
    accentColorHex: '81C784',
    attendees: ['guest_u_nil', 'guest_u_ayse'],
    tagsEn: ['Volunteering', 'Weekly'],
    tagsTr: ['Gönüllülük', 'Haftalık'],
  ),
  _EventSeed(
    'guest_event_8',
    'guest_club_film',
    titleEn: 'Tuesday Screening & Talk',
    titleTr: 'Salı Gösterimi ve Konuşma',
    descEn:
        'A film three countries pulled in the same month, followed by fifteen '
        'minutes from the Law faculty and an argument in the corridor.',
    descTr:
        'Üç ülkenin aynı ay kaldırdığı bir film, ardından Hukuk fakültesinden '
        'on beş dakika ve koridorda bir tartışma.',
    locationEn: 'Lecture Theatre 1',
    locationTr: 'Amfi 1',
    weekday: DateTime.tuesday,
    startHour: 19,
    durationHours: 3,
    imagePath: 'tpl:3',
    capacity: 90,
    accentColorHex: '16213E',
    attendees: ['guest_u_zeynep', 'guest_u_omer', 'guest_u_ipek', kGuestUserId],
    tagsEn: ['Screening', 'Discussion'],
    tagsTr: ['Gösterim', 'Tartışma'],
    withSpeakers: true,
  ),
  // Two events already past, so the activity history and "past events" tabs
  // have something in them.
  _EventSeed(
    'guest_event_past_1',
    kGuestBoardClubId,
    titleEn: 'Intervarsity Debate Championship',
    titleTr: 'Üniversiteler Arası Tartışma Şampiyonası',
    descEn:
        'Three days, sixty-four teams. We finished second overall and took '
        'best speaker in the final.',
    descTr:
        'Üç gün, altmış dört takım. Genel ikinci olduk ve finalde en iyi '
        'konuşmacı ödülünü aldık.',
    locationEn: 'Ankara',
    locationTr: 'Ankara',
    dayOffset: -17,
    startHour: 9,
    durationHours: 60,
    imagePath: 'tpl:5',
    accentColorHex: '8C1D40',
    attendees: [kGuestUserId, 'guest_u_elif', 'guest_u_omer'],
    tagsEn: ['Competition'],
    tagsTr: ['Yarışma'],
  ),
  _EventSeed(
    'guest_event_past_2',
    'guest_club_photo',
    titleEn: 'Print Exhibition Opening',
    titleTr: 'Baskı Sergisi Açılışı',
    descEn:
        'Thirty-one prints from nineteen members, hung in the atrium for two '
        'weeks.',
    descTr:
        'On dokuz üyeden otuz bir baskı, iki hafta boyunca atriumda sergilendi.',
    locationEn: 'Main Atrium',
    locationTr: 'Ana Atrium',
    dayOffset: -9,
    startHour: 18,
    durationHours: 3,
    imagePath: 'tpl:0',
    accentColorHex: 'FF6B6B',
    attendees: [kGuestUserId, 'guest_u_ipek', 'guest_u_zeynep'],
    tagsEn: ['Exhibition'],
    tagsTr: ['Sergi'],
  ),
];

// ── Interactions ────────────────────────────────────────────────────────────

/// Clubs the guest already follows — every club in the seed world.
///
/// Following *is* club membership in this app (`ChatStore.canAccessThread`),
/// so this is what opens the club rooms, and it covers all of them on purpose:
/// the joyride is a demo, so it starts on the far side of every Join button
/// instead of asking a visitor to press one before the app has anything to
/// show them.
///
/// Derived from [_clubSeeds] rather than listed out, so a club added there is
/// joined by construction. Listing them invites the failure this replaced: a
/// club missing from the list is still rendered as a room by
/// `ChatStore.threadsFor` — one the guest is locked out of.
///
/// The audience rule keeps a hidden example without an unjoined club:
/// `guest_post_10` is a board-only post in the robotics club, which the guest
/// follows without sitting on the board, so the feed still demonstrates
/// content being held back (see `content_visibility.dart`).
List<String> get _guestFollowedClubIds => [
  for (final seed in _clubSeeds) seed.id,
];

/// People the guest follows. Intersected with the follower set below to give
/// the mutual-follow graph that gates event attendee names.
const List<String> _guestFollowingIds = [
  'guest_u_selin',
  'guest_u_omer',
  'guest_u_elif',
  'guest_u_ipek',
  'guest_u_zeynep',
  'guest_u_nil',
];

/// People who follow the guest back.
const List<String> _guestFollowerIds = [
  'guest_u_selin',
  'guest_u_omer',
  'guest_u_elif',
  'guest_u_can',
  'guest_u_kaan',
];

const List<String> _guestLikedPostIds = [
  'guest_post_2',
  'guest_post_9',
  'guest_post_20',
];

const List<String> _guestSavedPostIds = ['guest_post_3', 'guest_post_19'];

class _CommentSeed {
  const _CommentSeed(
    this.id,
    this.postId,
    this.userId, {
    required this.en,
    required this.tr,
    required this.ageHours,
  });

  final String id;
  final String postId;
  final String userId;
  final String en;
  final String tr;
  final int ageHours;
}

const List<_CommentSeed> _commentSeeds = [
  _CommentSeed(
    'guest_c_1',
    'guest_post_1',
    'guest_u_omer',
    en: 'Signed up. Taking the opposition this time.',
    tr: 'Kaydoldum. Bu kez muhalefeti alıyorum.',
    ageHours: 2,
  ),
  _CommentSeed(
    'guest_c_2',
    'guest_post_1',
    'guest_u_can',
    en: 'Is the practice round really open to first-years?',
    tr: 'Deneme turu gerçekten birinci sınıflara açık mı?',
    ageHours: 1,
  ),
  _CommentSeed(
    'guest_c_3',
    'guest_post_2',
    'guest_u_kaan',
    en: 'Six weeks well spent. That last corner was brutal.',
    tr: 'Altı hafta boşa gitmemiş. Şu son viraj acımasızdı.',
    ageHours: 4,
  ),
  _CommentSeed(
    'guest_c_4',
    'guest_post_3',
    'guest_u_zeynep',
    en: 'I will bring the spare 35mm for anyone who wants to try film.',
    tr: 'Film denemek isteyenler için yedek 35mm getireceğim.',
    ageHours: 8,
  ),
  _CommentSeed(
    'guest_c_5',
    'guest_post_7',
    'guest_u_ayse',
    en: 'Forty-one is a record, surely?',
    tr: 'Kırk bir rekor olsa gerek?',
    ageHours: 30,
  ),
  _CommentSeed(
    'guest_c_6',
    'guest_post_9',
    kGuestUserId,
    en: 'Elif was extraordinary in that final. Well deserved.',
    tr: 'Elif o finalde olağanüstüydü. Hak etti.',
    ageHours: 40,
  ),
  _CommentSeed(
    'guest_c_7',
    'guest_post_20',
    'guest_u_burak',
    en: 'Four in the morning and I would do it again.',
    tr: 'Sabahın dördü ve yine yapardım.',
    ageHours: 120,
  ),
];

class _NotificationSeed {
  const _NotificationSeed(
    this.id, {
    required this.en,
    required this.tr,
    required this.targetType,
    required this.targetId,
    required this.ageMinutes,
    this.fromId,
    this.read = false,
  });

  final String id;
  final String en;
  final String tr;
  final String targetType;
  final String targetId;
  final int ageMinutes;
  final String? fromId;
  final bool read;
}

const List<_NotificationSeed> _notificationSeeds = [
  _NotificationSeed(
    'guest_n_1',
    en: 'Selin Korkmaz liked your post',
    tr: 'Selin Korkmaz gönderini beğendi',
    targetType: 'post',
    targetId: 'guest_post_1',
    fromId: 'guest_u_selin',
    ageMinutes: 12,
  ),
  _NotificationSeed(
    'guest_n_2',
    en: 'Ömer Faruk Çelik commented on your post',
    tr: 'Ömer Faruk Çelik gönderine yorum yaptı',
    targetType: 'post',
    targetId: 'guest_post_1',
    fromId: 'guest_u_omer',
    ageMinutes: 95,
  ),
  _NotificationSeed(
    'guest_n_3',
    en: 'Robotics Collective posted: Open Build Night is tomorrow',
    tr: 'Robotics Collective paylaştı: Açık Atölye Gecesi yarın',
    targetType: 'event',
    targetId: 'guest_event_2',
    ageMinutes: 240,
  ),
  _NotificationSeed(
    'guest_n_4',
    en: 'Can Demirtaş started following you',
    tr: 'Can Demirtaş seni takip etmeye başladı',
    targetType: 'user',
    targetId: 'guest_u_can',
    fromId: 'guest_u_can',
    ageMinutes: 420,
  ),
  _NotificationSeed(
    'guest_n_5',
    en: 'Frame Photography Club posted a new announcement',
    tr: 'Frame Photography Club yeni bir duyuru paylaştı',
    targetType: 'post',
    targetId: 'guest_post_12',
    ageMinutes: 1500,
    read: true,
  ),
  _NotificationSeed(
    'guest_n_6',
    en: 'Reel Society: Tuesday Screening starts in 8 hours',
    tr: 'Reel Society: Salı Gösterimi 8 saat içinde başlıyor',
    targetType: 'event',
    targetId: 'guest_event_8',
    ageMinutes: 2600,
    read: true,
  ),
];

// ── Build + apply ───────────────────────────────────────────────────────────

DateTime _hoursAgo(int hours) =>
    DateTime.now().subtract(Duration(hours: hours));

User _userFor(_Person person) => User(
  id: person.id,
  name: _t(person.name, person.nameTr ?? person.name),
  // `.invalid` is reserved and can never receive mail, so these addresses
  // cannot collide with a real person's.
  email: '${person.handle}@guest.invalid',
  password: '',
  role: 'student',
  subscribedClubIds: person.id == kGuestUserId
      ? List<String>.of(_guestFollowedClubIds)
      : const [],
  followingUserIds: person.id == kGuestUserId
      ? List<String>.of(_guestFollowingIds)
      : const [],
);

NewsPost _postFor(_PostSeed seed) => NewsPost(
  id: seed.id,
  clubId: seed.clubId,
  authorId: seed.authorId,
  content: _t(seed.en, seed.tr),
  createdAt: _hoursAgo(seed.ageHours),
  imagePath: _imageFor(seed.imagePath, seed.id, 1200, 1200),
  isAnnouncement: seed.isAnnouncement,
  audience: seed.audience,
  poll: seed.pollEn == null
      ? null
      : PollData(
          question: _t(seed.pollEn!, seed.pollTr!),
          options: localeService.languageCode == 'tr'
              ? List<String>.of(seed.pollOptionsTr!)
              : List<String>.of(seed.pollOptionsEn!),
        ),
);

/// Resolves a seed to a real start time.
///
/// Events are anchored to a weekday at a fixed hour rather than to "now plus N
/// hours", so a screening is at 19:00 and a sunrise walk at 07:00 no matter
/// when the joyride is opened.
DateTime _startFor(_EventSeed seed) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekday = seed.weekday;
  final DateTime day;
  if (weekday != null) {
    var delta = (weekday - today.weekday) % 7;
    // Always the *next* one, so an event never sits in today's past.
    if (delta == 0) delta = 7;
    day = today.add(Duration(days: delta + seed.weeksAhead * 7));
  } else {
    day = today.add(Duration(days: seed.dayOffset));
  }
  return day.add(Duration(hours: seed.startHour, minutes: seed.startMinute));
}

Event _eventFor(_EventSeed seed) {
  final start = _startFor(seed);
  final rsvpAt = _hoursAgo(48).toIso8601String();
  return Event(
    id: seed.id,
    clubId: seed.clubId,
    title: _t(seed.titleEn, seed.titleTr),
    description: _t(seed.descEn, seed.descTr),
    dateTime: start,
    endTime: start.add(Duration(hours: seed.durationHours)),
    location: _t(seed.locationEn, seed.locationTr),
    attendeeUserIds: List<String>.of(seed.attendees),
    rsvpTimestamps: {for (final id in seed.attendees) id: rsvpAt},
    imagePath: _imageFor(seed.imagePath, seed.id, 1200, 800),
    createdByUserId: seed.clubId == kGuestBoardClubId ? kGuestUserId : null,
    tags: localeService.languageCode == 'tr'
        ? List<String>.of(seed.tagsTr)
        : List<String>.of(seed.tagsEn),
    accentColorHex: seed.accentColorHex,
    capacity: seed.capacity,
    schedule: seed.withSchedule
        ? [
            EventSlot(time: start, title: _t('Doors open', 'Kapılar açılıyor')),
            EventSlot(
              time: start.add(const Duration(minutes: 30)),
              title: _t('Opening remarks', 'Açılış konuşması'),
              isHighlighted: true,
            ),
            EventSlot(
              time: start.add(const Duration(hours: 1)),
              title: _t('Main session', 'Ana oturum'),
              subtitle: _t('Two rounds', 'İki tur'),
            ),
            EventSlot(
              time: start.add(Duration(hours: seed.durationHours)),
              title: _t('Close and social', 'Kapanış ve sohbet'),
            ),
          ]
        : null,
    speakers: seed.withSpeakers
        ? [
            EventSpeaker(
              name: 'Elif Yıldız',
              role: _t('Chair', 'Oturum başkanı'),
            ),
            EventSpeaker(name: 'Mert Şahin', role: _t('Panellist', 'Panelist')),
          ]
        : const [],
  );
}

Map<String, String> _boardTitles() => {
  kGuestUserId: _t('Vice President', 'Başkan Yardımcısı'),
  'guest_u_omer': _t('Secretary', 'Sekreter'),
  'guest_u_elif': _t('Head of Training', 'Eğitim Sorumlusu'),
};

/// Replaces the seeded rows of [target] in place, leaving anything the guest
/// created themselves untouched. Ids are stable, so interaction state that
/// references them survives a language flip.
void _replaceSeeded<T>(
  List<T> target,
  List<T> seeded,
  String Function(T) idOf,
) {
  target.removeWhere((row) => idOf(row).startsWith(kGuestIdPrefix));
  target.insertAll(0, seeded);
}

/// (Re)builds every localized row. Called by [seedGuestWorld], and again by
/// [refreshGuestWorldLocale] when the EN/TR toggle flips.
void _applyLocalizedRows() {
  for (final seed in _clubSeeds) {
    final isBoardClub = seed.id == kGuestBoardClubId;
    final existing = clubForId(seed.id);
    if (existing == null) {
      upsertClub(
        Club(
          id: seed.id,
          name: seed.name,
          shortName: seed.shortName,
          description: _t(seed.descEn, seed.descTr),
          categoryName: _t(seed.categoryEn, seed.categoryTr),
          logoUrl: _useRemotePhotos ? _photoUrl(seed.id, 400, 400) : null,
          email: '${seed.id}@guest.invalid',
          adminUserIds: const [],
          createdAt: _hoursAgo(24 * 400),
          boardMemberIds: isBoardClub
              ? [kGuestUserId, 'guest_u_omer', 'guest_u_elif']
              : [],
          boardMemberTitles: isBoardClub ? _boardTitles() : {},
        ),
      );
    } else {
      // description/categoryName are mutable on Club, so a language flip
      // updates the same instance every screen already holds a reference to.
      existing.description = _t(seed.descEn, seed.descTr);
      existing.categoryName = _t(seed.categoryEn, seed.categoryTr);
      existing.logoUrl = _useRemotePhotos ? _photoUrl(seed.id, 400, 400) : null;
      if (isBoardClub) {
        existing.boardMemberTitles
          ..clear()
          ..addAll(_boardTitles());
      }
    }
  }

  _replaceSeeded(newsPosts, _postSeeds.map(_postFor).toList(), (p) => p.id);
  _replaceSeeded(events, _eventSeeds.map(_eventFor).toList(), (e) => e.id);
  _replaceSeeded(
    comments,
    _commentSeeds
        .map(
          (seed) => Comment(
            id: seed.id,
            postId: seed.postId,
            userId: seed.userId,
            content: _t(seed.en, seed.tr),
            createdAt: _hoursAgo(seed.ageHours),
          ),
        )
        .toList(),
    (comment) => comment.id,
  );

  final notifs = _notificationSeeds
      .map(
        (seed) => AppNotification(
          id: seed.id,
          userId: kGuestUserId,
          message: _t(seed.en, seed.tr),
          createdAt: DateTime.now().subtract(
            Duration(minutes: seed.ageMinutes),
          ),
          read: seed.read,
          targetType: seed.targetType,
          targetId: seed.targetId,
          fromId: seed.fromId,
        ),
      )
      .toList();
  _replaceSeeded(notifications, notifs, (n) => n.id);
  _replaceSeeded(userState.dynamicNotifications, notifs, (n) => n.id);

  // The guest's own label is translated, so rebuild the seeded rows (ids are
  // stable) and push the new name into the live session too, or the Home
  // greeting keeps whichever language the joyride started in.
  _replaceSeeded(users, _people.map(_userFor).toList(), (user) => user.id);
  if (authService.currentUser?.id == kGuestUserId) {
    authService.updateCurrentUserName(guestSessionUser().name);
  }

  for (final person in _people) {
    userState.majors[person.id] = _t(person.majorEn, person.majorTr);
    userState.years[person.id] = _t(person.yearEn, person.yearTr);
    userState.bios[person.id] = _t(person.bioEn, person.bioTr);
  }
}

// ── Conversations ───────────────────────────────────────────────────────────

const String _guestGroupId = 'guest_group_board';

class _MessageSeed {
  const _MessageSeed(
    this.id,
    this.senderId, {
    required this.en,
    required this.tr,
    required this.ageMinutes,
    this.kind = ChatMessageKind.text,
    this.titleEn,
    this.titleTr,
    this.pollOptionsEn,
    this.pollOptionsTr,
    this.seen = true,
  });

  final String id;
  final String senderId;
  final String en;
  final String tr;
  final int ageMinutes;
  final ChatMessageKind kind;
  final String? titleEn;
  final String? titleTr;
  final List<String>? pollOptionsEn;
  final List<String>? pollOptionsTr;
  final bool seen;
}

const List<_MessageSeed> _dmSelin = [
  _MessageSeed(
    'guest_m_selin_1',
    'guest_u_selin',
    en: 'Are you coming to build night on Thursday?',
    tr: 'Perşembe atölye gecesine geliyor musun?',
    ageMinutes: 190,
  ),
  _MessageSeed(
    'guest_m_selin_2',
    kGuestUserId,
    en: 'Planning to. Debate finishes at eight so I will be late.',
    tr: 'Planlıyorum. Tartışma sekizde bitiyor, o yüzden geç kalacağım.',
    ageMinutes: 185,
  ),
  _MessageSeed(
    'guest_m_selin_3',
    'guest_u_selin',
    en: 'That is fine, we go until eleven. Bring the calipers if you still have them.',
    tr: 'Sorun değil, on bire kadar devam ediyoruz. Kumpası hâlâ sendeyse getir.',
    ageMinutes: 180,
  ),
  _MessageSeed(
    'guest_m_selin_4',
    kGuestUserId,
    en: 'They are in my locker. See you Thursday.',
    tr: 'Dolabımda. Perşembe görüşürüz.',
    ageMinutes: 176,
  ),
  _MessageSeed(
    'guest_m_selin_5',
    'guest_u_selin',
    en: 'The line-follower finally finished a clean lap by the way. Six weeks.',
    tr: 'Bu arada çizgi izleyen sonunda temiz bir tur attı. Altı hafta.',
    ageMinutes: 42,
    seen: false,
  ),
];

const List<_MessageSeed> _dmOmer = [
  _MessageSeed(
    'guest_m_omer_1',
    'guest_u_omer',
    en: 'Did you see the motion for Thursday? Compulsory voting.',
    tr: 'Perşembe önergesini gördün mü? Zorunlu oy.',
    ageMinutes: 320,
  ),
  _MessageSeed(
    'guest_m_omer_2',
    kGuestUserId,
    en: 'I wrote it. Thought you would enjoy arguing the other side for once.',
    tr: 'Ben yazdım. Bir kez de öteki tarafı savunmaktan keyif alırsın diye düşündüm.',
    ageMinutes: 315,
  ),
  _MessageSeed(
    'guest_m_omer_3',
    'guest_u_omer',
    en: 'Cruel. I will take opposition and win anyway.',
    tr: 'Zalimlik. Muhalefeti alıp yine de kazanacağım.',
    ageMinutes: 300,
  ),
  _MessageSeed(
    'guest_m_omer_4',
    kGuestUserId,
    en: 'We have four first-timers signed up, so go gently in the practice round.',
    tr: 'Dört yeni katılımcı kaydoldu, deneme turunda yumuşak ol.',
    ageMinutes: 120,
  ),
];

const List<_MessageSeed> _dmElif = [
  _MessageSeed(
    'guest_m_elif_1',
    kGuestUserId,
    en: 'Best speaker in the final. Genuinely deserved.',
    tr: 'Finalde en iyi konuşmacı. Gerçekten hak ettin.',
    ageMinutes: 2400,
  ),
  _MessageSeed(
    'guest_m_elif_2',
    'guest_u_elif',
    en: 'Thank you. Second overall is the best we have ever done, no?',
    tr: 'Teşekkürler. Genel ikincilik şimdiye kadarki en iyimiz, değil mi?',
    ageMinutes: 2380,
  ),
  _MessageSeed(
    'guest_m_elif_3',
    kGuestUserId,
    en: 'By two places. I will put the write-up on the board tonight.',
    tr: 'İki sıra farkla. Yazıyı bu akşam panoya koyacağım.',
    ageMinutes: 2360,
  ),
];

const List<_MessageSeed> _groupBoard = [
  _MessageSeed(
    'guest_m_grp_1',
    'guest_u_elif',
    en: 'Board sync before Thursday? Twenty minutes, that is all.',
    tr: 'Perşembeden önce yönetim toplantısı? Yirmi dakika, hepsi bu.',
    ageMinutes: 500,
  ),
  _MessageSeed(
    'guest_m_grp_2',
    kGuestUserId,
    en: 'Wednesday 17:00 in the usual room. I will bring the sign-up sheet.',
    tr: 'Çarşamba 17:00, her zamanki odada. Kayıt listesini getireceğim.',
    ageMinutes: 480,
  ),
  _MessageSeed(
    'guest_m_grp_3',
    'guest_u_omer',
    en: 'Works for me. We should talk about the Model UN places too.',
    tr: 'Bana uygun. Model BM yerlerini de konuşmalıyız.',
    ageMinutes: 470,
  ),
  _MessageSeed(
    'guest_m_grp_4',
    'guest_u_elif',
    en: 'Agreed. Four committees and we still have not decided who chairs.',
    tr: 'Katılıyorum. Dört komite var ve kimin başkanlık edeceğine hâlâ karar vermedik.',
    ageMinutes: 60,
    seen: false,
  ),
];

const List<_MessageSeed> _clubChannel = [
  _MessageSeed(
    'guest_m_club_1',
    kGuestUserId,
    en:
        'Thursday is a full parliamentary round plus a practice slot for anyone '
        'new. Sign-ups close Wednesday noon.',
    tr:
        'Perşembe tam bir parlamenter tur ve yeni katılanlar için bir deneme '
        'slotu var. Kayıtlar çarşamba öğlen kapanıyor.',
    ageMinutes: 600,
    kind: ChatMessageKind.announcement,
    titleEn: 'Thursday round: sign-ups close Wednesday',
    titleTr: 'Perşembe turu: kayıtlar çarşamba kapanıyor',
  ),
  _MessageSeed(
    'guest_m_club_2',
    'guest_u_can',
    en: 'Is the practice slot really fine for a first-year with no experience?',
    tr: 'Deneme slotu deneyimi olmayan bir birinci sınıf için gerçekten uygun mu?',
    ageMinutes: 540,
  ),
  _MessageSeed(
    'guest_m_club_3',
    'guest_u_elif',
    en: 'That is exactly who it is for. Come and watch first if you prefer.',
    tr: 'Tam olarak onun için var. İstersen önce gelip izle.',
    ageMinutes: 520,
  ),
  _MessageSeed(
    'guest_m_club_4',
    kGuestUserId,
    en: 'Which night suits everyone for the extra training session?',
    tr: 'Ek antrenman oturumu için hangi akşam herkese uygun?',
    ageMinutes: 300,
    kind: ChatMessageKind.poll,
    titleEn: 'Extra training session',
    titleTr: 'Ek antrenman oturumu',
    pollOptionsEn: ['Monday', 'Tuesday', 'Friday'],
    pollOptionsTr: ['Pazartesi', 'Salı', 'Cuma'],
  ),
  _MessageSeed(
    'guest_m_club_5',
    'guest_u_nil',
    en: 'Friday for me, Mondays clash with volunteering.',
    tr: 'Benim için cuma, pazartesiler gönüllülükle çakışıyor.',
    ageMinutes: 250,
  ),
  _MessageSeed(
    'guest_m_club_6',
    kGuestUserId,
    en:
        'Motion slips and the judging rubric are pinned here from now on, so '
        'nobody has to dig through the group chat for them.',
    tr:
        'Önerge kâğıtları ve değerlendirme cetveli artık burada sabit, kimse '
        'grup sohbetini karıştırmak zorunda kalmasın.',
    ageMinutes: 180,
    kind: ChatMessageKind.announcement,
    titleEn: 'Motion slips and rubric are pinned',
    titleTr: 'Önerge kâğıtları ve cetvel sabitlendi',
  ),
  _MessageSeed(
    'guest_m_club_7',
    'guest_u_ayse',
    en: 'Thank you, I lost the rubric twice last semester.',
    tr: 'Teşekkürler, geçen dönem cetveli iki kez kaybettim.',
    ageMinutes: 150,
  ),
  _MessageSeed(
    'guest_m_club_8',
    'guest_u_omer',
    en: 'Reminder that the room changes to SOS 104 for the final round.',
    tr: 'Final turu için salonun SOS 104 olarak değiştiğini hatırlatayım.',
    ageMinutes: 90,
  ),
];

const List<_MessageSeed> _clubChannelHiking = [
  _MessageSeed(
    'guest_m_hike_1',
    'guest_u_burak',
    en:
        'Sunday is the ridge loop — 11km, one steep hour at the start, back by '
        '14:00. Boots, not trainers.',
    tr:
        'Pazar sırt turu var — 11km, başta bir saat dik, 14:00\'te dönüş. '
        'Spor ayakkabı değil, bot.',
    ageMinutes: 640,
    kind: ChatMessageKind.announcement,
    titleEn: 'Sunday: ridge loop, 11km',
    titleTr: 'Pazar: sırt turu, 11km',
  ),
  _MessageSeed(
    'guest_m_hike_2',
    'guest_u_ayse',
    en: 'Is there a bail-out point if someone needs to turn back early?',
    tr: 'Erken dönmek isteyen olursa ayrılma noktası var mı?',
    ageMinutes: 580,
  ),
  _MessageSeed(
    'guest_m_hike_3',
    'guest_u_burak',
    en: 'Yes, at the second gate. It is a twenty minute walk back to the road.',
    tr: 'Var, ikinci kapıda. Yola kadar yirmi dakikalık bir yürüyüş.',
    ageMinutes: 545,
  ),
  _MessageSeed(
    'guest_m_hike_4',
    'guest_u_mert',
    en: 'Two spare rain shells in the equipment box if anyone needs one.',
    tr: 'İhtiyacı olan olursa ekipman kutusunda iki yedek yağmurluk var.',
    ageMinutes: 300,
  ),
  _MessageSeed(
    'guest_m_hike_5',
    'guest_u_burak',
    en:
        'Carpool sign-up is open. Four drivers so far, which covers about '
        'sixteen people.',
    tr:
        'Araç paylaşımı kaydı açık. Şimdilik dört sürücü var, yaklaşık on altı '
        'kişiyi kapsıyor.',
    ageMinutes: 200,
    kind: ChatMessageKind.announcement,
    titleEn: 'Carpool sign-up is open',
    titleTr: 'Araç paylaşımı kaydı açık',
  ),
];

const List<_MessageSeed> _clubChannelMusic = [
  _MessageSeed(
    'guest_m_choir_1',
    'guest_u_zeynep',
    en:
        'Winter concert programme is settled: two folk arrangements, one '
        'contemporary piece, and the piece we commissioned.',
    tr:
        'Kış konseri programı belli: iki halk müziği düzenlemesi, bir çağdaş '
        'eser ve sipariş ettiğimiz parça.',
    ageMinutes: 820,
    kind: ChatMessageKind.announcement,
    titleEn: 'Winter concert programme is set',
    titleTr: 'Kış konseri programı belirlendi',
  ),
  _MessageSeed(
    'guest_m_choir_2',
    'guest_u_nil',
    en: 'Are the alto parts going out before rehearsal or at it?',
    tr: 'Alto partisyonları provadan önce mi dağıtılıyor, provada mı?',
    ageMinutes: 760,
  ),
  _MessageSeed(
    'guest_m_choir_3',
    'guest_u_zeynep',
    en: 'Before. They go up tonight so you have the week with them.',
    tr: 'Öncesinde. Bu akşam yükleniyor, bir haftan olsun diye.',
    ageMinutes: 730,
  ),
  _MessageSeed(
    'guest_m_choir_4',
    'guest_u_zeynep',
    en: 'Which rehearsal slot works better once the concert week starts?',
    tr: 'Konser haftası başlayınca hangi prova saati daha iyi olur?',
    ageMinutes: 400,
    kind: ChatMessageKind.poll,
    titleEn: 'Concert week rehearsal',
    titleTr: 'Konser haftası provası',
    pollOptionsEn: ['Tue 18:00', 'Wed 19:00', 'Sat 11:00'],
    pollOptionsTr: ['Salı 18:00', 'Çarşamba 19:00', 'Cumartesi 11:00'],
  ),
  _MessageSeed(
    'guest_m_choir_5',
    'guest_u_ipek',
    en: 'Saturday morning, the weekday ones always run into lab hours.',
    tr: 'Cumartesi sabahı, hafta içi olanlar hep laboratuvara denk geliyor.',
    ageMinutes: 340,
  ),
];

const List<_MessageSeed> _clubChannelVolunteer = [
  _MessageSeed(
    'guest_m_vol_1',
    'guest_u_ayse',
    en:
        'Saturday reading session at the community centre needs six people. '
        'Two hours, and the kids are six to nine.',
    tr:
        'Cumartesi toplum merkezindeki okuma seansı için altı kişi gerekiyor. '
        'İki saat, çocuklar altı-dokuz yaş arası.',
    ageMinutes: 700,
    kind: ChatMessageKind.announcement,
    titleEn: 'Saturday reading session needs six',
    titleTr: 'Cumartesi okuma seansı için altı kişi',
  ),
  _MessageSeed(
    'guest_m_vol_2',
    'guest_u_can',
    en: 'I can take it. Do we need any training first?',
    tr: 'Ben alabilirim. Önce bir eğitim gerekiyor mu?',
    ageMinutes: 660,
  ),
  _MessageSeed(
    'guest_m_vol_3',
    'guest_u_ayse',
    en: 'A short briefing on the day, half an hour before we start.',
    tr: 'Aynı gün kısa bir bilgilendirme, başlamadan yarım saat önce.',
    ageMinutes: 620,
  ),
  _MessageSeed(
    'guest_m_vol_4',
    'guest_u_mert',
    en: 'Four of the six spots are taken now.',
    tr: 'Altı yerin dördü şu an dolu.',
    ageMinutes: 280,
  ),
  _MessageSeed(
    'guest_m_vol_5',
    'guest_u_ayse',
    en:
        'Winter clothing drive starts next week. Collection boxes go in both '
        'library entrances.',
    tr:
        'Kışlık kıyafet toplama önümüzdeki hafta başlıyor. Kutular her iki '
        'kütüphane girişine konulacak.',
    ageMinutes: 240,
    kind: ChatMessageKind.announcement,
    titleEn: 'Winter clothing drive starts next week',
    titleTr: 'Kışlık kıyafet toplama haftaya başlıyor',
  ),
];

const List<_MessageSeed> _clubChannelEntre = [
  _MessageSeed(
    'guest_m_entre_1',
    'guest_u_mert',
    en:
        'Pitch night sign-ups close Friday. Nine slots, four minutes each, and '
        'you do not need slides — most of the good ones just talk.',
    tr:
        'Sunum gecesi kayıtları cuma kapanıyor. Dokuz slot, her birine dört '
        'dakika ve slayta gerek yok — iyi olanların çoğu sadece anlatıyor.',
    ageMinutes: 540,
    kind: ChatMessageKind.announcement,
    titleEn: 'Pitch night sign-ups close Friday',
    titleTr: 'Sunum gecesi kayıtları cuma kapanıyor',
  ),
  _MessageSeed(
    'guest_m_entre_2',
    'guest_u_can',
    en: 'Can I pitch something that is still just a landing page?',
    tr: 'Henüz sadece bir açılış sayfası olan bir şeyi sunabilir miyim?',
    ageMinutes: 505,
  ),
  _MessageSeed(
    'guest_m_entre_3',
    'guest_u_mert',
    en: 'Yes. Half the room is at that stage and the questions are kinder.',
    tr: 'Evet. Salonun yarısı o aşamada ve sorular daha yumuşak oluyor.',
    ageMinutes: 470,
  ),
  _MessageSeed(
    'guest_m_entre_4',
    'guest_u_burak',
    en:
        'Mentor hours moved to Wednesday afternoons. Same room, twenty-minute '
        'slots, sheet is on the board.',
    tr:
        'Mentor saatleri çarşamba öğleden sonralarına taşındı. Aynı oda, '
        'yirmi dakikalık görüşmeler, liste panoda.',
    ageMinutes: 300,
  ),
  _MessageSeed(
    'guest_m_entre_5',
    'guest_u_mert',
    en:
        'Demo day is confirmed for May and the room holds six teams. '
        'Applications open after reading week.',
    tr:
        'Demo günü mayıs için kesinleşti ve salon altı takım alıyor. '
        'Başvurular ara tatilden sonra açılıyor.',
    ageMinutes: 180,
    kind: ChatMessageKind.announcement,
    titleEn: 'Demo day confirmed for May',
    titleTr: 'Demo günü mayısta',
  ),
];

/// A club's general channel — the room every follower can read and only the
/// board can post in.
///
/// [boardVoiceId] is the sender whose messages are presented as the club itself,
/// the way a board member posting in the room appears under the club's name and
/// avatar rather than their own.
class _ClubChannelSeed {
  const _ClubChannelSeed(this.clubId, this.boardVoiceId, this.messages);

  final String clubId;
  final String boardVoiceId;
  final List<_MessageSeed> messages;
}

/// The guest's own one-to-one thread with a club — the room's Direct lane.
///
/// Real conversations are created by `ensureClubInboxThread`, which is a
/// Supabase round trip, so a guest has none and the lane renders empty however
/// much is seeded elsewhere. [replyFromId] answers as the club: a board
/// member's id carried with `senderClubId` set, which is exactly the shape
/// `ChatStore.sendMessage` produces for a club replying to a student.
class _ClubInboxSeed {
  const _ClubInboxSeed(
    this.clubId,
    this.replyFromId, {
    required this.askEn,
    required this.askTr,
    required this.replyEn,
    required this.replyTr,
    required this.askAgeMinutes,
    required this.replyAgeMinutes,
    this.replySeen = true,
  });

  final String clubId;
  final String replyFromId;
  final String askEn;
  final String askTr;
  final String replyEn;
  final String replyTr;
  final int askAgeMinutes;
  final int replyAgeMinutes;
  final bool replySeen;

  String get inboxId => 'guest_inbox_$clubId';
}

const List<_ClubInboxSeed> _clubInboxSeeds = [
  _ClubInboxSeed(
    kGuestBoardClubId,
    'guest_u_omer',
    askEn: 'Do I need to bring anything to the practice round on Thursday?',
    askTr: 'Perşembe deneme turuna bir şey getirmem gerekiyor mu?',
    replyEn: 'Just a notebook. We hand out the motion on the night.',
    replyTr: 'Sadece bir defter. Önergeyi o akşam dağıtıyoruz.',
    askAgeMinutes: 320,
    replyAgeMinutes: 295,
  ),
  _ClubInboxSeed(
    'guest_club_robotics',
    'guest_u_selin',
    askEn: 'Is there space on the arm subteam, or is it full for this term?',
    askTr: 'Kol alt ekibinde yer var mı, yoksa bu dönem doldu mu?',
    replyEn: 'Two spots left. Come to build night and we will pair you up.',
    replyTr: 'İki yer kaldı. Atölye gecesine gel, seni eşleştirelim.',
    askAgeMinutes: 430,
    replyAgeMinutes: 400,
  ),
  _ClubInboxSeed(
    'guest_club_photo',
    'guest_u_ipek',
    askEn: 'I have never used a darkroom. Is the induction beginner friendly?',
    askTr:
        'Daha önce karanlık oda kullanmadım. Eğitim yeni başlayanlara uygun mu?',
    replyEn: 'Completely. Most people at the Tuesday one have never printed.',
    replyTr: 'Tamamen. Salı grubundaki çoğu kişi hiç baskı yapmamış.',
    askAgeMinutes: 560,
    replyAgeMinutes: 520,
  ),
  _ClubInboxSeed(
    'guest_club_film',
    'guest_u_kaan',
    askEn: 'Can I suggest a film even though I only joined this week?',
    askTr: 'Bu hafta katılmış olmama rağmen film önerebilir miyim?',
    replyEn: 'Please do. New members usually pick the most interesting ones.',
    replyTr: 'Lütfen öner. Yeni üyeler genelde en ilginçlerini seçiyor.',
    askAgeMinutes: 240,
    replyAgeMinutes: 205,
    replySeen: false,
  ),
  _ClubInboxSeed(
    'guest_club_hiking',
    'guest_u_burak',
    askEn: 'How hard is the ridge loop if I have only done flat walks?',
    askTr: 'Sadece düz yürüyüş yaptıysam sırt turu ne kadar zor?',
    replyEn: 'The first hour is the hard part. After that it is comfortable.',
    replyTr: 'Zor kısmı ilk bir saat. Sonrası rahat.',
    askAgeMinutes: 380,
    replyAgeMinutes: 350,
  ),
  _ClubInboxSeed(
    'guest_club_music',
    'guest_u_zeynep',
    askEn: 'Is there an audition, or can I just come to a rehearsal?',
    askTr: 'Seçme var mı, yoksa provaya gelsem yeter mi?',
    replyEn: 'Just come. We place voices in the first ten minutes.',
    replyTr: 'Sadece gel. Sesleri ilk on dakikada yerleştiriyoruz.',
    askAgeMinutes: 610,
    replyAgeMinutes: 580,
  ),
  _ClubInboxSeed(
    'guest_club_volunteer',
    'guest_u_ayse',
    askEn: 'Can I sign up for one session without committing to every week?',
    askTr: 'Her haftaya söz vermeden tek seans için kaydolabilir miyim?',
    replyEn: 'That is how most people start. One session is completely fine.',
    replyTr: 'Çoğu kişi böyle başlıyor. Tek seans tamamen olur.',
    askAgeMinutes: 480,
    replyAgeMinutes: 450,
    replySeen: false,
  ),
  _ClubInboxSeed(
    'guest_club_entre',
    'guest_u_mert',
    askEn: 'Is pitch night only for teams, or can I come and watch first?',
    askTr:
        'Sunum gecesi sadece takımlar için mi, önce izlemeye gelebilir '
        'miyim?',
    replyEn: 'Come and watch. Most people pitch the second time they turn up.',
    replyTr: 'Gel ve izle. Çoğu kişi ikinci gelişinde sunuyor.',
    askAgeMinutes: 520,
    replyAgeMinutes: 490,
  ),
];

ClubInboxConversation _clubInboxFor(_ClubInboxSeed seed) =>
    ClubInboxConversation(
      id: seed.inboxId,
      clubId: seed.clubId,
      profileId: kGuestUserId,
      createdAt: _hoursAgo(seed.askAgeMinutes ~/ 60 + 1),
      updatedAt: DateTime.now().subtract(
        Duration(minutes: seed.replyAgeMinutes),
      ),
    );

List<ChatMessage> _clubInboxMessages(_ClubInboxSeed seed) {
  final threadId = ChatStore.clubInboxThreadId(seed.inboxId);
  final askAt = DateTime.now().subtract(Duration(minutes: seed.askAgeMinutes));
  final replyAt = DateTime.now().subtract(
    Duration(minutes: seed.replyAgeMinutes),
  );
  return [
    ChatMessage(
      id: 'guest_m_${seed.inboxId}_ask',
      threadId: threadId,
      senderId: kGuestUserId,
      senderAuthId: kGuestUserId,
      content: _t(seed.askEn, seed.askTr),
      createdAt: askAt,
      deliveredAt: askAt,
      seenAt: askAt.add(const Duration(minutes: 2)),
    ),
    ChatMessage(
      id: 'guest_m_${seed.inboxId}_reply',
      threadId: threadId,
      senderId: seed.replyFromId,
      senderAuthId: seed.replyFromId,
      // The club answers as itself, not as the board member who typed it.
      senderClubId: seed.clubId,
      content: _t(seed.replyEn, seed.replyTr),
      createdAt: replyAt,
      deliveredAt: replyAt,
      seenAt: seed.replySeen
          ? replyAt.add(const Duration(minutes: 3))
          : null,
    ),
  ];
}

/// The guest is on the debate club's board, so that room is the one they can
/// write in. The rest are clubs they merely follow, which is what puts the
/// read-only composer on screen — the single most confusing state in the app
/// to explain in words and the easiest to understand by seeing it.
///
/// One per seeded club: the guest is joined to all of them, and a joined club
/// with no channel opens as an empty room.
const List<_ClubChannelSeed> _clubChannels = [
  _ClubChannelSeed(kGuestBoardClubId, kGuestUserId, _clubChannel),
  _ClubChannelSeed(
    'guest_club_robotics',
    'guest_u_selin',
    _clubChannelRobotics,
  ),
  _ClubChannelSeed('guest_club_photo', 'guest_u_ipek', _clubChannelPhoto),
  _ClubChannelSeed('guest_club_film', 'guest_u_kaan', _clubChannelFilm),
  _ClubChannelSeed('guest_club_hiking', 'guest_u_burak', _clubChannelHiking),
  _ClubChannelSeed('guest_club_music', 'guest_u_zeynep', _clubChannelMusic),
  _ClubChannelSeed(
    'guest_club_volunteer',
    'guest_u_ayse',
    _clubChannelVolunteer,
  ),
  _ClubChannelSeed('guest_club_entre', 'guest_u_mert', _clubChannelEntre),
];

const List<_MessageSeed> _clubChannelRobotics = [
  _MessageSeed(
    'guest_m_robo_1',
    'guest_u_selin',
    en:
        'Build night moves to the new fabrication lab from this week. Same time, '
        'one floor up — bring your access card.',
    tr:
        'Atölye gecesi bu haftadan itibaren yeni üretim laboratuvarına taşınıyor. '
        'Aynı saat, bir üst kat — kartını getir.',
    ageMinutes: 430,
    kind: ChatMessageKind.announcement,
    titleEn: 'Build night: new lab, one floor up',
    titleTr: 'Atölye gecesi: yeni lab, bir üst kat',
  ),
  _MessageSeed(
    'guest_m_robo_2',
    'guest_u_can',
    en: 'Are the soldering stations already moved, or do we carry ours over?',
    tr: 'Lehim istasyonları taşındı mı, yoksa kendimiz mi götürüyoruz?',
    ageMinutes: 390,
  ),
  _MessageSeed(
    'guest_m_robo_3',
    'guest_u_selin',
    en: 'All eight are installed and tested. Only bring your own project boxes.',
    tr: 'Sekizi de kuruldu ve test edildi. Sadece kendi proje kutunuzu getirin.',
    ageMinutes: 360,
  ),
  _MessageSeed(
    'guest_m_robo_4',
    'guest_u_mert',
    en: 'The new lab has proper extraction too. Big upgrade.',
    tr: 'Yeni labda düzgün havalandırma da var. Büyük bir iyileşme.',
    ageMinutes: 200,
  ),
  _MessageSeed(
    'guest_m_robo_5',
    'guest_u_selin',
    en:
        'Parts order closes Sunday. Add what your subteam needs to the shared '
        'sheet and put your name next to it.',
    tr:
        'Parça siparişi pazar kapanıyor. Alt ekibinin ihtiyacını ortak tabloya '
        'ekle ve yanına adını yaz.',
    ageMinutes: 160,
    kind: ChatMessageKind.announcement,
    titleEn: 'Parts order closes Sunday',
    titleTr: 'Parça siparişi pazar kapanıyor',
  ),
  _MessageSeed(
    'guest_m_robo_6',
    'guest_u_kaan',
    en: 'Added two servos for the arm. Ours stripped during testing.',
    tr: 'Kol için iki servo ekledim. Bizimkiler test sırasında sıyrıldı.',
    ageMinutes: 120,
  ),
];

const List<_MessageSeed> _clubChannelPhoto = [
  _MessageSeed(
    'guest_m_photo_1',
    'guest_u_ipek',
    en:
        'Golden-hour walk on Saturday starts at the south gate at 06:40. We stop '
        'for coffee at the halfway point.',
    tr:
        'Cumartesi altın saat yürüyüşü 06:40\'ta güney kapısında başlıyor. Yolun '
        'yarısında kahve molası veriyoruz.',
    ageMinutes: 700,
    kind: ChatMessageKind.announcement,
    titleEn: 'Saturday golden-hour walk, 06:40',
    titleTr: 'Cumartesi altın saat yürüyüşü, 06:40',
  ),
  _MessageSeed(
    'guest_m_photo_2',
    'guest_u_ipek',
    en: 'What should the theme be for this month\'s print wall?',
    tr: 'Bu ayın baskı duvarı için tema ne olsun?',
    ageMinutes: 520,
    kind: ChatMessageKind.poll,
    titleEn: 'Print wall theme',
    titleTr: 'Baskı duvarı teması',
    pollOptionsEn: ['Night campus', 'Portraits', 'Reflections'],
    pollOptionsTr: ['Gece kampüs', 'Portreler', 'Yansımalar'],
  ),
  _MessageSeed(
    'guest_m_photo_3',
    'guest_u_zeynep',
    en: 'Reflections — the rain last week gave everyone something to work with.',
    tr: 'Yansımalar — geçen haftaki yağmur herkese malzeme verdi.',
    ageMinutes: 480,
  ),
  _MessageSeed(
    'guest_m_photo_4',
    'guest_u_burak',
    en: 'Can we borrow a tripod for the walk or should we bring our own?',
    tr: 'Yürüyüş için tripod alabilir miyiz yoksa kendimiz mi getirmeliyiz?',
    ageMinutes: 240,
  ),
  _MessageSeed(
    'guest_m_photo_5',
    'guest_u_ipek',
    en: 'Four club tripods live in the studio cupboard — first come, first served.',
    tr: 'Dört kulüp tripodu stüdyo dolabında — ilk gelen alır.',
    ageMinutes: 210,
  ),
  _MessageSeed(
    'guest_m_photo_6',
    'guest_u_ipek',
    en:
        'Darkroom inductions are Tuesday and Thursday at 17:00. You need one '
        'before you can book a slot on your own.',
    tr:
        'Karanlık oda eğitimleri salı ve perşembe 17:00\'de. Kendi başına slot '
        'ayırabilmen için bir tanesine katılman gerekiyor.',
    ageMinutes: 150,
    kind: ChatMessageKind.announcement,
    titleEn: 'Darkroom inductions: Tue & Thu, 17:00',
    titleTr: 'Karanlık oda eğitimi: salı ve perşembe 17:00',
  ),
];

const List<_MessageSeed> _clubChannelFilm = [
  _MessageSeed(
    'guest_m_film_1',
    'guest_u_kaan',
    en:
        'This week\'s screening is the 1966 print, not the restoration. Doors at '
        '19:00, discussion straight after.',
    tr:
        'Bu haftanın gösterimi restorasyon değil 1966 kopyası. Kapılar 19:00\'da, '
        'hemen ardından söyleşi var.',
    ageMinutes: 900,
    kind: ChatMessageKind.announcement,
    titleEn: 'Thursday screening: the 1966 print',
    titleTr: 'Perşembe gösterimi: 1966 kopyası',
  ),
  _MessageSeed(
    'guest_m_film_2',
    'guest_u_ayse',
    en: 'Is the discussion open to people who have not seen it before?',
    tr: 'Söyleşi daha önce izlemeyenlere de açık mı?',
    ageMinutes: 820,
  ),
  _MessageSeed(
    'guest_m_film_3',
    'guest_u_kaan',
    en: 'Completely. Half the room is usually seeing it for the first time.',
    tr: 'Tamamen. Salonun yarısı genelde ilk kez izliyor.',
    ageMinutes: 780,
  ),
  _MessageSeed(
    'guest_m_film_4',
    'guest_u_nil',
    en: 'Saving a seat near the front if anyone wants to join me.',
    tr: 'Öne yakın bir yer tutuyorum, katılmak isteyen olursa.',
    ageMinutes: 300,
  ),
  _MessageSeed(
    'guest_m_film_5',
    'guest_u_kaan',
    en:
        'Next term\'s programme is open for suggestions until the end of the '
        'month. One film per person, and say why.',
    tr:
        'Gelecek dönemin programı ay sonuna kadar önerilere açık. Kişi başı bir '
        'film, ve nedenini yaz.',
    ageMinutes: 260,
    kind: ChatMessageKind.announcement,
    titleEn: 'Suggestions open for next term',
    titleTr: 'Gelecek dönem için öneriler açık',
  ),
  _MessageSeed(
    'guest_m_film_6',
    'guest_u_zeynep',
    en: 'Putting forward Chungking Express. It deserves a room this size.',
    tr: 'Chungking Express öneriyorum. Bu büyüklükte bir salonu hak ediyor.',
    ageMinutes: 180,
  ),
];

ChatMessage _messageFor(
  _MessageSeed seed,
  String threadId, {
  String? senderClubId,
}) {
  final createdAt = DateTime.now().subtract(Duration(minutes: seed.ageMinutes));
  return ChatMessage(
    id: seed.id,
    threadId: threadId,
    senderId: seed.senderId,
    senderClubId: senderClubId,
    content: _t(seed.en, seed.tr),
    createdAt: createdAt,
    seenAt: seed.seen ? createdAt.add(const Duration(minutes: 1)) : null,
    kind: seed.kind,
    title: seed.titleEn == null ? null : _t(seed.titleEn!, seed.titleTr!),
    pollOptions: seed.pollOptionsEn == null
        ? const []
        : (localeService.languageCode == 'tr'
              ? List<String>.of(seed.pollOptionsTr!)
              : List<String>.of(seed.pollOptionsEn!)),
    pollVotes: seed.kind == ChatMessageKind.poll
        ? const {'guest_u_nil': 2, 'guest_u_omer': 0, 'guest_u_elif': 2}
        : const {},
  );
}

ChatGroup _guestGroup() => ChatGroup(
  id: _guestGroupId,
  creatorId: kGuestUserId,
  memberIds: const [kGuestUserId, 'guest_u_omer', 'guest_u_elif'],
  adminIds: const [kGuestUserId],
  customName: _t('Debate Board', 'Tartışma Yönetimi'),
  photoUrl: null,
  createdAt: _hoursAgo(24 * 120),
);

void _seedConversations() {
  final selinThread = ChatStore.dmThreadId(kGuestUserId, 'guest_u_selin');
  final omerThread = ChatStore.dmThreadId(kGuestUserId, 'guest_u_omer');
  final elifThread = ChatStore.dmThreadId(kGuestUserId, 'guest_u_elif');
  final groupThread = ChatStore.groupThreadId(_guestGroupId);

  chatStore.seedGuestConversations(
    messages: [
      for (final seed in _dmSelin) _messageFor(seed, selinThread),
      for (final seed in _dmOmer) _messageFor(seed, omerThread),
      for (final seed in _dmElif) _messageFor(seed, elifThread),
      for (final seed in _groupBoard) _messageFor(seed, groupThread),
      for (final seed in _clubInboxSeeds) ..._clubInboxMessages(seed),
      for (final channel in _clubChannels)
        for (final seed in channel.messages)
          _messageFor(
            seed,
            ChatStore.clubThreadId(channel.clubId),
            // Board-authored club messages are presented as the club itself.
            senderClubId: seed.senderId == channel.boardVoiceId
                ? channel.clubId
                : null,
          ),
    ],
    directThreadIds: [selinThread, omerThread, elifThread],
    groups: [_guestGroup()],
    clubInboxes: _clubInboxSeeds.map(_clubInboxFor),
  );
}

/// Populates the global registries with the fabricated campus.
///
/// Clears first: bootstrap opens the Hive boxes and runs
/// `ContentStore.applyToLists()` before anybody signs in, so the previous
/// occupant's cached posts and events may already be sitting in these lists.
///
/// Callers must call `guestSession.begin()` *before* this, so the persistence
/// gates are already closed and none of it can reach disk, and must establish
/// the guest identity (`AuthService.enterGuestSession`) before it too —
/// crossing an auth boundary clears ChatStore, which would otherwise throw
/// away the conversations seeded here.
void seedGuestWorld() {
  _clearRegistries();

  // `_applyLocalizedRows` seeds `users` (their labels are localized too).
  _applyLocalizedRows();

  subscriptions.addAll([
    for (final clubId in _guestFollowedClubIds)
      Subscription(
        id: 'guest_sub_me_$clubId',
        userId: kGuestUserId,
        clubId: clubId,
      ),
    for (var i = 0; i < _people.length; i++)
      Subscription(
        id: 'guest_sub_${_people[i].id}_$i',
        userId: _people[i].id,
        clubId: _clubSeeds[i % _clubSeeds.length].id,
      ),
  ]);

  // Keyed by the stable seed id, so the choice survives _applyLocalizedRows
  // rebuilding every post on an EN/TR flip.
  contentAudienceStore.seedAudiences({
    for (final seed in _postSeeds) seed.id: seed.audience,
  });

  for (final seed in _postSeeds) {
    supabasePostLikeCounts[seed.id] = seed.likeCount;
    // A few real Like rows too, so liker lists and avatar stacks are populated
    // rather than showing a bare count.
    for (final liker in _people.where((p) => p.id != seed.authorId).take(4)) {
      likes.add(
        Like(
          id: 'guest_like_${seed.id}_${liker.id}',
          postId: seed.id,
          userId: liker.id,
        ),
      );
    }
    shares.add(
      Share(
        id: 'guest_share_${seed.id}',
        targetId: seed.id,
        userId: _people[seed.ageHours % _people.length].id,
        createdAt: _hoursAgo(seed.ageHours ~/ 2 + 1),
      ),
    );
  }

  for (final seed in _clubSeeds) {
    supabaseClubMemberCounts[seed.id] = seed.memberCount;
  }
  for (final seed in _eventSeeds) {
    supabaseEventRsvpCounts[seed.id] = seed.attendees.length;
  }

  userState.replaceFollowedClubs(_guestFollowedClubIds);
  userState.replaceFollowedUsers(_guestFollowingIds);
  userState.replaceLikedPosts(_guestLikedPostIds);
  for (final id in _guestSavedPostIds) {
    userState.toggleSave(id);
  }
  userState.unreadNotifications = userState.unreadNotificationCountFor(
    userState.dynamicNotifications,
  );

  // `cachedPeople` backs the feed's people rail and the search directory;
  // `cachedFollowerIds` is the follower half of the mutual-follow graph that
  // decides whether event attendee names are visible.
  peopleService.seedFeedSuggestions(users, followerIds: _guestFollowerIds);
  peopleService.seedChatParticipants(users);
  // Both halves of the graph: the Followers/Following stats on the profile read
  // the per-user maps, not just the flat follower set above.
  peopleService.seedConnections(
    userId: kGuestUserId,
    followerIds: _guestFollowerIds,
    followingIds: _guestFollowingIds,
  );

  _seedConversations();

  _seeded = true;
  // Seed copy is bilingual, and the rows hold already-resolved strings, so the
  // language toggle has to rebuild them. Ids are stable, so nothing the guest
  // has liked, saved, voted on or RSVPed to is lost in the swap.
  localeService.addListener(refreshGuestWorldLocale);
}

/// Rebuilds the localized seed rows for the current language.
///
/// Every seeded id is deterministic, so swapping the row objects keeps the
/// guest's likes, saves, RSVPs, poll votes and comments pointing at the right
/// content. Anything the guest created themselves is left alone.
void refreshGuestWorldLocale() {
  if (!_seeded) return;
  _applyLocalizedRows();
  _seedConversations();
}

void _clearRegistries() {
  // These stores are in-memory and outlive the session. Guest interactions
  // never reach disk, but without clearing them a guest's RSVPs, votes and
  // check-ins would still be on screen after a real account signs in.
  rsvpStore.clear();
  pollStore.clearSessionState();
  contentAudienceStore.clearSessionState();
  checkinStore.clearSessionState();
  commentStore.clearSessionState();
  users.clear();
  clubs.clear();
  events.clear();
  newsPosts.clear();
  comments.clear();
  likes.clear();
  shares.clear();
  subscriptions.clear();
  notifications.clear();
  clubAdmins.clear();
  supabaseClubMemberCounts.clear();
  supabasePostLikeCounts.clear();
  supabaseEventRsvpCounts.clear();
  userState.resetForSessionBoundary();
  peopleService.clearRemoteCaches();
}

/// Tears the fabricated campus down. Called from `AuthService.logout` while the
/// guest flag is still set, so none of the emptying can be written to disk.
/// Deletes chat attachments the guest staged into the app's cache directory.
///
/// Staging is the one thing a joyride does touch on disk — a photo sent in a
/// chat is copied into the cache before it is "uploaded" — so leaving cleanly
/// means removing that segment. Failure is swallowed on purpose: unit tests and
/// unsupported platforms do not expose `path_provider`, and cache hygiene must
/// never be able to break logging out.
Future<void> _clearGuestStagedAttachments() async {
  try {
    await chatAttachmentStagingService.cleanupAccount(kGuestStagingAccountId);
  } catch (_) {
    // The next launch's staging sweep reclaims anything left behind.
  }
}

void clearGuestWorld() {
  localeService.removeListener(refreshGuestWorldLocale);
  unawaited(_clearGuestStagedAttachments());
  _clearRegistries();
  chatStore.clearGuestConversations();
  _seeded = false;
}
