export const config = {
  hfBackendUrl: process.env.NEXT_PUBLIC_HF_BACKEND_URL || 'https://moeslayer.hf.space',
  useHFTorrent: process.env.NEXT_PUBLIC_USE_HF_TORRENT === 'true',
};