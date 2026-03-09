const { app, BrowserWindow, ipcMain, shell } = require('electron');

if (require('electron-squirrel-startup')) {
  app.quit();
}

const RELEASES_API_URL = 'https://api.github.com/repos/Ethant123/broll_yoinkage/releases/latest';

let mainWindow = null;
let splashWindow = null;
let splashState = { type: 'checking' };
let pendingUpdateInfo = null;

function normalizeVersion(version) {
  return String(version || '')
    .trim()
    .replace(/^v/i, '')
    .split(/[+-]/)[0];
}

function compareVersions(a, b) {
  const aParts = normalizeVersion(a).split('.').map((part) => Number.parseInt(part || '0', 10));
  const bParts = normalizeVersion(b).split('.').map((part) => Number.parseInt(part || '0', 10));
  const len = Math.max(aParts.length, bParts.length);

  for (let i = 0; i < len; i += 1) {
    const av = aParts[i] || 0;
    const bv = bParts[i] || 0;
    if (av > bv) return 1;
    if (av < bv) return -1;
  }

  return 0;
}

function setSplashState(nextState) {
  splashState = nextState;
  if (splashWindow && !splashWindow.isDestroyed()) {
    splashWindow.webContents.send('update:state', splashState);
  }
}

function createSplashWindow() {
  splashWindow = new BrowserWindow({
    width: 520,
    height: 420,
    resizable: false,
    maximizable: false,
    minimizable: false,
    fullscreenable: false,
    titleBarStyle: 'hiddenInset',
    show: false,
    backgroundColor: '#24303d',
    webPreferences: {
      preload: UPDATE_WINDOW_PRELOAD_WEBPACK_ENTRY,
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  splashWindow.once('ready-to-show', () => {
    splashWindow.show();
  });

  splashWindow.on('closed', () => {
    splashWindow = null;
    if (!mainWindow) app.quit();
  });

  splashWindow.webContents.on('did-finish-load', () => {
    splashWindow.webContents.send('update:state', splashState);
  });

  splashWindow.loadURL(UPDATE_WINDOW_WEBPACK_ENTRY);
}

function createMainWindow() {
  if (mainWindow) {
    mainWindow.show();
    mainWindow.focus();
    return;
  }

  mainWindow = new BrowserWindow({
    width: 1120,
    height: 860,
    minWidth: 900,
    minHeight: 700,
    titleBarStyle: 'hiddenInset',
    backgroundColor: '#24303d',
    webPreferences: {
      preload: MAIN_WINDOW_PRELOAD_WEBPACK_ENTRY,
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.once('ready-to-show', () => {
    if (splashWindow && !splashWindow.isDestroyed()) {
      splashWindow.close();
    }
    mainWindow.show();
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  mainWindow.loadURL(MAIN_WINDOW_WEBPACK_ENTRY);
}

async function checkForUpdates() {
  setSplashState({ type: 'checking' });

  try {
    const response = await fetch(RELEASES_API_URL, {
      headers: {
        'User-Agent': 'B-Roll-Downloader',
        Accept: 'application/vnd.github+json',
      },
    });

    if (!response.ok) {
      throw new Error(`GitHub responded with ${response.status}`);
    }

    const release = await response.json();
    const currentVersion = normalizeVersion(app.getVersion());
    const latestVersion = normalizeVersion(release.tag_name);

    if (compareVersions(latestVersion, currentVersion) > 0) {
      pendingUpdateInfo = {
        version: release.tag_name || latestVersion,
        downloadUrl: release.assets?.[0]?.browser_download_url || release.html_url,
        releaseUrl: release.html_url,
      };

      setSplashState({
        type: 'update-required',
        currentVersion,
        latestVersion: pendingUpdateInfo.version,
      });
      return;
    }

    setSplashState({
      type: 'up-to-date',
      currentVersion,
    });

    setTimeout(() => {
      createMainWindow();
    }, 700);
  } catch (error) {
    setSplashState({
      type: 'error',
      message: error instanceof Error ? error.message : 'Unknown update error',
    });

    setTimeout(() => {
      createMainWindow();
    }, 1400);
  }
}

ipcMain.handle('update:open-download', async () => {
  const target = pendingUpdateInfo?.downloadUrl || pendingUpdateInfo?.releaseUrl || 'https://github.com/Ethant123/broll_yoinkage/releases/latest';
  await shell.openExternal(target);
  app.quit();
});

ipcMain.on('update:quit', () => {
  app.quit();
});

app.whenReady().then(() => {
  createSplashWindow();
  checkForUpdates();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createSplashWindow();
      checkForUpdates();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
