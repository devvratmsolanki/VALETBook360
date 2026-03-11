import { supabase } from '../lib/supabase';

const BUCKET = 'parking-photos';

/**
 * Upload a single photo to Supabase Storage.
 * @param {File} file - The image file to upload.
 * @param {string} txId - Transaction ID (used for path grouping).
 * @param {string} prefix - 'checkin' | 'parking' to separate operator vs driver photos.
 * @returns {string} The public URL of the uploaded file.
 */
export const uploadPhoto = async (file, txId, prefix = 'checkin') => {
    const ext = file.name?.split('.').pop() || 'jpg';
    const fileName = `${prefix}/${txId}/${Date.now()}_${Math.random().toString(36).slice(2, 8)}.${ext}`;

    const { error } = await supabase.storage.from(BUCKET).upload(fileName, file, {
        cacheControl: '3600',
        upsert: false,
    });
    if (error) throw error;

    const { data } = supabase.storage.from(BUCKET).getPublicUrl(fileName);
    return data.publicUrl;
};

/**
 * Upload multiple photos and return an array of public URLs.
 */
export const uploadMultiplePhotos = async (files, txId, prefix = 'checkin') => {
    const urls = await Promise.all(
        files.map((file) => uploadPhoto(file, txId, prefix))
    );
    return urls;
};
