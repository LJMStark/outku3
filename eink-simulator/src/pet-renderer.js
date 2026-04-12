// ============================================================
// Pet Renderer - Draws IP character sprites via SVG
// ============================================================

import { Character } from './state.js';

// Character visual configs
const CHARACTER_VISUALS = {
  [Character.NOOK]: {
    // Nook: fox-like creature with green bandana
    bodyColor: '#c8a060',
    accentColor: '#e8c88a',
    bandanaColor: '#3d6b2e',
    earColor: '#a07840',
    earInner: '#e8b0a0',
    eyeStyle: 'round',      // big round curious eyes
    tailType: 'bushy',
  },
  [Character.SILAS]: {
    // Silas: wise cat-like creature with cloak
    bodyColor: '#8b7d6b',
    accentColor: '#b8a890',
    bandanaColor: '#4a6080',
    earColor: '#706050',
    earInner: '#c0a898',
    eyeStyle: 'calm',       // half-lidded wise eyes
    tailType: 'smooth',
  },
  [Character.NOVA]: {
    // Nova: sleek wolf-like creature, cool tones
    bodyColor: '#6b7d8b',
    accentColor: '#90a8b8',
    bandanaColor: '#5b4080',
    earColor: '#506070',
    earInner: '#a0b0c0',
    eyeStyle: 'sharp',      // angular confident eyes
    tailType: 'pointed',
  },
};

export class PetRenderer {
  render(character, mood = 'idle') {
    const v = CHARACTER_VISUALS[character] || CHARACTER_VISUALS[Character.NOOK];
    const eyeOpen = mood === 'idle' || mood === 'postcard';
    const isDeep = mood === 'deep' || mood === 'building';

    return `
      <svg viewBox="0 0 120 150" width="120" height="150" xmlns="http://www.w3.org/2000/svg">
        <!-- Tail -->
        ${this._renderTail(v, mood)}

        <!-- Body -->
        <ellipse cx="60" cy="100" rx="35" ry="40" fill="${v.bodyColor}" />

        <!-- Belly -->
        <ellipse cx="60" cy="108" rx="22" ry="25" fill="${v.accentColor}" />

        <!-- Head -->
        <circle cx="60" cy="55" r="30" fill="${v.bodyColor}" />

        <!-- Ears -->
        <polygon points="35,35 25,8 48,30" fill="${v.earColor}" />
        <polygon points="38,33 30,14 47,30" fill="${v.earInner}" />
        <polygon points="85,35 95,8 72,30" fill="${v.earColor}" />
        <polygon points="82,33 90,14 73,30" fill="${v.earInner}" />

        <!-- Face -->
        <circle cx="60" cy="60" r="22" fill="${v.accentColor}" opacity="0.4" />

        <!-- Eyes -->
        ${this._renderEyes(v, eyeOpen, isDeep)}

        <!-- Nose -->
        <ellipse cx="60" cy="63" rx="4" ry="3" fill="#3a2a1a" />

        <!-- Mouth -->
        ${mood === 'postcard'
          ? '<path d="M 54 68 Q 60 74 66 68" stroke="#3a2a1a" stroke-width="1.5" fill="none" />'
          : '<path d="M 56 67 Q 60 70 64 67" stroke="#3a2a1a" stroke-width="1" fill="none" />'
        }

        <!-- Bandana -->
        <path d="M 38 72 Q 60 82 82 72 L 78 78 Q 60 86 42 78 Z" fill="${v.bandanaColor}" />
        <!-- Bandana knot -->
        <circle cx="75" cy="78" r="4" fill="${v.bandanaColor}" />
        <path d="M 78 76 L 88 85 M 78 80 L 85 92" stroke="${v.bandanaColor}" stroke-width="2.5" stroke-linecap="round" />

        <!-- Paws -->
        <ellipse cx="42" cy="135" rx="10" ry="6" fill="${v.bodyColor}" />
        <ellipse cx="78" cy="135" rx="10" ry="6" fill="${v.bodyColor}" />

        ${isDeep ? this._renderFocusEffect() : ''}
      </svg>
    `;
  }

  _renderEyes(v, open, isDeep) {
    if (!open || isDeep) {
      // Closed/focused eyes
      return `
        <path d="M 48 54 Q 52 52 56 54" stroke="#3a2a1a" stroke-width="2" fill="none" stroke-linecap="round" />
        <path d="M 64 54 Q 68 52 72 54" stroke="#3a2a1a" stroke-width="2" fill="none" stroke-linecap="round" />
      `;
    }

    if (v.eyeStyle === 'calm') {
      // Silas: half-lidded wise
      return `
        <ellipse cx="50" cy="54" rx="5" ry="4" fill="white" />
        <circle cx="51" cy="55" r="3" fill="#3a2a1a" />
        <path d="M 45 52 L 55 52" stroke="${v.bodyColor}" stroke-width="2" />
        <ellipse cx="70" cy="54" rx="5" ry="4" fill="white" />
        <circle cx="71" cy="55" r="3" fill="#3a2a1a" />
        <path d="M 65 52 L 75 52" stroke="${v.bodyColor}" stroke-width="2" />
      `;
    }

    if (v.eyeStyle === 'sharp') {
      // Nova: angular
      return `
        <ellipse cx="50" cy="54" rx="5" ry="5" fill="white" />
        <circle cx="51" cy="54" r="3.5" fill="#2a3a5a" />
        <circle cx="52" cy="53" r="1" fill="white" />
        <ellipse cx="70" cy="54" rx="5" ry="5" fill="white" />
        <circle cx="69" cy="54" r="3.5" fill="#2a3a5a" />
        <circle cx="70" cy="53" r="1" fill="white" />
      `;
    }

    // Nook: big round curious (default)
    return `
      <circle cx="50" cy="54" r="6" fill="white" />
      <circle cx="51" cy="55" r="4" fill="#3a2a1a" />
      <circle cx="53" cy="53" r="1.5" fill="white" />
      <circle cx="70" cy="54" r="6" fill="white" />
      <circle cx="69" cy="55" r="4" fill="#3a2a1a" />
      <circle cx="71" cy="53" r="1.5" fill="white" />
    `;
  }

  _renderTail(v, mood) {
    const sway = mood === 'postcard' ? 'transform="rotate(-10 90 120)"' : '';
    if (v.tailType === 'bushy') {
      return `
        <g ${sway}>
          <path d="M 85 110 Q 110 95 105 70 Q 100 80 95 85 Q 105 75 100 65"
                fill="${v.bodyColor}" stroke="${v.accentColor}" stroke-width="1" />
          <path d="M 100 68 Q 102 72 98 78" fill="${v.accentColor}" />
        </g>
      `;
    }
    if (v.tailType === 'pointed') {
      return `
        <g ${sway}>
          <path d="M 85 110 Q 108 90 102 60" stroke="${v.bodyColor}" stroke-width="6" fill="none" stroke-linecap="round" />
          <circle cx="102" cy="60" r="4" fill="${v.accentColor}" />
        </g>
      `;
    }
    // smooth
    return `
      <g ${sway}>
        <path d="M 85 110 Q 105 90 100 68" stroke="${v.bodyColor}" stroke-width="5" fill="none" stroke-linecap="round" />
      </g>
    `;
  }

  _renderFocusEffect() {
    return `
      <g opacity="0.3">
        <circle cx="30" cy="40" r="2" fill="#d4a843">
          <animate attributeName="opacity" values="0;1;0" dur="2s" repeatCount="indefinite" />
        </circle>
        <circle cx="90" cy="35" r="1.5" fill="#d4a843">
          <animate attributeName="opacity" values="0;1;0" dur="2.5s" repeatCount="indefinite" begin="0.5s" />
        </circle>
        <circle cx="20" cy="70" r="1" fill="#d4a843">
          <animate attributeName="opacity" values="0;1;0" dur="3s" repeatCount="indefinite" begin="1s" />
        </circle>
      </g>
    `;
  }
}
