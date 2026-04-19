'use client';

import { Suspense, useState, useEffect, useCallback, useRef } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { ArrowLeft } from 'lucide-react';
import VideoPlayer from '@/components/VideoPlayer';
import { config } from '@/lib/config';

const HF_BACKEND_URL = config.hfBackendUrl;

interface TorrentFile {
  index: number;
  name: string;
  size: number;
}

function LoadingFallback() {
  return (
    <div className="min-h-screen bg-black flex items-center justify-center">
      <div className="flex flex-col items-center gap-4">
        <div className="w-16 h-16 border-4 border-[var(--primary)] border-t-transparent rounded-full animate-spin" />
        <p className="text-white/80">Loading...</p>
      </div>
    </div>
  );
}

function WatchContent() {
  const searchParams = useSearchParams();
  const router = useRouter();
  
  const magnet = searchParams.get('magnet') || '';
  const title = searchParams.get('title') || 'Unknown';

  const [streamUrl, setStreamUrl] = useState<string | null>(null);
  const [files, setFiles] = useState<TorrentFile[]>([]);
  const [selectedFile, setSelectedFile] = useState(0);
  const [hash, setHash] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [useBackend, setUseBackend] = useState(true);
  const [debugInfo, setDebugInfo] = useState<string[]>([]);
  const [progress, setProgress] = useState({ downloaded: 0, total: 0, percent: 0, speed: 0, peers: 0 });

  const addDebug = useCallback((msg: string) => {
    console.log(`[HFBackend] ${msg}`);
    setDebugInfo(prev => [...prev.slice(-20), `[${new Date().toISOString().slice(11,19)}] ${msg}`]);
  }, []);

  const pollStatus = useCallback(async (h: string) => {
    try {
      const res = await fetch(`${HF_BACKEND_URL}/torrent/${h}/status`);
      const data = await res.json();
      setProgress({
        downloaded: data.downloaded || 0,
        total: data.total || 0,
        percent: data.progress || 0,
        speed: data.speed || 0,
        peers: data.peers || 0,
      });
    } catch (e) {
      console.error('Status poll error:', e);
    }
  }, []);

  useEffect(() => {
    if (!magnet) {
      addDebug('No magnet link provided');
      setLoading(false);
      return;
    }

    const initBackend = async () => {
      addDebug(`Using HF Backend: ${HF_BACKEND_URL}`);

      try {
        addDebug('Adding torrent...');
        const match = magnet.match(/btih:([a-fA-F0-9]+)/i);
        if (!match) {
          throw new Error('Invalid magnet hash');
        }
        const hash = match[1].toLowerCase();
        setHash(hash);

        const addRes = await fetch(`${HF_BACKEND_URL}/torrent/add`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ magnet }),
        });

        if (!addRes.ok) {
          const err = await addRes.json();
          throw new Error(err.error || 'Failed to add torrent');
        }

        addDebug(`Torrent added: ${hash}`);

        let attempts = 0;
        const maxAttempts = 30;
        
        const checkFiles = async () => {
          attempts++;
          try {
            const filesRes = await fetch(`${HF_BACKEND_URL}/torrent/${hash}/files`);
            if (!filesRes.ok) throw new Error('Not ready');
            const filesData = await filesRes.json();
            setFiles(filesData.files);
            addDebug(`Ready! ${filesData.files.length} files`);
            
            const defaultFile = filesData.files.find((f: TorrentFile) => 
              f.name.match(/\.(mp4|mkv|avi|mov|webm|m4v)$/i)
            ) || filesData.files[0];
            
            const fileIndex = defaultFile?.index || 0;
            setSelectedFile(fileIndex);
            setStreamUrl(`${HF_BACKEND_URL}/torrent/${hash}/stream?file=${fileIndex}`);
            setLoading(false);
          } catch (e) {
            if (attempts < maxAttempts) {
              addDebug(`Waiting for torrent... (${attempts}/${maxAttempts})`);
              setTimeout(checkFiles, 2000);
            } else {
              throw new Error('Timeout waiting for torrent');
            }
          }
        };

        pollStatus(hash);
        const statusInterval = setInterval(() => pollStatus(hash), 2000);
        checkFiles();

        return () => clearInterval(statusInterval);
      } catch (e: any) {
        addDebug(`Error: ${e.message}`);
        setError(e.message);
        setLoading(false);
        setUseBackend(false);
      }
    };

    initBackend();
  }, [magnet, addDebug, pollStatus, HF_BACKEND_URL]);

  const handleFileChange = useCallback(async (fileIndex: number) => {
    if (!hash) return;
    setSelectedFile(fileIndex);
    setStreamUrl(`${HF_BACKEND_URL}/torrent/${hash}/stream?file=${fileIndex}`);
  }, [hash, HF_BACKEND_URL]);

  const handleBack = useCallback(() => {
    router.back();
  }, [router]);

  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  };

  if (!magnet) {
    return (
      <div className="min-h-screen bg-black flex flex-col items-center justify-center p-4">
        <p className="text-red-400 text-lg mb-4">No magnet link provided</p>
        <button onClick={handleBack} className="px-6 py-3 bg-[var(--primary)] rounded-lg text-white">
          Go Back
        </button>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-black flex flex-col items-center justify-center">
        <div className="w-16 h-16 border-4 border-[var(--primary)] border-t-transparent rounded-full animate-spin mb-4" />
        <p className="text-white/80 mb-2">Connecting to torrent network...</p>
        {progress.percent > 0 && (
          <div className="text-white/60 text-sm">
            <p>{formatBytes(progress.downloaded)} / {formatBytes(progress.total)} ({progress.percent.toFixed(1)}%)</p>
            <p>{progress.peers} peers · {formatBytes(progress.speed)}/s</p>
          </div>
        )}
        <div className="mt-4 w-64 h-2 bg-gray-800 rounded-full overflow-hidden">
          <div 
            className="h-full bg-[var(--primary)] transition-all" 
            style={{ width: `${Math.min(progress.percent, 100)}%` }} 
          />
        </div>
        {debugInfo.length > 0 && (
          <div className="mt-4 p-2 bg-black/80 rounded text-xs font-mono max-w-xs max-h-24 overflow-auto">
            {debugInfo.slice(-4).map((msg, i) => (
              <div key={i} className="text-green-400">{msg}</div>
            ))}
          </div>
        )}
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-black flex flex-col items-center justify-center p-4">
        <p className="text-red-400 text-lg mb-4">{error}</p>
        <button onClick={handleBack} className="px-6 py-3 bg-[var(--primary)] rounded-lg text-white">
          Go Back
        </button>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-black flex flex-col">
      <div className="relative h-[80vh]">
        <button
          onClick={handleBack}
          className="absolute top-4 left-4 z-50 p-3 rounded-full bg-black/50 backdrop-blur-md hover:bg-black/70"
        >
          <ArrowLeft size={20} className="text-white" />
        </button>

        <div className="absolute top-4 left-1/2 -translate-x-1/2 z-40 px-4 py-2 bg-black/50 backdrop-blur-md rounded-lg max-w-md">
          <h1 className="text-white text-lg font-medium truncate">{title}</h1>
        </div>

        {streamUrl && (
          <VideoPlayer src={streamUrl} />
        )}
      </div>

      <div className="flex-1 p-4 bg-gray-900">
        <h2 className="text-white text-lg font-medium mb-3">Files</h2>
        <div className="space-y-1 max-h-40 overflow-auto">
          {files.map((file) => (
            <button
              key={file.index}
              onClick={() => handleFileChange(file.index)}
              className={`w-full text-left px-3 py-2 rounded ${
                selectedFile === file.index 
                  ? 'bg-[var(--primary)] text-white' 
                  : 'bg-gray-800 text-gray-300 hover:bg-gray-700'
              }`}
            >
              <div className="text-sm truncate">{file.name}</div>
              <div className="text-xs opacity-70">{formatBytes(file.size)}</div>
            </button>
          ))}
        </div>
      </div>

      {debugInfo.length > 0 && (
        <div className="fixed bottom-4 right-4 max-w-xs max-h-24 overflow-auto bg-black/80 p-2 rounded text-xs font-mono">
          {debugInfo.slice(-4).map((msg, i) => (
            <div key={i} className="text-green-400">{msg}</div>
          ))}
        </div>
      )}
    </div>
  );
}

export default function WatchPage() {
  return (
    <Suspense fallback={<LoadingFallback />}>
      <WatchContent />
    </Suspense>
  );
}