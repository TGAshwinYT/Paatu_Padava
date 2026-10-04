import React, { useState, useCallback, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { Eye, EyeOff, Check, Sparkles, Search as SearchIcon, X, Plus } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { updatePreferences, searchArtists } from '../services/api';
import { useGoogleLogin } from '@react-oauth/google';
import './AuthFlow.css';

// ─── Data ────────────────────────────────────────────────────────────────────

const LANGUAGES = [
  { id: 'tamil',     label: 'Tamil',     emoji: '🎵' },
  { id: 'hindi',     label: 'Hindi',     emoji: '🎶' },
  { id: 'telugu',    label: 'Telugu',    emoji: '🎸' },
  { id: 'kannada',   label: 'Kannada',   emoji: '🥁' },
  { id: 'malayalam', label: 'Malayalam', emoji: '🎷' },
  { id: 'punjabi',   label: 'Punjabi',   emoji: '🎺' },
  { id: 'english',   label: 'English',   emoji: '🎹' },
  { id: 'bengali',   label: 'Bengali',   emoji: '🎻' },
];

const POPULAR_ARTISTS = [
  { id: '1',  name: 'Anirudh Ravichander', imageUrl: 'https://c.saavncdn.com/artists/Anirudh_Ravichander_500x500.jpg' },
  { id: '2',  name: 'A.R. Rahman',         imageUrl: 'https://c.saavncdn.com/artists/A_R_Rahman_500x500.jpg' },
  { id: '3',  name: 'Hiphop Tamizha',      imageUrl: 'https://c.saavncdn.com/artists/Hiphop_Tamizha_500x500.jpg' },
  { id: '4',  name: 'Yuvan Shankar Raja',  imageUrl: 'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_500x500.jpg' },
  { id: '5',  name: 'Harris Jayaraj',      imageUrl: 'https://c.saavncdn.com/artists/Harris_Jayaraj_500x500.jpg' },
  { id: '6',  name: 'Santhosh Narayanan', imageUrl: 'https://c.saavncdn.com/artists/Santhosh_Narayanan_500x500.jpg' },
  { id: '7',  name: 'G. V. Prakash Kumar', imageUrl: 'https://c.saavncdn.com/artists/G_V_Prakash_Kumar_500x500.jpg' },
  { id: '8',  name: 'Sid Sriram',          imageUrl: 'https://c.saavncdn.com/artists/Sid_Sriram_500x500.jpg' },
  { id: '9',  name: 'Shreya Ghoshal',      imageUrl: 'https://c.saavncdn.com/artists/Shreya_Ghoshal_500x500.jpg' },
  { id: '10', name: 'D. Imman',            imageUrl: 'https://c.saavncdn.com/artists/D_Imman_500x500.jpg' },
  { id: '11', name: 'Ilaiyaraaja',         imageUrl: 'https://c.saavncdn.com/artists/Ilaiyaraaja_500x500.jpg' },
  { id: '12', name: 'Vijay Antony',        imageUrl: 'https://c.saavncdn.com/artists/Vijay_Antony_500x500.jpg' },
];

// ─── Simple debounce util (inline to avoid extra import) ─────────────────────
function debounce<T extends (...args: any[]) => void>(fn: T, ms: number) {
  let timer: ReturnType<typeof setTimeout>;
  return (...args: Parameters<T>) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

// ─── Google SVG icon ─────────────────────────────────────────────────────────
const GoogleIcon = () => (
  <svg className="pp-oauth-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
  </svg>
);

// ─── Progress dots ────────────────────────────────────────────────────────────
const ProgressDots: React.FC<{ step: number; total?: number }> = ({ step, total = 4 }) => (
  <div className="pp-progress">
    {Array.from({ length: total }).map((_, i) => (
      <div
        key={i}
        className={`pp-dot ${i + 1 === step ? 'pp-dot-active' : i + 1 < step ? 'pp-dot-done' : ''}`}
      />
    ))}
  </div>
);

// ─── AuthFlow Props ───────────────────────────────────────────────────────────
interface AuthFlowProps {
  /** Called after the full flow completes (step 4 "Let's Go" click) */
  onComplete?: () => void;
  /** Called when the user closes / dismisses the modal */
  onClose?: () => void;
}

// ═══════════════════════════════════════════════════════════════════════════════
// AuthFlow Component
// ═══════════════════════════════════════════════════════════════════════════════
const AuthFlow: React.FC<AuthFlowProps> = ({ onComplete, onClose }) => {
  // ── State Machine ───────────────────────────────────────────────────────────
  const [step,              setStep]              = useState<1 | 2 | 3 | 4>(1);
  const [authMode,          setAuthMode]          = useState<'login' | 'signup'>('login');
  const [selectedLanguages, setSelectedLanguages] = useState<string[]>([]);
  const [selectedArtists,   setSelectedArtists]   = useState<string[]>([]);

  // ── Auth fields ─────────────────────────────────────────────────────────────
  const [email,       setEmail]       = useState('');
  const [password,    setPassword]    = useState('');
  const [username,    setUsername]    = useState('');
  const [showPw,      setShowPw]      = useState(false);
  const [error,       setError]       = useState('');
  const [isLoading,   setIsLoading]   = useState(false);

  // ── Artist search (step 3) ──────────────────────────────────────────────────
  const [artistQuery,    setArtistQuery]    = useState('');
  const [artistResults,  setArtistResults]  = useState<any[]>([]);
  const [isSearching,    setIsSearching]    = useState(false);
  const [customArtists,  setCustomArtists]  = useState<any[]>([]);
  const [isSaving,       setIsSaving]       = useState(false);

  const { login, register, googleLogin } = useAuth();
  const navigate = useNavigate();

  // ── Artist search debounce ──────────────────────────────────────────────────
  const debouncedArtistSearch = useCallback(
    debounce(async (q: string) => {
      if (!q.trim()) { setArtistResults([]); return; }
      setIsSearching(true);
      try {
        const res = await searchArtists(q);
        setArtistResults(res);
      } catch {
        setArtistResults([]);
      } finally {
        setIsSearching(false);
      }
    }, 400),
    []
  );

  useEffect(() => { debouncedArtistSearch(artistQuery); }, [artistQuery]);

  // ─── Helpers ────────────────────────────────────────────────────────────────
  const toggleLanguage = (id: string) => {
    setSelectedLanguages(prev =>
      prev.includes(id) ? prev.filter(l => l !== id) : [...prev, id]
    );
  };

  const toggleArtist = (name: string) => {
    setSelectedArtists(prev =>
      prev.includes(name) ? prev.filter(a => a !== name) : [...prev, name]
    );
  };

  const addFromSearch = (artist: any) => {
    if (!customArtists.find(a => a.name === artist.name)) {
      setCustomArtists(prev => [artist, ...prev]);
    }
    if (!selectedArtists.includes(artist.name)) toggleArtist(artist.name);
    setArtistQuery('');
    setArtistResults([]);
  };

  const allArtists = [...customArtists, ...POPULAR_ARTISTS];

  // ─── Step 1: Email/password submit ─────────────────────────────────────────
  const handleCredentialsSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (password.length < 8) { setError('Password must be at least 8 characters.'); return; }

    setIsLoading(true);
    try {
      if (authMode === 'login') {
        await login(email, password);
      } else {
        if (!username.trim()) { setError('Username is required.'); return; }
        await register(email, password, username);
      }
      setStep(2);
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Something went wrong. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  // ─── Step 1: Google / OAuth ─────────────────────────────────────────────────
  const handleGoogleAuth = useGoogleLogin({
    onSuccess: async (tokenResponse) => {
      setIsLoading(true);
      setError('');
      try {
        await googleLogin(tokenResponse.access_token);
        setStep(2);
      } catch (err: any) {
        setError(err.response?.data?.detail || 'Google sign in failed');
      } finally {
        setIsLoading(false);
      }
    },
    onError: () => setError('Google sign in was unsuccessful')
  });

  // ─── Step 4: Save preferences & finish ─────────────────────────────────────
  const handleFinish = async () => {
    setIsSaving(true);
    try {
      await updatePreferences(selectedArtists);
    } catch {
      // non-blocking — proceed anyway
    } finally {
      setIsSaving(false);
    }
    onComplete ? onComplete() : navigate('/');
  };

  // ─── Wide card on steps 2 & 3 ──────────────────────────────────────────────
  const isWide = step === 2 || step === 3;

  // ═══════════════════════════════════════════════════════════════════════════
  // RENDER
  // ═══════════════════════════════════════════════════════════════════════════
  return (
    <div className="pp-root">
      {/* Animated background orbs */}
      <div className="pp-orbs">
        <div className="pp-orb pp-orb-1" />
        <div className="pp-orb pp-orb-2" />
        <div className="pp-orb pp-orb-3" />
      </div>

      {/* SVG noise texture */}
      <div className="pp-noise" aria-hidden="true" />

      {/* Card */}
      <div
        className={`pp-card${isWide ? ' pp-card-wide' : ''}`}
        key={step}  /* forces re-mount animation on step change */
      >
        {/* Close button (if onClose provided) */}
        {onClose && (
          <button
            onClick={onClose}
            aria-label="Close"
            style={{
              position: 'absolute', top: 16, right: 16,
              background: 'none', border: 'none', cursor: 'pointer',
              color: 'rgba(255,255,255,0.35)', padding: 4, borderRadius: 8,
              transition: 'color 0.15s',
            }}
            onMouseEnter={e => (e.currentTarget.style.color = '#fff')}
            onMouseLeave={e => (e.currentTarget.style.color = 'rgba(255,255,255,0.35)')}
          >
            <X size={20} />
          </button>
        )}

        {/* Logo */}
        <div className="pp-logo">
          <div className="pp-logo-icon">
            <img src="/logo.png" alt="Paatu Paaduva" onError={e => { e.currentTarget.style.display = 'none'; }} />
          </div>
          <span className="pp-logo-name">Paatu Paaduva</span>
        </div>

        {/* Progress dots */}
        <ProgressDots step={step} />

        {/* ── Step content ── */}
        <div className="pp-step-enter">

          {/* ══════════════════════════════════════════════════════════════════
              STEP 1 – Login / Signup
          ══════════════════════════════════════════════════════════════════ */}
          {step === 1 && (
            <>
              {/* Auth mode tabs */}
              <div className="pp-tabs" role="tablist">
                <button
                  role="tab"
                  aria-selected={authMode === 'login'}
                  className={`pp-tab${authMode === 'login' ? ' pp-tab-active' : ''}`}
                  onClick={() => { setAuthMode('login'); setError(''); }}
                >
                  Sign in
                </button>
                <button
                  role="tab"
                  aria-selected={authMode === 'signup'}
                  className={`pp-tab${authMode === 'signup' ? ' pp-tab-active' : ''}`}
                  onClick={() => { setAuthMode('signup'); setError(''); }}
                >
                  Create account
                </button>
              </div>

              <h2 className="pp-heading">
                {authMode === 'login' ? 'Welcome back 👋' : 'Join Paatu Paaduva'}
              </h2>
              <p className="pp-sub">
                {authMode === 'login'
                  ? 'Sign in to continue your music journey.'
                  : 'Create your account and discover music made for you.'}
              </p>

              {/* Error */}
              {error && <div className="pp-error" role="alert">{error}</div>}

              {/* Google OAuth */}
              <div className="pp-oauth-row">
                <button
                  className="pp-oauth-btn"
                  onClick={() => handleGoogleAuth()}
                  disabled={isLoading}
                  id="auth-google-btn"
                >
                  {isLoading
                    ? <span className="pp-spinner" />
                    : <GoogleIcon />
                  }
                  {isLoading ? 'Connecting…' : 'Continue with Google'}
                </button>
              </div>

              {/* Divider */}
              <div className="pp-divider">or</div>

              {/* Email form */}
              <form onSubmit={handleCredentialsSubmit} noValidate>
                {authMode === 'signup' && (
                  <div className="pp-field">
                    <label htmlFor="auth-username" className="pp-label">Username</label>
                    <input
                      id="auth-username"
                      type="text"
                      className="pp-input"
                      placeholder="e.g. music_lover_123"
                      value={username}
                      onChange={e => setUsername(e.target.value)}
                      required
                      autoComplete="username"
                    />
                  </div>
                )}

                <div className="pp-field">
                  <label htmlFor="auth-email" className="pp-label">Email address</label>
                  <input
                    id="auth-email"
                    type="email"
                    className="pp-input"
                    placeholder="name@example.com"
                    value={email}
                    onChange={e => setEmail(e.target.value)}
                    required
                    autoComplete="email"
                  />
                </div>

                <div className="pp-field">
                  <label htmlFor="auth-password" className="pp-label">Password</label>
                  <div className="pp-input-wrap">
                    <input
                      id="auth-password"
                      type={showPw ? 'text' : 'password'}
                      className="pp-input"
                      style={{ paddingRight: '42px' }}
                      placeholder="••••••••"
                      value={password}
                      onChange={e => setPassword(e.target.value)}
                      required
                      autoComplete={authMode === 'login' ? 'current-password' : 'new-password'}
                    />
                    <button
                      type="button"
                      className="pp-input-icon"
                      onClick={() => setShowPw(v => !v)}
                      aria-label={showPw ? 'Hide password' : 'Show password'}
                    >
                      {showPw ? <EyeOff size={16} /> : <Eye size={16} />}
                    </button>
                  </div>
                  {authMode === 'login' && (
                    <div className="pp-forgot">
                      <Link to="/forgot-password">Forgot password?</Link>
                    </div>
                  )}
                </div>

                <button
                  id="auth-submit-btn"
                  type="submit"
                  className="pp-btn-primary"
                  disabled={isLoading}
                >
                  {isLoading
                    ? <><span className="pp-spinner" style={{ marginRight: 8 }} />Processing…</>
                    : authMode === 'login' ? 'Log in' : 'Create account'
                  }
                </button>
              </form>

              <p className="pp-footer-text">
                {authMode === 'login' ? "Don't have an account?" : 'Already have an account?'}
                <button onClick={() => { setAuthMode(authMode === 'login' ? 'signup' : 'login'); setError(''); }}>
                  {authMode === 'login' ? 'Sign up free' : 'Log in'}
                </button>
              </p>
            </>
          )}

          {/* ══════════════════════════════════════════════════════════════════
              STEP 2 – Choose Languages
          ══════════════════════════════════════════════════════════════════ */}
          {step === 2 && (
            <>
              <h2 className="pp-heading">What languages do you love? 🌏</h2>
              <p className="pp-sub">Pick all the languages you enjoy. We'll curate your home feed accordingly.</p>

              <div className="pp-chip-grid">
                {LANGUAGES.map(lang => {
                  const sel = selectedLanguages.includes(lang.id);
                  return (
                    <button
                      key={lang.id}
                      id={`lang-${lang.id}`}
                      className={`pp-chip${sel ? ' pp-chip-sel' : ''}`}
                      onClick={() => toggleLanguage(lang.id)}
                      aria-pressed={sel}
                    >
                      <span className="pp-chip-emoji">{lang.emoji}</span>
                      {lang.label}
                      {sel && <Check size={13} className="pp-chip-check" />}
                    </button>
                  );
                })}
              </div>

              <button
                id="lang-continue-btn"
                className="pp-btn-primary"
                disabled={selectedLanguages.length === 0}
                onClick={() => setStep(3)}
              >
                {selectedLanguages.length === 0
                  ? 'Pick at least one language'
                  : `Continue with ${selectedLanguages.length} ${selectedLanguages.length === 1 ? 'language' : 'languages'} →`
                }
              </button>
            </>
          )}

          {/* ══════════════════════════════════════════════════════════════════
              STEP 3 – Choose Artists
          ══════════════════════════════════════════════════════════════════ */}
          {step === 3 && (
            <>
              <h2 className="pp-heading">
                <Sparkles size={22} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 8, color: '#a855f7' }} />
                Pick your favourite artists
              </h2>
              <p className="pp-sub">Choose at least 3 — we'll build a playlist just for you.</p>

              {/* Counter */}
              <div className="pp-counter">
                <span className="pp-counter-num">{selectedArtists.length}</span>
                <span>of 3 minimum selected</span>
              </div>

              {/* Artist search */}
              <div style={{ position: 'relative', marginBottom: 16 }}>
                <SearchIcon
                  size={16}
                  style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: 'rgba(255,255,255,0.3)', pointerEvents: 'none' }}
                />
                <input
                  id="artist-search-input"
                  type="text"
                  className="pp-input"
                  style={{ paddingLeft: '36px', paddingRight: artistQuery ? '36px' : '12px' }}
                  placeholder="Search more artists…"
                  value={artistQuery}
                  onChange={e => setArtistQuery(e.target.value)}
                />
                {artistQuery && (
                  <button
                    className="pp-input-icon"
                    onClick={() => { setArtistQuery(''); setArtistResults([]); }}
                    aria-label="Clear search"
                  >
                    <X size={14} />
                  </button>
                )}

                {/* Dropdown */}
                {(artistResults.length > 0 || isSearching) && (
                  <div style={{
                    position: 'absolute', top: 'calc(100% + 6px)', left: 0, right: 0,
                    background: 'rgba(18,18,28,0.98)', border: '1px solid rgba(255,255,255,0.1)',
                    borderRadius: 14, overflow: 'hidden', zIndex: 50,
                    boxShadow: '0 16px 48px rgba(0,0,0,0.6)',
                  }}>
                    {isSearching && (
                      <div style={{ padding: '14px', textAlign: 'center', color: 'rgba(255,255,255,0.35)', fontSize: 13 }}>
                        Searching…
                      </div>
                    )}
                    {artistResults.map(a => (
                      <div
                        key={a.id}
                        onClick={() => addFromSearch(a)}
                        style={{
                          display: 'flex', alignItems: 'center', gap: 12,
                          padding: '10px 14px', cursor: 'pointer',
                          borderBottom: '1px solid rgba(255,255,255,0.05)',
                          transition: 'background 0.15s',
                        }}
                        onMouseEnter={e => (e.currentTarget.style.background = 'rgba(168,85,247,0.1)')}
                        onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                      >
                        <img
                          src={a.imageUrl || '/logo.png'}
                          alt={a.name}
                          style={{ width: 36, height: 36, borderRadius: '50%', objectFit: 'cover' }}
                          onError={e => { e.currentTarget.src = '/logo.png'; }}
                        />
                        <span style={{ flex: 1, fontSize: 13, fontWeight: 700, color: '#fff' }}>{a.name}</span>
                        <Plus size={16} style={{ color: '#a855f7' }} />
                      </div>
                    ))}
                  </div>
                )}
              </div>

              {/* Artist grid */}
              <div className="pp-artist-grid">
                {allArtists.map(artist => {
                  const sel = selectedArtists.includes(artist.name);
                  return (
                    <div
                      key={artist.name}
                      id={`artist-${artist.id}`}
                      className="pp-artist"
                      onClick={() => toggleArtist(artist.name)}
                      role="checkbox"
                      aria-checked={sel}
                      tabIndex={0}
                      onKeyDown={e => e.key === 'Enter' && toggleArtist(artist.name)}
                    >
                      <div className={`pp-artist-img-wrap${sel ? ' pp-artist-img-wrap-sel' : ''}`}>
                        <img
                          src={artist.imageUrl}
                          alt={artist.name}
                          className="pp-artist-img"
                          onError={e => { e.currentTarget.src = '/logo.png'; }}
                        />
                        {sel && (
                          <div className="pp-artist-check-overlay">
                            <div className="pp-artist-check-badge">
                              <Check size={14} color="#fff" strokeWidth={3} />
                            </div>
                          </div>
                        )}
                      </div>
                      <span className={`pp-artist-name${sel ? ' pp-artist-name-sel' : ''}`}>
                        {artist.name}
                      </span>
                    </div>
                  );
                })}
              </div>

              <button
                id="build-playlist-btn"
                className="pp-btn-primary"
                disabled={selectedArtists.length < 3}
                onClick={() => setStep(4)}
              >
                {selectedArtists.length < 3
                  ? `Choose ${3 - selectedArtists.length} more artist${3 - selectedArtists.length === 1 ? '' : 's'}`
                  : `Build my playlist →`
                }
              </button>
            </>
          )}

          {/* ══════════════════════════════════════════════════════════════════
              STEP 4 – You're all set!
          ══════════════════════════════════════════════════════════════════ */}
          {step === 4 && (
            <>
              {/* Celebration icon */}
              <div className="pp-success-icon">
                <Sparkles size={34} color="#fff" />
              </div>

              <h2 className="pp-success-heading">You're all set! 🎉</h2>
              <p className="pp-success-sub">
                Your personalised music feed is ready. Here's what we tuned it for:
              </p>

              {/* Tags: languages + artists dynamically rendered */}
              <div className="pp-tags-row">
                {selectedLanguages.map((langId, i) => {
                  const lang = LANGUAGES.find(l => l.id === langId);
                  return (
                    <span
                      key={`lang-${langId}`}
                      className="pp-tag"
                      style={{ animationDelay: `${i * 50}ms` }}
                    >
                      {lang?.emoji} {lang?.label ?? langId}
                    </span>
                  );
                })}
                {selectedArtists.map((name, i) => (
                  <span
                    key={`artist-${name}`}
                    className="pp-tag"
                    style={{ animationDelay: `${(selectedLanguages.length + i) * 50}ms` }}
                  >
                    {name}
                  </span>
                ))}
              </div>

              <button
                id="finish-btn"
                className="pp-btn-primary"
                disabled={isSaving}
                onClick={handleFinish}
              >
                {isSaving
                  ? <><span className="pp-spinner" style={{ marginRight: 8 }} />Crafting your feed…</>
                  : "Let's Go 🚀"
                }
              </button>
            </>
          )}

        </div>{/* /pp-step-enter */}
      </div>{/* /pp-card */}
    </div>
  );
};

export default AuthFlow;
