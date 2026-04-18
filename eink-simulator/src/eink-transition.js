// ============================================================
// E-ink Transition - Screen refresh animations
// ============================================================

export class EinkTransition {
  constructor(screenEl) {
    this.el = screenEl;
    this._locked = false;
    this._queue = [];
  }

  // Full refresh: flash black -> flash white -> render new content
  // Mimics real e-ink full page refresh (~350ms)
  async fullRefresh(renderFn) {
    if (this._locked) {
      // Queue this render but drop intermediate frames
      this._queue = [renderFn];
      return;
    }

    this._locked = true;

    try {
      // Phase 1: Flash black (150ms)
      this.el.classList.add('eink-flash-black');
      await this._wait(150);

      // Phase 2: Flash white + render new content underneath (100ms)
      this.el.classList.remove('eink-flash-black');
      this.el.classList.add('eink-flash-white');
      renderFn();
      await this._wait(100);

      // Phase 3: Reveal new content
      this.el.classList.remove('eink-flash-white');
      await this._wait(50);
    } finally {
      this._locked = false;

      // Process queued render if any
      if (this._queue.length > 0) {
        const next = this._queue.pop();
        this._queue = [];
        await this.fullRefresh(next);
      }
    }
  }

  // Partial refresh: quick fade for minor content updates (~200ms)
  async partialRefresh(renderFn) {
    if (this._locked) {
      renderFn();
      return;
    }

    this._locked = true;

    try {
      // Slight ghost effect then render
      this.el.classList.add('eink-partial-ghost');
      await this._wait(80);
      renderFn();
      await this._wait(80);
      this.el.classList.remove('eink-partial-ghost');
      await this._wait(40);
    } finally {
      this._locked = false;
    }
  }

  // Show unlock banner overlay
  async showUnlockBanner(sceneName) {
    const banner = document.createElement('div');
    banner.className = 'unlock-banner';
    banner.innerHTML = `
      <div class="unlock-banner-icon">&#9733;</div>
      <div class="unlock-banner-text">${sceneName} Unlocked</div>
    `;

    this.el.appendChild(banner);

    // Trigger entrance animation
    await this._wait(50);
    banner.classList.add('visible');

    // Hold for 2 seconds then fade out
    await this._wait(2000);
    banner.classList.add('fade-out');

    await this._wait(500);
    banner.remove();
  }

  // Animate bottles incrementing one by one
  async animateBottles(fromCount, toCount, updateFn) {
    for (let i = fromCount + 1; i <= toCount; i++) {
      await this._wait(400);
      updateFn(i);

      // Find the latest bottle element and animate it
      const bottles = this.el.querySelectorAll('.energy-bottle');
      const lastBottle = bottles[bottles.length - 1];
      if (lastBottle) {
        lastBottle.classList.add('bottle-fly-in');
      }
    }
  }

  _wait(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
