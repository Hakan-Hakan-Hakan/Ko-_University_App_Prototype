import '../models/content_audience.dart';
import 'locale_service.dart';

class S {
  S._();
  static String _t(String en, String tr) =>
      localeService.languageCode == 'tr' ? tr : en;

  // ── Feed
  static String get goodMorning => _t('Good morning', 'Günaydın');
  static String get goodAfternoon =>
      _t('Good afternoon', 'İyi öğleden sonralar');
  static String get goodEvening => _t('Good evening', 'İyi akşamlar');
  static String get stillUp => _t('Still up', 'Hâlâ uyanık mısın');
  static String get thisWeek => _t('THIS WEEK', 'BU HAFTA');
  static String get eventsOnCampus =>
      _t('Events on campus', 'Kampüsteki etkinlikler');
  static String get campusHappening => _t(
    "Here's what's happening on campus.",
    'Kampüste neler oluyor, göz at.',
  );
  static String get membersHappening => _t(
    "Here's what your members are up to.",
    'Üyelerin neler yapıyor, göz at.',
  );
  static String get seeAll => _t('See all', 'Hepsini gör');
  static String get fromYourClubs => _t('FROM YOUR CLUBS', 'KULÜPLERİNDEN');
  static String get clubFeed => _t('CLUB FEED', 'KULÜp AKIŞI');
  static String get following => _t('Following', 'Takip');
  static String get all => _t('All', 'Tümü');
  static String get forYou => _t('For You', 'Senin İçin');
  static String get latest => _t('Latest', 'Son Gönderiler');
  static String get nothingHere => _t('Nothing here yet', 'Henüz bir şey yok');
  static String get followClubs => _t(
    'Follow clubs to see their posts\nand events in your feed',
    'Gönderilerini görmek için\nkulüp takip et',
  );
  static String get endOfFeed =>
      _t('Updates Are Coming!', 'Updates Are Coming!');
  static String get exploreClubs =>
      _t('Explore All Clubs', 'Tüm Kulüpleri Keşfet');
  static String get peopleMightKnow =>
      _t('People You Might Know', 'Tanıyor Olabileceğin Kişiler');
  static String get suggestedForYou =>
      _t('Suggested for you', 'Senin için önerilenler');
  static String get followBack => _t('Follow back', 'Geri takip et');
  static String get sharePostToChat =>
      _t('Share post to a chat', 'Gönderiyi sohbette paylaş');
  static String get postShared => _t('Post shared', 'Gönderi paylaşıldı');
  static String get noStudentChatsYet => _t(
    'Start a student chat before sharing a post.',
    'Gönderi paylaşmadan önce bir öğrenci sohbeti başlat.',
  );
  static String get sharedPost => _t('Shared post', 'Paylaşılan gönderi');
  static String get eventUnavailable =>
      _t('Event unavailable', 'Etkinlik kullanılamıyor');
  static String get loadingEvent =>
      _t('Loading event…', 'Etkinlik yükleniyor…');
  static String get clubMightLike =>
      _t('Club You Might Like', 'Beğenebileceğin Kulüp');
  static String get today => _t('Today', 'Bugün');
  static String get tomorrow => _t('Tomorrow', 'Yarın');
  static String likedBy(String name) => _t('Liked by $name', '$name beğendi');
  static String likedByOthers(String name, int count) => _t(
    'Liked by $name and $count ${count == 1 ? 'other' : 'others'}',
    '$name ve $count diğer kişi beğendi',
  );

  // ── Explore
  static String get explore => _t('Explore', 'Keşfet');
  static String get discoverClubs => _t('Discover Clubs', 'Kulüpleri Keşfet');
  static String get findPeople => _t('Find People', 'Kişileri Bul');
  static String get searchClubs => _t('Search…', 'Ara…');
  static String get searchPeople => _t('Search people…', 'Kişi ara…');
  static String get allClubs => _t('All clubs', 'Tüm kulüpler');
  static String get exploreContentTab => _t('Events', 'Etkinlikler');
  static String get searchEventsPosts => _t('Search events…', 'Etkinlik ara…');
  static String get upcomingEvents =>
      _t('Upcoming events', 'Yaklaşan etkinlikler');
  static String get noContentMatch =>
      _t('No matches found', 'Sonuç bulunamadı');
  static String get noClubsMatch => _t('No clubs match', 'Eşleşen kulüp yok');
  static String get tryDifferentSearch =>
      _t('Try a different search term', 'Farklı bir arama terimi dene');
  static String get studentProfile => _t('Student profile', 'Öğrenci profili');
  static String get joined => _t('Joined ✓', 'Katıldı ✓');
  static String get join => _t('Join', 'Katıl');
  static String get follow => _t('Follow', 'Takip Et');
  static String get noOneMatches => _t('No one found', 'Kimse bulunamadı');
  static String get tryNameSearch =>
      _t('Try a name, surname, or email', 'İsim, soyisim veya e-posta dene');
  static String get filterByMajor =>
      _t('Filter by major', 'Bölüme göre filtrele');
  static String get clearMajorFilter =>
      _t('Clear major filter', 'Bölüm filtresini temizle');
  static String get searchMajors => _t('Search majors', 'Bölüm ara');
  static String get noMatchingMajor =>
      _t('No matching major', 'Eşleşen bölüm yok');
  static String get clearSearch => _t('Clear search', 'Aramayı temizle');
  static String get done => _t('Done', 'Bitti');
  static String peopleResultCount(int count) =>
      _t(count == 1 ? '1 result' : '$count results', '$count sonuç');
  static String get noPeopleInSelectedMajor =>
      _t('No students found in this major', 'Bu bölümde öğrenci bulunamadı');
  static String get tryAnotherMajorOrName => _t(
    'Try another major or change the name search',
    'Başka bir bölüm seç veya isim aramasını değiştir',
  );

  // ── This Week
  static String get discoverEvents =>
      _t('Discover events', 'Etkinlikleri Keşfet');
  static String get searchEvents =>
      _t('Search events, clubs, topics', 'Etkinlik, kulüp, konu ara');
  static String get anyDate => _t('Any date', 'Herhangi bir tarih');
  static String get past => _t('Past', 'Geçmiş');
  static String get live => _t('Live', 'Canlı');
  static String get allEvents => _t('All events', 'Tüm etkinlikler');
  static String get everythingOnCampus =>
      _t('Everything happening on campus', 'Kampüste olan her şey');
  static String get followingOnly =>
      _t('Only clubs you follow', 'Sadece takip ettiğin kulüpler');
  static String get showEventsFrom =>
      _t('Show events from', 'Şunlardan etkinlikleri göster');
  static String get pickDate => _t('Pick a date', 'Tarih seç');
  static String get clear => _t('Clear', 'Temizle');
  static String get showAllDates =>
      _t('Show all dates', 'Tüm tarihleri göster');
  static String get noEventsFound =>
      _t('No events found', 'Etkinlik bulunamadı');
  static String get tryDifferentKeyword => _t(
    'Try a different keyword or clear your filters.',
    'Farklı bir anahtar kelime deneyin veya filtrelerinizi temizleyin.',
  );
  static String get nothingScheduled => _t(
    'Nothing scheduled here yet — check another date.',
    'Henüz planlanmış bir şey yok — başka bir tarih deneyin.',
  );
  static String get checkBackLater => _t(
    'Nothing on the calendar right now — check back soon!',
    'Şu anda takvimde bir şey yok — yakında tekrar bak!',
  );
  static String get resetFilters => _t('Reset filters', 'Filtreleri Sıfırla');
  static String get newEvents => _t('New events', 'Yeni Etkinlikler');
  static String get allCaughtUp => _t('All caught up', 'Hepsi Görüldü');
  static String get newEventsHint => _t(
    'Newly created events will appear here until you open their details.',
    'Yeni etkinlikler, detaylarını açana kadar burada görünür.',
  );
  static String get going => _t('Going', 'Gidiyorum');
  static String get rsvp => _t('RSVP', 'Kayıt Ol');
  static String get ended => _t('Ended', 'Bitti');

  // ── Notifications
  static String get notifications => _t('Notifications', 'Bildirimler');
  static String get filterYou => _t('You', 'Sen');
  static String get filterEvents => _t('Events', 'Etkinlikler');
  static String get filterClubs => _t('Clubs', 'Kulüpler');
  static String get newSection => _t('New', 'Yeni');
  static String get earlier => _t('Earlier', 'Daha Önce');
  static String get accept => _t('Accept', 'Kabul Et');
  static String get decline => _t('Decline', 'Reddet');
  static String get nothingHereNotif => _t('Nothing here', 'Henüz bir şey yok');

  // ── Event Pass / check-in
  static String get eventPass => _t('Event Pass', 'Etkinlik Kartı');
  static String get eventPassHint => _t(
    'Show this code at the door to check in.',
    'Girişte bu kodu göstererek yoklamaya katıl.',
  );
  static String get showMyPass => _t('Show my pass', 'Kartımı göster');
  static String get scanCheckins => _t('Scan check-ins', 'Yoklama tara');
  static String get scanInvalidPass =>
      _t('Not a valid Event Pass', 'Geçersiz Etkinlik Kartı');
  static String get scanWrongEvent =>
      _t('Pass belongs to another event', 'Kart başka bir etkinliğe ait');
  static String get scanAlreadyIn =>
      _t('already checked in', 'zaten giriş yaptı');
  static String get scanNotAdmitted => _t('Not admitted', 'Alınmadı');
  static String get scanNoRsvpTitle => _t('No RSVP found', 'RSVP bulunamadı');
  static String scanNoRsvpBody(String name) => _t(
    "$name didn't RSVP to this event. Admit anyway?",
    '$name bu etkinliğe RSVP yapmamış. Yine de alınsın mı?',
  );
  static String get scanAdmitAnyway => _t('Admit anyway', 'Yine de al');
  static String checkedInCounter(int checked, int total) =>
      _t('$checked / $total checked in', '$checked / $total giriş yaptı');
  static String get checkedIn => _t('Checked in', 'Giriş yaptı');

  // ── Polls & announcements
  static String get addPoll => _t('Add poll', 'Anket ekle');
  static String get pollQuestionHint => _t('Ask a question…', 'Bir soru sor…');
  static String pollOptionHint(int n) => _t('Option $n', 'Seçenek $n');
  static String pollVotes(int n) => _t(n == 1 ? '1 vote' : '$n votes', '$n oy');
  static String get announcement => _t('Announcement', 'Duyuru');
  static String get markAsAnnouncement =>
      _t('Post as announcement', 'Duyuru olarak paylaş');

  // ── Comments
  static String get comments => _t('Comments', 'Yorumlar');
  static String get addComment => _t('Add a comment…', 'Yorum ekle…');
  static String get noCommentsYet => _t(
    'No comments yet. Be the first!',
    'Henüz yorum yok. İlk yorumu sen yap!',
  );
  static String get deleteComment => _t('Delete comment', 'Yorumu sil');
  static String get reportComment => _t('Report comment', 'Yorumu bildir');
  static String get whyReportComment => _t(
    'Why are you reporting this comment?',
    'Bu yorumu neden bildiriyorsun?',
  );
  static String get commentReported => _t(
    'Comment reported and removed from your feed.',
    'Yorum bildirildi ve akışından kaldırıldı.',
  );
  static String get commentHiddenOffline => _t(
    'Comment hidden. We will send the report when you are back online.',
    'Yorum gizlendi. Çevrimiçi olduğunda bildirim gönderilecek.',
  );
  static String get commentDeleted => _t('Comment deleted', 'Yorum silindi');
  static String get commentDeleteFailed => _t(
    'Comment could not be deleted. Please try again.',
    'Yorum silinemedi. Lütfen tekrar dene.',
  );
  static String get commentFailed => _t(
    'Comment could not be posted. Please try again.',
    'Yorum gönderilemedi. Lütfen tekrar dene.',
  );
  static String commentsWithCount(int count) =>
      _t('Comments · $count', 'Yorumlar · $count');
  static String get commentsStudentsOnly => _t(
    'Sign in with a student account to join the conversation.',
    'Sohbete katılmak için öğrenci hesabınla giriş yap.',
  );

  // ── Messages
  static String get deleteMessage => _t('Delete message', 'Mesajı sil');
  static String get deleteMessageMsg => _t(
    'This message will be permanently removed.',
    'Bu mesaj kalıcı olarak kaldırılacak.',
  );

  // ── Profile
  static String get posts => _t('Posts', 'Gönderiler');
  static String get clubs => _t('Clubs', 'Kulüpler');
  static String get followers => _t('Followers', 'Takipçiler');
  static String get myClubs => _t('My Clubs', 'Kulüplerim');
  static String get myContent => _t('My Content', 'İçeriklerim');
  static String get boardMembers => _t('Board Members', 'Yönetim Kurulu');
  static String get board => _t('Board', 'Yönetim');
  static String get cancel => _t('Cancel', 'İptal');
  static String get save => _t('Save', 'Kaydet');
  static String get delete => _t('Delete', 'Sil');
  static String get superAdmin => _t('Super Admin', 'Süper Yönetici');
  static String get clubAdmin => _t('Club Admin', 'Kulüp Yöneticisi');
  static String get addMajorYear => _t('Add major & year', 'Bölüm ve yıl ekle');
  static String get addBio => _t('Add a bio…', 'Biyografi ekle…');
  static String get noClubsYet => _t(
    "You haven't followed any clubs yet.",
    'Henüz bir kulüp takip etmediniz.',
  );
  static String get exploreClubsHint => _t(
    'Explore clubs and follow the ones you like.',
    'Kulüpleri keşfet ve beğendiklerini takip et.',
  );
  static String get noBoardMembers =>
      _t('No board members yet.', 'Henüz yönetim üyesi yok.');
  static String get approvedHere => _t(
    'Approved requests will appear here.',
    'Onaylanan istekler burada görünür.',
  );
  static String get noPostsYet => _t('No posts yet.', 'Henüz gönderi yok.');
  static String get noEventsYet => _t('No events yet.', 'Henüz etkinlik yok.');
  static String get noFollowersYet =>
      _t('No followers yet.', 'Henüz takipçi yok.');
  static String get notFollowingAnyone =>
      _t('Not following anyone yet.', 'Henüz kimseyi takip etmiyor.');
  static String get changePhoto =>
      _t('Change Profile Photo', 'Profil Fotoğrafını Değiştir');
  static String get takePhoto => _t('Take a Photo', 'Fotoğraf Çek');
  static String get useCamera =>
      _t('Use your camera right now', 'Kameranı hemen kullan');
  static String get chooseFromLib =>
      _t('Choose from Library', 'Kütüphaneden Seç');
  static String get pickFromLib =>
      _t('Pick from your photo library', 'Fotoğraf kütüphanenizden seçin');
  static String get removePhoto => _t('Remove photo', 'Fotoğrafı Kaldır');
  static String get majorYearLabel => _t('Major & Year', 'Bölüm & Yıl');
  static String get selectMajor => _t('Select your major', 'Bölümünü seç');
  static String get selectMajorHint => _t('Select major', 'Bölüm seç');
  static String get yearLabel => _t('Year', 'Yıl');
  static String get bioLabel => _t('Bio', 'Biyografi');
  static String get bioHint =>
      _t('Tell people a little about yourself', 'Kendinizi kısaca tanıtın');
  static String get useThisPhoto =>
      _t('Use this photo?', 'Bu fotoğrafı kullan?');
  static String get usePhoto => _t('Use Photo', 'Fotoğrafı Kullan');
  static String get deletePost => _t('Delete post?', 'Gönderi silinsin mi?');
  static String get deletePostMsg => _t(
    'This post will be permanently removed.',
    'Bu gönderi kalıcı olarak kaldırılacak.',
  );
  static String get deleteEvent => _t('Delete event?', 'Etkinlik silinsin mi?');
  static String get deleteEventMsg => _t(
    'This event will be permanently removed.',
    'Bu etkinlik kalıcı olarak kaldırılacak.',
  );
  static String get majorNotAdded => _t('Major not added', 'Bölüm eklenmedi');
  static String get yearNotAdded => _t('Year not added', 'Yıl eklenmedi');
  static String get addBioIntro => _t(
    'Add a bio to introduce yourself.',
    'Kendinizi tanıtmak için biyografi ekleyin.',
  );

  // ── Bottom nav
  static String get home => _t('Home', 'Ana Sayfa');
  static String get events => _t('Events', 'Etkinlikler');
  static String get search => _t('Search', 'Ara');
  static String get alerts => _t('Alerts', 'Bildirimler');
  static String get profile => _t('Profile', 'Profil');
  static String get admin => _t('Admin', 'Yönetici');

  // ── Settings
  static String get settings => _t('Settings', 'Ayarlar');
  static String get language => _t('Language', 'Dil');
  static String get appearance => _t('Appearance', 'Görünüm');
  static String get darkMode => _t('Dark Mode', 'Karanlık Mod');
  static String get lightMode => _t('Light Mode', 'Aydınlık Mod');
  static String get switchToDark =>
      _t('Switch to dark theme', 'Karanlık temaya geç');
  static String get switchToLight =>
      _t('Switch to light theme', 'Aydınlık temaya geç');
  static String get help => _t('Help', 'Yardım');
  static String get supportAndLegal => _t('Support & Legal', 'Destek ve Yasal');
  static String get supportCenter => _t('Support Center', 'Destek Merkezi');
  static String get supportCenterSubtitle =>
      _t('Help, FAQs & contact', 'Yardım, sık sorulanlar ve iletişim');
  static String get privacyPolicy =>
      _t('Privacy Policy', 'Gizlilik Politikası');
  static String get privacyPolicySubtitle =>
      _t('How ClubUp handles your data', 'ClubUp verilerinizi nasıl işler');
  static String get termsOfUse => _t('Terms of Use', 'Kullanım Koşulları');
  static String get termsOfUseSubtitle => _t(
    'Community rules & safety enforcement',
    'Topluluk kuralları ve güvenlik uygulaması',
  );
  static String get deleteAccount => _t('Delete Account', 'Hesabı Sil');
  static String get deleteAccountSubtitle => _t(
    'Request permanent account & data deletion',
    'Hesap ve verilerin kalıcı olarak silinmesini iste',
  );
  static String get couldNotOpenPage =>
      _t('Could not open this page.', 'Bu sayfa açılamadı.');
  static String get account => _t('Account', 'Hesap');
  static String get logOut => _t('Log Out', 'Çıkış Yap');
  static String get editProfile => _t('Edit Profile', 'Profili Düzenle');
  static String get editProfileSubtitle =>
      _t('Photo, bio, major & year', 'Fotoğraf, biyografi, bölüm & yıl');
  static String get changeMyName => _t('Change My Name', 'Adımı Değiştir');
  static String get changeNameSubtitle => _t(
    'Choose the name people see on your student profile.',
    'Öğrenci profilinde görünen adı seç.',
  );
  static String get displayName => _t('Display name', 'Görünen ad');
  static String get nameTaken =>
      _t('That name is already taken.', 'Bu isim zaten alınmış.');
  static String get useRealName => _t('Use Real Name', 'Gerçek Adı Kullan');
  static String get saveName => _t('Save Name', 'Adı Kaydet');
  static String get notSetConfigure => _t(
    'Not set — tap to configure',
    'Ayarlanmadı — yapılandırmak için dokun',
  );
  static String get replayTutorial =>
      _t('Replay the tour', 'Turu yeniden izle');
  static String get replayTutorialSubtitle =>
      _t('Take the campus tour again', 'Kampüs turunu yeniden yap');

  // ── Onboarding intro (first-run carousel)
  static String get onboardingIntroDiscoverTitle =>
      _t('Discover campus life', 'Kampüs hayatını keşfet');
  static String get onboardingIntroDiscoverSubtitle => _t(
    "See what's happening across campus, all in one feed.",
    'Kampüste neler olduğunu tek bir akışta gör.',
  );
  static String get onboardingIntroCalendarTitle =>
      _t('RSVP in a tap', 'Tek dokunuşla LCV ver');
  static String get onboardingIntroCalendarSubtitle => _t(
    "Say you're going and events land on your calendar automatically.",
    'Gidiyorum de, etkinlikler takvimine otomatik eklensin.',
  );
  static String get onboardingIntroClubsTitle =>
      _t('Follow your clubs', 'Kulüplerini takip et');
  static String get onboardingIntroClubsSubtitle => _t(
    'Never miss an update from the clubs you love.',
    'Sevdiğin kulüplerden hiçbir güncellemeyi kaçırma.',
  );
  static String get onboardingIntroReadyTitle =>
      _t('Ready to dive in?', 'Başlamaya hazır mısın?');
  static String get onboardingIntroReadySubtitle => _t(
    'Join your campus community and make it yours.',
    'Kampüs topluluğuna katıl ve burayı kendine ait kıl.',
  );
  static String get onboardingIntroSkip => _t('Skip', 'Atla');
  static String get onboardingIntroGetStarted => _t('Get started', 'Başla');
  static String get onboardingIntroLogIn => _t('Log in', 'Giriş yap');

  // ── Onboarding — coach-card controls
  static String get onboardingNext => _t('Next', 'İleri');
  static String get onboardingBack => _t('Back', 'Geri');
  static String get onboardingSkipTour => _t('Skip tour', 'Turu atla');

  // ── Onboarding — club-admin tour guide lines
  static String get onboardingClubComposer => _t(
    "This is your club's feed. Got news? Share an update right from here.",
    'Burası kulübünün akışı. Haber mi var? Güncellemeyi doğrudan '
        'buradan paylaş.',
  );
  static String get onboardingClubCreateEvent => _t(
    'The + button creates events — date, cover photo, schedule, '
        'speakers, the works.',
    '+ düğmesi etkinlik oluşturur — tarih, kapak fotoğrafı, program, '
        'konuşmacılar, hepsi.',
  );
  static String get onboardingClubProfileTabs => _t(
    "Your club's public home: posts, events and your board, "
        'all in one place.',
    'Kulübünün herkese açık yüzü: gönderiler, etkinlikler '
        've yönetim kurulu, hepsi bir arada.',
  );
  static String get onboardingClubChats => _t(
    'Your community chat lives here — members can talk to each other, '
        'and to you.',
    'Topluluk sohbetin burada — üyeler birbirleriyle ve seninle '
        'konuşabilir.',
  );
  static String get onboardingClubModeration => _t(
    'Review reports and manage profile or club access from the moderation area.',
    'Bildirimleri incele ve profil ya da kulüp erişimini moderasyon alanından yönet.',
  );
  static String get onboardingClubSettings => _t(
    'Name, photo, categories, board members — manage all of it '
        'from settings.',
    'İsim, fotoğraf, kategoriler, yönetim kurulu — hepsini ayarlardan '
        'yönet.',
  );

  // ── Onboarding — starter checklist
  static String get checklistTitle => _t('Get started', 'Başlarken');
  static String get checklistSubtitle => _t(
    'Three small steps to make ClubUp yours',
    "ClubUp'ı sana ait kılacak üç küçük adım",
  );
  static String get checklistFollowClub =>
      _t('Follow a club you like', 'Beğendiğin bir kulübü takip et');
  static String get checklistFollowClubAction =>
      _t('Explore clubs', 'Kulüpleri keşfet');
  static String get checklistRsvpEvent =>
      _t('RSVP to an event', 'Bir etkinliğe LCV ver');
  static String get checklistRsvpEventAction =>
      _t('See events', 'Etkinliklere bak');
  static String get checklistSayHi =>
      _t('Say hi to someone', 'Birine selam ver');
  static String get checklistSayHiAction => _t('Open chats', 'Sohbetleri aç');
  static String get checklistDismiss => _t('Hide', 'Gizle');
  static String get checklistAllDone =>
      _t("You're all set! 🎉", 'Hepsi tamam! 🎉');

  // ── Community safety & moderation
  static String get safetyHero => _t(
    'A safe campus community starts with everyone',
    'Güvenli bir kampüs topluluğu hepimizle başlar',
  );
  static String get safetyIntro => _t(
    'Please review and accept the Terms of Use before creating an account or signing in.',
    'Hesap oluşturmadan veya giriş yapmadan önce lütfen Kullanım Koşullarını inceleyip kabul et.',
  );
  static String get communitySafetyTerms =>
      _t('COMMUNITY SAFETY TERMS', 'TOPLULUK GÜVENLİĞİ KOŞULLARI');
  static String get zeroTolerance => _t('Zero tolerance', 'Sıfır tolerans');
  static String get zeroToleranceBody => _t(
    'Objectionable content, harassment, threats, hate, sexual exploitation, scams, and abusive users are not allowed.',
    'Sakıncalı içeriklere, tacize, tehditlere, nefrete, cinsel sömürüye, dolandırıcılığa ve kötü niyetli kullanıcılara izin verilmez.',
  );
  static String get reportHarmfulContent =>
      _t('Report harmful content', 'Zararlı içeriği bildir');
  static String get reportHarmfulContentBody => _t(
    'Use the report option on posts and profiles. ClubUp reviews reports and acts on violations within 24 hours.',
    'Gönderi ve profillerdeki bildirme seçeneğini kullan. ClubUp bildirimleri 24 saat içinde inceler ve ihlaller için işlem yapar.',
  );
  static String get blockAbusiveUsers =>
      _t('Block abusive users', 'Kötü niyetli kullanıcıları engelle');
  static String get blockAbusiveUsersBody => _t(
    'Blocking reports the account to ClubUp and immediately removes that user and their content from your experience.',
    'Engelleme, hesabı ClubUp’a bildirir ve kullanıcıyı ve içeriğini deneyiminden hemen kaldırır.',
  );
  static String get enforcement => _t('Enforcement', 'Yaptırım');
  static String get enforcementBody => _t(
    'ClubUp may remove violating content and suspend or permanently eject the responsible account.',
    'ClubUp ihlalli içeriği kaldırabilir ve sorumlu hesabı askıya alabilir veya kalıcı olarak hizmetten çıkarabilir.',
  );
  static String get readFullTerms =>
      _t('Read full Terms of Use', 'Kullanım Koşullarının tamamını oku');
  static String get agreeToSafetyTerms => _t(
    'I agree to the Terms of Use and Community Safety Terms.',
    'Kullanım Koşullarını ve Topluluk Güvenliği Koşullarını kabul ediyorum.',
  );
  static String get agreeAndContinue =>
      _t('Agree and continue', 'Kabul et ve devam et');
  static String get couldNotOpenThisPage =>
      _t('Could not open this page.', 'Bu sayfa açılamadı.');
  static String get whyReportPost => _t(
    'Why are you reporting this post?',
    'Bu gönderiyi neden bildiriyorsun?',
  );
  static String get whyReportUser => _t(
    'Why are you reporting this user?',
    'Bu kullanıcıyı neden bildiriyorsun?',
  );
  static String get whyBlockUser => _t(
    'Why are you blocking this user?',
    'Bu kullanıcıyı neden engelliyorsun?',
  );
  static String get chooseReportReason => _t(
    'Choose the reason that best describes the issue. Reports are reviewed within 24 hours.',
    'Sorunu en iyi açıklayan nedeni seç. Bildirimler 24 saat içinde incelenir.',
  );
  static String moderationReasonLabel(String value) => switch (value) {
    'harassment' => _t('Harassment or bullying', 'Taciz veya zorbalık'),
    'hate_or_discrimination' => _t(
      'Hate or discrimination',
      'Nefret veya ayrımcılık',
    ),
    'sexual_content' => _t(
      'Sexual or explicit content',
      'Cinsel veya açık içerik',
    ),
    'violence_or_danger' => _t(
      'Violence or dangerous behavior',
      'Şiddet veya tehlikeli davranış',
    ),
    'spam_or_scam' => _t('Spam or scam', 'Spam veya dolandırıcılık'),
    _ => _t('Something else', 'Başka bir neden'),
  };
  static String moderationReasonDetail(String value) => switch (value) {
    'harassment' => _t(
      'Targets, threatens, or abuses a person or group.',
      'Bir kişiyi veya grubu hedef alır, tehdit eder ya da kötüye kullanır.',
    ),
    'hate_or_discrimination' => _t(
      'Attacks people based on a protected characteristic.',
      'İnsanlara korunan bir özellikleri nedeniyle saldırır.',
    ),
    'sexual_content' => _t(
      'Contains unwanted nudity or sexual material.',
      'İstenmeyen çıplaklık veya cinsel materyal içerir.',
    ),
    'violence_or_danger' => _t(
      'Threatens harm or promotes dangerous conduct.',
      'Zarar tehdidi içerir veya tehlikeli davranışı teşvik eder.',
    ),
    'spam_or_scam' => _t(
      'Misleads people or repeatedly posts unwanted material.',
      'İnsanları yanıltır veya sürekli istenmeyen içerik paylaşır.',
    ),
    _ => _t(
      'Another violation of the ClubUp Terms of Use.',
      'ClubUp Kullanım Koşullarının başka bir ihlali.',
    ),
  };
  static String get reportPost => _t('Report post', 'Gönderiyi bildir');
  static String get reportUser => _t('Report user', 'Kullanıcıyı bildir');
  static String get reportUserSubtitle => _t(
    'Send this profile to ClubUp for review.',
    'Bu profili incelenmesi için ClubUp’a gönder.',
  );
  static String get blockAndReportUser =>
      _t('Block and report user', 'Kullanıcıyı engelle ve bildir');
  static String get blockAndReportSubtitle => _t(
    'Immediately hide this user and notify ClubUp.',
    'Bu kullanıcıyı hemen gizle ve ClubUp’a bildir.',
  );
  static String blockUserQuestion(String name) =>
      _t('Block $name?', '$name engellensin mi?');
  static String get blockUserExplanation => _t(
    'Their profile and content will be removed from your experience immediately. ClubUp will also receive a safety report.',
    'Profili ve içeriği deneyiminden hemen kaldırılacak. ClubUp ayrıca bir güvenlik bildirimi alacak.',
  );
  static String get userReported => _t(
    'User reported. Our team will review it within 24 hours.',
    'Kullanıcı bildirildi. Ekibimiz 24 saat içinde inceleyecek.',
  );
  static String get reportSendFailed => _t(
    'Could not send the report. Please try again.',
    'Bildirim gönderilemedi. Lütfen tekrar dene.',
  );
  static String get userBlockedAndReported =>
      _t('User blocked and reported.', 'Kullanıcı engellendi ve bildirildi.');
  static String get userBlockedOffline => _t(
    'User blocked on this device. The report could not be sent; please try again when online.',
    'Kullanıcı bu cihazda engellendi. Bildirim gönderilemedi; çevrimiçi olduğunda tekrar dene.',
  );
  static String get blockedAccounts =>
      _t('Blocked people and clubs', 'Engellenen kişiler ve kulüpler');
  static String get blockedAccountsSubtitle => _t(
    'Review and unblock accounts you have hidden.',
    'Gizlediğin hesapları incele ve engellerini kaldır.',
  );
  static String get people => _t('People', 'Kişiler');
  static String get clubsLabel => _t('Clubs', 'Kulüpler');
  static String get unblock => _t('Unblock', 'Engeli kaldır');
  static String unblockQuestion(String name) =>
      _t('Unblock $name?', '$name için engel kaldırılsın mı?');
  static String get unblockExplanation => _t(
    'Their profile and content will appear in your experience again.',
    'Profili ve içeriği deneyiminde yeniden görünecek.',
  );
  static String get unblockFailed => _t(
    'Could not unblock this account. Please try again.',
    'Bu hesabın engeli kaldırılamadı. Lütfen tekrar dene.',
  );
  static String get noBlockedPeople =>
      _t('You have not blocked anyone.', 'Engellediğin kimse yok.');
  static String get noBlockedClubs =>
      _t('You have not blocked any clubs.', 'Engellediğin kulüp yok.');
  static String get whyBlockClub =>
      _t('Why are you blocking this club?', 'Bu kulübü neden engelliyorsun?');
  static String blockClubQuestion(String name) =>
      _t('Block $name?', '$name engellensin mi?');
  static String get blockAndReportClub =>
      _t('Block and report club', 'Kulübü engelle ve bildir');
  static String get clubBlockedAndReported =>
      _t('Club blocked and reported.', 'Kulüp engellendi ve bildirildi.');
  static String get clubBlockedOffline => _t(
    'Club blocked on this device. The report could not be sent; please try again when online.',
    'Kulüp bu cihazda engellendi. Bildirim gönderilemedi; çevrimiçi olduğunda tekrar dene.',
  );
  static String get postReportedAndRemoved => _t(
    'Post reported and removed from your feed.',
    'Gönderi bildirildi ve akışından kaldırıldı.',
  );
  static String get postHiddenOffline => _t(
    'Post hidden. The report could not be sent; please try again when online.',
    'Gönderi gizlendi. Bildirim gönderilemedi; çevrimiçi olduğunda tekrar dene.',
  );
  static String get safetyOptions =>
      _t('Safety options', 'Güvenlik seçenekleri');

  /// Settings group heading for the blocked-accounts entry.
  static String get privacySection => _t('Privacy', 'Gizlilik');
  static String get moderation => _t('Moderation', 'Moderasyon');
  static String get moderationCenter =>
      _t('ClubUp moderation center', 'ClubUp moderasyon merkezi');
  static String get moderationCenterSubtitle => _t(
    'Review reports and manage login bans on this device.',
    'Bildirimleri incele ve bu cihazdaki giriş yasaklarını yönet.',
  );
  static String get reports => _t('Reports', 'Bildirimler');
  static String get profiles => _t('Profiles', 'Profiller');
  static String get noReports =>
      _t('No reports have been made yet.', 'Henüz bildirim yapılmadı.');
  static String get noProfiles =>
      _t('No profiles are available yet.', 'Henüz profil bulunmuyor.');
  static String get noClubsForModeration =>
      _t('No clubs are available yet.', 'Henüz kulüp bulunmuyor.');
  static String get ban => _t('Ban', 'Yasakla');
  static String get unban => _t('Unban', 'Yasağı kaldır');
  static String get banned => _t('Banned', 'Yasaklandı');
  static String get active => _t('Active', 'Aktif');
  static String get banProfile => _t('Ban profile', 'Profili yasakla');
  static String get unbanProfile =>
      _t('Unban profile', 'Profil yasağını kaldır');
  static String get banClub => _t('Ban club', 'Kulübü yasakla');
  static String get unbanClub => _t('Unban club', 'Kulüp yasağını kaldır');
  static String get banConfirmation => _t(
    'They will no longer be able to log in with their email and password.',
    'E-posta ve şifreleriyle artık giriş yapamayacaklar.',
  );
  static String get unbanConfirmation =>
      _t('They will be able to log in again.', 'Tekrar giriş yapabilecekler.');
  static String get moderationActionFailed => _t(
    'This action is available only to the ClubUp profile.',
    'Bu işlem yalnızca ClubUp profili tarafından kullanılabilir.',
  );
  static String get moderationAccessDenied => _t(
    'Only the ClubUp profile can access this area.',
    'Bu alana yalnızca ClubUp profili erişebilir.',
  );
  static String get reportedBy => _t('Reported by', 'Bildiren');
  static String get reportedContent =>
      _t('Reported content', 'Bildirilen içerik');
  static String get reason => _t('Reason', 'Neden');
  static String get unknownProfile =>
      _t('Unknown profile', 'Bilinmeyen profil');
  static String get unknownClub => _t('Unknown club', 'Bilinmeyen kulüp');
  static String get bannedFromApp => _t(
    'You have been banned from this app.',
    'Bu uygulamadan yasaklandınız.',
  );
  static String get contentSafetyRejected => _t(
    'This content cannot be published because it may violate the ClubUp Community Safety Terms.',
    'Bu içerik ClubUp Topluluk Güvenliği Koşullarını ihlal edebileceği için yayımlanamaz.',
  );
  static String get profileSection => _t('Profile', 'Profil');

  // ── Settings — Club admin
  static String get clubSection => _t('Club', 'Kulüp');
  static String get clubName => _t('Club Name', 'Kulüp Adı');
  static String get clubNameLabel => _t('Club name', 'Kulüp adı');
  static String get clubPhoto => _t('Club Photo', 'Kulüp Fotoğrafı');
  static String get changeClubPhoto =>
      _t('Change Club Photo', 'Kulüp Fotoğrafını Değiştir');
  static String get tapToChangeLogo => _t(
    'Tap to change your club logo',
    'Kulüp logonuzu değiştirmek için dokun',
  );
  static String get clubCategories =>
      _t('Club Categories', 'Kulüp Kategorileri');
  static String get chooseTagsHint => _t(
    'Choose tags that help students discover your club.',
    'Öğrencilerin kulübünüzü keşfetmesine yardımcı olacak etiketler seçin.',
  );
  static String get customTags => _t('Custom tags', 'Özel etiketler');
  static String get customTagsHint =>
      _t('Design, Gaming, Culture', 'Tasarım, Oyun, Kültür');
  static String get separateWithCommas =>
      _t('Separate custom tags with commas', 'Özel etiketleri virgülle ayırın');
  static String get saveCategories =>
      _t('Save Categories', 'Kategorileri Kaydet');
  static String get addDiscoveryTags =>
      _t('Add discovery tags', 'Keşif etiketleri ekle');
  static String get clubDescription =>
      _t('Club Description', 'Kulüp Açıklaması');
  static String get clubDescriptionHint =>
      _t('What is this club about?', 'Bu kulüp ne hakkında?');
  static String get manageBoardMembers =>
      _t('Manage Board Members', 'Yönetim Kurulunu Yönet');
  static String get manageBoardSubtitle => _t(
    'Add or remove board members & roles',
    'Yönetim üyelerini ve rolleri ekle veya kaldır',
  );

  // ── Feed composer
  static String get post => _t('Post', 'Gönder');
  static String get addPhoto => _t('Add photo', 'Fotoğraf ekle');
  static String get whatsHappeningAtClub =>
      _t("What's happening at your club?", 'Kulübünde neler oluyor?');
  static String get tapForDetails =>
      _t('Tap for details', 'Detaylar için dokun');

  // ── This Week
  static String get pastEventsHint => _t(
    'Events that finished during the last 7 days.',
    'Son 7 gün içinde biten etkinlikler.',
  );
  static String get upcomingEventsHint =>
      _t("What's on across campus.", 'Kampüste neler var.');

  // ── Notifications
  static String get yesterday => _t('Yesterday', 'Dün');
  static String noNotificationsFor(String label) => _t(
    'No ${label}notifications right now. We\'ll let you know when something happens.',
    '${label}bildirim yok şu an. Bir şey olduğunda haber veririz.',
  );

  // ── Explore
  static String get profilesWillAppear => _t(
    'Profiles will appear here after users sign up',
    'Kullanıcılar kaydolduktan sonra profiller burada görünecek',
  );

  // ── Profile
  static String get prepYear => _t('Prep', 'Hazırlık');
  static String get graduate => _t('Graduate', 'Lisansüstü');

  // ── Chats
  static String get chats => _t('Chats', 'Sohbetler');
  static String get newChat => _t('New chat', 'Yeni sohbet');
  static String get noChatsYet =>
      _t('No conversations yet', 'Henüz sohbet yok');
  static String get noChatsHint => _t(
    'Message a friend or join a club\nto start chatting.',
    'Sohbete başlamak için bir arkadaşına yaz\nveya bir kulübe katıl.',
  );
  static String get typeMessage => _t('Message…', 'Mesaj…');
  static String get startConversation =>
      _t('Start the conversation', 'Sohbeti başlat');
  static String get joinToChat =>
      _t('Join the club to chat', 'Sohbet için kulübe katıl');
  static String get joinToChatHint => _t(
    'This chat is only for club members.\nFollow the club to join the conversation.',
    'Bu sohbet sadece kulüp üyeleri içindir.\nSohbete katılmak için kulübü takip et.',
  );
  static String get clubChat => _t('Club chat', 'Kulüp sohbeti');
  static String get clubInbox => _t('Club inbox', 'Kulüp gelen kutusu');
  static String get privateSoloChat =>
      _t('Private solo chat', 'Özel birebir sohbet');
  static String get privateClubMessage =>
      _t('Private club message', 'Özel kulüp mesajı');
  static String get messageClub => _t('Message club', 'Kulübe mesaj yaz');
  static String get clubChannelReadOnly => _t(
    'Only board members can post in this channel.',
    'Bu kanalda yalnızca yönetim kurulu üyeleri paylaşım yapabilir.',
  );
  static String get secureChatUnavailable => _t(
    'Messaging is not available yet. Try again shortly.',
    'Mesajlaşma henüz kullanılamıyor. Birazdan tekrar dene.',
  );
  static String chatMembers(int n) => _t('$n members', '$n üye');
  static String communityMembers(int n) =>
      n >= 100 ? _t('100+ Members', '100+ Üye') : _t('$n Members', '$n Üye');
  static String get message => _t('Message', 'Mesaj');

  /// Sits under the club name on an empty community room. The empty screen
  /// already says there are no messages, so this line only invites.
  static String get sayHello =>
      _t('Say hello to your club', 'Kulübüne merhaba de');
  static String get adminLabel => _t('Admin', 'Yönetici');
  static String get you => _t('You', 'Sen');
  static String get typing => _t('typing…', 'yazıyor…');
  static String get sent => _t('Sent', 'Gönderildi');
  static String get delivered => _t('Delivered', 'Teslim edildi');
  static String get seen => _t('Seen', 'Görüldü');
  static String get read => _t('Read', 'Okundu');
  static String get messageInfo => _t('Message info', 'Mesaj bilgisi');
  static String get readBy => _t('Read by', 'Okuyanlar');
  static String get deliveredTo => _t('Delivered to', 'Teslim edilenler');
  static String get noOneYet => _t('No one yet', 'Henüz kimse');
  static String deliveredAt(String time) =>
      _t('Delivered $time', '$time teslim edildi');
  static String readAt(String time) => _t('Read $time', '$time okundu');
  static String get reply => _t('Reply', 'Yanıtla');
  static String replyingTo(String name) =>
      _t('Replying to $name', '$name adlı kişiye yanıt');
  static String get cancelReply => _t('Cancel reply', 'Yanıtı iptal et');
  static String nNew(int n) => _t('$n new', '$n yeni');
  static String get searchStudents => _t('Search students…', 'Öğrenci ara…');
  static String get studentChats => _t('Students', 'Öğrenciler');
  static String get clubChats => _t('Clubs', 'Kulüpler');
  static String get searchClubChats =>
      _t('Search club chats…', 'Kulüp sohbeti ara…');
  static String get noStudentChats =>
      _t('No student conversations yet', 'Henüz öğrenci sohbeti yok');
  static String get noStudentChatsHint => _t(
    'Start a new chat to message another student.',
    'Başka bir öğrenciye yazmak için yeni bir sohbet başlat.',
  );
  static String get noClubChats =>
      _t('No club conversations yet', 'Henüz kulüp sohbeti yok');
  static String get noClubChatsHint => _t(
    'Join a club to access its community chat.',
    'Topluluk sohbetine erişmek için bir kulübe katıl.',
  );
  static String get messagesLabel => _t('Messages', 'Mesajlar');
  static String get viewProfile => _t('View profile', 'Profili gör');

  // ── New student chat (empty thread)
  /// Shown under the name when there is nothing else worth saying about a
  /// brand-new thread. Deliberately short so the empty state stays quiet.
  static String get chatNoMessagesYet =>
      _t('No messages yet', 'Henüz mesaj yok');
  static String chatPeopleCount(int n) => _t('$n people', '$n kişi');
  static String get chatCreatedByYou => _t('created by you', 'sen kurdun');
  static String chatAlsoIn(String clubName) =>
      _t('Also in $clubName', 'Ortak kulüp: $clubName');
  static String chatMutualFriends(int n) => n == 1
      ? _t('1 mutual friend', '1 ortak arkadaş')
      : _t('$n mutual friends', '$n ortak arkadaş');

  static String get attachToMessage => _t('Add to message', 'Mesaja ekle');

  // ── Club community
  static String get communityMembersButton => _t('Members', 'Üyeler');
  static String communityEventsButton(int n) =>
      _t('Events · $n', 'Etkinlikler · $n');
  static String get communityNotices => _t('Notices', 'Duyurular');

  // ── Club Board + Chat + Solo Chat
  /// The official notice area — the lane a club room lands on.
  static String get clubBoardTab => _t('Board', 'Pano');

  /// The room itself, where board-member replies live.
  static String get clubChatTab => _t('Chat', 'Sohbet');
  static String get clubSoloChatTab => _t('Solo Chat', 'Birebir Sohbet');
  static String get soloChatWithClubTitle =>
      _t('Your private chat with the club', 'Kulüple özel sohbetin');
  static String get soloChatAllTitle =>
      _t('All private chats', 'Tüm özel sohbetler');
  static String get soloChatEmptyTitle =>
      _t('No solo chat yet', 'Henüz birebir sohbet yok');
  static String get soloChatEmptyHint => _t(
    'Start a private conversation with the club. Only you and the club team can see it.',
    'Kulüple özel bir sohbet başlat. Bu sohbeti yalnızca sen ve kulüp ekibi görebilir.',
  );
  static String get soloChatAllEmptyHint => _t(
    'Student conversations with the club will appear here.',
    'Öğrencilerin kulüple yaptığı sohbetler burada görünecek.',
  );
  static String get startSoloChat =>
      _t('Start solo chat', 'Birebir sohbet başlat');
  static String get boardGroupPinned => _t('Pinned', 'Sabitlenen');
  static String boardGroupNew(int n) => _t('New · $n', 'Yeni · $n');
  static String get boardGroupEarlier => _t('Earlier', 'Daha önce');
  static String get boardPostNotice => _t('Post a notice', 'Duyuru paylaş');
  static String get boardOnlyBoardPosts =>
      _t('Only the board posts here', 'Burada yalnızca yönetim paylaşır');
  static String get boardSayItInChat => _t('Say it in chat', 'Sohbette söyle');
  static String get boardReplyInChat => _t('Reply in chat', 'Sohbette yanıtla');
  static String boardRepliesInChat(int n) =>
      _t('$n replies in chat', 'Sohbette $n yanıt');
  static String get boardReplyingToNotice =>
      _t('REPLYING TO NOTICE', 'DUYURUYA YANIT');
  static String get boardEmptyTitle => _t('No notices yet', 'Henüz duyuru yok');
  static String get boardEmptyHintStaff => _t(
    'Post a notice and every member sees it here — replies happen in chat.',
    'Bir duyuru paylaş, tüm üyeler burada görsün — yanıtlar sohbette olur.',
  );
  static String get boardEmptyHintMember => _t(
    "The club's notices will appear here. Until then, the room is in chat.",
    'Kulübün duyuruları burada görünecek. O zamana kadar sohbete geç.',
  );
  static String boardReplyCount(int n) =>
      n == 1 ? _t('1 reply', '1 yanıt') : _t('$n replies', '$n yanıt');
  static String get noticeLabel => _t('NOTICE', 'DUYURU');
  static String get boardExpandNotice => _t('Open notice', 'Duyuruyu aç');
  static String get boardCollapseNotice => _t('Close notice', 'Duyuruyu kapat');
  static String get announcementLabel => _t('ANNOUNCEMENT', 'DUYURU');
  static String get pinnedLabel => _t('Pinned', 'Sabitlendi');
  static String get pinToTop => _t('Pin to top', 'Yukarı sabitle');
  static String get unpin => _t('Unpin', 'Sabitlemeyi kaldır');
  static String get pollLabel => _t('POLL', 'ANKET');
  static String pollCloses(String when) =>
      _t('closes $when', '$when kapanıyor');
  static String get pollClosed => _t('closed', 'kapandı');
  static String get pollVoted => _t('voted', 'oy verdin');
  static String goingCount(int n) => _t('$n going', '$n kişi gidiyor');
  static String leftOffHere(int n) =>
      _t('You left off here · $n new', 'Buradan devam · $n yeni');
  static String typingOne(String name) =>
      _t('$name is typing', '$name yazıyor');
  static String typingMany(String names) =>
      _t('$names are typing', '$names yazıyor');
  static String get jumpToLatest => _t('Jump to latest', 'En sona git');
  static String seenCount(int n) => _t('$n seen', '$n görüntüleme');
  static String get attachMedia =>
      _t('Photos & videos', 'Fotoğraf ve videolar');
  static String get attachPhoto => _t('Photo', 'Fotoğraf');
  static String get attachVideo => _t('Video', 'Video');
  static String get couldNotAttachPhoto =>
      _t('Could not attach that photo.', 'Fotoğraf eklenemedi.');
  static String get attachmentCouldNotSend => _t(
    'This attachment could not be sent. Check its type, size, and your access, then choose it again.',
    'Bu ek gönderilemedi. Türünü, boyutunu ve erişimini kontrol edip tekrar seç.',
  );
  static String get messageCouldNotSend => _t(
    'This message could not be sent. Please try again.',
    'Bu mesaj gönderilemedi. Lütfen tekrar dene.',
  );
  static String get photoSavedLocallyUploadFailed => _t(
    'Photo saved locally, but upload failed.',
    'Fotoğraf cihaza kaydedildi ama yükleme başarısız oldu.',
  );
  static String get attachFile => _t('File', 'Dosya');
  static String get mediaCaptionHint => _t('Add a caption…', 'Açıklama ekle…');
  static String get mediaSend => _t('Send media', 'Medyayı gönder');
  static String get mediaPreviewRemove => _t('Remove', 'Kaldır');
  static String get mediaPreviewEmpty =>
      _t('No media selected', 'Medya seçilmedi');
  static String mediaPreviewPosition(int current, int total) =>
      _t('$current of $total', '$current / $total');
  static String mediaSelectionRejected(int count) => count == 1
      ? _t(
          '1 item could not be added. Media must be available and smaller than 100 MB.',
          '1 öğe eklenemedi. Medya erişilebilir ve 100 MB\'tan küçük olmalı.',
        )
      : _t(
          '$count items could not be added. Media must be available and smaller than 100 MB.',
          '$count öğe eklenemedi. Medya erişilebilir ve 100 MB\'tan küçük olmalı.',
        );
  static String get mediaSelectionFailed => _t(
    'Could not open your media library. Please try again.',
    'Medya arşivi açılamadı. Lütfen tekrar dene.',
  );
  static String get mediaSendFailed => _t(
    'The media could not be sent. Please try again.',
    'Medya gönderilemedi. Lütfen tekrar dene.',
  );

  // ── Chat camera
  static String get cameraUnavailable =>
      _t('Camera unavailable', 'Kamera kullanılamıyor');
  static String get cameraUnavailableBody => _t(
    'No camera is available right now. Pick a photo from your library instead.',
    'Şu anda kullanılabilir bir kamera yok. Bunun yerine arşivinden bir '
        'fotoğraf seç.',
  );
  static String get cameraPermissionTitle =>
      _t('Camera access is off', 'Kamera erişimi kapalı');
  static String get cameraPermissionBody => _t(
    'Allow camera access in Settings to take a photo here.',
    'Buradan fotoğraf çekmek için Ayarlar\u2019dan kamera erişimine izin ver.',
  );
  static String get cameraRestrictedBody => _t(
    'Camera use is restricted on this device.',
    'Bu cihazda kamera kullanımı kısıtlanmış.',
  );
  static String get openSettings => _t('Open Settings', 'Ayarları Aç');
  static String get switchCamera => _t('Switch camera', 'Kamerayı değiştir');
  static String get flashOff => _t('Flash off', 'Flaş kapalı');
  static String get flashAuto => _t('Flash auto', 'Flaş otomatik');
  static String get flashOn => _t('Flash on', 'Flaş açık');
  static String get cameraCaptureFailed => _t(
    'That photo could not be taken. Please try again.',
    'Fotoğraf çekilemedi. Lütfen tekrar dene.',
  );
  static String get attachPoll => _t('Poll', 'Anket');
  static String get attachEvent => _t('Event', 'Etkinlik');
  static String get mentionEveryone => _t('everyone', 'herkes');
  static String get allMembers => _t('All members', 'Tüm üyeler');
  static String get memberRole => _t('Member', 'Üye');
  static String get retryMembers => _t(
    'Could not load members. Try again',
    'Üyeler yüklenemedi. Tekrar dene',
  );
  static String get communityComposerHint => _t("What's up?", 'Neler oluyor?');
  static String get newPollTitle => _t('New poll', 'Yeni anket');
  static String get pollQuestion => _t('Question', 'Soru');
  static String pollOptionLabel(int n) => _t('Option $n', '$n. seçenek');
  static String get addOption => _t('Add option', 'Seçenek ekle');
  static String get pollClosesIn => _t('Closes in', 'Kapanış');
  static String pollHours(int n) => _t('${n}h', '$n sa');
  static String pollDays(int n) => _t('${n}d', '$n gün');
  static String get shareEvent => _t('Share an event', 'Etkinlik paylaş');
  static String get noUpcomingEvents =>
      _t('No upcoming events', 'Yaklaşan etkinlik yok');
  static String get postAsAnnouncement =>
      _t('Post as announcement', 'Duyuru olarak paylaş');
  static String get announcementTitleHint =>
      _t('Announcement headline', 'Duyuru başlığı');
  static String get chatDisplay => _t('Chat display', 'Sohbet görünümü');
  static String get changeChatBackground =>
      _t('Change chat background', 'Sohbet arka planını değiştir');
  static String get chatBackground =>
      _t('Chat background', 'Sohbet arka planı');
  static String get backgroundClassic => _t('Classic', 'Klasik');
  static String get backgroundWarm => _t('Warm', 'Sıcak');
  static String get backgroundOcean => _t('Ocean', 'Okyanus');
  static String get backgroundForest => _t('Forest', 'Orman');
  static String get backgroundMidnight => _t('Midnight', 'Gece');
  static String get messageStyle => _t('Message style', 'Mesaj biçimi');
  static String get styleRows => _t('Rows', 'Satır');
  static String get styleBubbles => _t('Bubbles', 'Balon');
  static String get styleCards => _t('Cards', 'Kart');
  static String get announcementsStyle => _t('Announcements', 'Duyurular');
  static String get emphasisSubtle => _t('Subtle', 'Sade');
  static String get emphasisTinted => _t('Tinted', 'Renkli');
  static String get emphasisBold => _t('Bold', 'Belirgin');
  static String get showRolesBadges =>
      _t('Show roles & badges', 'Rolleri ve rozetleri göster');
  static String get muteCommunity =>
      _t('Mute notifications', 'Bildirimleri sustur');
  static String get unmuteCommunity =>
      _t('Unmute notifications', 'Bildirimleri aç');
  static String get muted => _t('Muted', 'Susturuldu');
  static String get react => _t('React', 'Tepki ver');
  static String get copyText => _t('Copy text', 'Metni kopyala');
  static String get copied => _t('Copied', 'Kopyalandı');
  static String get clubSettings => _t('Club settings', 'Kulüp ayarları');
  static String get openClubProfile =>
      _t('Open club profile', 'Kulüp profilini aç');
  static String get downloadAttachment => _t('Open', 'Aç');
  static String activeAgo(String ago) =>
      _t('Active $ago ago', '$ago önce aktif');

  static const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekdaysTr = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  static const _monthsEn = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _monthsTr = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];

  /// [weekday] follows [DateTime.weekday] (1 = Monday).
  static String weekdayShort(int weekday) =>
      _t(_weekdaysEn[(weekday - 1) % 7], _weekdaysTr[(weekday - 1) % 7]);

  static String monthShort(int month) =>
      _t(_monthsEn[(month - 1) % 12], _monthsTr[(month - 1) % 12]);

  // ── HOME area (ClubUp-Desings handoff) ─────────────────────────────────────
  /// `categories-horizontal-track` greeting prefix, e.g. "Hi, Hakan".
  static String get hiPrefix => _t('Hi,', 'Merhaba,');
  static String get unfollow => _t('Unfollow', 'Takibi bırak');
  static String get repliesTitle => _t('Replies', 'Yanıtlar');
  static String get replyAction => _t('Reply', 'Yanıtla');
  static String get noRepliesYetLine =>
      _t('No replies yet. Start the thread!', 'Henüz yanıt yok. İlk sen yaz!');
  static String replyToHint(String name) =>
      _t('Reply to $name…', '$name kişisine yanıt ver…');
  static String get shareSheetTitle => _t('Share', 'Paylaş');
  static String get quickSendLabel => _t('QUICK SEND', 'HIZLI GÖNDER');
  static String get shareResultsLabel => _t('RESULTS', 'SONUÇLAR');
  static String get shareSearchHint => _t('Search chats…', 'Sohbetlerde ara…');
  static String get sendAction => _t('Send', 'Gönder');
  static String get copyLinkAction => _t('Copy Link', 'Bağlantıyı kopyala');
  static String get noShareMatches =>
      _t('No chats match that name.', 'Bu ada uyan sohbet yok.');

  // ── PROFILE area (ClubUp-Desings handoff) ──────────────────────────────────
  /// `mutual-clubs` section header on `profile-menu`.
  static String get mutualClubs => _t('Mutual Clubs', 'Ortak Kulüpler');

  /// `hosting` section header — upcoming events at clubs where this student
  /// holds a board role.
  static String get hostingNext => _t('Hosting Next', 'Sırada Düzenliyor');

  /// The `badge` beside a peer's handle when they already follow you.
  static String get followsYou => _t('Follows you', 'Seni takip ediyor');

  /// Quiet placeholders — the frames have no empty state for these sections.
  static String get noClubsYetLine =>
      _t('No clubs yet. Find one to join!', 'Henüz kulüp yok. Birine katıl!');
  static String get noUpcomingEventsLine =>
      _t('Nothing on the calendar yet.', 'Takvimde henüz bir şey yok.');

  // ── CHATS area (ClubUp-Desings handoff) ────────────────────────────────────
  // The header dropdown on `chats-light` 243:475. `S.clubChats` /
  // `S.studentChats` are the old segmented control's labels and say
  // "Clubs" / "Students"; the handoff says "Clubs" / "Friends".
  static String get chatsTabClubs => _t('Clubs', 'Kulüpler');
  static String get chatsTabFriends => _t('Friends', 'Arkadaşlar');

  /// `search-bar` placeholder on `chats-light` 243:489.
  static String get searchConversations =>
      _t('Search conversations…', 'Sohbetlerde ara…');

  /// The three round quick actions on `group-info` 104:36.
  static String get chatsMuteAction => _t('Mute', 'Sessize al');
  static String get chatsUnmuteAction => _t('Unmute', 'Sesi aç');
  static String get chatsMediaAction => _t('Media', 'Medya');

  /// Card labels on `group-info` 104:50 / 104:53 and `edit-group-info`
  /// 107:37 / 107:42.
  static String get chatsDescriptionLabel => _t('Description', 'Açıklama');
  static String get chatsMembersLabel => _t('Members', 'Üyeler');
  static String get chatsGroupNameLabel => _t('Group Name', 'Grup Adı');
  static String chatsMembersCount(int count) =>
      _t('Members ($count)', 'Üyeler ($count)');
  static String get chatsAddMemberRow => _t('Add member', 'Üye ekle');

  /// A group description is **device-local** — `ChatGroup` has no such field,
  /// so there is nothing to sync it with. See `chat_group_prefs.dart`.
  static String get chatsDescriptionHint =>
      _t('Add a description…', 'Bir açıklama ekle…');
  static String get chatsDescriptionLocalNote =>
      _t('Saved on this device only.', 'Yalnızca bu cihazda kaydedilir.');

  /// `group-menu` sheet rows, 105:62.
  static String get chatsEditGroupInfo =>
      _t('Edit Group Info', 'Grup Bilgisini Düzenle');
  static String get chatsAddToFavorites =>
      _t('Add to Favorites', 'Favorilere Ekle');
  static String get chatsRemoveFromFavorites =>
      _t('Remove from Favorites', 'Favorilerden Çıkar');
  static String get chatsMuteNotifications =>
      _t('Mute Notifications', 'Bildirimleri Sessize Al');
  static String get chatsUnmuteNotifications =>
      _t('Unmute Notifications', 'Bildirimleri Aç');
  static String get chatsReportGroup => _t('Report Group', 'Grubu Bildir');
  static String get chatsLeaveGroup => _t('Leave Group', 'Gruptan Ayrıl');
  static String get chatsExitGroup => _t('Exit Group', 'Gruptan Çık');

  /// `leave-group` dialog, 105:474.
  static String get chatsLeaveGroupQuestion =>
      _t('Leave Group?', 'Gruptan ayrılınsın mı?');
  static String chatsLeaveGroupBody(String name) => _t(
    'You will no longer receive messages from $name. This action cannot be undone.',
    '$name grubundan artık mesaj almayacaksın. Bu işlem geri alınamaz.',
  );

  /// `shared-media` 105:189.
  static String get chatsSharedMedia => _t('Shared Media', 'Paylaşılan Medya');
  static String get chatsMediaTab => _t('Media', 'Medya');
  static String get chatsLinksTab => _t('Links', 'Bağlantılar');
  static String get chatsDocsTab => _t('Docs', 'Belgeler');
  static String get chatsNoSharedMedia =>
      _t('No photos shared yet.', 'Henüz fotoğraf paylaşılmadı.');
  static String get chatsNoSharedLinks =>
      _t('No links shared yet.', 'Henüz bağlantı paylaşılmadı.');
  static String get chatsNoSharedDocs =>
      _t('No files shared yet.', 'Henüz dosya paylaşılmadı.');

  /// `edit-group-info` 107:35 / 107:83.
  static String get chatsChangeGroupPhoto =>
      _t('Change Group Photo', 'Grup Fotoğrafını Değiştir');
  static String get chatsSaveChanges =>
      _t('Save Changes', 'Değişiklikleri Kaydet');

  /// `add-member` 105:346 / 105:350 / 105:356.
  static String get chatsSearchContacts =>
      _t('Search contacts…', 'Kişilerde ara…');
  static String get chatsSuggested => _t('Suggested', 'Önerilen');

  /// `member-actions` sheet rows, 108:70.
  static String get chatsMakeAdmin => _t('Make Admin', 'Yönetici Yap');
  static String get chatsDismissAdmin =>
      _t('Dismiss as Admin', 'Yöneticilikten Çıkar');
  static String get chatsRemoveFromGroup =>
      _t('Remove from Group', 'Gruptan Çıkar');
  static String get chatsMemberRole => _t('Member', 'Üye');

  /// `search-results` 110:105 — the in-thread message search.
  static String get chatsSearchMessages =>
      _t('Search messages…', 'Mesajlarda ara…');
  static String chatsResultsFound(int count) => _t(
    count == 1 ? '1 result found' : '$count results found',
    '$count sonuç bulundu',
  );
  static String get chatsNoResultsFound => _t('No matches', 'Eşleşme yok');

  /// `chats-clubs` 234:412 / 225:27 — the private lane a student shares with a
  /// club's admins.
  static String get chatsDirectLane => _t('Direct', 'Özel');
  static String get chatsDmWithAdmins =>
      _t('Direct message with admins', 'Yöneticilerle özel mesaj');

  /// `chat-group` header subtitle, 102:144.
  static String chatsFriendsCount(int count) =>
      _t(count == 1 ? '1 friend' : '$count friends', '$count arkadaş');

  /// The old create-group screen hard-coded this in English.
  static String get chatsSelectAtLeastTwo =>
      _t('Select at least 2', 'En az 2 kişi seç');

  /// `time-ago` on an inbox row, 243:497.
  static String chatsTimeAgo(String amount) =>
      _t('$amount ago', '$amount önce');
  static String get chatsJustNow => _t('now', 'şimdi');

  // ── CLUB CHATS INSIDE area (ClubUp-Desings handoff) ────────────────────────
  // The lane dropdown on `club-header` 221:363. `S.clubBoardTab` /
  // `S.clubChatTab` / `S.clubSoloChatTab` are the old segmented control's
  // labels ("Board" / "Chat" / "Solo Chat"); the handoff reads
  // "Board" / "Chats" / "Direct".
  static String get clubLaneBoard => _t('Board', 'Pano');
  static String get clubLaneChats => _t('Chats', 'Sohbet');
  static String get clubLaneDirect => _t('Direct', 'Özel');

  /// `announcement-card` 143:240 — the notice's reply count.
  static String clubReplyCount(int count) =>
      _t(count == 1 ? '1 reply' : '$count replies', '$count yanıt');

  /// `composer-locked` 143:279.
  static String get clubOnlyAdminsPost => _t(
    'Only admins can post in announcements',
    'Duyurulara yalnızca yöneticiler yazabilir',
  );

  /// `system-message` 143:37 — the Chats lane's pinned notice.
  static String clubPinnedByLine(String name) =>
      _t('$name pinned a message', '$name bir mesaj sabitledi');

  /// `143:66` — the receipt under an outgoing club message.
  static String clubSeenBy(int count) =>
      _t('Seen by $count', '$count kişi gördü');

  /// `club-attachment-sheet` 146:298.
  static String clubShareToTitle(String clubName) =>
      _t('Share to $clubName', '$clubName ile paylaş');
  static String clubShareVisibility(int members) => _t(
    'Everything you send is visible to all $members members',
    'Gönderdiğin her şey $members üyenin tamamına görünür',
  );
  static String get clubShareEvent => _t('Event', 'Etkinlik');

  /// `club-message-actions` 146:3 rows that are not already in `S`.
  static String get clubPinMessage => _t('Pin Message', 'Mesajı Sabitle');
  static String get clubUnpinMessage =>
      _t('Unpin Message', 'Sabitlemeyi Kaldır');
  static String get clubSaveMessage => _t('Save Message', 'Mesajı Kaydet');
  static String get clubUnsaveMessage =>
      _t('Remove from Saved', 'Kayıtlılardan Çıkar');
  static String get clubReportMessage => _t('Report Message', 'Mesajı Bildir');
  static String get clubDeleteForEveryone =>
      _t('Delete for Everyone', 'Herkesten Sil');
  static String get clubMessageSaved =>
      _t('Saved on this device.', 'Bu cihazda kaydedildi.');

  /// `club-chats-empty` 140:31.
  static String get clubChatsEmptyBody => _t(
    'Join a club and its group chat shows up here. Say hello, plan events and '
        'share photos.',
    'Bir kulübe katıl, grup sohbeti burada görünsün. Selam ver, etkinlik '
        'planla, fotoğraf paylaş.',
  );
  static String get clubChatsExploreClubs =>
      _t('Explore Clubs', 'Kulüpleri Keşfet');
  static String get clubChatsBrowseEvents =>
      _t('Browse Events', 'Etkinliklere Bak');
  static String get clubChatsFriendsHint => _t(
    'Friends chats live in the Friends tab',
    'Arkadaş sohbetleri Arkadaşlar sekmesinde',
  );

  /// `club-chats-search` 141:33 — the section label over club hits.
  static String get clubSearchSectionLabel => _t('Clubs', 'Kulüpler');
  static String clubMembersAndUnread(int members, int unread) => _t(
    unread > 0 ? '$members members · $unread unread' : '$members members',
    unread > 0 ? '$members üye · $unread okunmamış' : '$members üye',
  );

  /// `club-member-list` 142:231.
  static String get clubMembersTitle => _t('Members', 'Üyeler');
  static String get clubSearchMembers => _t('Search members', 'Üye ara');
  static String get clubSectionAdmins => _t('Admins', 'Yöneticiler');
  static String get clubSectionModerators => _t('Moderators', 'Moderatörler');
  static String get clubSectionMembers => _t('Members', 'Üyeler');
  static String get clubRoleMod => _t('Mod', 'Mod');
  static String get clubRoleYou => _t('You', 'Sen');
  static String get clubCreatedTheClub =>
      _t('Created the club', 'Kulübü kurdu');
  static String get clubMemberRole => _t('Member', 'Üye');
  static String get clubNoMemberMatches =>
      _t('No members match that name.', 'Bu ada uyan üye yok.');

  /// The Chats lane before anyone has spoken — `club-chat-reply` has no empty
  /// state of its own.
  static String get clubChatEmptyLine => _t(
    'No messages yet. Say hello to the club.',
    'Henüz mesaj yok. Kulübe merhaba de.',
  );

  /// `club-chats-empty` 140:36. `S.noClubChats` says "No club conversations
  /// yet"; the frame is shorter.
  static String get clubChatsEmptyTitle =>
      _t('No club chats yet', 'Henüz kulüp sohbeti yok');

  // ── SETTINGS area (`profile-settings` 120:3 / 120:144)
  /// Section labels. `Account` already exists on [AppLocalizations]; these
  /// three do not.
  static String get settingsPreferences => _t('Preferences', 'Tercihler');
  static String get settingsSupport => _t('Support', 'Destek');
  static String get settingsDangerZone => _t('Danger Zone', 'Tehlikeli Alan');

  /// `row-edit-profile` reads "Name, username, bio and photo" in the frame;
  /// students have no username field, so the line names what is really there.
  static String get settingsEditProfileSubtitle =>
      _t('Name, bio and photo', 'Ad, biyografi ve fotoğraf');

  /// `row-privacy-security`. The frame's "Private account, blocking" promises a
  /// private-account switch the app has no field for — blocking is what this
  /// row actually opens.
  static String get settingsPrivacy => _t('Privacy', 'Gizlilik');
  static String get settingsPrivacySubtitle =>
      _t('Blocked people and clubs', 'Engellenen kişiler ve kulüpler');

  static String get settingsSavedItems => _t('Saved Items', 'Kaydedilenler');
  static String get settingsReportProblem =>
      _t('Report a Problem', 'Sorun Bildir');
  static String get settingsAboutClubUp =>
      _t('About ClubUp', 'ClubUp Hakkında');

  /// `sec-support`, added on top of the frame: the browser build of ClubUp.
  /// Title-only and link-glyphed like every other row in that section.
  static String get settingsWebVersion => _t('Web Version', 'Web Sürümü');
  static String get settingsLightOption => _t('Light', 'Açık');
  static String get settingsDarkOption => _t('Dark', 'Koyu');

  /// The footer under `sec-danger-zone`.
  static String settingsVersionLine(String version, String build) =>
      _t('ClubUp v$version (build $build)', 'ClubUp v$version (yapı $build)');

  // ── FİRST LANDİNG PAGE (`login-screen` 495:5 / 485:5)
  /// `divider` — between Log In and Sign Up.
  static String get landingOr => _t('OR', 'VEYA');

  /// `btn-guest` `631:17` on `Login Screen New ` — the top-left pill. The frame
  /// letters it "Continue as Guest"; the user shortened it to fit the pill.
  /// Opens the guest joyride (see `guest_world.dart`).
  static String get landingGuestLogin => _t('Guest Login', 'Misafir Girişi');

  // ── Guest joyride ───────────────────────────────────────────────────────────
  // Shown once, immediately after the guest pill is tapped, before the tour.
  // A visitor must not mistake the fabricated campus for the real thing.

  static String get guestNoticeTitle => _t('This is a demo', 'Bu bir demo');

  static String get guestNoticeBody => _t(
    'You are exploring ClubUp with sample data. The students, clubs, posts, '
        'events and messages you see here are made up — none of them are real.',
    'ClubUp\'u örnek verilerle keşfediyorsunuz. Burada gördüğünüz öğrenciler, '
        'kulüpler, gönderiler, etkinlikler ve mesajlar kurgusaldır — hiçbiri '
        'gerçek değildir.',
  );

  static String get guestNoticeFooter => _t(
    'Everything works, so do try it: like a post, RSVP to an event, send a '
        'message. Nothing you do is saved, and it is all cleared when you log out '
        'from Settings.',
    'Her şey çalışıyor, deneyin: bir gönderiyi beğenin, bir etkinliğe katılın, '
        'mesaj gönderin. Yaptığınız hiçbir şey kaydedilmez ve Ayarlar\'dan çıkış '
        'yaptığınızda tümü silinir.',
  );

  static String get guestNoticeAction =>
      _t('Start exploring', 'Keşfetmeye başla');

  /// `footer/admin-link`. One tap opens the club portal; five quick taps still
  /// reveal the platform-admin entry.
  static String get landingClubAdminPortal =>
      _t('Club Admin Portal', 'Kulüp Yönetici Portalı');

  // ── CLUB HOME area (`home-feed-alt` 272:31 / 272:200, `admin-compose` 298:5)
  /// The compose card's placeholder. The old prompt read "What's happening at
  /// your club?"; the frame's card is shorter.
  static String get clubHomeComposerHint =>
      _t("What's happening?", 'Neler oluyor?');

  // ── EVENT WIZARD area (`wz-*` chain: 310:11, 310:62, 310:133, 324:978)
  /// `nav-right` — the step chip, e.g. "1 of 3".
  static String eventWizardStepOf(int step, int total) =>
      _t('$step of $total', '$step / $total');

  /// The three `nav-bar` titles, then the preview page.
  static String get eventWizardStepOneTitle =>
      _t('Create Event', 'Etkinlik Oluştur');
  static String get eventWizardStepTwoTitle =>
      _t('Speakers & Tags', 'Konuşmacılar ve Etiketler');
  static String get eventWizardStepThreeTitle =>
      _t('Programme & Preview', 'Program ve Önizleme');
  static String get eventWizardPreviewTitle =>
      _t('Event Preview', 'Etkinlik Önizlemesi');
  static String get eventWizardPreviewBadge => _t('Preview', 'Önizleme');

  /// `bottom-action` labels.
  static String get eventWizardNextStep => _t('Next Step', 'Sonraki Adım');
  static String get eventWizardCreateEvent =>
      _t('Create Event', 'Etkinlik Oluştur');
  static String get eventWizardPublish =>
      _t('Publish Event', 'Etkinliği Yayınla');
  static String get eventWizardSaveChanges =>
      _t('Save Changes', 'Değişiklikleri Kaydet');

  /// `photo-uploader` 315:32. The frame mocks a filled cover with the event
  /// name; an empty uploader has to say what it takes.
  static String get eventWizardCoverHint =>
      _t('Add event cover', 'Etkinlik kapağı ekle');

  /// Step 1 fields.
  static String get eventWizardTitleLabel => _t('Event Title', 'Etkinlik Adı');
  static String get eventWizardTitleHint =>
      _t('e.g. Sunset DJ Session & Mixer', 'örn. Gün Batımı DJ Seansı');
  static String get eventWizardLocationLabel => _t('Location', 'Konum');
  static String get eventWizardLocationHint =>
      _t('Search address or venue', 'Adres veya mekân ara');
  static String get eventWizardDescriptionLabel =>
      _t('Description', 'Açıklama');
  static String get eventWizardDescriptionHint => _t(
    'What is this event about? Share key highlights and guidelines...',
    'Bu etkinlik ne hakkında? Öne çıkanları ve kuralları paylaş...',
  );
  static String get eventWizardStarts => _t('Starts', 'Başlangıç');
  static String get eventWizardEnds => _t('Ends', 'Bitiş');
  static String get eventWizardDate => _t('Date', 'Tarih');
  static String get eventWizardTime => _t('Time', 'Saat');
  static String get eventWizardSelectStartDate =>
      _t('Select start date', 'Başlangıç tarihi');
  static String get eventWizardSelectEndDate =>
      _t('Select end date', 'Bitiş tarihi');
  static String get eventWizardSelectStart => _t('Select start', 'Başlangıç');
  static String get eventWizardSelectEnd => _t('Select end', 'Bitiş');

  /// The two picker sheets, `319:7` and `315:71`.
  static String get eventWizardSelectDate => _t('Select Date', 'Tarih Seç');
  static String get eventWizardSelectStartTime =>
      _t('Select Start Time', 'Başlangıç Saati');
  static String get eventWizardSelectEndTime =>
      _t('Select End Time', 'Bitiş Saati');

  /// Step 2.
  static String get eventWizardTagsLabel => _t('Event Tags', 'Etiketler');
  static String get eventWizardTagHint =>
      _t('Enter tag name...', 'Etiket adı gir...');
  static String get eventWizardAddSpeaker =>
      _t('Add Speaker', 'Konuşmacı Ekle');
  static String get eventWizardAddAnotherSpeaker =>
      _t('Add another speaker', 'Başka bir konuşmacı ekle');
  static String get eventWizardAddRegistrationLink =>
      _t('Add Registration Link', 'Kayıt Bağlantısı Ekle');
  static String get eventWizardRegistrationLabel =>
      _t('Registration Link (Optional)', 'Kayıt Bağlantısı (İsteğe bağlı)');
  static String get eventWizardRegistrationHint =>
      _t('e.g. ticket-link.com/event', 'örn. bilet-linki.com/etkinlik');

  /// `add-speaker-modal` 325:154.
  static String get eventWizardFullName => _t('Full Name', 'Ad Soyad');
  static String get eventWizardFullNameHint =>
      _t('e.g. Sarah Chen', 'örn. Elif Yılmaz');
  static String get eventWizardRoleTitle => _t('Role / Title', 'Rol / Unvan');
  static String get eventWizardRoleTitleHint =>
      _t('e.g. Resident DJ & Producer', 'örn. Kulüp DJ ve Yapımcı');
  static String get eventWizardLinkedinLabel =>
      _t('LinkedIn Profile', 'LinkedIn Profili');
  static String get eventWizardLinkedinHint =>
      _t('linkedin.com/in/username', 'linkedin.com/in/kullanici');
  static String get eventWizardSaveSpeaker =>
      _t('Save Speaker', 'Konuşmacıyı Kaydet');

  /// Step 3 and `add-session` 325:485.
  static String get eventWizardProgrammeSchedule =>
      _t('Programme Schedule', 'Program Akışı');
  static String get eventWizardAddSession => _t('Add Session', 'Oturum Ekle');
  static String get eventWizardSessionName => _t('Session Name', 'Oturum Adı');
  static String get eventWizardSessionNameHint =>
      _t('e.g. Keynote Panel Discussion', 'örn. Açılış Paneli');
  static String get eventWizardSessionSpeaker =>
      _t('Speaker / Presenter', 'Konuşmacı / Sunucu');
  static String get eventWizardSessionSpeakerHint =>
      _t('e.g. Sarah Chen', 'örn. Elif Yılmaz');
  static String get eventWizardStartTime => _t('Start Time', 'Başlangıç Saati');
  static String get eventWizardSaveSession =>
      _t('Save Session', 'Oturumu Kaydet');
  static String eventWizardSessionSpeakerLine(String name) =>
      _t('Speaker: $name', 'Konuşmacı: $name');
  static String get eventWizardNoSessions => _t(
    'No sessions yet. Add the first one.',
    'Henüz oturum yok. İlkini ekle.',
  );

  /// `Live Event Preview` and the preview page.
  static String get eventWizardLivePreview =>
      _t('Live Event Preview', 'Canlı Etkinlik Önizlemesi');
  static String eventWizardSpeakerCount(int count) =>
      _t('$count ${count == 1 ? 'Speaker' : 'Speakers'}', '$count Konuşmacı');
  static String eventWizardSessionCount(int count) =>
      _t('$count ${count == 1 ? 'Session' : 'Sessions'}', '$count Oturum');
  static String get eventWizardAbout =>
      _t('About this Event', 'Bu Etkinlik Hakkında');
  static String get eventWizardUntitled =>
      _t('Untitled event', 'Adsız etkinlik');

  /// Why a step will not advance. The frame draws no disabled button, so the
  /// CTA stays solid and says what is missing instead.
  static String get eventWizardNeedTitleAndPlace =>
      _t('Add a title and a location first.', 'Önce bir ad ve konum ekle.');
  static String get eventWizardNeedValidRange => _t(
    'The end has to come after the start.',
    'Bitiş, başlangıçtan sonra olmalı.',
  );

  /// `plus-menu` 297:8 — the create sheet.
  static String get eventWizardCreateNew => _t('Create New', 'Yeni Oluştur');
  static String get eventWizardCreatePost =>
      _t('Create Post', 'Gönderi Oluştur');
  static String get eventWizardCreatePostSubtitle => _t(
    'Share updates with your community',
    'Topluluğunla güncellemeleri paylaş',
  );
  static String get eventWizardCreateEventSubtitle =>
      _t('Plan and host a new event', 'Yeni bir etkinlik planla');

  // ── CONTENT AUDIENCE — who a post or event is addressed to ──────────────────
  // Three nested tiers shared by the post composer and the event wizard, so the
  // copy lives here once rather than in each area's own block.
  static String get audienceFieldLabel =>
      _t('Who can see this', 'Bunu kim görebilir');
  static String get audienceSheetTitle =>
      _t('Who can see this', 'Bunu kim görebilir');
  static String get audienceEveryone => _t('Everyone', 'Herkes');
  static String get audienceEveryoneHint =>
      _t('All students on campus', 'Kampüsteki tüm öğrenciler');
  static String get audienceFollowers => _t('Followers', 'Takipçiler');
  static String get audienceFollowersHint =>
      _t('People who follow your club', 'Kulübünü takip edenler');
  static String get audienceBoard => _t('Board members', 'Yönetim kurulu');
  static String get audienceBoardHint =>
      _t('Your board only', 'Sadece yönetim kurulun');

  /// The short label a picker cell shows once a tier is chosen.
  static String audienceTierLabel(ContentAudience audience) =>
      switch (audience) {
        ContentAudience.everyone => audienceEveryone,
        ContentAudience.followers => audienceFollowers,
        ContentAudience.board => audienceBoard,
      };

  static String audienceTierHint(ContentAudience audience) =>
      switch (audience) {
        ContentAudience.everyone => audienceEveryoneHint,
        ContentAudience.followers => audienceFollowersHint,
        ContentAudience.board => audienceBoardHint,
      };

  /// The badge a restricted post or event carries on its card. Empty for
  /// [ContentAudience.everyone] — public content gets no badge at all.
  static String audienceTierPill(ContentAudience audience) =>
      switch (audience) {
        ContentAudience.everyone => '',
        ContentAudience.followers => _t(
          'Followers only',
          'Yalnızca takipçiler',
        ),
        ContentAudience.board => _t('Board only', 'Yalnızca yönetim'),
      };

  static String get audienceChangeAction =>
      _t('Change audience', 'Görünürlüğü değiştir');

  // ── CLUB CHATS area ─────────────────────────────────────────────────────────
  // Section label `543:32`: the club side of a room a student already sees.
  // Everything else on those frames reuses the CHATS and CLUB CHATS INSIDE
  // strings, so this block is deliberately short.

  /// `admin-dm-list` 335:6 — the Direct lane titles itself "Messages" on the
  /// board side, where the header carries an inbox rather than one club.
  static String get clubDirectInboxTitle => _t('Messages', 'Mesajlar');
  static String get clubDirectNoMatches =>
      _t('No conversations match that name.', 'Bu ada uyan sohbet yok.');
  static String get clubDirectInboxEmpty => _t(
    'No student has written to the club yet.',
    'Kulübe henüz yazan öğrenci yok.',
  );

  /// `admin-chats-list` 331:136 — the Board lane's composer, which the student
  /// frame draws only as a locked strip.
  static String get clubBoardComposerHint =>
      _t('Write an announcement…', 'Duyuru yaz…');

  // ── CLUB PROFILE area ───────────────────────────────────────────────────────
  // Section label `555:33`. Everything else on these frames reuses existing
  // l10n keys (Members / Events / Board Members / View), so this block only
  // carries what the handoff added and the profile-specific Timeline label.

  /// `chat-header` `332:2208` — the frames title the club's own profile
  /// rather than repeating the club name, which the identity card already
  /// carries.
  static String get clubProfileTitle => _t('Club Profile', 'Kulüp Profili');

  /// The club profile presents posts as a chronological stream, so its label
  /// is distinct from the generic Posts wording used elsewhere in the app.
  static String get clubProfileTimeline => _t('Timeline', 'Akış');

  /// `board-header` `332:2015` — opens the full `board-members-all` list.
  static String get clubProfileViewAll => _t('View all', 'Tümünü gör');

  /// `board-members-all` `346:24` / `346:30`.
  static String get clubProfileBoardMembersTitle =>
      _t('Board Members', 'Yönetim Kurulu');
  static String get clubProfileSearchMembers =>
      _t('Search members…', 'Üye ara…');
  static String get clubProfileNoMembersMatch => _t(
    'No board member matches that name.',
    'Bu ada uyan yönetim üyesi yok.',
  );

  /// The frames draw no per-row controls, so the club's own edit/remove
  /// actions live behind a long press and this line says so.
  static String get clubProfileBoardHint => _t(
    'Press and hold a member to change their title or remove them.',
    'Unvanını değiştirmek veya çıkarmak için üyeye basılı tut.',
  );

  /// The event cards carry no control either, for the same reason.
  static String get clubProfileEventHint => _t(
    'Press and hold an event to delete it.',
    'Silmek için etkinliğe basılı tut.',
  );

  /// `insights` `347:24` and its four metric tiles.
  static String get clubInsightsTitle =>
      _t('Club Insights', 'Kulüp İstatistikleri');
  static String get clubInsightsAllTimeFollowers =>
      _t('All-Time Followers', 'Toplam Takipçi');
  static String get clubInsightsTotalRsvps =>
      _t('Total RSVPs', 'Toplam Katılım');
  static String get clubInsightsTotalLikes =>
      _t('Total Likes', 'Toplam Beğeni');
  static String get clubInsightsTotalViews =>
      _t('Total Views', 'Toplam Görüntülenme');
  static String get clubInsightsPostPerformance =>
      _t('Post Performance', 'Gönderi Performansı');
  static String get clubInsightsMostPopular => _t('Most Popular', 'En Popüler');

  // ── Manage Board Members — `board-members-light/dark` `413:7` / `413:105`.
  // The frame reachable from Settings ▸ Manage Board Members. Its accent is
  // drawn `#1DA1F2` in Figma — a mockup default; the screen uses the club
  // burgundy like every other frame in this section.

  /// `section-label` `413:29`.
  static String get clubBoardAddSection =>
      _t('ADD BOARD MEMBER', 'YÖNETİM ÜYESİ EKLE');

  /// `search-field` `413:34`.
  static String get clubBoardSearchByName =>
      _t('Search by name…', 'İsme göre ara…');

  /// `role-input-container` `413:45` and the field's placeholder `413:47`,
  /// which the frame fills with a sample title.
  static String get clubBoardRoleLabel => _t('Role *', 'Unvan *');
  static String get clubBoardRoleHint => _t('Treasurer', 'Sayman');
  static String get clubBoardRoleRequired => _t(
    'Write a role before adding this member.',
    'Bu üyeyi eklemeden önce bir unvan yazın.',
  );

  /// `add-to-board-btn` `413:49`.
  static String get clubBoardAddToBoard => _t('Add to Board', 'Yönetime Ekle');

  /// `section-label` `413:52` — the frame prints the live count in the label.
  static String clubBoardCurrentCount(int count) =>
      _t('CURRENT BOARD MEMBERS ($count)', 'MEVCUT YÖNETİM ÜYELERİ ($count)');

  /// The dropdown lists the club's members who are not on the board yet.
  static String get clubBoardNoCandidates => _t(
    'Everyone who follows this club is already on the board.',
    'Bu kulübü takip eden herkes zaten yönetimde.',
  );
  static String get clubBoardNoCandidateMatch =>
      _t('No member matches that name.', 'Bu ada uyan üye yok.');

  /// Shown under the list: the frame draws only a trash button, so changing a
  /// title stays on the long press this section uses everywhere else.
  static String get clubBoardManageHint => _t(
    'Press and hold a member to change their title.',
    'Unvanını değiştirmek için üyeye basılı tut.',
  );

  /// The `Add to Board` button acts on the row you tapped in the dropdown.
  static String get clubBoardPickSomeone =>
      _t('Pick someone from the list first.', 'Önce listeden birini seç.');

  // ── CLUB SETTINGS sub-flow ──────────────────────────────────────────────────
  // `settings` `350:6` / `350:184` and everything it opens: `edit-category`
  // `367:61`, `edit-description` `367:157`, `settings-language` `417:208` and
  // `blocked-students`/`blocked-clubs` `414:*`. Same story as the board screen:
  // every accent on these frames is drawn `#1DA1F2`, a mockup default, and is
  // rendered in the club burgundy instead.

  /// `section-label` `350:31` / `350:69` — the frame's two new section names;
  /// Preferences, Support and Danger Zone already exist above.
  static String get clubSettingsProfileSection =>
      _t('Club Profile', 'Kulüp Profili');
  static String get clubSettingsManagementSection =>
      _t('Management', 'Yönetim');
  static String get clubSettingsLegalSection => _t('Legal', 'Yasal');

  /// `change-photo-btn` `350:43` — the chip on the identity card.
  static String get clubSettingsEditPhoto => _t('Edit', 'Düzenle');

  /// `settings-row` `350:83` — one row for both blocked lists.
  static String get clubSettingsBlockedRow =>
      _t('Blocked People & Clubs', 'Engellenen Kişiler ve Kulüpler');

  /// `settings-language` `417:208` — the sheet behind the Language row.
  static String get clubSettingsChooseLanguage =>
      _t('Choose Language', 'Dil Seç');

  /// `edit-category` `367:61`.
  static String get clubCategoryTitle => _t('Category', 'Kategori');
  static String get clubCategorySearchHint =>
      _t('Search or create a tag…', 'Etiket ara veya oluştur…');
  static String get clubCategorySuggested => _t('Suggested', 'Önerilen');
  static String get clubCategoryAdded => _t('Added', 'Eklenen');
  static String get clubCategoryAdd => _t('Add Category', 'Kategori Ekle');
  static String get clubCategoryNoneAdded =>
      _t('No categories yet.', 'Henüz kategori yok.');

  /// `edit-description` `367:157`. The frame prints 300; the app's field has
  /// always capped at 240 and raising it is a backend question, so the limit
  /// is passed in rather than written into the string.
  static String get clubDescriptionTitle => _t('Description', 'Açıklama');
  static String clubDescriptionMax(int max) =>
      _t('Maximum $max characters', 'En fazla $max karakter');
  static String clubDescriptionCounter(int used, int max) => '$used / $max';

  /// `blocked-students` / `blocked-clubs` `414:8` / `414:103`.
  static String get blockedSearchHint =>
      _t('Search blocked…', 'Engellenenlerde ara…');
  static String get blockedStudentsTab => _t('Students', 'Öğrenciler');
  static String get blockedClubsTab => _t('Clubs', 'Kulüpler');
  static String get bannedStudentsLabel =>
      _t('Banned Students', 'Engellenen Öğrenciler');
  static String get bannedClubsLabel =>
      _t('Banned Clubs', 'Engellenen Kulüpler');
  static String get blockedNoMatch =>
      _t('Nothing matches that name.', 'Bu ada uyan bir şey yok.');
  static String blockedClubMembers(int count) =>
      _t('$count Members', '$count Üye');

  /// The name sheet on `settings` `421:9`.
  static String get clubEditNameTitle =>
      _t('Edit Club Name', 'Kulüp Adını Düzenle');
  static String get clubEditNameSubtitle => _t(
    'Changes are updated instantly for all members.',
    'Değişiklikler tüm üyeler için anında güncellenir.',
  );
  static String get clubEditNameField => _t('Club Name', 'Kulüp Adı');
  static String get clubEditNameSave =>
      _t('Save Changes', 'Değişiklikleri Kaydet');

  static String get clubInitials => _t('Club Initials', 'Kulüp Kısaltması');
  static String get clubEditInitialsTitle =>
      _t('Edit Club Initials', 'Kulüp Kısaltmasını Düzenle');
  static String get clubEditInitialsSubtitle => _t(
    'Choose the short @name shown on Home and your public club profile.',
    'Ana sayfada ve herkese açık kulüp profilinde görünecek kısa @adı seç.',
  );
  static String get clubEditInitialsField => _t('Initials', 'Kısaltma');
  static String get clubEditInitialsHint => _t('kbr or IES', 'kbr veya IES');
  static String get clubEditInitialsInvalid => _t(
    'Use 1–15 letters, numbers, or underscores.',
    '1–15 harf, rakam veya alt çizgi kullan.',
  );
  static String get couldNotUpdateClubInitials =>
      _t('Could not update club initials.', 'Kulüp kısaltması güncellenemedi.');
  static String get clubInitialsPermissionMissing => _t(
    'Club initials need the latest database update before they can be saved.',
    'Kulüp kısaltmasını kaydetmek için en son veritabanı güncellemesi gerekli.',
  );

  // ── ACCOUNT SWITCHER area
  /// `profile-switcher` `424:113` / `424:6`.
  static String get switchAccountTitle =>
      _t('Switch Account', 'Hesap Değiştir');
  static String get switchAccountPersonal => _t('Personal', 'Kişisel');
  static String get switchAccountFailed => _t(
    'This account could not be selected. Try again.',
    'Bu hesap seçilemedi. Tekrar dene.',
  );

  // ── STUDENT UI · IN-APP TUTORIAL area
  // Copy lifted verbatim from the `tut-*` frames (y≈34000) and the kit board
  // `canvas-tutorial-kit` 391:4. Turkish runs roughly 20% longer than English,
  // which is why the coach card hugs its height and is never given a fixed one.

  /// `Eyebrow` — the page name, then the counter when the page has more than
  /// one step.
  static String tutorialEyebrow(String page, int current, int total) =>
      _t('$page · STEP $current OF $total', '$page · ADIM $current / $total');

  static String get tutorialPageHomeFeed => _t('HOME FEED', 'ANA AKIŞ');
  static String get tutorialPageThisWeek => _t('THIS WEEK', 'BU HAFTA');
  static String get tutorialPageSearch => _t('SEARCH', 'ARAMA');
  static String get tutorialPageChats => _t('CHATS', 'SOHBETLER');
  static String get tutorialPageProfile => _t('PROFILE', 'PROFİL');
  static String get tutorialPageAnnouncements =>
      _t('ANNOUNCEMENTS', 'DUYURULAR');

  /// The club-admin tour is out of scope on the design board, but it renders
  /// through the same card and still needs page names for its eyebrow.
  static String get tutorialPageClubFeed => _t('CLUB FEED', 'KULÜP AKIŞI');
  static String get tutorialPageClubProfile =>
      _t('CLUB PROFILE', 'KULÜP PROFİLİ');
  static String get tutorialPageModeration => _t('MODERATION', 'MODERASYON');

  /// The primary pill on the last step of a page.
  static String get tutorialGotIt => _t('Got it', 'Anladım');

  // `tut-home-nav` 387:3
  static String get tutorialHomeNavTitle =>
      _t('Five tabs, one app', 'Beş sekme, tek uygulama');
  static String get tutorialHomeNavBody => _t(
    'Home is your club feed. This Week lists events, Search finds clubs and '
        'people, Chats holds every conversation and Profile is your card. '
        'The tab you are on turns burgundy.',
    'Ana sayfa kulüp akışın. Bu Hafta etkinlikleri listeler, Arama kulüpleri '
        've kişileri bulur, Sohbetler tüm yazışmalarını tutar, Profil ise '
        'senin kartın. Bulunduğun sekme bordo olur.',
  );

  // `tut-home-following` 387:394
  static String get tutorialHomeFollowingTitle =>
      _t('Choose what you see', 'Ne göreceğini seç');
  static String get tutorialHomeFollowingBody => _t(
    'Tap Following to switch between the clubs you already follow and '
        'everything happening across campus.',
    'Takip Edilenler’e dokunarak zaten takip ettiğin kulüpler ile kampüsteki '
        'her şey arasında geçiş yap.',
  );

  // `tut-events-filters` 388:1123
  static String get tutorialEventsSearchTitle =>
      _t('Search by keywords', 'Anahtar kelimeyle ara');
  static String get tutorialEventsSearchBody => _t(
    'Type a keyword into the search bar to quickly find events that match '
        'your interests.',
    'İlgi alanlarına uyan etkinlikleri hızlıca bulmak için arama çubuğuna bir '
        'anahtar kelime yaz.',
  );

  // `tut-events-card` 388:1434
  static String get tutorialEventsCardTitle =>
      _t('Every event at a glance', 'Her etkinlik tek bakışta');
  static String get tutorialEventsCardBody => _t(
    'A card carries the date, the time, the place and who is hosting. '
        'Tap it to open the full event page.',
    'Bir kart tarihi, saati, yeri ve düzenleyeni taşır. Etkinliğin tam '
        'sayfasını açmak için karta dokun.',
  );

  // `tut-search-bar` 389:204
  static String get tutorialSearchTitle =>
      _t('One search for everything', 'Her şey için tek arama');
  static String get tutorialSearchBody => _t(
    'Look up clubs, events and people from the same field. Results update '
        'as you type.',
    'Kulüpleri, etkinlikleri ve kişileri aynı alandan ara. Sonuçlar sen '
        'yazdıkça güncellenir.',
  );

  // `tut-chats-tabs` 389:985
  static String get tutorialChatsTitle =>
      _t('Clubs and direct messages', 'Kulüpler ve mesajlar');
  static String get tutorialChatsBody => _t(
    'The dropdown in the header switches between your club chats and your '
        'one to one messages without leaving the page.',
    'Başlıktaki açılır menü, sayfadan çıkmadan kulüp sohbetlerin ile birebir '
        'mesajların arasında geçiş yapar.',
  );

  // `tut-profile-hero` 390:3
  static String get tutorialProfileHeroTitle =>
      _t('Your card on campus', 'Kampüsteki kartın');
  static String get tutorialProfileHeroBody => _t(
    'Your photo, year, major and interests sit at the top. Edit profile '
        'updates all of it, and other students see the same card.',
    'Fotoğrafın, sınıfın, bölümün ve ilgi alanların en üstte durur. Profili '
        'Düzenle hepsini günceller ve diğer öğrenciler aynı kartı görür.',
  );

  // `tut-profile-clubs` 390:248
  static String get tutorialProfileClubsTitle =>
      _t('Your clubs and your events', 'Kulüplerin ve etkinliklerin');
  static String get tutorialProfileClubsBody => _t(
    'My Clubs lists everything you joined and Events keeps the ones you '
        'said yes to. Tap any row to open it.',
    'Kulüplerim katıldığın her şeyi listeler, Etkinlikler ise evet dediklerini '
        'tutar. Açmak için herhangi bir satıra dokun.',
  );

  // `tut-announcements` 389:2162 — a page-level tip, not a tour stop.
  static String get tutorialAnnouncementsTitle =>
      _t('Pinned club news', 'Sabitlenmiş kulüp haberleri');
  static String get tutorialAnnouncementsBody => _t(
    'Announcements are posted by club admins only, so nothing important gets '
        'buried. Read them here, then head back to the chat.',
    'Duyuruları yalnızca kulüp yöneticileri paylaşır, böylece önemli hiçbir '
        'şey kaybolmaz. Buradan oku, sonra sohbete geri dön.',
  );

  // `tut-welcome` 386:3 — step 01.
  static String get tutorialWelcomeEyebrow => _t('WELCOME', 'HOŞ GELDİN');
  static String get tutorialWelcomeTitle =>
      _t('Welcome to ClubUp', 'ClubUp’a hoş geldin');
  static String get tutorialWelcomeBody => _t(
    'A one minute tour of the five things you will use every day: your feed, '
        'events, search, chats and your profile card.',
    'Her gün kullanacağın beş şeyin bir dakikalık turu: akışın, etkinlikler, '
        'arama, sohbetler ve profil kartın.',
  );
  static String get tutorialWelcomeFootnote => _t(
    'You can replay this tour any time from Profile then Settings.',
    'Bu turu istediğin zaman Profil, ardından Ayarlar’dan tekrar izleyebilirsin.',
  );
  static String get tutorialSkipForNow => _t('Skip for now', 'Şimdilik atla');
  static String get tutorialStartTour => _t('Start the tour', 'Tura başla');

  // `tut-finish` 390:1494 — step 32.
  static String get tutorialFinishEyebrow =>
      _t('TOUR COMPLETE', 'TUR TAMAMLANDI');
  static String get tutorialFinishTitle =>
      _t('You are all set', 'Her şey hazır');
  static String get tutorialFinishBody => _t(
    'That is the whole app. Post in your feed, say yes to events, search for '
        'new clubs and keep your profile current.',
    'Uygulamanın tamamı bu kadar. Akışında paylaş, etkinliklere evet de, yeni '
        'kulüpler ara ve profilini güncel tut.',
  );
  static String get tutorialFinishFootnote => _t(
    'Profile then Settings then Replay tutorial brings this back any time.',
    'Profil, ardından Ayarlar, ardından Turu tekrar izle bunu istediğin zaman '
        'geri getirir.',
  );
  static String get tutorialReplayTour =>
      _t('Replay the tour', 'Turu tekrar izle');
  static String get tutorialExploreClubUp =>
      _t('Explore ClubUp', 'ClubUp’ı keşfet');

  // ── EVENT ATTENDEES area
  // A student is shown their friends going, never the guest list, and never a
  // headcount — so none of these carry a number. The singular exists only
  // because "Friends that are going" reads wrong for exactly one.
  static String get friendsGoingLabel =>
      _t('Friends that are going', 'Arkadaşların katılıyor');
  static String get oneFriendGoingLabel =>
      _t('A friend is going', 'Bir arkadaşın katılıyor');
  static String get friendsGoingTitle =>
      _t('Friends going', 'Katılan arkadaşlar');
  // The empty list has to say why it is empty rather than claim nobody is
  // going — the event may well be full.
  static String get friendsGoingEmpty => _t(
    'None of your friends are going yet',
    'Arkadaşlarından kimse henüz katılmıyor',
  );
  static String get attendeesHiddenForClubs => _t(
    'Only the hosting club can see who is going',
    'Kimlerin katıldığını yalnızca etkinliği düzenleyen kulüp görebilir',
  );
}
