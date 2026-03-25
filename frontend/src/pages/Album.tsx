import { useParams, Link } from 'react-router-dom';
import { Play, Heart, Download, MoreHorizontal, Clock } from 'lucide-react';
import { useAudio } from '../context/AudioContext';
import PopularAlbums from '../components/PopularAlbums';

const Album = () => {
    const { id } = useParams();
    const { playTrack } = useAudio();

    // Dummy Data for immediate rendering
    const albumData = {
        id: id || '1',
        title: 'Manmadhan Ambu',
        artist: 'Devi Sri Prasad',
        artistImage: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=50&h=50&fit=crop',
        coverUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&h=500&fit=crop',
        year: '2010',
        songCount: '10 songs',
        duration: '42 min 15 sec',
        dominantColor: '#4a3b32',
        tracks: [
            { id: 's1', title: 'Dhinka Chika', artist: 'Devi Sri Prasad', duration: '4:15' },
            { id: 's2', title: 'Neeyum Naanum', artist: 'Devi Sri Prasad', duration: '5:20' },
            { id: 's3', title: 'Kamal Haasan Special', artist: 'Devi Sri Prasad', duration: '3:45' },
            { id: 's4', title: 'Oivilaamal', artist: 'Devi Sri Prasad', duration: '4:10' },
            { id: 's5', title: 'Theme of Manmadhan', artist: 'Devi Sri Prasad', duration: '2:30' },
        ],
        moreAlbums: [
            { id: 'a2', title: 'Pushpa', coverUrl: 'https://images.unsplash.com/photo-1493225457124-a1a2a5ea3a26?w=200&h=200&fit=crop' },
            { id: 'a3', title: 'Arya 2', coverUrl: 'https://images.unsplash.com/photo-1514525253361-bee8a19740c1?w=200&h=200&fit=crop' },
            { id: 'a4', title: 'Singam', coverUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=200&h=200&fit=crop' },
            { id: 'a5', title: 'Gabbar Singh', coverUrl: 'https://images.unsplash.com/photo-1459749411177-042180ce673c?w=200&h=200&fit=crop' },
        ]
    };

    return (
        <div className="flex flex-col min-h-full">
            {/* Hero Header */}
            <div 
                className="relative pt-12 pb-8 px-6 flex flex-col md:flex-row items-center md:items-end gap-8 transition-colors duration-500"
                style={{ background: `linear-gradient(to bottom, ${albumData.dominantColor}, #171717)` }}
            >
                {/* Album Cover */}
                <div className="w-48 h-48 md:w-60 md:h-60 flex-shrink-0 shadow-[0_8px_40px_rgba(0,0,0,0.6)] rounded-sm overflow-hidden transform hover:scale-[1.02] transition-transform duration-300">
                    <img 
                        src={albumData.coverUrl} 
                        alt={albumData.title}
                        className="w-full h-full object-cover"
                    />
                </div>

                {/* Album Details */}
                <div className="flex flex-col items-center md:items-start text-center md:text-left">
                    <span className="text-xs font-bold uppercase tracking-widest text-white mb-2">Album</span>
                    <h1 className="text-4xl md:text-7xl lg:text-8xl font-black text-white mb-6 tracking-tighter">
                        {albumData.title}
                    </h1>
                    
                    <div className="flex flex-wrap items-center justify-center md:justify-start gap-1 text-sm font-bold text-white/90">
                        <div className="flex items-center gap-2 mr-1 group cursor-pointer">
                            <img src={albumData.artistImage} alt={albumData.artist} className="w-6 h-6 rounded-full border border-white/10" />
                            <span className="hover:underline">{albumData.artist}</span>
                        </div>
                        <span className="mx-1 text-white/60">•</span>
                        <span>{albumData.year}</span>
                        <span className="mx-1 text-white/60">•</span>
                        <span>{albumData.songCount}</span>
                        <span className="mx-1 text-white/60">•</span>
                        <span className="text-white/60 font-medium">{albumData.duration}</span>
                    </div>
                </div>
            </div>

            {/* Content Area */}
            <div className="flex-1 bg-gradient-to-b from-[#121212]/50 via-[#121212] to-black px-6 pb-12">
                {/* Action Bar */}
                <div className="flex items-center gap-8 py-6">
                    <button 
                        className="w-14 h-14 bg-[#1ed760] rounded-full text-black flex items-center justify-center hover:scale-105 active:scale-95 transition-all shadow-xl"
                        title="Play"
                    >
                        <Play size={24} fill="black" className="ml-1" />
                    </button>

                    <button className="text-neutral-400 hover:text-white transition-colors" title="Add to Library">
                        <Heart size={32} />
                    </button>

                    <button className="text-neutral-400 hover:text-white transition-colors border border-neutral-600 rounded-full p-1" title="Download">
                        <Download size={20} />
                    </button>

                    <button className="text-neutral-400 hover:text-white transition-colors" title="More options">
                        <MoreHorizontal size={32} />
                    </button>
                </div>

                {/* Tracklist Table */}
                <div className="mt-4">
                    {/* Header Row */}
                    <div className="grid grid-cols-[16px_1fr_120px] gap-4 px-4 py-2 border-b border-white/10 text-neutral-400 text-xs uppercase font-bold tracking-widest mb-4">
                        <div className="text-center">#</div>
                        <div>Title</div>
                        <div className="flex justify-end"><Clock size={16} /></div>
                    </div>

                    {/* Track Rows */}
                    <div className="flex flex-col gap-1">
                        {albumData.tracks.map((track, index) => (
                            <div 
                                key={track.id}
                                onClick={() => playTrack(track as any)}
                                className="grid grid-cols-[16px_1fr_120px] gap-4 px-4 py-2 hover:bg-white/10 rounded-md group transition-colors cursor-pointer items-center"
                            >
                                <div className="flex items-center justify-center w-4 h-4 text-sm font-medium text-neutral-400">
                                    <span className="group-hover:hidden">{index + 1}</span>
                                    <Play size={14} fill="white" className="hidden group-hover:block text-white" />
                                </div>
                                <div className="flex flex-col min-w-0">
                                    <span className="text-white font-medium truncate">{track.title}</span>
                                    <span className="text-xs text-neutral-400 group-hover:text-white transition-colors truncate">{track.artist}</span>
                                </div>
                                <div className="flex justify-end text-sm text-neutral-400 font-medium">
                                    {track.duration}
                                </div>
                            </div>
                        ))}
                    </div>
                </div>

                {/* More by Artist Section */}
                <div className="mt-16">
                    <div className="flex items-center justify-between mb-6">
                        <h2 className="text-2xl font-bold text-white hover:underline cursor-pointer">
                            More by {albumData.artist}
                        </h2>
                        <Link to="#" className="text-sm font-bold text-neutral-400 hover:text-white hover:underline transition-all">
                            See discography
                        </Link>
                    </div>
                    
                    <PopularAlbums albums={albumData.moreAlbums as any} title="" />
                </div>
            </div>
        </div>
    );
};

export default Album;
