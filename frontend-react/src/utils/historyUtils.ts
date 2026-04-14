export interface Collection {
  id: string;
  title: string;
  coverUrl: string;
  type: 'album' | 'playlist' | 'mix';
}

const STORAGE_KEY = 'paatu_paaduva_recent_collections';

export const saveCollectionPlay = (collection: Collection) => {
  try {
    const existing = localStorage.getItem(STORAGE_KEY);
    let collections: Collection[] = existing ? JSON.parse(existing) : [];

    // Remove duplicates
    collections = collections.filter(c => c.id !== collection.id);

    // Add to front
    collections.unshift(collection);

    // Keep only last 8
    collections = collections.slice(0, 8);

    localStorage.setItem(STORAGE_KEY, JSON.stringify(collections));
  } catch (error) {
    console.error('Error saving collection play:', error);
  }
};

export const getRecentCollections = (): Collection[] => {
  try {
    const existing = localStorage.getItem(STORAGE_KEY);
    return existing ? JSON.parse(existing) : [];
  } catch (error) {
    console.error('Error getting recent collections:', error);
    return [];
  }
};
