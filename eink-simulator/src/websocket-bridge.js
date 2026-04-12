// ============================================================
// WebSocket Bridge - Communication with iOS APP
// ============================================================

export class WebSocketBridge {
  constructor(state) {
    this.state = state;
    this.ws = null;
    this._statusEl = document.getElementById('ws-status');
    this._logEl = document.getElementById('ws-log');

    this._bindConnectButton();
  }

  _bindConnectButton() {
    const btn = document.getElementById('btn-ws-connect');
    const urlInput = document.getElementById('ws-url');

    btn.addEventListener('click', () => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.close();
        return;
      }
      this.connect(urlInput.value);
    });
  }

  connect(url) {
    try {
      this.ws = new WebSocket(url);
    } catch (err) {
      this._setStatus('disconnected', `Error: ${err.message}`);
      return;
    }

    this.ws.onopen = () => {
      this._setStatus('connected', 'Connected');
      this._log('out', 'Connected to APP');
      document.getElementById('btn-ws-connect').textContent = 'Disconnect';
    };

    this.ws.onclose = () => {
      this._setStatus('disconnected', 'Disconnected');
      document.getElementById('btn-ws-connect').textContent = 'Connect';
    };

    this.ws.onerror = (err) => {
      this._setStatus('disconnected', 'Connection Error');
      this._log('in', `Error: WebSocket failed`);
    };

    this.ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        this._handleMessage(msg);
        this._log('in', `${msg.type}: ${this._summarizeMessage(msg)}`);
      } catch (err) {
        this._log('in', `Parse error: ${event.data.substring(0, 60)}`);
      }
    };
  }

  send(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      const data = JSON.stringify(message);
      this.ws.send(data);
      this._log('out', `${message.type}`);
    }
  }

  _handleMessage(msg) {
    switch (msg.type) {
      case 'app_pet_status':
        this.state.applyPetStatus({
          petName: msg.petName,
          characterId: msg.characterId,
          petMood: msg.petMood,
          sceneId: msg.sceneId,
        });
        break;

      case 'app_focus_state':
        this.state.applyFocusState({
          energyBottles: msg.energyBottles,
          activeFocusTaskId: msg.activeFocusTaskId,
          focusPhase: msg.focusPhase,
          elapsedMinutes: msg.elapsedMinutes,
          taskTitle: msg.taskTitle,
        });
        break;

      case 'app_screensaver':
        this.state.applyScreensaverConfig(msg.config);
        break;

      case 'app_scene_unlock':
        this.state.applySceneUnlocks(msg.unlocks);
        break;

      case 'daypack':
        this._applyDayPack(msg.payload);
        break;

      case 'focus_start':
        this.state.update({
          focusTask: {
            id: msg.payload.taskId || 'remote',
            title: msg.payload.taskTitle || 'Focus Task',
            overview: msg.payload.overview || '',
            tips: msg.payload.tips || '',
          },
          activeFocusTaskId: msg.payload.taskId || this.state.activeFocusTaskId,
          focusPhase: 'warmup',
          displayMode: 'focus-warmup',
          focusElapsedMinutes: 0,
          currentPhaseBottleProgress: 0,
        });
        break;

      case 'focus_phase':
        {
          const focusPhase = this.state.normalizeFocusPhase(msg.payload.phase);
          const elapsed = msg.payload.elapsed || 0;
          this.state.update({
            focusPhase,
            focusElapsedMinutes: elapsed,
            displayMode: this.state.focusPhaseToDisplayMode(focusPhase),
            currentPhaseBottleProgress: elapsed / 30,
          });
        }
        break;

      case 'focus_end':
        this.state.update({
          focusPhase: 'idle',
          displayMode: 'idle',
          focusElapsedMinutes: 0,
          currentPhaseBottleProgress: 0,
          energyBottles: this.state.energyBottles + (msg.payload.bottlesEarned || 0),
        });
        break;

      case 'screensaver':
        this.state.applyScreensaverConfig({
          type: msg.payload.type,
          quote: msg.payload.quote,
          author: msg.payload.author,
          sceneId: msg.payload.sceneId || msg.payload.scene,
          postcardDay: msg.payload.postcardDay,
        });
        break;

      case 'scene_change':
        this.state.applySceneUnlocks([{ sceneId: msg.payload.sceneId }]);
        break;

      default:
        this._log('in', `Unknown message type: ${msg.type}`);
    }
  }

  _applyDayPack(payload) {
    const updates = {};
    if (payload.weather) updates.weather = payload.weather;
    if (payload.date) updates.date = payload.date;
    if (payload.tasks) updates.tasks = payload.tasks;
    if (payload.events) updates.events = payload.events;
    if (payload.petDialogue) updates.petDialogue = payload.petDialogue;
    if (payload.taskProgress) updates.taskProgress = payload.taskProgress;
    if (payload.character) {
      updates.character = this.state.normalizeCharacter(payload.character);
      updates.petName = this.state.normalizePetName(payload.character);
    }
    if (payload.petName || payload.petMood || payload.sceneId) {
      this.state.applyPetStatus({
        petName: payload.petName,
        petMood: payload.petMood,
        sceneId: payload.sceneId,
      });
    }
    if (payload.scene) updates.scene = this.state.normalizeSceneId(payload.scene);
    if (payload.energyBottles !== undefined) updates.energyBottles = payload.energyBottles;
    if (payload.consecutiveDays !== undefined) updates.consecutiveDays = payload.consecutiveDays;

    if (Object.keys(updates).length > 0) {
      this.state.update(updates);
    }
  }

  _summarizeMessage(msg) {
    const summary = msg.payload ?? {
      ...msg,
      type: undefined,
    };
    return JSON.stringify(summary).substring(0, 80);
  }

  _setStatus(cls, text) {
    this._statusEl.className = `ws-status ${cls}`;
    this._statusEl.textContent = text;
  }

  _log(direction, text) {
    const div = document.createElement('div');
    div.className = `log-${direction}`;
    const time = new Date().toLocaleTimeString();
    div.textContent = `[${time}] ${direction === 'in' ? '<-' : '->'} ${text}`;
    this._logEl.prepend(div);

    // Keep log size manageable
    while (this._logEl.children.length > 50) {
      this._logEl.removeChild(this._logEl.lastChild);
    }
  }
}
