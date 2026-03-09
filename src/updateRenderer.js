const spinner = document.getElementById('spinner');
const title = document.getElementById('title');
const message = document.getElementById('message');
const meta = document.getElementById('meta');
const actions = document.getElementById('actions');
const downloadBtn = document.getElementById('downloadBtn');
const quitBtn = document.getElementById('quitBtn');

downloadBtn.addEventListener('click', () => {
  window.updaterAPI.openDownload();
});

quitBtn.addEventListener('click', () => {
  window.updaterAPI.quit();
});

window.updaterAPI.onState((state) => {
  const type = state?.type || 'checking';

  if (type === 'checking') {
    spinner.classList.remove('hidden');
    actions.classList.add('hidden');
    title.textContent = 'Checking for updates…';
    message.textContent = 'Please wait while we check GitHub for the latest release.';
    meta.textContent = '';
    return;
  }

  if (type === 'up-to-date') {
    spinner.classList.remove('hidden');
    actions.classList.add('hidden');
    title.textContent = 'You’re up to date';
    message.textContent = 'Launching the app now.';
    meta.textContent = state.currentVersion ? `Current version: ${state.currentVersion}` : '';
    return;
  }

  if (type === 'update-required') {
    spinner.classList.add('hidden');
    actions.classList.remove('hidden');
    title.textContent = 'Update required';
    message.textContent = 'A newer version is available. Download it before continuing.';
    meta.textContent = `Current: ${state.currentVersion}   Latest: ${state.latestVersion}`;
    return;
  }

  if (type === 'error') {
    spinner.classList.add('hidden');
    actions.classList.add('hidden');
    title.textContent = 'Couldn’t check for updates';
    message.textContent = 'Launching the current version anyway.';
    meta.textContent = state.message || '';
  }
});
