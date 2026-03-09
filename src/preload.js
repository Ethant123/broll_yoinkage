const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('updaterAPI', {
  onState(callback) {
    const handler = (_event, state) => callback(state);
    ipcRenderer.on('update:state', handler);
    return () => ipcRenderer.removeListener('update:state', handler);
  },
  openDownload() {
    return ipcRenderer.invoke('update:open-download');
  },
  quit() {
    ipcRenderer.send('update:quit');
  },
});
