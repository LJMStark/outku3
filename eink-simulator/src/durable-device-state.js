const STORAGE_KEY = 'kirole.einkSimulator.deviceState.v1';

export function restoreDurableDeviceState(state, storage = globalThis.localStorage) {
  if (!state || !storage) return false;
  try {
    const raw = storage.getItem(STORAGE_KEY);
    if (!raw) return false;
    return state.importDurableDeviceState(JSON.parse(raw));
  } catch {
    return false;
  }
}

export function persistDurableDeviceState(state, storage = globalThis.localStorage) {
  if (!state || !storage) return false;
  try {
    storage.setItem(STORAGE_KEY, JSON.stringify(state.exportDurableDeviceState()));
    return true;
  } catch {
    return false;
  }
}
