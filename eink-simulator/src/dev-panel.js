// ============================================================
// Dev Panel - Developer controls for testing display modes
// ============================================================

import { DisplayMode, Scene, Character } from './state.js';

export class DevPanel {
  constructor(state) {
    this.state = state;
    this._bindModeButtons();
    this._bindSceneButtons();
    this._bindCharButtons();
    this._bindFocusSlider();
    this._bindBottleButtons();
  }

  _bindModeButtons() {
    const buttons = document.querySelectorAll('[data-mode]');
    buttons.forEach(btn => {
      btn.addEventListener('click', () => {
        buttons.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        this.state.setDisplayMode(btn.dataset.mode);
      });
    });
  }

  _bindSceneButtons() {
    const buttons = document.querySelectorAll('.scene-btn');
    buttons.forEach(btn => {
      btn.addEventListener('click', () => {
        buttons.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        this.state.setScene(btn.dataset.scene);
      });
    });
  }

  _bindCharButtons() {
    const buttons = document.querySelectorAll('.char-btn');
    buttons.forEach(btn => {
      btn.addEventListener('click', () => {
        buttons.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        this.state.setCharacter(btn.dataset.char);
      });
    });
  }

  _bindFocusSlider() {
    const slider = document.getElementById('focus-slider');
    const label = document.getElementById('focus-time-label');

    slider.addEventListener('input', () => {
      const minutes = parseInt(slider.value, 10);
      label.textContent = `${minutes} min`;
      this.state.setFocusMinutes(minutes);

      // Update mode button active state
      const modeButtons = document.querySelectorAll('[data-mode]');
      modeButtons.forEach(b => b.classList.remove('active'));
      const currentMode = this.state.displayMode;
      const activeBtn = document.querySelector(`[data-mode="${currentMode}"]`);
      if (activeBtn) activeBtn.classList.add('active');
    });
  }

  _bindBottleButtons() {
    const addBtn = document.getElementById('btn-add-bottle');
    const resetBtn = document.getElementById('btn-reset-bottles');
    const countLabel = document.getElementById('bottle-count');

    addBtn.addEventListener('click', () => {
      this.state.addBottle();
      countLabel.textContent = this.state.energyBottles;
    });

    resetBtn.addEventListener('click', () => {
      this.state.resetBottles();
      countLabel.textContent = '0';
    });
  }
}
