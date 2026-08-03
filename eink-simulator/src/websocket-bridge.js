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
      this._onConnected();
      this._setStatus('connected', 'Connected');
      this._log('out', 'Connected to APP');
      document.getElementById('btn-ws-connect').textContent = 'Disconnect';
    };

    this.ws.onclose = () => {
      this.state.setAppConnected(false);
      this._setStatus('disconnected', 'Disconnected');
      document.getElementById('btn-ws-connect').textContent = 'Connect';
    };

    this.ws.onerror = () => {
      this.state.setAppConnected(false);
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

      case 'app_task_library':
        this._applyTaskLibrarySnapshot(msg.payload?.records || msg.records || []);
        break;

      case 'app_task_action_ack':
        this._handleTaskActionAck(msg.payload || msg);
        break;

      case 'focus_start':
        this.state.startFocusTask({
          id: msg.payload.taskId || 'remote',
          title: msg.payload.taskTitle || 'Focus Task',
          overview: msg.payload.overview || '',
          phaseTexts: msg.payload.phaseTexts,
        });
        break;

      case 'focus_phase':
        this.state.applyFocusState({
          activeFocusTaskId: this.state.activeFocusTaskId,
          focusPhase: msg.payload.phase,
          elapsedMinutes: msg.payload.elapsed,
        });
        break;

      case 'focus_end':
        this._handleFocusEnd(msg.payload);
        break;

      case 'daily_summary':
        this.state.update({
          settlementReview: msg.payload?.review || this.state.settlementReview,
          settlementQuote: msg.payload?.quote || this.state.settlementQuote,
        });
        this.state.enterDailySummary();
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

  // E-ink feedback is a static page replacement; no completion animation.
  _handleFocusEnd(payload = {}) {
    const bottlesEarned = payload.bottlesEarned || 0;
    this.state.applyFocusState({
      energyBottles: this.state.energyBottles + bottlesEarned,
      activeFocusTaskId: null,
      focusPhase: 'idle',
      elapsedMinutes: 0,
    });
  }

  _applyDayPack(payload) {
    const updates = {};
    if (payload.weather) updates.weather = payload.weather;
    if (payload.date) updates.date = payload.date;
    if (payload.tasks) updates.tasks = payload.tasks;
    if (payload.taskLibrary) {
      this._applyTaskLibrarySnapshot(payload.taskLibrary);
    } else if (payload.tasks) {
      // Compatibility for the current debug bridge until it sends the independent 0x23 library.
      this._applyTaskLibrarySnapshot(payload.tasks);
    }
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
    if (payload.settlementReview) updates.settlementReview = payload.settlementReview;
    if (payload.settlementQuote) updates.settlementQuote = payload.settlementQuote;

    if (Object.keys(updates).length > 0) {
      this.state.update(updates);
    }
  }

  /**
   * Reconnect path: mark the App connected, then resend the full outbox
   * (pending + unacknowledged) in insertionSeq order, followed by a single
   * hw_task_action_replay_end marker so the App can flush its merged library
   * only after every offline action has been delivered on the wire.
   * Locally the library stays blocked until matching non-internal-error
   * app_task_action_ack clears every outbox item — replay_end does not unlock.
   */
  _onConnected() {
    this.state.setAppConnected(true);
    this._flushOutboxTaskActions();
  }

  _flushOutboxTaskActions() {
    const outbox = this.state.flushPendingTaskActions();
    for (const entry of outbox) {
      const message = this.state.taskActionToHardwareMessage(entry);
      if (message) this.send(message);
    }
    // Always emit the end marker after the ordered action stream (possibly empty).
    this.send({ type: 'hw_task_action_replay_end' });
    return outbox;
  }

  _handleTaskActionAck(payload = {}) {
    const outcome = this.state.applyTaskActionAck({
      action: payload.action,
      operationId: payload.operationId ?? payload.operationID,
      result: payload.result ?? payload.code,
    });
    if (outcome.status === 'internalError') {
      this._log('in', `Task action ACK internalError op=${payload.operationId}`);
    }
    return outcome;
  }

  _applyTaskLibrarySnapshot(records = []) {
    const accepted = this.state.setCommittedTaskLibrary(records);
    if (!accepted) {
      this._log(
        'in',
        this.state.replayFailed
          ? 'Blocked task library (replay failed)'
          : 'Blocked task library (outbox not fully acknowledged)'
      );
    }
    return accepted;
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
