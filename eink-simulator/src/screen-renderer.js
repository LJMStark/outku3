// ============================================================
// Screen Renderer - Renders E-ink display content
// ============================================================

import { DisplayMode } from './state.js';
import { PetRenderer } from './pet-renderer.js';
import { EinkTransition } from './eink-transition.js';

export class ScreenRenderer {
  constructor(screenEl, state) {
    this.el = screenEl;
    this.state = state;
    this.petRenderer = new PetRenderer();
    this.transition = new EinkTransition(screenEl);

    // Track previous state for change detection
    this._prevMode = null;
    this._prevScene = null;
    this._prevCharacter = null;
  }

  render() {
    const modeChanged = this._prevMode !== this.state.displayMode;
    const sceneChanged = this._prevScene !== this.state.scene;
    const characterChanged = this._prevCharacter !== this.state.character;

    const doRender = () => this._renderContent();

    // Decide transition type based on what changed
    if (modeChanged || sceneChanged || characterChanged) {
      // Major change: full e-ink refresh
      this.transition.fullRefresh(doRender);
    } else {
      // Minor update: partial refresh (dialogue, task progress)
      this.transition.partialRefresh(doRender);
    }

    this._prevMode = this.state.displayMode;
    this._prevScene = this.state.scene;
    this._prevCharacter = this.state.character;

    // Check for unlock banner
    if (this.state.lastUnlockedScene) {
      const sceneName = this.state.lastUnlockedScene;
      this.state.lastUnlockedScene = null;
      this.transition.showUnlockBanner(
        sceneName.charAt(0).toUpperCase() + sceneName.slice(1)
      );
    }
  }

  _renderContent() {
    const mode = this.state.displayMode;

    switch (mode) {
      case DisplayMode.IDLE:
        this.renderIdleScreen();
        break;
      case DisplayMode.FOCUS_WARMUP:
        this.renderFocusScreen('warmup');
        break;
      case DisplayMode.FOCUS_BUILDING:
        this.renderFocusScreen('building');
        break;
      case DisplayMode.FOCUS_DEEP:
        this.renderFocusScreen('deep');
        break;
      case DisplayMode.SCREENSAVER_NORMAL:
        this.renderScreensaver();
        break;
      case DisplayMode.SCREENSAVER_POSTCARD:
        this.renderPostcard();
        break;
      default:
        this.renderIdleScreen();
    }
  }

  // ----------------------------------------------------------
  // Status Bar (shared)
  // ----------------------------------------------------------
  _statusBarHTML() {
    const { weather, date } = this.state;
    return `
      <div class="eink-statusbar">
        <div class="weather">
          <span>${weather.icon}</span>
          <span>${weather.temp} ${weather.unit}&deg;</span>
          <span>${weather.condition}</span>
        </div>
        <div class="date">${date}</div>
      </div>
    `;
  }

  // ----------------------------------------------------------
  // Progress Bar
  // ----------------------------------------------------------
  _progressBarHTML() {
    const { completed, total, percent } = this.state.taskProgress;
    const dots = [];
    for (let i = 0; i < total; i++) {
      dots.push(`<span class="dot ${i < completed ? '' : 'empty'}"></span>`);
    }
    return `
      <div class="eink-progress">
        ${dots.join('')}
        <span>${percent}%</span>
      </div>
    `;
  }

  // ----------------------------------------------------------
  // Energy Bottles
  // ----------------------------------------------------------
  _bottlesHTML(showGlowing = false) {
    const count = this.state.energyBottles;
    if (count === 0 && !showGlowing) return '';

    const bottles = [];
    for (let i = 0; i < count; i++) {
      bottles.push(`
        <div class="energy-bottle filled">
          <div class="bottle-cap"></div>
        </div>
      `);
    }
    if (showGlowing) {
      bottles.push(`
        <div class="energy-bottle glowing">
          <div class="bottle-cap"></div>
        </div>
      `);
    }
    return `<div class="eink-bottles">${bottles.join('')}</div>`;
  }

  // ----------------------------------------------------------
  // Idle Screen
  // ----------------------------------------------------------
  renderIdleScreen() {
    const sceneClass = this.state.getSceneClass();

    this.el.innerHTML = `
      ${this._statusBarHTML()}
      <div class="eink-main">
        <div class="eink-pet-area">
          <div class="eink-scene-bg ${sceneClass}"></div>
          <div class="eink-dialogue">${this.state.petDialogue}</div>
          <div class="eink-pet-sprite">
            ${this.petRenderer.render(this.state.character, this.state.getPetRenderMood())}
          </div>
        </div>
        <div class="eink-info-area">
          ${this._progressBarHTML()}
          ${this._renderEvents()}
          ${this._renderTaskList()}
        </div>
      </div>
    `;
  }

  // ----------------------------------------------------------
  // Focus Screens (3 phases)
  // ----------------------------------------------------------
  renderFocusScreen(phase) {
    const sceneClass = this.state.getSceneClass();
    const elapsed = this.state.focusElapsedMinutes;
    const showBottles = phase === 'deep';

    this.el.innerHTML = `
      ${this._statusBarHTML()}
      <div class="focus-timer-display">Focus: ${elapsed} min</div>
      <div class="eink-main">
        <div class="eink-pet-area">
          <div class="eink-scene-bg ${sceneClass}"></div>
          <div class="eink-dialogue">${this.state.petDialogue}</div>
          <div class="eink-pet-sprite">
            ${this.petRenderer.render(this.state.character, phase)}
          </div>
          ${showBottles ? this._bottlesHTML(true) : ''}
        </div>
        <div class="eink-info-area">
          ${this._renderFocusTask()}
        </div>
      </div>
    `;
  }

  // ----------------------------------------------------------
  // Screensaver (normal - quote + scene)
  // ----------------------------------------------------------
  renderScreensaver() {
    const sceneClass = this.state.getSceneClass();
    this.el.innerHTML = `
      <div class="eink-screensaver ${sceneClass}">
        <div class="quote-text">${this.state.screensaverQuote}</div>
        <div class="quote-author">-- ${this.state.screensaverAuthor}</div>
      </div>
    `;
  }

  // ----------------------------------------------------------
  // Postcard (special streak milestones)
  // ----------------------------------------------------------
  renderPostcard() {
    const sceneClass = this.state.getSceneClass();
    const day = this.state.postcardDay;

    this.el.innerHTML = `
      <div class="eink-postcard ${sceneClass}">
        <div class="postcard-frame"></div>
        <div class="eink-pet-sprite" style="position:absolute; bottom:60px; right:40px; z-index:5;">
          ${this.petRenderer.render(this.state.character, 'postcard')}
        </div>
        <div class="postcard-label">Day ${day} - Keep going!</div>
      </div>
    `;
  }

  // ----------------------------------------------------------
  // Helper: Render events list
  // ----------------------------------------------------------
  _renderEvents() {
    return this.state.events.map(evt => `
      <div class="eink-card">
        <div class="card-time">${evt.time} ${evt.title}</div>
        <p>${evt.description}</p>
      </div>
    `).join('');
  }

  // ----------------------------------------------------------
  // Helper: Render task list
  // ----------------------------------------------------------
  _renderTaskList() {
    const items = this.state.tasks.map(t =>
      `<li class="${t.completed ? 'completed' : ''}">${t.title}</li>`
    ).join('');

    return `
      <div class="eink-card">
        <h3>Task List</h3>
        <ul class="eink-task-list">${items}</ul>
      </div>
    `;
  }

  // ----------------------------------------------------------
  // Helper: Render focus task card
  // ----------------------------------------------------------
  _renderFocusTask() {
    const ft = this.state.focusTask;
    return `
      <div class="eink-card">
        <h3>${ft.title}</h3>
        <p>Overview: ${ft.overview}</p>
        <div class="card-tips">*Tips: ${ft.tips}</div>
      </div>
    `;
  }
}
