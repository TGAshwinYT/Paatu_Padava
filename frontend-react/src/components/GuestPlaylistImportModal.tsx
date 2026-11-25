import React from 'react';
import { FolderSync } from 'lucide-react';

interface GuestPlaylistImportModalProps {
  isOpen: boolean;
  count: number;
  isBusy: boolean;
  onApprove: () => void;
  onDecline: () => void;
}

const GuestPlaylistImportModal: React.FC<GuestPlaylistImportModalProps> = ({
  isOpen,
  count,
  isBusy,
  onApprove,
  onDecline,
}) => {
  if (!isOpen || count <= 0) return null;
  const label = count === 1 ? 'playlist' : 'playlists';

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/75 backdrop-blur-sm p-4">
      <div className="w-full max-w-md rounded-2xl bg-neutral-900 border border-white/10 p-6 shadow-2xl">
        <div className="flex items-center gap-3 mb-3">
          <div className="p-2.5 rounded-xl bg-purple-600/20 text-purple-400">
            <FolderSync size={22} />
          </div>
          <h3 className="text-lg font-bold text-white">Import Guest Playlists?</h3>
        </div>
        <p className="text-sm text-neutral-300 leading-relaxed mb-6">
          You have {count} Guest {label} on this device. Would you like to import them into your account?
        </p>
        <div className="flex justify-end gap-3">
          <button
            type="button"
            disabled={isBusy}
            onClick={onDecline}
            className="px-4 py-2 rounded-xl text-sm font-semibold text-neutral-300 hover:text-white hover:bg-white/10 transition-colors disabled:opacity-50"
          >
            Keep Local Only
          </button>
          <button
            type="button"
            disabled={isBusy}
            onClick={onApprove}
            className="px-4 py-2 rounded-xl text-sm font-semibold bg-purple-600 hover:bg-purple-500 text-white transition-colors disabled:opacity-50"
          >
            {isBusy ? 'Importing...' : 'Import to Account'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default GuestPlaylistImportModal;
