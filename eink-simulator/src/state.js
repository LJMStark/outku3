// ============================================================
// Simulator State - Single source of truth
// ============================================================

// Display Modes
export const DisplayMode = Object.freeze({
  IDLE: 'idle',
  FOCUS_WARMUP: 'focus-warmup',
  FOCUS_BUILDING: 'focus-building',
  FOCUS_DEEP: 'focus-deep',
  DAILY_SUMMARY: 'daily-summary',
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
  JOY: 'joy',
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
  joy: Character.JOY,
  nook: Character.JOY,
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
  {
    id: '1',
    title: 'Laundry',
    completed: false,
    overview: 'Sort the clothes and start the next load.',
    phaseTexts: {
      warmup: 'One small load is enough to begin.',
      building: 'Keep the cycle moving.',
      deep: 'Finish the load you already started.',
    },
  },
  {
    id: '2',
    title: 'Brainstorm Kirole Colorways',
    completed: false,
    overview: 'Explore a focused set of color directions for Kirole.',
    phaseTexts: {
      warmup: 'Start with the first useful contrast.',
      building: 'Keep only the strongest directions.',
      deep: 'Commit to the clearest palette.',
    },
  },
  { id: '3', title: 'Approve Factory Prototypes', completed: true },
  {
    id: '4',
    title: 'Check and reply to emails',
    completed: false,
    overview: 'Reply to the messages that need a decision today.',
    phaseTexts: {
      warmup: 'Open the message that needs one clear answer.',
      building: 'Keep each reply short and useful.',
      deep: 'Close the remaining decision threads.',
    },
  },
  { id: '5', title: 'Plan your tasks for the day', completed: true },
  {
    id: '6',
    title: 'Complete a key task',
    completed: false,
    overview: 'Protect time for the most important unfinished task.',
    phaseTexts: {
      warmup: 'Begin with the smallest concrete action.',
      building: 'Stay with the one useful path.',
      deep: 'Finish the core result before polishing.',
    },
  },
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

const DEFAULT_PHASE_TEXTS = Object.freeze({
  warmup: 'Start with one small step.',
  building: 'Stay with the task in front of you.',
  deep: 'Keep the important work moving.',
});

const isFocusMode = mode => String(mode).startsWith('focus');
const isScreensaverMode = mode => String(mode).startsWith('screensaver');

export class SimulatorState {
  constructor() {
    this._listeners = [];

    // Display
    this.displayMode = DisplayMode.IDLE;
    this.scene = Scene.HARBOR;
    this.character = Character.JOY;
    this.petName = 'Joy';
    this.petMood = 'idle';

    // Weather
    this.weather = { temp: '42/23', unit: 'F', condition: 'SUNNY', icon: '-*' };
    this.date = 'Feb 10, 2026';

    // Tasks & Events
    this.tasks = [...DEFAULT_TASKS];
    this.taskLibrary = DEFAULT_TASKS
      .filter(task => !task.completed)
      .map(task => this._normalizeTaskRecord(task));
    this.events = [...DEFAULT_EVENTS];

    // Focus
    this.focusTask = this.taskLibrary[0] || null;
    this.activeFocusTaskId = null;
    this.focusPhase = 'idle';
    this.focusElapsedMinutes = 0;
    this.focusTimerActive = false;
    this.focusSourceMode = DisplayMode.IDLE;

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
    this.screensaverSourceMode = DisplayMode.IDLE;

    // Daily summary
    this.settlementReview = 'You kept the day moving and made steady progress.';
    this.settlementQuote = 'Leave a little space for tomorrow.';
    this.dailySummarySourceMode = DisplayMode.IDLE;

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
    if (minutes > 0 && !isFocusMode(this.displayMode)) {
      this.enterQueueHead();
    }

    let mode = DisplayMode.IDLE;
    if (minutes > 0 && minutes <= 5) mode = DisplayMode.FOCUS_WARMUP;
    else if (minutes > 5 && minutes <= 15) mode = DisplayMode.FOCUS_BUILDING;
    else if (minutes > 15) mode = DisplayMode.FOCUS_DEEP;

    const updates = {
      focusPhase: this._displayModeToFocusPhase(mode),
      focusElapsedMinutes: minutes,
      displayMode: mode,
      currentPhaseBottleProgress: minutes / 30,
    };
    if (mode === DisplayMode.IDLE) {
      updates.activeFocusTaskId = null;
    }
    this.update(updates);
  }

  // Energy bottles
  addBottle() {
    this.update({ energyBottles: this.energyBottles + 1 });
  }

  resetBottles() {
    this.update({ energyBottles: 0 });
  }

  setCommittedTaskLibrary(records = []) {
    const taskLibrary = records
      .map(record => this._normalizeTaskRecord(record))
      .filter(record => record.id && !record.completed);

    this.update({ taskLibrary });
  }

  enterQueueHead() {
    if (this.displayMode !== DisplayMode.IDLE) return null;
    const task = this.taskLibrary[0];
    if (!task) return null;

    this.startFocusTask(task);
    return { type: 'hw_start_task', taskId: task.id };
  }

  startFocusTask(record) {
    const task = this._normalizeTaskRecord(record);
    if (!task.id) return;
    if (!isFocusMode(this.displayMode)) {
      this.focusSourceMode = this._restorableMode(this.displayMode);
    }
    this.update({
      focusTask: task,
      activeFocusTaskId: task.id,
      focusPhase: 'warmup',
      displayMode: DisplayMode.FOCUS_WARMUP,
      focusElapsedMinutes: 0,
      currentPhaseBottleProgress: 0,
    });
  }

  // Complete task
  completeCurrentTask() {
    if (!isFocusMode(this.displayMode) || !this.activeFocusTaskId) return null;

    const taskId = this.activeFocusTaskId;
    const taskLibrary = this.taskLibrary.filter(task => task.id !== taskId);
    const tasks = this.tasks.map(task => (
      this._taskId(task) === taskId ? { ...task, completed: true } : task
    ));
    this._returnFromFocus({ taskLibrary, tasks });
    return { type: 'hw_complete_task', taskId };
  }

  // Skip task
  skipCurrentTask() {
    if (!isFocusMode(this.displayMode) || !this.activeFocusTaskId) return null;

    const taskId = this.activeFocusTaskId;
    const taskIndex = this.taskLibrary.findIndex(task => task.id === taskId);
    if (taskIndex < 0) return null;
    const task = this.taskLibrary[taskIndex];
    const taskLibrary = [
      ...this.taskLibrary.slice(0, taskIndex),
      ...this.taskLibrary.slice(taskIndex + 1),
      task,
    ];
    this._returnFromFocus({ taskLibrary });
    return { type: 'hw_skip_task', taskId };
  }

  handleShortPress() {
    if (this.displayMode === DisplayMode.IDLE) {
      return this.enterQueueHead();
    }
    if (isFocusMode(this.displayMode)) {
      return this.completeCurrentTask();
    }
    return null;
  }

  handleLongPress() {
    if (this.displayMode === DisplayMode.IDLE) {
      return this.enterDailySummary();
    }
    if (isFocusMode(this.displayMode)) {
      return this.skipCurrentTask();
    }
    if (this.displayMode === DisplayMode.DAILY_SUMMARY) {
      return this.exitDailySummary();
    }
    return null;
  }

  enterDailySummary() {
    if (isScreensaverMode(this.displayMode) || isFocusMode(this.displayMode)) return null;
    if (this.displayMode !== DisplayMode.DAILY_SUMMARY) {
      this.dailySummarySourceMode = this.displayMode;
    }
    this.update({ displayMode: DisplayMode.DAILY_SUMMARY });
    return { type: 'hw_enter_daily_summary' };
  }

  exitDailySummary() {
    if (this.displayMode !== DisplayMode.DAILY_SUMMARY) return null;
    const displayMode = this._restorableMode(this.dailySummarySourceMode);
    this.update({ displayMode });
    return { type: 'hw_exit_daily_summary' };
  }

  // Toggle screensaver
  toggleScreensaver() {
    if (isScreensaverMode(this.displayMode)) {
      const displayMode = isScreensaverMode(this.screensaverSourceMode)
        ? DisplayMode.IDLE
        : (this.screensaverSourceMode || DisplayMode.IDLE);
      this.update({ displayMode });
      return { type: 'hw_exit_screensaver' };
    }

    this.screensaverSourceMode = this.displayMode;
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
    const screensaverVisible = isScreensaverMode(this.displayMode);
    const matchedTask = activeFocusTaskId
      ? this.taskLibrary.find(task => task.id === activeFocusTaskId)
      : null;
    const nextFocusTask = activeFocusTaskId
      ? this._normalizeTaskRecord({
          ...(matchedTask || this.focusTask || {}),
          id: activeFocusTaskId,
          title: taskTitle || matchedTask?.title || this.focusTask?.title,
        })
      : this.focusTask;
    let nextDisplayMode;
    if (screensaverVisible) {
      if (normalizedPhase === 'idle') {
        if (isFocusMode(this.screensaverSourceMode)) {
          this.screensaverSourceMode = this._restorableMode(this.focusSourceMode);
        }
      } else {
        if (!isFocusMode(this.screensaverSourceMode)) {
          this.focusSourceMode = this._restorableMode(this.screensaverSourceMode);
        }
        this.screensaverSourceMode = this.focusPhaseToDisplayMode(normalizedPhase);
      }
      nextDisplayMode = this.displayMode;
    } else {
      nextDisplayMode = normalizedPhase === 'idle'
        ? (isFocusMode(this.displayMode) ? this._restorableMode(this.focusSourceMode) : this.displayMode)
        : this.focusPhaseToDisplayMode(normalizedPhase);
    }

    if (!screensaverVisible && normalizedPhase !== 'idle' && !isFocusMode(this.displayMode)) {
      this.focusSourceMode = this._restorableMode(this.displayMode);
    }

    this.update({
      energyBottles: energyBottles ?? this.energyBottles,
      activeFocusTaskId: normalizedPhase === 'idle' ? null : (activeFocusTaskId ?? this.activeFocusTaskId),
      focusTask: nextFocusTask,
      focusPhase: normalizedPhase,
      displayMode: nextDisplayMode,
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
    if (!isScreensaverMode(this.displayMode)) {
      this.screensaverSourceMode = this.displayMode;
    }
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
      [Character.JOY]: { name: 'Joy', emoji: '\uD83E\uDD8A', color: '#c8a060' },
      [Character.SILAS]: { name: 'Silas', emoji: '\uD83E\uDDD9', color: '#6b8cae' },
      [Character.NOVA]: { name: 'Nova', emoji: '\u2604\uFE0F', color: '#8b5cf6' },
    };
    return chars[this.character] || chars[Character.JOY];
  }

  // Get scene class name
  getSceneClass() {
    return `scene-${this.scene}`;
  }

  focusSupportText() {
    if (!this.focusTask) return '';
    if (this.focusElapsedMinutes <= 5) return this.focusTask.phaseTexts.warmup;
    if (this.focusElapsedMinutes <= 15) return this.focusTask.phaseTexts.building;
    return this.focusTask.phaseTexts.deep;
  }

  _returnFromFocus(changes = {}) {
    this.update({
      ...changes,
      activeFocusTaskId: null,
      focusPhase: 'idle',
      displayMode: this._restorableMode(this.focusSourceMode),
      focusElapsedMinutes: 0,
      currentPhaseBottleProgress: 0,
    });
  }

  _normalizeTaskRecord(record = {}) {
    const phaseTexts = record.phaseTexts || record.phase_texts || {};
    return {
      ...record,
      id: this._taskId(record),
      title: record.title || 'Untitled task',
      overview: record.overview || record.detail || record.details || record.notes || '',
      phaseTexts: {
        warmup: phaseTexts.starting || phaseTexts.warmup || phaseTexts.zeroToFive || DEFAULT_PHASE_TEXTS.warmup,
        building: phaseTexts.building || phaseTexts.sixToFifteen || DEFAULT_PHASE_TEXTS.building,
        deep: phaseTexts.deep || phaseTexts.sixteenPlus || DEFAULT_PHASE_TEXTS.deep,
      },
    };
  }

  _taskId(task = {}) {
    return String(task.id || task.taskId || task.taskID || '');
  }

  _restorableMode(mode) {
    if (isFocusMode(mode) || isScreensaverMode(mode)) return DisplayMode.IDLE;
    return mode || DisplayMode.IDLE;
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
