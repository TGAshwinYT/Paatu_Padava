export const getValidImage = (song: any) => {
    if (!song) return '/logo.png'; // Use actual default image path

    let img = song.image || song.images || song.thumbnail || song.thumbnails || song.cover_url || song.coverUrl;

    if (img && typeof img === 'string') {
        if (img.includes('placeholder.com')) return '/logo.png';
        if (img.includes(',')) return img.split(',').pop()?.trim() || img;
        return img.replace('150x150', '500x500'); // Force high-res
    }
    if (Array.isArray(img) && img.length > 0) {
        const lastImg = img[img.length - 1];
        if (!lastImg) return '/logo.png';
        if (typeof lastImg === 'string') return lastImg.includes('placeholder.com') ? '/logo.png' : lastImg;
        const resolved = lastImg.link || lastImg.url || '/logo.png';
        return resolved.includes('placeholder.com') ? '/logo.png' : resolved;
    }
    return '/logo.png';
};
