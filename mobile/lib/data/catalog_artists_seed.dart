import '../domain/models/catalog_entry.dart';

/// Pre-seeded verified musical artists across 18 regional and global music languages
class CatalogArtistsSeed {
  static const List<CatalogArtist> data = [
    // --- Tamil ---
    CatalogArtist(id: 'anirudh_ravichander', name: 'Anirudh Ravichander', role: 'Composer / Singer', imageUrl: 'https://c.saavncdn.com/artists/Anirudh_Ravichander_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'ar_rahman', name: 'A.R. Rahman', role: 'Composer / Singer', imageUrl: 'https://c.saavncdn.com/artists/AR_Rahman_002_20210120084455_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'yuvan_shankar_raja', name: 'Yuvan Shankar Raja', role: 'Composer / Singer', imageUrl: 'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'harris_jayaraj', name: 'Harris Jayaraj', role: 'Composer', imageUrl: 'https://c.saavncdn.com/artists/Harris_Jayaraj_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'ilaiyaraaja', name: 'Ilaiyaraaja', role: 'Maestro Composer / Singer', imageUrl: 'https://c.saavncdn.com/artists/Ilaiyaraaja_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'santhosh_narayanan', name: 'Santhosh Narayanan', role: 'Composer / Singer', imageUrl: 'https://c.saavncdn.com/artists/Santhosh_Narayanan_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'gv_prakash_kumar', name: 'G.V. Prakash Kumar', role: 'Composer / Singer', imageUrl: 'https://c.saavncdn.com/artists/G_V__Prakash_Kumar_003_20251113063655_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'sid_sriram', name: 'Sid Sriram', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Sid_Sriram_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'sp_balasubrahmanyam', name: 'S.P. Balasubrahmanyam', role: 'Legendary Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/S_P_Balasubrahmanyam_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'ks_chithra', name: 'K.S. Chithra', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/K_S__Chithra_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'shreya_ghoshal', name: 'Shreya Ghoshal', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Shreya_Ghoshal_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'pradeep_kumar', name: 'Pradeep Kumar', role: 'Playback Singer / Composer', imageUrl: 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'haricharan', name: 'Haricharan', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Haricharan_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'chinmayi', name: 'Chinmayi', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Chinmayi_Sripada_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'swetha_mohan', name: 'Swetha Mohan', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Shweta_Mohan_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'jonita_gandhi', name: 'Jonita Gandhi', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Jonita_Gandhi_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'sai_abhyankkar', name: 'Sai Abhyankkar', role: 'Composer / Singer', imageUrl: 'https://c.saavncdn.com/artists/Sai_Abhyankkar_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'd_imman', name: 'D. Imman', role: 'Composer', imageUrl: 'https://c.saavncdn.com/artists/D__Imman_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'deva', name: 'Deva', role: 'Composer / Gaana Singer', imageUrl: 'https://c.saavncdn.com/artists/Deva_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'vidyasagar', name: 'Vidyasagar', role: 'Composer', imageUrl: 'https://c.saavncdn.com/artists/Vidyasagar_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'hiphop_tamizha', name: 'Hiphop Tamizha', role: 'Composer / Hip Hop Artist', imageUrl: 'https://c.saavncdn.com/artists/Hiphop_Tamizha_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'dhee', name: 'Dhee', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Dhee_20180510121326_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'super_subu', name: 'Super Subu', role: 'Lyricist / Singer', imageUrl: 'https://c.saavncdn.com/artists/Super_Subu_000_20230809105700_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'anthony_daasan', name: 'Anthony Daasan', role: 'Folk / Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Anthony_Daasan_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'thaman_s', name: 'Thaman S', role: 'Composer / Singer', imageUrl: 'https://c.saavncdn.com/artists/Thaman_S_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'vishal_mishra', name: 'Vishal Mishra', role: 'Playback Singer / Composer', imageUrl: 'https://c.saavncdn.com/artists/Vishal_Mishra_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'dhanush', name: 'Dhanush', role: 'Playback Singer / Lyricist', imageUrl: 'https://c.saavncdn.com/artists/Dhanush_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'hesham_abdul_wahab', name: 'Hesham Abdul Wahab', role: 'Music Director / Singer', imageUrl: 'https://c.saavncdn.com/artists/Hesham_Abdul_Wahab_001_20220919094035_500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'dhruv_vikram', name: 'Dhruv Vikram', role: 'Actor / Playback Singer', imageUrl: 'https://c.saavncdn.com/498/Adithya-Varma-Tamil-2019-20191127090744-500x500.jpg', language: 'tamil'),
    CatalogArtist(id: 'shruti_haasan', name: 'Shruti Haasan', role: 'Playback Singer / Actress', imageUrl: 'https://c.saavncdn.com/artists/Shruti_Haasan_500x500.jpg', language: 'tamil'),

    // --- English ---
    CatalogArtist(id: 'taylor_swift', name: 'Taylor Swift', role: 'Pop / Country Singer-Songwriter', imageUrl: 'https://c.saavncdn.com/artists/Taylor_Swift_500x500.jpg', language: 'english'),
    CatalogArtist(id: 'ed_sheeran', name: 'Ed Sheeran', role: 'Pop / Acoustic Singer-Songwriter', imageUrl: 'https://c.saavncdn.com/artists/Ed_Sheeran_500x500.jpg', language: 'english'),
    CatalogArtist(id: 'the_weeknd', name: 'The Weeknd', role: 'R&B / Synth-Pop Artist', imageUrl: 'https://c.saavncdn.com/artists/The_Weeknd_500x500.jpg', language: 'english'),
    CatalogArtist(id: 'drake', name: 'Drake', role: 'Hip-Hop / R&B Artist', imageUrl: 'https://c.saavncdn.com/artists/Drake_500x500.jpg', language: 'english'),
    CatalogArtist(id: 'billie_eilish', name: 'Billie Eilish', role: 'Alternative Pop Singer', imageUrl: 'https://c.saavncdn.com/artists/Billie_Eilish_500x500.jpg', language: 'english'),
    CatalogArtist(id: 'bruno_mars', name: 'Bruno Mars', role: 'Funk / Pop Singer', imageUrl: 'https://c.saavncdn.com/artists/Bruno_Mars_500x500.jpg', language: 'english'),
    CatalogArtist(id: 'dua_lipa', name: 'Dua Lipa', role: 'Dance Pop Singer', imageUrl: 'https://c.saavncdn.com/artists/Dua_Lipa_500x500.jpg', language: 'english'),
    CatalogArtist(id: 'coldplay', name: 'Coldplay', role: 'Alternative Rock Band', imageUrl: 'https://c.saavncdn.com/artists/Coldplay_500x500.jpg', language: 'english'),
    CatalogArtist(id: 'eminem', name: 'Eminem', role: 'Legendary Hip-Hop Artist', imageUrl: 'https://c.saavncdn.com/artists/Eminem_500x500.jpg', language: 'english'),
    CatalogArtist(id: 'post_malone', name: 'Post Malone', role: 'Pop / Hip-Hop Singer', imageUrl: 'https://c.saavncdn.com/artists/Post_Malone_500x500.jpg', language: 'english'),

    // --- Hindi ---
    CatalogArtist(id: 'arijit_singh', name: 'Arijit Singh', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Arijit_Singh_002_20230323062147_500x500.jpg', language: 'hindi'),
    CatalogArtist(id: 'pritam', name: 'Pritam', role: 'Music Director', imageUrl: 'https://c.saavncdn.com/artists/Pritam_500x500.jpg', language: 'hindi'),
    CatalogArtist(id: 'shreya_ghoshal_hindi', name: 'Shreya Ghoshal', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Shreya_Ghoshal_500x500.jpg', language: 'hindi'),
    CatalogArtist(id: 'neha_kakkar', name: 'Neha Kakkar', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Neha_Kakkar_500x500.jpg', language: 'hindi'),
    CatalogArtist(id: 'atif_aslam', name: 'Atif Aslam', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Atif_Aslam_500x500.jpg', language: 'hindi'),
    CatalogArtist(id: 'badshah', name: 'Badshah', role: 'Rapper / Producer', imageUrl: 'https://c.saavncdn.com/artists/Badshah_500x500.jpg', language: 'hindi'),
    CatalogArtist(id: 'jubin_nautiyal', name: 'Jubin Nautiyal', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Jubin_Nautiyal_500x500.jpg', language: 'hindi'),
    CatalogArtist(id: 'vishal_shekhar', name: 'Vishal-Shekhar', role: 'Music Directors', imageUrl: 'https://c.saavncdn.com/artists/Vishal_Shekhar_500x500.jpg', language: 'hindi'),
    CatalogArtist(id: 'sachin_jigar_hindi', name: 'Sachin-Jigar', role: 'Music Directors', imageUrl: 'https://c.saavncdn.com/artists/Sachin_Jigar_500x500.jpg', language: 'hindi'),
    CatalogArtist(id: 'sonu_nigam', name: 'Sonu Nigam', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Sonu_Nigam_500x500.jpg', language: 'hindi'),

    // --- Telugu ---
    CatalogArtist(id: 'devi_sri_prasad', name: 'Devi Sri Prasad', role: 'Music Director / Singer', imageUrl: 'https://c.saavncdn.com/artists/Devi_Sri_Prasad_500x500.jpg', language: 'telugu'),
    CatalogArtist(id: 'thaman_s_telugu', name: 'Thaman S', role: 'Music Director', imageUrl: 'https://c.saavncdn.com/artists/Thaman_S_500x500.jpg', language: 'telugu'),
    CatalogArtist(id: 'anurag_kulkarni', name: 'Anurag Kulkarni', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Anurag_Kulkarni_500x500.jpg', language: 'telugu'),
    CatalogArtist(id: 'mm_keeravaani', name: 'M.M. Keeravaani', role: 'Music Director / Composer', imageUrl: 'https://c.saavncdn.com/artists/M_M__Keeravani_500x500.jpg', language: 'telugu'),
    CatalogArtist(id: 'armaan_malik_telugu', name: 'Armaan Malik', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Armaan_Malik_500x500.jpg', language: 'telugu'),
    CatalogArtist(id: 'ram_miriyala', name: 'Ram Miriyala', role: 'Singer / Composer', imageUrl: 'https://c.saavncdn.com/artists/Ram_Miriyala_500x500.jpg', language: 'telugu'),
    CatalogArtist(id: 'mangli', name: 'Mangli', role: 'Folk / Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Mangli_500x500.jpg', language: 'telugu'),

    // --- Malayalam ---
    CatalogArtist(id: 'sushin_shyam', name: 'Sushin Shyam', role: 'Music Director / Singer', imageUrl: 'https://c.saavncdn.com/artists/Sushin_Shyam_500x500.jpg', language: 'malayalam'),
    CatalogArtist(id: 'jakes_bejoy', name: 'Jakes Bejoy', role: 'Music Director', imageUrl: 'https://c.saavncdn.com/artists/Jakes_Bejoy_500x500.jpg', language: 'malayalam'),
    CatalogArtist(id: 'kj_yesudas', name: 'K.J. Yesudas', role: 'Legendary Classical Singer', imageUrl: 'https://c.saavncdn.com/artists/K_J__Yesudas_500x500.jpg', language: 'malayalam'),
    CatalogArtist(id: 'hesham_abdul_wahab_mal', name: 'Hesham Abdul Wahab', role: 'Music Director / Singer', imageUrl: 'https://c.saavncdn.com/artists/Hesham_Abdul_Wahab_001_20220919094035_500x500.jpg', language: 'malayalam'),
    CatalogArtist(id: 'shaan_rahman', name: 'Shaan Rahman', role: 'Music Director', imageUrl: 'https://c.saavncdn.com/artists/Shaan_Rahman_500x500.jpg', language: 'malayalam'),
    CatalogArtist(id: 'gopi_sundar', name: 'Gopi Sundar', role: 'Music Director', imageUrl: 'https://c.saavncdn.com/artists/Gopi_Sundar_500x500.jpg', language: 'malayalam'),
    CatalogArtist(id: 'vineeth_sreenivasan', name: 'Vineeth Sreenivasan', role: 'Singer / Director', imageUrl: 'https://c.saavncdn.com/artists/Vineeth_Sreenivasan_500x500.jpg', language: 'malayalam'),

    // --- Kannada ---
    CatalogArtist(id: 'arjun_janya', name: 'Arjun Janya', role: 'Music Director', imageUrl: 'https://c.saavncdn.com/artists/Arjun_Janya_500x500.jpg', language: 'kannada'),
    CatalogArtist(id: 'charan_raj', name: 'Charan Raj', role: 'Composer', imageUrl: 'https://c.saavncdn.com/artists/Charan_Raj_500x500.jpg', language: 'kannada'),
    CatalogArtist(id: 'sanjith_hegde', name: 'Sanjith Hegde', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Sanjith_Hegde_500x500.jpg', language: 'kannada'),
    CatalogArtist(id: 'vijay_prakash', name: 'Vijay Prakash', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Vijay_Prakash_500x500.jpg', language: 'kannada'),
    CatalogArtist(id: 'ajaneesh_loknath', name: 'B. Ajaneesh Loknath', role: 'Composer', imageUrl: 'https://c.saavncdn.com/artists/B_Ajaneesh_Loknath_500x500.jpg', language: 'kannada'),
    CatalogArtist(id: 'ravi_basrur', name: 'Ravi Basrur', role: 'Music Director', imageUrl: 'https://c.saavncdn.com/artists/Ravi_Basrur_500x500.jpg', language: 'kannada'),

    // --- Punjabi ---
    CatalogArtist(id: 'diljit_dosanjh', name: 'Diljit Dosanjh', role: 'Singer / Global Icon', imageUrl: 'https://c.saavncdn.com/artists/Diljit_Dosanjh_500x500.jpg', language: 'punjabi'),
    CatalogArtist(id: 'sidhu_moose_wala', name: 'Sidhu Moose Wala', role: 'Singer / Rapper', imageUrl: 'https://c.saavncdn.com/artists/Sidhu_Moose_Wala_500x500.jpg', language: 'punjabi'),
    CatalogArtist(id: 'karan_aujla', name: 'Karan Aujla', role: 'Singer / Rapper', imageUrl: 'https://c.saavncdn.com/artists/Karan_Aujla_500x500.jpg', language: 'punjabi'),
    CatalogArtist(id: 'ap_dhillon', name: 'AP Dhillon', role: 'Singer / Producer', imageUrl: 'https://c.saavncdn.com/artists/AP_Dhillon_500x500.jpg', language: 'punjabi'),
    CatalogArtist(id: 'guru_randhawa', name: 'Guru Randhawa', role: 'Singer / Composer', imageUrl: 'https://c.saavncdn.com/artists/Guru_Randhawa_500x500.jpg', language: 'punjabi'),
    CatalogArtist(id: 'b_praak', name: 'B Praak', role: 'Singer / Music Director', imageUrl: 'https://c.saavncdn.com/artists/B_Praak_500x500.jpg', language: 'punjabi'),

    // --- Marathi ---
    CatalogArtist(id: 'ajay_atul', name: 'Ajay-Atul', role: 'Music Directors', imageUrl: 'https://c.saavncdn.com/artists/Ajay_Atul_500x500.jpg', language: 'marathi'),
    CatalogArtist(id: 'swapnil_bandodkar', name: 'Swapnil Bandodkar', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Swapnil_Bandodkar_500x500.jpg', language: 'marathi'),
    CatalogArtist(id: 'avdhoot_gupte', name: 'Avdhoot Gupte', role: 'Singer / Director', imageUrl: 'https://c.saavncdn.com/artists/Avdhoot_Gupte_500x500.jpg', language: 'marathi'),
    CatalogArtist(id: 'adarsh_shinde', name: 'Adarsh Shinde', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Adarsh_Shinde_500x500.jpg', language: 'marathi'),

    // --- Bengali ---
    CatalogArtist(id: 'anupam_roy', name: 'Anupam Roy', role: 'Singer / Lyricist', imageUrl: 'https://c.saavncdn.com/artists/Anupam_Roy_500x500.jpg', language: 'bengali'),
    CatalogArtist(id: 'jeet_gannguli', name: 'Jeet Gannguli', role: 'Music Director', imageUrl: 'https://c.saavncdn.com/artists/Jeet_Gannguli_500x500.jpg', language: 'bengali'),
    CatalogArtist(id: 'shaan_bengali', name: 'Shaan', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Shaan_500x500.jpg', language: 'bengali'),

    // --- Gujarati ---
    CatalogArtist(id: 'kinjal_dave', name: 'Kinjal Dave', role: 'Folk / Garba Singer', imageUrl: 'https://c.saavncdn.com/artists/Kinjal_Dave_500x500.jpg', language: 'gujarati'),
    CatalogArtist(id: 'geeta_rabari', name: 'Geeta Rabari', role: 'Folk Singer', imageUrl: 'https://c.saavncdn.com/artists/Geeta_Rabari_500x500.jpg', language: 'gujarati'),
    CatalogArtist(id: 'aditya_gadhvi', name: 'Aditya Gadhvi', role: 'Folk Singer', imageUrl: 'https://c.saavncdn.com/artists/Aditya_Gadhvi_500x500.jpg', language: 'gujarati'),

    // --- Bhojpuri ---
    CatalogArtist(id: 'pawan_singh', name: 'Pawan Singh', role: 'Singer / Actor', imageUrl: 'https://c.saavncdn.com/artists/Pawan_Singh_500x500.jpg', language: 'bhojpuri'),
    CatalogArtist(id: 'khesari_lal_yadav', name: 'Khesari Lal Yadav', role: 'Singer / Actor', imageUrl: 'https://c.saavncdn.com/artists/Khesari_Lal_Yadav_500x500.jpg', language: 'bhojpuri'),
    CatalogArtist(id: 'shilpi_raj', name: 'Shilpi Raj', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Shilpi_Raj_500x500.jpg', language: 'bhojpuri'),

    // --- Urdu ---
    CatalogArtist(id: 'rahat_fateh_ali_khan', name: 'Rahat Fateh Ali Khan', role: 'Qawwali / Sufi Singer', imageUrl: 'https://c.saavncdn.com/artists/Rahat_Fateh_Ali_Khan_500x500.jpg', language: 'urdu'),
    CatalogArtist(id: 'nusrat_fateh_ali_khan', name: 'Nusrat Fateh Ali Khan', role: 'Qawwali Maestro', imageUrl: 'https://c.saavncdn.com/artists/Nusrat_Fateh_Ali_Khan_500x500.jpg', language: 'urdu'),
    CatalogArtist(id: 'ali_zafar', name: 'Ali Zafar', role: 'Singer / Songwriter', imageUrl: 'https://c.saavncdn.com/artists/Ali_Zafar_500x500.jpg', language: 'urdu'),

    // --- Haryanvi ---
    CatalogArtist(id: 'renuka_panwar', name: 'Renuka Panwar', role: 'Folk / Pop Singer', imageUrl: 'https://c.saavncdn.com/artists/Renuka_Panwar_500x500.jpg', language: 'haryanvi'),
    CatalogArtist(id: 'gulzaar_chhaniwala', name: 'Gulzaar Chhaniwala', role: 'Singer / Producer', imageUrl: 'https://c.saavncdn.com/artists/Gulzaar_Chhaniwala_500x500.jpg', language: 'haryanvi'),

    // --- Rajasthani ---
    CatalogArtist(id: 'mame_khan', name: 'Mame Khan', role: 'Folk / Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Mame_Khan_500x500.jpg', language: 'rajasthani'),
    CatalogArtist(id: 'ila_arun', name: 'Ila Arun', role: 'Folk Pop Singer', imageUrl: 'https://c.saavncdn.com/artists/Ila_Arun_500x500.jpg', language: 'rajasthani'),

    // --- Odia ---
    CatalogArtist(id: 'humane_sagar', name: 'Humane Sagar', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Humane_Sagar_500x500.jpg', language: 'odia'),
    CatalogArtist(id: 'diptirekha_padhi', name: 'Diptirekha Padhi', role: 'Playback Singer', imageUrl: 'https://c.saavncdn.com/artists/Diptirekha_Padhi_500x500.jpg', language: 'odia'),

    // --- Assamese ---
    CatalogArtist(id: 'zubeen_garg', name: 'Zubeen Garg', role: 'Singer / Composer', imageUrl: 'https://c.saavncdn.com/artists/Zubeen_Garg_500x500.jpg', language: 'assamese'),
    CatalogArtist(id: 'papon', name: 'Papon', role: 'Singer / Composer', imageUrl: 'https://c.saavncdn.com/artists/Papon_500x500.jpg', language: 'assamese'),

    // --- Spanish ---
    CatalogArtist(id: 'bad_bunny', name: 'Bad Bunny', role: 'Latin Trap / Reggaeton Icon', imageUrl: 'https://c.saavncdn.com/artists/Bad_Bunny_500x500.jpg', language: 'spanish'),
    CatalogArtist(id: 'rosalia', name: 'Rosalía', role: 'Flamenco Pop Singer', imageUrl: 'https://c.saavncdn.com/artists/Rosalia_500x500.jpg', language: 'spanish'),
    CatalogArtist(id: 'j_balvin', name: 'J Balvin', role: 'Reggaeton Artist', imageUrl: 'https://c.saavncdn.com/artists/J_Balvin_500x500.jpg', language: 'spanish'),
    CatalogArtist(id: 'shakira', name: 'Shakira', role: 'Latin Pop Superstar', imageUrl: 'https://c.saavncdn.com/artists/Shakira_500x500.jpg', language: 'spanish'),

    // --- Korean ---
    CatalogArtist(id: 'bts', name: 'BTS', role: 'K-Pop Supergroup', imageUrl: 'https://c.saavncdn.com/artists/BTS_500x500.jpg', language: 'korean'),
    CatalogArtist(id: 'blackpink', name: 'BLACKPINK', role: 'K-Pop Girl Group', imageUrl: 'https://c.saavncdn.com/artists/Blackpink_500x500.jpg', language: 'korean'),
    CatalogArtist(id: 'newjeans', name: 'NewJeans', role: 'K-Pop Girl Group', imageUrl: 'https://c.saavncdn.com/artists/NewJeans_500x500.jpg', language: 'korean'),
    CatalogArtist(id: 'iu', name: 'IU', role: 'Singer-Songwriter / Actress', imageUrl: 'https://c.saavncdn.com/artists/IU_500x500.jpg', language: 'korean'),
  ];

  /// Retrieves verified artists matching the given language (case-insensitive)
  static List<CatalogArtist> getArtistsForLanguage(String language, {int limit = 12}) {
    final langNorm = language.trim().toLowerCase();
    final matches = data.where((a) => a.language.toLowerCase() == langNorm).take(limit).toList();
    if (matches.isNotEmpty) return matches;
    return data.take(limit).toList();
  }

  /// Retrieves verified artists matching any of the user's preferred languages
  static List<CatalogArtist> getArtistsForLanguages(List<String> languages, {int limitPerLang = 6}) {
    if (languages.isEmpty) return data.take(15).toList();
    final List<CatalogArtist> result = [];
    final Set<String> addedIds = {};

    for (final lang in languages) {
      final langNorm = lang.trim().toLowerCase();
      final perLang = data.where((a) => a.language.toLowerCase() == langNorm).take(limitPerLang);
      for (final a in perLang) {
        if (!addedIds.contains(a.id)) {
          addedIds.add(a.id);
          result.add(a);
        }
      }
    }

    if (result.isEmpty) {
      return data.take(15).toList();
    }
    return result;
  }
}
