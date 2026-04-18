// ============================================================
// Kirole E-ink Display Simulator - Main Entry
// ============================================================

import { ScreenRenderer } from './screen-renderer.js';
import { HardwareControls } from './hardware-controls.js';
import { DevPanel } from './dev-panel.js';
import { WebSocketBridge } from './websocket-bridge.js';
import { SimulatorState } from './state.js';

// Initialize global state
const state = new SimulatorState();

// Initialize modules
const screen = new ScreenRenderer(
  document.getElementById('eink-screen'),
  state
);
const hardware = new HardwareControls(state);
const devPanel = new DevPanel(state);
const wsBridge = new WebSocketBridge(state);

// Cross-wire: bridge needs renderer for animations, hardware needs bridge for events
wsBridge.setScreenRenderer(screen);
hardware.setWebSocketBridge(wsBridge);

// Wire up state change listener
state.onChange(() => {
  screen.render();
});

// Initial render
screen.render();

