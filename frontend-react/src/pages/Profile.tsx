import { useState, useEffect } from 'react';
import { User as UserIcon, Search, X, Plus } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import HomeSection from '../components/HomeSection';
import { getFollowedArtists, searchArtists, followArtist, unfollowArtist } from '../services/api';
import { useNavigate } from 'react-router-dom';

const Profile = () => {
    const { user } = useAuth();
    const [followedArtists, setFollowedArtists] = useState<any[]>([]);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [searchQuery, setSearchQuery] = useState('');
    const [searchResults, setSearchResults] = useState<any[]>([]);
    const [isSearching, setIsSearching] = useState(false);
    const navigate = useNavigate();

    useEffect(() => {
        if (user) {
            fetchFollowed();
        }
    }, [user]);

    const fetchFollowed = async () => {
        const data = await getFollowedArtists();
        setFollowedArtists(data);
    };

    // Debounced artist search
    useEffect(() => {
        const timer = setTimeout(async () => {
            if (searchQuery.trim().length > 1) {
                setIsSearching(true);
                const results = await searchArtists(searchQuery);
                setSearchResults(results);
                setIsSearching(false);
            } else {
                setSearchResults([]);
            }
        }, 300);
        return () => clearTimeout(timer);
    }, [searchQuery]);

    const handleFollow = async (artist: any) => {
        try {
            await followArtist({
                id: artist.id,
                name: artist.name,
                imageUrl: artist.imageUrl || artist.image?.[0]?.url
            });
            fetchFollowed();
        } catch (err) {
            console.error("Follow error:", err);
        }
    };

    const handleUnfollow = async (artistId: string) => {
        try {
            await unfollowArtist(artistId);
            fetchFollowed();
        } catch (err) {
            console.error("Unfollow error:", err);
        }
    };

    if (!user) {
        return (
            <div className="flex flex-col items-center justify-center min-h-[60vh] gap-6">
                <div className="w-20 h-20 rounded-full bg-neutral-800 flex items-center justify-center">
                    <UserIcon size={40} className="text-neutral-500" />
                </div>
                <h2 className="text-2xl font-bold">Please log in to view your profile</h2>
                <button 
                    onClick={() => navigate('/login')}
                    className="bg-white text-black px-8 py-3 rounded-full font-bold hover:scale-105 transition-all"
                >
                    Log in
                </button>
            </div>
        );
    }

    return (
        <div className="flex flex-col gap-12 pb-24">
            {/* Massive Header */}
            <div className="flex flex-col md:flex-row items-center md:items-end gap-8 pt-6">
                <div className="w-48 h-48 md:w-64 md:h-64 rounded-full bg-neutral-800 shadow-2xl flex items-center justify-center overflow-hidden border-4 border-neutral-700">
                    <UserIcon size={100} className="text-neutral-600" />
                </div>
                <div className="flex flex-col items-center md:items-start">
                    <span className="text-xs uppercase font-bold tracking-widest text-neutral-400 mb-2">Profile</span>
                    <h1 className="text-5xl md:text-8xl font-black text-white tracking-tighter">
                        {user.username}
                    </h1>
                    <div className="flex items-center gap-4 mt-6">
                        <span className="text-sm font-medium text-neutral-400">{followedArtists.length} Following</span>
                        <div className="w-1 h-1 rounded-full bg-neutral-600" />
                        <span className="text-sm font-medium text-neutral-400">Premium Member</span>
                    </div>
                </div>
            </div>

            {/* Sections */}
            <div className="flex flex-col gap-12 mt-8">
                {/* Top Artists (Proxy using first 6 followed) */}
                {followedArtists.length > 0 && (
                    <HomeSection title="Top artists this month">
                        <div className="flex overflow-x-auto gap-6 pb-4 scrollbar-hide">
                            {followedArtists.slice(0, 6).map((artist) => (
                                <div key={artist.id} className="flex flex-col items-center gap-3 min-w-[140px] group cursor-pointer">
                                    <div className="w-32 h-32 rounded-full overflow-hidden shadow-lg group-hover:shadow-2xl transition-all duration-300 transform group-hover:scale-105">
                                        <img 
                                            src={artist.imageUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop'} 
                                            className="w-full h-full object-cover"
                                            alt={artist.name}
                                        />
                                    </div>
                                    <span className="text-sm font-bold text-white text-center truncate w-full">{artist.name}</span>
                                    <span className="text-xs text-neutral-400">Artist</span>
                                </div>
                            ))}
                        </div>
                    </HomeSection>
                )}

                {/* Following Section */}
                <HomeSection 
                    title="Following" 
                    rightElement={
                        <button 
                            onClick={() => setIsModalOpen(true)}
                            className="text-xs uppercase font-bold tracking-widest text-neutral-400 hover:text-white transition-colors"
                        >
                            Edit Preferences
                        </button>
                    }
                >
                    {followedArtists.length > 0 ? (
                         <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-6">
                            {followedArtists.map((artist) => (
                                <div key={artist.id} className="bg-[#181818] p-5 rounded-xl hover:bg-[#282828] transition-all group relative">
                                    <div className="w-full aspect-square rounded-full overflow-hidden mb-4 shadow-lg">
                                        <img 
                                            src={artist.imageUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200&h=200&fit=crop'} 
                                            className="w-full h-full object-cover"
                                            alt={artist.name}
                                        />
                                    </div>
                                    <p className="text-sm font-bold text-white truncate">{artist.name}</p>
                                    <p className="text-xs text-neutral-400 mt-1 uppercase tracking-tighter font-semibold">Artist</p>
                                </div>
                            ))}
                        </div>
                    ) : (
                        <div className="flex flex-col items-center justify-center p-12 bg-neutral-900/50 rounded-2xl border border-white/5 gap-4">
                            <p className="text-neutral-400 font-medium">You aren't following any artists yet.</p>
                            <button 
                                onClick={() => setIsModalOpen(true)}
                                className="flex items-center gap-2 bg-white text-black px-6 py-2 rounded-full font-bold text-sm hover:scale-105 transition-all"
                            >
                                <Plus size={16} />
                                Find more artists
                            </button>
                        </div>
                    )}
                </HomeSection>
            </div>

            {/* Edit Preferences Modal */}
            {isModalOpen && (
                <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-in fade-in duration-300">
                    <div className="bg-[#181818] w-full max-w-2xl rounded-2xl shadow-2xl border border-white/10 flex flex-col max-h-[80vh] overflow-hidden">
                        {/* Modal Header */}
                        <div className="p-6 border-b border-white/5 flex items-center justify-between">
                            <h2 className="text-2xl font-black text-white">Find Artists</h2>
                            <button onClick={() => setIsModalOpen(false)} className="text-neutral-400 hover:text-white transition-colors">
                                <X size={24} />
                            </button>
                        </div>

                        {/* Search Bar */}
                        <div className="p-6 bg-black/20">
                            <div className="relative">
                                <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-neutral-500" size={20} />
                                <input 
                                    autoFocus
                                    type="text" 
                                    value={searchQuery}
                                    onChange={(e) => setSearchQuery(e.target.value)}
                                    placeholder="Search for an artist..."
                                    className="w-full bg-neutral-800 text-white rounded-xl py-3.5 pl-12 pr-4 focus:outline-none focus:ring-2 focus:ring-white/10 transition-all font-medium"
                                />
                            </div>
                        </div>

                        {/* Search Results / Following List */}
                        <div className="flex-1 overflow-y-auto p-6 space-y-6">
                            {searchQuery.trim().length > 0 ? (
                                <div className="space-y-4">
                                    <h3 className="text-xs uppercase font-bold text-neutral-500 tracking-wider">Search Results</h3>
                                    {isSearching ? (
                                        <div className="flex items-center justify-center py-8">
                                            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white"></div>
                                        </div>
                                    ) : searchResults.length > 0 ? (
                                        <div className="grid grid-cols-1 gap-2">
                                            {searchResults.map((artist) => (
                                                <div key={artist.id} className="flex items-center justify-between p-3 hover:bg-white/5 rounded-xl transition-colors group">
                                                    <div className="flex items-center gap-4">
                                                        <img 
                                                            src={artist.imageUrl || artist.image?.[0]?.url || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=50&h=50&fit=crop'} 
                                                            className="w-12 h-12 rounded-full object-cover shadow-md"
                                                            alt={artist.name}
                                                        />
                                                        <span className="font-bold text-white">{artist.name}</span>
                                                    </div>
                                                    <button 
                                                        onClick={() => handleFollow(artist)}
                                                        className="px-4 py-1.5 rounded-full border border-neutral-600 font-bold hover:border-white transition-all text-sm group-active:scale-95"
                                                    >
                                                        {followedArtists.some(f => f.id === artist.id) ? 'Following' : 'Follow'}
                                                    </button>
                                                </div>
                                            ))}
                                        </div>
                                    ) : (
                                        <p className="text-center text-neutral-500 py-8">No artists found for "{searchQuery}"</p>
                                    )}
                                </div>
                            ) : (
                                <div className="space-y-4">
                                    <div className="flex items-center justify-between">
                                        <h3 className="text-xs uppercase font-bold text-neutral-500 tracking-wider">Current Following</h3>
                                        <span className="text-xs text-neutral-500">{followedArtists.length} Artists</span>
                                    </div>
                                    <div className="grid grid-cols-1 gap-2">
                                        {followedArtists.map((artist) => (
                                            <div key={artist.id} className="flex items-center justify-between p-3 bg-white/5 rounded-xl transition-colors">
                                                <div className="flex items-center gap-4">
                                                    <img 
                                                        src={artist.imageUrl || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=50&h=50&fit=crop'} 
                                                        className="w-12 h-12 rounded-full object-cover shadow-md"
                                                        alt={artist.name}
                                                    />
                                                    <span className="font-bold text-white">{artist.name}</span>
                                                </div>
                                                <button 
                                                    onClick={() => handleUnfollow(artist.id)}
                                                    className="p-2 text-neutral-400 hover:text-red-500 hover:bg-red-500/10 rounded-full transition-all"
                                                >
                                                    <X size={20} />
                                                </button>
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            )}
                        </div>

                        {/* Modal Footer */}
                        <div className="p-6 border-t border-white/5 bg-black/20 flex justify-end">
                            <button 
                                onClick={() => setIsModalOpen(false)}
                                className="bg-white text-black px-8 py-2.5 rounded-full font-bold hover:scale-105 transition-all text-sm"
                            >
                                Done
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default Profile;
