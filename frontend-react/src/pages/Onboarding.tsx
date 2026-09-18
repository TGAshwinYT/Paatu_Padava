import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, Check, Sparkles, X, Plus, Globe, ArrowRight, ArrowLeft } from 'lucide-react';
import { updatePreferences, searchArtists, updatePreferredLanguages } from '../services/api';
import debounce from '../utils/debounce';

const AVAILABLE_LANGUAGES = [
  { id: 'tamil', native: 'தமிழ்', english: 'Tamil' },
  { id: 'english', native: 'English', english: 'English' },
  { id: 'hindi', native: 'हिन्दी', english: 'Hindi' },
  { id: 'telugu', native: 'తెలుగు', english: 'Telugu' },
  { id: 'malayalam', native: 'മലയാളം', english: 'Malayalam' },
  { id: 'kannada', native: 'ಕನ್ನಡ', english: 'Kannada' },
  { id: 'punjabi', native: 'ਪੰਜਾਬੀ', english: 'Punjabi' },
  { id: 'marathi', native: 'मराठी', english: 'Marathi' },
  { id: 'bengali', native: 'বাংলা', english: 'Bengali' },
];

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
  const [step, setStep] = useState<1 | 2>(1);
  const [selectedLanguages, setSelectedLanguages] = useState<string[]>(['tamil', 'english']);
  const [selectedArtists, setSelectedArtists] = useState<string[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [isUpdating, setIsUpdating] = useState(false);
  const [customArtists, setCustomArtists] = useState<any[]>([]);
  const navigate = useNavigate();

  const toggleLanguage = (langId: string) => {
    setSelectedLanguages(prev =>
      prev.includes(langId) ? prev.filter(l => l !== langId) : [...prev, langId]
    );
  };

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
    if (selectedLanguages.length < 1 || selectedArtists.length < 3) return;
    setIsUpdating(true);
    try {
      await Promise.all([
        updatePreferredLanguages(selectedLanguages),
        updatePreferences(selectedArtists)
      ]);
      navigate('/');
    } catch (error) {
      alert("Failed to save preferences. Please try again.");
    } finally {
      setIsUpdating(false);
    }
  };

  const allArtistsDisplay = [...customArtists, ...POPULAR_ARTISTS];

  return (
    <div className="min-h-screen bg-surface-base text-white p-6 md:p-12 flex flex-col items-center pb-36">
      <div className="max-w-5xl w-full">
        {/* Step Indicator */}
        <div className="flex items-center justify-center gap-2 mb-8">
          <button
            onClick={() => setStep(1)}
            className={`flex items-center gap-2 px-4 py-1.5 rounded-full text-xs font-bold transition-all ${
              step === 1 ? 'bg-brand text-black shadow-lg shadow-brand/20' : 'bg-surface-card text-muted hover:text-white'
            }`}
          >
            <span>1. Languages</span>
            {selectedLanguages.length > 0 && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-black/20">{selectedLanguages.length}</span>}
          </button>
          <div className="w-6 h-0.5 bg-neutral-800" />
          <button
            onClick={() => { if (selectedLanguages.length >= 1) setStep(2); }}
            disabled={selectedLanguages.length < 1}
            className={`flex items-center gap-2 px-4 py-1.5 rounded-full text-xs font-bold transition-all disabled:opacity-30 ${
              step === 2 ? 'bg-brand text-black shadow-lg shadow-brand/20' : 'bg-surface-card text-muted hover:text-white'
            }`}
          >
            <span>2. Artists</span>
            {selectedArtists.length > 0 && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-black/20">{selectedArtists.length}</span>}
          </button>
        </div>

        {step === 1 ? (
          /* Step 1: Language Selection */
          <div className="animate-in fade-in slide-in-from-left-4 duration-500">
            <header className="text-center mb-10">
              <div className="inline-block p-3 bg-brand rounded-2xl mb-6 shadow-[0_0_30px_rgba(30,215,96,0.3)]">
                <Globe size={32} className="text-black" />
              </div>
              <h1 className="text-4xl md:text-5xl font-black mb-3 bg-gradient-to-r from-white to-neutral-400 bg-clip-text text-transparent">
                What do you listen to?
              </h1>
              <p className="text-lg text-muted max-w-xl mx-auto">
                Choose at least 1 music language to personalize your feed and search results.
              </p>
            </header>

            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4 max-w-3xl mx-auto mb-12">
              {AVAILABLE_LANGUAGES.map((lang) => {
                const isSelected = selectedLanguages.includes(lang.id);
                return (
                  <div
                    key={lang.id}
                    onClick={() => toggleLanguage(lang.id)}
                    className={`relative p-5 rounded-2xl flex items-center justify-between cursor-pointer transition-all duration-300 ring-2 border ${
                      isSelected
                        ? 'ring-brand bg-brand/10 border-brand/40 scale-[1.02] shadow-[0_0_25px_rgba(30,215,96,0.25)]'
                        : 'ring-transparent bg-surface-card hover:bg-surface border-white/5 text-neutral-300'
                    }`}
                  >
                    <div className="flex flex-col">
                      <span className={`text-xl font-bold tracking-tight ${isSelected ? 'text-white' : 'text-neutral-200'}`}>
                        {lang.native}
                      </span>
                      <span className={`text-sm ${isSelected ? 'text-brand font-medium' : 'text-muted'}`}>
                        {lang.english}
                      </span>
                    </div>
                    {isSelected ? (
                      <div className="bg-brand text-black rounded-full p-1.5 shadow-lg animate-in zoom-in duration-200">
                        <Check size={18} strokeWidth={3.5} />
                      </div>
                    ) : (
                      <div className="w-7 h-7 rounded-full border border-white/10 flex items-center justify-center text-neutral-600">
                        <Plus size={16} />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        ) : (
          /* Step 2: Artist Selection */
          <div className="animate-in fade-in slide-in-from-right-4 duration-500">
            <header className="text-center mb-10">
              <div className="inline-block p-3 bg-brand rounded-2xl mb-6 shadow-[0_0_30px_rgba(30,215,96,0.3)]">
                <Sparkles size={32} className="text-black" />
              </div>
              <h1 className="text-4xl md:text-5xl font-black mb-3 bg-gradient-to-r from-white to-neutral-400 bg-clip-text text-transparent">
                Tailor Your Sound
              </h1>
              <p className="text-lg text-muted">
                Choose at least 3 artists to personalize your experience.
              </p>
            </header>

            {/* Search Bar */}
            <div className="relative max-w-xl mx-auto mb-12 z-50">
              <div className="relative group">
                <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-neutral-500 group-focus-within:text-brand transition-colors" size={20} />
                <input 
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Search more artists (e.g. Sid Sriram)..."
                  className="w-full bg-surface border border-white/5 rounded-2xl py-4 pl-12 pr-4 text-white focus:ring-2 focus:ring-brand outline-none transition-all shadow-xl"
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
                <div className="absolute top-full left-0 right-0 mt-2 bg-surface border border-white/10 rounded-2xl shadow-2xl overflow-hidden animate-in fade-in slide-in-from-top-2 duration-200">
                  {searchResults.map(artist => (
                    <div 
                      key={artist.id}
                      onClick={() => addArtistFromSearch(artist)}
                      className="flex items-center gap-4 p-3 hover:bg-surface-hover cursor-pointer transition-colors border-b border-white/5 last:border-none"
                    >
                      <img src={artist.imageUrl || 'https://www.jiosaavn.com/_i/3.0/artist-default-music.png'} alt={artist.name} className="w-12 h-12 rounded-full object-cover" />
                      <div className="flex-1">
                        <p className="font-bold">{artist.name}</p>
                      </div>
                      <Plus size={18} className="text-brand" />
                    </div>
                  ))}
                </div>
              )}
              {isSearching && (
                <div className="absolute top-full left-0 right-0 mt-2 p-4 bg-surface border border-white/10 rounded-2xl text-center text-muted">
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
                      ? 'ring-brand scale-105 shadow-[0_0_30px_rgba(30,215,96,0.4)]' 
                      : 'ring-transparent group-hover:ring-white/20'
                  }`}>
                    <img 
                      src={artist.imageUrl || 'https://www.jiosaavn.com/_i/3.0/artist-default-music.png'} 
                      alt={artist.name} 
                      className="w-full h-full rounded-full object-cover grayscale-[30%] group-hover:grayscale-0 transition-all duration-500"
                    />
                    {selectedArtists.includes(artist.name) && (
                      <div className="absolute inset-0 bg-brand/20 rounded-full flex items-center justify-center animate-in zoom-in duration-300">
                        <div className="bg-brand text-black rounded-full p-2 shadow-xl">
                          <Check size={20} strokeWidth={4} />
                        </div>
                      </div>
                    )}
                  </div>
                  <span className={`font-bold text-center transition-colors ${selectedArtists.includes(artist.name) ? 'text-brand' : 'text-muted group-hover:text-white'}`}>
                    {artist.name}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Bottom Action Bar */}
        <div className="fixed bottom-0 left-0 right-0 p-6 flex items-center justify-center gap-4 bg-gradient-to-t from-surface-base via-surface-base/95 to-transparent z-40 backdrop-blur-md">
          {step === 2 && (
            <button
              onClick={() => setStep(1)}
              className="bg-surface hover:bg-surface-hover text-white font-bold px-6 py-4 rounded-full transition-all flex items-center gap-2 border border-white/10"
            >
              <ArrowLeft size={18} />
              <span>Back</span>
            </button>
          )}

          {step === 1 ? (
            <button 
              onClick={() => {
                if (selectedLanguages.length >= 1) {
                  setStep(2);
                  window.scrollTo({ top: 0, behavior: 'smooth' });
                }
              }}
              disabled={selectedLanguages.length < 1}
              className="bg-brand text-black text-lg font-black px-12 py-4 rounded-full shadow-[0_10px_40px_rgba(30,215,96,0.3)] hover:scale-105 transition-all active:scale-95 disabled:opacity-25 disabled:scale-100 flex items-center gap-3"
            >
              <span>Next: Choose Artists</span>
              <ArrowRight size={20} />
            </button>
          ) : (
            <button 
              onClick={handleFinish}
              disabled={selectedArtists.length < 3 || isUpdating}
              className="bg-brand text-black text-lg font-black px-12 py-4 rounded-full shadow-[0_10px_40px_rgba(30,215,96,0.3)] hover:scale-105 transition-all active:scale-95 disabled:opacity-25 disabled:scale-100 flex items-center gap-3"
            >
              {isUpdating ? 'Crafting Feed...' : selectedArtists.length < 3 ? `Choose ${3 - selectedArtists.length} More Artists` : "Start Listening"}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

export default Onboarding;

