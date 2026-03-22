import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, Music, Check, Sparkles, X, Plus } from 'lucide-react';
import { updatePreferences, searchArtists } from '../services/api';
import debounce from '../utils/debounce'; // I'll create this utility

const POPULAR_ARTISTS = [
  { id: "1", name: "Anirudh Ravichander", imageUrl: "https://c.saavncdn.com/artists/Anirudh_Ravichander_500x500.jpg" },
  { id: "2", name: "A.R. Rahman", imageUrl: "https://c.saavncdn.com/artists/A_R_Rahman_500x500.jpg" },
  { id: "3", name: "Hiphop Tamizha", imageUrl: "https://c.saavncdn.com/artists/Hiphop_Tamizha_500x500.jpg" },
  { id: "4", name: "Yuvan Shankar Raja", imageUrl: "https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_500x500.jpg" },
  { id: "5", name: "Harris Jayaraj", imageUrl: "https://c.saavncdn.com/artists/Harris_Jayaraj_500x500.jpg" },
  { id: "6", name: "Santhosh Narayanan", imageUrl: "https://c.saavncdn.com/artists/Santhosh_Narayanan_500x500.jpg" },
  { id: "7", name: "G. V. Prakash Kumar", imageUrl: "https://c.saavncdn.com/artists/G_V_Prakash_Kumar_500x500.jpg" },
  { id: "8", name: "Sid Sriram", imageUrl: "https://c.saavncdn.com/artists/Sid_Sriram_500x500.jpg" },
  { id: "9", name: "Shreya Ghoshal", imageUrl: "https://c.saavncdn.com/artists/Shreya_Ghoshal_500x500.jpg" },
  { id: "10", name: "D. Imman", imageUrl: "https://c.saavncdn.com/artists/D_Imman_500x500.jpg" },
  { id: "11", name: "Ilaiyaraaja", imageUrl: "https://c.saavncdn.com/artists/Ilaiyaraaja_500x500.jpg" },
  { id: "12", name: "Vijay Antony", imageUrl: "https://c.saavncdn.com/artists/Vijay_Antony_500x500.jpg" }
];

const Onboarding = () => {
  const [selectedArtists, setSelectedArtists] = useState<string[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [isUpdating, setIsUpdating] = useState(false);
  const [customArtists, setCustomArtists] = useState<any[]>([]);
  const navigate = useNavigate();

  const toggleArtist = (name: string) => {
    setSelectedArtists(prev => 
      prev.includes(name) ? prev.filter(a => a !== name) : [...prev, name]
    );
  };

  const handleSearch = useCallback(
    debounce(async (query: string) => {
      if (!query) {
        setSearchResults([]);
        return;
      }
      setIsSearching(true);
      try {
        const results = await searchArtists(query);
        setSearchResults(results);
      } catch (err) {
        console.error("Artist search failed:", err);
      } finally {
        setIsSearching(false);
      }
    }, 500),
    []
  );

  useEffect(() => {
    handleSearch(searchQuery);
  }, [searchQuery, handleSearch]);

  const addArtistFromSearch = (artist: any) => {
    if (!customArtists.find(a => a.name === artist.name)) {
      setCustomArtists(prev => [artist, ...prev]);
    }
    if (!selectedArtists.includes(artist.name)) {
      toggleArtist(artist.name);
    }
    setSearchQuery('');
    setSearchResults([]);
  };

  const handleFinish = async () => {
    if (selectedArtists.length < 3) return;
    setIsUpdating(true);
    try {
      await updatePreferences(selectedArtists);
      navigate('/');
    } catch (error) {
      alert("Failed to save preferences. Please try again.");
    } finally {
      setIsUpdating(false);
    }
  };

  const allArtistsDisplay = [...customArtists, ...POPULAR_ARTISTS];

  return (
    <div className="min-h-screen bg-black text-white p-6 md:p-12 flex flex-col items-center pb-32">
      <div className="max-w-5xl w-full">
        <header className="text-center mb-10 animate-in fade-in slide-in-from-top-10 duration-700">
           <div className="inline-block p-3 bg-green-500 rounded-2xl mb-6 shadow-[0_0_30px_rgba(34,197,94,0.3)]">
              <Sparkles size={32} className="text-black" />
           </div>
           <h1 className="text-4xl md:text-5xl font-black mb-3 bg-gradient-to-r from-white to-neutral-500 bg-clip-text text-transparent">
             Tailor Your Sound
           </h1>
           <p className="text-lg text-neutral-400">
             Choose at least 3 artists to personalize your experience.
           </p>
        </header>

        {/* Search Bar */}
        <div className="relative max-w-xl mx-auto mb-12 z-50">
          <div className="relative group">
            <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-neutral-500 group-focus-within:text-green-500 transition-colors" size={20} />
            <input 
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search more artists (e.g. Sid Sriram)..."
              className="w-full bg-neutral-900 border border-white/5 rounded-2xl py-4 pl-12 pr-4 text-white focus:ring-2 focus:ring-green-500 outline-none transition-all shadow-xl"
            />
            {searchQuery && (
              <button 
                onClick={() => setSearchQuery('')}
                className="absolute right-4 top-1/2 -translate-y-1/2 text-neutral-500 hover:text-white"
              >
                <X size={18} />
              </button>
            )}
          </div>

          {/* Search Results Dropdown */}
          {searchResults.length > 0 && (
            <div className="absolute top-full left-0 right-0 mt-2 bg-neutral-900 border border-white/10 rounded-2xl shadow-2xl overflow-hidden animate-in fade-in slide-in-from-top-2 duration-200">
              {searchResults.map(artist => (
                <div 
                  key={artist.id}
                  onClick={() => addArtistFromSearch(artist)}
                  className="flex items-center gap-4 p-3 hover:bg-neutral-800 cursor-pointer transition-colors border-b border-white/5 last:border-none"
                >
                  <img src={artist.imageUrl || 'https://www.jiosaavn.com/_i/3.0/artist-default-music.png'} alt={artist.name} className="w-12 h-12 rounded-full object-cover" />
                  <div className="flex-1">
                    <p className="font-bold">{artist.name}</p>
                  </div>
                  <Plus size={18} className="text-green-500" />
                </div>
              ))}
            </div>
          )}
          {isSearching && (
             <div className="absolute top-full left-0 right-0 mt-2 p-4 bg-neutral-900 border border-white/10 rounded-2xl text-center text-neutral-500">
               Searching...
             </div>
          )}
        </div>

        {/* Artist Grid */}
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-6">
            {allArtistsDisplay.map(artist => (
                <div 
                    key={artist.name}
                    onClick={() => toggleArtist(artist.name)}
                    className="flex flex-col items-center gap-3 group cursor-pointer"
                >
                    <div className={`relative aspect-square w-full rounded-full transition-all duration-300 ring-4 ${
                        selectedArtists.includes(artist.name) 
                        ? 'ring-green-500 scale-105 shadow-[0_0_30px_rgba(34,197,94,0.4)]' 
                        : 'ring-transparent group-hover:ring-white/20'
                    }`}>
                        <img 
                          src={artist.imageUrl || 'https://www.jiosaavn.com/_i/3.0/artist-default-music.png'} 
                          alt={artist.name}
                          className="w-full h-full rounded-full object-cover grayscale-[30%] group-hover:grayscale-0 transition-all duration-500"
                        />
                        {selectedArtists.includes(artist.name) && (
                            <div className="absolute inset-0 bg-green-500/20 rounded-full flex items-center justify-center animate-in zoom-in duration-300">
                                <div className="bg-green-500 text-black rounded-full p-2 shadow-xl">
                                  <Check size={20} strokeWidth={4} />
                                </div>
                            </div>
                        )}
                    </div>
                    <span className={`font-bold text-center transition-colors ${selectedArtists.includes(artist.name) ? 'text-green-500' : 'text-neutral-400 group-hover:text-white'}`}>
                      {artist.name}
                    </span>
                </div>
            ))}
        </div>

        {/* Bottom Bar */}
        <div className="fixed bottom-0 left-0 right-0 p-8 flex justify-center bg-gradient-to-t from-black via-black/90 to-transparent z-40">
            <button 
                onClick={handleFinish}
                disabled={selectedArtists.length < 3 || isUpdating}
                className="bg-green-500 text-black text-xl font-black px-16 py-4 rounded-full shadow-[0_10px_40px_rgba(34,197,94,0.3)] hover:scale-105 transition-all active:scale-95 disabled:opacity-20 disabled:scale-100 flex items-center gap-3"
            >
                {isUpdating ? 'Crafting Feed...' : selectedArtists.length < 3 ? `Choose ${3 - selectedArtists.length} More` : "Start Listening"}
            </button>
        </div>
      </div>
    </div>
  );
};

export default Onboarding;
