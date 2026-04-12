// ============================================================
// Hardware Controls - Simulates E-ink device buttons
// ============================================================

export class HardwareControls {
  constructor(state) {
    this.state = state;
    this._longPressTimer = null;
    this._isLongPress = false;
    this._wsBridge = null;

    this._bindButtons();
  }

  setWebSocketBridge(bridge) {
    this._wsBridge = bridge;
  }

  _bindButtons() {
    const btnClick = document.getElementById('btn-scroll-click');
    const btnPower = document.getElementById('btn-power');
    const btnUp = document.getElementById('btn-scroll-up');
    const btnDown = document.getElementById('btn-scroll-down');

    // Scroll click: short = complete task, long = skip task
    btnClick.addEventListener('mousedown', () => {
      this._isLongPress = false;
      this._longPressTimer = setTimeout(() => {
        this._isLongPress = true;
        const msg = this.state.skipCurrentTask();
        this._sendToApp(msg);
      }, 800);
    });

    btnClick.addEventListener('mouseup', () => {
      clearTimeout(this._longPressTimer);
      if (!this._isLongPress) {
        const msg = this.state.completeCurrentTask();
        this._sendToApp(msg);
      }
    });

    btnClick.addEventListener('mouseleave', () => {
      clearTimeout(this._longPressTimer);
    });

    // Power button: toggle screensaver
    btnPower.addEventListener('click', () => {
      const msg = this.state.toggleScreensaver();
      this._sendToApp(msg);
    });

    // Scroll up/down: cycle through tasks/events
    btnUp.addEventListener('click', () => {
      // Scroll up in task list (visual feedback only)
      this.state._notify();
    });

    btnDown.addEventListener('click', () => {
      // Scroll down in task list (visual feedback only)
      this.state._notify();
    });
  }

  _sendToApp(message) {
    if (this._wsBridge && message) {
      this._wsBridge.send(message);
    }
  }
}
