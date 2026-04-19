'use client';

import { useState, useCallback, useEffect, useRef } from 'react';

const HF_BACKEND_URL = process.env.NEXT_PUBLIC_HF_BACKEND_URL || 'https://moeslayer.hf.space';

export interface HFTorrentFile {
  index: number;
  name: string;
  size: number;
}

export interface HFTorrentStatus {
  hash: string;
  ready: boolean;
  downloaded: number;
  total: number;
  progress: number;
  speed: number;
  peers: number;
  seeding: boolean;
}

export interface HFTorrentResult {
  hash: string;
  streamUrl: string;
  files: HFTorrentFile[];
  selectedFile: number;
}

export function useHFTorrent(backendUrl: string = HF_BACKEND_URL) {
  const [status, setStatus] = useState<HFTorrentStatus | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [currentHash, setCurrentHash] = useState<string | null>(null);
  const statusIntervalRef = useRef<NodeJS.Timeout | null>(null);

  const addTorrent = useCallback(async (magnet: string): Promise<HFTorrentResult> => {
    setError(null);
    
    const match = magnet.match(/btih:([a-fA-F0-9]+)/i);
    const hash = match ? match[1].toLowerCase() : '';
    
    if (!hash) {
      throw new Error('Invalid magnet link');
    }

    const addResponse = await fetch(`${backendUrl}/torrent/add`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ magnet }),
    });

    if (!addResponse.ok) {
      const err = await addResponse.json();
      throw new Error(err.error || 'Failed to add torrent');
    }

    const data = await addResponse.json();
    setCurrentHash(data.hash);

    const filesRes = await fetch(`${backendUrl}/torrent/${data.hash}/files`);
    const filesData = await filesRes.json();
    
    const selectedFile = 0;
    const streamUrl = `${backendUrl}/torrent/${data.hash}/stream?file=${selectedFile}`;

    setIsReady(true);
    startStatusPolling(data.hash);

    return {
      hash: data.hash,
      streamUrl,
      files: filesData.files,
      selectedFile,
    };
  }, [backendUrl]);

  const getFiles = useCallback(async (hash: string): Promise<HFTorrentFile[]> => {
    const res = await fetch(`${backendUrl}/torrent/${hash}/files`);
    const data = await res.json();
    return data.files;
  }, [backendUrl]);

  const getStreamUrl = useCallback((hash: string, fileIndex: number = 0): string => {
    return `${backendUrl}/torrent/${hash}/stream?file=${fileIndex}`;
  }, [backendUrl]);

  const getStatus = useCallback(async (hash: string): Promise<HFTorrentStatus> => {
    const res = await fetch(`${backendUrl}/torrent/${hash}/status`);
    const data = await res.json();
    return data;
  }, [backendUrl]);

  const removeTorrent = useCallback(async (hash: string) => {
    await fetch(`${backendUrl}/torrent/${hash}`, { method: 'DELETE' });
    if (statusIntervalRef.current) {
      clearInterval(statusIntervalRef.current);
      statusIntervalRef.current = null;
    }
    setStatus(null);
    setIsReady(false);
    setCurrentHash(null);
  }, [backendUrl]);

  const startStatusPolling = useCallback((hash: string) => {
    if (statusIntervalRef.current) {
      clearInterval(statusIntervalRef.current);
    }

    const poll = async () => {
      try {
        const s = await getStatus(hash);
        setStatus(s);
      } catch (e) {
        console.error('Status polling error:', e);
      }
    };

    poll();
    statusIntervalRef.current = setInterval(poll, 2000);
  }, [getStatus]);

  useEffect(() => {
    return () => {
      if (statusIntervalRef.current) {
        clearInterval(statusIntervalRef.current);
      }
    };
  }, []);

  return {
    addTorrent,
    getFiles,
    getStreamUrl,
    getStatus,
    removeTorrent,
    status,
    isReady,
    error,
    currentHash,
  };
}