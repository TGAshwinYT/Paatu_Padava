import '../domain/models/catalog_entry.dart';

/// Pre-seeded verified film tracks with strict role separation
class CatalogSongsSeed {
  static const List<CatalogSong> data = [
    // --- JAILER (2023) ---
    CatalogSong(
      id: 'cat_jailer_hukum', title: 'Hukum - Thalaivar Alappara', movieTitle: 'Jailer', movieId: 'jailer_2023',
      composer: 'Anirudh Ravichander', singers: 'Anirudh Ravichander, Super Subu', starring: 'Rajinikanth',
      year: 2023, duration: 207, coverUrl: 'https://c.saavncdn.com/492/Jailer-Tamil-2023-20230728185848-500x500.jpg', createdAt: 1690500000,
    ),
    CatalogSong(
      id: 'cat_jailer_kaavaalaa', title: 'Kaavaalaa', movieTitle: 'Jailer', movieId: 'jailer_2023',
      composer: 'Anirudh Ravichander', singers: 'Shilpa Rao, Anirudh Ravichander', starring: 'Tamannaah Bhatia, Rajinikanth',
      year: 2023, duration: 191, coverUrl: 'https://c.saavncdn.com/492/Jailer-Tamil-2023-20230728185848-500x500.jpg', createdAt: 1690500000,
    ),
    CatalogSong(
      id: 'cat_jailer_jujubee', title: 'Jujubee', movieTitle: 'Jailer', movieId: 'jailer_2023',
      composer: 'Anirudh Ravichander', singers: 'Dhee, Anirudh Ravichander, Maran', starring: 'Rajinikanth',
      year: 2023, duration: 167, coverUrl: 'https://c.saavncdn.com/492/Jailer-Tamil-2023-20230728185848-500x500.jpg', createdAt: 1690500000,
    ),

    // --- LEO (2023) ---
    CatalogSong(
      id: 'cat_leo_naa_ready', title: 'Naa Ready', movieTitle: 'Leo', movieId: 'leo_2023',
      composer: 'Anirudh Ravichander', singers: 'Thalapathy Vijay, Anirudh Ravichander, Asal Kolaar', starring: 'Thalapathy Vijay, Trisha Krishnan',
      year: 2023, duration: 248, coverUrl: 'https://c.saavncdn.com/023/Leo-Tamil-2023-20231019114757-500x500.jpg', createdAt: 1697670000,
    ),
    CatalogSong(
      id: 'cat_leo_badass', title: 'Badass', movieTitle: 'Leo', movieId: 'leo_2023',
      composer: 'Anirudh Ravichander', singers: 'Anirudh Ravichander', starring: 'Thalapathy Vijay',
      year: 2023, duration: 229, coverUrl: 'https://c.saavncdn.com/023/Leo-Tamil-2023-20231019114757-500x500.jpg', createdAt: 1697670000,
    ),
    CatalogSong(
      id: 'cat_leo_anbenum', title: 'Anbenum', movieTitle: 'Leo', movieId: 'leo_2023',
      composer: 'Anirudh Ravichander', singers: 'Anirudh Ravichander, Lothika', starring: 'Thalapathy Vijay, Trisha Krishnan',
      year: 2023, duration: 214, coverUrl: 'https://c.saavncdn.com/023/Leo-Tamil-2023-20231019114757-500x500.jpg', createdAt: 1697670000,
    ),
    CatalogSong(
      id: 'cat_leo_ordinary_person', title: 'Ordinary Person', movieTitle: 'Leo', movieId: 'leo_2023',
      composer: 'Anirudh Ravichander', singers: 'Nikhita Gandhi', starring: 'Thalapathy Vijay',
      year: 2023, duration: 138, coverUrl: 'https://c.saavncdn.com/023/Leo-Tamil-2023-20231019114757-500x500.jpg', createdAt: 1697670000,
    ),

    // --- VIKRAM (2022) ---
    CatalogSong(
      id: 'cat_vikram_pathala', title: 'Pathala Pathala', movieTitle: 'Vikram', movieId: 'vikram_2022',
      composer: 'Anirudh Ravichander', singers: 'Kamal Haasan, Anirudh Ravichander', starring: 'Kamal Haasan, Vijay Sethupathi, Fahadh Faasil',
      year: 2022, duration: 211, coverUrl: 'https://c.saavncdn.com/333/Vikram-Tamil-2022-20220515182605-500x500.jpg', createdAt: 1652600000,
    ),
    CatalogSong(
      id: 'cat_vikram_porkanda_singam', title: 'Porkanda Singam', movieTitle: 'Vikram', movieId: 'vikram_2022',
      composer: 'Anirudh Ravichander', singers: 'Ravi G', starring: 'Kamal Haasan',
      year: 2022, duration: 198, coverUrl: 'https://c.saavncdn.com/333/Vikram-Tamil-2022-20220515182605-500x500.jpg', createdAt: 1652600000,
    ),
    CatalogSong(
      id: 'cat_vikram_wasted', title: 'Wasted', movieTitle: 'Vikram', movieId: 'vikram_2022',
      composer: 'Anirudh Ravichander', singers: 'Anirudh Ravichander', starring: 'Kamal Haasan',
      year: 2022, duration: 183, coverUrl: 'https://c.saavncdn.com/333/Vikram-Tamil-2022-20220515182605-500x500.jpg', createdAt: 1652600000,
    ),

    // --- MASTER (2021) ---
    CatalogSong(
      id: 'cat_master_vaathi_coming', title: 'Vaathi Coming', movieTitle: 'Master', movieId: 'master_2021',
      composer: 'Anirudh Ravichander', singers: 'Anirudh Ravichander, Gana Balachandar', starring: 'Thalapathy Vijay',
      year: 2021, duration: 228, coverUrl: 'https://c.saavncdn.com/427/Master-Tamil-2020-20200316084620-500x500.jpg', createdAt: 1610000000,
    ),
    CatalogSong(
      id: 'cat_master_vaathi_raid', title: 'Vaathi Raid', movieTitle: 'Master', movieId: 'master_2021',
      composer: 'Anirudh Ravichander', singers: 'Arivu, Anirudh Ravichander', starring: 'Thalapathy Vijay',
      year: 2021, duration: 208, coverUrl: 'https://c.saavncdn.com/427/Master-Tamil-2020-20200316084620-500x500.jpg', createdAt: 1610000000,
    ),

    // --- VETTAIYAN (2024) ---
    CatalogSong(
      id: 'cat_vettaiyan_manasilaayo', title: 'Manasilaayo', movieTitle: 'Vettaiyan', movieId: 'vettaiyan_2024',
      composer: 'Anirudh Ravichander', singers: 'Malaysia Vasudevan, Yugendran, Anirudh Ravichander, Deepthi Suresh', starring: 'Rajinikanth, Manju Warrier',
      year: 2024, duration: 247, coverUrl: 'https://c.saavncdn.com/743/Vettaiyan-Tamil-2024-20240909192410-500x500.jpg', createdAt: 1725840000,
    ),
    CatalogSong(
      id: 'cat_vettaiyan_hunter_vantaar', title: 'Hunter Vantaar', movieTitle: 'Vettaiyan', movieId: 'vettaiyan_2024',
      composer: 'Anirudh Ravichander', singers: 'Siddharth Basrur', starring: 'Rajinikanth',
      year: 2024, duration: 195, coverUrl: 'https://c.saavncdn.com/743/Vettaiyan-Tamil-2024-20240909192410-500x500.jpg', createdAt: 1725840000,
    ),

    // --- AMARAN (2024) ---
    CatalogSong(
      id: 'cat_amaran_hey_minnale', title: 'Hey Minnale', movieTitle: 'Amaran', movieId: 'amaran_2024',
      composer: 'G.V. Prakash Kumar', singers: 'Haricharan, Shweta Mohan', starring: 'Sivakarthikeyan, Sai Pallavi',
      year: 2024, duration: 254, coverUrl: 'https://c.saavncdn.com/643/Amaran-Tamil-2024-20241004111245-500x500.jpg', createdAt: 1728000000,
    ),
    CatalogSong(
      id: 'cat_amaran_uyirey', title: 'Uyirey', movieTitle: 'Amaran', movieId: 'amaran_2024',
      composer: 'G.V. Prakash Kumar', singers: 'G.V. Prakash Kumar', starring: 'Sivakarthikeyan, Sai Pallavi',
      year: 2024, duration: 232, coverUrl: 'https://c.saavncdn.com/643/Amaran-Tamil-2024-20241004111245-500x500.jpg', createdAt: 1728000000,
    ),

    // --- GOAT (2024) ---
    CatalogSong(
      id: 'cat_goat_whistle_podu', title: 'Whistle Podu', movieTitle: 'GOAT - The Greatest Of All Time', movieId: 'goat_2024',
      composer: 'Yuvan Shankar Raja', singers: 'Thalapathy Vijay, Yuvan Shankar Raja', starring: 'Thalapathy Vijay',
      year: 2024, duration: 258, coverUrl: 'https://c.saavncdn.com/832/The-Greatest-Of-All-Time-Tamil-2024-500x500.jpg', createdAt: 1713000000,
    ),
    CatalogSong(
      id: 'cat_goat_spark', title: 'Spark', movieTitle: 'GOAT - The Greatest Of All Time', movieId: 'goat_2024',
      composer: 'Yuvan Shankar Raja', singers: 'Yuvan Shankar Raja, Vrusha Balu', starring: 'Thalapathy Vijay, Meenakshi Chaudhary',
      year: 2024, duration: 228, coverUrl: 'https://c.saavncdn.com/832/The-Greatest-Of-All-Time-Tamil-2024-500x500.jpg', createdAt: 1722600000,
    ),
    CatalogSong(
      id: 'cat_goat_matta', title: 'Matta', movieTitle: 'GOAT - The Greatest Of All Time', movieId: 'goat_2024',
      composer: 'Yuvan Shankar Raja', singers: 'Yuvan Shankar Raja, Shenbagaraj', starring: 'Thalapathy Vijay',
      year: 2024, duration: 205, coverUrl: 'https://c.saavncdn.com/832/The-Greatest-Of-All-Time-Tamil-2024-500x500.jpg', createdAt: 1725000000,
    ),

    // --- ROJA (1992) ---
    CatalogSong(
      id: 'cat_roja_chinna_chinna_aasai', title: 'Chinna Chinna Aasai', movieTitle: 'Roja', movieId: 'roja_1992',
      composer: 'A.R. Rahman', singers: 'Minmini', starring: 'Arvind Swamy, Madhoo',
      year: 1992, duration: 295, coverUrl: 'https://c.saavncdn.com/500/Roja-Tamil-1992-500x500.jpg', createdAt: 713900000,
    ),
    CatalogSong(
      id: 'cat_roja_pudhu_vellai_mazhai', title: 'Pudhu Vellai Mazhai', movieTitle: 'Roja', movieId: 'roja_1992',
      composer: 'A.R. Rahman', singers: 'Unni Menon, Sujatha Mohan', starring: 'Arvind Swamy, Madhoo',
      year: 1992, duration: 316, coverUrl: 'https://c.saavncdn.com/500/Roja-Tamil-1992-500x500.jpg', createdAt: 713900000,
    ),

    // --- VINNAITHAANDI VARUVAAYAA (2010) ---
    CatalogSong(
      id: 'cat_vtv_hosanna', title: 'Hosanna', movieTitle: 'Vinnaithaandi Varuvaayaa', movieId: 'vinnaithaandi_varuvaayaa_2010',
      composer: 'A.R. Rahman', singers: 'Vijay Prakash, Suzanne D\'Mello, Blaaze', starring: 'Silambarasan TR, Trisha Krishnan',
      year: 2010, duration: 331, coverUrl: 'https://c.saavncdn.com/500/Vinnaithaandi-Varuvaayaa-Tamil-2010-500x500.jpg', createdAt: 1263000000,
    ),
    CatalogSong(
      id: 'cat_vtv_aaromale', title: 'Aaromale', movieTitle: 'Vinnaithaandi Varuvaayaa', movieId: 'vinnaithaandi_varuvaayaa_2010',
      composer: 'A.R. Rahman', singers: 'Alphons Joseph', starring: 'Silambarasan TR',
      year: 2010, duration: 346, coverUrl: 'https://c.saavncdn.com/500/Vinnaithaandi-Varuvaayaa-Tamil-2010-500x500.jpg', createdAt: 1263000000,
    ),

    // --- PAIYAA (2010) ---
    CatalogSong(
      id: 'cat_paiyaa_thuli_thuli', title: 'Thuli Thuli', movieTitle: 'Paiyaa', movieId: 'paiyaa_2010',
      composer: 'Yuvan Shankar Raja', singers: 'Haricharan, Tanvi Shah', starring: 'Karthi, Tamannaah Bhatia',
      year: 2010, duration: 284, coverUrl: 'https://c.saavncdn.com/500/Paiyaa-Tamil-2010-500x500.jpg', createdAt: 1260000000,
    ),
    CatalogSong(
      id: 'cat_paiyaa_adada_mazhaida', title: 'Adada Mazhaida', movieTitle: 'Paiyaa', movieId: 'paiyaa_2010',
      composer: 'Yuvan Shankar Raja', singers: 'Rahul Nambiar, Saindhavi', starring: 'Karthi, Tamannaah Bhatia',
      year: 2010, duration: 254, coverUrl: 'https://c.saavncdn.com/500/Paiyaa-Tamil-2010-500x500.jpg', createdAt: 1260000000,
    ),

    // --- INDEPENDENT CHARTBUSTERS ---
    CatalogSong(
      id: 'cat_katchi_sera', title: 'Katchi Sera', movieTitle: 'Think Indie', movieId: null,
      composer: 'Sai Abhyankkar', singers: 'Sai Abhyankkar', starring: 'Sai Abhyankkar',
      year: 2024, duration: 185, coverUrl: 'https://c.saavncdn.com/artists/Sai_Abhyankkar_500x500.jpg', createdAt: 1705000000,
    ),
    CatalogSong(
      id: 'cat_aasa_kooda', title: 'Aasa Kooda', movieTitle: 'Think Indie', movieId: null,
      composer: 'Sai Abhyankkar', singers: 'Sai Abhyankkar, Sai Smriti', starring: 'Sai Abhyankkar',
      year: 2024, duration: 198, coverUrl: 'https://c.saavncdn.com/artists/Sai_Abhyankkar_500x500.jpg', createdAt: 1718000000,
    ),
    CatalogSong(
      id: 'cat_enjoy_enjaami', title: 'Enjoy Enjaami', movieTitle: 'Maajja', movieId: null,
      composer: 'Santhosh Narayanan', singers: 'Dhee, Arivu', starring: 'Dhee, Arivu',
      year: 2021, duration: 250, coverUrl: 'https://c.saavncdn.com/500/Enjoy-Enjaami-Tamil-2021-500x500.jpg', createdAt: 1615000000,
    ),

    // --- MEESAYA MURUKKU (2017) ---
    CatalogSong(
      id: 'cat_meesaya_murukku_title', title: 'Meesaya Murukku', movieTitle: 'Meesaya Murukku', movieId: 'meesaya_murukku_2017',
      composer: 'Hiphop Tamizha', singers: 'Hiphop Tamizha, Kharesma Ravichandran', starring: 'Hiphop Tamizha Aadhi, Aathmika',
      year: 2017, duration: 224, coverUrl: 'https://c.saavncdn.com/500/Meesaya-Murukku-Tamil-2017-500x500.jpg', createdAt: 1500000000,
    ),

    // --- BAASHA (1995) ---
    CatalogSong(
      id: 'cat_baasha_naan_autokaaran', title: 'Naan Autokaaran', movieTitle: 'Baasha', movieId: 'baasha_1995',
      composer: 'Deva', singers: 'S.P. Balasubrahmanyam', starring: 'Rajinikanth',
      year: 1995, duration: 284, coverUrl: 'https://c.saavncdn.com/500/Baasha-Tamil-1995-500x500.jpg', createdAt: 790000000,
    ),

    // --- GHILLI (2004) ---
    CatalogSong(
      id: 'cat_ghilli_appadi_podu', title: 'Appadi Podu', movieTitle: 'Ghilli', movieId: 'ghilli_2004',
      composer: 'Vidyasagar', singers: 'KK, Anuradha Sriram', starring: 'Thalapathy Vijay, Trisha Krishnan',
      year: 2004, duration: 334, coverUrl: 'https://c.saavncdn.com/500/Ghilli-Tamil-2004-500x500.jpg', createdAt: 1080000000,
    ),
  ];
}
