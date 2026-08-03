// ============================================================
// Hardware Controls - Simulates E-ink device buttons
// ============================================================

export class HardwareControls {
  constructor(
    state,
    {
      scheduleRepeating = (callback, milliseconds) => setInterval(callback, milliseconds),
      cancelRepeating = timer => clearInterval(timer),
    } = {}
  ) {
    this.state = state;
    this._longPressTimer = null;
    this._isLongPress = false;
    this._wsBridge = null;
    this._cancelRepeating = cancelRepeating;

    this._bindButtons();
    this._focusClockTimer = scheduleRepeating(() => {
      this.state.refreshFocusFromClock();
    }, 1_000);
  }

  setWebSocketBridge(bridge) {
    this._wsBridge = bridge;
  }

  dispose() {
    if (this._focusClockTimer !== null) {
      this._cancelRepeating(this._focusClockTimer);
      this._focusClockTimer = null;
    }
  }

  _bindButtons() {
    const btnClick = document.getElementById('btn-action');
    const btnPower = document.getElementById('btn-power');

    // The device has one action button. Its result depends on the current page.
    btnClick.addEventListener('pointerdown', () => {
      this._isLongPress = false;
      this._longPressTimer = setTimeout(() => {
        this._isLongPress = true;
        const msg = this.state.handleLongPress();
        this._sendToApp(msg);
      }, 800);
    });

    btnClick.addEventListener('pointerup', () => {
      clearTimeout(this._longPressTimer);
      if (!this._isLongPress) {
        const msg = this.state.handleShortPress();
        this._sendToApp(msg);
      }
    });

    const cancelPress = () => {
      clearTimeout(this._longPressTimer);
      this._longPressTimer = null;
    };
    btnClick.addEventListener('pointercancel', cancelPress);
    btnClick.addEventListener('pointerleave', cancelPress);

    // Power button: toggle screensaver
    btnPower.addEventListener('click', () => {
      const msg = this.state.toggleScreensaver();
      this._sendToApp(msg);
    });

  }

  _sendToApp(message) {
    if (this._wsBridge && message) {
      this._wsBridge.send(message);
    }
  }
}
