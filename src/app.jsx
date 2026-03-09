import React, { useEffect, useMemo, useRef, useState } from 'react';
import './app.css';

const DOWNLOAD_PATH = '~/Downloads/B-Roll';
const COMPLETE_SOUND_URL = 'https://www.trekcore.com/audio/computer/computerbeep_43.mp3';
const PROJECT_MEMORY_KEY = 'broll-project-name-memory-v1';
const PROJECT_MEMORY_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_PROJECT_MEMORY_ITEMS = 8;
const MAX_CONCURRENT_DOWNLOADS = 3;
const TIME_RE = /^\d{2}:\d{2}:\d{2}$/;
const DOWNLOAD_PROGRESS_MIN = 8;
const DOWNLOAD_PROGRESS_MAX = 86;
const CONVERT_PROGRESS_MIN = 90;
const ACTIVE_STATUSES = new Set(['Queued', 'Downloading', 'Converting']);
const CANCELABLE_STATUSES = new Set(['Queued', 'Downloading', 'Converting']);
const FAILED_STATUSES = new Set(['Aborted', 'Failed', 'Error']);
const YOUTUBE_HOSTS = new Set([
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
  'www.youtu.be',
  'youtube-nocookie.com',
  'www.youtube-nocookie.com',
]);

const cn = (...parts) => parts.filter(Boolean).join(' ');

function parseClipTime(value) {
  if (!TIME_RE.test(value)) return null;
  const [hours, minutes, seconds] = value.split(':').map(Number);
  return minutes > 59 || seconds > 59 ? null : hours * 3600 + minutes * 60 + seconds;
}

function clamp(value, min = 0, max = 100) {
  return Math.max(min, Math.min(max, value));
}

function hashString(value) {
  let hash = 0;
  for (let i = 0; i < value.length; i += 1) hash = (hash * 31 + value.charCodeAt(i)) >>> 0;
  return hash;
}

function sanitizeProjectMemory(rawValue) {
  const now = Date.now();
  if (!Array.isArray(rawValue)) return [];
  return rawValue
    .filter((entry) => entry && typeof entry.name === 'string' && typeof entry.lastUsedAt === 'number')
    .map((entry) => ({ name: entry.name.trim(), lastUsedAt: entry.lastUsedAt }))
    .filter((entry) => entry.name && now - entry.lastUsedAt <= PROJECT_MEMORY_WINDOW_MS)
    .sort((a, b) => b.lastUsedAt - a.lastUsedAt)
    .slice(0, MAX_PROJECT_MEMORY_ITEMS);
}

function persistProjectMemory(items) {
  if (typeof window === 'undefined') return;
  if (!items.length) {
    window.localStorage.removeItem(PROJECT_MEMORY_KEY);
    return;
  }
  window.localStorage.setItem(PROJECT_MEMORY_KEY, JSON.stringify(items));
}

function loadProjectMemory() {
  if (typeof window === 'undefined') return [];
  try {
    const parsed = JSON.parse(window.localStorage.getItem(PROJECT_MEMORY_KEY) ?? '[]');
    const cleaned = sanitizeProjectMemory(parsed);
    persistProjectMemory(cleaned);
    return cleaned;
  } catch {
    window.localStorage.removeItem(PROJECT_MEMORY_KEY);
    return [];
  }
}

function normalizeYoutubeUrl(rawUrl) {
  const trimmed = rawUrl.trim();
  if (!trimmed) return null;
  try {
    const parsed = new URL(/^[a-z][a-z0-9+.-]*:/i.test(trimmed) ? trimmed : `https://${trimmed}`);
    if (!YOUTUBE_HOSTS.has(parsed.hostname.toLowerCase())) return null;
    parsed.hash = '';
    return parsed.toString();
  } catch {
    return null;
  }
}

function extractVideoId(url) {
  try {
    const parsed = new URL(url);
    if (parsed.hostname.toLowerCase().includes('youtu.be')) {
      return parsed.pathname.split('/').filter(Boolean)[0] || 'unknown';
    }
    if (parsed.searchParams.get('v')) return parsed.searchParams.get('v');
    const parts = parsed.pathname.split('/').filter(Boolean);
    const i = parts.findIndex((part) => ['shorts', 'embed', 'live', 'v'].includes(part));
    return (i !== -1 && parts[i + 1]) || parts.at(-1) || 'unknown';
  } catch {
    return 'unknown';
  }
}

function getMockYoutubeTitle(url) {
  const id = extractVideoId(url);
  if (url.includes('shorts')) return `YouTube Shorts clip ${id} with vertical b-roll and natural audio`;
  if (url.includes('live')) return `Live stream archive segment ${id} from official channel coverage`;
  if (url.includes('embed')) return `Embedded video source ${id} pulled into the archive workflow`;
  if (url.includes('playlist=')) return `Playlist-linked video ${id} resolved from YouTube watch URL`;
  return `Resolved YouTube video title for ${id} that may be long enough to need truncation`;
}

function getMockEstimatedSizeMb(url) {
  const base = 40 + (hashString(extractVideoId(url)) % 260);
  if (url.includes('shorts')) return 18 + base * 0.22;
  if (url.includes('live')) return 260 + base * 1.45;
  if (url.includes('playlist=')) return 110 + base * 0.8;
  return 55 + base * 0.65;
}

function getMockDurations(sizeMb) {
  return {
    downloadDurationMs: Math.round(900 + sizeMb * 10),
    convertDurationMs: Math.round(500 + sizeMb * 4.5),
  };
}

function analyzeUrls(rawText) {
  const seen = new Set();
  const validUrls = [];
  let invalidCount = 0;
  let duplicateCount = 0;

  for (const raw of rawText.split('\n').map((line) => line.trim()).filter(Boolean)) {
    const normalized = normalizeYoutubeUrl(raw);
    if (!normalized) {
      invalidCount += 1;
      continue;
    }
    if (seen.has(normalized)) {
      duplicateCount += 1;
      continue;
    }
    seen.add(normalized);
    validUrls.push(normalized);
  }

  return { validUrls, invalidCount, duplicateCount };
}

function ThemeToggle({ themeMode, setThemeMode }) {
  const options = [
    { value: 'light', label: '☀' },
    { value: 'dark', label: '☾' },
    { value: 'system', label: '⌘' },
  ];

  return (
    <div className="theme-toggle">
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          className={themeMode === option.value ? 'active' : ''}
          onClick={() => setThemeMode(option.value)}
          title={option.value}
          aria-label={option.value}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

function ServiceBadge() {
  return <span className="service-pill">YouTube</span>;
}

function StatusBadge({ item, onAbort }) {
  const label = ['Downloading', 'Converting'].includes(item.status)
    ? `${item.status} ${Math.round(item.progress)}%`
    : item.status;

  if (FAILED_STATUSES.has(item.status)) {
    return <span className="status-pill" style={{ background: 'var(--danger-bg)', borderColor: 'var(--danger-border)', color: 'var(--danger-text)' }}>{item.status}</span>;
  }

  if (CANCELABLE_STATUSES.has(item.status)) {
    return (
      <button type="button" className="status-cancel" onClick={onAbort} title="Abort this item">
        <span className="label-text">{label}</span>
        <span className="cancel-text">CANCEL</span>
      </button>
    );
  }

  return <span className="status-pill">{label}</span>;
}

function QueueProgress({ item }) {
  const failed = FAILED_STATUSES.has(item.status);
  const active = item.status === 'Downloading' || item.status === 'Converting';

  return (
    <div className={cn('progress-track', failed && 'failed')}>
      <div
        className={cn('progress-fill', failed && 'failed')}
        style={{ width: `${clamp(item.progress)}%` }}
      >
        {active && !failed ? <div className="progress-shimmer" /> : null}
      </div>
    </div>
  );
}

export default function App() {
  const [projectName, setProjectName] = useState('');
  const [projectNameMemory, setProjectNameMemory] = useState([]);
  const [projectNameFocused, setProjectNameFocused] = useState(false);
  const [requireProjectName, setRequireProjectName] = useState(true);
  const [projectNameErrorPulse, setProjectNameErrorPulse] = useState(false);
  const [urls, setUrls] = useState('https://www.youtube.com/watch?v=example1\nhttps://youtu.be/example2\nhttps://www.youtube.com/shorts/example3');
  const [clipMode, setClipMode] = useState(false);
  const [startTime, setStartTime] = useState('00:00:12');
  const [endTime, setEndTime] = useState('00:00:22');
  const [queue, setQueue] = useState([]);
  const [themeMode, setThemeMode] = useState('system');
  const [systemTheme, setSystemTheme] = useState('light');

  const audioRef = useRef(null);
  const prevActiveRef = useRef(false);
  const projectErrorTimeoutRef = useRef(null);
  const suggestionBlurTimeoutRef = useRef(null);

  useEffect(() => {
    if (typeof window === 'undefined' || !window.matchMedia) return undefined;
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const updateTheme = () => setSystemTheme(media.matches ? 'dark' : 'light');
    updateTheme();

    if (typeof media.addEventListener === 'function') {
      media.addEventListener('change', updateTheme);
      return () => media.removeEventListener('change', updateTheme);
    }

    media.addListener(updateTheme);
    return () => media.removeListener(updateTheme);
  }, []);

  useEffect(() => {
    setProjectNameMemory(loadProjectMemory());
    return () => {
      if (projectErrorTimeoutRef.current) clearTimeout(projectErrorTimeoutRef.current);
      if (suggestionBlurTimeoutRef.current) clearTimeout(suggestionBlurTimeoutRef.current);
    };
  }, []);

  const resolvedTheme = themeMode === 'system' ? systemTheme : themeMode;
  const trimmedProjectName = projectName.trim();
  const { validUrls, invalidCount, duplicateCount } = useMemo(() => analyzeUrls(urls), [urls]);
  const queueHasActive = useMemo(() => queue.some((item) => ACTIVE_STATUSES.has(item.status)), [queue]);
  const startSeconds = useMemo(() => parseClipTime(startTime), [startTime]);
  const endSeconds = useMemo(() => parseClipTime(endTime), [endTime]);

  const clipValidationMessage = !clipMode
    ? ''
    : startSeconds === null || endSeconds === null
      ? 'Use HH:MM:SS for both start and end.'
      : endSeconds <= startSeconds
        ? 'End time must be later than start time.'
        : '';

  const canStart = validUrls.length > 0 && !clipValidationMessage;

  const projectSuggestions = useMemo(() => {
    const query = trimmedProjectName.toLowerCase();
    return projectNameMemory.filter((entry) => !query || entry.name.toLowerCase().includes(query));
  }, [projectNameMemory, trimmedProjectName]);

  useEffect(() => {
    if (typeof window === 'undefined' || !queue.length) return undefined;

    const intervalId = setInterval(() => {
      const now = Date.now();

      setQueue((current) => {
        let next = current.map((item) => {
          if (item.status === 'Downloading') {
            const ratio = item.downloadDurationMs
              ? Math.min((now - (item.downloadStartedAt ?? now)) / item.downloadDurationMs, 1)
              : 1;

            if (ratio >= 1) {
              return { ...item, status: 'Converting', progress: CONVERT_PROGRESS_MIN, convertStartedAt: now };
            }

            return {
              ...item,
              progress: Math.max(
                item.progress,
                DOWNLOAD_PROGRESS_MIN + (DOWNLOAD_PROGRESS_MAX - DOWNLOAD_PROGRESS_MIN) * ratio
              ),
            };
          }

          if (item.status === 'Converting') {
            const ratio = item.convertDurationMs
              ? Math.min((now - (item.convertStartedAt ?? now)) / item.convertDurationMs, 1)
              : 1;

            if (ratio >= 1) {
              return { ...item, status: 'Complete', progress: 100 };
            }

            return {
              ...item,
              progress: Math.max(item.progress, CONVERT_PROGRESS_MIN + (100 - CONVERT_PROGRESS_MIN) * ratio),
            };
          }

          return item;
        });

        const slots = Math.max(0, MAX_CONCURRENT_DOWNLOADS - next.filter((item) => item.status === 'Downloading').length);
        if (!slots) return next;

        const nextIds = next
          .map((item, index) => ({ item, index }))
          .filter(({ item }) => item.status === 'Queued')
          .sort((a, b) => a.item.estimatedSizeMb - b.item.estimatedSizeMb || a.index - b.index)
          .slice(0, slots)
          .map(({ item }) => item.id);

        if (!nextIds.length) return next;

        const idSet = new Set(nextIds);
        return next.map((item) =>
          idSet.has(item.id) && item.status === 'Queued'
            ? { ...item, status: 'Downloading', progress: DOWNLOAD_PROGRESS_MIN, downloadStartedAt: now }
            : item
        );
      });
    }, 140);

    return () => clearInterval(intervalId);
  }, [queue.length]);

  useEffect(() => {
    const hasActive = queue.some((item) => ACTIVE_STATUSES.has(item.status));
    const allComplete = queue.length > 0 && queue.every((item) => item.status === 'Complete');

    if (prevActiveRef.current && !hasActive && allComplete && audioRef.current) {
      audioRef.current.currentTime = 0;
      audioRef.current.play().catch(() => {});
    }

    prevActiveRef.current = hasActive;
  }, [queue]);

  const rememberProjectName = (name) => {
    const normalized = name.trim();
    if (!normalized) return;

    setProjectNameMemory((current) => {
      const next = sanitizeProjectMemory([
        { name: normalized, lastUsedAt: Date.now() },
        ...current.filter((entry) => entry.name.toLowerCase() !== normalized.toLowerCase()),
      ]);
      persistProjectMemory(next);
      return next;
    });
  };

  const removeProjectMemoryItem = (name) => {
    setProjectNameMemory((current) => {
      const next = current.filter((entry) => entry.name !== name);
      persistProjectMemory(next);
      return next;
    });
  };

  const triggerProjectNameError = () => {
    if (projectErrorTimeoutRef.current) clearTimeout(projectErrorTimeoutRef.current);
    setProjectNameErrorPulse(false);

    requestAnimationFrame(() => {
      setProjectNameErrorPulse(true);
      projectErrorTimeoutRef.current = setTimeout(() => setProjectNameErrorPulse(false), 480);
    });
  };

  const addJobs = () => {
    if (!canStart) return;

    if (requireProjectName && !trimmedProjectName) {
      triggerProjectNameError();
      return;
    }

    if (requireProjectName) rememberProjectName(trimmedProjectName);

    const timestamp = Date.now();
    const newItems = validUrls.map((url, index) => {
      const estimatedSizeMb = getMockEstimatedSizeMb(url);
      return {
        id: timestamp + index,
        title: getMockYoutubeTitle(url),
        status: 'Queued',
        progress: 0,
        url,
        clipMode,
        startTime: clipMode ? startTime : null,
        endTime: clipMode ? endTime : null,
        projectName: requireProjectName ? trimmedProjectName : '',
        estimatedSizeMb,
        ...getMockDurations(estimatedSizeMb),
        downloadStartedAt: null,
        convertStartedAt: null,
        cleanupPending: false,
      };
    });

    setQueue((current) => [...current.filter((item) => item.status !== 'Complete'), ...newItems]);
    setUrls('');
    setProjectNameFocused(false);
  };

  const abortQueueItem = (id) => {
    setQueue((current) =>
      current.map((item) =>
        item.id === id && CANCELABLE_STATUSES.has(item.status)
          ? { ...item, status: 'Aborted', cleanupPending: true }
          : item
      )
    );
  };

  return (
    <div className={cn('app-shell', resolvedTheme)}>
      <audio ref={audioRef} preload="auto" src={COMPLETE_SOUND_URL} />
      <ThemeToggle themeMode={themeMode} setThemeMode={setThemeMode} />

      <div className="app-frame">
        <div className="app-title-wrap">
          <h1 className="app-title">B-Roll Downloader</h1>
          <div className="service-row">
            <span className="service-pill">YouTube</span>
          </div>
          <div className="path-text">Downloads to {DOWNLOAD_PATH}</div>
        </div>

        <div className="stack">
          <div className="panel">
            <div className="panel-content">
              <div className={cn('field-block', projectNameErrorPulse && 'shake')}>
                <div className="field-label-row">
                  <label className="field-label">Project Name</label>
                  <label className="require-toggle">
                    <input
                      type="checkbox"
                      checked={requireProjectName}
                      onChange={(e) => setRequireProjectName(e.target.checked)}
                    />
                    <span>Required</span>
                  </label>
                </div>

                <div className={cn('project-collapse', !requireProjectName && 'hidden')}>
                  <div style={{ position: 'relative', marginTop: 4 }}>
                    <input
                      className={cn('field', projectNameErrorPulse && requireProjectName && 'error')}
                      value={projectName}
                      onChange={(e) => setProjectName(e.target.value)}
                      onFocus={() => {
                        if (suggestionBlurTimeoutRef.current) clearTimeout(suggestionBlurTimeoutRef.current);
                        setProjectNameFocused(true);
                      }}
                      onBlur={() => {
                        suggestionBlurTimeoutRef.current = setTimeout(() => setProjectNameFocused(false), 100);
                      }}
                      placeholder="Enter project name"
                    />

                    {projectNameFocused && projectSuggestions.length > 0 ? (
                      <div className="suggestion-panel">
                        <div className="suggestion-list">
                          {projectSuggestions.map((entry) => (
                            <div key={entry.name} className="suggestion-item">
                              <button
                                type="button"
                                className="suggestion-pick"
                                onMouseDown={(e) => e.preventDefault()}
                                onClick={() => {
                                  setProjectName(entry.name);
                                  setProjectNameFocused(false);
                                }}
                                title={entry.name}
                              >
                                <span>{entry.name}</span>
                              </button>

                              <button
                                type="button"
                                className="suggestion-remove"
                                onMouseDown={(e) => e.preventDefault()}
                                onClick={() => removeProjectMemoryItem(entry.name)}
                                title={`Remove ${entry.name}`}
                              >
                                ×
                              </button>
                            </div>
                          ))}
                        </div>
                      </div>
                    ) : null}
                  </div>
                </div>
              </div>

              <div className="field-block">
                <label className="field-label">YouTube URLs</label>
                <textarea
                  className="textarea"
                  value={urls}
                  onChange={(e) => setUrls(e.target.value)}
                  placeholder="Paste one YouTube URL per line"
                />
                <div className="helper-row">
                  <span>🔗</span>
                  <span>{validUrls.length} valid link{validUrls.length === 1 ? '' : 's'}</span>
                  {invalidCount ? <span>• {invalidCount} invalid ignored</span> : null}
                  {duplicateCount ? <span>• {duplicateCount} duplicate{duplicateCount === 1 ? '' : 's'} skipped</span> : null}
                </div>
              </div>

              <div className="toggle-card">
                <div className="toggle-row">
                  <div className="toggle-left">
                    <div className="icon-chip">✂</div>
                    <div>
                      <div className="toggle-title">Clip Mode</div>
                      <div className="toggle-subtitle">Only download a specific time range.</div>
                    </div>
                  </div>

                  <label className="switch-wrap">
                    <input
                      className="switch-input"
                      type="checkbox"
                      checked={clipMode}
                      onChange={(e) => setClipMode(e.target.checked)}
                    />
                  </label>
                </div>

                {clipMode ? (
                  <div className="clip-grid">
                    <div className="field-block">
                      <label className="field-label">Start</label>
                      <input
                        className="field"
                        value={startTime}
                        onChange={(e) => setStartTime(e.target.value)}
                        placeholder="00:00:12"
                      />
                    </div>

                    <div className="field-block">
                      <label className="field-label">End</label>
                      <input
                        className="field"
                        value={endTime}
                        onChange={(e) => setEndTime(e.target.value)}
                        placeholder="00:00:22"
                      />
                    </div>

                    {clipValidationMessage ? (
                      <div className="small-muted" style={{ color: 'var(--danger-text)', gridColumn: '1 / -1' }}>
                        {clipValidationMessage}
                      </div>
                    ) : null}
                  </div>
                ) : null}
              </div>

              <button
                type="button"
                className={cn('primary-button', validUrls.length > 0 && 'valid')}
                onClick={addJobs}
                disabled={!canStart}
              >
                {queueHasActive && validUrls.length > 0 ? 'Add to Queue' : 'Start Download'}
              </button>
            </div>
          </div>

          <div className="panel">
            <div className="panel-content" style={{ gap: 12 }}>
              <div className="queue-header">
                <div className="toggle-title">Queue</div>
                <div className="queue-right">
                  <div className="queue-count">{queue.length} item{queue.length === 1 ? '' : 's'}</div>
                  <button
                    type="button"
                    className="queue-clear"
                    onClick={() => setQueue([])}
                    disabled={!queue.length}
                    title="Clear queue"
                  >
                    🗑
                  </button>
                </div>
              </div>

              {!queue.length ? (
                <div className="empty-queue">No downloads yet.</div>
              ) : (
                <div className="queue-list">
                  {queue.map((item) => (
                    <div key={item.id} className="queue-item">
                      <div className="queue-item-top">
                        <div className="queue-title-wrap">
                          <div className="queue-title" title={item.title}>
                            {item.title}
                          </div>
                        </div>

                        <div className="queue-badges">
                          <ServiceBadge />
                          <StatusBadge item={item} onAbort={() => abortQueueItem(item.id)} />
                        </div>
                      </div>

                      <div className="progress-wrap">
                        <QueueProgress item={item} />
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
