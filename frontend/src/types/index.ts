export interface Song {
  id: string;
  title: string;
  artist: string;
  coverUrl: string;
  audioUrl: string;
  downloadUrls?: string[];
}

export const DUMMY_SONGS: Song[] = [
  {
    id: "1",
    title: "Lofi Study",
    artist: "FASSounds",
    coverUrl: "https://images.unsplash.com/photo-1614613535308-eb5fbd3d2c17?w=300&h=300&fit=crop",
    audioUrl: "https://cdn.pixabay.com/download/audio/2022/05/27/audio_1808fbf07a.mp3?filename=lofi-study-112191.mp3"
  },
  {
    id: "2",
    title: "Good Night",
    artist: "FASSounds",
    coverUrl: "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=300&h=300&fit=crop",
    audioUrl: "https://cdn.pixabay.com/download/audio/2022/10/14/audio_9939f792cb.mp3?filename=good-night-109988.mp3"
  },
  {
    id: "3",
    title: "Chill Abstract",
    artist: "Coma-Media",
    coverUrl: "https://images.unsplash.com/photo-1493225457124-a1a2a5f529db?w=300&h=300&fit=crop",
    audioUrl: "https://cdn.pixabay.com/download/audio/2022/11/03/audio_c8c8fc5cb7.mp3?filename=chill-abstract-intention-12099.mp3"
  },
  {
    id: "4",
    title: "Separation",
    artist: "William_King",
    coverUrl: "https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=300&h=300&fit=crop",
    audioUrl: "https://cdn.pixabay.com/download/audio/2022/10/25/audio_24a25c3eb6.mp3?filename=separation-185196.mp3"
  },
  {
    id: "5",
    title: "Leva Eternity",
    artist: "Lemonmusicstudio",
    coverUrl: "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300&h=300&fit=crop",
    audioUrl: "https://cdn.pixabay.com/download/audio/2021/11/25/audio_91b3cb81ed.mp3?filename=leva-eternity-149473.mp3"
  }
];
