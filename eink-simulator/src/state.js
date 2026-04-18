// ============================================================
// Simulator State - Single source of truth
// ============================================================

// Display Modes
export const DisplayMode = Object.freeze({
  IDLE: 'idle',
  FOCUS_WARMUP: 'focus-warmup',
  FOCUS_BUILDING: 'focus-building',
  FOCUS_DEEP: 'focus-deep',
  SCREENSAVER_NORMAL: 'screensaver-normal',
  SCREENSAVER_POSTCARD: 'screensaver-postcard',
});

// Scenes
export const Scene = Object.freeze({
  HARBOR: 'harbor',
  FOREST: 'forest',
  NIGHT_CITY: 'night-city',
});

// IP Characters
export const Character = Object.freeze({
  NOOK: 'nook',
  SILAS: 'silas',
  NOVA: 'nova',
});

const SCENE_ALIASES = Object.freeze({
  harbor: Scene.HARBOR,
  forest: Scene.FOREST,
  'night-city': Scene.NIGHT_CITY,
  nightCity: Scene.NIGHT_CITY,
  night_city: Scene.NIGHT_CITY,
});

const CHARACTER_ALIASES = Object.freeze({
  nook: Character.NOOK,
  silas: Character.SILAS,
  nova: Character.NOVA,
});

const SUPPORTED_RENDER_MOODS = new Set([
  'idle',
  'warmup',
  'building',
  'deep',
  'postcard',
]);

// Default tasks and events for demo
const DEFAULT_TASKS = [
  { id: '1', title: 'Laundry', completed: false },
  { id: '2', title: 'Brainstorm Kirole Colorways', completed: false },
  { id: '3', title: 'Approve Factory Prototypes', completed: true },
  { id: '4', title: 'Check and reply to emails', completed: false },
  { id: '5', title: 'Plan your tasks for the day', completed: true },
  { id: '6', title: 'Complete a key task', completed: false },
];

const DEFAULT_EVENTS = [
  {
    id: 'e1',
    time: '9:30',
    title: 'All Hands',
    description: 'The quarterly all hands with pretty much everyone at the company. Happening over Zoom!',
  },
  {
    id: 'e2',
    time: '10:30',
    title: 'Kirole Makeit Factory Sync',
    description: 'Meeting w/ reps at the Kirole Factory- Invite says the agenda is to nail down some colorways.',
  },
];

const DEFAULT_FOCUS_TASK = {
  id: 'ft1',
  title: 'Deployment: OpenClaw System',
  overview: 'Deploying OpenClaw core clusters via Docker. Syncing configuration files.',
  tips: 'Check server port availability first. Ensuring port 8080 is clear will prevent common \'address already in use\' errors during the initial launch.',
};

export class SimulatorState {
  constructor() {
    this._listeners = [];

    // Display
    this.displayMode = DisplayMode.IDLE;
    this.scene = Scene.HARBOR;
    this.character = Character.NOOK;
    this.petName = 'Nook';
    this.petMood = 'idle';

    // Weather
    this.weather = { temp: '42/23', unit: 'F', condition: 'SUNNY', icon: '-*' };
    this.date = 'Feb 10, 2026';

    // Tasks & Events
    this.tasks = [...DEFAULT_TASKS];
    this.events = [...DEFAULT_EVENTS];

    // Focus
    this.focusTask = { ...DEFAULT_FOCUS_TASK };
    this.activeFocusTaskId = DEFAULT_FOCUS_TASK.id;
    this.focusPhase = 'idle';
    this.focusElapsedMinutes = 0;
    this.focusTimerActive = false;

    // Energy
    this.energyBottles = 0;
    this.currentPhaseBottleProgress = 0; // 0.0 - 1.0 within current 30-min cycle

    // Progress
    this.taskProgress = { completed: 5, total: 10, percent: 50 };

    // Dialogue
    this.petDialogue = 'Today, I completed planned tasks and made steady progress.';

    // Screensaver
    this.screensaverQuote = 'We are all in the gutter, but some of us are looking at the stars.';
    this.screensaverAuthor = 'Oscar Wilde';
    this.postcardDay = 7;

    // Streak
    this.consecutiveDays = 7;

    // Scene unlocks
    this.sceneUnlocks = [];

    // Animation triggers
    this.lastUnlockedScene = null;
  }

  // Register change listeners
  onChange(fn) {
    this._listeners.push(fn);
  }

  // Notify all listeners
  _notify() {
    for (const fn of this._listeners) {
      fn();
    }
  }

  // Update state and notify
  update(changes) {
    for (const [key, value] of Object.entries(changes)) {
      if (key !== '_listeners') {
        this[key] = value;
      }
    }
    this._notify();
  }

  // Set display mode
  setDisplayMode(mode) {
    this.update({ displayMode: mode });
  }

  // Set scene
  setScene(scene) {
    this.update({ scene: this.normalizeSceneId(scene) });
  }

  // Set character
  setCharacter(character) {
    this.update({
      character: this.normalizeCharacter(character),
      petName: this.normalizePetName(character),
    });
  }

  // Focus timer
  setFocusMinutes(minutes) {
    let mode = DisplayMode.IDLE;
    if (minutes > 0 && minutes <= 5) mode = DisplayMode.FOCUS_WARMUP;
    else if (minutes > 5 && minutes <= 15) mode = DisplayMode.FOCUS_BUILDING;
    else if (minutes > 15) mode = DisplayMode.FOCUS_DEEP;

    this.update({
      focusPhase: this._displayModeToFocusPhase(mode),
      focusElapsedMinutes: minutes,
      displayMode: mode,
      currentPhaseBottleProgress: minutes / 30,
    });
  }

  // Energy bottles
  addBottle() {
    this.update({ energyBottles: this.energyBottles + 1 });
  }

  resetBottles() {
    this.update({ energyBottles: 0 });
  }

  // Complete task
  completeCurrentTask() {
    if (this.displayMode.startsWith('focus')) {
      const completed = this.tasks.filter(t => !t.completed)[0];
      if (completed) {
        completed.completed = true;
        this.update({
          tasks: [...this.tasks],
          displayMode: DisplayMode.IDLE,
          focusElapsedMinutes: 0,
        });
      }
    }
    return { type: 'hw_complete_task', payload: { taskId: this.focusTask.id } };
  }

  // Skip task
  skipCurrentTask() {
    if (this.displayMode.startsWith('focus')) {
      this.update({
        displayMode: DisplayMode.IDLE,
        focusElapsedMinutes: 0,
      });
    }
    return { type: 'hw_skip_task', payload: { taskId: this.focusTask.id } };
  }

  // Toggle screensaver
  toggleScreensaver() {
    if (this.displayMode.startsWith('screensaver')) {
      this.update({ displayMode: DisplayMode.IDLE });
      return { type: 'hw_exit_screensaver' };
    }

    const isPostcard = [3, 7, 21].includes(this.consecutiveDays);
    this.update({
      displayMode: isPostcard
        ? DisplayMode.SCREENSAVER_POSTCARD
        : DisplayMode.SCREENSAVER_NORMAL,
    });
    return { type: 'hw_enter_screensaver' };
  }

  normalizeSceneId(sceneId) {
    if (!sceneId) return this.scene;
    return SCENE_ALIASES[sceneId] || sceneId;
  }

  normalizeCharacter(characterOrName) {
    if (!characterOrName) return this.character;
    const normalized = String(characterOrName).trim().toLowerCase();
    return CHARACTER_ALIASES[normalized] || this.character;
  }

  normalizePetName(characterOrName) {
    const character = this.normalizeCharacter(characterOrName);
    return character.charAt(0).toUpperCase() + character.slice(1);
  }

  normalizeFocusPhase(phase) {
    if (!phase) return 'idle';
    const normalized = String(phase).trim().toLowerCase();
    if (['idle', 'warmup', 'building', 'deep'].includes(normalized)) {
      return normalized;
    }
    return 'idle';
  }

  focusPhaseToDisplayMode(phase) {
    switch (this.normalizeFocusPhase(phase)) {
      case 'warmup':
        return DisplayMode.FOCUS_WARMUP;
      case 'building':
        return DisplayMode.FOCUS_BUILDING;
      case 'deep':
        return DisplayMode.FOCUS_DEEP;
      default:
        return DisplayMode.IDLE;
    }
  }

  applyPetStatus({ petName, characterId, petMood, sceneId }) {
    const nextCharacter = characterId
      ? this.normalizeCharacter(characterId)
      : (petName ? this.normalizeCharacter(petName) : this.character);
    const nextMood = petMood || this.petMood;
    const updates = {
      character: nextCharacter,
      petName: petName || this.normalizePetName(nextCharacter),
      petMood: nextMood,
    };

    if (sceneId) {
      updates.scene = this.normalizeSceneId(sceneId);
    }

    this.update(updates);
  }

  applyFocusState({ energyBottles, activeFocusTaskId, focusPhase, elapsedMinutes, taskTitle }) {
    const normalizedPhase = this.normalizeFocusPhase(focusPhase);
    const nextFocusTask = activeFocusTaskId
      ? {
          ...this.focusTask,
          id: activeFocusTaskId,
          title: taskTitle || this.focusTask.title,
        }
      : this.focusTask;

    this.update({
      energyBottles: energyBottles ?? this.energyBottles,
      activeFocusTaskId: activeFocusTaskId ?? this.activeFocusTaskId,
      focusTask: nextFocusTask,
      focusPhase: normalizedPhase,
      displayMode: this.focusPhaseToDisplayMode(normalizedPhase),
      focusElapsedMinutes: normalizedPhase === 'idle' ? 0 : (elapsedMinutes ?? this.focusElapsedMinutes),
      currentPhaseBottleProgress: normalizedPhase === 'idle'
        ? 0
        : ((elapsedMinutes ?? this.focusElapsedMinutes) / 30),
    });
  }

  applyScreensaverConfig(config = {}) {
    const nextDisplayMode = config.type === 'postcard'
      ? DisplayMode.SCREENSAVER_POSTCARD
      : DisplayMode.SCREENSAVER_NORMAL;
    const updates = {
      displayMode: nextDisplayMode,
      screensaverQuote: config.quote || this.screensaverQuote,
      screensaverAuthor: config.author || this.screensaverAuthor,
    };

    if (config.sceneId) {
      updates.scene = this.normalizeSceneId(config.sceneId);
    }

    if (config.postcardDay !== undefined) {
      updates.postcardDay = config.postcardDay;
    }

    this.update(updates);
  }

  applySceneUnlocks(unlocks = []) {
    const normalizedUnlocks = unlocks
      .filter(unlock => unlock?.sceneId)
      .map(unlock => ({ sceneId: this.normalizeSceneId(unlock.sceneId) }));

    // Detect newly unlocked scenes
    const prevIds = new Set(this.sceneUnlocks.map(u => u.sceneId));
    const newScene = normalizedUnlocks.find(u => !prevIds.has(u.sceneId));

    const updates = { sceneUnlocks: normalizedUnlocks };
    const latestUnlock = normalizedUnlocks.at(-1);
    if (latestUnlock) {
      updates.scene = latestUnlock.sceneId;
    }

    if (newScene) {
      updates.lastUnlockedScene = newScene.sceneId;
    }

    this.update(updates);
  }

  getPetRenderMood() {
    if (SUPPORTED_RENDER_MOODS.has(this.petMood)) {
      return this.petMood;
    }
    return 'idle';
  }

  // Get character display info
  getCharacterInfo() {
    const chars = {
      [Character.NOOK]: { name: 'Nook', emoji: '\uD83E\uDD8A', color: '#c8a060' },
      [Character.SILAS]: { name: 'Silas', emoji: '\uD83E\uDDD9', color: '#6b8cae' },
      [Character.NOVA]: { name: 'Nova', emoji: '\u2604\uFE0F', color: '#8b5cf6' },
    };
    return chars[this.character] || chars[Character.NOOK];
  }

  // Get scene class name
  getSceneClass() {
    return `scene-${this.scene}`;
  }

  _displayModeToFocusPhase(mode) {
    switch (mode) {
      case DisplayMode.FOCUS_WARMUP:
        return 'warmup';
      case DisplayMode.FOCUS_BUILDING:
        return 'building';
      case DisplayMode.FOCUS_DEEP:
        return 'deep';
      default:
        return 'idle';
    }
  }
}
